/// Data Consistency Tests
/// Tests atomic operations, consistency validation, and concurrent access safety
#[test_only]
module olend::test_data_consistency;

use sui::test_scenario;
use sui::sui::SUI;

use olend::account;
use olend::liquidity;
use olend::constants;

const ADMIN: address = @0xAD;
const USER1: address = @0x1;
const USER2: address = @0x2;

// ===== Account Data Consistency Tests =====

/// Test atomic level and points update
#[test]
fun test_atomic_update_level_and_points() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Test atomic update
    account::atomic_update_level_and_points(
        &mut account,
        &account_cap,
        5, // new level
        100, // points to add
        test_scenario::ctx(&mut scenario)
    );
    
    // Verify both updates succeeded
    assert!(account::get_level(&account) == 5, 0);
    assert!(account::get_points(&account) == 100, 1);
    
    // Verify activity was updated
    let status = account::get_status(&account);
    let current_time = tx_context::epoch_timestamp_ms(test_scenario::ctx(&mut scenario));
    assert!(account::get_status_last_activity(&status) <= current_time, 2);
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test atomic position add and activity update
#[test]
fun test_atomic_add_position_and_update_activity() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Create a dummy position ID
    let position_id = object::id_from_address(@0x123);
    
    // Test atomic operation
    account::atomic_add_position_and_update_activity(
        &mut account,
        &account_cap,
        position_id,
        test_scenario::ctx(&mut scenario)
    );
    
    // Verify position was added
    let position_ids = account::get_position_ids(&account);
    assert!(vector::length(&position_ids) == 1, 0);
    assert!(*vector::borrow(&position_ids, 0) == position_id, 1);
    
    // Verify activity was updated
    let status = account::get_status(&account);
    let current_time = tx_context::epoch_timestamp_ms(test_scenario::ctx(&mut scenario));
    assert!(account::get_status_last_activity(&status) <= current_time, 2);
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test atomic position remove and activity update
#[test]
fun test_atomic_remove_position_and_update_activity() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Create dummy position IDs
    let position_id1 = object::id_from_address(@0x123);
    let position_id2 = object::id_from_address(@0x456);
    
    // Add positions first
    account::add_position(&mut account, &account_cap, position_id1);
    account::add_position(&mut account, &account_cap, position_id2);
    
    // Verify positions were added
    let position_ids = account::get_position_ids(&account);
    assert!(vector::length(&position_ids) == 2, 0);
    
    // Test atomic remove operation
    account::atomic_remove_position_and_update_activity(
        &mut account,
        &account_cap,
        position_id1,
        test_scenario::ctx(&mut scenario)
    );
    
    // Verify position was removed
    let position_ids = account::get_position_ids(&account);
    assert!(vector::length(&position_ids) == 1, 1);
    assert!(*vector::borrow(&position_ids, 0) == position_id2, 2);
    
    // Verify activity was updated
    let status = account::get_status(&account);
    let current_time = tx_context::epoch_timestamp_ms(test_scenario::ctx(&mut scenario));
    assert!(account::get_status_last_activity(&status) <= current_time, 3);
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test batch position update
#[test]
fun test_atomic_batch_position_update() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Create dummy position IDs
    let position_id1 = object::id_from_address(@0x123);
    let position_id2 = object::id_from_address(@0x456);
    let position_id3 = object::id_from_address(@0x789);
    let position_id4 = object::id_from_address(@0xABC);
    
    // Add initial positions
    account::add_position(&mut account, &account_cap, position_id1);
    account::add_position(&mut account, &account_cap, position_id2);
    
    // Prepare batch update
    let mut positions_to_add = vector::empty<object::ID>();
    vector::push_back(&mut positions_to_add, position_id3);
    vector::push_back(&mut positions_to_add, position_id4);
    
    let mut positions_to_remove = vector::empty<object::ID>();
    vector::push_back(&mut positions_to_remove, position_id1);
    
    // Execute batch update
    account::atomic_batch_position_update(
        &mut account,
        &account_cap,
        positions_to_add,
        positions_to_remove,
        test_scenario::ctx(&mut scenario)
    );
    
    // Verify final state
    let position_ids = account::get_position_ids(&account);
    assert!(vector::length(&position_ids) == 3, 0); // 2 - 1 + 2 = 3
    
    // Verify specific positions
    assert!(vector::contains(&position_ids, &position_id2), 1); // Should remain
    assert!(vector::contains(&position_ids, &position_id3), 2); // Should be added
    assert!(vector::contains(&position_ids, &position_id4), 3); // Should be added
    assert!(!vector::contains(&position_ids, &position_id1), 4); // Should be removed
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test account consistency validation
#[test]
fun test_validate_account_consistency() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create valid account
    let (account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Test valid account
    assert!(
        account::validate_account_consistency(&account, &account_cap, test_scenario::ctx(&mut scenario)),
        0
    );
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test account consistency validation with invalid data
#[test]
fun test_validate_account_consistency_invalid() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account with invalid data
    let future_time = tx_context::epoch_timestamp_ms(test_scenario::ctx(&mut scenario)) + 1000000;
    let (account, account_cap) = account::create_inconsistent_account_for_test(
        USER1,
        15, // Invalid level (> max_user_level)
        future_time, // Future timestamp
        test_scenario::ctx(&mut scenario)
    );
    
    // Test invalid account
    assert!(
        !account::validate_account_consistency(&account, &account_cap, test_scenario::ctx(&mut scenario)),
        0
    );
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test concurrent access safety check
#[test]
fun test_check_concurrent_access_safety() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, USER1);
    
    // Get registry and create account
    let mut registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    let (account, account_cap) = account::create_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // Test concurrent access safety
    assert!(
        account::check_concurrent_access_safety(
            &registry,
            &account,
            &account_cap,
            test_scenario::ctx(&mut scenario)
        ),
        0
    );
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

// ===== Security Enhancement Tests =====

/// Test rate limiting functionality
#[test]
fun test_rate_limiting() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Test normal operation within limits
    assert!(account::check_rate_limit(&mut account, &account_cap, test_scenario::ctx(&mut scenario)), 0);
    
    // Simulate many operations to hit rate limit
    let mut i = 0;
    while (i < constants::max_operations_per_window()) {
        let allowed = account::check_rate_limit(&mut account, &account_cap, test_scenario::ctx(&mut scenario));
        if (!allowed) {
            break
        };
        i = i + 1;
    };
    
    // Should now be at or over the limit
    assert!(!account::check_rate_limit(&mut account, &account_cap, test_scenario::ctx(&mut scenario)), 1);
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test replay attack protection
#[test]
fun test_replay_protection() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Create a dummy transaction hash
    let mut tx_hash = vector::empty<u8>();
    vector::push_back(&mut tx_hash, 1);
    vector::push_back(&mut tx_hash, 2);
    vector::push_back(&mut tx_hash, 3);
    
    // First use should be allowed
    assert!(account::check_replay_protection(&mut account, &account_cap, tx_hash), 0);
    
    // Second use of same hash should be blocked
    assert!(!account::check_replay_protection(&mut account, &account_cap, tx_hash), 1);
    
    // Different hash should be allowed
    let mut new_tx_hash = vector::empty<u8>();
    vector::push_back(&mut new_tx_hash, 4);
    vector::push_back(&mut new_tx_hash, 5);
    vector::push_back(&mut new_tx_hash, 6);
    
    assert!(account::check_replay_protection(&mut account, &account_cap, new_tx_hash), 2);
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test suspicious activity detection
#[test]
fun test_suspicious_activity_detection() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Test normal activity (should not be suspicious)
    assert!(
        !account::detect_suspicious_activity(
            &account, 
            &account_cap, 
            1, // deposit
            1000, // normal amount
            test_scenario::ctx(&mut scenario)
        ), 
        0
    );
    
    // Test very large amount (should be suspicious)
    assert!(
        account::detect_suspicious_activity(
            &account, 
            &account_cap, 
            1, // deposit
            2_000_000_000_000, // very large amount
            test_scenario::ctx(&mut scenario)
        ), 
        1
    );
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test account restriction status check
#[test]
fun test_account_restriction_status() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account with max suspicious activities (already restricted)
    let (account, account_cap) = account::create_account_with_security_for_test(
        USER1,
        0, // operation_count
        constants::max_suspicious_activities(), // at limit
        test_scenario::ctx(&mut scenario)
    );
    
    // Account should be restricted
    assert!(account::is_account_restricted(&account, test_scenario::ctx(&mut scenario)), 0);
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test account restriction due to suspicious activity
#[test]
#[expected_failure(abort_code = 2016, location = olend::account)]
fun test_account_restriction() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account with high suspicious activity count
    let (mut account, account_cap) = account::create_account_with_security_for_test(
        USER1,
        0, // operation_count
        constants::max_suspicious_activities() - 1, // just below limit
        test_scenario::ctx(&mut scenario)
    );
    
    // Account should not be restricted yet
    assert!(!account::is_account_restricted(&account, test_scenario::ctx(&mut scenario)), 0);
    
    // Record one more suspicious activity (should trigger restriction and abort)
    account::record_suspicious_activity(&mut account, &account_cap, test_scenario::ctx(&mut scenario));
    
    // Cleanup (won't reach here due to expected failure)
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test comprehensive security check
#[test]
fun test_comprehensive_security_check() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Create transaction hash
    let mut tx_hash = vector::empty<u8>();
    vector::push_back(&mut tx_hash, 1);
    vector::push_back(&mut tx_hash, 2);
    vector::push_back(&mut tx_hash, 3);
    
    // Normal operation should pass all checks
    account::comprehensive_security_check(
        &mut account,
        &account_cap,
        1, // deposit
        1000, // normal amount
        tx_hash,
        test_scenario::ctx(&mut scenario)
    );
    
    // Verify security status
    let (op_count, suspicious_count, _window_start, is_restricted) = account::get_security_status(
        &account, 
        test_scenario::ctx(&mut scenario)
    );
    
    assert!(op_count == 1, 0); // Should have incremented
    assert!(suspicious_count == 0, 1); // Should not be suspicious
    assert!(!is_restricted, 2); // Should not be restricted
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test security counter reset
#[test]
fun test_security_counter_reset() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account with some security activity
    let (mut account, account_cap) = account::create_account_with_security_for_test(
        USER1,
        50, // operation_count
        5, // suspicious_count
        test_scenario::ctx(&mut scenario)
    );
    
    // Verify initial state
    let (op_count, suspicious_count, _window_start, _is_restricted) = account::get_security_status(
        &account, 
        test_scenario::ctx(&mut scenario)
    );
    assert!(op_count == 50, 0);
    assert!(suspicious_count == 5, 1);
    
    // Reset counters
    account::reset_security_counters(&mut account, &account_cap, test_scenario::ctx(&mut scenario));
    
    // Verify reset
    let (op_count_after, suspicious_count_after, _window_start_after, is_restricted_after) = account::get_security_status(
        &account, 
        test_scenario::ctx(&mut scenario)
    );
    assert!(op_count_after == 0, 2);
    assert!(suspicious_count_after == 0, 3);
    assert!(!is_restricted_after, 4);
    
    // Cleanup
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

// ===== Vault Data Consistency Tests =====
// Note: Vault consistency tests will be added after implementing the missing functions

// ===== Registry Data Consistency Tests =====

/// Test registry consistency validation
#[test]
fun test_validate_registry_consistency() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get registry
    let registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    
    // Test valid registry
    assert!(liquidity::validate_registry_consistency(&registry), 0);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

/// Test registry concurrent safety check
#[test]
fun test_check_registry_concurrent_safety() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get registry
    let registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    
    // Test concurrent safety
    assert!(liquidity::check_registry_concurrent_safety(&registry), 0);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

/// Test cross-vault consistency validation
#[test]
fun test_validate_cross_vault_consistency() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get registry
    let registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    
    // Test empty vault list (should be consistent)
    let empty_vaults = vector::empty<object::ID>();
    assert!(liquidity::validate_cross_vault_consistency(&registry, empty_vaults), 0);
    
    // Test with some vault IDs
    let mut vault_ids = vector::empty<object::ID>();
    vector::push_back(&mut vault_ids, object::id_from_address(@0x123));
    vector::push_back(&mut vault_ids, object::id_from_address(@0x456));
    
    assert!(liquidity::validate_cross_vault_consistency(&registry, vault_ids), 1);
    
    // Test with duplicate vault IDs (should be inconsistent)
    let mut duplicate_vault_ids = vector::empty<object::ID>();
    let duplicate_id = object::id_from_address(@0x123);
    vector::push_back(&mut duplicate_vault_ids, duplicate_id);
    vector::push_back(&mut duplicate_vault_ids, duplicate_id);
    
    assert!(!liquidity::validate_cross_vault_consistency(&registry, duplicate_vault_ids), 2);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

/// Test registry snapshot functionality
#[test]
fun test_registry_snapshot() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get registry
    let registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    
    // Capture snapshot
    let (version, admin_cap_id) = liquidity::capture_registry_snapshot(&registry);
    
    // Validate against snapshot (should match)
    assert!(liquidity::validate_against_snapshot(&registry, version, admin_cap_id), 0);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

/// Test atomic vault registration and activation
#[test]
fun test_atomic_register_and_activate_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize registry
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get registry and admin cap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    
    // Create vault ID
    let vault_id = object::id_from_address(@0x123);
    
    // Test atomic registration and activation
    liquidity::atomic_register_and_activate_vault<SUI>(
        &mut registry,
        vault_id,
        &admin_cap,
        true // activate immediately
    );
    
    // Verify vault was registered and activated
    let active_vaults = liquidity::get_active_vaults<SUI>(&registry);
    assert!(vector::length(&active_vaults) == 1, 0);
    assert!(*vector::borrow(&active_vaults, 0) == vault_id, 1);
    
    // Cleanup
    sui::test_utils::destroy(admin_cap);
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

// ===== Error Handling Tests =====

/// Test atomic operation failure scenarios
#[test]
#[expected_failure(abort_code = 2007, location = olend::account)]
fun test_atomic_operation_with_wrong_cap() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create two accounts
    let (mut account1, _cap1) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    let (_account2, cap2) = account::create_account_for_test(
        USER2, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Try to use wrong cap (should fail)
    account::atomic_update_level_and_points(
        &mut account1,
        &cap2, // Wrong cap
        5,
        100,
        test_scenario::ctx(&mut scenario)
    );
    
    // Cleanup (won't reach here due to expected failure)
    sui::test_utils::destroy(account1);
    sui::test_utils::destroy(_cap1);
    sui::test_utils::destroy(_account2);
    sui::test_utils::destroy(cap2);
    test_scenario::end(scenario);
}

/// Test batch operation with invalid position
#[test]
#[expected_failure(abort_code = 2011, location = olend::account)]
fun test_batch_operation_with_invalid_position() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Try to remove non-existent position
    let positions_to_add = vector::empty<object::ID>();
    let mut positions_to_remove = vector::empty<object::ID>();
    vector::push_back(&mut positions_to_remove, object::id_from_address(@0x123)); // Non-existent
    
    account::atomic_batch_position_update(
        &mut account,
        &account_cap,
        positions_to_add,
        positions_to_remove,
        test_scenario::ctx(&mut scenario)
    );
    
    // Cleanup (won't reach here due to expected failure)
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

// ===== Security Error Tests =====

/// Test rate limit enforcement failure
#[test]
#[expected_failure(abort_code = 2013, location = olend::account)]
fun test_rate_limit_enforcement_failure() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account with max operations already used
    let (mut account, account_cap) = account::create_account_with_security_for_test(
        USER1,
        constants::max_operations_per_window(), // At limit
        0, // suspicious_count
        test_scenario::ctx(&mut scenario)
    );
    
    // This should fail due to rate limit
    account::enforce_rate_limit(&mut account, &account_cap, test_scenario::ctx(&mut scenario));
    
    // Cleanup (won't reach here due to expected failure)
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test replay attack enforcement failure
#[test]
#[expected_failure(abort_code = 2014, location = olend::account)]
fun test_replay_attack_enforcement_failure() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account
    let (mut account, account_cap) = account::create_account_for_test(
        USER1, 
        test_scenario::ctx(&mut scenario)
    );
    
    // Create transaction hash
    let mut tx_hash = vector::empty<u8>();
    vector::push_back(&mut tx_hash, 1);
    vector::push_back(&mut tx_hash, 2);
    vector::push_back(&mut tx_hash, 3);
    
    // First use should succeed
    account::enforce_replay_protection(&mut account, &account_cap, tx_hash);
    
    // Second use should fail
    account::enforce_replay_protection(&mut account, &account_cap, tx_hash);
    
    // Cleanup (won't reach here due to expected failure)
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}

/// Test account restriction failure
#[test]
#[expected_failure(abort_code = 2016, location = olend::account)]
fun test_account_restriction_failure() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account at the restriction limit
    let (mut account, account_cap) = account::create_account_with_security_for_test(
        USER1,
        0, // operation_count
        constants::max_suspicious_activities(), // At restriction limit
        test_scenario::ctx(&mut scenario)
    );
    
    // This should fail due to account restriction
    account::comprehensive_security_check(
        &mut account,
        &account_cap,
        1, // deposit
        1000, // normal amount
        vector::empty<u8>(),
        test_scenario::ctx(&mut scenario)
    );
    
    // Cleanup (won't reach here due to expected failure)
    sui::test_utils::destroy(account);
    sui::test_utils::destroy(account_cap);
    test_scenario::end(scenario);
}