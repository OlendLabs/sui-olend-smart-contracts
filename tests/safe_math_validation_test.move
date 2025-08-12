#[test_only]
module olend::safe_math_validation_test;

use olend::safe_math;

#[test]
fun test_sqrt_basic_functionality() {
    // Test basic sqrt functionality
    assert!(safe_math::safe_sqrt(0) == 0, 0);
    assert!(safe_math::safe_sqrt(1) == 1, 1);
    assert!(safe_math::safe_sqrt(4) == 2, 2);
    assert!(safe_math::safe_sqrt(9) == 3, 3);
    assert!(safe_math::safe_sqrt(16) == 4, 4);
}

#[test]
fun test_sqrt_large_safe_values() {
    // Test with large but safe values
    let large_square = 1_000_000_000_000u64; // 10^12
    let sqrt_result = safe_math::safe_sqrt(large_square);
    assert!(sqrt_result == 1_000_000u64, 0); // 10^6
    
    // Test with another large perfect square
    let square_100k = 10_000_000_000u64; // 10^10
    assert!(safe_math::safe_sqrt(square_100k) == 100_000u64, 1); // 10^5
}

#[test]
fun test_mul_div_alternative_paths() {
    // Test that mul_div uses alternative calculation paths correctly
    let max_u64 = 18_446_744_073_709_551_615u64;
    let large_a = max_u64 / 2 + 1;
    let large_b = 3;
    let result = safe_math::safe_mul_div(large_a, large_b, 2);
    assert!(result > 0, 0); // Should succeed
}

#[test]
fun test_basic_operations_work() {
    // Test that basic operations still work
    assert!(safe_math::safe_add(100, 200) == 300, 0);
    assert!(safe_math::safe_mul(10, 20) == 200, 1);
    assert!(safe_math::safe_sub(300, 100) == 200, 2);
    assert!(safe_math::safe_div(100, 10) == 10, 3);
}