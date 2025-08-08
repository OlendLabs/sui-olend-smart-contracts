/// Oracle module for price feed management using Pyth Network
/// Provides real-time price feeds for DeFi lending platform
module olend::oracle;

use sui::object::{ID, UID};
use sui::transfer;
use sui::tx_context::TxContext;
use sui::table::{Self, Table};
use std::type_name::{Self, TypeName};
use sui::clock::{Self, Clock};
use sui::event;

// Pyth Network integration
use pyth::pyth;
use pyth::price_info::{Self, PriceInfo, PriceInfoObject};
use pyth::price::{Self, Price};
use pyth::state::{State as PythState};
use pyth::price_identifier::PriceIdentifier;
use pyth::i64::{Self, I64};

use olend::constants;
use olend::errors;
use olend::utils;

// ===== Structs =====

/// Global oracle registry for managing price feeds
public struct OracleRegistry has key {
    id: UID,
    version: u64,
    /// Mapping of asset types to their price feed information
    price_feeds: Table<TypeName, PriceFeedInfo>,
    /// Oracle admin capability ID
    admin_cap_id: ID,
    /// Pyth state object for price updates
    pyth_state: ID,
    /// Oracle configuration parameters
    config: OracleConfig,
}

/// Information about a specific price feed
public struct PriceFeedInfo has store, copy, drop {
    /// Pyth price identifier for this asset
    price_id: PriceIdentifier,
    /// Decimal places for the price (e.g., 8 for USD prices)
    decimals: u8,
    /// Whether this price feed is active
    is_active: bool,
    /// Minimum confidence threshold (basis points, e.g., 100 = 1%)
    min_confidence_bps: u64,
    /// Maximum acceptable price age in seconds
    max_price_age_seconds: u64,
    /// Last update timestamp
    last_update_time: u64,
    /// Asset symbol for identification
    asset_symbol: vector<u8>,
}

/// Cached price data with validation
public struct PriceData has copy, drop {
    /// Price value with appropriate decimals
    price: u64,
    /// Price confidence interval
    confidence: u64,
    /// Timestamp of price publication
    publish_time: u64,
    /// Whether the price is considered valid
    is_valid: bool,
    /// Asset type this price represents
    asset_type: TypeName,
}

/// Oracle configuration parameters
public struct OracleConfig has store, copy, drop {
    /// Global circuit breaker - emergency pause all oracle operations
    emergency_pause: bool,
    /// Default maximum price age for all feeds (seconds)
    default_max_price_age: u64,
    /// Default minimum confidence threshold (basis points)
    default_min_confidence_bps: u64,
    /// Maximum number of price feeds
    max_price_feeds: u64,
}

/// Oracle admin capability for managing price feeds
public struct OracleAdminCap has key, store {
    id: UID,
    /// Registry ID this capability manages
    registry_id: ID,
}

// ===== Events =====

/// Event emitted when a new price feed is registered
public struct PriceFeedRegistered has copy, drop {
    asset_type: TypeName,
    price_id: PriceIdentifier,
    asset_symbol: vector<u8>,
}

/// Event emitted when a price is updated
public struct PriceUpdated has copy, drop {
    asset_type: TypeName,
    price: u64,
    confidence: u64,
    publish_time: u64,
}

/// Event emitted when oracle is paused/unpaused
public struct OracleStatusChanged has copy, drop {
    emergency_pause: bool,
    timestamp: u64,
}

// ===== Constants =====

/// Maximum price age in seconds (30 minutes)
const MAX_PRICE_AGE_SECONDS: u64 = 1800;

/// Minimum confidence threshold in basis points (1% = 100 bps)
const MIN_CONFIDENCE_THRESHOLD_BPS: u64 = 100;

/// Maximum number of supported price feeds
const MAX_PRICE_FEEDS: u64 = 100;

/// Basis points denominator (10000 = 100%)
const BASIS_POINTS_DENOMINATOR: u64 = 10000;

// ===== Error Constants =====

/// Oracle error code range: 3000-3999
const ORACLE_ERROR_RANGE_START: u64 = 3000;

/// Oracle is paused
const EOracle_Paused: u64 = 3001;

/// Price feed not found
const EPrice_Feed_Not_Found: u64 = 3002;

/// Price data is stale
const EPrice_Stale: u64 = 3003;

/// Price confidence too low
const EPrice_Confidence_Too_Low: u64 = 3004;

/// Invalid price identifier
const EInvalid_Price_Id: u64 = 3005;

/// Price feed already exists
const EPrice_Feed_Already_Exists: u64 = 3006;

/// Maximum price feeds exceeded
const EMax_Price_Feeds_Exceeded: u64 = 3007;

/// Invalid oracle configuration
const EInvalid_Oracle_Config: u64 = 3008;

/// Price data validation failed
const EPrice_Validation_Failed: u64 = 3009;

/// Pyth state mismatch
const EPyth_State_Mismatch: u64 = 3010;

// ===== Initialization =====

/// Initialize the oracle registry - called during module deployment
fun init(ctx: &mut TxContext) {
    let registry_uid = object::new(ctx);
    let admin_cap_uid = object::new(ctx);
    let registry_id = object::uid_to_inner(&registry_uid);
    
    let admin_cap = OracleAdminCap {
        id: admin_cap_uid,
        registry_id,
    };
    
    let config = OracleConfig {
        emergency_pause: false,
        default_max_price_age: MAX_PRICE_AGE_SECONDS,
        default_min_confidence_bps: MIN_CONFIDENCE_THRESHOLD_BPS,
        max_price_feeds: MAX_PRICE_FEEDS,
    };
    
    let registry = OracleRegistry {
        id: registry_uid,
        version: constants::current_version(),
        price_feeds: table::new(ctx),
        admin_cap_id: object::id(&admin_cap),
        pyth_state: object::id_from_address(@0x0), // Will be set when Pyth state is provided
        config,
    };
    
    transfer::transfer(admin_cap, tx_context::sender(ctx));
    transfer::share_object(registry);
}

// ===== Admin Functions =====

/// Set the Pyth state object for oracle operations
public fun set_pyth_state(
    registry: &mut OracleRegistry,
    admin_cap: &OracleAdminCap,
    pyth_state: &PythState,
    ctx: &mut TxContext
) {
    verify_admin_capability(registry, admin_cap);
    verify_version(registry);
    
    registry.pyth_state = object::id(pyth_state);
    
    event::emit(OracleStatusChanged {
        emergency_pause: registry.config.emergency_pause,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });
}

/// Register a new price feed for an asset type
public fun register_price_feed<T>(
    registry: &mut OracleRegistry,
    admin_cap: &OracleAdminCap,
    price_id: PriceIdentifier,
    decimals: u8,
    min_confidence_bps: u64,
    max_price_age_seconds: u64,
    asset_symbol: vector<u8>,
    ctx: &mut TxContext
) {
    verify_admin_capability(registry, admin_cap);
    verify_version(registry);
    assert!(!registry.config.emergency_pause, EOracle_Paused);
    
    let asset_type = type_name::get<T>();
    
    // Check if price feed already exists
    assert!(!table::contains(&registry.price_feeds, asset_type), EPrice_Feed_Already_Exists);
    
    // Check maximum price feeds limit
    assert!(table::length(&registry.price_feeds) < registry.config.max_price_feeds, EMax_Price_Feeds_Exceeded);
    
    // Validate configuration parameters
    assert!(min_confidence_bps <= BASIS_POINTS_DENOMINATOR, EInvalid_Oracle_Config);
    assert!(max_price_age_seconds > 0, EInvalid_Oracle_Config);
    
    let feed_info = PriceFeedInfo {
        price_id,
        decimals,
        is_active: true,
        min_confidence_bps,
        max_price_age_seconds,
        last_update_time: 0,
        asset_symbol,
    };
    
    table::add(&mut registry.price_feeds, asset_type, feed_info);
    
    event::emit(PriceFeedRegistered {
        asset_type,
        price_id,
        asset_symbol,
    });
}

/// Update price feed configuration
public fun update_price_feed<T>(
    registry: &mut OracleRegistry,
    admin_cap: &OracleAdminCap,
    is_active: bool,
    min_confidence_bps: u64,
    max_price_age_seconds: u64,
) {
    verify_admin_capability(registry, admin_cap);
    verify_version(registry);
    
    let asset_type = type_name::get<T>();
    assert!(table::contains(&registry.price_feeds, asset_type), EPrice_Feed_Not_Found);
    
    let feed_info = table::borrow_mut(&mut registry.price_feeds, asset_type);
    feed_info.is_active = is_active;
    feed_info.min_confidence_bps = min_confidence_bps;
    feed_info.max_price_age_seconds = max_price_age_seconds;
}

/// Emergency pause/unpause all oracle operations
public fun set_emergency_pause(
    registry: &mut OracleRegistry,
    admin_cap: &OracleAdminCap,
    emergency_pause: bool,
    ctx: &mut TxContext
) {
    verify_admin_capability(registry, admin_cap);
    verify_version(registry);
    
    registry.config.emergency_pause = emergency_pause;
    
    event::emit(OracleStatusChanged {
        emergency_pause,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });
}

// ===== Price Query Functions =====

/// Get current price data for an asset type
public fun get_price<T>(
    registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
): PriceData {
    assert!(!registry.config.emergency_pause, EOracle_Paused);
    
    let asset_type = type_name::get<T>();
    assert!(table::contains(&registry.price_feeds, asset_type), EPrice_Feed_Not_Found);
    
    let feed_info = table::borrow(&registry.price_feeds, asset_type);
    assert!(feed_info.is_active, EPrice_Feed_Not_Found);
    
    // Get price with age validation using the same pattern as reference code
    let price_struct = pyth::get_price_no_older_than(price_info_object, clock, feed_info.max_price_age_seconds);
    
    // Extract price and confidence using proper I64 handling
    let price_i64 = price::get_price(&price_struct);
    let price_value = i64::get_magnitude_if_positive(&price_i64);  // Use proper I64 to u64 conversion
    let confidence_value = price::get_conf(&price_struct);
    let publish_time = price::get_timestamp(&price_struct);
    
    // Validate confidence
    let confidence_ratio = (confidence_value * BASIS_POINTS_DENOMINATOR) / price_value;
    assert!(confidence_ratio <= feed_info.min_confidence_bps, EPrice_Confidence_Too_Low);
    
    PriceData {
        price: price_value,
        confidence: confidence_value,
        publish_time,
        is_valid: true,
        asset_type,
    }
}

/// Get price with custom validation parameters
public fun get_price_with_validation<T>(
    registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    max_age_seconds: u64,
    min_confidence_bps: u64,
): PriceData {
    assert!(!registry.config.emergency_pause, EOracle_Paused);
    
    let asset_type = type_name::get<T>();
    assert!(table::contains(&registry.price_feeds, asset_type), EPrice_Feed_Not_Found);
    
    let feed_info = table::borrow(&registry.price_feeds, asset_type);
    assert!(feed_info.is_active, EPrice_Feed_Not_Found);
    
    // Get price with custom age validation
    let price_struct = pyth::get_price_no_older_than(price_info_object, clock, max_age_seconds);
    
    // Extract price data using proper I64 handling
    let price_value = i64::get_magnitude_if_positive(&price::get_price(&price_struct));
    let confidence_value = price::get_conf(&price_struct);
    let publish_time = price::get_timestamp(&price_struct);
    
    let confidence_ratio = (confidence_value * BASIS_POINTS_DENOMINATOR) / price_value;
    assert!(confidence_ratio <= min_confidence_bps, EPrice_Confidence_Too_Low);
    
    PriceData {
        price: price_value,
        confidence: confidence_value,
        publish_time,
        is_valid: true,
        asset_type,
    }
}

/// Calculate USD value of an asset amount using oracle price
public fun calculate_usd_value<T>(
    registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    asset_amount: u64,
    asset_decimals: u8,
): u64 {
    let price_data = get_price<T>(registry, price_info_object, clock);
    let feed_info = table::borrow(&registry.price_feeds, type_name::get<T>());
    
    // Normalize asset amount to price decimals
    let normalized_amount = if (asset_decimals >= feed_info.decimals) {
        asset_amount / utils::pow(10, asset_decimals - feed_info.decimals)
    } else {
        asset_amount * utils::pow(10, feed_info.decimals - asset_decimals)
    };
    
    (normalized_amount * price_data.price) / utils::pow(10, feed_info.decimals)
}

// ===== View Functions =====

/// Check if a price feed exists for an asset type
public fun has_price_feed<T>(registry: &OracleRegistry): bool {
    let asset_type = type_name::get<T>();
    table::contains(&registry.price_feeds, asset_type)
}

/// Get price feed information for an asset type
public fun get_price_feed_info<T>(registry: &OracleRegistry): PriceFeedInfo {
    let asset_type = type_name::get<T>();
    assert!(table::contains(&registry.price_feeds, asset_type), EPrice_Feed_Not_Found);
    *table::borrow(&registry.price_feeds, asset_type)
}

/// Get oracle configuration
public fun get_oracle_config(registry: &OracleRegistry): OracleConfig {
    registry.config
}

/// Check if oracle is paused
public fun is_oracle_paused(registry: &OracleRegistry): bool {
    registry.config.emergency_pause
}

/// Get the number of registered price feeds
public fun get_price_feed_count(registry: &OracleRegistry): u64 {
    table::length(&registry.price_feeds)
}

/// Check if a price feed exists for a specific asset type by TypeName
public fun has_price_feed_by_type(registry: &OracleRegistry, asset_type: TypeName): bool {
    table::contains(&registry.price_feeds, asset_type)
}

/// Calculate USD value of an asset amount using oracle price by TypeName
public fun calculate_usd_value_by_type(
    registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    asset_type: TypeName,
    asset_amount: u64,
    asset_decimals: u8,
): u64 {
    assert!(!registry.config.emergency_pause, EOracle_Paused);
    assert!(table::contains(&registry.price_feeds, asset_type), EPrice_Feed_Not_Found);
    
    let feed_info = table::borrow(&registry.price_feeds, asset_type);
    assert!(feed_info.is_active, EPrice_Feed_Not_Found);
    
    // Get price with age validation
    let price_struct = pyth::get_price_no_older_than(price_info_object, clock, feed_info.max_price_age_seconds);
    
    // Extract price data using proper I64 handling
    let price_value = i64::get_magnitude_if_positive(&price::get_price(&price_struct));
    let confidence_value = price::get_conf(&price_struct);
    
    let confidence_ratio = (confidence_value * BASIS_POINTS_DENOMINATOR) / price_value;
    assert!(confidence_ratio <= feed_info.min_confidence_bps, EPrice_Confidence_Too_Low);
    
    // Normalize asset amount to price decimals
    let normalized_amount = if (asset_decimals >= feed_info.decimals) {
        asset_amount / utils::pow(10, asset_decimals - feed_info.decimals)
    } else {
        asset_amount * utils::pow(10, feed_info.decimals - asset_decimals)
    };
    
    (normalized_amount * price_value) / utils::pow(10, feed_info.decimals)
}

// ===== Helper Functions =====

/// Verify admin capability matches the registry
fun verify_admin_capability(registry: &OracleRegistry, admin_cap: &OracleAdminCap) {
    assert!(admin_cap.registry_id == object::id(registry), errors::unauthorized_access());
}

/// Verify registry version compatibility
fun verify_version(registry: &OracleRegistry) {
    utils::verify_version(registry.version);
}

/// Create invalid price data for error cases
public fun create_invalid_price_data<T>(): PriceData {
    PriceData {
        price: 0,
        confidence: 0,
        publish_time: 0,
        is_valid: false,
        asset_type: type_name::get<T>(),
    }
}

/// Validate price data structure
public fun validate_price_data(price_data: &PriceData): bool {
    price_data.is_valid && price_data.price > 0
}

// ===== Price Data Accessors =====

/// Get price from PriceData
public fun price_data_price(price_data: &PriceData): u64 {
    price_data.price
}

/// Get confidence from PriceData
public fun price_data_confidence(price_data: &PriceData): u64 {
    price_data.confidence
}

/// Get publish time from PriceData
public fun price_data_publish_time(price_data: &PriceData): u64 {
    price_data.publish_time
}

/// Check if price data is valid
public fun price_data_is_valid(price_data: &PriceData): bool {
    price_data.is_valid
}

/// Get asset type from PriceData
public fun price_data_asset_type(price_data: &PriceData): TypeName {
    price_data.asset_type
}

// ===== Test Helper Functions =====

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun create_test_price_data<T>(
    price: u64,
    confidence: u64,
    publish_time: u64,
): PriceData {
    PriceData {
        price,
        confidence,
        publish_time,
        is_valid: true,
        asset_type: type_name::get<T>(),
    }
}

#[test_only]
public fun create_test_oracle_registry(ctx: &mut TxContext): (OracleRegistry, OracleAdminCap) {
    let registry_uid = object::new(ctx);
    let admin_cap_uid = object::new(ctx);
    let registry_id = object::uid_to_inner(&registry_uid);
    
    let admin_cap = OracleAdminCap {
        id: admin_cap_uid,
        registry_id,
    };
    
    let config = OracleConfig {
        emergency_pause: false,
        default_max_price_age: MAX_PRICE_AGE_SECONDS,
        default_min_confidence_bps: MIN_CONFIDENCE_THRESHOLD_BPS,
        max_price_feeds: MAX_PRICE_FEEDS,
    };
    
    let registry = OracleRegistry {
        id: registry_uid,
        version: constants::current_version(),
        price_feeds: table::new(ctx),
        admin_cap_id: object::id(&admin_cap),
        pyth_state: object::id_from_address(@0x0),
        config,
    };
    
    (registry, admin_cap)
}