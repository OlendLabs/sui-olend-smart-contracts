/// Basic functionality tests
#[test_only]
module olend::basic_tests;

use olend::constants;
use olend::utils;
use olend::errors;
    
#[test]
fun test_basic_functions() {
    // Test version compatibility
    assert!(utils::is_version_compatible(2, 1), 0);
    assert!(utils::is_version_compatible(1, 1), 0);
    assert!(!utils::is_version_compatible(1, 2), 0);
    
    // Test user level validation
    assert!(utils::is_valid_user_level(1), 0);
    assert!(utils::is_valid_user_level(5), 0);
    assert!(utils::is_valid_user_level(10), 0);
    assert!(!utils::is_valid_user_level(0), 0);
    assert!(!utils::is_valid_user_level(11), 0);
    
    // Test allowance type validation
    assert!(utils::is_valid_allowance_type(constants::allowance_type_lending()), 0);
    assert!(utils::is_valid_allowance_type(constants::allowance_type_borrowing()), 0);
    assert!(utils::is_valid_allowance_type(constants::allowance_type_trading()), 0);
    assert!(utils::is_valid_allowance_type(constants::allowance_type_withdrawal()), 0);
    assert!(!utils::is_valid_allowance_type(0), 0);
    assert!(!utils::is_valid_allowance_type(5), 0);
}

#[test]
fun test_constants_access() {
    // Test constants access functions
    assert!(constants::current_version() > 0, 0);
    assert!(constants::max_daily_withdrawal_limit() > 0, 0);
    assert!(constants::default_user_level() >= 1, 0);
    assert!(constants::max_user_level() >= constants::default_user_level(), 0);
    assert!(constants::seconds_per_day() == 86400, 0);
    
    // Test uniqueness of allowance type constants
    assert!(constants::allowance_type_lending() != constants::allowance_type_borrowing(), 0);
    assert!(constants::allowance_type_lending() != constants::allowance_type_trading(), 0);
    assert!(constants::allowance_type_lending() != constants::allowance_type_withdrawal(), 0);
    assert!(constants::allowance_type_borrowing() != constants::allowance_type_trading(), 0);
    assert!(constants::allowance_type_borrowing() != constants::allowance_type_withdrawal(), 0);
    assert!(constants::allowance_type_trading() != constants::allowance_type_withdrawal(), 0);
}

#[test]
fun test_error_codes_access() {
    // Test error code access functions
    assert!(errors::vault_paused() == 1001, 0);
    assert!(errors::vault_not_found() == 1002, 0);
    assert!(errors::insufficient_assets() == 1003, 0);
    assert!(errors::account_not_found() == 2001, 0);
    assert!(errors::account_suspended() == 2002, 0);
    assert!(errors::insufficient_allowance() == 2003, 0);
    assert!(errors::invalid_input() == 9001, 0);
    assert!(errors::operation_denied() == 9002, 0);
}

#[test]
fun test_version_info() {
    // Test version info creation
    let _version = utils::create_version_info(1, 2, 3);
    // Version info creation successful, no additional assertions needed, compilation success indicates success
}