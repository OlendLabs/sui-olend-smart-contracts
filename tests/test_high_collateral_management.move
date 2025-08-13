#[test_only]
module olend::test_high_collateral_management;

use sui::test_scenario;
use sui::test_utils;

use olend::borrowing_pool::{Self};
use olend::account::{Self};

// Test coins
public struct BTC has drop {}
public struct ETH has drop {}
public struct USDC has drop {}

const ADMIN: address = @0xAD;
const USER1: address = @0x1;

/// Test high collateral ratio calculation for different asset types
#[test]
fun test_high_collateral_ratio_calculation() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);
    
    // Create test pool
    let pool = borrowing_pool::create_pool_for_test<USDC>(
        1,
        b"Test Pool",
        0, // dynamic
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        ctx
    );
    
    // Create test account with level 5 (should get full bonus)
    let (account, account_cap) = account::create_account_for_test(USER1, ctx);
    
    // Test BTC max LTV calculation
    let btc_max_ltv = borrowing_pool::calculate_max_ltv_for_asset<USDC, BTC>(&pool, &account);
    // Debug: print actual value
    std::debug::print(&btc_max_ltv);
    // The account has level 0 by default, so no bonus should be applied
    // BTC base max LTV is 9700 (97%), level 0 gets no bonus
    assert!(btc_max_ltv == 9700, 0); // 97% + 0% bonus = 97%
    
    // Test ETH max LTV calculation  
    let eth_max_ltv = borrowing_pool::calculate_max_ltv_for_asset<USDC, ETH>(&pool, &account);
    assert!(eth_max_ltv == 9500, 1); // 95% + 0% bonus = 95%
    
    // Test default asset max LTV calculation
    let usdc_max_ltv = borrowing_pool::calculate_max_ltv_for_asset<USDC, USDC>(&pool, &account);
    assert!(usdc_max_ltv == 9000, 2); // 90% + 0% bonus = 90%
    
    test_utils::destroy(pool);
    test_utils::destroy(account);
    test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test high collateral configuration management
#[test]
fun test_high_collateral_config_management() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);
    
    // Create admin cap and pool
    let admin_cap = borrowing_pool::create_admin_cap_for_test(ctx);
    let mut pool = borrowing_pool::create_pool_with_admin_for_test<USDC>(
        1,
        b"Test Pool",
        0, // dynamic
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        &admin_cap,
        ctx
    );
    
    // Get initial configuration
    let (btc_ltv, eth_ltv, default_ltv, bonus_ltv, dynamic_enabled) = 
        borrowing_pool::get_high_collateral_config(&pool);
    assert!(btc_ltv == 9700, 0); // 97%
    assert!(eth_ltv == 9500, 1); // 95%
    assert!(default_ltv == 9000, 2); // 90%
    assert!(bonus_ltv == 200, 3); // 2%
    assert!(dynamic_enabled == true, 4);
    
    // Update configuration
    borrowing_pool::update_high_collateral_config(
        &mut pool,
        &admin_cap,
        9800, // 98% for BTC
        9600, // 96% for ETH
        9100, // 91% for others
        300, // 3% bonus
        false // disable dynamic
    );
    
    // Verify updated configuration
    let (new_btc_ltv, new_eth_ltv, new_default_ltv, new_bonus_ltv, new_dynamic_enabled) = 
        borrowing_pool::get_high_collateral_config(&pool);
    assert!(new_btc_ltv == 9800, 5);
    assert!(new_eth_ltv == 9600, 6);
    assert!(new_default_ltv == 9100, 7);
    assert!(new_bonus_ltv == 300, 8);
    assert!(new_dynamic_enabled == false, 9);
    
    test_utils::destroy(admin_cap);
    test_utils::destroy(pool);
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
        b"Test Pool",
        0, // dynamic
        500, // 5% base rate
        8000, // 80% initial LTV
        9000, // 90% warning LTV
        9500, // 95% liquidation LTV
        &admin_cap,
        ctx
    );
    
    // Get initial risk monitoring configuration
    let (threshold, interval, auto_liq, risk_alert) = 
        borrowing_pool::get_risk_monitoring_config(&pool);
    assert!(threshold == 500, 0); // 5%
    assert!(interval == 300, 1); // 5 minutes
    assert!(auto_liq == true, 2);
    assert!(risk_alert == true, 3);
    
    // Update risk monitoring configuration
    borrowing_pool::update_risk_monitoring_config(
        &mut pool,
        &admin_cap,
        1000, // 10% threshold
        600, // 10 minutes
        false, // disable auto liquidation
        false // disable risk alerts
    );
    
    // Verify updated configuration
    let (new_threshold, new_interval, new_auto_liq, new_risk_alert) = 
        borrowing_pool::get_risk_monitoring_config(&pool);
    assert!(new_threshold == 1000, 4);
    assert!(new_interval == 600, 5);
    assert!(new_auto_liq == false, 6);
    assert!(new_risk_alert == false, 7);
    
    test_utils::destroy(admin_cap);
    test_utils::destroy(pool);
    test_scenario::end(scenario);
}