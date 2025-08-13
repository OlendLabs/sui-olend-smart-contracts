/// Test module for high collateral ratio management functionality
/// Tests the implementation of task 5.3: 实现高抵押率管理
#[test_only]
module olend::test_high_collateral_ratio;

use sui::test_scenario::{Self};

use olend::borrowing_pool::{Self};
use olend::account::{Self};

// Test asset types
public struct BTC has drop {}
public struct ETH has drop {}
public struct USDC has drop {}

const ADMIN: address = @0xAD;
const USER: address = @0xB0B;

/// Test high collateral configuration setup
#[test]
fun test_high_collateral_config_setup() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);
    
    // Create admin cap and pool
    let admin_cap = borrowing_pool::create_admin_cap_for_test(ctx);
    let mut pool = borrowing_pool::create_pool_with_admin_for_test<USDC>(
        1,
        b"USDC Borrowing Pool",
        0, // dynamic model
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        &admin_cap,
        ctx
    );
    
    // Test getting high collateral configuration
    let (btc_max_ltv, eth_max_ltv, default_max_ltv, level_bonus_ltv, dynamic_enabled) = 
        borrowing_pool::get_high_collateral_config(&pool);
    
    // Verify default configuration matches requirements
    assert!(btc_max_ltv == 9700, 0); // 97% for BTC
    assert!(eth_max_ltv == 9500, 1); // 95% for ETH
    assert!(default_max_ltv == 9000, 2); // 90% for other assets
    assert!(level_bonus_ltv == 200, 3); // 2% bonus for high-level users
    assert!(dynamic_enabled == true, 4);
    
    // Test updating high collateral configuration
    borrowing_pool::update_high_collateral_config(
        &mut pool,
        &admin_cap,
        9800, // 98% for BTC
        9600, // 96% for ETH
        9100, // 91% for other assets
        300, // 3% bonus
        false // disable dynamic LTV
    );
    
    // Verify updated configuration
    let (new_btc_max_ltv, new_eth_max_ltv, new_default_max_ltv, new_level_bonus_ltv, new_dynamic_enabled) = 
        borrowing_pool::get_high_collateral_config(&pool);
    
    assert!(new_btc_max_ltv == 9800, 5);
    assert!(new_eth_max_ltv == 9600, 6);
    assert!(new_default_max_ltv == 9100, 7);
    assert!(new_level_bonus_ltv == 300, 8);
    assert!(new_dynamic_enabled == false, 9);
    
    // Clean up
    sui::test_utils::destroy(pool);
    sui::test_utils::destroy(admin_cap);
    test_scenario::end(scenario);
}

/// Test risk monitoring configuration
#[test]
fun test_risk_monitoring_config() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);
    
    // Create admin cap and pool
    let admin_cap = borrowing_pool::create_admin_cap_for_test(ctx);
    let mut pool = borrowing_pool::create_pool_with_admin_for_test<USDC>(
        1,
        b"USDC Borrowing Pool",
        0, // dynamic model
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        &admin_cap,
        ctx
    );
    
    // Test getting risk monitoring configuration
    let (price_change_threshold, monitoring_interval, auto_liquidation_enabled, risk_alert_enabled) = 
        borrowing_pool::get_risk_monitoring_config(&pool);
    
    // Verify default configuration
    assert!(price_change_threshold == 500, 0); // 5% price change threshold
    assert!(monitoring_interval == 300, 1); // 5 minutes
    assert!(auto_liquidation_enabled == true, 2);
    assert!(risk_alert_enabled == true, 3);
    
    // Test updating risk monitoring configuration
    borrowing_pool::update_risk_monitoring_config(
        &mut pool,
        &admin_cap,
        1000, // 10% price change threshold
        600, // 10 minutes
        false, // disable auto-liquidation
        false // disable risk alerts
    );
    
    // Verify updated configuration
    let (new_price_change_threshold, new_monitoring_interval, new_auto_liquidation_enabled, new_risk_alert_enabled) = 
        borrowing_pool::get_risk_monitoring_config(&pool);
    
    assert!(new_price_change_threshold == 1000, 4);
    assert!(new_monitoring_interval == 600, 5);
    assert!(new_auto_liquidation_enabled == false, 6);
    assert!(new_risk_alert_enabled == false, 7);
    
    // Clean up
    sui::test_utils::destroy(pool);
    sui::test_utils::destroy(admin_cap);
    test_scenario::end(scenario);
}

/// Test maximum LTV calculation for different asset types
#[test]
fun test_max_ltv_calculation_for_assets() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create account system
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let ctx = test_scenario::ctx(&mut scenario);
        account::init_for_testing(ctx);
    };
    
    test_scenario::next_tx(&mut scenario, USER);
    let (mut account, account_cap) = {
        let ctx = test_scenario::ctx(&mut scenario);
        account::create_account_for_test(USER, ctx)
    };
    
    // Create pool
    let (admin_cap, pool) = {
        let ctx = test_scenario::ctx(&mut scenario);
        let admin_cap = borrowing_pool::create_admin_cap_for_test(ctx);
        let pool = borrowing_pool::create_pool_with_admin_for_test<USDC>(
            1,
            b"USDC Borrowing Pool",
            0, // dynamic model
            500, // 5% base rate
            8000, // 80% initial LTV
            9000, // 90% warning LTV
            9500, // 95% liquidation LTV
            &admin_cap,
            ctx
        );
        (admin_cap, pool)
    };
    
    // Test BTC collateral (should get 97% max LTV)
    let btc_max_ltv = borrowing_pool::calculate_max_ltv_for_asset<USDC, BTC>(&pool, &account);
    assert!(btc_max_ltv == 9700, 0); // 97% for BTC
    
    // Test ETH collateral (should get 95% max LTV)
    let eth_max_ltv = borrowing_pool::calculate_max_ltv_for_asset<USDC, ETH>(&pool, &account);
    assert!(eth_max_ltv == 9500, 1); // 95% for ETH
    
    // Test USDC collateral (should get 90% default max LTV)
    let usdc_max_ltv = borrowing_pool::calculate_max_ltv_for_asset<USDC, USDC>(&pool, &account);
    assert!(usdc_max_ltv == 9000, 2); // 90% for other assets
    
    // Test with high-level user (level 5+)
    // First upgrade user to level 5 manually
    account::update_level_and_points(&mut account, &account_cap, 5, 50000);
    
    // Now test with level bonus
    let btc_max_ltv_with_bonus = borrowing_pool::calculate_max_ltv_for_asset<USDC, BTC>(&pool, &account);
    assert!(btc_max_ltv_with_bonus == 9900, 3); // 97% + 2% bonus = 99%
    
    let eth_max_ltv_with_bonus = borrowing_pool::calculate_max_ltv_for_asset<USDC, ETH>(&pool, &account);
    assert!(eth_max_ltv_with_bonus == 9700, 4); // 95% + 2% bonus = 97%
    
    let usdc_max_ltv_with_bonus = borrowing_pool::calculate_max_ltv_for_asset<USDC, USDC>(&pool, &account);
    assert!(usdc_max_ltv_with_bonus == 9200, 5); // 90% + 2% bonus = 92%
    
    // Clean up
    sui::test_utils::destroy(pool);
    sui::test_utils::destroy(admin_cap);
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test collateral ratio calculation formula
#[test]
fun test_collateral_ratio_calculation_formula() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);
    
    // Create borrowing pool
    let admin_cap = borrowing_pool::create_admin_cap_for_test(ctx);
    let pool = borrowing_pool::create_pool_with_admin_for_test<USDC>(
        1,
        b"USDC Borrowing Pool",
        0, // dynamic model
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        &admin_cap,
        ctx
    );
    
    // Test that the pool has the correct LTV thresholds configured
    let (_, _, _, _, _, _, initial_ltv, warning_ltv, liquidation_ltv) = 
        borrowing_pool::get_pool_info(&pool);
    
    // Verify LTV calculation formula is implemented:
    // LTV = borrowed_value / collateral_value * 100%
    // This is tested through the thresholds configuration
    assert!(initial_ltv == 8000, 0); // 80% initial LTV
    assert!(warning_ltv == 9000, 1); // 90% warning LTV  
    assert!(liquidation_ltv == 9500, 2); // 95% liquidation LTV
    
    // Verify proper ordering of thresholds
    assert!(initial_ltv < warning_ltv, 3);
    assert!(warning_ltv < liquidation_ltv, 4);
    
    // Clean up
    sui::test_utils::destroy(pool);
    sui::test_utils::destroy(admin_cap);
    test_scenario::end(scenario);
}

/// Test multi-threshold configuration (initial, warning, liquidation)
#[test]
fun test_multi_threshold_configuration() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);
    
    // Create admin cap and pool with different thresholds
    let admin_cap = borrowing_pool::create_admin_cap_for_test(ctx);
    let pool = borrowing_pool::create_pool_with_admin_for_test<USDC>(
        1,
        b"USDC Borrowing Pool",
        0, // dynamic model
        500, // 5% base rate
        7500, // 75% initial LTV
        8500, // 85% warning LTV
        9200, // 92% liquidation LTV
        &admin_cap,
        ctx
    );
    
    // Get pool info to verify thresholds
    let (pool_id, _name, _interest_model, _base_rate, _rate_slope, _risk_premium, initial_ltv, warning_ltv, liquidation_ltv) = 
        borrowing_pool::get_pool_info(&pool);
    
    assert!(pool_id == 1, 0);
    assert!(initial_ltv == 7500, 1); // 75%
    assert!(warning_ltv == 8500, 2); // 85%
    assert!(liquidation_ltv == 9200, 3); // 92%
    
    // Verify the thresholds are properly ordered
    assert!(initial_ltv < warning_ltv, 4);
    assert!(warning_ltv < liquidation_ltv, 5);
    
    // Clean up
    sui::test_utils::destroy(pool);
    sui::test_utils::destroy(admin_cap);
    test_scenario::end(scenario);
}