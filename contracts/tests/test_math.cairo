//! Tests for Math utilities

use starkyield::utils::math::Math;

#[cfg(test)]
mod tests {
    use super::Math;

    const SCALE: u256 = 1_000000000000000000;

    // ═══════════════════════════════════════════════════════
    // SQRT TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_sqrt_of_one() {
        // sqrt(1e18) should be approximately 1e9
        let result = Math::sqrt(SCALE);
        // sqrt(1e18) = 1e9
        let expected = 1_000000000;
        let diff = if result >= expected { result - expected } else { expected - result };
        assert(diff <= 1, 'sqrt(1e18) should be ~1e9');
    }

    #[test]
    fn test_sqrt_of_four() {
        // sqrt(4e18) should be approximately 2e9
        let result = Math::sqrt(4 * SCALE);
        let expected = 2_000000000;
        let diff = if result >= expected { result - expected } else { expected - result };
        assert(diff <= 1, 'sqrt(4e18) should be ~2e9');
    }

    #[test]
    fn test_sqrt_of_zero() {
        let result = Math::sqrt(0);
        assert(result == 0, 'sqrt(0) should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // FIXED-POINT ARITHMETIC TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_mul_fixed() {
        // 2.0 * 3.0 = 6.0
        let a = 2 * SCALE;
        let b = 3 * SCALE;
        let result = Math::mul_fixed(a, b);
        assert(result == 6 * SCALE, '2.0 * 3.0 should be 6.0');
    }

    #[test]
    fn test_mul_fixed_decimal() {
        // 1.5 * 2.0 = 3.0
        let a = 1_500000000000000000; // 1.5
        let b = 2 * SCALE;
        let result = Math::mul_fixed(a, b);
        assert(result == 3 * SCALE, '1.5 * 2.0 should be 3.0');
    }

    #[test]
    fn test_div_fixed() {
        // 6.0 / 3.0 = 2.0
        let a = 6 * SCALE;
        let b = 3 * SCALE;
        let result = Math::div_fixed(a, b);
        assert(result == 2 * SCALE, '6.0 / 3.0 should be 2.0');
    }

    #[test]
    fn test_div_fixed_decimal() {
        // 1.0 / 2.0 = 0.5
        let a = SCALE;
        let b = 2 * SCALE;
        let result = Math::div_fixed(a, b);
        let expected = 500000000000000000; // 0.5e18
        assert(result == expected, '1.0 / 2.0 should be 0.5');
    }

    #[test]
    #[should_panic]
    fn test_div_fixed_by_zero() {
        Math::div_fixed(SCALE, 0);
    }

    // ═══════════════════════════════════════════════════════
    // UTILITY FUNCTION TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_abs_diff() {
        assert(Math::abs_diff(10, 3) == 7, '|10-3| should be 7');
        assert(Math::abs_diff(3, 10) == 7, '|3-10| should be 7');
        assert(Math::abs_diff(5, 5) == 0, '|5-5| should be 0');
    }

    #[test]
    fn test_min() {
        assert(Math::min(3, 5) == 3, 'min(3,5) should be 3');
        assert(Math::min(5, 3) == 3, 'min(5,3) should be 3');
        assert(Math::min(4, 4) == 4, 'min(4,4) should be 4');
    }

    #[test]
    fn test_max() {
        assert(Math::max(3, 5) == 5, 'max(3,5) should be 5');
        assert(Math::max(5, 3) == 5, 'max(5,3) should be 5');
        assert(Math::max(4, 4) == 4, 'max(4,4) should be 4');
    }

    #[test]
    fn test_clamp() {
        assert(Math::clamp(5, 1, 10) == 5, 'clamp 5 in [1,10] = 5');
        assert(Math::clamp(0, 1, 10) == 1, 'clamp 0 in [1,10] = 1');
        assert(Math::clamp(15, 1, 10) == 10, 'clamp 15 in [1,10] = 10');
    }

    // ═══════════════════════════════════════════════════════
    // PERCENT CHANGE TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_percent_change_increase() {
        let (change, is_increase) = Math::percent_change(100 * SCALE, 150 * SCALE);
        assert(is_increase, 'Should be increase');
        let expected = 500000000000000000; // 50% = 0.5e18
        assert(change == expected, '50% increase');
    }

    #[test]
    fn test_percent_change_decrease() {
        let (change, is_increase) = Math::percent_change(100 * SCALE, 80 * SCALE);
        assert(!is_increase, 'Should be decrease');
        let expected = 200000000000000000; // 20% = 0.2e18
        assert(change == expected, '20% decrease');
    }

    #[test]
    fn test_percent_change_zero_old() {
        let (change, _) = Math::percent_change(0, 100 * SCALE);
        assert(change == 0, 'Zero old value returns 0');
    }

    // ═══════════════════════════════════════════════════════
    // PRICE RATIO TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_price_ratio_double() {
        let ratio = Math::price_ratio(120000 * SCALE, 60000 * SCALE);
        assert(ratio == 2 * SCALE, 'Ratio should be 2.0');
    }

    #[test]
    fn test_price_ratio_half() {
        let ratio = Math::price_ratio(30000 * SCALE, 60000 * SCALE);
        let expected = 500000000000000000; // 0.5
        assert(ratio == expected, 'Ratio should be 0.5');
    }
}
