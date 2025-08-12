#[test_only]
module olend::security_infrastructure_test;

use sui::test_scenario::{Self};
use sui::clock::{Self};
use olend::security;
use olend::security_constants;
use olend::errors;

#[test]
fun test_security_event_emission() {
    let mut scenario = test_scenario::begin(@0x1);
    let ctx = test_scenario::ctx(&mut scenario);
    
    // Create a clock for testing
    let mut clock = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clock, 1000);
    
    // Test emitting a security event
    security::emit_security_event(
        b"TEST_EVENT",
        security::severity_medium(),
        @0x1,
        b"Test security event details",
        b"Test mitigation action",
        &clock
    );
    
    // Test oracle security event
    security::emit_oracle_security_event<u64>(
        b"PRICE_MANIPULATION",
        100,
        120,
        95,
        20,
        &clock
    );
    
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun test_security_constants() {
    // Test oracle security constants
    assert!(security_constants::max_price_staleness() == 300_000, 0);
    assert!(security_constants::min_confidence_threshold() == 95, 1);
    assert!(security_constants::max_price_deviation_per_block() == 1000, 2);
    
    // Test mathematical safety constants
    assert!(security_constants::precision_factor() == 10_000, 3);
    assert!(security_constants::min_division_value() == 1, 4);
    
    // Test access control constants
    assert!(security_constants::default_operation_delay() == 86_400_000, 5);
    assert!(security_constants::max_call_depth() == 10, 6);
    
    // Test validation functions
    assert!(security_constants::is_valid_time_delay(3600_000), 7);
    assert!(!security_constants::is_valid_time_delay(30_000), 8);
    assert!(security_constants::is_valid_confidence_threshold(95), 9);
    assert!(!security_constants::is_valid_confidence_threshold(30), 10);
}

#[test]
fun test_error_codes() {
    // Test security error codes are in correct range (5000-5999)
    assert!(errors::oracle_price_stale() == 5001, 0);
    assert!(errors::oracle_confidence_low() == 5002, 1);
    assert!(errors::price_manipulation_detected() == 5003, 2);
    assert!(errors::circuit_breaker_active() == 5004, 3);
    assert!(errors::reentrancy_detected() == 5005, 4);
    assert!(errors::flash_loan_attack() == 5006, 5);
    assert!(errors::math_overflow() == 5007, 6);
    assert!(errors::math_underflow() == 5008, 7);
    assert!(errors::access_denied() == 5009, 8);
    assert!(errors::operation_delayed() == 5010, 9);
}

#[test]
fun test_security_utility_functions() {
    let mut scenario = test_scenario::begin(@0x1);
    let ctx = test_scenario::ctx(&mut scenario);
    
    let mut clock = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clock, 1000);
    
    // Test security details creation
    let details = security::create_security_details(
        b"Test description",
        b"Additional data"
    );
    assert!(details.length() > 0, 0);
    
    // Test mitigation action creation
    let mitigation = security::create_mitigation_action(
        b"PAUSE_OPERATION",
        b"param1=value1"
    );
    assert!(mitigation.length() > 0, 1);
    
    // Test severity validation
    assert!(security::is_valid_severity(1), 2);
    assert!(security::is_valid_severity(4), 3);
    assert!(!security::is_valid_severity(0), 4);
    assert!(!security::is_valid_severity(5), 5);
    
    // Test immediate attention check
    assert!(!security::requires_immediate_attention(1), 6);
    assert!(!security::requires_immediate_attention(2), 7);
    assert!(security::requires_immediate_attention(3), 8);
    assert!(security::requires_immediate_attention(4), 9);
    
    // Test rate limiting logic
    assert!(!security::should_rate_limit(5, 3600_000, 10, 2000, 1000), 10);
    assert!(security::should_rate_limit(10, 3600_000, 10, 2000, 1000), 11);
    
    // Test security score calculation
    let score = security::calculate_security_score(90, 85, 2, 98);
    assert!(score > 0, 12);
    
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun test_security_config_validation() {
    // Test valid configuration
    assert!(security::validate_security_config(
        300_000,  // max_price_delay
        95,       // min_confidence
        1000,     // max_deviation
        10        // call_depth_limit
    ), 0);
    
    // Test invalid price delay (too short)
    assert!(!security::validate_security_config(
        30_000,   // too short
        95,
        1000,
        10
    ), 1);
    
    // Test invalid confidence (too low)
    assert!(!security::validate_security_config(
        300_000,
        30,       // too low
        1000,
        10
    ), 2);
    
    // Test invalid deviation (too high)
    assert!(!security::validate_security_config(
        300_000,
        95,
        6000,     // too high
        10
    ), 3);
    
    // Test invalid call depth (too high)
    assert!(!security::validate_security_config(
        300_000,
        95,
        1000,
        25        // too high
    ), 4);
}

#[test]
fun test_audit_trail_creation() {
    let mut scenario = test_scenario::begin(@0x1);
    let ctx = test_scenario::ctx(&mut scenario);
    
    let mut clock = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clock, 1000);
    
    // Test successful operation audit
    security::create_audit_trail(
        b"PARAMETER_CHANGE",
        @0x1,
        @0x2,
        b"interest_rate=5%",
        true,
        &clock
    );
    
    // Test failed operation audit
    security::create_audit_trail(
        b"EMERGENCY_PAUSE",
        @0x1,
        @0x2,
        b"reason=suspicious_activity",
        false,
        &clock
    );
    
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}