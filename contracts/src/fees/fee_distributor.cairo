//! FeeDistributor — YieldBasis fee split and dynamic admin fee
//!
//! Fee model:
//!   - 50% of Ekubo trading fees → recycled into pool (FEE_POOL_SHARE)
//!   - 50% of fees → distributed to LT holders / vesyYB (FEE_DIST_SHARE)
//!   - Admin fee fraction: f_a = 1 - (1 - f_min) * sqrt(1 - s/T)
//!     where s = staked LT, T = total LT supply, f_min = 10%
//!
//! All fractions are 1e18-scaled fixed-point.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IFeeDistributor<TContractState> {
    /// Compute the dynamic admin fee fraction (1e18-scaled).
    /// f_a = 1 - (1 - f_min) * sqrt(1 - s/T)
    fn compute_admin_fee(self: @TContractState, staked_lt: u256, total_lt: u256) -> u256;

    /// Distribute `fee_amount` USDC according to 50/50 split (stub).
    fn distribute(ref self: TContractState, fee_amount: u256);

    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod FeeDistributor {
    use super::IFeeDistributor;
    use starknet::ContractAddress;
    use starkyield::utils::constants::Constants;
    use starkyield::utils::math::Math;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        total_fees_distributed: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        FeesDistributed: FeesDistributed,
    }

    #[derive(Drop, starknet::Event)]
    struct FeesDistributed {
        pool_share: u256,
        dist_share: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl FeeDistributorImpl of IFeeDistributor<ContractState> {
        /// Dynamic admin fee: f_a = 1 - (1 - f_min) * sqrt(1 - s/T)
        /// All values 1e18-scaled. Uses integer square-root approximation.
        fn compute_admin_fee(self: @ContractState, staked_lt: u256, total_lt: u256) -> u256 {
            if total_lt == 0 {
                return Constants::MIN_ADMIN_FEE;
            }
            let scale = Constants::SCALE;
            // ratio = s / T  (1e18-scaled)
            let ratio = Math::div_fixed(staked_lt, total_lt);
            // one_minus_ratio = 1 - s/T
            let one_minus_ratio = if ratio >= scale { 0 } else { scale - ratio };
            // sqrt_val = sqrt(one_minus_ratio * 1e18) / 1e9  ≈ sqrt(1 - s/T) in 1e18
            let sqrt_val = Math::sqrt(one_minus_ratio * scale) / 1_000_000_000_u256;
            let one_minus_fmin = scale - Constants::MIN_ADMIN_FEE;
            let term = Math::mul_fixed(one_minus_fmin, sqrt_val);
            if term >= scale { 0 } else { scale - term }
        }

        /// Distribute fee (stub): emits a 50/50 split event.
        fn distribute(ref self: ContractState, fee_amount: u256) {
            let pool_share = Math::mul_fixed(fee_amount, Constants::FEE_POOL_SHARE);
            let dist_share = fee_amount - pool_share;
            self.total_fees_distributed.write(self.total_fees_distributed.read() + fee_amount);
            self.emit(FeesDistributed { pool_share, dist_share });
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
