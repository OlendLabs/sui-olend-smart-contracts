/// Account module unit tests
/// Tests AccountRegistry creation, Account management, and permission control
#[test_only]
module olend::test_account;

use sui::test_scenario;

use olend::account;
use olend::constants;

const ADMIN: address = @0xAD;
const USER1: address = @0x1;
const USER2: address = @0x2;

/// Test AccountRegistry creation and initialization
#[test]
fun test_create_account_registry() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared AccountRegistry (no AdminCap in decentralized platform)
    let registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    
    // Verify initial state
    assert!(account::get_registry_version(&registry) == constants::current_version(), 0);
    assert!(account::get_account_count(&registry) == 0, 1);
    assert!(!account::account_exists(&registry, USER1), 2);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

/// Test account creation functionality
#[test]
fun test_create_account() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared AccountRegistry
    let mut registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    // No AdminCap in decentralized platform
    
    // Create account for USER1
    test_scenario::next_tx(&mut scenario, USER1);
    account::create_and_transfer_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // Get the objects back for testing
    test_scenario::next_tx(&mut scenario, USER1);
    let user_account = test_scenario::take_from_sender<account::Account>(&scenario);
    let user_cap = test_scenario::take_from_sender<account::AccountCap>(&scenario);
    
    // Verify account creation results
    assert!(account::get_owner(&user_account) == USER1, 0);
    assert!(account::get_level(&user_account) == constants::default_user_level(), 1);
    assert!(account::get_points(&user_account) == 0, 2);
    assert!(vector::length(&account::get_position_ids(&user_account)) == 0, 3);
    // Sub-account functionality removed from decentralized platform
    // Account is always active in decentralized platform
    
    // Verify AccountCap
    assert!(account::get_owner_from_cap(&user_cap) == USER1, 6);
    assert!(account::get_account_id_from_cap(&user_cap) == object::id(&user_account), 7);
    assert!(account::verify_account_cap(&user_account, &user_cap), 8);
    
    // Verify registry state
    assert!(account::account_exists(&registry, USER1), 9);
    assert!(account::get_account_count(&registry) == 1, 10);
    
    let account_id_opt = account::get_account(&registry, USER1);
    assert!(option::is_some(&account_id_opt), 11);
    assert!(*option::borrow(&account_id_opt) == object::id(&user_account), 12);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::return_shared(registry);
    // No AdminCap to destroy in decentralized platform
    test_scenario::end(scenario);
}

/// Test creating multiple accounts
#[test]
fun test_create_multiple_accounts() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared AccountRegistry
    let mut registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    // No AdminCap in decentralized platform
    
    // Create account for USER1
    test_scenario::next_tx(&mut scenario, USER1);
    account::create_and_transfer_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // Create account for USER2
    test_scenario::next_tx(&mut scenario, USER2);
    account::create_and_transfer_account(&mut registry, USER2, test_scenario::ctx(&mut scenario));
    
    // Get objects back for testing
    test_scenario::next_tx(&mut scenario, USER1);
    let user1_account = test_scenario::take_from_sender<account::Account>(&scenario);
    let user1_cap = test_scenario::take_from_sender<account::AccountCap>(&scenario);
    
    test_scenario::next_tx(&mut scenario, USER2);
    let user2_account = test_scenario::take_from_sender<account::Account>(&scenario);
    let user2_cap = test_scenario::take_from_sender<account::AccountCap>(&scenario);
    
    // Verify both accounts exist
    assert!(account::account_exists(&registry, USER1), 0);
    assert!(account::account_exists(&registry, USER2), 1);
    assert!(account::get_account_count(&registry) == 2, 2);
    
    // Verify account isolation
    assert!(account::get_owner(&user1_account) == USER1, 3);
    assert!(account::get_owner(&user2_account) == USER2, 4);
    assert!(object::id(&user1_account) != object::id(&user2_account), 5);
    
    // Verify capability isolation
    assert!(!account::verify_account_cap(&user1_account, &user2_cap), 6);
    assert!(!account::verify_account_cap(&user2_account, &user1_cap), 7);
    assert!(account::verify_account_cap(&user1_account, &user1_cap), 8);
    assert!(account::verify_account_cap(&user2_account, &user2_cap), 9);
    
    // Cleanup
    sui::test_utils::destroy(user1_account);
    sui::test_utils::destroy(user1_cap);
    sui::test_utils::destroy(user2_account);
    sui::test_utils::destroy(user2_cap);
    test_scenario::return_shared(registry);
    // No AdminCap to destroy in decentralized platform
    test_scenario::end(scenario);
}

/// Test position ID management
#[test]
fun test_position_management() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Create mock position IDs
    let position_id_1 = object::id_from_address(@0x101);
    let position_id_2 = object::id_from_address(@0x102);
    
    // Add first position
    account::add_position(&mut user_account, &user_cap, position_id_1);
    
    let position_ids = account::get_position_ids(&user_account);
    assert!(vector::length(&position_ids) == 1, 0);
    assert!(vector::contains(&position_ids, &position_id_1), 1);
    
    // Add second position
    account::add_position(&mut user_account, &user_cap, position_id_2);
    
    let position_ids = account::get_position_ids(&user_account);
    assert!(vector::length(&position_ids) == 2, 2);
    assert!(vector::contains(&position_ids, &position_id_1), 3);
    assert!(vector::contains(&position_ids, &position_id_2), 4);
    
    // Try to add duplicate position (should not add)
    account::add_position(&mut user_account, &user_cap, position_id_1);
    let position_ids = account::get_position_ids(&user_account);
    assert!(vector::length(&position_ids) == 2, 5); // Still 2, not 3
    
    // Remove first position
    account::remove_position(&mut user_account, &user_cap, position_id_1);
    
    let position_ids = account::get_position_ids(&user_account);
    assert!(vector::length(&position_ids) == 1, 6);
    assert!(!vector::contains(&position_ids, &position_id_1), 7);
    assert!(vector::contains(&position_ids, &position_id_2), 8);
    
    // Remove second position
    account::remove_position(&mut user_account, &user_cap, position_id_2);
    
    let position_ids = account::get_position_ids(&user_account);
    assert!(vector::length(&position_ids) == 0, 9);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test level and points management
#[test]
fun test_level_and_points_management() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Verify initial state
    assert!(account::get_level(&user_account) == constants::default_user_level(), 0);
    assert!(account::get_points(&user_account) == 0, 1);
    
    // Update level and points
    account::update_level_and_points(&mut user_account, &user_cap, 5, 1000);
    
    assert!(account::get_level(&user_account) == 5, 2);
    assert!(account::get_points(&user_account) == 1000, 3);
    
    // Update points again (accumulative)
    account::update_level_and_points(&mut user_account, &user_cap, 7, 500);
    
    assert!(account::get_level(&user_account) == 7, 4);
    assert!(account::get_points(&user_account) == 1500, 5);
    
    // Update to maximum level
    account::update_level_and_points(&mut user_account, &user_cap, constants::max_user_level(), 0);
    
    assert!(account::get_level(&user_account) == constants::max_user_level(), 6);
    assert!(account::get_points(&user_account) == 1500, 7);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test account activity update
#[test]
fun test_activity_update() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    let initial_status = account::get_status(&user_account);
    let initial_activity = account::get_status_last_activity(&initial_status);
    
    // Simulate time passing and update activity
    test_scenario::next_tx(&mut scenario, USER1);
    account::update_activity(&mut user_account, &user_cap, test_scenario::ctx(&mut scenario));
    
    let updated_status = account::get_status(&user_account);
    // Note: In test environment, timestamps might be the same, but the function should work
    assert!(account::get_status_last_activity(&updated_status) >= initial_activity, 0);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test account activity tracking (decentralized approach)
#[test]
fun test_account_activity_tracking() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Get initial status
    let status = account::get_status(&user_account);
    let creation_time = account::get_status_created_at(&status);
    let initial_activity = account::get_status_last_activity(&status);
    
    // Verify timestamps are reasonable (in test environment, timestamps can start from 0)
    assert!(creation_time >= 0, 0);
    assert!(initial_activity >= creation_time, 1);
    
    // Test account age calculation
    let current_time = creation_time + 1000; // 1 second later
    let age = account::get_account_age(&status, current_time);
    assert!(age == 1000, 2);
    
    // Test time since last activity
    let time_since_activity = account::get_time_since_last_activity(&status, current_time);
    assert!(time_since_activity == (current_time - initial_activity), 3);
    
    // Test recent activity check
    assert!(account::has_recent_activity(&user_account, current_time), 4);
    
    // Test with old activity (more than 30 days)
    let old_time = creation_time + (31 * 24 * 60 * 60 * 1000); // 31 days later
    assert!(!account::has_recent_activity(&user_account, old_time), 5);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

// ===== Error Condition Tests =====

/// Test creating duplicate account
#[test]
#[expected_failure(abort_code = 2008, location = olend::account)]
fun test_create_duplicate_account() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let mut registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    // No AdminCap in decentralized platform
    
    // Create first account
    test_scenario::next_tx(&mut scenario, USER1);
    let (user_account1, user_cap1) = account::create_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // Try to create duplicate account (should fail)
    let (user_account2, user_cap2) = account::create_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // This line should never be reached due to the expected failure
    sui::test_utils::destroy(user_account2);
    sui::test_utils::destroy(user_cap2);
    
    // Cleanup
    sui::test_utils::destroy(user_account1);
    sui::test_utils::destroy(user_cap1);
    test_scenario::return_shared(registry);
    // No AdminCap to return in decentralized platform
    test_scenario::end(scenario);
}

/// Test unauthorized position management
#[test]
#[expected_failure(abort_code = 2007, location = olend::account)]
fun test_unauthorized_position_management() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create accounts for testing
    let (mut user1_account, _user1_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, USER2);
    let (_user2_account, user2_cap) = account::create_account_for_test(USER2, test_scenario::ctx(&mut scenario));
    
    let position_id = object::id_from_address(@0x101);
    
    // Try to add position to user1's account using user2's capability (should fail)
    account::add_position(&mut user1_account, &user2_cap, position_id);
    
    // Cleanup
    sui::test_utils::destroy(user1_account);
    sui::test_utils::destroy(_user1_cap);
    sui::test_utils::destroy(_user2_account);
    sui::test_utils::destroy(user2_cap);
    test_scenario::end(scenario);
}

/// Test removing non-existent position
#[test]
#[expected_failure(abort_code = 2011, location = olend::account)]
fun test_remove_nonexistent_position() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    let position_id = object::id_from_address(@0x101);
    
    // Try to remove non-existent position (should fail)
    account::remove_position(&mut user_account, &user_cap, position_id);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test invalid level update
#[test]
#[expected_failure(abort_code = 9001, location = olend::account)]
fun test_invalid_level_update() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Try to set level above maximum (should fail)
    account::update_level_and_points(&mut user_account, &user_cap, constants::max_user_level() + 1, 0);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test operations on suspended account
#[test]
fun test_decentralized_account_operations() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Test that all operations work without centralized control
    let position_id1 = object::id_from_address(@0x101);
    let position_id2 = object::id_from_address(@0x102);
    
    // Add positions
    account::add_position(&mut user_account, &user_cap, position_id1);
    account::add_position(&mut user_account, &user_cap, position_id2);
    
    // Verify positions were added
    let positions = account::get_position_ids(&user_account);
    assert!(vector::length(&positions) == 2, 0);
    assert!(vector::contains(&positions, &position_id1), 1);
    assert!(vector::contains(&positions, &position_id2), 2);
    
    // Update level and points
    account::update_level_and_points(&mut user_account, &user_cap, 5, 1000);
    assert!(account::get_level(&user_account) == 5, 3);
    assert!(account::get_points(&user_account) == 1000, 4);
    
    // Update activity
    account::update_activity(&mut user_account, &user_cap, test_scenario::ctx(&mut scenario));
    
    // Remove a position
    account::remove_position(&mut user_account, &user_cap, position_id1);
    let positions = account::get_position_ids(&user_account);
    assert!(vector::length(&positions) == 1, 5);
    assert!(vector::contains(&positions, &position_id2), 6);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

// ===== Query Function Tests =====

/// Test comprehensive query functions
#[test]
fun test_query_functions() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let mut registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    // No AdminCap in decentralized platform
    
    // Test registry queries
    assert!(account::get_registry_version(&registry) == constants::current_version(), 0);
    assert!(account::get_account_count(&registry) == 0, 1);
    // No admin capability in decentralized platform
    
    // Create account
    test_scenario::next_tx(&mut scenario, USER1);
    account::create_and_transfer_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // Get objects back for testing
    test_scenario::next_tx(&mut scenario, USER1);
    let user_account = test_scenario::take_from_sender<account::Account>(&scenario);
    let user_cap = test_scenario::take_from_sender<account::AccountCap>(&scenario);
    
    // Test account queries
    assert!(account::get_owner(&user_account) == USER1, 3);
    assert!(account::get_level(&user_account) == constants::default_user_level(), 4);
    assert!(account::get_points(&user_account) == 0, 5);
    assert!(vector::length(&account::get_position_ids(&user_account)) == 0, 6);
    // Sub-account functionality removed from decentralized platform
    // Account is always active in decentralized platform
    
    // Test capability queries
    assert!(account::get_account_id_from_cap(&user_cap) == object::id(&user_account), 9);
    assert!(account::get_owner_from_cap(&user_cap) == USER1, 10);
    
    // Test status queries
    let status = account::get_status(&user_account);
    assert!(account::get_status_created_at(&status) >= 0, 11);
    assert!(account::get_status_last_activity(&status) >= 0, 12);
    
    // Test new activity tracking functions
    let current_time = account::get_status_created_at(&status) + 1000;
    assert!(account::get_account_age(&status, current_time) == 1000, 13);
    assert!(account::has_recent_activity(&user_account, current_time), 14);
    
    // Test registry queries after account creation
    assert!(account::get_account_count(&registry) == 1, 15);
    assert!(account::account_exists(&registry, USER1), 16);
    assert!(!account::account_exists(&registry, USER2), 17);
    
    let account_id_opt = account::get_account(&registry, USER1);
    assert!(option::is_some(&account_id_opt), 18);
    assert!(*option::borrow(&account_id_opt) == object::id(&user_account), 19);
    
    let no_account_opt = account::get_account(&registry, USER2);
    assert!(option::is_none(&no_account_opt), 20);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::return_shared(registry);
    // No AdminCap to destroy in decentralized platform
    test_scenario::end(scenario);
}

/// Test account capability verification
#[test]
fun test_account_cap_verification() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create two accounts for testing
    let (user1_account, user1_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    test_scenario::next_tx(&mut scenario, USER2);
    let (user2_account, user2_cap) = account::create_account_for_test(USER2, test_scenario::ctx(&mut scenario));
    
    // Test correct capability verification
    assert!(account::verify_account_cap(&user1_account, &user1_cap), 0);
    assert!(account::verify_account_cap(&user2_account, &user2_cap), 1);
    
    // Test incorrect capability verification
    assert!(!account::verify_account_cap(&user1_account, &user2_cap), 2);
    assert!(!account::verify_account_cap(&user2_account, &user1_cap), 3);
    
    // Cleanup
    sui::test_utils::destroy(user1_account);
    sui::test_utils::destroy(user1_cap);
    sui::test_utils::destroy(user2_account);
    sui::test_utils::destroy(user2_cap);
    test_scenario::end(scenario);
}

/// Test edge cases and boundary conditions
#[test]
fun test_edge_cases() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Test minimum level
    account::update_level_and_points(&mut user_account, &user_cap, 1, 0);
    assert!(account::get_level(&user_account) == 1, 0);
    
    // Test maximum level
    account::update_level_and_points(&mut user_account, &user_cap, constants::max_user_level(), 0);
    assert!(account::get_level(&user_account) == constants::max_user_level(), 1);
    
    // Test large points value
    account::update_level_and_points(&mut user_account, &user_cap, constants::max_user_level(), 1000000);
    assert!(account::get_points(&user_account) == 1000000, 2);
    
    // Test adding many positions
    let position_addresses = vector[
        @0x100, @0x101, @0x102, @0x103, @0x104,
        @0x105, @0x106, @0x107, @0x108, @0x109
    ];
    let mut i = 0;
    while (i < 10) {
        let position_id = object::id_from_address(*vector::borrow(&position_addresses, i));
        account::add_position(&mut user_account, &user_cap, position_id);
        i = i + 1;
    };
    
    let position_ids = account::get_position_ids(&user_account);
    assert!(vector::length(&position_ids) == 10, 3);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}
//
// ===== Upgrade Function Tests =====

/// Test AccountRegistry version tracking
#[test]
fun test_registry_version_tracking() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    
    // Verify initial version matches current protocol version
    let version = account::get_registry_version(&registry);
    assert!(version == constants::current_version(), 0);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

/// Test Account version consistency
#[test]
fun test_account_version_consistency() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Verify account functions normally with current version
    let _position_id = object::id_from_address(@0x101);
    
    // Test that account operations work correctly
    assert!(account::verify_account_cap(&user_account, &user_cap), 0);
    assert!(account::get_level(&user_account) == constants::default_user_level(), 1);
    assert!(account::get_points(&user_account) == 0, 2);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test version validation in upgrade functions
#[test]
fun test_version_validation() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    
    // Verify version is set correctly
    let version = account::get_registry_version(&registry);
    assert!(version == constants::current_version(), 0);
    assert!(version > 0, 1); // Version should be positive
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

// ===== Cross-Module Integration Tests =====

/// Test user identity verification for cross-module operations
#[test]
fun test_verify_user_identity() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let mut registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    
    // Create account for USER1
    test_scenario::next_tx(&mut scenario, USER1);
    account::create_and_transfer_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // Get the objects back for testing
    test_scenario::next_tx(&mut scenario, USER1);
    let user_account = test_scenario::take_from_sender<account::Account>(&scenario);
    let user_cap = test_scenario::take_from_sender<account::AccountCap>(&scenario);
    
    // Test successful identity verification
    assert!(account::verify_user_identity(&registry, &user_account, &user_cap), 0);
    
    // Test with non-existent user (create account without registering)
    let (fake_account, fake_cap) = account::create_account_for_test(USER2, test_scenario::ctx(&mut scenario));
    assert!(!account::verify_user_identity(&registry, &fake_account, &fake_cap), 1);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    sui::test_utils::destroy(fake_account);
    sui::test_utils::destroy(fake_cap);
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}

/// Test get user level for cross-module operations
#[test]
fun test_get_user_level_for_module() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Test getting initial level
    let initial_level = account::get_user_level_for_module(&user_account, &user_cap);
    assert!(initial_level == constants::default_user_level(), 0);
    
    // Update level and test again
    account::update_level_and_points(&mut user_account, &user_cap, 5, 1000);
    let updated_level = account::get_user_level_for_module(&user_account, &user_cap);
    assert!(updated_level == 5, 1);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test update user activity for cross-module operations
#[test]
fun test_update_user_activity_for_module() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Get initial activity time
    let status = account::get_status(&user_account);
    let initial_activity = account::get_status_last_activity(&status);
    
    // Simulate some time passing
    test_scenario::next_tx(&mut scenario, USER1);
    
    // Update activity from cross-module operation
    account::update_user_activity_for_module(&mut user_account, &user_cap, test_scenario::ctx(&mut scenario));
    
    // Verify activity was updated
    let updated_status = account::get_status(&user_account);
    let updated_activity = account::get_status_last_activity(&updated_status);
    assert!(updated_activity >= initial_activity, 0);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test add user points for cross-module operations
#[test]
fun test_add_user_points_for_module() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create account for testing
    let (mut user_account, user_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    
    // Verify initial points
    assert!(account::get_points(&user_account) == 0, 0);
    
    // Add points from cross-module operation
    account::add_user_points_for_module(&mut user_account, &user_cap, 500);
    assert!(account::get_points(&user_account) == 500, 1);
    
    // Add more points
    account::add_user_points_for_module(&mut user_account, &user_cap, 300);
    assert!(account::get_points(&user_account) == 800, 2);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::end(scenario);
}

/// Test cross-module operations with wrong capability (should fail)
#[test]
#[expected_failure(abort_code = 2007, location = olend::account)]
fun test_cross_module_wrong_capability() {
    let mut scenario = test_scenario::begin(USER1);
    
    // Create two accounts
    let (user1_account, _user1_cap) = account::create_account_for_test(USER1, test_scenario::ctx(&mut scenario));
    let (_user2_account, user2_cap) = account::create_account_for_test(USER2, test_scenario::ctx(&mut scenario));
    
    // Try to use USER2's capability on USER1's account (should fail)
    account::get_user_level_for_module(&user1_account, &user2_cap);
    
    // Cleanup
    sui::test_utils::destroy(user1_account);
    sui::test_utils::destroy(_user1_cap);
    sui::test_utils::destroy(_user2_account);
    sui::test_utils::destroy(user2_cap);
    test_scenario::end(scenario);
}

/// Test comprehensive cross-module integration scenario
#[test]
fun test_comprehensive_cross_module_integration() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize AccountRegistry for testing
    account::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    let mut registry = test_scenario::take_shared<account::AccountRegistry>(&scenario);
    
    // Create account for USER1
    test_scenario::next_tx(&mut scenario, USER1);
    account::create_and_transfer_account(&mut registry, USER1, test_scenario::ctx(&mut scenario));
    
    // Get the objects back for testing
    test_scenario::next_tx(&mut scenario, USER1);
    let mut user_account = test_scenario::take_from_sender<account::Account>(&scenario);
    let user_cap = test_scenario::take_from_sender<account::AccountCap>(&scenario);
    
    // Simulate a complete cross-module operation flow
    
    // 1. Verify user identity
    assert!(account::verify_user_identity(&registry, &user_account, &user_cap), 0);
    
    // 2. Get user level for fee calculation
    let user_level = account::get_user_level_for_module(&user_account, &user_cap);
    assert!(user_level == constants::default_user_level(), 1);
    
    // 3. Update user activity
    account::update_user_activity_for_module(&mut user_account, &user_cap, test_scenario::ctx(&mut scenario));
    
    // 4. Reward user with points
    let reward_points = if (user_level >= 5) { 100 } else { 50 };
    account::add_user_points_for_module(&mut user_account, &user_cap, reward_points);
    
    // 5. Verify final state
    assert!(account::get_points(&user_account) == 50, 2); // Default level gets 50 points
    
    // 6. Test level upgrade affects rewards
    account::update_level_and_points(&mut user_account, &user_cap, 7, 0);
    let new_level = account::get_user_level_for_module(&user_account, &user_cap);
    assert!(new_level == 7, 3);
    
    // 7. Add more points with higher level
    account::add_user_points_for_module(&mut user_account, &user_cap, 100);
    assert!(account::get_points(&user_account) == 150, 4);
    
    // Cleanup
    sui::test_utils::destroy(user_account);
    sui::test_utils::destroy(user_cap);
    test_scenario::return_shared(registry);
    test_scenario::end(scenario);
}