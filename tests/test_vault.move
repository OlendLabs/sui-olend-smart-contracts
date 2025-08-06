/// Vault<T> module unit tests
/// Tests Vault creation, ERC-4626 compatibility, and core operations
#[test_only]
#[allow(unused_use)]
module olend::test_vault;

use sui::test_scenario;
use sui::coin;
use sui::test_utils;

use olend::liquidity;
use olend::vault;
use olend::errors;

// Mock coin type for testing
public struct TestCoin has drop {}

const ADMIN: address = @0xAD;
const USER: address = @0x123;

/// Test Vault creation and initialization
#[test]
fun test_create_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // Create a vault
    let max_daily_withdrawal = 1000000;
    let vault = vault::create_vault<TestCoin>(
        &mut registry,
        &admin_cap,
        max_daily_withdrawal,
        test_scenario::ctx(&mut scenario)
    );
    
    // Verify initial vault state
    assert!(vault::total_assets(&vault) == 0, 0);
    assert!(vault::total_supply(&vault) == 0, 1);
    assert!(vault::get_borrowed_assets(&vault) == 0, 2);
    assert!(vault::get_available_assets(&vault) == 0, 3);
    
    // Verify vault status
    assert!(vault::is_vault_active(&vault), 4);
    assert!(!vault::is_vault_paused(&vault), 5);
    assert!(vault::deposits_allowed(&vault), 6);
    assert!(vault::withdrawals_allowed(&vault), 7);
    
    // Verify daily limit
    let (max_limit, _current_day, withdrawn_today) = vault::get_daily_limit(&vault);
    assert!(max_limit == max_daily_withdrawal, 8);
    assert!(withdrawn_today == 0, 9);
    
    // Verify vault config
    let (min_deposit, min_withdrawal, deposit_fee, withdrawal_fee) = vault::get_vault_config(&vault);
    assert!(min_deposit == 1, 10);
    assert!(min_withdrawal == 1, 11);
    assert!(deposit_fee == 0, 12);
    assert!(withdrawal_fee == 0, 13);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test deposit functionality (ERC-4626 compatibility)
#[test]
fun test_deposit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault for testing
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, USER);
    
    // Create test coin for deposit
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    
    // Perform deposit
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Verify deposit results
    assert!(vault::total_assets(&vault) == deposit_amount, 0);
    assert!(vault::total_supply(&vault) == deposit_amount, 1); // 1:1 ratio for first deposit
    assert!(vault::get_available_assets(&vault) == deposit_amount, 2);
    
    // Verify YToken
    let shares = vault::get_ytoken_value(&ytoken);
    assert!(shares == deposit_amount, 3);
    
    // Test conversion functions
    assert!(vault::convert_to_shares(&vault, deposit_amount) == deposit_amount, 5);
    assert!(vault::convert_to_assets(&vault, deposit_amount) == deposit_amount, 6);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::end(scenario);
}

/// Test withdrawal functionality (ERC-4626 compatibility)
#[test]
fun test_withdraw() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault and perform initial deposit
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, USER);
    
    // Perform withdrawal
    let withdrawn_coin = vault::withdraw(&mut vault, ytoken, test_scenario::ctx(&mut scenario));
    
    // Verify withdrawal results
    assert!(coin::value(&withdrawn_coin) == deposit_amount, 0);
    assert!(vault::total_assets(&vault) == 0, 1);
    assert!(vault::total_supply(&vault) == 0, 2);
    assert!(vault::get_available_assets(&vault) == 0, 3);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(withdrawn_coin);
    test_scenario::end(scenario);
}

/// Test multiple deposits and share calculation
#[test]
fun test_multiple_deposits() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // First deposit: 1000 assets -> 1000 shares (1:1 ratio)
    let first_deposit = 1000;
    let coin1 = coin::mint_for_testing<TestCoin>(first_deposit, test_scenario::ctx(&mut scenario));
    let ytoken1 = vault::deposit(&mut vault, coin1, test_scenario::ctx(&mut scenario));
    
    assert!(vault::total_assets(&vault) == first_deposit, 0);
    assert!(vault::total_supply(&vault) == first_deposit, 1);
    
    // Simulate interest accrual by adding assets directly to vault (via repay)
    let interest = 100;
    let interest_coin = coin::mint_for_testing<TestCoin>(interest, test_scenario::ctx(&mut scenario));
    vault::repay(&mut vault, interest_coin);
    
    // Now total assets = 1100, total shares = 1000
    assert!(vault::total_assets(&vault) == first_deposit + interest, 2);
    assert!(vault::total_supply(&vault) == first_deposit, 3);
    
    // Second deposit: 550 assets should get ~500 shares (550 * 1000 / 1100 = 500)
    let second_deposit = 550;
    let coin2 = coin::mint_for_testing<TestCoin>(second_deposit, test_scenario::ctx(&mut scenario));
    let ytoken2 = vault::deposit(&mut vault, coin2, test_scenario::ctx(&mut scenario));
    
    let expected_shares = (second_deposit * first_deposit) / (first_deposit + interest);
    let actual_shares = vault::get_ytoken_value(&ytoken2);
    assert!(actual_shares == expected_shares, 4);
    
    // Verify total state
    assert!(vault::total_assets(&vault) == first_deposit + interest + second_deposit, 5);
    assert!(vault::total_supply(&vault) == first_deposit + expected_shares, 6);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken1);
    test_utils::destroy(ytoken2);
    test_scenario::end(scenario);
}

/// Test borrow and repay functionality (package-level access)
#[test]
fun test_borrow_repay() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault with initial deposit
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Test borrow
    let borrow_amount = 300;
    let borrowed_coin = vault::borrow(&mut vault, borrow_amount, test_scenario::ctx(&mut scenario));
    
    // Verify borrow results
    assert!(coin::value(&borrowed_coin) == borrow_amount, 0);
    assert!(vault::get_borrowed_assets(&vault) == borrow_amount, 1);
    assert!(vault::get_available_assets(&vault) == deposit_amount - borrow_amount, 2);
    assert!(vault::total_assets(&vault) == deposit_amount, 3); // Total includes borrowed
    
    // Test repay
    vault::repay(&mut vault, borrowed_coin);
    
    // Verify repay results
    assert!(vault::get_borrowed_assets(&vault) == 0, 4);
    assert!(vault::get_available_assets(&vault) == deposit_amount, 5);
    assert!(vault::total_assets(&vault) == deposit_amount, 6);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::end(scenario);
}

/// Test daily withdrawal limit
#[test]
fun test_daily_withdrawal_limit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault with low daily limit
    let daily_limit = 500;
    let mut vault = vault::create_vault_for_test<TestCoin>(daily_limit, test_scenario::ctx(&mut scenario));
    
    // Deposit more than daily limit
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Split YToken for partial withdrawal
    let partial_shares = daily_limit; // Same as deposit amount for 1:1 ratio
    let ytoken_partial = coin::split(&mut ytoken, partial_shares, test_scenario::ctx(&mut scenario));
    
    // First withdrawal within limit should succeed
    let withdrawn_coin1 = vault::withdraw(&mut vault, ytoken_partial, test_scenario::ctx(&mut scenario));
    assert!(coin::value(&withdrawn_coin1) == partial_shares, 0);
    
    // Verify daily limit tracking
    let (_, _, withdrawn_today) = vault::get_daily_limit(&vault);
    assert!(withdrawn_today == partial_shares, 1);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(withdrawn_coin1);
    test_scenario::end(scenario);
}

/// Test vault status management
#[test]
fun test_vault_status_management() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Test pause functionality
    vault::pause_vault_operations(&mut vault, &admin_cap);
    assert!(vault::is_vault_paused(&vault), 1);
    assert!(!vault::deposits_allowed(&vault), 2);
    assert!(!vault::withdrawals_allowed(&vault), 3);
    
    // Test resume functionality
    vault::resume_vault_operations(&mut vault, &admin_cap);
    assert!(vault::is_vault_active(&vault), 4);
    assert!(!vault::is_vault_paused(&vault), 5);
    assert!(vault::deposits_allowed(&vault), 6);
    assert!(vault::withdrawals_allowed(&vault), 7);
    
    // Test deposits only mode
    vault::set_deposits_only(&mut vault, &admin_cap);
    assert!(vault::deposits_allowed(&vault), 8);
    assert!(!vault::withdrawals_allowed(&vault), 9);
    
    // Test withdrawals only mode
    vault::set_withdrawals_only(&mut vault, &admin_cap);
    assert!(!vault::deposits_allowed(&vault), 10);
    assert!(vault::withdrawals_allowed(&vault), 11);
    
    // Test deactivation
    vault::deactivate_vault(&mut vault, &admin_cap);
    assert!(!vault::is_vault_active(&vault), 12);
    assert!(!vault::deposits_allowed(&vault), 13);
    assert!(!vault::withdrawals_allowed(&vault), 14);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test vault configuration updates
#[test]
fun test_vault_config_update() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Update vault configuration
    let new_min_deposit = 100;
    let new_min_withdrawal = 50;
    let new_deposit_fee = 25; // 0.25%
    let new_withdrawal_fee = 50; // 0.5%
    
    vault::update_vault_config(
        &mut vault,
        &admin_cap,
        new_min_deposit,
        new_min_withdrawal,
        new_deposit_fee,
        new_withdrawal_fee
    );
    
    // Verify configuration update
    let (min_deposit, min_withdrawal, deposit_fee, withdrawal_fee) = vault::get_vault_config(&vault);
    assert!(min_deposit == new_min_deposit, 0);
    assert!(min_withdrawal == new_min_withdrawal, 1);
    assert!(deposit_fee == new_deposit_fee, 2);
    assert!(withdrawal_fee == new_withdrawal_fee, 3);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test conversion functions with zero values
#[test]
fun test_conversion_edge_cases() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create empty vault
    let vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Test conversions with empty vault
    assert!(vault::convert_to_shares(&vault, 100) == 100, 0); // 1:1 for empty vault
    assert!(vault::convert_to_assets(&vault, 100) == 0, 1); // No assets to convert
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::end(scenario);
}

/// Test error conditions - zero deposit
#[test]
#[expected_failure(abort_code = 1012)]
fun test_zero_deposit_fails() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    let zero_coin = coin::mint_for_testing<TestCoin>(0, test_scenario::ctx(&mut scenario));
    
    // This should fail with EZeroAssets error
    let ytoken = vault::deposit(&mut vault, zero_coin, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::end(scenario);
}

/// Test error conditions - insufficient assets for withdrawal
#[test]
#[expected_failure(abort_code = 1003)]
fun test_insufficient_assets_withdrawal_fails() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Deposit some assets
    let deposit_amount = 100;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut _ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Borrow all available assets
    let borrowed_coin = vault::borrow(&mut vault, deposit_amount, test_scenario::ctx(&mut scenario));
    
    // Try to withdraw (should fail due to insufficient available assets)
    let fake_ytoken = coin::split(&mut _ytoken, 50, test_scenario::ctx(&mut scenario));
    
    let withdrawn_coin = vault::withdraw(&mut vault, fake_ytoken, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(_ytoken);
    test_utils::destroy(borrowed_coin);
    test_utils::destroy(withdrawn_coin);
    test_scenario::end(scenario);
}

/// Test error conditions - paused vault operations
#[test]
#[expected_failure(abort_code = 1001)]
fun test_paused_vault_deposit_fails() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Pause vault
    vault::pause_vault_operations(&mut vault, &admin_cap);
    
    // Try to deposit (should fail)
    let test_coin = coin::mint_for_testing<TestCoin>(100, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}