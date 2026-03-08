use starkyield::utils::constants::Constants;
use starkyield::utils::math::Math;

/// Health status levels for the protocol
#[derive(Drop, Copy, PartialEq)]
pub enum HealthStatus {
    Safe,       // HF > 2.0
    Moderate,   // 1.5 < HF <= 2.0
    Warning,    // 1.2 < HF <= 1.5
    Danger,     // HF <= 1.2
}

/// Risk Manager — StarkYield protocol safety monitor
///
/// In StarkYield the health factor is LP-based:
///   HF = LP_value / (debt × LIQUIDATION_THRESHOLD)
/// where LP_value = Ekubo pool value of the CDP collateral (USDC, 18-decimal).
/// The `collateral` parameter throughout this module refers to LP value, not raw BTC.
///
/// Responsibilities:
/// - Health factor classification
/// - Deleverage amount calculations
/// - Price sanity checks
/// - Withdrawal limit enforcement

#[starknet::interface]
pub trait IRiskManager<TContractState> {
    /// Assess health status from health factor
    fn assess_health(self: @TContractState, health_factor: u256) -> u8;
    /// Calculate how much to deleverage to reach target HF
    fn calculate_deleverage_amount(
        self: @TContractState,
        current_hf: u256,
        target_hf: u256,
        collateral: u256,
        debt: u256,
    ) -> u256;
    /// Check if a price change is within sanity bounds
    fn check_price_sanity(
        self: @TContractState, new_price: u256, last_price: u256,
    ) -> bool;
    /// Check if withdrawal is within daily limits
    fn check_withdrawal_limit(
        self: @TContractState, amount: u256,
    ) -> bool;
    /// Record a withdrawal for limit tracking
    fn record_withdrawal(ref self: TContractState, amount: u256);
    /// Reset daily withdrawal counter (called at day boundary)
    fn reset_daily_withdrawals(ref self: TContractState);
    /// Check if rebalance is needed
    fn needs_rebalance(
        self: @TContractState, current_leverage: u256, target_leverage: u256,
    ) -> bool;
    /// Get max daily withdrawal limit
    fn get_max_daily_withdrawal(self: @TContractState) -> u256;
    /// Set max daily withdrawal limit (admin)
    fn set_max_daily_withdrawal(ref self: TContractState, max_amount: u256);
}

#[starknet::contract]
pub mod RiskManager {
    use super::{IRiskManager, Constants, Math};
    use starknet::get_caller_address;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        max_daily_withdrawal: u256,
        daily_withdrawal_used: u256,
        last_reset_timestamp: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RiskAlert: RiskAlert,
        DeleverageTriggered: DeleverageTriggered,
    }

    #[derive(Drop, starknet::Event)]
    struct RiskAlert {
        health_factor: u256,
        status: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct DeleverageTriggered {
        deleverage_amount: u256,
        current_hf: u256,
        target_hf: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        max_daily_withdrawal: u256,
    ) {
        self.owner.write(owner);
        self.max_daily_withdrawal.write(max_daily_withdrawal);
    }

    #[abi(embed_v0)]
    impl RiskManagerImpl of IRiskManager<ContractState> {
        /// Assess health status and return a numeric code
        /// 0 = Safe, 1 = Moderate, 2 = Warning, 3 = Danger
        fn assess_health(self: @ContractState, health_factor: u256) -> u8 {
            if health_factor > Constants::SAFE_HEALTH_FACTOR {
                0 // Safe
            } else if health_factor > Constants::MODERATE_HEALTH_FACTOR {
                1 // Moderate
            } else if health_factor > Constants::MIN_HEALTH_FACTOR {
                2 // Warning
            } else {
                3 // Danger
            }
        }

        /// Calculate the amount of debt to repay to bring HF to target
        ///
        /// HF = collateral / (debt * liquidation_threshold)
        /// target_hf = (collateral - deleverage_value) / ((debt - deleverage_value) * LT)
        ///
        /// Solving for deleverage_value:
        /// deleverage = (debt * LT * target_hf - collateral) / (LT * target_hf - 1)
        fn calculate_deleverage_amount(
            self: @ContractState,
            current_hf: u256,
            target_hf: u256,
            collateral: u256,
            debt: u256,
        ) -> u256 {
            // If already at target, no deleverage needed
            if current_hf >= target_hf {
                return 0;
            }

            if debt == 0 {
                return 0;
            }

            let lt = Constants::LIQUIDATION_THRESHOLD;

            // numerator = debt * LT * target_hf - collateral * SCALE
            let debt_lt_target = Math::mul_fixed(Math::mul_fixed(debt, lt), target_hf);

            if debt_lt_target <= collateral {
                return 0;
            }

            let numerator = debt_lt_target - collateral;

            // denominator = LT * target_hf - SCALE
            let lt_target = Math::mul_fixed(lt, target_hf);
            if lt_target <= Constants::SCALE {
                // Edge case: would need to repay everything
                return debt;
            }
            let denominator = lt_target - Constants::SCALE;

            Math::div_fixed(numerator, denominator)
        }

        /// Check if the price change is within acceptable deviation
        fn check_price_sanity(
            self: @ContractState, new_price: u256, last_price: u256,
        ) -> bool {
            if last_price == 0 {
                return true; // First price, always accept
            }

            let deviation = Math::abs_diff(new_price, last_price);
            let deviation_pct = Math::div_fixed(deviation, last_price);

            deviation_pct <= Constants::MAX_PRICE_DEVIATION
        }

        /// Check if a withdrawal amount is within daily limits
        fn check_withdrawal_limit(self: @ContractState, amount: u256) -> bool {
            let max = self.max_daily_withdrawal.read();
            if max == 0 {
                return true; // No limit set
            }
            let used = self.daily_withdrawal_used.read();
            used + amount <= max
        }

        /// Record a withdrawal for daily limit tracking
        fn record_withdrawal(ref self: ContractState, amount: u256) {
            let current = self.daily_withdrawal_used.read();
            self.daily_withdrawal_used.write(current + amount);
        }

        /// Reset daily withdrawal counter
        fn reset_daily_withdrawals(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.daily_withdrawal_used.write(0);
        }

        /// Check if leverage deviation exceeds rebalance threshold
        fn needs_rebalance(
            self: @ContractState, current_leverage: u256, target_leverage: u256,
        ) -> bool {
            let deviation = Math::abs_diff(current_leverage, target_leverage);
            deviation > Constants::REBALANCE_THRESHOLD
        }

        /// Get the max daily withdrawal limit
        fn get_max_daily_withdrawal(self: @ContractState) -> u256 {
            self.max_daily_withdrawal.read()
        }

        /// Set the max daily withdrawal limit (admin only)
        fn set_max_daily_withdrawal(ref self: ContractState, max_amount: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.max_daily_withdrawal.write(max_amount);
        }
    }
}
