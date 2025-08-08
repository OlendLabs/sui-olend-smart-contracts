/// Vault<T> module unit tests
/// Tests Vault creation, ERC-4626 compatibility, and core operations
#[test_only]
module olend::test_vault;

use sui::test_scenario;
use sui::coin;
use sui::test_utils;

use olend::liquidity;
use olend::vault;
use olend::constants;

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
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    
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
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
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
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
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
#[expected_failure(abort_code = 1012, location = olend::vault)]
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
#[expected_failure(abort_code = 1003, location = olend::vault)]
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
#[expected_failure(abort_code = 1001, location = olend::vault)]
fun test_paused_vault_deposit_fails() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
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

// ===== Package Level Functions Tests =====

/// Test borrow function with insufficient available assets
#[test]
#[expected_failure(abort_code = 1003, location = olend::vault)]
fun test_borrow_exceeds_available_assets() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Deposit some assets
    let deposit_amount = 100;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Try to borrow more than available (should fail)
    let borrow_amount = 150;
    let borrowed_coin = vault::borrow(&mut vault, borrow_amount, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(borrowed_coin);
    test_scenario::end(scenario);
}

/// Test borrow function with zero amount
#[test]
#[expected_failure(abort_code = 1012, location = olend::vault)]
fun test_borrow_zero_amount() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Deposit some assets
    let deposit_amount = 100;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Try to borrow zero amount (should fail)
    let borrowed_coin = vault::borrow(&mut vault, 0, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(borrowed_coin);
    test_scenario::end(scenario);
}

/// Test borrow and repay with interest accrual simulation
#[test]
fun test_borrow_repay_interest_accrual() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Initial deposit
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Borrow some assets
    let borrow_amount = 300;
    let borrowed_coin = vault::borrow(&mut vault, borrow_amount, test_scenario::ctx(&mut scenario));
    
    // Verify borrow state
    assert!(vault::get_borrowed_assets(&vault) == borrow_amount, 0);
    assert!(vault::get_available_assets(&vault) == deposit_amount - borrow_amount, 1);
    assert!(vault::total_assets(&vault) == deposit_amount, 2); // Total includes borrowed
    
    // Simulate interest accrual by repaying more than borrowed
    let interest = 50;
    let repay_amount = borrow_amount + interest;
    let repay_coin = coin::mint_for_testing<TestCoin>(repay_amount, test_scenario::ctx(&mut scenario));
    vault::repay(&mut vault, repay_coin);
    
    // Verify interest accrual
    assert!(vault::get_borrowed_assets(&vault) == 0, 3);
    assert!(vault::total_assets(&vault) == deposit_amount + interest, 4);
    assert!(vault::get_available_assets(&vault) == deposit_amount + interest, 5);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(borrowed_coin);
    test_scenario::end(scenario);
}

/// Test multiple borrows and repays
#[test]
fun test_multiple_borrow_repay_cycles() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Initial deposit
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // First borrow cycle
    let borrow1 = 200;
    let borrowed_coin1 = vault::borrow(&mut vault, borrow1, test_scenario::ctx(&mut scenario));
    assert!(vault::get_borrowed_assets(&vault) == borrow1, 0);
    
    // Second borrow cycle
    let borrow2 = 150;
    let borrowed_coin2 = vault::borrow(&mut vault, borrow2, test_scenario::ctx(&mut scenario));
    assert!(vault::get_borrowed_assets(&vault) == borrow1 + borrow2, 1);
    
    // Partial repay
    vault::repay(&mut vault, borrowed_coin1);
    assert!(vault::get_borrowed_assets(&vault) == borrow2, 2);
    
    // Full repay
    vault::repay(&mut vault, borrowed_coin2);
    assert!(vault::get_borrowed_assets(&vault) == 0, 3);
    assert!(vault::get_available_assets(&vault) == deposit_amount, 4);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::end(scenario);
}

// ===== Daily Limit Tests =====

/// Test daily withdrawal limit exceeded
#[test]
#[expected_failure(abort_code = 1004, location = olend::vault)]
fun test_daily_limit_exceeded() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault with low daily limit
    let daily_limit = 500;
    let mut vault = vault::create_vault_for_test<TestCoin>(daily_limit, test_scenario::ctx(&mut scenario));
    
    // Deposit more than daily limit
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Try to withdraw more than daily limit (should fail)
    let withdraw_amount = daily_limit + 100;
    let ytoken_to_withdraw = coin::split(&mut ytoken, withdraw_amount, test_scenario::ctx(&mut scenario));
    let withdrawn_coin = vault::withdraw(&mut vault, ytoken_to_withdraw, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(withdrawn_coin);
    test_scenario::end(scenario);
}

/// Test multiple withdrawals within daily limit
#[test]
fun test_multiple_withdrawals_within_limit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault with daily limit
    let daily_limit = 500;
    let mut vault = vault::create_vault_for_test<TestCoin>(daily_limit, test_scenario::ctx(&mut scenario));
    
    // Deposit assets
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // First withdrawal
    let withdraw1 = 200;
    let ytoken1 = coin::split(&mut ytoken, withdraw1, test_scenario::ctx(&mut scenario));
    let withdrawn_coin1 = vault::withdraw(&mut vault, ytoken1, test_scenario::ctx(&mut scenario));
    
    // Check daily limit tracking
    let (_, _, withdrawn_today) = vault::get_daily_limit(&vault);
    assert!(withdrawn_today == withdraw1, 0);
    
    // Second withdrawal (total should be within limit)
    let withdraw2 = 250;
    let ytoken2 = coin::split(&mut ytoken, withdraw2, test_scenario::ctx(&mut scenario));
    let withdrawn_coin2 = vault::withdraw(&mut vault, ytoken2, test_scenario::ctx(&mut scenario));
    
    // Check total withdrawn today
    let (_, _, withdrawn_today_final) = vault::get_daily_limit(&vault);
    assert!(withdrawn_today_final == withdraw1 + withdraw2, 1);
    assert!(withdrawn_today_final <= daily_limit, 2);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(withdrawn_coin1);
    test_utils::destroy(withdrawn_coin2);
    test_scenario::end(scenario);
}

/// Test daily limit reset functionality (simulated)
#[test]
fun test_daily_limit_reset_simulation() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create vault with daily limit
    let daily_limit = 500;
    let mut vault = vault::create_vault_for_test<TestCoin>(daily_limit, test_scenario::ctx(&mut scenario));
    
    // Deposit assets
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Withdraw up to daily limit
    let withdraw_amount = daily_limit;
    let ytoken_to_withdraw = coin::split(&mut ytoken, withdraw_amount, test_scenario::ctx(&mut scenario));
    let withdrawn_coin = vault::withdraw(&mut vault, ytoken_to_withdraw, test_scenario::ctx(&mut scenario));
    
    // Verify limit is reached
    let (max_limit, _current_day, withdrawn_today) = vault::get_daily_limit(&vault);
    assert!(withdrawn_today == daily_limit, 0);
    assert!(max_limit == daily_limit, 1);
    
    // Note: Actual day reset testing would require time manipulation
    // which is not easily testable in the current framework
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(withdrawn_coin);
    test_scenario::end(scenario);
}

// ===== Version Control Tests =====

/// Test version mismatch in deposit operation
#[test]
#[expected_failure(abort_code = 1006, location = olend::vault)]
fun test_version_mismatch_deposit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Set vault to an older version to simulate version mismatch
    vault::set_vault_version_for_test(&mut vault, 0); // Set to version 0, current is 1
    
    let test_coin = coin::mint_for_testing<TestCoin>(100, test_scenario::ctx(&mut scenario));
    
    // This should fail due to version mismatch
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::end(scenario);
}

/// Test version compatibility check
#[test]
fun test_version_compatibility() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Test that current version operations work
    let test_coin = coin::mint_for_testing<TestCoin>(100, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Test withdrawal with same version
    let withdrawn_coin = vault::withdraw(&mut vault, ytoken, test_scenario::ctx(&mut scenario));
    
    assert!(coin::value(&withdrawn_coin) == 100, 0);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(withdrawn_coin);
    test_scenario::end(scenario);
}

// ===== Concurrent Operations Tests =====

/// Test concurrent deposits and withdrawals
#[test]
fun test_concurrent_deposits_and_withdrawals() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Simulate multiple users depositing
    test_scenario::next_tx(&mut scenario, @0x1);
    let coin1 = coin::mint_for_testing<TestCoin>(500, test_scenario::ctx(&mut scenario));
    let mut ytoken1 = vault::deposit(&mut vault, coin1, test_scenario::ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, @0x2);
    let coin2 = coin::mint_for_testing<TestCoin>(300, test_scenario::ctx(&mut scenario));
    let ytoken2 = vault::deposit(&mut vault, coin2, test_scenario::ctx(&mut scenario));
    
    // Verify total state
    assert!(vault::total_assets(&vault) == 800, 0);
    assert!(vault::total_supply(&vault) == 800, 1);
    
    // Simulate one user withdrawing while another deposits
    test_scenario::next_tx(&mut scenario, @0x3);
    let coin3 = coin::mint_for_testing<TestCoin>(200, test_scenario::ctx(&mut scenario));
    let ytoken3 = vault::deposit(&mut vault, coin3, test_scenario::ctx(&mut scenario));
    
    // Partial withdrawal by first user
    let partial_ytoken = coin::split(&mut ytoken1, 250, test_scenario::ctx(&mut scenario));
    let withdrawn_coin = vault::withdraw(&mut vault, partial_ytoken, test_scenario::ctx(&mut scenario));
    
    // Verify final state
    assert!(coin::value(&withdrawn_coin) == 250, 2);
    assert!(vault::total_assets(&vault) == 750, 3); // 800 + 200 - 250
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken1);
    test_utils::destroy(ytoken2);
    test_utils::destroy(ytoken3);
    test_utils::destroy(withdrawn_coin);
    test_scenario::end(scenario);
}

/// Test borrow during deposit operations
#[test]
fun test_borrow_during_deposit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Initial deposit
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Borrow some assets
    let borrow_amount = 300;
    let borrowed_coin = vault::borrow(&mut vault, borrow_amount, test_scenario::ctx(&mut scenario));
    
    // Another user deposits while assets are borrowed
    test_scenario::next_tx(&mut scenario, @0x2);
    let deposit2_amount = 500;
    let test_coin2 = coin::mint_for_testing<TestCoin>(deposit2_amount, test_scenario::ctx(&mut scenario));
    let ytoken2 = vault::deposit(&mut vault, test_coin2, test_scenario::ctx(&mut scenario));
    
    // Verify state consistency
    assert!(vault::total_assets(&vault) == deposit_amount + deposit2_amount, 0);
    assert!(vault::get_borrowed_assets(&vault) == borrow_amount, 1);
    assert!(vault::get_available_assets(&vault) == deposit_amount + deposit2_amount - borrow_amount, 2);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(ytoken2);
    test_utils::destroy(borrowed_coin);
    test_scenario::end(scenario);
}

// ===== Configuration and Edge Cases Tests =====

/// Test all vault status transitions
#[test]
fun test_all_status_transitions() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Test initial active state
    assert!(vault::is_vault_active(&vault), 0);
    assert!(vault::deposits_allowed(&vault), 1);
    assert!(vault::withdrawals_allowed(&vault), 2);
    
    // Test pause transition
    vault::pause_vault_operations(&mut vault, &admin_cap);
    assert!(vault::is_vault_paused(&vault), 3);
    assert!(!vault::deposits_allowed(&vault), 4);
    assert!(!vault::withdrawals_allowed(&vault), 5);
    
    // Test resume transition
    vault::resume_vault_operations(&mut vault, &admin_cap);
    assert!(vault::is_vault_active(&vault), 6);
    assert!(vault::deposits_allowed(&vault), 7);
    assert!(vault::withdrawals_allowed(&vault), 8);
    
    // Test deposits only mode
    vault::set_deposits_only(&mut vault, &admin_cap);
    assert!(vault::deposits_allowed(&vault), 9);
    assert!(!vault::withdrawals_allowed(&vault), 10);
    
    // Test withdrawals only mode
    vault::set_withdrawals_only(&mut vault, &admin_cap);
    assert!(!vault::deposits_allowed(&vault), 11);
    assert!(vault::withdrawals_allowed(&vault), 12);
    
    // Test deactivation
    vault::deactivate_vault(&mut vault, &admin_cap);
    assert!(!vault::is_vault_active(&vault), 13);
    assert!(!vault::deposits_allowed(&vault), 14);
    assert!(!vault::withdrawals_allowed(&vault), 15);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test operations in different vault states
#[test]
fun test_operations_in_different_states() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Initial deposit in active state
    let test_coin = coin::mint_for_testing<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Set to deposits only mode
    vault::set_deposits_only(&mut vault, &admin_cap);
    
    // Deposit should work
    let test_coin2 = coin::mint_for_testing<TestCoin>(500, test_scenario::ctx(&mut scenario));
    let ytoken2 = vault::deposit(&mut vault, test_coin2, test_scenario::ctx(&mut scenario));
    
    // Set to withdrawals only mode
    vault::set_withdrawals_only(&mut vault, &admin_cap);
    
    // Withdrawal should work
    let partial_ytoken = coin::split(&mut ytoken, 300, test_scenario::ctx(&mut scenario));
    let withdrawn_coin = vault::withdraw(&mut vault, partial_ytoken, test_scenario::ctx(&mut scenario));
    
    assert!(coin::value(&withdrawn_coin) == 300, 0);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(ytoken2);
    test_utils::destroy(withdrawn_coin);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

// ===== Emergency and Security Features Tests =====

/// Test emergency pause functionality
#[test]
fun test_emergency_pause() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Initial state should be active
    assert!(vault::is_vault_active(&vault), 0);
    assert!(!vault::is_emergency_paused(&vault), 1);
    
    // Emergency pause
    vault::emergency_pause(&mut vault, &admin_cap);
    
    // Verify emergency state
    assert!(!vault::is_vault_active(&vault), 2);
    assert!(vault::is_emergency_paused(&vault), 3);
    assert!(!vault::deposits_allowed(&vault), 4);
    assert!(!vault::withdrawals_allowed(&vault), 5);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test emergency pause blocks all operations
#[test]
#[expected_failure(abort_code = 1008, location = olend::vault)]
fun test_emergency_pause_blocks_operations() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Emergency pause
    vault::emergency_pause(&mut vault, &admin_cap);
    
    // Try to deposit (should fail)
    let test_coin = coin::mint_for_testing<TestCoin>(100, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test dynamic daily limit adjustment
#[test]
fun test_update_daily_limit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Check initial limit
    let (initial_limit, _, _) = vault::get_daily_limit(&vault);
    assert!(initial_limit == 1000000, 0);
    
    // Update limit
    let new_limit = 500000;
    vault::update_daily_limit(&mut vault, new_limit, &admin_cap);
    
    // Verify update
    let (updated_limit, _, _) = vault::get_daily_limit(&vault);
    assert!(updated_limit == new_limit, 1);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test vault statistics function
#[test]
fun test_vault_statistics() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Initial statistics (empty vault)
    let (total_assets, total_supply, borrowed_assets, available_assets, utilization_rate) = 
        vault::get_vault_statistics(&vault);
    assert!(total_assets == 0, 0);
    assert!(total_supply == 0, 1);
    assert!(borrowed_assets == 0, 2);
    assert!(available_assets == 0, 3);
    assert!(utilization_rate == 0, 4);
    
    // Add some assets
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Statistics after deposit
    let (total_assets, total_supply, borrowed_assets, available_assets, utilization_rate) = 
        vault::get_vault_statistics(&vault);
    assert!(total_assets == deposit_amount, 5);
    assert!(total_supply == deposit_amount, 6);
    assert!(borrowed_assets == 0, 7);
    assert!(available_assets == deposit_amount, 8);
    assert!(utilization_rate == 0, 9); // No borrowing yet
    
    // Borrow some assets
    let borrow_amount = 300;
    let borrowed_coin = vault::borrow(&mut vault, borrow_amount, test_scenario::ctx(&mut scenario));
    
    // Statistics after borrow
    let (total_assets, total_supply, borrowed_assets, available_assets, utilization_rate) = 
        vault::get_vault_statistics(&vault);
    assert!(total_assets == deposit_amount, 10);
    assert!(total_supply == deposit_amount, 11);
    assert!(borrowed_assets == borrow_amount, 12);
    assert!(available_assets == deposit_amount - borrow_amount, 13);
    assert!(utilization_rate == 3000, 14); // 30% utilization (300/1000 * 10000)
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(borrowed_coin);
    test_scenario::end(scenario);
}

/// Test invalid daily limit updates
#[test]
#[expected_failure(abort_code = 9001, location = olend::vault)]
fun test_invalid_daily_limit_update() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Try to set zero limit (should fail)
    vault::update_daily_limit(&mut vault, 0, &admin_cap);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

// ===== Enhanced Security Control Tests =====

/// Test enhanced emergency pause functionality
#[test]
fun test_enhanced_emergency_pause() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Verify vault is initially active
    assert!(vault::is_vault_active(&vault), 0);
    assert!(!vault::is_emergency_paused(&vault), 1);
    
    // Perform emergency pause
    vault::emergency_pause(&mut vault, &admin_cap);
    
    // Verify emergency pause state
    assert!(!vault::is_vault_active(&vault), 2);
    assert!(vault::is_emergency_paused(&vault), 3);
    assert!(!vault::deposits_allowed(&vault), 4);
    assert!(!vault::withdrawals_allowed(&vault), 5);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test global emergency pause functionality
#[test]
fun test_global_emergency_pause() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000000, test_scenario::ctx(&mut scenario));
    
    // Verify vault is initially active
    assert!(!vault::is_global_emergency_paused(&vault), 0);
    
    // Perform global emergency pause
    vault::global_emergency_pause(&mut vault, &admin_cap);
    
    // Verify global emergency pause state
    assert!(vault::is_emergency_paused(&vault), 1);
    assert!(vault::is_global_emergency_paused(&vault), 2);
    
    // Verify daily limit is exhausted
    let (max_limit, _, withdrawn_today) = vault::get_daily_limit(&vault);
    assert!(withdrawn_today == max_limit, 3);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test daily limit management functions
#[test]
fun test_daily_limit_management() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Deposit some assets first
    let deposit_amount = 2000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Test check_daily_limit function
    assert!(vault::check_daily_limit(&vault, 500, test_scenario::ctx(&mut scenario)), 0);
    assert!(vault::check_daily_limit(&vault, 1000, test_scenario::ctx(&mut scenario)), 1);
    assert!(!vault::check_daily_limit(&vault, 1500, test_scenario::ctx(&mut scenario)), 2);
    
    // Test get_remaining_daily_limit function
    let remaining = vault::get_remaining_daily_limit(&vault, test_scenario::ctx(&mut scenario));
    assert!(remaining == 1000, 3);
    
    // Perform a withdrawal to update daily limit
    let withdraw_amount = 300;
    let ytoken_to_withdraw = coin::split(&mut ytoken, withdraw_amount, test_scenario::ctx(&mut scenario));
    let withdrawn_coin = vault::withdraw(&mut vault, ytoken_to_withdraw, test_scenario::ctx(&mut scenario));
    
    // Check remaining limit after withdrawal
    let remaining_after = vault::get_remaining_daily_limit(&vault, test_scenario::ctx(&mut scenario));
    assert!(remaining_after == 700, 4);
    
    // Test reset_daily_limit function
    vault::reset_daily_limit(&mut vault, &admin_cap);
    let remaining_after_reset = vault::get_remaining_daily_limit(&vault, test_scenario::ctx(&mut scenario));
    assert!(remaining_after_reset == 1000, 5);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(withdrawn_coin);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test enhanced update daily limit functionality
#[test]
fun test_enhanced_update_daily_limit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Verify initial daily limit
    let (initial_limit, _, _) = vault::get_daily_limit(&vault);
    assert!(initial_limit == 1000, 0);
    
    // Update daily limit
    let new_limit = 2000;
    vault::update_daily_limit(&mut vault, new_limit, &admin_cap);
    
    // Verify updated daily limit
    let (updated_limit, _, _) = vault::get_daily_limit(&vault);
    assert!(updated_limit == new_limit, 1);
    
    // Test remaining limit with new limit
    let remaining = vault::get_remaining_daily_limit(&vault, test_scenario::ctx(&mut scenario));
    assert!(remaining == new_limit, 2);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test force update day counter functionality
#[test]
fun test_force_update_day_counter() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Deposit and withdraw to set some daily usage
    let deposit_amount = 1500;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    let withdraw_amount = 500;
    let ytoken_to_withdraw = coin::split(&mut ytoken, withdraw_amount, test_scenario::ctx(&mut scenario));
    let withdrawn_coin = vault::withdraw(&mut vault, ytoken_to_withdraw, test_scenario::ctx(&mut scenario));
    
    // Verify daily usage
    let (_, current_day, withdrawn_today) = vault::get_daily_limit(&vault);
    assert!(withdrawn_today == withdraw_amount, 0);
    
    // Force update day counter
    let new_day = current_day + 1;
    vault::force_update_day_counter(&mut vault, new_day, &admin_cap);
    
    // Verify day counter update and reset
    let (_, updated_day, withdrawn_after_update) = vault::get_daily_limit(&vault);
    assert!(updated_day == new_day, 1);
    assert!(withdrawn_after_update == 0, 2); // Should be reset
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(withdrawn_coin);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test comprehensive security status check
#[test]
fun test_security_status_check() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Test initial security status
    let (is_active, is_paused, emergency_paused, daily_limit_exceeded, remaining_limit, utilization_rate) = 
        vault::get_security_status(&vault, test_scenario::ctx(&mut scenario));
    
    assert!(is_active, 0);
    assert!(!is_paused, 1);
    assert!(!emergency_paused, 2);
    assert!(!daily_limit_exceeded, 3);
    assert!(remaining_limit == 1000, 4);
    assert!(utilization_rate == 0, 5);
    
    // Add some assets and borrow to change utilization
    let deposit_amount = 1000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    let borrow_amount = 300;
    let borrowed_coin = vault::borrow(&mut vault, borrow_amount, test_scenario::ctx(&mut scenario));
    
    // Test security status with utilization
    let (_, _, _, _, _, utilization_rate_after) = 
        vault::get_security_status(&vault, test_scenario::ctx(&mut scenario));
    
    // Utilization should be 30% = 3000 basis points
    assert!(utilization_rate_after == 3000, 6);
    
    // Test emergency pause effect on security status
    vault::emergency_pause(&mut vault, &admin_cap);
    let (is_active_after, _, emergency_paused_after, _, _, _) = 
        vault::get_security_status(&vault, test_scenario::ctx(&mut scenario));
    
    assert!(!is_active_after, 7);
    assert!(emergency_paused_after, 8);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(borrowed_coin);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test emergency pause blocks all operations
#[test]
#[expected_failure(abort_code = 1008, location = olend::vault)]
fun test_emergency_pause_blocks_deposit() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Emergency pause the vault
    vault::emergency_pause(&mut vault, &admin_cap);
    
    // Try to deposit (should fail)
    let test_coin = coin::mint_for_testing<TestCoin>(100, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test emergency pause blocks withdrawal
#[test]
#[expected_failure(abort_code = 1008, location = olend::vault)]
fun test_emergency_pause_blocks_withdrawal() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Deposit first
    let test_coin = coin::mint_for_testing<TestCoin>(100, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Emergency pause the vault
    vault::emergency_pause(&mut vault, &admin_cap);
    
    // Try to withdraw (should fail)
    let withdrawn_coin = vault::withdraw(&mut vault, ytoken, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(withdrawn_coin);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test emergency pause blocks borrow
#[test]
#[expected_failure(abort_code = 1008, location = olend::vault)]
fun test_emergency_pause_blocks_borrow() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Deposit first
    let test_coin = coin::mint_for_testing<TestCoin>(100, test_scenario::ctx(&mut scenario));
    let ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Emergency pause the vault
    vault::emergency_pause(&mut vault, &admin_cap);
    
    // Try to borrow (should fail)
    let borrowed_coin = vault::borrow(&mut vault, 50, test_scenario::ctx(&mut scenario));
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(borrowed_coin);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test enhanced invalid daily limit update
#[test]
#[expected_failure(abort_code = 9001, location = olend::vault)]
fun test_enhanced_invalid_daily_limit_update() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Try to set zero daily limit (should fail)
    vault::update_daily_limit(&mut vault, 0, &admin_cap);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test daily limit exceeds maximum allowed
#[test]
#[expected_failure(abort_code = 9001, location = olend::vault)]
fun test_daily_limit_exceeds_maximum() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Try to set daily limit above maximum (should fail)
    let max_limit = constants::max_daily_withdrawal_limit();
    vault::update_daily_limit(&mut vault, max_limit + 1, &admin_cap);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test version mismatch in security functions
#[test]
#[expected_failure(abort_code = 1006, location = olend::vault)]
fun test_version_mismatch_in_security_functions() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let mut vault = vault::create_vault_for_test<TestCoin>(1000, test_scenario::ctx(&mut scenario));
    
    // Set vault to an older version
    vault::set_vault_version_for_test(&mut vault, 0);
    
    // Try to reset daily limit (should fail due to version mismatch)
    vault::reset_daily_limit(&mut vault, &admin_cap);
    
    // Cleanup
    test_utils::destroy(vault);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test comprehensive daily limit workflow
#[test]
fun test_comprehensive_daily_limit_workflow() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry and get AdminCap
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    let daily_limit = 1000;
    let mut vault = vault::create_vault_for_test<TestCoin>(daily_limit, test_scenario::ctx(&mut scenario));
    
    // Deposit assets
    let deposit_amount = 2000;
    let test_coin = coin::mint_for_testing<TestCoin>(deposit_amount, test_scenario::ctx(&mut scenario));
    let mut ytoken = vault::deposit(&mut vault, test_coin, test_scenario::ctx(&mut scenario));
    
    // Test multiple withdrawals within limit
    let withdraw1 = 300;
    let ytoken1 = coin::split(&mut ytoken, withdraw1, test_scenario::ctx(&mut scenario));
    let coin1 = vault::withdraw(&mut vault, ytoken1, test_scenario::ctx(&mut scenario));
    
    let withdraw2 = 400;
    let ytoken2 = coin::split(&mut ytoken, withdraw2, test_scenario::ctx(&mut scenario));
    let coin2 = vault::withdraw(&mut vault, ytoken2, test_scenario::ctx(&mut scenario));
    
    // Check remaining limit
    let remaining = vault::get_remaining_daily_limit(&vault, test_scenario::ctx(&mut scenario));
    assert!(remaining == daily_limit - withdraw1 - withdraw2, 0);
    
    // Try to withdraw remaining amount
    let withdraw3 = remaining;
    let ytoken3 = coin::split(&mut ytoken, withdraw3, test_scenario::ctx(&mut scenario));
    let coin3 = vault::withdraw(&mut vault, ytoken3, test_scenario::ctx(&mut scenario));
    
    // Verify limit is exhausted
    let remaining_final = vault::get_remaining_daily_limit(&vault, test_scenario::ctx(&mut scenario));
    assert!(remaining_final == 0, 1);
    
    // Verify security status shows limit exceeded
    let (_, _, _, daily_limit_exceeded, _, _) = 
        vault::get_security_status(&vault, test_scenario::ctx(&mut scenario));
    assert!(daily_limit_exceeded, 2);
    
    // Cleanup
    test_utils::destroy(vault);
    test_utils::destroy(ytoken);
    test_utils::destroy(coin1);
    test_utils::destroy(coin2);
    test_utils::destroy(coin3);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}