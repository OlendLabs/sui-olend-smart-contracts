/// Test module for BorrowingPool functionality
/// Tests the core borrowing pool structure and basic operations
#[test_only]
#[allow(unused_use, unused_const)]
module olend::test_borrowing_pool;

use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
use sui::coin::{Self, Coin};
use sui::clock::{Self, Clock};
use sui::test_utils;

use olend::borrowing_pool::{Self, BorrowingPoolRegistry, BorrowingPool, BorrowingPoolAdminCap, BorrowPosition, CollateralHolder};
use olend::vault::{Self, Vault};
use olend::ytoken::{YToken};
use olend::account::{Self, AccountRegistry, Account, AccountCap};
use olend::oracle::{Self, PriceOracle, OracleAdminCap};
use olend::liquidity::{Self, Registry, LiquidityAdminCap};

// Test coin types
public struct USDC has drop {}
public struct BTC has drop {}

const ADMIN: address = @0xAD;
const USER: address = @0xB0B;

/// Test creating borrowing pool registry and admin capability
#[test]
fun test_initialize_borrowing_pools() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize borrowing pools (testing)
    borrowing_pool::init_for_testing(ctx(&mut scenario));
    next_tx(&mut scenario, ADMIN);
    // Verify admin cap was created and destroy it
    let admin_cap = test::take_from_sender<BorrowingPoolAdminCap>(&scenario);
    test_utils::destroy(admin_cap);
    
    test::end(scenario);
}

/// Test creating a borrowing pool
#[test]
fun test_create_borrowing_pool() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize borrowing pools (testing)
    borrowing_pool::init_for_testing(ctx(&mut scenario));
    
    next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test::take_shared<BorrowingPoolRegistry>(&scenario);
        let admin_cap = test::take_from_sender<BorrowingPoolAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Create a borrowing pool for USDC
        let pool_id = borrowing_pool::create_borrowing_pool<USDC>(
            &mut registry,
            &admin_cap,
            b"USDC Borrowing Pool",
            b"High-ratio borrowing pool for USDC",
            0, // Dynamic interest model
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
        
        // Verify pool was created
        assert!(borrowing_pool::pool_exists(&registry, pool_id), 0);
        assert!(borrowing_pool::get_total_pools(&registry) == 1, 1);
        
        clock::destroy_for_testing(clock);
        test_utils::destroy(admin_cap);
        test::return_shared(registry);
    };
    test::end(scenario);
}

/// Test borrowing pool query functions
#[test]
fun test_borrowing_pool_queries() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize borrowing pools (testing)
    borrowing_pool::init_for_testing(ctx(&mut scenario));
    
    next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test::take_shared<BorrowingPoolRegistry>(&scenario);
        let admin_cap = test::take_from_sender<BorrowingPoolAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Create a borrowing pool
        let _pool_id = borrowing_pool::create_borrowing_pool<USDC>(
            &mut registry,
            &admin_cap,
            b"USDC Pool",
            b"Test pool",
            0, // Dynamic
            500, // 5% base
            1000, // 10% slope
            200, // 2% premium
            700, // 7% fixed
            8000, // 80% initial LTV
            9000, // 90% warning LTV
            9500, // 95% liquidation LTV
            1_000_000, // 1M limit
            &clock,
            ctx(&mut scenario)
        );
        
        clock::destroy_for_testing(clock);
        test_utils::destroy(admin_cap);
        test::return_shared(registry);
    };
    
    next_tx(&mut scenario, ADMIN);
    {
        let registry = test::take_shared<BorrowingPoolRegistry>(&scenario);
        let pool = test::take_shared<BorrowingPool<USDC>>(&scenario);
        
        // Test pool info query
        let (pool_id, name, interest_model, base_rate, rate_slope, risk_premium, initial_ltv, warning_ltv, liquidation_ltv) = 
            borrowing_pool::get_pool_info(&pool);
        
        assert!(pool_id == 1, 0);
        assert!(name == b"USDC Pool", 1);
        assert!(interest_model == 0, 2);
        assert!(base_rate == 500, 3);
        assert!(rate_slope == 1000, 4);
        assert!(risk_premium == 200, 5);
        assert!(initial_ltv == 8000, 6);
        assert!(warning_ltv == 9000, 7);
        assert!(liquidation_ltv == 9500, 8);
        
        // Test pool stats query
        let (total_borrowed, active_positions, total_borrowers, total_interest_paid, total_liquidations, current_apr) = 
            borrowing_pool::get_pool_stats(&pool);
        
        assert!(total_borrowed == 0, 9);
        assert!(active_positions == 0, 10);
        assert!(total_borrowers == 0, 11);
        assert!(total_interest_paid == 0, 12);
        assert!(total_liquidations == 0, 13);
        assert!(current_apr == 700, 14); // base_rate + risk_premium
        
        // Test pool status
        let status = borrowing_pool::get_pool_status(&pool);
        assert!(status == 0, 15); // Active
        
        // Test borrowing allowed
        assert!(borrowing_pool::borrowing_allowed(&pool), 16);
        assert!(borrowing_pool::repayment_allowed(&pool), 17);
        
        // Test registry queries
        let pools_for_usdc = borrowing_pool::get_pools_for_asset<USDC>(&registry);
        assert!(vector::length(&pools_for_usdc) == 1, 18);
        
        test::return_shared(registry);
        test::return_shared(pool);
    };
    
    test::end(scenario);
}

/// Test creating borrowing pool for testing
#[test]
fun test_create_pool_for_test() {
    let mut scenario = test::begin(ADMIN);
    
    // Create pool for testing
    let pool = borrowing_pool::create_pool_for_test<USDC>(
        1, // pool_id
        b"Test Pool",
        0, // dynamic model
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        ctx(&mut scenario)
    );
    
    // Verify pool properties
    let (pool_id, name, interest_model, base_rate, _rate_slope, _risk_premium, initial_ltv, warning_ltv, liquidation_ltv) = 
        borrowing_pool::get_pool_info(&pool);
    
    assert!(pool_id == 1, 0);
    assert!(name == b"Test Pool", 1);
    assert!(interest_model == 0, 2);
    assert!(base_rate == 500, 3);
    assert!(initial_ltv == 8000, 4);
    assert!(warning_ltv == 9000, 5);
    assert!(liquidation_ltv == 9500, 6);
    
    test_utils::destroy(pool);
    test::end(scenario);
}

/// Test registry initialization for testing
#[test]
fun test_init_registry_for_test() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize registry for testing
    let (registry, admin_cap) = borrowing_pool::init_registry_for_test(ctx(&mut scenario));
    
    // Verify registry properties
    assert!(borrowing_pool::get_registry_version(&registry) == 1, 0);
    assert!(borrowing_pool::get_total_pools(&registry) == 0, 1);
    
    test_utils::destroy(registry);
    test_utils::destroy(admin_cap);
    test::end(scenario);
}

/// Test multiple asset types
#[test]
fun test_multiple_asset_types() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize borrowing pools (testing)
    borrowing_pool::init_for_testing(ctx(&mut scenario));
    
    next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test::take_shared<BorrowingPoolRegistry>(&scenario);
        let admin_cap = test::take_from_sender<BorrowingPoolAdminCap>(&scenario);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Create pools for different assets
        let _usdc_pool_id = borrowing_pool::create_borrowing_pool<USDC>(
            &mut registry,
            &admin_cap,
            b"USDC Pool",
            b"USDC borrowing pool",
            0, 500, 1000, 200, 700, 8000, 9000, 9500, 1_000_000,
            &clock,
            ctx(&mut scenario)
        );
        
        let _btc_pool_id = borrowing_pool::create_borrowing_pool<BTC>(
            &mut registry,
            &admin_cap,
            b"BTC Pool",
            b"BTC borrowing pool",
            0, 600, 1200, 300, 900, 9000, 9500, 9700, 10_000,
            &clock,
            ctx(&mut scenario)
        );
        
        // Verify both pools exist
        assert!(borrowing_pool::get_total_pools(&registry) == 2, 0);
        
        let usdc_pools = borrowing_pool::get_pools_for_asset<USDC>(&registry);
        let btc_pools = borrowing_pool::get_pools_for_asset<BTC>(&registry);
        
        assert!(vector::length(&usdc_pools) == 1, 1);
        assert!(vector::length(&btc_pools) == 1, 2);
        
        clock::destroy_for_testing(clock);
        test_utils::destroy(admin_cap);
        test::return_shared(registry);
    };
    test::end(scenario);
}