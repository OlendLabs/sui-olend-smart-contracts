/// Package Interface Tests - Tests for module interaction interfaces
/// Tests the package-level borrow and repay functions for inter-module communication
#[test_only]
module olend::test_package_interface;

use sui::test_scenario::{Self};
use sui::coin::{Self};
use sui::sui::SUI;

use olend::liquidity::{Self, Registry, LiquidityAdminCap};
use olend::vault::{Self};
use olend::constants;

// Test constants
const ADMIN: address = @0xAD;

const INITIAL_DEPOSIT: u64 = 1000000; // 1M units
const BORROW_AMOUNT: u64 = 500000;    // 500K units
const REPAY_AMOUNT: u64 = 300000;     // 300K units

#[test]
/// Test successful package-level borrow operation
fun test_package_borrow_success() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault with initial liquidity and test borrow
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // Verify initial state
        let initial_total_assets = vault::total_assets(&vault);
        let initial_available = vault::get_available_assets(&vault);
        let initial_borrowed = vault::get_borrowed_assets(&vault);
        
        assert!(initial_total_assets == INITIAL_DEPOSIT, 0);
        assert!(initial_available == INITIAL_DEPOSIT, 1);
        assert!(initial_borrowed == 0, 2);
        
        // Perform borrow operation (package-level function)
        let borrowed_coin = vault::borrow(&mut vault, BORROW_AMOUNT, test_scenario::ctx(&mut scenario));
        
        // Verify borrow results
        assert!(coin::value(&borrowed_coin) == BORROW_AMOUNT, 3);
        
        // Verify vault state after borrow
        let final_total_assets = vault::total_assets(&vault);
        let final_available = vault::get_available_assets(&vault);
        let final_borrowed = vault::get_borrowed_assets(&vault);
        
        assert!(final_total_assets == INITIAL_DEPOSIT, 4); // Total assets unchanged
        assert!(final_available == INITIAL_DEPOSIT - BORROW_AMOUNT, 5); // Available reduced
        assert!(final_borrowed == BORROW_AMOUNT, 6); // Borrowed increased
        
        // Clean up
        coin::burn_for_testing(borrowed_coin);
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
/// Test successful package-level repay operation
fun test_package_repay_success() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault, add liquidity, borrow, then repay
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // First borrow some assets
        let borrowed_coin = vault::borrow(&mut vault, BORROW_AMOUNT, test_scenario::ctx(&mut scenario));
        coin::burn_for_testing(borrowed_coin); // Simulate using the borrowed assets
        
        // Verify state before repay
        let initial_total_assets = vault::total_assets(&vault);
        let initial_available = vault::get_available_assets(&vault);
        let initial_borrowed = vault::get_borrowed_assets(&vault);
        
        assert!(initial_total_assets == INITIAL_DEPOSIT, 0);
        assert!(initial_available == INITIAL_DEPOSIT - BORROW_AMOUNT, 1);
        assert!(initial_borrowed == BORROW_AMOUNT, 2);
        
        // Create repayment coin and perform repay operation (package-level function)
        let repay_coin = coin::mint_for_testing<SUI>(REPAY_AMOUNT, test_scenario::ctx(&mut scenario));
        vault::repay(&mut vault, repay_coin);
        
        // Verify vault state after repay
        let final_total_assets = vault::total_assets(&vault);
        let final_available = vault::get_available_assets(&vault);
        let final_borrowed = vault::get_borrowed_assets(&vault);
        
        assert!(final_total_assets == INITIAL_DEPOSIT, 3); // Total assets unchanged
        assert!(final_available == INITIAL_DEPOSIT - BORROW_AMOUNT + REPAY_AMOUNT, 4); // Available increased
        assert!(final_borrowed == BORROW_AMOUNT - REPAY_AMOUNT, 5); // Borrowed decreased
        
        // Clean up
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
/// Test full repayment operation
fun test_package_full_repay() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault, add liquidity, borrow, then fully repay
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // First borrow some assets
        let borrowed_coin = vault::borrow(&mut vault, BORROW_AMOUNT, test_scenario::ctx(&mut scenario));
        coin::burn_for_testing(borrowed_coin);
        
        // Create full repayment coin and perform full repay
        let repay_coin = coin::mint_for_testing<SUI>(BORROW_AMOUNT, test_scenario::ctx(&mut scenario));
        vault::repay(&mut vault, repay_coin);
        
        // Verify vault state after full repay
        let final_total_assets = vault::total_assets(&vault);
        let final_available = vault::get_available_assets(&vault);
        let final_borrowed = vault::get_borrowed_assets(&vault);
        
        assert!(final_total_assets == INITIAL_DEPOSIT, 0);
        assert!(final_available == INITIAL_DEPOSIT, 1); // Back to original
        assert!(final_borrowed == 0, 2); // No borrowed assets
        
        // Clean up
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
/// Test over-repayment handling
fun test_package_over_repay() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault, add liquidity, borrow, then over-repay
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // First borrow some assets
        let borrowed_coin = vault::borrow(&mut vault, BORROW_AMOUNT, test_scenario::ctx(&mut scenario));
        coin::burn_for_testing(borrowed_coin);
        
        let initial_borrowed = vault::get_borrowed_assets(&vault);
        assert!(initial_borrowed == BORROW_AMOUNT, 0);
        
        // Create over-repayment coin (more than borrowed)
        let over_repay_amount = BORROW_AMOUNT + 100000;
        let repay_coin = coin::mint_for_testing<SUI>(over_repay_amount, test_scenario::ctx(&mut scenario));
        vault::repay(&mut vault, repay_coin);
        
        // Verify vault state after over-repay
        let final_total_assets = vault::total_assets(&vault);
        let final_available = vault::get_available_assets(&vault);
        let final_borrowed = vault::get_borrowed_assets(&vault);
        
        // Total assets should increase by the over-repayment
        assert!(final_total_assets == INITIAL_DEPOSIT + 100000, 1);
        assert!(final_available == INITIAL_DEPOSIT + 100000, 2);
        assert!(final_borrowed == 0, 3); // Borrowed should be zero
        
        // Clean up
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = 1012, location = olend::vault)]
/// Test borrow with zero amount should fail
fun test_package_borrow_zero_amount() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault and try to borrow zero amount
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // Try to borrow zero amount - should fail
        let borrowed_coin = vault::borrow(&mut vault, 0, test_scenario::ctx(&mut scenario));
        
        // Clean up (won't reach here due to expected failure)
        coin::burn_for_testing(borrowed_coin);
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = 1003, location = olend::vault)]
/// Test borrow more than available should fail
fun test_package_borrow_insufficient_assets() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault and try to borrow more than available
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // Try to borrow more than available - should fail
        let excessive_amount = INITIAL_DEPOSIT + 1;
        let borrowed_coin = vault::borrow(&mut vault, excessive_amount, test_scenario::ctx(&mut scenario));
        
        // Clean up (won't reach here due to expected failure)
        coin::burn_for_testing(borrowed_coin);
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = 1012, location = olend::vault)]
/// Test repay with zero amount should fail
fun test_package_repay_zero_amount() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault and try to repay zero amount
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Try to repay zero amount - should fail
        let repay_coin = coin::mint_for_testing<SUI>(0, test_scenario::ctx(&mut scenario));
        vault::repay(&mut vault, repay_coin);
        
        // Clean up (won't reach here due to expected failure)
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
/// Test multiple borrow and repay operations
fun test_package_multiple_borrow_repay() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault and test multiple operations
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // Multiple borrow operations
        let borrowed_coin1 = vault::borrow(&mut vault, 200000, test_scenario::ctx(&mut scenario));
        assert!(coin::value(&borrowed_coin1) == 200000, 0);
        coin::burn_for_testing(borrowed_coin1);
        
        let borrowed_coin2 = vault::borrow(&mut vault, 150000, test_scenario::ctx(&mut scenario));
        assert!(coin::value(&borrowed_coin2) == 150000, 1);
        coin::burn_for_testing(borrowed_coin2);
        
        // Verify total borrowed
        assert!(vault::get_borrowed_assets(&vault) == 350000, 2);
        assert!(vault::get_available_assets(&vault) == INITIAL_DEPOSIT - 350000, 3);
        
        // Multiple repay operations
        let repay_coin1 = coin::mint_for_testing<SUI>(100000, test_scenario::ctx(&mut scenario));
        vault::repay(&mut vault, repay_coin1);
        
        let repay_coin2 = coin::mint_for_testing<SUI>(150000, test_scenario::ctx(&mut scenario));
        vault::repay(&mut vault, repay_coin2);
        
        // Verify remaining borrowed
        assert!(vault::get_borrowed_assets(&vault) == 100000, 4);
        assert!(vault::get_available_assets(&vault) == INITIAL_DEPOSIT - 100000, 5);
        
        // Clean up
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}

#[test]
/// Test borrow and repay with interest simulation
fun test_package_borrow_repay_with_interest() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    };
    
    // Create vault and test interest simulation
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = test_scenario::take_shared<Registry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<LiquidityAdminCap>(&scenario);
        
        // Create vault
        let mut vault = vault::create_vault<SUI>(
            &mut registry,
            &admin_cap,
            constants::max_daily_withdrawal_limit(),
            test_scenario::ctx(&mut scenario)
        );
        
        // Add initial liquidity
        let deposit_coin = coin::mint_for_testing<SUI>(INITIAL_DEPOSIT, test_scenario::ctx(&mut scenario));
        let ytoken_coin = vault::deposit(&mut vault, deposit_coin, test_scenario::ctx(&mut scenario));
        
        // Borrow assets
        let borrowed_coin = vault::borrow(&mut vault, BORROW_AMOUNT, test_scenario::ctx(&mut scenario));
        coin::burn_for_testing(borrowed_coin);
        assert!(vault::get_borrowed_assets(&vault) == BORROW_AMOUNT, 0);
        
        // Simulate interest accrual by repaying more than borrowed
        let interest = 50000; // 10% interest
        let total_repay = BORROW_AMOUNT + interest;
        let repay_coin = coin::mint_for_testing<SUI>(total_repay, test_scenario::ctx(&mut scenario));
        vault::repay(&mut vault, repay_coin);
        
        // Verify vault gained the interest
        assert!(vault::get_borrowed_assets(&vault) == 0, 1);
        assert!(vault::total_assets(&vault) == INITIAL_DEPOSIT + interest, 2);
        assert!(vault::get_available_assets(&vault) == INITIAL_DEPOSIT + interest, 3);
        
        // Clean up
        coin::burn_for_testing(ytoken_coin);
        sui::test_utils::destroy(vault);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    
    test_scenario::end(scenario);
}