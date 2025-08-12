/// Security Constants Module
/// Defines security-related constants and configuration values for the OLend platform
module olend::security_constants;

// ===== Oracle Security Constants =====

/// Maximum acceptable price staleness in milliseconds (5 minutes)
public fun max_price_staleness(): u64 { 300_000 }

/// Minimum confidence threshold for price data (95%)
public fun min_confidence_threshold(): u64 { 95 }

/// Maximum price deviation percentage per block (10%)
public fun max_price_deviation_per_block(): u64 { 1000 } // 10% in basis points

/// Circuit breaker threshold for extreme price movements (20%)
public fun circuit_breaker_threshold(): u64 { 2000 } // 20% in basis points

/// Price history window size for validation
public fun price_history_window_size(): u64 { 100 }

/// Oracle emergency mode timeout (30 minutes)
public fun oracle_emergency_timeout(): u64 { 1_800_000 }

// ===== Mathematical Safety Constants =====

/// Maximum safe multiplication factor to prevent overflow
public fun max_safe_mul_factor(): u64 { 1_000_000_000_000_000_000 } // 10^18

/// Precision factor for percentage calculations
public fun precision_factor(): u64 { 10_000 } // 100% = 10,000 basis points

/// Maximum safe addition value
public fun max_safe_add_value(): u64 { 18_446_744_073_709_551_615 / 2 } // u64::MAX / 2

/// Minimum value for division operations
public fun min_division_value(): u64 { 1 }

// ===== Access Control Constants =====

/// Default time delay for critical operations (24 hours)
public fun default_operation_delay(): u64 { 86_400_000 }

/// Emergency admin timeout (1 hour)
public fun emergency_admin_timeout(): u64 { 3_600_000 }

/// Maximum number of pending operations per address
public fun max_pending_operations(): u64 { 10 }

/// Multi-signature timeout (48 hours)
public fun multisig_timeout(): u64 { 172_800_000 }

/// Maximum number of authorized signers
public fun max_authorized_signers(): u64 { 20 }

// ===== Reentrancy Protection Constants =====

/// Maximum allowed call depth
public fun max_call_depth(): u64 { 10 }

/// Reentrancy guard timeout (1 minute)
public fun reentrancy_guard_timeout(): u64 { 60_000 }

// ===== Flash Loan Protection Constants =====

/// Minimum position age for critical operations (1 block)
public fun min_position_age(): u64 { 1 }

/// Rate limit window size (1 hour)
public fun rate_limit_window(): u64 { 3_600_000 }

/// Maximum operations per window per address
public fun max_operations_per_window(): u64 { 100 }

/// Suspicious activity threshold
public fun suspicious_activity_threshold(): u64 { 50 }

/// Flash loan cooldown period (5 minutes)
public fun flash_loan_cooldown(): u64 { 300_000 }

/// Maximum same-block operations
public fun max_same_block_operations(): u64 { 5 }

// ===== Circuit Breaker Constants =====

/// Circuit breaker failure threshold
public fun circuit_breaker_failure_threshold(): u64 { 5 }

/// Circuit breaker time window (10 minutes)
public fun circuit_breaker_time_window(): u64 { 600_000 }

/// Circuit breaker recovery timeout (30 minutes)
public fun circuit_breaker_recovery_timeout(): u64 { 1_800_000 }

/// Volume threshold for circuit breaker activation
public fun volume_threshold(): u64 { 1_000_000_000_000 } // 1M tokens (assuming 6 decimals)

// ===== Monitoring Constants =====

/// Event batch size for processing
public fun event_batch_size(): u64 { 100 }

/// Monitoring window size (1 hour)
public fun monitoring_window(): u64 { 3_600_000 }

/// Alert threshold for critical events
public fun critical_alert_threshold(): u64 { 10 }

/// Maximum event history size
public fun max_event_history_size(): u64 { 10_000 }

// ===== Security Validation Constants =====

/// Minimum required security score
public fun min_security_score(): u64 { 80 }

/// Security validation timeout
public fun security_validation_timeout(): u64 { 30_000 }

/// Maximum retry attempts for security operations
public fun max_security_retry_attempts(): u64 { 3 }

// ===== Role-Based Access Control Constants =====

/// Admin role identifier
public fun role_admin(): vector<u8> { b"ADMIN" }

/// Emergency admin role identifier
public fun role_emergency_admin(): vector<u8> { b"EMERGENCY_ADMIN" }

/// Oracle admin role identifier
public fun role_oracle_admin(): vector<u8> { b"ORACLE_ADMIN" }

/// Security admin role identifier
public fun role_security_admin(): vector<u8> { b"SECURITY_ADMIN" }

/// Liquidator role identifier
public fun role_liquidator(): vector<u8> { b"LIQUIDATOR" }

/// Pauser role identifier
public fun role_pauser(): vector<u8> { b"PAUSER" }

// ===== Operation Type Constants =====

/// Borrowing operation type
public fun op_type_borrow(): vector<u8> { b"BORROW" }

/// Lending operation type
public fun op_type_lend(): vector<u8> { b"LEND" }

/// Liquidation operation type
public fun op_type_liquidate(): vector<u8> { b"LIQUIDATE" }

/// Repayment operation type
public fun op_type_repay(): vector<u8> { b"REPAY" }

/// Withdrawal operation type
public fun op_type_withdraw(): vector<u8> { b"WITHDRAW" }

/// Parameter change operation type
public fun op_type_param_change(): vector<u8> { b"PARAM_CHANGE" }

/// Emergency pause operation type
public fun op_type_emergency_pause(): vector<u8> { b"EMERGENCY_PAUSE" }

// ===== Circuit Breaker State Constants =====

/// Circuit breaker closed state
public fun breaker_state_closed(): vector<u8> { b"CLOSED" }

/// Circuit breaker open state
public fun breaker_state_open(): vector<u8> { b"OPEN" }

/// Circuit breaker half-open state
public fun breaker_state_half_open(): vector<u8> { b"HALF_OPEN" }

// ===== Security Configuration Validation =====

/// Validate if a time delay is within acceptable range
public fun is_valid_time_delay(delay: u64): bool {
    delay >= 60_000 && delay <= 604_800_000 // 1 minute to 1 week
}

/// Validate if a confidence threshold is acceptable
public fun is_valid_confidence_threshold(threshold: u64): bool {
    threshold >= 50 && threshold <= 100 // 50% to 100%
}

/// Validate if a deviation threshold is reasonable
public fun is_valid_deviation_threshold(threshold: u64): bool {
    threshold >= 100 && threshold <= 5000 // 1% to 50% in basis points
}

/// Validate if a rate limit is reasonable
public fun is_valid_rate_limit(limit: u64): bool {
    limit >= 1 && limit <= 1000 // 1 to 1000 operations per window
}

/// Validate if a call depth is safe
public fun is_valid_call_depth(depth: u64): bool {
    depth <= max_call_depth()
}

/// Validate if a security score is acceptable
public fun is_valid_security_score(score: u64): bool {
    score >= 0 && score <= 100
}

// ===== Enhanced Oracle Security Constants =====

/// Current security version for enhanced oracle
public fun current_security_version(): u64 { 1 }

/// Minimum validation score for price acceptance
public fun min_validation_score(): u64 { 70 }

/// Maximum price history points to keep
public fun max_price_history_points(): u64 { 100 }

/// Default heartbeat for price feeds (60 seconds)
public fun default_price_feed_heartbeat(): u64 { 60 }

/// Maximum allowed price feed heartbeat (1 hour)
public fun max_price_feed_heartbeat(): u64 { 3600 }

/// Minimum allowed price feed heartbeat (10 seconds)
public fun min_price_feed_heartbeat(): u64 { 10 }

/// Price manipulation detection sensitivity (basis points)
public fun manipulation_detection_sensitivity(): u64 { 500 } // 5%

/// Circuit breaker activation threshold multiplier
public fun circuit_breaker_multiplier(): u64 { 2 } // 2x normal threshold

/// Emergency mode activation threshold
public fun emergency_mode_threshold(): u64 { 3 } // 3 consecutive failures

/// Price validation timeout (30 seconds)
public fun price_validation_timeout(): u64 { 30 }

/// Maximum price age for validation (10 minutes)
public fun max_price_age_for_validation(): u64 { 600 }

/// Trend analysis window size (minimum points needed)
public fun trend_analysis_min_points(): u64 { 3 }

/// Maximum trend analysis points
public fun trend_analysis_max_points(): u64 { 10 }

/// Validation score weights (out of 100)
public fun validation_weight_staleness(): u64 { 30 }
public fun validation_weight_confidence(): u64 { 25 }
public fun validation_weight_deviation(): u64 { 20 }
public fun validation_weight_trend(): u64 { 25 }

/// Risk level thresholds
public fun risk_level_low_threshold(): u64 { 30 }
public fun risk_level_medium_threshold(): u64 { 60 }
public fun risk_level_high_threshold(): u64 { 80 }