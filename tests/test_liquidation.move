#[test_only]
module olend::test_liquidation;

use sui::test_scenario::{Self, Scenario};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::test_utils;

use olend::borrowing_pool::{Self, BorrowingPool, BorrowingPoolRegistry, BorrowingPoolAdminCap};
use olend::vault::{Self, Vault};
use olend::account::{Self, Account, AccountRegistry, AccountCap};
use olend::oracle::{Self, PriceOracle, OracleAdminCap};
use olend::ytoken::{YToken};
use olend::test_coin::{Self, TEST_COIN};

const ADMIN: address = @0xAD;
const USER: address = @0x1;
const LIQUIDATOR: address = @0x2;

fun ctx(scenario: &mut Scenario): &mut TxContext {
    test_scenario::ctx(scenario)
}

#[test]
fun test_liquidation_tick_calculation() {
    let mut scenario = test_scenario::begin(ADMIN);
    let clock = clock::create_for_testing(ctx(&mut scenario));
    
    // Initialize borrowing pool registry
    borrowing_pool::init_for_testing(ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<BorrowingPoolRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<BorrowingPoolAdminCap>(&scenario);
        
        // Create a borrowing pool
        let _pool_id = borrowing_pool::create_borrowing_pool<TEST_COIN>(
            &mut registry,
            &admin_cap,
            b"Test Pool",
            b"Test Description",
            0, // dynamic interest model
            500, // 5% base rate
            1000, // 10% rate slope
            200, // 2% risk premium
            800, // 8% fixed rate
            8000, // 80% initial LTV
            9000, // 90% warning LTV
            9500, // 95% liquidation LTV
            1_000_000_000, // max borrow limit
            &clock,
            ctx(&mut scenario)
        );
        
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
    };
    
    test_scenario::next_tx(&mut scenario, USER);
    {
        let pool = test_scenario::take_shared<BorrowingPool<TEST_COIN>>(&scenario);
        
        // Test liquidation tick calculation
        let ticks = borrowing_pool::calculate_liquidation_ticks(&pool);
        
        // Should have ticks from liquidation_ltv (95%) to 100%
        // With tick_size of 0.5% (50 basis points), we should have 10 ticks
        assert!(vector::length(&ticks) == 10, 0);
        
        test_scenario::return_shared(pool);
    };
    
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun test_liquidation_config_update() {
    let mut scenario = test_scenario::begin(ADMIN);
    let clock = clock::create_for_testing(ctx(&mut scenario));
    
    // Initialize borrowing pool registry
    borrowing_pool::init_for_testing(ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<BorrowingPoolRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<BorrowingPoolAdminCap>(&scenario);
        
        // Create a borrowing pool
        let _pool_id = borrowing_pool::create_borrowing_pool<TEST_COIN>(
            &mut registry,
            &admin_cap,
            b"Test Pool",
            b"Test Description",
            0, // dynamic interest model
            500, // 5% base rate
            1000, // 10% rate slope
            200, // 2% risk premium
            800, // 8% fixed rate
            8000, // 80% initial LTV
            9000, // 90% warning LTV
            9500, // 95% liquidation LTV
            1_000_000_000, // max borrow limit
            &clock,
            ctx(&mut scenario)
        );
        
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
    };
    
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut pool = test_scenario::take_shared<BorrowingPool<TEST_COIN>>(&scenario);
        let admin_cap = test_scenario::take_from_sender<BorrowingPoolAdminCap>(&scenario);
        
        // Get initial config
        let (initial_tick_size, initial_penalty, initial_reward, initial_max_ratio) = 
            borrowing_pool::get_liquidation_config(&pool);
        
        assert!(initial_tick_size == 50, 0); // 0.5%
        assert!(initial_penalty == 10, 0); // 0.1%
        assert!(initial_reward == 5, 0); // 0.05%
        assert!(initial_max_ratio == 1000, 0); // 10%
        
        // Update liquidation config
        borrowing_pool::update_liquidation_config<TEST_COIN>(
            &mut pool,
            &admin_cap,
            option::some(100), // 1% tick size
            option::some(20), // 0.2% penalty
            option::some(10), // 0.1% reward
            option::some(2000), // 20% max ratio
        );
        
        // Verify config was updated
        let (new_tick_size, new_penalty, new_reward, new_max_ratio) = 
            borrowing_pool::get_liquidation_config(&pool);
        
        assert!(new_tick_size == 100, 0);
        assert!(new_penalty == 20, 0);
        assert!(new_reward == 10, 0);
        assert!(new_max_ratio == 2000, 0);
        
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(pool);
    };
    
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun test_liquidation_enabled_check() {
    let mut scenario = test_scenario::begin(ADMIN);
    let clock = clock::create_for_testing(ctx(&mut scenario));
    
    // Initialize borrowing pool registry
    borrowing_pool::init_for_testing(ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<BorrowingPoolRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<BorrowingPoolAdminCap>(&scenario);
        
        // Create a borrowing pool
        let _pool_id = borrowing_pool::create_borrowing_pool<TEST_COIN>(
            &mut registry,
            &admin_cap,
            b"Test Pool",
            b"Test Description",
            0, // dynamic interest model
            500, // 5% base rate
            1000, // 10% rate slope
            200, // 2% risk premium
            800, // 8% fixed rate
            8000, // 80% initial LTV
            9000, // 90% warning LTV
            9500, // 95% liquidation LTV
            1_000_000_000, // max borrow limit
            &clock,
            ctx(&mut scenario)
        );
        
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
    };
    
    test_scenario::next_tx(&mut scenario, USER);
    {
        let pool = test_scenario::take_shared<BorrowingPool<TEST_COIN>>(&scenario);
        
        // Check that liquidation is enabled by default
        assert!(borrowing_pool::is_liquidation_enabled(&pool), 0);
        
        // Check liquidation stats
        let (total_liquidations, total_penalties, penalty_rate, reward_rate) = 
            borrowing_pool::get_liquidation_stats(&pool);
        
        assert!(total_liquidations == 0, 0);
        assert!(total_penalties == 0, 0);
        assert!(penalty_rate == 10, 0); // 0.1%
        assert!(reward_rate == 5, 0); // 0.05%
        
        test_scenario::return_shared(pool);
    };
    
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}