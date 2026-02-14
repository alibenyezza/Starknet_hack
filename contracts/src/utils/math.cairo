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
        if x < Constants::SCALE {
            return 0;
        }

        // Start with an initial guess
        let mut guess = x / 2 + 1;
        let mut prev_guess = 0;

        // Iterate until convergence (max 20 iterations for safety)
        let mut i: u8 = 0;
        loop {
            if i == 20 {
                break;
            }
            prev_guess = guess;
            guess = (guess + x / guess) / 2;
            
            // Check if we've converged (difference < 1)
            if guess >= prev_guess {
                if guess - prev_guess <= 1 {
                    break;
                }
            } else {
                if prev_guess - guess <= 1 {
                    break;
                }
            }
            i += 1;
        }

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
