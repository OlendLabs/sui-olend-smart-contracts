/// Fixed test module for BorrowingPool core functionality
/// Tests basic functionality without complex oracle integration
#[test_only]
module olend::test_borrowing_fixed;

use sui::test_scenario::{Self as test, ctx};
use sui::test_utils;
use olend::borrowing_pool;

// Test coin types
public struct USDC has drop {}

const ADMIN: address = @0xAD;

/// Test basic pool creation and configuration
#[test]
fun test_pool_creation_fixed() {
    let mut scenario = test::begin(ADMIN);
    
    // Create test pool
    let pool = borrowing_pool::create_pool_for_test<USDC>(
        1, // pool_id
        b"Test USDC Pool",
        0, // dynamic model
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        ctx(&mut scenario)
    );
    
    // Check pool info
    let (pool_id, name, interest_model, base_rate, _rate_slope, _risk_premium, initial_ltv, warning_ltv, liquidation_ltv) = 
        borrowing_pool::get_pool_info(&pool);
    
    assert!(pool_id == 1, 0);
    assert!(name == b"Test USDC Pool", 1);
    assert!(interest_model == 0, 2);
    assert!(base_rate == 500, 3);
    assert!(initial_ltv == 8000, 4);
    assert!(warning_ltv == 9000, 5);
    assert!(liquidation_ltv == 9500, 6);
    
    // Check pool stats
    let (total_borrowed, active_positions, total_borrowers, total_interest_paid, total_liquidations, current_apr) = 
        borrowing_pool::get_pool_stats(&pool);
    
    assert!(total_borrowed == 0, 7);
    assert!(active_positions == 0, 8);
    assert!(total_borrowers == 0, 9);
    assert!(total_interest_paid == 0, 10);
    assert!(total_liquidations == 0, 11);
    assert!(current_apr > 0, 12); // Should have some base rate
    
    // Check pool status
    let status = borrowing_pool::get_pool_status(&pool);
    assert!(status == 0, 13); // Active status
    
    // Check borrowing and repayment allowed
    assert!(borrowing_pool::borrowing_allowed(&pool), 14);
    assert!(borrowing_pool::repayment_allowed(&pool), 15);
    
    // Cleanup
    test_utils::destroy(pool);
    test::end(scenario);
}

/// Test pool registry functionality
#[test]
fun test_pool_registry_fixed() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize registry
    let (mut registry, admin_cap) = borrowing_pool::init_registry_for_test(ctx(&mut scenario));
    
    // Check initial state
    assert!(borrowing_pool::get_total_pools(&registry) == 0, 0);
    assert!(borrowing_pool::get_registry_version(&registry) > 0, 1);
    
    // Create a pool
    let clock = sui::clock::create_for_testing(ctx(&mut scenario));
    let pool_id = borrowing_pool::create_borrowing_pool<USDC>(
        &mut registry,
        &admin_cap,
        b"USDC Pool",
        b"Test USDC borrowing pool",
        0, // dynamic model
        500, // 5% base rate
        1000, // 10% rate slope
        200, // 2% risk premium
        700, // 7% fixed rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        1_000_000, // 1M max borrow limit
        &clock,
        ctx(&mut scenario)
    );
    
    // Check registry updated
    assert!(borrowing_pool::get_total_pools(&registry) == 1, 2);
    assert!(borrowing_pool::pool_exists(&registry, pool_id), 3);
    
    // Check asset pools
    let usdc_pools = borrowing_pool::get_pools_for_asset<USDC>(&registry);
    assert!(vector::length(&usdc_pools) == 1, 4);
    assert!(*vector::borrow(&usdc_pools, 0) == pool_id, 5);
    
    // Cleanup
    sui::clock::destroy_for_testing(clock);
    test_utils::destroy(registry);
    test_utils::destroy(admin_cap);
    test::end(scenario);
}

/// Test interest rate calculation
#[test]
fun test_interest_calculation_fixed() {
    let mut scenario = test::begin(ADMIN);
    
    // Create pool with higher interest rate for testing
    let mut pool = borrowing_pool::create_pool_for_test<USDC>(
        1,
        b"High Interest Pool",
        0, // dynamic model
        1000, // 10% base rate
        8000, 9000, 9500,
        ctx(&mut scenario)
    );
    
    let clock = sui::clock::create_for_testing(ctx(&mut scenario));
    
    // Update pool interest
    borrowing_pool::update_pool_interest(&mut pool, &clock);
    
    // Check that pool stats are updated
    let (_total_borrowed, _active_positions, _total_borrowers, _total_interest_paid, _total_liquidations, current_apr) = 
        borrowing_pool::get_pool_stats(&pool);
    
    // Should have base rate + risk premium as current APR
    assert!(current_apr >= 1000, 0); // At least base rate
    
    // Cleanup
    test_utils::destroy(pool);
    sui::clock::destroy_for_testing(clock);
    test::end(scenario);
}

/// Test pool configuration validation
#[test]
#[expected_failure(abort_code = olend::borrowing_pool::EInvalidPoolConfig)]
fun test_invalid_pool_config_fixed() {
    let mut scenario = test::begin(ADMIN);
    
    let (mut registry, admin_cap) = borrowing_pool::init_registry_for_test(ctx(&mut scenario));
    let clock = sui::clock::create_for_testing(ctx(&mut scenario));
    
    // Try to create pool with invalid LTV configuration (initial > warning)
    let _pool_id = borrowing_pool::create_borrowing_pool<USDC>(
        &mut registry,
        &admin_cap,
        b"Invalid Pool",
        b"Pool with invalid config",
        0, 500, 1000, 200, 700,
        9000, // initial LTV
        8000, // warning LTV (should be > initial)
        9500, // liquidation LTV
        1_000_000,
        &clock,
        ctx(&mut scenario)
    );
    
    // Should not reach here
    abort 999
}