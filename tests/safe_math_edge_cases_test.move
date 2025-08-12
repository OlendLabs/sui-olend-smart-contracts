#[test_only]
module olend::safe_math_edge_cases_test;

use sui::test_scenario::{Self};
use sui::clock::{Self};
use olend::safe_math;
use olend::errors;

// ===== Division by Zero Edge Cases =====

#[test]
#[expected_failure(abort_code = 5016)]
fun edge_case_safe_div_zero_divisor() {
    safe_math::safe_div(1000, 0);
}

#[test]
#[expected_failure(abort_code = 5016)]
fun edge_case_safe_mul_div_zero_divisor() {
    safe_math::safe_mul_div(1000, 500, 0);
}

#[test]
#[expected_failure(abort_code = 5016)]
fun edge_case_safe_percentage_zero_basis() {
    safe_math::safe_percentage(1000, 500, 0);
}

#[test]
#[expected_failure(abort_code = 5016)]
fun edge_case_collateral_ratio_zero_borrowed() {
    safe_math::calculate_collateral_ratio_safe(1000, 0, 10000);
}

#[test]
#[expected_failure(abort_code = 5016)]
fun edge_case_collateral_ratio_zero_precision() {
    safe_math::calculate_collateral_ratio_safe(1000, 500, 0);
}

#[test]
#[expected_failure(abort_code = 5016)]
fun edge_case_compound_interest_zero_precision() {
    safe_math::calculate_compound_interest_safe(1000, 500, 1, 0);
}

#[test]
#[expected_failure(abort_code = 5016)]
fun edge_case_basis_points_zero_total() {
    safe_math::calculate_basis_points(500, 0);
}

// ===== Overflow Edge Cases =====

#[test]
#[expected_failure(abort_code = 5007)]
fun edge_case_safe_add_max_plus_one() {
    let max_u64 = 18_446_744_073_709_551_615u64;
    safe_math::safe_add(max_u64, 1);
}

#[test]
#[expected_failure(abort_code = 5007)]
fun edge_case_safe_add_two_large_numbers() {
    let large = 10_000_000_000_000_000_000u64;
    safe_math::safe_add(large, large);
}

#[test]
#[expected_failure(abort_code = 5007)]
fun edge_case_safe_mul_large_squares() {
    let large = 4_294_967_296u64; // 2^32
    safe_math::safe_mul(large, large); // Should overflow
}

#[test]
#[expected_failure(abort_code = 5007)]
fun edge_case_safe_mul_max_by_two() {
    let max_u64 = 18_446_744_073_709_551_615u64;
    safe_math::safe_mul(max_u64, 2);
}

#[test]
fun edge_case_safe_mul_div_overflow_intermediate() {
    // This should work because our implementation uses alternative calculation paths
    // to avoid intermediate overflow when the final result fits
    let max_u64 = 18_446_744_073_709_551_615u64;
    let large_a = max_u64 / 2 + 1;
    let large_b = 3;
    let result = safe_math::safe_mul_div(large_a, large_b, 2); // Uses 128-bit intermediate calculation
    assert!(result > 0, 0); // Should succeed and return a valid result
}

// ===== Underflow Edge Cases =====

#[test]
#[expected_failure(abort_code = 5008)]
fun edge_case_safe_sub_underflow_simple() {
    safe_math::safe_sub(100, 200);
}

#[test]
#[expected_failure(abort_code = 5008)]
fun edge_case_safe_sub_zero_minus_one() {
    safe_math::safe_sub(0, 1);
}

#[test]
#[expected_failure(abort_code = 5008)]
fun edge_case_safe_sub_large_underflow() {
    let small = 1_000_000u64;
    let large = 10_000_000_000u64;
    safe_math::safe_sub(small, large);
}

// ===== Boundary Value Testing =====

#[test]
fun edge_case_max_u64_operations() {
    let max_u64 = 18_446_744_073_709_551_615u64;
    
    // Operations that should work with MAX_U64
    assert!(safe_math::safe_add(max_u64, 0) == max_u64, 0);
    assert!(safe_math::safe_sub(max_u64, 0) == max_u64, 1);
    assert!(safe_math::safe_mul(max_u64, 1) == max_u64, 2);
    assert!(safe_math::safe_div(max_u64, 1) == max_u64, 3);
    assert!(safe_math::safe_mul(max_u64, 0) == 0, 4);
    
    // MAX_U64 divided by itself should be 1
    assert!(safe_math::safe_div(max_u64, max_u64) == 1, 5);
    
    // MAX_U64 minus itself should be 0
    assert!(safe_math::safe_sub(max_u64, max_u64) == 0, 6);
}

#[test]
fun edge_case_zero_operations() {
    // All operations with zero
    assert!(safe_math::safe_add(0, 0) == 0, 0);
    assert!(safe_math::safe_sub(0, 0) == 0, 1);
    assert!(safe_math::safe_mul(0, 0) == 0, 2);
    assert!(safe_math::safe_mul(0, 1000000) == 0, 3);
    assert!(safe_math::safe_mul(1000000, 0) == 0, 4);
    
    // Zero divided by anything (except zero) should be zero
    assert!(safe_math::safe_div(0, 1) == 0, 5);
    assert!(safe_math::safe_div(0, 1000000) == 0, 6);
    
    // Zero in mul_div operations
    assert!(safe_math::safe_mul_div(0, 1000, 500) == 0, 7);
    assert!(safe_math::safe_mul_div(1000, 0, 500) == 0, 8);
}

#[test]
fun edge_case_one_operations() {
    let test_values = vector[1u64, 100u64, 1000000u64, 18_446_744_073_709_551_615u64];
    
    let mut i = 0;
    while (i < test_values.length()) {
        let val = *vector::borrow(&test_values, i);
        
        // Multiplication by 1 should be identity
        assert!(safe_math::safe_mul(val, 1) == val, i * 10);
        assert!(safe_math::safe_mul(1, val) == val, i * 10 + 1);
        
        // Division by 1 should be identity
        assert!(safe_math::safe_div(val, 1) == val, i * 10 + 2);
        
        // Addition with 0 should be identity
        assert!(safe_math::safe_add(val, 0) == val, i * 10 + 3);
        assert!(safe_math::safe_add(0, val) == val, i * 10 + 4);
        
        // Subtraction of 0 should be identity
        assert!(safe_math::safe_sub(val, 0) == val, i * 10 + 5);
        
        i = i + 1;
    };
}

// ===== Precision Edge Cases =====

#[test]
fun edge_case_precision_loss_in_division() {
    // Test cases where integer division causes precision loss
    assert!(safe_math::safe_div(10, 3) == 3, 0); // 10/3 = 3.33... -> 3
    assert!(safe_math::safe_div(100, 7) == 14, 1); // 100/7 = 14.28... -> 14
    assert!(safe_math::safe_div(1000, 13) == 76, 2); // 1000/13 = 76.92... -> 76
    
    // Test mul_div precision preservation
    assert!(safe_math::safe_mul_div(1000, 333, 1000) == 333, 3); // Should preserve precision
    assert!(safe_math::safe_mul_div(1000, 1, 3) == 333, 4); // 1000/3 = 333.33... -> 333
}

#[test]
fun edge_case_percentage_precision() {
    // Test percentage calculations with precision edge cases
    let amount = 1000u64;
    let basis_points = 10000u64;
    
    // Very small percentages
    assert!(safe_math::safe_percentage(amount, 1, basis_points) == 0, 0); // 0.01% of 1000 = 0.1 -> 0
    assert!(safe_math::safe_percentage(amount, 10, basis_points) == 1, 1); // 0.1% of 1000 = 1
    
    // Edge case: 99.99%
    assert!(safe_math::safe_percentage(amount, 9999, basis_points) == 999, 2);
    
    // Edge case: exactly 100%
    assert!(safe_math::safe_percentage(amount, basis_points, basis_points) == amount, 3);
}

#[test]
fun edge_case_collateral_ratio_precision() {
    let precision = 10000u64; // 100% = 10000
    
    // Edge case: collateral slightly less than borrowed
    let ratio1 = safe_math::calculate_collateral_ratio_safe(9999, 10000, precision);
    assert!(ratio1 == 9999, 0); // 99.99%
    
    // Edge case: collateral slightly more than borrowed
    let ratio2 = safe_math::calculate_collateral_ratio_safe(10001, 10000, precision);
    assert!(ratio2 == 10001, 1); // 100.01%
    
    // Edge case: very small borrowed amount
    let ratio3 = safe_math::calculate_collateral_ratio_safe(1000000, 1, precision);
    assert!(ratio3 == 1000000 * precision, 2); // Very high ratio
}

// ===== Input Validation Edge Cases =====

#[test]
#[expected_failure(abort_code = 9001)]
fun edge_case_safe_percentage_exceeds_max() {
    // Test percentage exceeding 200% limit
    safe_math::safe_percentage(1000, 20001, 10000); // 200.01%
}

#[test]
#[expected_failure(abort_code = 9001)]
fun edge_case_compound_interest_rate_too_high() {
    // Test compound interest with rate > 100%
    safe_math::calculate_compound_interest_safe(1000, 10001, 1, 10000);
}

#[test]
#[expected_failure(abort_code = 9001)]
fun edge_case_compound_interest_periods_too_many() {
    // Test compound interest with too many periods
    safe_math::calculate_compound_interest_safe(1000, 500, 1001, 10000);
}

#[test]
#[expected_failure(abort_code = 9001)]
fun edge_case_liquidation_ratio_exceeds_max() {
    // Test liquidation ratio exceeding maximum
    safe_math::calculate_liquidation_amount_safe(10000, 8000, 7500); // 80% > 75% max
}

#[test]
#[expected_failure(abort_code = 9001)]
fun edge_case_liquidation_ratio_exceeds_100_percent() {
    // Test liquidation ratio exceeding 100%
    safe_math::calculate_liquidation_amount_safe(10000, 10001, 15000); // 100.01%
}

#[test]
#[expected_failure(abort_code = 9001)]
fun edge_case_safe_pow_exponent_too_large() {
    // Test power with exponent > 64
    safe_math::safe_pow(2, 65);
}

// ===== Compound Interest Edge Cases =====

#[test]
fun edge_case_compound_interest_zero_rate() {
    let principal = 1000000u64;
    let precision = 10000u64;
    
    // Zero rate should return principal regardless of periods
    assert!(safe_math::calculate_compound_interest_safe(principal, 0, 0, precision) == principal, 0);
    assert!(safe_math::calculate_compound_interest_safe(principal, 0, 1, precision) == principal, 1);
    assert!(safe_math::calculate_compound_interest_safe(principal, 0, 100, precision) == principal, 2);
}

#[test]
fun edge_case_compound_interest_zero_periods() {
    let principal = 1000000u64;
    let precision = 10000u64;
    
    // Zero periods should return principal regardless of rate
    assert!(safe_math::calculate_compound_interest_safe(principal, 0, 0, precision) == principal, 0);
    assert!(safe_math::calculate_compound_interest_safe(principal, 500, 0, precision) == principal, 1);
    assert!(safe_math::calculate_compound_interest_safe(principal, 10000, 0, precision) == principal, 2);
}

#[test]
fun edge_case_compound_interest_boundary_approximation() {
    let principal = 1000000u64;
    let precision = 10000u64;
    
    // Test boundary between approximation and iterative calculation
    // Rate = 1000 (10%), Periods = 10 (boundary case)
    let result_boundary = safe_math::calculate_compound_interest_safe(principal, 1000, 10, precision);
    assert!(result_boundary > principal, 0);
    
    // Rate = 1001 (10.01%), Periods = 10 (should use iterative)
    let result_iterative = safe_math::calculate_compound_interest_safe(principal, 1001, 10, precision);
    assert!(result_iterative > principal, 1);
    
    // Periods = 11 (should use iterative even with small rate)
    let result_periods = safe_math::calculate_compound_interest_safe(principal, 500, 11, precision);
    assert!(result_periods > principal, 2);
}

// ===== Power Function Edge Cases =====

#[test]
fun edge_case_safe_pow_special_values() {
    // Test special base values
    assert!(safe_math::safe_pow(0, 0) == 1, 0); // 0^0 = 1 by convention
    assert!(safe_math::safe_pow(0, 1) == 0, 1);
    assert!(safe_math::safe_pow(0, 100) == 0, 2);
    
    assert!(safe_math::safe_pow(1, 0) == 1, 3);
    assert!(safe_math::safe_pow(1, 1) == 1, 4);
    assert!(safe_math::safe_pow(1, 64) == 1, 5);
    
    // Test powers of 2 up to safe limits
    assert!(safe_math::safe_pow(2, 0) == 1, 6);
    assert!(safe_math::safe_pow(2, 1) == 2, 7);
    assert!(safe_math::safe_pow(2, 10) == 1024, 8);
    assert!(safe_math::safe_pow(2, 20) == 1048576, 9);
}

#[test]
#[expected_failure(abort_code = 5007)]
fun edge_case_safe_pow_overflow() {
    // This should overflow: 2^64 > MAX_U64
    safe_math::safe_pow(2, 64);
}

// ===== Square Root Edge Cases =====

#[test]
fun edge_case_safe_sqrt_special_values() {
    // Test special values
    assert!(safe_math::safe_sqrt(0) == 0, 0);
    assert!(safe_math::safe_sqrt(1) == 1, 1);
    
    // Test perfect squares
    assert!(safe_math::safe_sqrt(4) == 2, 2);
    assert!(safe_math::safe_sqrt(9) == 3, 3);
    assert!(safe_math::safe_sqrt(16) == 4, 4);
    assert!(safe_math::safe_sqrt(25) == 5, 5);
    assert!(safe_math::safe_sqrt(100) == 10, 6);
    assert!(safe_math::safe_sqrt(10000) == 100, 7);
    
    // Test non-perfect squares (should return floor)
    assert!(safe_math::safe_sqrt(2) == 1, 8); // floor(sqrt(2)) = floor(1.414...) = 1
    assert!(safe_math::safe_sqrt(3) == 1, 9); // floor(sqrt(3)) = floor(1.732...) = 1
    assert!(safe_math::safe_sqrt(8) == 2, 10); // floor(sqrt(8)) = floor(2.828...) = 2
    assert!(safe_math::safe_sqrt(15) == 3, 11); // floor(sqrt(15)) = floor(3.872...) = 3
    assert!(safe_math::safe_sqrt(99) == 9, 12); // floor(sqrt(99)) = floor(9.949...) = 9
}

#[test]
fun edge_case_safe_sqrt_large_values() {
    // Test with large values
    let large_perfect_square = 1000000000000u64; // 10^12
    assert!(safe_math::safe_sqrt(large_perfect_square) == 1000000u64, 0); // 10^6
    
    // Test with maximum u64 value
    let max_u64 = 18_446_744_073_709_551_615u64;
    let sqrt_max = safe_math::safe_sqrt(max_u64);
    
    // Verify the result is correct: sqrt_max^2 <= max_u64 < (sqrt_max+1)^2
    assert!(sqrt_max > 0, 1);
    // We can't easily verify the exact bounds without risking overflow in the test
    // but we can verify it's reasonable
    assert!(sqrt_max > 4_000_000_000u64, 2); // Should be > 4 billion
    assert!(sqrt_max < 5_000_000_000u64, 3); // Should be < 5 billion
}

// ===== Overflow Detection Edge Cases =====

#[test]
fun edge_case_overflow_detection_accuracy() {
    let max_u64 = 18_446_744_073_709_551_615u64;
    
    // Test accurate overflow detection for multiplication
    assert!(!safe_math::would_mul_overflow(max_u64, 1), 0);
    assert!(safe_math::would_mul_overflow(max_u64, 2), 1);
    assert!(!safe_math::would_mul_overflow(max_u64 / 2, 2), 2);
    assert!(safe_math::would_mul_overflow(max_u64 / 2 + 1, 2), 3);
    
    // Test accurate overflow detection for addition
    assert!(!safe_math::would_add_overflow(max_u64, 0), 4);
    assert!(safe_math::would_add_overflow(max_u64, 1), 5);
    assert!(!safe_math::would_add_overflow(max_u64 - 1, 1), 6);
    assert!(safe_math::would_add_overflow(max_u64 - 1, 2), 7);
    
    // Test accurate underflow detection for subtraction
    assert!(!safe_math::would_sub_underflow(100, 100), 8);
    assert!(!safe_math::would_sub_underflow(100, 99), 9);
    assert!(safe_math::would_sub_underflow(100, 101), 10);
    assert!(safe_math::would_sub_underflow(0, 1), 11);
}

// ===== Bounds Validation Edge Cases =====

#[test]
fun edge_case_bounds_validation() {
    // Test bounds validation for different operations
    assert!(safe_math::validate_safe_bounds(1000, b"ADD"), 0);
    assert!(safe_math::validate_safe_bounds(1000, b"MUL"), 1);
    assert!(safe_math::validate_safe_bounds(1000, b"MUL_DIV"), 2);
    assert!(safe_math::validate_safe_bounds(1000, b"OTHER"), 3);
    
    // Test with maximum safe values
    let max_safe_mul = safe_math::max_safe_mul_value(1000);
    assert!(safe_math::validate_safe_bounds(max_safe_mul, b"MUL"), 4);
    
    // Test with values that exceed safe bounds
    let max_u64 = 18_446_744_073_709_551_615u64;
    assert!(!safe_math::validate_safe_bounds(max_u64, b"MUL"), 5);
}

#[test]
fun edge_case_max_safe_mul_value() {
    // Test max safe multiplication value calculation
    assert!(safe_math::max_safe_mul_value(0) == 18_446_744_073_709_551_615u64, 0);
    assert!(safe_math::max_safe_mul_value(1) == 18_446_744_073_709_551_615u64, 1);
    assert!(safe_math::max_safe_mul_value(2) == 9_223_372_036_854_775_807u64, 2);
    assert!(safe_math::max_safe_mul_value(1000) == 18_446_744_073_709_551u64, 3);
    
    // Verify the returned values are actually safe
    let factor = 1000u64;
    let max_safe = safe_math::max_safe_mul_value(factor);
    assert!(!safe_math::would_mul_overflow(max_safe, factor), 4);
}