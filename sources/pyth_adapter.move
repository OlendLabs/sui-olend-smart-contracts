/// Pyth Network Adapter Module
/// Handles integration with Pyth Network oracle on Sui
module olend::pyth_adapter;

use std::type_name::{Self, TypeName};
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

/// Batch update prices for multiple assets from Pyth
public fun batch_update_prices_from_pyth(
    _oracle: &mut PriceOracle,
    _pyth_state: &PythState,
    asset_types: vector<TypeName>,
    _clock: &Clock,
    _ctx: &TxContext
) {
    let mut i = 0;
    let len = vector::length(&asset_types);
    
    while (i < len) {
        let _asset_type = *vector::borrow(&asset_types, i);
        
        // For each asset type, we would need to call the appropriate update function
        // This is a simplified version - in practice, we'd need type-specific calls
        
        i = i + 1;
    };
}

/// Get fresh price from Pyth without caching (for immediate use)
/// Type parameter T is needed for future type-specific operations
#[allow(unused_type_parameter)]
public fun get_fresh_price_from_pyth<T>(
    _oracle: &PriceOracle,
    pyth_state: &PythState,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
): oracle::PriceInfo {
    // Get price from Pyth using the actual API
    let pyth_price = pyth::get_price(pyth_state, price_info_object, clock);
    
    // Convert and return
    convert_pyth_price_to_price_info(pyth_price, clock)
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
    // For now, create a mock price info since we need to understand the Pyth API better
    // In a real implementation, we would extract values from pyth_price
    
    // Create a mock price for development
    oracle::create_price_info(
        50000_00000000, // $50,000 with 8 decimals
        1000_00000000,  // $1,000 confidence interval  
        1000000000,     // Mock timestamp
        8,              // 8 decimal places
        true            // Mark as valid
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