//! Mathematical utilities for StarkYield protocol
//!
//! This module provides fixed-point arithmetic operations and mathematical
//! functions needed for IL calculations, leverage computations, and price conversions.

use starkyield::utils::constants::Constants;

#[allow(unused)]

/// Fixed-point math operations
pub mod Math {
    use super::Constants;

    /// Calculate square root using Babylonian method (Newton's method)
    /// 
    /// # Arguments
    /// * `x` - The number to calculate square root of (scaled by 1e18)
    /// 
    /// # Returns
    /// Square root of x (scaled by 1e18)
    pub fn sqrt(x: u256) -> u256 {
        if x == 0 {
            return 0;
        }

        // Use x itself as initial guess, but cap it for efficiency
        // For Babylonian method, a smaller starting guess converges faster
        let mut guess = x;
        // Reduce initial guess by repeated halving to be closer to sqrt(x)
        let mut temp = x;
        let mut shift: u32 = 0;
        loop {
            if temp <= 1 {
                break;
            }
            temp = temp / 2;
            shift += 1;
        };
        // Initial guess ≈ 2^(shift/2)
        guess = 1;
        let half_shift = shift / 2;
        let mut j: u32 = 0;
        loop {
            if j >= half_shift {
                break;
            }
            guess = guess * 2;
            j += 1;
        };

        // Babylonian method — converges quadratically from a good initial guess
        let mut i: u8 = 0;
        loop {
            if i == 64 {
                break;
            }
            let new_guess = (guess + x / guess) / 2;

            // Check convergence
            let diff = if new_guess >= guess {
                new_guess - guess
            } else {
                guess - new_guess
            };
            guess = new_guess;
            if diff <= 1 {
                break;
            }
            i += 1;
        };

        guess
    }

    /// Multiply two fixed-point numbers (both scaled by 1e18)
    /// Result is scaled by 1e18
    pub fn mul_fixed(a: u256, b: u256) -> u256 {
        (a * b) / Constants::SCALE
    }

    /// Divide two fixed-point numbers (both scaled by 1e18)
    /// Result is scaled by 1e18
    pub fn div_fixed(a: u256, b: u256) -> u256 {
        if b == 0 {
            assert(false, 'Division by zero');
        }
        (a * Constants::SCALE) / b
    }

    /// Calculate absolute difference between two numbers
    pub fn abs_diff(a: u256, b: u256) -> u256 {
        if a >= b {
            a - b
        } else {
            b - a
        }
    }

    /// Calculate percentage change
    /// Returns the percentage change scaled by 1e18
    pub fn percent_change(old_value: u256, new_value: u256) -> (u256, bool) {
        if old_value == 0 {
            return (0, false);
        }

        if new_value >= old_value {
            let change = ((new_value - old_value) * Constants::SCALE) / old_value;
            (change, true) // true = increase
        } else {
            let change = ((old_value - new_value) * Constants::SCALE) / old_value;
            (change, false) // false = decrease
        }
    }

    /// Calculate price ratio (new_price / old_price) scaled by 1e18
    pub fn price_ratio(new_price: u256, old_price: u256) -> u256 {
        if old_price == 0 {
            assert(false, 'Old price cannot be zero');
        }
        (new_price * Constants::SCALE) / old_price
    }

    /// Minimum of two numbers
    pub fn min(a: u256, b: u256) -> u256 {
        if a <= b {
            a
        } else {
            b
        }
    }

    /// Maximum of two numbers
    pub fn max(a: u256, b: u256) -> u256 {
        if a >= b {
            a
        } else {
            b
        }
    }

    /// Clamp value between min and max
    pub fn clamp(value: u256, min_val: u256, max_val: u256) -> u256 {
        let clamped_min = max(value, min_val);
        min(clamped_min, max_val)
    }
}
