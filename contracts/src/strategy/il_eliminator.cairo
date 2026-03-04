use starkyield::utils::constants::Constants;
use starkyield::utils::math::Math;

/// IL Eliminator — YieldBasis monitoring module
///
/// In YieldBasis, IL is structurally eliminated because the LP position is matched
/// 1:1 by a USDC CDP debt. This module is retained for monitoring and analytics only.
/// No active rebalancing is performed here; VirtualPool handles rebalancing externally.
///
/// IL Formula (reference): IL = 1 - 2*sqrt(r)/(1+r) where r = p1/p0

#[starknet::interface]
pub trait IILEliminator<TContractState> {
    /// Calculate Impermanent Loss for a given price change
    fn calculate_il(self: @TContractState, entry_price: u256, current_price: u256) -> (u256, bool);
    /// Calculate leverage position P&L
    fn calculate_leverage_pnl(
        self: @TContractState,
        entry_price: u256,
        current_price: u256,
        leverage: u256,
        position_size: u256,
    ) -> (u256, bool);
    /// Calculate optimal leverage based on volatility
    fn calculate_optimal_leverage(
        self: @TContractState, volatility: u256, trading_fees_apr: u256,
    ) -> u256;
    /// Calculate net position: leverage gains minus IL losses
    fn calculate_net_position(
        self: @TContractState, il_loss: u256, leverage_gain: u256, is_leverage_profit: bool,
    ) -> (u256, bool);
}

#[starknet::contract]
pub mod ILEliminator {
    use super::{IILEliminator, Constants, Math};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ILEliminatorImpl of IILEliminator<ContractState> {
        /// Calculate the Impermanent Loss percentage
        ///
        /// Formula: IL = 1 - (2 * sqrt(r) / (1 + r))
        /// where r = current_price / entry_price
        ///
        /// Returns (il_percentage scaled by 1e18, true if loss)
        fn calculate_il(
            self: @ContractState, entry_price: u256, current_price: u256,
        ) -> (u256, bool) {
            assert(entry_price > 0, 'Entry price must be > 0');
            assert(current_price > 0, 'Current price must be > 0');

            // If price hasn't changed, no IL
            if entry_price == current_price {
                return (0, false);
            }

            // price_ratio = current_price / entry_price (scaled 1e18)
            let price_ratio = Math::div_fixed(current_price, entry_price);

            // sqrt(price_ratio) — need to scale properly for sqrt
            // sqrt operates on raw values, so we need sqrt(price_ratio * SCALE) to get result in SCALE
            let sqrt_ratio = Math::sqrt(price_ratio * Constants::SCALE);

            // numerator = 2 * sqrt(price_ratio)
            let numerator = 2 * sqrt_ratio;

            // denominator = 1 + price_ratio (both in SCALE)
            let denominator = Constants::SCALE + price_ratio;

            // ratio = (2 * sqrt(r)) / (1 + r)
            let ratio = Math::div_fixed(numerator, denominator);

            if ratio >= Constants::SCALE {
                // No IL (rounding)
                (0, false)
            } else {
                // IL = 1 - ratio
                let il = Constants::SCALE - ratio;
                (il, true)
            }
        }

        /// Calculate P&L for a leveraged position
        ///
        /// PnL = position_size * price_change_pct * leverage
        ///
        /// Returns (pnl_amount, true if profit)
        fn calculate_leverage_pnl(
            self: @ContractState,
            entry_price: u256,
            current_price: u256,
            leverage: u256,
            position_size: u256,
        ) -> (u256, bool) {
            assert(entry_price > 0, 'Entry price must be > 0');
            assert(position_size > 0, 'Position size must be > 0');

            let (price_change, is_increase) = Math::percent_change(entry_price, current_price);

            // pnl = position_size * price_change * leverage / SCALE^2
            let pnl = Math::mul_fixed(Math::mul_fixed(position_size, price_change), leverage);

            (pnl, is_increase)
        }

        /// Calculate the optimal leverage to compensate IL
        ///
        /// Based on expected IL from volatility:
        /// expected_il ≈ volatility^2 / 8
        /// optimal_leverage = 1 + trading_fees / expected_il
        ///
        /// Clamped between 1.5x and 3x
        fn calculate_optimal_leverage(
            self: @ContractState, volatility: u256, trading_fees_apr: u256,
        ) -> u256 {
            // expected_il = volatility^2 / (8 * SCALE)
            let vol_squared = Math::mul_fixed(volatility, volatility);
            let expected_il = vol_squared / 8;

            if expected_il == 0 {
                // Low volatility, default to 2x
                return Constants::TARGET_LEVERAGE;
            }

            // optimal = 1 + fees / expected_il
            let fee_ratio = Math::div_fixed(trading_fees_apr, expected_il);
            let optimal = Constants::SCALE + fee_ratio;

            // Clamp between MIN_LEVERAGE (1.5x) and MAX_LEVERAGE (3x)
            Math::clamp(optimal, Constants::MIN_LEVERAGE, Constants::MAX_LEVERAGE)
        }

        /// Calculate net position after IL and leverage gains
        ///
        /// Returns (net_amount, true if net positive)
        fn calculate_net_position(
            self: @ContractState,
            il_loss: u256,
            leverage_gain: u256,
            is_leverage_profit: bool,
        ) -> (u256, bool) {
            if is_leverage_profit {
                // Leverage profit - IL loss
                if leverage_gain >= il_loss {
                    (leverage_gain - il_loss, true)
                } else {
                    (il_loss - leverage_gain, false)
                }
            } else {
                // Both are losses
                (il_loss + leverage_gain, false)
            }
        }
    }
}
