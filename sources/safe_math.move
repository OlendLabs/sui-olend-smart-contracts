/// SafeMath Library Module
/// Provides overflow-protected mathematical operations for the OLend DeFi lending platform
/// All operations include comprehensive bounds checking and error handling
module olend::safe_math;

use olend::errors;
use olend::security;
use olend::security_constants;
use sui::clock::Clock;

// ===== SafeMath Structure =====

/// SafeMath utility structure for overflow-protected operations
public struct SafeMath has drop {}

// ===== Core Safe Mathematical Operations =====

/// Safe multiplication with division to prevent overflow
/// Performs (a * b) / c with overflow protection
/// Aborts with EMathOverflow if overflow would occur
public fun safe_mul_div(a: u64, b: u64, c: u64): u64 {
    // Check for division by zero
    assert!(c != 0, errors::division_by_zero());
    
    // Check for zero inputs (optimization)
    if (a == 0 || b == 0) {
        return 0
    };
    
    // Check if we can perform the operation without overflow
    // Use the mathematical property: if a * b would overflow, then a > MAX_U64 / b
    let max_u64 = 18_446_744_073_709_551_615u64;
    
    // For very large numbers, use alternative calculation to prevent overflow
    if (a > max_u64 / b) {
        // Try to reduce precision by dividing first
        if (a % c == 0) {
            // a is divisible by c, so divide first
            (a / c) * b
        } else if (b % c == 0) {
            // b is divisible by c, so divide first
            a * (b / c)
        } else {
            // Use high-precision calculation with 128-bit intermediate
            // This is a simplified approach - in production, you'd want proper 128-bit math
            let result = ((a as u128) * (b as u128)) / (c as u128);
            assert!(result <= (max_u64 as u128), errors::math_overflow());
            (result as u64)
        }
    } else {
        // Safe to multiply first, then divide
        (a * b) / c
    }
}

/// Safe addition with overflow protection
/// Aborts with EMathOverflow if overflow would occur
public fun safe_add(a: u64, b: u64): u64 {
    let max_u64 = 18_446_744_073_709_551_615u64;
    
    // Check for overflow: if a + b would overflow, then a > MAX_U64 - b
    assert!(a <= max_u64 - b, errors::math_overflow());
    
    a + b
}

/// Safe subtraction with underflow protection
/// Aborts with EMathUnderflow if underflow would occur
public fun safe_sub(a: u64, b: u64): u64 {
    // Check for underflow
    assert!(a >= b, errors::math_underflow());
    
    a - b
}

/// Safe multiplication with overflow protection
/// Aborts with EMathOverflow if overflow would occur
public fun safe_mul(a: u64, b: u64): u64 {
    // Check for zero (optimization)
    if (a == 0 || b == 0) {
        return 0
    };
    
    let max_u64 = 18_446_744_073_709_551_615u64;
    
    // Check for overflow: if a * b would overflow, then a > MAX_U64 / b
    assert!(a <= max_u64 / b, errors::math_overflow());
    
    a * b
}

/// Safe division with zero check
/// Aborts with EDivisionByZero if divisor is zero
public fun safe_div(a: u64, b: u64): u64 {
    assert!(b != 0, errors::division_by_zero());
    a / b
}

// ===== Percentage and Basis Point Operations =====

/// Safe percentage calculation using basis points
/// Calculates (amount * percentage) / basis_points with overflow protection
/// percentage is in basis points (e.g., 500 = 5%)
public fun safe_percentage(amount: u64, percentage: u64, basis_points: u64): u64 {
    assert!(basis_points != 0, errors::division_by_zero());
    
    // Validate percentage is reasonable (not more than 100% unless explicitly allowed)
    assert!(percentage <= basis_points * 2, errors::invalid_input()); // Allow up to 200%
    
    safe_mul_div(amount, percentage, basis_points)
}

/// Calculate percentage with default basis points (10,000 = 100%)
public fun calculate_percentage(amount: u64, percentage_bp: u64): u64 {
    safe_percentage(amount, percentage_bp, security_constants::precision_factor())
}

/// Calculate basis points from two values (result * 10000 / total)
public fun calculate_basis_points(result: u64, total: u64): u64 {
    assert!(total != 0, errors::division_by_zero());
    safe_mul_div(result, security_constants::precision_factor(), total)
}

// ===== DeFi-Specific Safe Operations =====

/// Calculate collateral ratio with overflow protection
/// Returns ratio in basis points (10000 = 100%)
public fun calculate_collateral_ratio_safe(
    collateral_value: u64,
    borrowed_value: u64,
    precision: u64
): u64 {
    assert!(borrowed_value != 0, errors::division_by_zero());
    assert!(precision != 0, errors::division_by_zero());
    
    safe_mul_div(collateral_value, precision, borrowed_value)
}

/// Calculate interest with compound interest formula protection
/// amount * (1 + rate)^time approximation for small rates
public fun calculate_compound_interest_safe(
    principal: u64,
    rate_bp: u64,        // Interest rate in basis points
    time_periods: u64,   // Number of time periods
    precision: u64       // Precision factor
): u64 {
    assert!(precision != 0, errors::division_by_zero());
    
    // For safety, limit the rate and time to prevent extreme calculations
    assert!(rate_bp <= 10000, errors::invalid_input()); // Max 100% per period
    assert!(time_periods <= 1000, errors::invalid_input()); // Max 1000 periods
    
    if (time_periods == 0) {
        return principal
    };
    
    // Simple compound interest: P * (1 + r)^t
    // For small rates, use approximation: P * (1 + r*t + (r*t)^2/2)
    if (rate_bp <= 1000 && time_periods <= 10) { // 10% rate, 10 periods max for approximation
        let rate_times_time = safe_mul(rate_bp, time_periods);
        let linear_term = safe_mul_div(principal, rate_times_time, precision);
        let quadratic_term = safe_mul_div(
            safe_mul_div(principal, safe_mul(rate_times_time, rate_times_time), safe_mul(precision, precision)),
            1,
            2
        );
        safe_add(safe_add(principal, linear_term), quadratic_term)
    } else {
        // For larger rates or longer periods, use iterative calculation
        let mut result = principal;
        let mut i = 0;
        while (i < time_periods) {
            result = safe_mul_div(result, safe_add(precision, rate_bp), precision);
            i = i + 1;
        };
        result
    }
}

/// Calculate liquidation amount with safety checks
public fun calculate_liquidation_amount_safe(
    debt_amount: u64,
    liquidation_ratio: u64,  // In basis points
    max_liquidation_ratio: u64 // Maximum allowed liquidation ratio
): u64 {
    assert!(liquidation_ratio <= max_liquidation_ratio, errors::invalid_input());
    assert!(liquidation_ratio <= security_constants::precision_factor(), errors::invalid_input());
    
    safe_percentage(debt_amount, liquidation_ratio, security_constants::precision_factor())
}

// ===== Advanced Safe Operations =====

/// Safe power calculation for small exponents
/// Calculates base^exponent with overflow protection
public fun safe_pow(base: u64, exponent: u64): u64 {
    if (exponent == 0) {
        return 1
    };
    
    if (base == 0) {
        return 0
    };
    
    if (base == 1) {
        return 1
    };
    
    // Limit exponent to prevent extreme calculations
    assert!(exponent <= 64, errors::invalid_input());
    
    let mut result = 1u64;
    let mut i = 0u64;
    
    while (i < exponent) {
        result = safe_mul(result, base);
        i = i + 1;
    };
    
    result
}

/// Safe square root calculation using Newton's method
/// Returns the floor of the square root
public fun safe_sqrt(x: u64): u64 {
    if (x == 0) {
        return 0
    };
    
    if (x == 1) {
        return 1
    };
    
    // Newton's method for square root with overflow protection
    let mut z = x;
    // Use a safer initial guess to avoid overflow
    let mut y = if (x > 1) {
        // For large x, start with x/2 to avoid overflow in (x+1)/2
        if (x == 18_446_744_073_709_551_615u64) { // MAX_U64
            4_294_967_295u64 // Approximately sqrt(MAX_U64)
        } else {
            (x + 1) / 2
        }
    } else {
        1
    };
    
    while (y < z) {
        z = y;
        let quotient = safe_div(x, y);
        // Use safe addition with overflow check
        if (would_add_overflow(quotient, y)) {
            // If addition would overflow, we've found our answer
            break
        };
        y = (quotient + y) / 2;
    };
    
    z
}

// ===== Validation and Utility Functions =====

/// Check if a multiplication would overflow
public fun would_mul_overflow(a: u64, b: u64): bool {
    if (a == 0 || b == 0) {
        false
    } else {
        let max_u64 = 18_446_744_073_709_551_615u64;
        a > max_u64 / b
    }
}

/// Check if an addition would overflow
public fun would_add_overflow(a: u64, b: u64): bool {
    let max_u64 = 18_446_744_073_709_551_615u64;
    a > max_u64 - b
}

/// Check if a subtraction would underflow
public fun would_sub_underflow(a: u64, b: u64): bool {
    a < b
}

/// Get the maximum safe value for multiplication with a given factor
public fun max_safe_mul_value(factor: u64): u64 {
    if (factor == 0) {
        return 18_446_744_073_709_551_615u64 // MAX_U64
    };
    
    18_446_744_073_709_551_615u64 / factor
}

/// Validate that a value is within safe bounds for mathematical operations
public fun validate_safe_bounds(value: u64, operation: vector<u8>): bool {
    let max_safe = security_constants::max_safe_mul_factor();
    
    if (operation == b"MUL" || operation == b"MUL_DIV") {
        value <= max_safe
    } else if (operation == b"ADD") {
        value <= security_constants::max_safe_add_value()
    } else {
        true // Other operations don't have specific bounds
    }
}

// ===== Error Handling and Logging =====

/// Handle mathematical operation error with comprehensive logging
public fun handle_math_error(
    operation: vector<u8>,
    inputs: vector<u64>,
    error_type: vector<u8>,
    clock: &Clock
) {
    // Calculate expected result if possible (for logging)
    let expected_result = if (inputs.length() >= 2 && error_type != b"DIVISION_BY_ZERO") {
        // For overflow/underflow, we can't calculate the actual result
        0
    } else {
        0
    };
    
    // Emit mathematical security event
    security::emit_math_security_event(
        operation,
        inputs,
        expected_result,
        error_type,
        clock
    );
    
    // Emit general security event for critical math errors
    security::emit_security_event(
        security::event_type_math_overflow(),
        security::severity_high(),
        @0x0, // No specific address for math errors
        security::create_security_details(
            b"Mathematical operation safety violation",
            operation
        ),
        security::create_mitigation_action(
            b"OPERATION_ABORTED",
            b"Safe math bounds exceeded"
        ),
        clock
    );
}

// ===== Constants and Configuration =====

/// Get the maximum safe multiplication factor
public fun max_safe_multiplication_factor(): u64 {
    security_constants::max_safe_mul_factor()
}

/// Get the precision factor for percentage calculations
public fun precision_factor(): u64 {
    security_constants::precision_factor()
}

/// Get the minimum value for division operations
public fun min_division_value(): u64 {
    security_constants::min_division_value()
}