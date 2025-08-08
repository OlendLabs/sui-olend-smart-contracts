/// Module initialization tests
/// Tests the init and init_for_testing functions
#[test_only]
#[allow(duplicate_alias)]
module olend::test_init;

use sui::test_scenario;
use sui::object;
use std::option;

use olend::liquidity;
use olend::constants;

const ADMIN: address = @0xAD;

/// Test init_for_testing function
#[test]
fun test_init_for_testing() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Test init_for_testing function
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let mut registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    
    // Verify initialization
    assert!(liquidity::get_version(&registry) == constants::current_version(), 0);
    assert!(liquidity::get_admin_cap_id(&registry) == object::id(&admin_cap), 1);
    assert!(!liquidity::has_vaults<sui::sui::SUI>(&registry), 2);
    
    // Test that we can register a vault
    let vault_id = object::id_from_address(@0x1);
    liquidity::register_vault<sui::sui::SUI>(&mut registry, vault_id, &admin_cap);
    
    // Verify vault registration
    assert!(liquidity::has_vaults<sui::sui::SUI>(&registry), 3);
    assert!(option::is_some(&liquidity::get_default_vault<sui::sui::SUI>(&registry)), 4);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}

/// Test init_for_testing function consistency
#[test]
fun test_init_for_testing_consistency() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Test init_for_testing function (same as main test)
    liquidity::init_for_testing(test_scenario::ctx(&mut scenario));
    test_scenario::next_tx(&mut scenario, ADMIN);
    
    // Get shared Registry and AdminCap
    let registry = test_scenario::take_shared<liquidity::Registry>(&scenario);
    let admin_cap = test_scenario::take_from_sender<liquidity::LiquidityAdminCap>(&scenario);
    
    // Verify it works the same as the main create_test_registry function
    assert!(liquidity::get_version(&registry) == constants::current_version(), 0);
    assert!(liquidity::get_admin_cap_id(&registry) == object::id(&admin_cap), 1);
    
    // Cleanup
    test_scenario::return_shared(registry);
    test_scenario::return_to_sender(&scenario, admin_cap);
    test_scenario::end(scenario);
}