//! Constants for StarkYield protocol
//! 
//! This module defines all protocol-wide constants including:
//! - Scaling factors for fixed-point arithmetic
//! - Leverage limits
//! - Health factor thresholds
//! - Risk parameters

pub mod Constants {
    /// Scaling factor for fixed-point arithmetic (1e18)
    pub const SCALE: u256 = 1_000000000000000000;

    /// Target leverage ratio (2x = 2e18)
    pub const TARGET_LEVERAGE: u256 = 2_000000000000000000;

    /// Maximum allowed leverage (3x = 3e18)
    pub const MAX_LEVERAGE: u256 = 3_000000000000000000;

    /// Minimum leverage (1.5x = 1.5e18)
    pub const MIN_LEVERAGE: u256 = 1_500000000000000000;

    /// Minimum health factor before deleveraging (1.2 = 1.2e18)
    pub const MIN_HEALTH_FACTOR: u256 = 1_200000000000000000;

    /// Health factor threshold for moderate risk (1.5 = 1.5e18)
    pub const MODERATE_HEALTH_FACTOR: u256 = 1_500000000000000000;

    /// Health factor threshold for safe zone (2.0 = 2.0e18)
    pub const SAFE_HEALTH_FACTOR: u256 = 2_000000000000000000;

    /// Liquidation threshold (85% = 0.85e18)
    pub const LIQUIDATION_THRESHOLD: u256 = 850000000000000000;

    /// Maximum price deviation allowed (10% = 0.1e18)
    pub const MAX_PRICE_DEVIATION: u256 = 100000000000000000;

    /// Price staleness threshold in seconds (1 hour = 3600)
    pub const PRICE_STALENESS_THRESHOLD: u64 = 3600;

    /// Rebalance threshold (0.1x = 0.1e18) - triggers rebalance if leverage differs by this amount
    pub const REBALANCE_THRESHOLD: u256 = 100000000000000000;

    /// Default slippage tolerance (0.5% = 0.005e18)
    pub const DEFAULT_SLIPPAGE: u256 = 5000000000000000;
}
