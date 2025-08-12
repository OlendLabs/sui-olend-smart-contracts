#[test_only]
module olend::safe_math_fuzz_test;

use sui::test_scenario::{Self};
use sui::clock::{Self};
use olend::safe_math;
use olend::errors;

// ===== Fuzz Testing for Mathematical Operations =====

#[test]
fun fuzz_test_safe_add_extreme_values() {
    // Test with maximum safe values
    let max_safe_half = 9_223_372_036_854_775_807u64; // MAX_U64 / 2
    assert!(safe_math::safe_add(max_safe_half, max_safe_half) == max_safe_half * 2, 0);
    
    // Test with values just below overflow threshold
    let max_u64 = 18_446_744_073_709_551_615u64;
    assert!(safe_math::safe_add(max_u64 - 1, 1) == max_u64, 1);
    assert!(safe_math::safe_add(max_u64 - 100, 100) == max_u64, 2);
    
    // Test with random large values that shouldn't overflow
    let large_a = 10_000_000_000_000_000_000u64;
    let large_b = 8_000_000_000_000_000_000u64;
    assert!(safe_math::safe_add(large_a, large_b - 1) == large_a + large_b - 1, 3);
}

#[test]
fun fuzz_test_safe_mul_extreme_values() {
    // Test with square root of MAX_U64 (largest values that can be safely multiplied)
    let sqrt_max = 4_294_967_295u64; // Approximately sqrt(MAX_U64)
    let result = safe_math::safe_mul(sqrt_max, sqrt_max);
    assert!(result > 0, 0); // Should not overflow
    
    // Test with powers of 2
    assert!(safe_math::safe_mul(2_147_483_648u64, 2) == 4_294_967_296u64, 1);
    assert!(safe_math::safe_mul(1_073_741_824u64, 4) == 4_294_967_296u64, 2);
    
    // Test with large prime numbers
    let prime1 = 982_451_653u64;
    let prime2 = 18_446_744_073_709_551_557u64 / prime1; // Ensure no overflow
    let result = safe_math::safe_mul(prime1, prime2);
    assert!(result > 0, 3);
}

#[test]
fun fuzz_test_safe_mul_div_extreme_precision() {
    // Test with extreme precision requirements
    let max_u64 = 18_446_744_073_709_551_615u64;
    
    // Test with large numerators and denominators
    let large_num = max_u64 / 1000;
    let result = safe_math::safe_mul_div(large_num, 999, 1000);
    assert!(result < large_num, 0);
    
    // Test precision preservation with large numbers
    let precision_test = safe_math::safe_mul_div(1_000_000_000_000u64, 123_456_789u64, 1_000_000_000u64);
    assert!(precision_test > 0, 1);
    
    // Test with maximum safe values
    let safe_max = 4_294_967_295u64;
    let result2 = safe_math::safe_mul_div(safe_max, safe_max, safe_max);
    assert!(result2 == safe_max, 2);
}

#[test]
fun fuzz_test_percentage_calculations_extreme() {
    // Test with maximum percentage values
    let amount = 1_000_000_000_000u64;
    let max_percentage = 20000u64; // 200% (maximum allowed)
    let basis_points = 10000u64;
    
    let result = safe_math::safe_percentage(amount, max_percentage, basis_points);
    assert!(result == amount * 2, 0);
    
    // Test with very small percentages
    let tiny_percentage = 1u64; // 0.01%
    let tiny_result = safe_math::safe_percentage(amount, tiny_percentage, basis_points);
    assert!(tiny_result == amount / basis_points, 1);
    
    // Test with various basis point systems
    let result_100 = safe_math::safe_percentage(1000, 50, 100); // 50%
    let result_1000 = safe_math::safe_percentage(1000, 500, 1000); // 50%
    assert!(result_100 == result_1000, 2);
}

#[test]
fun fuzz_test_collateral_ratio_extreme_values() {
    // Test with very high collateral values
    let max_collateral = 1_000_000_000_000_000u64;
    let min_borrowed = 1u64;
    let precision = 10000u64;
    
    let ratio = safe_math::calculate_collateral_ratio_safe(max_collateral, min_borrowed, precision);
    assert!(ratio > 0, 0);
    
    // Test with equal values
    let equal_value = 1_000_000_000u64;
    let equal_ratio = safe_math::calculate_collateral_ratio_safe(equal_value, equal_value, precision);
    assert!(equal_ratio == precision, 1); // Should be 100%
    
    // Test with maximum safe precision
    let max_precision = 1_000_000u64;
    let high_precision_ratio = safe_math::calculate_collateral_ratio_safe(
        1_500_000u64, 
        1_000_000u64, 
        max_precision
    );
    assert!(high_precision_ratio == max_precision * 3 / 2, 2); // 150%
}

#[test]
fun fuzz_test_compound_interest_extreme_scenarios() {
    // Test with maximum allowed rate and periods
    let principal = 1_000_000u64;
    let max_rate = 10000u64; // 100% per period
    let max_periods = 10u64; // Within approximation range
    let precision = 10000u64;
    
    let result = safe_math::calculate_compound_interest_safe(principal, max_rate, max_periods, precision);
    assert!(result > principal, 0);
    
    // Test with very small rates over many periods
    let small_rate = 1u64; // 0.01% per period
    let many_periods = 1000u64; // Maximum allowed periods
    let small_result = safe_math::calculate_compound_interest_safe(principal, small_rate, many_periods, precision);
    assert!(small_result > principal, 1);
    
    // Test with zero rate
    let zero_result = safe_math::calculate_compound_interest_safe(principal, 0, 100, precision);
    assert!(zero_result == principal, 2);
}

#[test]
fun fuzz_test_power_calculations_boundary() {
    // Test power calculations at boundaries
    assert!(safe_math::safe_pow(2, 63) > 0, 0); // Should not overflow
    assert!(safe_math::safe_pow(3, 40) > 0, 1); // Large but safe
    assert!(safe_math::safe_pow(10, 19) > 0, 2); // Close to MAX_U64
    
    // Test with base 1 (should always return 1)
    assert!(safe_math::safe_pow(1, 64) == 1, 3);
    
    // Test with various small bases and large exponents
    assert!(safe_math::safe_pow(2, 32) == 4_294_967_296u64, 4);
    assert!(safe_math::safe_pow(3, 20) == 3_486_784_401u64, 5);
}

#[test]
fun fuzz_test_sqrt_large_numbers() {
    // Test square root with very large numbers
    let max_u64 = 18_446_744_073_709_551_615u64;
    let sqrt_max = safe_math::safe_sqrt(max_u64);
    assert!(sqrt_max > 0, 0);
    
    // Verify the result is correct (sqrt_max^2 <= max_u64 < (sqrt_max+1)^2)
    assert!(safe_math::safe_mul(sqrt_max, sqrt_max) <= max_u64, 1);
    
    // Test with perfect large squares
    let large_square = 1_000_000_000_000u64; // 10^12
    let sqrt_result = safe_math::safe_sqrt(large_square);
    assert!(safe_math::safe_mul(sqrt_result, sqrt_result) == large_square, 2);
    
    // Test with powers of 2
    let power_of_2 = 1_152_921_504_606_846_976u64; // 2^60
    let sqrt_power = safe_math::safe_sqrt(power_of_2);
    assert!(sqrt_power == 1_073_741_824u64, 3); // 2^30
}

// ===== Property-Based Testing =====

#[test]
fun property_test_addition_commutativity() {
    // Test that a + b = b + a for various values
    let test_a = vector[100u64, 1_000_000u64, 9_223_372_036_854_775_807u64, 0u64];
    let test_b = vector[200u64, 2_000_000u64, 100u64, 1_000_000u64];
    
    let mut i = 0;
    while (i < test_a.length()) {
        let a = *vector::borrow(&test_a, i);
        let b = *vector::borrow(&test_b, i);
        assert!(safe_math::safe_add(a, b) == safe_math::safe_add(b, a), i);
        i = i + 1;
    };
}

#[test]
fun property_test_multiplication_commutativity() {
    // Test that a * b = b * a for various values
    let test_a = vector[100u64, 1_000u64, 4_294_967u64, 0u64];
    let test_b = vector[200u64, 2_000u64, 1_000u64, 1_000_000u64];
    
    let mut i = 0;
    while (i < test_a.length()) {
        let a = *vector::borrow(&test_a, i);
        let b = *vector::borrow(&test_b, i);
        assert!(safe_math::safe_mul(a, b) == safe_math::safe_mul(b, a), i);
        i = i + 1;
    };
}

#[test]
fun property_test_multiplication_identity() {
    // Test that a * 1 = a for various values
    let test_values = vector[
        0u64, 1u64, 100u64, 1_000_000u64, 
        18_446_744_073_709_551_615u64
    ];
    
    let mut i = 0;
    while (i < test_values.length()) {
        let a = *vector::borrow(&test_values, i);
        assert!(safe_math::safe_mul(a, 1) == a, i);
        i = i + 1;
    };
}

#[test]
fun property_test_addition_identity() {
    // Test that a + 0 = a for various values
    let test_values = vector[
        0u64, 1u64, 100u64, 1_000_000u64, 
        18_446_744_073_709_551_615u64
    ];
    
    let mut i = 0;
    while (i < test_values.length()) {
        let a = *vector::borrow(&test_values, i);
        assert!(safe_math::safe_add(a, 0) == a, i);
        i = i + 1;
    };
}

#[test]
fun property_test_subtraction_inverse() {
    // Test that (a + b) - b = a for various values
    let test_a = vector[100u64, 1_000_000u64, 9_223_372_036_854_775_807u64];
    let test_b = vector[50u64, 500_000u64, 100u64];
    
    let mut i = 0;
    while (i < test_a.length()) {
        let a = *vector::borrow(&test_a, i);
        let b = *vector::borrow(&test_b, i);
        let sum = safe_math::safe_add(a, b);
        assert!(safe_math::safe_sub(sum, b) == a, i);
        i = i + 1;
    };
}

#[test]
fun property_test_division_inverse() {
    // Test that (a * b) / b = a for various values
    let test_a = vector[100u64, 1_000_000u64, 4_294_967_295u64];
    let test_b = vector[50u64, 1000u64, 1000u64];
    
    let mut i = 0;
    while (i < test_a.length()) {
        let a = *vector::borrow(&test_a, i);
        let b = *vector::borrow(&test_b, i);
        let product = safe_math::safe_mul(a, b);
        assert!(safe_math::safe_div(product, b) == a, i);
        i = i + 1;
    };
}

#[test]
fun property_test_percentage_consistency() {
    // Test that percentage calculations are consistent across different basis points
    let amount = 1_000_000u64;
    let percentages = vector[5000u64, 500u64, 50u64];  // 50% in different basis systems
    let basis_points = vector[10000u64, 1000u64, 100u64];
    
    let mut results = vector::empty<u64>();
    let mut i = 0;
    while (i < percentages.length()) {
        let pct = *vector::borrow(&percentages, i);
        let basis = *vector::borrow(&basis_points, i);
        let result = safe_math::safe_percentage(amount, pct, basis);
        vector::push_back(&mut results, result);
        i = i + 1;
    };
    
    // All results should be equal (50% of amount)
    let expected = amount / 2;
    let mut j = 0;
    while (j < results.length()) {
        assert!(*vector::borrow(&results, j) == expected, j);
        j = j + 1;
    };
}

#[test]
fun property_test_sqrt_monotonicity() {
    // Test that sqrt is monotonic: if a <= b then sqrt(a) <= sqrt(b)
    let test_values = vector[
        0u64, 1u64, 4u64, 9u64, 16u64, 25u64, 100u64, 
        10000u64, 1000000u64, 1000000000000u64
    ];
    
    let mut i = 0;
    while (i < test_values.length() - 1) {
        let a = *vector::borrow(&test_values, i);
        let b = *vector::borrow(&test_values, i + 1);
        let sqrt_a = safe_math::safe_sqrt(a);
        let sqrt_b = safe_math::safe_sqrt(b);
        assert!(sqrt_a <= sqrt_b, i);
        i = i + 1;
    };
}

// ===== Mathematical Invariant Testing =====

#[test]
fun invariant_test_collateral_ratio_bounds() {
    // Test that collateral ratio is always >= 0 and behaves correctly
    let collaterals = vector[1000u64, 1000u64, 500u64, 1u64, 1000000u64];
    let borroweds = vector[500u64, 1000u64, 1000u64, 1000u64, 1u64];
    let precisions = vector[10000u64, 10000u64, 10000u64, 10000u64, 10000u64];
    
    let mut i = 0;
    while (i < collaterals.length()) {
        let collateral = *vector::borrow(&collaterals, i);
        let borrowed = *vector::borrow(&borroweds, i);
        let precision = *vector::borrow(&precisions, i);
        let ratio = safe_math::calculate_collateral_ratio_safe(collateral, borrowed, precision);
        
        // Ratio should always be positive
        assert!(ratio > 0, i * 10);
        
        // Ratio should be proportional to collateral/borrowed
        if (collateral >= borrowed) {
            assert!(ratio >= precision, i * 10 + 1); // >= 100%
        } else {
            assert!(ratio < precision, i * 10 + 2); // < 100%
        };
        
        i = i + 1;
    };
}

#[test]
fun invariant_test_compound_interest_growth() {
    // Test that compound interest always grows (or stays same for 0 rate)
    let principal = 1000000u64;
    let precision = 10000u64;
    
    let test_rates = vector[0u64, 100u64, 500u64, 1000u64]; // 0%, 1%, 5%, 10%
    let test_periods = vector[0u64, 1u64, 5u64, 10u64];
    
    let mut i = 0;
    while (i < test_rates.length()) {
        let rate = *vector::borrow(&test_rates, i);
        let mut j = 0;
        while (j < test_periods.length()) {
            let periods = *vector::borrow(&test_periods, j);
            let result = safe_math::calculate_compound_interest_safe(principal, rate, periods, precision);
            
            if (rate == 0 || periods == 0) {
                assert!(result == principal, i * 100 + j); // No growth
            } else {
                assert!(result >= principal, i * 100 + j); // Should grow
            };
            
            j = j + 1;
        };
        i = i + 1;
    };
}