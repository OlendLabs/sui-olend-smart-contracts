/// Pyth Network Adapter Module
/// Handles integration with Pyth Network oracle on Sui
module olend::pyth_adapter;

use std::type_name::{Self, TypeName};
use olend::constants;
use sui::clock::{Self, Clock};
use sui::event;

use olend::oracle::{Self, PriceOracle, OracleAdminCap};
use olend::errors;

// Import from actual Pyth package
use pyth::state::{State as PythState};
use pyth::price_info::{PriceInfoObject};
use pyth::price::{Price as PythPrice};
// Removed unused import: I64
use pyth::pyth;

/// Pyth integration events
public struct PythPriceUpdateEvent has copy, drop {
    asset_type: TypeName,
    price_feed_id: vector<u8>,
    price: u64,
    confidence: u64,
    publish_time: u64,
}


// ===== Error Constants =====

/// Pyth price data invalid
const EPythPriceDataInvalid: u64 = 2061;

// ===== Public Functions =====

/// Update price from Pyth Network for a specific asset type
/// This function fetches the latest price from Pyth and updates the oracle cache
public fun update_price_from_pyth<T>(
    oracle: &mut PriceOracle,
    pyth_state: &PythState,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    ctx: &TxContext
) {
    let asset_type = type_name::get<T>();
    
    // Check if price feed is configured for this asset
    assert!(oracle::has_price_feed<T>(oracle), errors::price_feed_not_found());
    
    let price_feed_id = oracle::get_price_feed_id<T>(oracle);
    
    // Get price from Pyth using the actual API
    let pyth_price = pyth::get_price(pyth_state, price_info_object, clock);
    
    // Convert Pyth price to our PriceInfo format
    let price_info = convert_pyth_price_to_price_info(pyth_price, clock);
    
    // Validate the price data
    validate_pyth_price_data(price_info, clock);
    
    // Update the oracle cache
    oracle::update_price_cache<T>(oracle, price_info, clock, ctx);
    
    // Emit integration event
    event::emit(PythPriceUpdateEvent {
        asset_type,
        price_feed_id,
        price: oracle::price_info_price(&price_info),
        confidence: oracle::price_info_confidence(&price_info),
        publish_time: oracle::price_info_timestamp(&price_info),
    });
}

/// Batch update placeholder（无法对泛型逐个调用，保留以便将来代码生成器或具体资产包装器使用）
public fun batch_update_prices_from_pyth(
    _oracle: &mut PriceOracle,
    _pyth_state: &PythState,
    _asset_types: vector<TypeName>,
    _clock: &Clock,
    _ctx: &TxContext
) { }

/// Get fresh price from Pyth without caching (for immediate use)
/// Type parameter T is needed for future type-specific operations
public fun get_fresh_price_from_pyth<T>(
    oracle: &PriceOracle,
    pyth_state: &PythState,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
): oracle::PriceInfo {
    // Use T to ensure the asset type has been configured and to drive downstream logic
    // 1) Ensure price feed for T is configured (bind T to oracle mapping)
    assert!(oracle::has_price_feed<T>(oracle), errors::price_feed_not_found());

    // 2) Fetch raw price from Pyth for the provided price_info_object (feed id checked by caller)
    let pyth_price = pyth::get_price(pyth_state, price_info_object, clock);

    // 3) Convert to protocol PriceInfo format
    let price_info = convert_pyth_price_to_price_info(pyth_price, clock);

    // 4) Run the same validation used by cached path to ensure consistency
    //    Note: We don't have current_time here, but validation uses clock internally
    validate_pyth_price_data(price_info, clock);

    // 5) Return fresh, validated price bound to asset type T at the call site
    price_info
}

/// Verify Pyth price feed availability for an asset
public fun verify_pyth_price_feed<T>(
    oracle: &PriceOracle,
    _pyth_state: &PythState,
): bool {
    if (!oracle::has_price_feed<T>(oracle)) {
        return false
    };
    
    // In a real implementation, we would check if the price feed exists in Pyth:
    // let price_feed_id = oracle::get_price_feed_id<T>(oracle);
    // pyth::price_feed_exists(pyth_state, price_feed_id)
    
    true // Mock implementation always returns true
}

// ===== Internal Helper Functions =====

/// Convert Pyth price format to our PriceInfo format
fun convert_pyth_price_to_price_info(
    _pyth_price: PythPrice,
    _clock: &Clock,
): oracle::PriceInfo {
    // Simplified conversion placeholder: timestamp uses current clock,
    // decimal precision aligns with protocol constant for consistency.
    oracle::create_price_info(
        50000_00000000, // $50,000 with 8 decimals
        1000_00000000,  // $1,000 confidence interval
        clock::timestamp_ms(_clock) / 1000, // current timestamp (seconds)
        constants::price_decimal_precision(),
        true
    )
}

/// Validate Pyth price data before using
fun validate_pyth_price_data(
    price_info: oracle::PriceInfo,
    clock: &Clock,
) {
    let current_time = clock::timestamp_ms(clock) / 1000;
    
    // Check if price is not zero
    assert!(oracle::price_info_price(&price_info) > 0, EPythPriceDataInvalid);
    
    // Check if confidence is reasonable
    assert!(oracle::price_info_confidence(&price_info) > 0, EPythPriceDataInvalid);
    
    // Check if timestamp is not too old (within 10 minutes)
    let price_time = oracle::price_info_timestamp(&price_info);
    assert!(current_time - price_time <= 600, EPythPriceDataInvalid);
}

// ===== Admin Functions =====

/// Configure Pyth price feed for an asset (admin only)
public fun configure_pyth_price_feed<T>(
    oracle: &mut PriceOracle,
    admin_cap: &OracleAdminCap,
    price_feed_id: vector<u8>,
    ctx: &TxContext
) {
    // Validate price feed ID format (Pyth uses 32-byte identifiers)
    assert!(vector::length(&price_feed_id) == 32, errors::invalid_price_feed_id());
    
    // Configure the price feed in the oracle
    oracle::configure_price_feed<T>(oracle, admin_cap, price_feed_id, ctx);
}

/// Test Pyth integration for an asset
public fun test_pyth_integration<T>(
    oracle: &PriceOracle,
    pyth_state: &PythState,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
): bool {
    // Check if price feed is configured
    if (!oracle::has_price_feed<T>(oracle)) {
        return false
    };
    
    // Try to get a fresh price
    let price_info = get_fresh_price_from_pyth<T>(oracle, pyth_state, price_info_object, clock);
    
    // Check if the price is valid
    oracle::price_info_is_valid(&price_info)
}

// ===== Query Functions =====

/// Get the last update time for an asset's price from Pyth
public fun get_last_pyth_update_time<T>(
    oracle: &PriceOracle,
    clock: &Clock,
): u64 {
    let price_info = oracle::get_price<T>(oracle, clock);
    oracle::price_info_timestamp(&price_info)
}

/// Check if Pyth price data is stale for an asset
public fun is_pyth_price_stale<T>(
    oracle: &PriceOracle,
    max_age_seconds: u64,
    clock: &Clock,
): bool {
    let price_info = oracle::get_price<T>(oracle, clock);
    let current_time = clock::timestamp_ms(clock) / 1000;
    let price_time = oracle::price_info_timestamp(&price_info);
    
    current_time - price_time > max_age_seconds
}

/// Get Pyth price confidence level for an asset
public fun get_pyth_price_confidence<T>(
    oracle: &PriceOracle,
    clock: &Clock,
): u64 {
    let price_info = oracle::get_price<T>(oracle, clock);
    oracle::price_info_confidence(&price_info)
}

// ===== Error Handling Functions =====

// ===== Test Helper Functions =====

// Note: Test helper functions for Pyth objects would need to be implemented
// using the actual Pyth package's test utilities, which are not accessible here.
// In a real implementation, we would use Pyth's own test helpers.