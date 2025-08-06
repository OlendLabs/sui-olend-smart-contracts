/// Registry module unit tests
/// Tests Registry creation, Vault management, and query functions
#[test_only]
#[allow(duplicate_alias)]
module olend::test_registry;

use sui::test_scenario;
use sui::object;
use std::vector;
use std::option;

use olend::liquidity;
use olend::constants;

// Mock asset types for testing
public struct TestCoin has drop {}
public struct AnotherCoin has drop {}

const ADMIN: address = @0xAD;

/// Test Registry creation and initialization
#[test]
fun test_create_registry() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // Verify initial state
    assert!(liquidity::get_version(&registry) == constants::current_version(), 0);
    assert!(liquidity::get_admin_cap_id(&registry) == object::id(&admin_cap), 1);
    assert!(!liquidity::has_vaults<TestCoin>(&registry), 2);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test Vault registration functionality
#[test]
fun test_register_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // Create mock Vault ID
    let vault_id = object::id_from_address(@0x1);
    
    // Register first Vault (automatically becomes default)
    liquidity::register_vault<TestCoin>(&mut registry, vault_id, &admin_cap);
    
    // Verify registration results
    assert!(liquidity::has_vaults<TestCoin>(&registry), 0);
    assert!(option::is_some(&liquidity::get_default_vault<TestCoin>(&registry)), 1);
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == vault_id, 2);
    
    let active_vaults = liquidity::get_active_vaults<TestCoin>(&registry);
    assert!(vector::length(&active_vaults) == 1, 3);
    assert!(*vector::borrow(&active_vaults, 0) == vault_id, 4);
    
    // 清理
    sui::test_utils::destroy(registry);
    sui::test_utils::destroy(admin_cap);
    test_scenario::end(scenario);
}

/// Test that only one Vault can exist per asset type
#[test]
fun test_single_vault_per_asset() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // 创建虚拟 Vault ID
    let vault_id_1 = object::id_from_address(@0x1);
    
    // 注册第一个 Vault（自动成为默认）
    liquidity::register_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap);
    
    // 验证第一个 Vault 注册成功
    let active_vaults = liquidity::get_active_vaults<TestCoin>(&registry);
    assert!(vector::length(&active_vaults) == 1, 0);
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == vault_id_1, 1);
    assert!(liquidity::is_vault_active<TestCoin>(&registry, vault_id_1), 2);
    
    // 测试暂停和恢复功能
    liquidity::pause_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap);
    
    // 验证暂停状态
    assert!(!liquidity::is_vault_active<TestCoin>(&registry, vault_id_1), 3);
    assert!(option::is_none(&liquidity::get_default_vault<TestCoin>(&registry)), 4);
    
    let paused_vaults = liquidity::get_paused_vaults<TestCoin>(&registry);
    assert!(vector::length(&paused_vaults) == 1, 5);
    assert!(*vector::borrow(&paused_vaults, 0) == vault_id_1, 6);
    
    // 恢复 Vault
    liquidity::resume_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap, true);
    
    // 验证恢复状态
    assert!(liquidity::is_vault_active<TestCoin>(&registry, vault_id_1), 7);
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == vault_id_1, 8);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test Vault management for different asset types
#[test]
fun test_different_asset_types() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // 为不同资产类型创建 Vault
    let test_vault_id = object::id_from_address(@0x1);
    let another_vault_id = object::id_from_address(@0x2);
    
    // 注册 TestCoin 的 Vault
    liquidity::register_vault<TestCoin>(&mut registry, test_vault_id, &admin_cap);
    
    // 注册 AnotherCoin 的 Vault
    liquidity::register_vault<AnotherCoin>(&mut registry, another_vault_id, &admin_cap);
    
    // 验证两种资产类型都有 Vault
    assert!(liquidity::has_vaults<TestCoin>(&registry), 0);
    assert!(liquidity::has_vaults<AnotherCoin>(&registry), 1);
    
    // 验证默认 Vault 设置正确
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == test_vault_id, 2);
    assert!(*option::borrow(&liquidity::get_default_vault<AnotherCoin>(&registry)) == another_vault_id, 3);
    
    // 验证活跃状态
    assert!(liquidity::is_vault_active<TestCoin>(&registry, test_vault_id), 4);
    assert!(liquidity::is_vault_active<AnotherCoin>(&registry, another_vault_id), 5);
    
    // 验证跨类型隔离
    assert!(!liquidity::is_vault_active<TestCoin>(&registry, another_vault_id), 6);
    assert!(!liquidity::is_vault_active<AnotherCoin>(&registry, test_vault_id), 7);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test Vault pause functionality
#[test]
fun test_pause_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // 注册一个 Vault
    let vault_id_1 = object::id_from_address(@0x1);
    
    liquidity::register_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap);
    
    // 验证 Vault 注册成功并成为默认
    assert!(liquidity::is_vault_active<TestCoin>(&registry, vault_id_1), 0);
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == vault_id_1, 1);
    
    // 暂停 Vault
    liquidity::pause_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap);
    
    // 验证暂停结果
    assert!(!liquidity::is_vault_active<TestCoin>(&registry, vault_id_1), 2);
    
    // 验证默认 Vault 已被清除
    assert!(option::is_none(&liquidity::get_default_vault<TestCoin>(&registry)), 3);
    
    // 验证暂停列表
    let paused_vaults = liquidity::get_paused_vaults<TestCoin>(&registry);
    assert!(vector::length(&paused_vaults) == 1, 4);
    assert!(*vector::borrow(&paused_vaults, 0) == vault_id_1, 5);
    
    // 验证活跃列表为空
    let active_vaults = liquidity::get_active_vaults<TestCoin>(&registry);
    assert!(vector::length(&active_vaults) == 0, 6);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test Vault resume functionality
#[test]
fun test_resume_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // 注册并暂停一个 Vault
    let vault_id = object::id_from_address(@0x1);
    liquidity::register_vault<TestCoin>(&mut registry, vault_id, &admin_cap);
    liquidity::pause_vault<TestCoin>(&mut registry, vault_id, &admin_cap);
    
    // 验证暂停状态
    assert!(!liquidity::is_vault_active<TestCoin>(&registry, vault_id), 0);
    
    // 恢复 Vault 并设置为默认
    liquidity::resume_vault<TestCoin>(&mut registry, vault_id, &admin_cap, true);
    
    // 验证恢复结果
    assert!(liquidity::is_vault_active<TestCoin>(&registry, vault_id), 1);
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == vault_id, 2);
    
    // 验证列表状态
    let active_vaults = liquidity::get_active_vaults<TestCoin>(&registry);
    let paused_vaults = liquidity::get_paused_vaults<TestCoin>(&registry);
    
    assert!(vector::length(&active_vaults) == 1, 3);
    assert!(vector::length(&paused_vaults) == 0, 4);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test setting default Vault
#[test]
fun test_set_default_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // 注册一个 Vault（自动成为默认）
    let vault_id_1 = object::id_from_address(@0x1);
    
    liquidity::register_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap);
    
    // 验证初始默认 Vault
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == vault_id_1, 0);
    
    // 由于现在只能有一个活跃的 Vault，set_default_vault 函数在这种情况下
    // 实际上没有太大意义，因为唯一的活跃 Vault 就是默认的
    // 但我们仍然可以测试函数调用是否正常工作
    liquidity::set_default_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap);
    
    // 验证默认 Vault 仍然是同一个
    assert!(*option::borrow(&liquidity::get_default_vault<TestCoin>(&registry)) == vault_id_1, 1);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test permission verification - unauthorized admin attempts
#[test]
#[expected_failure(abort_code = 1007)]
fun test_unauthorized_access() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let _admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // Create another Registry with different AdminCap (simulate unauthorized user)
    test_scenario::next_tx(&mut scenario, @0x999); // Different user
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, @0x999);
    
    let fake_registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let fake_admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    let vault_id = object::id_from_address(@0x1);
    
    // 尝试使用假的 AdminCap 注册 Vault（应该失败）
    liquidity::register_vault<TestCoin>(&mut registry, vault_id, &fake_admin_cap);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, _admin_cap);
    test_scenario::return_shared(fake_registry);
    test_scenario::return_to_sender(&scenario, fake_admin_cap);
    test_scenario::end(scenario);
}

/// Test pausing non-existent Vault
#[test]
#[expected_failure(abort_code = 1002)]
fun test_pause_nonexistent_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    let vault_id = object::id_from_address(@0x1);
    
    // 尝试暂停不存在的 Vault（应该失败）
    liquidity::pause_vault<TestCoin>(&mut registry, vault_id, &admin_cap);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test setting inactive Vault as default
#[test]
#[expected_failure(abort_code = 1008)]
fun test_set_inactive_vault_as_default() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // 注册并暂停一个 Vault
    let vault_id = object::id_from_address(@0x1);
    liquidity::register_vault<TestCoin>(&mut registry, vault_id, &admin_cap);
    liquidity::pause_vault<TestCoin>(&mut registry, vault_id, &admin_cap);
    
    // 尝试设置暂停的 Vault 为默认（应该失败）
    liquidity::set_default_vault<TestCoin>(&mut registry, vault_id, &admin_cap);
    
    // 清理
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test that registering a second active Vault fails
#[test]
#[expected_failure(abort_code = 1013)]
fun test_cannot_register_second_active_vault() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize Registry for testing
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::AdminCap>(&scenario);
    
    // Register first Vault
    let vault_id_1 = object::id_from_address(@0x1);
    liquidity::register_vault<TestCoin>(&mut registry, vault_id_1, &admin_cap);
    
    // Try to register second Vault (should fail)
    let vault_id_2 = object::id_from_address(@0x2);
    liquidity::register_vault<TestCoin>(&mut registry, vault_id_2, &admin_cap);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}