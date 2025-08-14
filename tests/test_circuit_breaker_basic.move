/// Basic Circuit Breaker Tests
/// Simplified tests for circuit breaker functionality
#[test_only]
module olend::test_circuit_breaker_basic;

use sui::test_scenario::{Self, next_tx, ctx};
use sui::clock;
use sui::test_utils;

use olend::secure_oracle::{Self, SecurityAdminCap};
use olend::oracle::{Self, PriceOracle};

// Test asset type
public struct USDC has drop {}

const ADMIN: address = @0xAD;

/// Test basic circuit breaker configuration
#[test]
fun test_circuit_breaker_basic_configuration() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    let oracle_admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
    
    // Get shared oracle
    next_tx(&mut scenario, ADMIN);
    let oracle = test_scenario::take_shared<PriceOracle>(&scenario);
    
    // Create secure oracle
    let mut secure_oracle = secure_oracle::create_secure_oracle(&oracle, &oracle_admin_cap, ctx(&mut scenario));
    
    // Configure price feed with circuit breaker enabled
    secure_oracle::configure_enhanced_price_feed<USDC>(
        &mut secure_oracle,
        &oracle_admin_cap,
        b"test_feed_id",
        6, // decimals
        60, // heartbeat
        500, // 5% deviation threshold
        95, // 95% confidence threshold
        300, // 5 minutes max staleness
        true, // circuit breaker enabled
        true, // validation enabled
        ctx(&mut scenario)
    );
    
    // Test accessor functions
    assert!(secure_oracle::is_circuit_breaker_enabled<USDC>(&secure_oracle), 0);
    assert!(secure_oracle::get_circuit_breaker_threshold(&secure_oracle) == 2000, 0); // Default 20%
    assert!(!secure_oracle::get_emergency_mode_status(&secure_oracle), 0);
    
    // Clean up
    test_scenario::return_shared(oracle);
    test_utils::destroy(secure_oracle);
    test_utils::destroy(oracle_admin_cap);
    test_scenario::end(scenario);
}

/// Test circuit breaker price deviation activation
#[test]
fun test_circuit_breaker_price_activation() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create clock
    let mut clock = clock::create_for_testing(ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000000);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    let oracle_admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
    
    // Get shared oracle
    next_tx(&mut scenario, ADMIN);
    let oracle = test_scenario::take_shared<PriceOracle>(&scenario);
    
    // Create secure oracle
    let mut secure_oracle = secure_oracle::create_secure_oracle(&oracle, &oracle_admin_cap, ctx(&mut scenario));
    
    // Configure price feed with circuit breaker enabled
    secure_oracle::configure_enhanced_price_feed<USDC>(
        &mut secure_oracle,
        &oracle_admin_cap,
        b"test_feed_id",
        6,
        60,
        500,
        95,
        300,
        true, // circuit breaker enabled
        true,
        ctx(&mut scenario)
    );
    
    // Test circuit breaker activation with 25% price change (exceeds 20% threshold)
    let should_activate = secure_oracle::check_and_activate_circuit_breaker<USDC>(
        &mut secure_oracle,
        2500, // 25% price change in basis points
        &clock
    );
    
    assert!(should_activate, 0);
    
    // Clean up
    test_scenario::return_shared(oracle);
    test_utils::destroy(secure_oracle);
    test_utils::destroy(oracle_admin_cap);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

/// Test circuit breaker confidence drop activation
#[test]
fun test_circuit_breaker_confidence_activation() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create clock
    let mut clock = clock::create_for_testing(ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000000);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    let oracle_admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
    
    // Get shared oracle
    next_tx(&mut scenario, ADMIN);
    let oracle = test_scenario::take_shared<PriceOracle>(&scenario);
    
    // Create secure oracle
    let mut secure_oracle = secure_oracle::create_secure_oracle(&oracle, &oracle_admin_cap, ctx(&mut scenario));
    
    // Configure price feed
    secure_oracle::configure_enhanced_price_feed<USDC>(
        &mut secure_oracle,
        &oracle_admin_cap,
        b"test_feed_id",
        6,
        60,
        500,
        95,
        300,
        true, // circuit breaker enabled
        true,
        ctx(&mut scenario)
    );
    
    // Test confidence drop circuit breaker (95% -> 70% = 25 point drop)
    let should_activate = secure_oracle::check_confidence_circuit_breaker<USDC>(
        &mut secure_oracle,
        70, // current confidence
        95, // previous confidence
        &clock
    );
    
    assert!(should_activate, 0);
    
    // Clean up
    test_scenario::return_shared(oracle);
    test_utils::destroy(secure_oracle);
    test_utils::destroy(oracle_admin_cap);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

/// Test emergency circuit breaker activation and deactivation
#[test]
fun test_emergency_circuit_breaker() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create clock
    let mut clock = clock::create_for_testing(ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000000);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    let oracle_admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
    
    // Get shared oracle
    next_tx(&mut scenario, ADMIN);
    let oracle = test_scenario::take_shared<PriceOracle>(&scenario);
    
    // Create secure oracle
    let mut secure_oracle = secure_oracle::create_secure_oracle(&oracle, &oracle_admin_cap, ctx(&mut scenario));
    
    // Get security admin cap
    next_tx(&mut scenario, ADMIN);
    let security_admin_cap = test_scenario::take_from_sender<SecurityAdminCap>(&scenario);
    
    // Test emergency circuit breaker activation
    secure_oracle::activate_emergency_circuit_breaker(
        &mut secure_oracle,
        &security_admin_cap,
        b"System-wide security threat detected",
        &clock,
        ctx(&mut scenario)
    );
    
    // Verify emergency mode is active
    assert!(secure_oracle::get_emergency_mode_status(&secure_oracle), 0);
    
    // Advance time
    clock::increment_for_testing(&mut clock, 3600000); // 1 hour
    
    // Deactivate emergency circuit breaker
    secure_oracle::deactivate_emergency_circuit_breaker(
        &mut secure_oracle,
        &security_admin_cap,
        &clock,
        ctx(&mut scenario)
    );
    
    // Verify emergency mode is deactivated
    assert!(!secure_oracle::get_emergency_mode_status(&secure_oracle), 0);
    
    // Clean up
    test_scenario::return_to_sender(&scenario, security_admin_cap);
    test_scenario::return_shared(oracle);
    test_utils::destroy(secure_oracle);
    test_utils::destroy(oracle_admin_cap);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

/// Test circuit breaker disabled configuration
#[test]
fun test_circuit_breaker_disabled() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create clock
    let mut clock = clock::create_for_testing(ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1000000);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    let oracle_admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
    
    // Get shared oracle
    next_tx(&mut scenario, ADMIN);
    let oracle = test_scenario::take_shared<PriceOracle>(&scenario);
    
    // Create secure oracle
    let mut secure_oracle = secure_oracle::create_secure_oracle(&oracle, &oracle_admin_cap, ctx(&mut scenario));
    
    // Configure price feed with circuit breaker disabled
    secure_oracle::configure_enhanced_price_feed<USDC>(
        &mut secure_oracle,
        &oracle_admin_cap,
        b"test_feed_id",
        6,
        60,
        500,
        95,
        300,
        false, // circuit breaker disabled
        true,
        ctx(&mut scenario)
    );
    
    // Test that circuit breaker doesn't activate when disabled
    let should_activate = secure_oracle::check_and_activate_circuit_breaker<USDC>(
        &mut secure_oracle,
        2500, // 25% price change
        &clock
    );
    
    assert!(!should_activate, 0);
    assert!(!secure_oracle::is_circuit_breaker_enabled<USDC>(&secure_oracle), 0);
    
    // Clean up
    test_scenario::return_shared(oracle);
    test_utils::destroy(secure_oracle);
    test_utils::destroy(oracle_admin_cap);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

/// Test circuit breaker state and config accessors
#[test]
fun test_circuit_breaker_accessors() {
    // Test circuit breaker state creation and accessor functions
    let state = secure_oracle::create_circuit_breaker_state(
        true,  // is_active
        1000,  // activation_time
        1,     // trigger_type (price deviation)
        2500,  // trigger_value (25%)
        4600,  // recovery_time
        1,     // activation_count
        500    // last_reset_time
    );
    
    // Test accessor functions
    assert!(secure_oracle::circuit_breaker_state_is_active(&state), 0);
    assert!(secure_oracle::circuit_breaker_state_activation_time(&state) == 1000, 0);
    assert!(secure_oracle::circuit_breaker_state_trigger_type(&state) == 1, 0);
    assert!(secure_oracle::circuit_breaker_state_trigger_value(&state) == 2500, 0);
    assert!(secure_oracle::circuit_breaker_state_recovery_time(&state) == 4600, 0);
    assert!(secure_oracle::circuit_breaker_state_activation_count(&state) == 1, 0);
    
    // Test circuit breaker config creation and accessor functions
    let config = secure_oracle::create_circuit_breaker_config(
        true,  // enabled
        1000,  // price_deviation_threshold
        20,    // confidence_drop_threshold
        2,     // manipulation_threshold
        3600,  // recovery_duration
        5,     // max_activations_per_hour
        false  // emergency_override
    );
    
    // Test accessor functions
    assert!(secure_oracle::circuit_breaker_config_enabled(&config), 0);
    assert!(secure_oracle::circuit_breaker_config_price_deviation_threshold(&config) == 1000, 0);
    assert!(secure_oracle::circuit_breaker_config_confidence_drop_threshold(&config) == 20, 0);
    assert!(secure_oracle::circuit_breaker_config_manipulation_threshold(&config) == 2, 0);
    assert!(secure_oracle::circuit_breaker_config_recovery_duration(&config) == 3600, 0);
}