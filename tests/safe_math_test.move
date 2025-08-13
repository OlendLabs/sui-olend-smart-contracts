#[test_only]
module olend::safe_math_test;

use sui::test_scenario::{Self};
use sui::clock::{Self};
use olend::safe_math;
use olend::errors;

#[test]
fun test_safe_add_normal_cases() {
    // Test normal addition
    assert!(safe_math::safe_add(100, 200) == 300, 0);
    assert!(safe_math::safe_add(0, 100) == 100, 1);
    assert!(safe_math::safe_add(100, 0) == 100, 2);
    
    // Test large numbers that don't overflow
    let large_num = 9_223_372_036_854_775_807u64; // Close to MAX_U64/2
    assert!(safe_math::safe_add(large_num, 100) == large_num + 100, 3);
}

#[test]
#[expected_failure(abort_code = 5007)]
fun test_safe_add_overflow() {
    let max_u64 = 18_446_744_073_709_551_615u64;
    safe_math::safe_add(max_u64, 1);
}

#[test]
fun test_safe_sub_normal_cases() {
    // Test normal subtraction
    assert!(safe_math::safe_sub(300, 100) == 200, 0);
    assert!(safe_math::safe_sub(100, 100) == 0, 1);
    assert!(safe_math::safe_sub(1000, 1) == 999, 2);
}

#[test]
#[expected_failure(abort_code = 5008)]
fun test_safe_sub_underflow() {
    safe_math::safe_sub(100, 200);
}

#[test]
fun test_safe_mul_normal_cases() {
    // Test normal multiplication
    assert!(safe_math::safe_mul(10, 20) == 200, 0);
    assert!(safe_math::safe_mul(0, 100) == 0, 1);
    assert!(safe_math::safe_mul(100, 0) == 0, 2);
    assert!(safe_math::safe_mul(1, 100) == 100, 3);
    
    // Test large numbers that don't overflow
    assert!(safe_math::safe_mul(1000000, 1000000) == 1000000000000, 4);
}

#[test]
#[expected_failure(abort_code = 5007)]
fun test_safe_mul_overflow() {
    let large_num = 4_294_967_296u64; // 2^32
    safe_math::safe_mul(large_num, large_num); // This should overflow
}

#[test]
fun test_safe_div_normal_cases() {
    // Test normal division
    assert!(safe_math::safe_div(100, 10) == 10, 0);
    assert!(safe_math::safe_div(0, 10) == 0, 1);
    assert!(safe_math::safe_div(100, 3) == 33, 2); // Integer division
}

#[test]
#[expected_failure(abort_code = 5016)]
fun test_safe_div_by_zero() {
    safe_math::safe_div(100, 0);
}

#[test]
fun test_safe_mul_div_normal_cases() {
    // Test normal mul_div operations
    assert!(safe_math::safe_mul_div(100, 200, 50) == 400, 0);
    assert!(safe_math::safe_mul_div(0, 200, 50) == 0, 1);
    assert!(safe_math::safe_mul_div(100, 0, 50) == 0, 2);
    
    // Test precision preservation
    assert!(safe_math::safe_mul_div(1000, 5000, 10000) == 500, 3);
    
    // Test large numbers
    let large_a = 1_000_000_000_000u64;
    let large_b = 2_000_000u64;
    let divisor = 1_000_000u64;
    let expected = (large_a / divisor) * large_b; // Avoid overflow in test
    assert!(safe_math::safe_mul_div(large_a, large_b, divisor) == expected, 4);
}

#[test]
#[expected_failure(abort_code = 5016)]
fun test_safe_mul_div_by_zero() {
    safe_math::safe_mul_div(100, 200, 0);
}

#[test]
fun test_safe_percentage() {
    // Test percentage calculations
    assert!(safe_math::safe_percentage(1000, 500, 10000) == 50, 0); // 5% of 1000
    assert!(safe_math::safe_percentage(1000, 1000, 10000) == 100, 1); // 10% of 1000
    assert!(safe_math::safe_percentage(1000, 10000, 10000) == 1000, 2); // 100% of 1000
    
    // Test with different basis points
    assert!(safe_math::safe_percentage(1000, 50, 100) == 500, 3); // 50% of 1000 with basis 100
}

#[test]
fun test_calculate_percentage() {
    // Test with default basis points (10000)
    assert!(safe_math::calculate_percentage(1000, 500) == 50, 0); // 5% of 1000
    assert!(safe_math::calculate_percentage(2000, 2500) == 500, 1); // 25% of 2000
}

#[test]
fun test_calculate_basis_points() {
    // Test basis points calculation
    assert!(safe_math::calculate_basis_points(50, 1000) == 500, 0); // 50/1000 = 5% = 500bp
    assert!(safe_math::calculate_basis_points(250, 1000) == 2500, 1); // 25% = 2500bp
    assert!(safe_math::calculate_basis_points(1000, 1000) == 10000, 2); // 100% = 10000bp
}

#[test]
fun test_calculate_collateral_ratio_safe() {
    // Test collateral ratio calculations
    let collateral = 15000u64;
    let borrowed = 10000u64;
    let precision = 10000u64;
    
    let ratio = safe_math::calculate_collateral_ratio_safe(collateral, borrowed, precision);
    assert!(ratio == 15000, 0); // 150% ratio
    
    // Test with different values
    let ratio2 = safe_math::calculate_collateral_ratio_safe(12000, 10000, 10000);
    assert!(ratio2 == 12000, 1); // 120% ratio
}

#[test]
#[expected_failure(abort_code = 5016)]
fun test_calculate_collateral_ratio_zero_borrowed() {
    safe_math::calculate_collateral_ratio_safe(15000, 0, 10000);
}

#[test]
fun test_calculate_compound_interest_safe() {
    // Test simple compound interest
    let principal = 1000u64;
    let rate_bp = 500u64; // 5%
    let time_periods = 1u64;
    let precision = 10000u64;
    
    let result = safe_math::calculate_compound_interest_safe(principal, rate_bp, time_periods, precision);
    assert!(result > principal, 0); // Should be more than principal
    
    // Test zero periods
    let result_zero = safe_math::calculate_compound_interest_safe(principal, rate_bp, 0, precision);
    assert!(result_zero == principal, 1);
}

#[test]
fun test_calculate_liquidation_amount_safe() {
    let debt = 10000u64;
    let liquidation_ratio = 5000u64; // 50%
    let max_ratio = 7500u64; // 75% max
    
    let liquidation_amount = safe_math::calculate_liquidation_amount_safe(debt, liquidation_ratio, max_ratio);
    assert!(liquidation_amount == 5000, 0); // 50% of debt
}

#[test]
#[expected_failure(abort_code = 9001)]
fun test_calculate_liquidation_amount_exceeds_max() {
    let debt = 10000u64;
    let liquidation_ratio = 8000u64; // 80%
    let max_ratio = 7500u64; // 75% max
    
    safe_math::calculate_liquidation_amount_safe(debt, liquidation_ratio, max_ratio);
}

#[test]
fun test_safe_pow() {
    // Test power calculations
    assert!(safe_math::safe_pow(2, 0) == 1, 0);
    assert!(safe_math::safe_pow(2, 1) == 2, 1);
    assert!(safe_math::safe_pow(2, 3) == 8, 2);
    assert!(safe_math::safe_pow(10, 2) == 100, 3);
    assert!(safe_math::safe_pow(0, 5) == 0, 4);
    assert!(safe_math::safe_pow(1, 100) == 1, 5);
}

#[test]
#[expected_failure(abort_code = 9001)]
fun test_safe_pow_large_exponent() {
    safe_math::safe_pow(2, 100); // Should fail due to exponent limit
}

#[test]
fun test_safe_sqrt() {
    // Test square root calculations
    assert!(safe_math::safe_sqrt(0) == 0, 0);
    assert!(safe_math::safe_sqrt(1) == 1, 1);
    assert!(safe_math::safe_sqrt(4) == 2, 2);
    assert!(safe_math::safe_sqrt(9) == 3, 3);
    assert!(safe_math::safe_sqrt(16) == 4, 4);
    assert!(safe_math::safe_sqrt(100) == 10, 5);
    
    // Test non-perfect squares
    assert!(safe_math::safe_sqrt(8) == 2, 6); // Floor of sqrt(8) ≈ 2.83
    assert!(safe_math::safe_sqrt(15) == 3, 7); // Floor of sqrt(15) ≈ 3.87
}

#[test]
fun test_overflow_detection() {
    // Test overflow detection functions
    assert!(!safe_math::would_mul_overflow(100, 200), 0);
    assert!(safe_math::would_mul_overflow(4_294_967_296u64, 4_294_967_296u64), 1);
    
    assert!(!safe_math::would_add_overflow(100, 200), 2);
    let max_u64 = 18_446_744_073_709_551_615u64;
    assert!(safe_math::would_add_overflow(max_u64, 1), 3);
    
    assert!(!safe_math::would_sub_underflow(200, 100), 4);
    assert!(safe_math::would_sub_underflow(100, 200), 5);
}

#[test]
fun test_max_safe_mul_value() {
    let factor = 1000u64;
    let max_safe = safe_math::max_safe_mul_value(factor);
    
    // Should not overflow when multiplied by factor
    assert!(!safe_math::would_mul_overflow(max_safe, factor), 0);
    
    // Test with zero factor
    let max_safe_zero = safe_math::max_safe_mul_value(0);
    assert!(max_safe_zero == 18_446_744_073_709_551_615u64, 1);
}

#[test]
fun test_validate_safe_bounds() {
    // Test bounds validation
    assert!(safe_math::validate_safe_bounds(1000, b"MUL"), 0);
    assert!(safe_math::validate_safe_bounds(1000, b"ADD"), 1);
    assert!(safe_math::validate_safe_bounds(1000, b"OTHER"), 2);
    
    // Test with very large values
    let very_large = 18_446_744_073_709_551_615u64;
    assert!(!safe_math::validate_safe_bounds(very_large, b"MUL"), 3);
}

#[test]
fun test_math_error_handling() {
    let mut scenario = test_scenario::begin(@0x1);
    let ctx = test_scenario::ctx(&mut scenario);
    
    let mut clock = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clock, 1000);
    
    // Test error handling (this just tests the function doesn't crash)
    let inputs = vector[100u64, 200u64];
    safe_math::handle_math_error(
        b"TEST_OPERATION",
        inputs,
        b"OVERFLOW",
        &clock
    );
    
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun test_constants_access() {
    // Test that constants are accessible
    let _max_factor = safe_math::max_safe_multiplication_factor();
    let _precision = safe_math::precision_factor();
    let _min_div = safe_math::min_division_value();
    
    // Verify they have reasonable values
    assert!(safe_math::precision_factor() == 10000, 0);
    assert!(safe_math::min_division_value() == 1, 1);
}