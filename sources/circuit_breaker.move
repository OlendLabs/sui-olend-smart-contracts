/// System-wide Circuit Breaker Module
/// Provides comprehensive circuit breaker functionality for all protocol operations
/// Built on top of the secure oracle circuit breaker foundation
module olend::circuit_breaker;


use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::event;

use olend::errors;

use olend::security_constants;
use olend::safe_math;

// ===== Circuit Breaker Registry Structure =====

/// System-wide circuit breaker registry
public struct CircuitBreakerRegistry has key {
    id: UID,
    version: u64,
    
    // Circuit breaker states per operation type
    breakers: Table<vector<u8>, CircuitBreakerState>,
    
    // Global emergency controls
    global_emergency: bool,
    emergency_triggered_time: u64,
    
    // Thresholds and configurations
    operation_thresholds: Table<vector<u8>, ThresholdConfig>,
    
    // Recovery mechanisms
    recovery_conditions: Table<vector<u8>, RecoveryConfig>,
    
    // Admin controls
    admin_cap_id: ID,
}

/// Circuit breaker state for individual operations
public struct CircuitBreakerState has store, copy, drop {
    is_open: bool,
    failure_count: u64,
    last_failure_time: u64,
    last_success_time: u64,
    state_change_time: u64,
    consecutive_failures: u64,
    total_operations: u64,
    success_rate: u64, // In basis points (10000 = 100%)
}

/// Threshold configuration for circuit breaker activation
public struct ThresholdConfig has store, copy, drop {
    failure_threshold: u64,        // Number of failures to trigger
    time_window: u64,              // Time window for failure counting (seconds)
    recovery_timeout: u64,         // Time before attempting recovery (seconds)
    volume_threshold: u64,         // Volume threshold for activation
    success_rate_threshold: u64,   // Minimum success rate (basis points)
}

/// Recovery configuration for circuit breaker
public struct RecoveryConfig has store, copy, drop {
    auto_recovery_enabled: bool,
    recovery_test_count: u64,      // Number of test operations for recovery
    recovery_success_rate: u64,    // Required success rate for recovery (basis points)
    max_recovery_attempts: u64,    // Maximum recovery attempts per day
    recovery_attempts_today: u64,  // Current recovery attempts
    last_recovery_attempt: u64,    // Timestamp of last recovery attempt
}

/// Circuit breaker admin capability
public struct CircuitBreakerAdminCap has key, store {
    id: UID,
}

// ===== Events =====

/// Circuit breaker state change event
public struct CircuitBreakerStateChangeEvent has copy, drop {
    operation_type: vector<u8>,
    old_state: bool, // false = closed, true = open
    new_state: bool,
    trigger_reason: vector<u8>,
    failure_count: u64,
    timestamp: u64,
}

/// Circuit breaker operation blocked event
public struct CircuitBreakerBlockedEvent has copy, drop {
    operation_type: vector<u8>,
    caller: address,
    reason: vector<u8>,
    timestamp: u64,
}

/// Circuit breaker recovery event
public struct CircuitBreakerRecoveryEvent has copy, drop {
    operation_type: vector<u8>,
    recovery_type: u8, // 0=auto, 1=manual, 2=test
    success: bool,
    timestamp: u64,
}

// ===== Error Constants =====

const E_OPERATION_NOT_CONFIGURED: u64 = 6003;
const E_INVALID_THRESHOLD_CONFIG: u64 = 6004;

// ===== Operation Type Constants =====

const OPERATION_BORROW: vector<u8> = b"BORROW";
const OPERATION_REPAY: vector<u8> = b"REPAY";
const OPERATION_LIQUIDATE: vector<u8> = b"LIQUIDATE";
const OPERATION_ORACLE_UPDATE: vector<u8> = b"ORACLE_UPDATE";
const OPERATION_VAULT_DEPOSIT: vector<u8> = b"VAULT_DEPOSIT";
const OPERATION_VAULT_WITHDRAW: vector<u8> = b"VAULT_WITHDRAW";

// ===== Initialization =====

/// Initialize circuit breaker system
fun init(ctx: &mut TxContext) {
    let admin_cap = CircuitBreakerAdminCap { id: object::new(ctx) };
    transfer::transfer(admin_cap, tx_context::sender(ctx));
}

/// Create and share circuit breaker registry
public fun create_and_share_registry(
    admin_cap: &CircuitBreakerAdminCap,
    ctx: &mut TxContext
) {
    let registry = create_registry(admin_cap, ctx);
    transfer::share_object(registry);
}

/// Create circuit breaker registry
public fun create_registry(
    admin_cap: &CircuitBreakerAdminCap,
    ctx: &mut TxContext
): CircuitBreakerRegistry {
    CircuitBreakerRegistry {
        id: object::new(ctx),
        version: security_constants::current_security_version(),
        breakers: table::new(ctx),
        global_emergency: false,
        emergency_triggered_time: 0,
        operation_thresholds: table::new(ctx),
        recovery_conditions: table::new(ctx),
        admin_cap_id: object::id(admin_cap),
    }
}

// ===== Configuration Functions =====

/// Configure circuit breaker for an operation type
public fun configure_circuit_breaker(
    registry: &mut CircuitBreakerRegistry,
    admin_cap: &CircuitBreakerAdminCap,
    operation_type: vector<u8>,
    threshold_config: ThresholdConfig,
    recovery_config: RecoveryConfig,
    _ctx: &TxContext
) {
    // Verify admin permissions
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Validate configuration
    assert!(threshold_config.failure_threshold > 0, E_INVALID_THRESHOLD_CONFIG);
    assert!(threshold_config.time_window > 0, E_INVALID_THRESHOLD_CONFIG);
    assert!(threshold_config.recovery_timeout > 0, E_INVALID_THRESHOLD_CONFIG);
    assert!(threshold_config.success_rate_threshold <= 10000, E_INVALID_THRESHOLD_CONFIG);
    
    // Add or update threshold configuration
    if (table::contains(&registry.operation_thresholds, operation_type)) {
        let existing_config = table::borrow_mut(&mut registry.operation_thresholds, operation_type);
        *existing_config = threshold_config;
    } else {
        table::add(&mut registry.operation_thresholds, operation_type, threshold_config);
    };
    
    // Add or update recovery configuration
    if (table::contains(&registry.recovery_conditions, operation_type)) {
        let existing_recovery = table::borrow_mut(&mut registry.recovery_conditions, operation_type);
        *existing_recovery = recovery_config;
    } else {
        table::add(&mut registry.recovery_conditions, operation_type, recovery_config);
    };
    
    // Initialize circuit breaker state if not exists
    if (!table::contains(&registry.breakers, operation_type)) {
        let initial_state = CircuitBreakerState {
            is_open: false,
            failure_count: 0,
            last_failure_time: 0,
            last_success_time: 0,
            state_change_time: 0,
            consecutive_failures: 0,
            total_operations: 0,
            success_rate: 10000, // 100% initially
        };
        table::add(&mut registry.breakers, operation_type, initial_state);
    };
}

// ===== Circuit Breaker Check Functions =====

/// Check if operation is allowed (main entry point)
public fun check_operation_allowed(
    registry: &CircuitBreakerRegistry,
    operation_type: vector<u8>,
    caller: address,
    clock: &Clock,
): bool {
    // Check global emergency first
    if (registry.global_emergency) {
        emit_blocked_event(operation_type, caller, b"Global emergency active", clock);
        return false
    };
    
    // Check if operation is configured
    if (!table::contains(&registry.breakers, operation_type)) {
        // If not configured, allow operation (fail-open for unconfigured operations)
        return true
    };
    
    let breaker_state = table::borrow(&registry.breakers, operation_type);
    
    // If circuit breaker is open, block operation
    if (breaker_state.is_open) {
        // Check if recovery timeout has passed
        let current_time = clock::timestamp_ms(clock) / 1000;
        let threshold_config = table::borrow(&registry.operation_thresholds, operation_type);
        
        if (current_time - breaker_state.state_change_time >= threshold_config.recovery_timeout) {
            // Recovery timeout passed, but don't automatically close - require explicit recovery
            emit_blocked_event(operation_type, caller, b"Circuit breaker open - recovery timeout passed", clock);
        } else {
            emit_blocked_event(operation_type, caller, b"Circuit breaker open", clock);
        };
        return false
    };
    
    true
}

/// Record operation result and update circuit breaker state
public fun record_operation_result(
    registry: &mut CircuitBreakerRegistry,
    operation_type: vector<u8>,
    success: bool,
    clock: &Clock,
) {
    // Skip if operation not configured
    if (!table::contains(&registry.breakers, operation_type)) {
        return
    };
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    let breaker_state = table::borrow_mut(&mut registry.breakers, operation_type);
    let threshold_config = table::borrow(&registry.operation_thresholds, operation_type);
    
    // Update operation statistics
    breaker_state.total_operations = safe_math::safe_add(breaker_state.total_operations, 1);
    
    if (success) {
        // Reset consecutive failures on success
        breaker_state.consecutive_failures = 0;
        breaker_state.last_success_time = current_time;
        
        // Update success rate
        update_success_rate(breaker_state, true);
    } else {
        // Increment failure counters
        breaker_state.failure_count = safe_math::safe_add(breaker_state.failure_count, 1);
        breaker_state.consecutive_failures = safe_math::safe_add(breaker_state.consecutive_failures, 1);
        breaker_state.last_failure_time = current_time;
        
        // Update success rate
        update_success_rate(breaker_state, false);
        
        // Check if circuit breaker should be triggered
        check_and_trigger_inline(breaker_state, threshold_config, current_time, operation_type);
    };
}

/// Update success rate based on recent operations
fun update_success_rate(state: &mut CircuitBreakerState, success: bool) {
    // Simple moving average approach - weight recent operations more heavily
    let current_rate = state.success_rate;
    let weight = 100; // Weight for new operation (out of 10000)
    
    let new_operation_rate = if (success) 10000 else 0;
    let weighted_new = safe_math::safe_mul_div(new_operation_rate, weight, 10000);
    let weighted_old = safe_math::safe_mul_div(current_rate, safe_math::safe_sub(10000, weight), 10000);
    
    state.success_rate = safe_math::safe_add(weighted_new, weighted_old);
}

/// Result of circuit breaker trigger check
public struct TriggerResult has drop {
    should_trigger: bool,
    trigger_reason: vector<u8>,
}



/// Check and trigger circuit breaker inline to avoid borrowing issues
fun check_and_trigger_inline(
    state: &mut CircuitBreakerState,
    config: &ThresholdConfig,
    current_time: u64,
    operation_type: vector<u8>,
) {
    let mut should_trigger = false;
    let mut trigger_reason = b"";
    
    // Check consecutive failure threshold
    if (state.consecutive_failures >= config.failure_threshold) {
        should_trigger = true;
        trigger_reason = b"Consecutive failure threshold exceeded";
    }
    // Check success rate threshold
    else if (state.success_rate < config.success_rate_threshold && state.total_operations >= 10) {
        should_trigger = true;
        trigger_reason = b"Success rate below threshold";
    }
    // Check time-based failure rate
    else if (state.last_failure_time > 0 && 
             current_time - state.last_failure_time <= config.time_window &&
             state.failure_count >= config.failure_threshold) {
        should_trigger = true;
        trigger_reason = b"Failure rate in time window exceeded";
    };
    
    if (should_trigger && !state.is_open) {
        // Trigger circuit breaker
        state.is_open = true;
        state.state_change_time = current_time;
        
        // Emit state change event
        event::emit(CircuitBreakerStateChangeEvent {
            operation_type,
            old_state: false,
            new_state: true,
            trigger_reason,
            failure_count: state.failure_count,
            timestamp: current_time,
        });
    };
}

// ===== Recovery Functions =====

/// Attempt automatic recovery of circuit breaker
public fun attempt_recovery(
    registry: &mut CircuitBreakerRegistry,
    operation_type: vector<u8>,
    clock: &Clock,
): bool {
    // Check if operation is configured
    assert!(table::contains(&registry.breakers, operation_type), E_OPERATION_NOT_CONFIGURED);
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    let breaker_state = table::borrow_mut(&mut registry.breakers, operation_type);
    let recovery_config = table::borrow_mut(&mut registry.recovery_conditions, operation_type);
    
    // Check if recovery is allowed
    if (!recovery_config.auto_recovery_enabled) {
        return false
    };
    
    // Check if circuit breaker is open
    if (!breaker_state.is_open) {
        return true // Already closed
    };
    
    // Check recovery attempts limit
    let day_start = (current_time / 86400) * 86400; // Start of current day
    if (recovery_config.last_recovery_attempt < day_start) {
        // Reset daily counter
        recovery_config.recovery_attempts_today = 0;
    };
    
    if (recovery_config.recovery_attempts_today >= recovery_config.max_recovery_attempts) {
        return false
    };
    
    // Update recovery attempt tracking
    recovery_config.recovery_attempts_today = safe_math::safe_add(recovery_config.recovery_attempts_today, 1);
    recovery_config.last_recovery_attempt = current_time;
    
    // Check if enough time has passed since circuit breaker opened
    let threshold_config = table::borrow(&registry.operation_thresholds, operation_type);
    if (current_time - breaker_state.state_change_time < threshold_config.recovery_timeout) {
        return false
    };
    
    // Attempt recovery - close circuit breaker tentatively
    breaker_state.is_open = false;
    breaker_state.state_change_time = current_time;
    breaker_state.failure_count = 0; // Reset failure count
    breaker_state.consecutive_failures = 0;
    
    // Emit recovery event
    event::emit(CircuitBreakerRecoveryEvent {
        operation_type,
        recovery_type: 0, // Auto recovery
        success: true,
        timestamp: current_time,
    });
    
    true
}

/// Manual recovery by admin
public fun manual_recovery(
    registry: &mut CircuitBreakerRegistry,
    admin_cap: &CircuitBreakerAdminCap,
    operation_type: vector<u8>,
    clock: &Clock,
) {
    // Verify admin permissions
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Check if operation is configured
    assert!(table::contains(&registry.breakers, operation_type), E_OPERATION_NOT_CONFIGURED);
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    let breaker_state = table::borrow_mut(&mut registry.breakers, operation_type);
    
    if (breaker_state.is_open) {
        breaker_state.is_open = false;
        breaker_state.state_change_time = current_time;
        breaker_state.failure_count = 0;
        breaker_state.consecutive_failures = 0;
        
        // Emit recovery event
        event::emit(CircuitBreakerRecoveryEvent {
            operation_type,
            recovery_type: 1, // Manual recovery
            success: true,
            timestamp: current_time,
        });
    };
}

// ===== Emergency Functions =====

/// Activate global emergency mode
public fun activate_global_emergency(
    registry: &mut CircuitBreakerRegistry,
    admin_cap: &CircuitBreakerAdminCap,
    clock: &Clock,
) {
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    registry.global_emergency = true;
    registry.emergency_triggered_time = clock::timestamp_ms(clock) / 1000;
    
    // Note: Security event emission would be implemented here
    // For now, we rely on the circuit breaker events
}

/// Deactivate global emergency mode
public fun deactivate_global_emergency(
    registry: &mut CircuitBreakerRegistry,
    admin_cap: &CircuitBreakerAdminCap,
) {
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    registry.global_emergency = false;
    registry.emergency_triggered_time = 0;
}

// ===== Helper Functions =====

/// Emit blocked operation event
fun emit_blocked_event(
    operation_type: vector<u8>,
    caller: address,
    reason: vector<u8>,
    clock: &Clock,
) {
    event::emit(CircuitBreakerBlockedEvent {
        operation_type,
        caller,
        reason,
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
}

// ===== Query Functions =====

/// Check if circuit breaker is open for operation type
public fun is_circuit_breaker_open(
    registry: &CircuitBreakerRegistry,
    operation_type: vector<u8>,
): bool {
    if (!table::contains(&registry.breakers, operation_type)) {
        return false
    };
    
    let state = table::borrow(&registry.breakers, operation_type);
    state.is_open
}

/// Get circuit breaker state
public fun get_circuit_breaker_state(
    registry: &CircuitBreakerRegistry,
    operation_type: vector<u8>,
): CircuitBreakerState {
    assert!(table::contains(&registry.breakers, operation_type), E_OPERATION_NOT_CONFIGURED);
    *table::borrow(&registry.breakers, operation_type)
}

/// Check if global emergency is active
public fun is_global_emergency_active(registry: &CircuitBreakerRegistry): bool {
    registry.global_emergency
}

/// Get operation type constants for external use
public fun operation_borrow(): vector<u8> { OPERATION_BORROW }
public fun operation_repay(): vector<u8> { OPERATION_REPAY }
public fun operation_liquidate(): vector<u8> { OPERATION_LIQUIDATE }
public fun operation_oracle_update(): vector<u8> { OPERATION_ORACLE_UPDATE }
public fun operation_vault_deposit(): vector<u8> { OPERATION_VAULT_DEPOSIT }
public fun operation_vault_withdraw(): vector<u8> { OPERATION_VAULT_WITHDRAW }

// ===== Accessor Functions for Testing =====

/// Create threshold config for testing
public fun create_threshold_config(
    failure_threshold: u64,
    time_window: u64,
    recovery_timeout: u64,
    volume_threshold: u64,
    success_rate_threshold: u64,
): ThresholdConfig {
    ThresholdConfig {
        failure_threshold,
        time_window,
        recovery_timeout,
        volume_threshold,
        success_rate_threshold,
    }
}

/// Create recovery config for testing
public fun create_recovery_config(
    auto_recovery_enabled: bool,
    recovery_test_count: u64,
    recovery_success_rate: u64,
    max_recovery_attempts: u64,
): RecoveryConfig {
    RecoveryConfig {
        auto_recovery_enabled,
        recovery_test_count,
        recovery_success_rate,
        max_recovery_attempts,
        recovery_attempts_today: 0,
        last_recovery_attempt: 0,
    }
}