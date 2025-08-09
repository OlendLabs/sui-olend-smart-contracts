/// Price Oracle Module - Pyth Network Integration
/// Provides real-time price data for assets using Pyth Network oracle
module olend::oracle;

use std::type_name::{Self, TypeName};
use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::event;

use olend::constants;
use olend::errors;
use olend::utils;

// ===== Struct Definitions =====

/// Global price oracle - Shared Object for price data management
public struct PriceOracle has key {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Pyth price feed ID mappings for each asset type
    price_feeds: Table<TypeName, vector<u8>>,
    /// Cached price information for efficiency
    price_cache: Table<TypeName, PriceInfo>,
    /// Maximum acceptable price data delay in seconds (default: 300 = 5 minutes)
    max_price_delay: u64,
    /// Minimum confidence requirement (default: 95%)
    min_confidence: u64,
    /// Oracle configuration parameters
    config: OracleConfig,
}

/// Price information structure
public struct PriceInfo has store, copy, drop {
    /// Price in USD with 8 decimal precision (e.g., 50000_00000000 = $50,000)
    price: u64,
    /// Confidence interval (same precision as price)
    confidence: u64,
    /// Price publication timestamp
    timestamp: u64,
    /// Price exponent (for handling different decimal places, stored as u8 with sign bit)
    expo: u8,
    /// Whether this price data is valid
    is_valid: bool,
}

/// Oracle configuration parameters
public struct OracleConfig has store, copy, drop {
    /// Enable/disable price caching
    enable_cache: bool,
    /// Cache expiration time in seconds
    cache_expiry: u64,
    /// Enable/disable price validation
    enable_validation: bool,
    /// Maximum price change percentage per update (to detect manipulation)
    max_price_change_pct: u64,
    /// Emergency mode flag
    emergency_mode: bool,
}

/// Oracle admin capability for management operations
public struct OracleAdminCap has key, store {
    id: UID,
}

/// Price update event
public struct PriceUpdateEvent has copy, drop {
    asset_type: TypeName,
    old_price: u64,
    new_price: u64,
    timestamp: u64,
    confidence: u64,
}

/// Price validation error event
public struct PriceValidationErrorEvent has copy, drop {
    asset_type: TypeName,
    error_type: u8, // 1: stale, 2: low confidence, 3: manipulation detected
    timestamp: u64,
    details: vector<u8>,
}

// ===== Error Constants =====

/// Price feed not configured for asset type
const EPriceFeedNotFound: u64 = 2050;

/// Price data is stale (too old)
const EPriceDataStale: u64 = 2051;

/// Price confidence too low
const EPriceConfidenceTooLow: u64 = 2052;

/// Price manipulation detected
const EPriceManipulationDetected: u64 = 2053;

/// Invalid price feed ID
const EInvalidPriceFeedId: u64 = 2054;

/// Oracle in emergency mode
const EOracleEmergencyMode: u64 = 2055;

/// Price validation failed
const EPriceValidationFailed: u64 = 2056;

/// Unauthorized oracle access
const EUnauthorizedOracleAccess: u64 = 2057;

/// Invalid oracle configuration
const EInvalidOracleConfig: u64 = 2058;

/// Price cache miss
const EPriceCacheMiss: u64 = 2059;

// ===== Public Functions =====

/// Initialize the price oracle system
/// Creates a shared PriceOracle object and returns admin capability
public fun initialize_oracle(ctx: &mut TxContext): OracleAdminCap {
    let oracle = PriceOracle {
        id: object::new(ctx),
        version: constants::current_version(),
        price_feeds: table::new(ctx),
        price_cache: table::new(ctx),
        max_price_delay: 300, // 5 minutes default
        min_confidence: 95,   // 95% confidence default
        config: OracleConfig {
            enable_cache: true,
            cache_expiry: 60, // 1 minute cache
            enable_validation: true,
            max_price_change_pct: 1000, // 10% max change
            emergency_mode: false,
        },
    };

    transfer::share_object(oracle);

    OracleAdminCap {
        id: object::new(ctx),
    }
}

/// Configure price feed for an asset type
/// Only callable by admin
public fun configure_price_feed<T>(
    oracle: &mut PriceOracle,
    _admin_cap: &OracleAdminCap,
    price_feed_id: vector<u8>,
    _ctx: &TxContext
) {
    // Version check
    assert!(
        utils::is_version_compatible(oracle.version, constants::current_version()),
        errors::version_mismatch()
    );

    // Validate price feed ID
    assert!(!vector::is_empty(&price_feed_id), EInvalidPriceFeedId);

    let asset_type = type_name::get<T>();
    
    // Add or update price feed mapping
    if (table::contains(&oracle.price_feeds, asset_type)) {
        let existing_feed = table::borrow_mut(&mut oracle.price_feeds, asset_type);
        *existing_feed = price_feed_id;
    } else {
        table::add(&mut oracle.price_feeds, asset_type, price_feed_id);
    };
}

/// Get current price for an asset type
/// Returns cached price if available and valid, otherwise fetches from Pyth
public fun get_price<T>(
    oracle: &PriceOracle,
    clock: &Clock,
): PriceInfo {
    // Version check
    assert!(
        utils::is_version_compatible(oracle.version, constants::current_version()),
        errors::version_mismatch()
    );

    // Check emergency mode
    assert!(!oracle.config.emergency_mode, EOracleEmergencyMode);

    let asset_type = type_name::get<T>();
    
    // Check if price feed is configured
    assert!(table::contains(&oracle.price_feeds, asset_type), EPriceFeedNotFound);

    // Try to get cached price first
    if (oracle.config.enable_cache && table::contains(&oracle.price_cache, asset_type)) {
        let cached_price = *table::borrow(&oracle.price_cache, asset_type);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Check if cached price is still valid
        if (cached_price.is_valid && 
            current_time - cached_price.timestamp <= oracle.config.cache_expiry) {
            return cached_price
        };
    };

    // If no valid cached price, we would fetch from Pyth here
    // For now, return a placeholder that indicates we need Pyth integration
    PriceInfo {
        price: 0,
        confidence: 0,
        timestamp: clock::timestamp_ms(clock) / 1000,
        expo: 8, // 8 decimal places (stored as positive, interpreted as negative)
        is_valid: false,
    }
}

/// Update price in cache (internal function for Pyth integration)
/// This will be called by the Pyth integration functions
public(package) fun update_price_cache<T>(
    oracle: &mut PriceOracle,
    price_info: PriceInfo,
    clock: &Clock,
    _ctx: &TxContext
) {
    let asset_type = type_name::get<T>();
    let current_time = clock::timestamp_ms(clock) / 1000;

    // Validate price data
    if (oracle.config.enable_validation) {
        validate_price_data(oracle, &price_info, current_time);
    };

    // Check for price manipulation
    if (table::contains(&oracle.price_cache, asset_type)) {
        let old_price = table::borrow(&oracle.price_cache, asset_type);
        if (old_price.is_valid) {
            check_price_manipulation(oracle, old_price.price, price_info.price, asset_type);
        };
    };

    // Update cache
    if (table::contains(&oracle.price_cache, asset_type)) {
        let cached_price = table::borrow_mut(&mut oracle.price_cache, asset_type);
        *cached_price = price_info;
    } else {
        table::add(&mut oracle.price_cache, asset_type, price_info);
    };

    // Emit price update event
    event::emit(PriceUpdateEvent {
        asset_type,
        old_price: if (table::contains(&oracle.price_cache, asset_type)) {
            table::borrow(&oracle.price_cache, asset_type).price
        } else { 0 },
        new_price: price_info.price,
        timestamp: current_time,
        confidence: price_info.confidence,
    });
}

/// Convert asset amount to USD value using current price
public fun convert_to_usd<T>(
    oracle: &PriceOracle,
    amount: u64,
    decimals: u8,
    clock: &Clock,
): u64 {
    let price_info = get_price<T>(oracle, clock);
    assert!(price_info.is_valid, EPriceValidationFailed);

    // Calculate USD value with proper decimal handling
    // Formula: (amount * price) / (10^asset_decimals * 10^price_decimals)
    let price_decimals = price_info.expo; // Assuming expo represents decimal places

    // Avoid overflow by using smaller numbers for calculation
    let asset_divisor = pow(10, decimals);
    let price_divisor = pow(10, price_decimals);
    
    if (asset_divisor == 0 || price_divisor == 0) {
        0
    } else {
        // First divide amount by asset decimals, then multiply by price, then divide by price decimals
        let normalized_amount = amount / asset_divisor;
        (normalized_amount * price_info.price) / price_divisor
    }
}

/// Get price feed ID for an asset type
public fun get_price_feed_id<T>(oracle: &PriceOracle): vector<u8> {
    let asset_type = type_name::get<T>();
    assert!(table::contains(&oracle.price_feeds, asset_type), EPriceFeedNotFound);
    *table::borrow(&oracle.price_feeds, asset_type)
}

/// Check if price feed is configured for asset type
public fun has_price_feed<T>(oracle: &PriceOracle): bool {
    let asset_type = type_name::get<T>();
    table::contains(&oracle.price_feeds, asset_type)
}

/// Get oracle configuration
public fun get_oracle_config(oracle: &PriceOracle): OracleConfig {
    oracle.config
}

// ===== Admin Functions =====

/// Update oracle configuration
public fun update_oracle_config(
    oracle: &mut PriceOracle,
    _admin_cap: &OracleAdminCap,
    new_config: OracleConfig,
) {
    assert!(
        utils::is_version_compatible(oracle.version, constants::current_version()),
        errors::version_mismatch()
    );

    oracle.config = new_config;
}

/// Set maximum price delay
public fun set_max_price_delay(
    oracle: &mut PriceOracle,
    _admin_cap: &OracleAdminCap,
    delay_seconds: u64,
) {
    assert!(
        utils::is_version_compatible(oracle.version, constants::current_version()),
        errors::version_mismatch()
    );

    oracle.max_price_delay = delay_seconds;
}

/// Set minimum confidence requirement
public fun set_min_confidence(
    oracle: &mut PriceOracle,
    _admin_cap: &OracleAdminCap,
    confidence: u64,
) {
    assert!(
        utils::is_version_compatible(oracle.version, constants::current_version()),
        errors::version_mismatch()
    );

    assert!(confidence <= 100, EInvalidOracleConfig);
    oracle.min_confidence = confidence;
}

/// Enable/disable emergency mode
public fun set_emergency_mode(
    oracle: &mut PriceOracle,
    _admin_cap: &OracleAdminCap,
    emergency: bool,
) {
    oracle.config.emergency_mode = emergency;
}

/// Clear price cache for an asset type
public fun clear_price_cache<T>(
    oracle: &mut PriceOracle,
    _admin_cap: &OracleAdminCap,
) {
    let asset_type = type_name::get<T>();
    if (table::contains(&oracle.price_cache, asset_type)) {
        table::remove(&mut oracle.price_cache, asset_type);
    };
}

// ===== Internal Helper Functions =====

/// Validate price data quality
fun validate_price_data(
    oracle: &PriceOracle,
    price_info: &PriceInfo,
    current_time: u64,
) {
    // Check if price data is not too old
    if (current_time - price_info.timestamp > oracle.max_price_delay) {
        event::emit(PriceValidationErrorEvent {
            asset_type: type_name::get<u64>(), // Placeholder
            error_type: 1, // Stale data
            timestamp: current_time,
            details: b"Price data too old",
        });
        abort EPriceDataStale
    };

    // Check confidence level
    if (price_info.confidence < oracle.min_confidence) {
        event::emit(PriceValidationErrorEvent {
            asset_type: type_name::get<u64>(), // Placeholder
            error_type: 2, // Low confidence
            timestamp: current_time,
            details: b"Price confidence too low",
        });
        abort EPriceConfidenceTooLow
    };
}

/// Check for potential price manipulation
fun check_price_manipulation(
    oracle: &PriceOracle,
    old_price: u64,
    new_price: u64,
    asset_type: TypeName,
) {
    if (old_price == 0) return; // Skip check for first price

    let price_change_pct = if (new_price > old_price) {
        ((new_price - old_price) * 10000) / old_price // Basis points
    } else {
        ((old_price - new_price) * 10000) / old_price
    };

    if (price_change_pct > oracle.config.max_price_change_pct) {
        event::emit(PriceValidationErrorEvent {
            asset_type,
            error_type: 3, // Manipulation detected
            timestamp: 0, // Will be set by caller
            details: b"Excessive price change detected",
        });
        abort EPriceManipulationDetected
    };
}

/// Simple power function for decimal calculations
fun pow(base: u64, exp: u8): u64 {
    let mut result = 1;
    let mut i = 0;
    while (i < exp) {
        result = result * base;
        i = i + 1;
    };
    result
}

// ===== Public Accessor Functions =====

/// Get current version
public fun version(oracle: &PriceOracle): u64 {
    oracle.version
}

/// Get max price delay setting
public fun max_price_delay(oracle: &PriceOracle): u64 {
    oracle.max_price_delay
}

/// Get min confidence setting
public fun min_confidence(oracle: &PriceOracle): u64 {
    oracle.min_confidence
}

/// Check if oracle is in emergency mode
public fun is_emergency_mode(oracle: &PriceOracle): bool {
    oracle.config.emergency_mode
}

/// Create price info structure (for testing)
public fun create_price_info(
    price: u64,
    confidence: u64,
    timestamp: u64,
    expo: u8,
    is_valid: bool,
): PriceInfo {
    PriceInfo {
        price,
        confidence,
        timestamp,
        expo,
        is_valid,
    }
}

/// Get price from price info
public fun price_info_price(price_info: &PriceInfo): u64 {
    price_info.price
}

/// Get confidence from price info
public fun price_info_confidence(price_info: &PriceInfo): u64 {
    price_info.confidence
}

/// Get timestamp from price info
public fun price_info_timestamp(price_info: &PriceInfo): u64 {
    price_info.timestamp
}

/// Get expo from price info
public fun price_info_expo(price_info: &PriceInfo): u8 {
    price_info.expo
}

/// Check if price info is valid
public fun price_info_is_valid(price_info: &PriceInfo): bool {
    price_info.is_valid
}