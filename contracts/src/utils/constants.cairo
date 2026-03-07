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

    // ── Token decimals ────────────────────────────────────────────────────────

    /// BTC token decimals (matches real wBTC: 8)
    pub const BTC_DECIMALS: u8 = 8;

    /// USDC token decimals (matches real USDC: 6)
    pub const USDC_DECIMALS: u8 = 6;

    /// Internal 18-decimal precision used for fixed-point math
    pub const INTERNAL_DECIMALS: u8 = 18;

    /// Scale factor to normalise raw BTC (8 dec) → internal (18 dec): 10^(18-8) = 1e10
    pub const BTC_SCALE_FACTOR: u256 = 10_000_000_000;

    /// Scale factor to normalise raw USDC (6 dec) → internal (18 dec): 10^(18-6) = 1e12
    pub const USDC_SCALE_FACTOR: u256 = 1_000_000_000_000;

    /// Minimum shares burned on first EkuboLPWrapper deposit (inflation-attack guard)
    pub const MIN_INITIAL_SHARES: u256 = 1_000;

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

    // ── LEVAMM constants ─────────────────────────────────────────────────────

    /// Leverage ratio for 2× leverage: (L/(L+1))^2 = (2/3)^2 = 4/9 scaled to 1e18
    /// 4e18 / 9 = 444_444_444_444_444_444
    pub const LEV_RATIO_2X: u256 = 444_444_444_444_444_444;

    /// Safety band minimum DTV for 2× leverage: 6.25% (1e18-scaled)
    pub const DTV_MIN_2X: u256 = 62_500_000_000_000_000;

    /// Safety band maximum DTV for 2× leverage: 53.125% (1e18-scaled)
    pub const DTV_MAX_2X: u256 = 531_250_000_000_000_000;

    /// Default Staker reward rate: 1e12 syYB per block per unit staked
    pub const DEFAULT_REWARD_RATE: u256 = 1_000_000_000_000;

    // ── YieldBasis constants ──────────────────────────────────────────────────

    /// Share of trading fees recycled into the Ekubo pool (50% = 0.5e18)
    pub const FEE_POOL_SHARE: u256 = 500_000_000_000_000_000;

    /// Share of trading fees distributed to LT holders / vesyYB (50% = 0.5e18)
    pub const FEE_DIST_SHARE: u256 = 500_000_000_000_000_000;

    /// Minimum admin fee fraction f_min (10% = 0.1e18)
    pub const MIN_ADMIN_FEE: u256 = 100_000_000_000_000_000;

    /// Flash loan fee — fee-less per YieldBasis design (0%)
    pub const FLASH_LOAN_FEE: u256 = 0;

    /// Target DTV for 2× leverage CDP position (50% = 0.5e18)
    pub const TARGET_DTV: u256 = 500_000_000_000_000_000;

    /// Fraction of CDP interest recycled into Ekubo pool (100% = 1e18)
    pub const INTEREST_RECYCLE_RATE: u256 = 1_000_000_000_000_000_000;
}
