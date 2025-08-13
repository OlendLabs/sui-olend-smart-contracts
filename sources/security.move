/// Security Infrastructure Module
/// Provides comprehensive security event structures, logging mechanisms, and base security functionality
/// for the OLend DeFi lending platform
module olend::security;

use sui::event;
use sui::clock::{Self, Clock};
use std::type_name::{Self, TypeName};

// ===== Security Event Structures =====

/// General security event for comprehensive logging and monitoring
public struct SecurityEvent has copy, drop {
    /// Type of security event (e.g., "ORACLE_MANIPULATION", "REENTRANCY_ATTEMPT")
    event_type: vector<u8>,
    /// Severity level: 1=Low, 2=Medium, 3=High, 4=Critical
    severity: u8,
    /// Timestamp when the event occurred
    timestamp: u64,
    /// Address that triggered or was affected by the event
    affected_address: address,
    /// Additional details about the event in JSON-like format
    details: vector<u8>,
    /// Action taken to mitigate the security issue
    mitigation_action: vector<u8>,
}

/// Oracle-specific security event for price manipulation and validation issues
public struct OracleSecurityEvent has copy, drop {
    /// Asset type that was affected
    asset_type: TypeName,
    /// Type of oracle security event
    event_type: vector<u8>,
    /// Price before the security event
    price_before: u64,
    /// Price after the security event (if applicable)
    price_after: u64,
    /// Confidence level of the price data
    confidence: u64,
    /// Percentage deviation that triggered the event
    deviation_percentage: u64,
    /// Timestamp of the event
    timestamp: u64,
}

/// Mathematical operation security event for overflow/underflow detection
public struct MathSecurityEvent has copy, drop {
    /// Type of mathematical operation that failed
    operation_type: vector<u8>,
    /// Input values that caused the security issue
    input_values: vector<u64>,
    /// Expected result (if calculable)
    expected_result: u64,
    /// Error type (overflow, underflow, division by zero)
    error_type: vector<u8>,
    /// Timestamp of the event
    timestamp: u64,
}

/// Access control security event for unauthorized access attempts
public struct AccessControlEvent has copy, drop {
    /// Address that attempted the operation
    caller: address,
    /// Operation that was attempted
    operation: vector<u8>,
    /// Required role/permission for the operation
    required_permission: vector<u8>,
    /// Actual role/permission of the caller
    caller_permission: vector<u8>,
    /// Whether the access was granted or denied
    access_granted: bool,
    /// Timestamp of the access attempt
    timestamp: u64,
}

/// Reentrancy protection event for tracking potential attacks
public struct ReentrancyEvent has copy, drop {
    /// Contract/function that detected reentrancy
    contract_type: TypeName,
    /// Function name where reentrancy was detected
    function_name: vector<u8>,
    /// Call depth when reentrancy was detected
    call_depth: u64,
    /// Address that initiated the call chain
    initiator: address,
    /// Whether the reentrancy attempt was blocked
    blocked: bool,
    /// Timestamp of the event
    timestamp: u64,
}

/// Flash loan protection event for MEV and attack detection
public struct FlashLoanProtectionEvent has copy, drop {
    /// Address involved in the suspicious activity
    address: address,
    /// Type of protection that was triggered
    protection_type: vector<u8>,
    /// Operation that was blocked or flagged
    blocked_operation: vector<u8>,
    /// Time since last similar operation
    time_since_last_op: u64,
    /// Number of operations in current window
    operation_count: u64,
    /// Timestamp of the event
    timestamp: u64,
}

/// Circuit breaker event for system-wide protection activation
public struct CircuitBreakerEvent has copy, drop {
    /// Type of operation that triggered the circuit breaker
    operation_type: vector<u8>,
    /// Current state of the circuit breaker (OPEN, CLOSED, HALF_OPEN)
    breaker_state: vector<u8>,
    /// Threshold that was exceeded
    threshold_exceeded: u64,
    /// Current value that exceeded the threshold
    current_value: u64,
    /// Time window for the measurement
    time_window: u64,
    /// Timestamp of the event
    timestamp: u64,
}

// ===== Security Event Emission Functions =====

/// Emit a general security event
public fun emit_security_event(
    event_type: vector<u8>,
    severity: u8,
    affected_address: address,
    details: vector<u8>,
    mitigation_action: vector<u8>,
    clock: &Clock
) {
    let security_event = SecurityEvent {
        event_type,
        severity,
        timestamp: clock::timestamp_ms(clock),
        affected_address,
        details,
        mitigation_action,
    };
    event::emit(security_event);
}

/// Emit an oracle security event
public fun emit_oracle_security_event<T>(
    event_type: vector<u8>,
    price_before: u64,
    price_after: u64,
    confidence: u64,
    deviation_percentage: u64,
    clock: &Clock
) {
    let oracle_event = OracleSecurityEvent {
        asset_type: type_name::get<T>(),
        event_type,
        price_before,
        price_after,
        confidence,
        deviation_percentage,
        timestamp: clock::timestamp_ms(clock),
    };
    event::emit(oracle_event);
}

/// Emit a mathematical operation security event
public fun emit_math_security_event(
    operation_type: vector<u8>,
    input_values: vector<u64>,
    expected_result: u64,
    error_type: vector<u8>,
    clock: &Clock
) {
    let math_event = MathSecurityEvent {
        operation_type,
        input_values,
        expected_result,
        error_type,
        timestamp: clock::timestamp_ms(clock),
    };
    event::emit(math_event);
}

/// Emit an access control event
public fun emit_access_control_event(
    caller: address,
    operation: vector<u8>,
    required_permission: vector<u8>,
    caller_permission: vector<u8>,
    access_granted: bool,
    clock: &Clock
) {
    let access_event = AccessControlEvent {
        caller,
        operation,
        required_permission,
        caller_permission,
        access_granted,
        timestamp: clock::timestamp_ms(clock),
    };
    event::emit(access_event);
}

/// Emit a reentrancy protection event
public fun emit_reentrancy_event<T>(
    function_name: vector<u8>,
    call_depth: u64,
    initiator: address,
    blocked: bool,
    clock: &Clock
) {
    let reentrancy_event = ReentrancyEvent {
        contract_type: type_name::get<T>(),
        function_name,
        call_depth,
        initiator,
        blocked,
        timestamp: clock::timestamp_ms(clock),
    };
    event::emit(reentrancy_event);
}

/// Emit a flash loan protection event
public fun emit_flash_loan_protection_event(
    address: address,
    protection_type: vector<u8>,
    blocked_operation: vector<u8>,
    time_since_last_op: u64,
    operation_count: u64,
    clock: &Clock
) {
    let protection_event = FlashLoanProtectionEvent {
        address,
        protection_type,
        blocked_operation,
        time_since_last_op,
        operation_count,
        timestamp: clock::timestamp_ms(clock),
    };
    event::emit(protection_event);
}

/// Emit a circuit breaker event
public fun emit_circuit_breaker_event(
    operation_type: vector<u8>,
    breaker_state: vector<u8>,
    threshold_exceeded: u64,
    current_value: u64,
    time_window: u64,
    clock: &Clock
) {
    let breaker_event = CircuitBreakerEvent {
        operation_type,
        breaker_state,
        threshold_exceeded,
        current_value,
        time_window,
        timestamp: clock::timestamp_ms(clock),
    };
    event::emit(breaker_event);
}

// ===== Security Severity Levels =====

/// Low severity security event
public fun severity_low(): u8 { 1 }

/// Medium severity security event
public fun severity_medium(): u8 { 2 }

/// High severity security event
public fun severity_high(): u8 { 3 }

/// Critical severity security event
public fun severity_critical(): u8 { 4 }

// ===== Common Security Event Types =====

/// Oracle price manipulation event type
public fun event_type_oracle_manipulation(): vector<u8> { b"ORACLE_MANIPULATION" }

/// Price staleness event type
public fun event_type_price_stale(): vector<u8> { b"PRICE_STALE" }

/// Low confidence event type
public fun event_type_low_confidence(): vector<u8> { b"LOW_CONFIDENCE" }

/// Circuit breaker activation event type
public fun event_type_circuit_breaker(): vector<u8> { b"CIRCUIT_BREAKER" }

/// Reentrancy attempt event type
public fun event_type_reentrancy(): vector<u8> { b"REENTRANCY_ATTEMPT" }

/// Flash loan attack event type
public fun event_type_flash_loan_attack(): vector<u8> { b"FLASH_LOAN_ATTACK" }

/// Mathematical overflow event type
public fun event_type_math_overflow(): vector<u8> { b"MATH_OVERFLOW" }

/// Mathematical underflow event type
public fun event_type_math_underflow(): vector<u8> { b"MATH_UNDERFLOW" }

/// Access denied event type
public fun event_type_access_denied(): vector<u8> { b"ACCESS_DENIED" }

/// Rate limit exceeded event type
public fun event_type_rate_limit(): vector<u8> { b"RATE_LIMIT_EXCEEDED" }

/// Suspicious activity event type
public fun event_type_suspicious_activity(): vector<u8> { b"SUSPICIOUS_ACTIVITY" }

/// Price manipulation detection event type
public fun event_type_price_manipulation(): vector<u8> { b"PRICE_MANIPULATION" }

/// Enhanced oracle validation event type
public fun event_type_oracle_validation(): vector<u8> { b"ORACLE_VALIDATION" }

/// Price trend anomaly event type
public fun event_type_price_trend_anomaly(): vector<u8> { b"PRICE_TREND_ANOMALY" }

/// Oracle emergency mode event type
public fun event_type_oracle_emergency(): vector<u8> { b"ORACLE_EMERGENCY" }

/// Price feed configuration change event type
public fun event_type_feed_config_change(): vector<u8> { b"FEED_CONFIG_CHANGE" }

// ===== Security Utility Functions =====

/// Create a detailed security event description
public fun create_security_details(
    description: vector<u8>,
    additional_data: vector<u8>
): vector<u8> {
    let mut details = b"description:";
    details.append(description);
    details.append(b",data:");
    details.append(additional_data);
    details
}

/// Create mitigation action description
public fun create_mitigation_action(
    action: vector<u8>,
    parameters: vector<u8>
): vector<u8> {
    let mut mitigation = b"action:";
    mitigation.append(action);
    mitigation.append(b",params:");
    mitigation.append(parameters);
    mitigation
}

/// Validate security event severity level
public fun is_valid_severity(severity: u8): bool {
    severity >= 1 && severity <= 4
}

/// Check if event requires immediate attention (high or critical severity)
public fun requires_immediate_attention(severity: u8): bool {
    severity >= 3
}

// ===== Security Error Handling Functions =====

/// Create a comprehensive error context for security failures
public fun create_error_context(
    error_code: u64,
    operation: vector<u8>,
    caller: address,
    additional_info: vector<u8>
): vector<u8> {
    let mut context = b"error_code:";
    context.append(u64_to_bytes(error_code));
    context.append(b",operation:");
    context.append(operation);
    context.append(b",caller:");
    context.append(address_to_bytes(caller));
    context.append(b",info:");
    context.append(additional_info);
    context
}

/// Handle security violation with comprehensive logging
public fun handle_security_violation(
    violation_type: vector<u8>,
    severity: u8,
    caller: address,
    details: vector<u8>,
    mitigation: vector<u8>,
    clock: &Clock
) {
    // Emit security event
    emit_security_event(
        violation_type,
        severity,
        caller,
        details,
        mitigation,
        clock
    );
    
    // Additional handling for critical violations
    if (severity >= severity_critical()) {
        // Log critical security violation
        emit_security_event(
            b"CRITICAL_SECURITY_VIOLATION",
            severity_critical(),
            caller,
            create_security_details(b"Critical security violation detected", details),
            create_mitigation_action(b"IMMEDIATE_REVIEW_REQUIRED", mitigation),
            clock
        );
    };
}

/// Validate security configuration parameters
public fun validate_security_config(
    max_price_delay: u64,
    min_confidence: u64,
    max_deviation: u64,
    call_depth_limit: u64
): bool {
    // Validate price delay (should be reasonable, not too short or too long)
    if (max_price_delay < 60_000 || max_price_delay > 3_600_000) { // 1 minute to 1 hour
        return false
    };
    
    // Validate confidence threshold
    if (min_confidence < 50 || min_confidence > 100) {
        return false
    };
    
    // Validate deviation threshold
    if (max_deviation > 5000) { // Max 50% deviation
        return false
    };
    
    // Validate call depth
    if (call_depth_limit > 20) { // Reasonable call depth limit
        return false
    };
    
    true
}

/// Create audit trail entry for security operations
public fun create_audit_trail(
    operation_type: vector<u8>,
    operator: address,
    _target: address,
    parameters: vector<u8>,
    result: bool,
    clock: &Clock
) {
    let audit_details = create_security_details(
        b"Security operation audit",
        parameters
    );
    
    let mitigation = if (result) {
        create_mitigation_action(b"OPERATION_SUCCESSFUL", b"")
    } else {
        create_mitigation_action(b"OPERATION_FAILED", b"Review required")
    };
    
    emit_security_event(
        operation_type,
        if (result) severity_low() else severity_medium(),
        operator,
        audit_details,
        mitigation,
        clock
    );
}

// ===== Security Utility Helper Functions =====

/// Convert u64 to bytes for logging
fun u64_to_bytes(value: u64): vector<u8> {
    // Simple conversion for logging purposes
    if (value == 0) return b"0";
    
    let mut result = vector::empty<u8>();
    let mut temp = value;
    
    while (temp > 0) {
        let digit = ((temp % 10) as u8) + 48; // Convert to ASCII
        result.insert(digit, 0);
        temp = temp / 10;
    };
    
    result
}

/// Convert address to bytes for logging
fun address_to_bytes(addr: address): vector<u8> {
    // Convert address to hex string representation
    let addr_bytes = std::bcs::to_bytes(&addr);
    let mut result = b"0x";
    let hex_chars = b"0123456789abcdef";
    
    let mut i = 0;
    while (i < addr_bytes.length()) {
        let byte = addr_bytes[i];
        result.push_back(hex_chars[(byte >> 4) as u64]);
        result.push_back(hex_chars[(byte & 0x0f) as u64]);
        i = i + 1;
    };
    
    result
}

/// Check if operation should be rate limited
public fun should_rate_limit(
    operation_count: u64,
    time_window: u64,
    max_operations: u64,
    current_time: u64,
    window_start: u64
): bool {
    // Check if we're still in the same time window
    if (current_time - window_start > time_window) {
        // New window, reset allowed
        false
    } else {
        // Same window, check if limit exceeded
        operation_count >= max_operations
    }
}

/// Calculate security score based on multiple factors
public fun calculate_security_score(
    oracle_health: u64,      // 0-100
    system_stability: u64,   // 0-100
    recent_violations: u64,  // Number of recent violations
    uptime_percentage: u64   // 0-100
): u64 {
    // Base score from oracle health and system stability
    let base_score = (oracle_health + system_stability) / 2;
    
    // Penalty for recent violations (each violation reduces score by 5)
    let violation_penalty = if (recent_violations > 20) 100 else recent_violations * 5;
    
    // Bonus for high uptime
    let uptime_bonus = if (uptime_percentage > 95) 10 else 0;
    
    // Calculate final score
    let raw_score = base_score + uptime_bonus;
    if (raw_score > violation_penalty) {
        raw_score - violation_penalty
    } else {
        0
    }
}