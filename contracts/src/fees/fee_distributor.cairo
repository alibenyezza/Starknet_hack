//! FeeDistributor — StarkYield fee distribution (accurate model)
//!
//! Receives the 50% distribution share of trading fees from LEVAMM.collect_fees().
//! The other 50% is auto-recycled into pool collateral by the LEVAMM itself.
//!
//! Distribution logic:
//!   1. Recovery Mode: if share price < HWM → 100% to recovery, admin fee waived
//!   2. Subtract volatility decay (rebalancing costs paid by arbitrageurs)
//!   3. Split net remainder:
//!      - f_a → veSY holders (protocol revenue / governance)
//!      - (1 - f_a) → UNSTAKED LT holders (direct trading fee yield)
//!      Note: STAKED LT holders do NOT receive trading fees — they get SY emissions instead
//!
//! Dynamic admin fee:
//!   f_a = 1 - (1 - f_min) * sqrt(1 - s/T)
//!   where s = staked LT, T = total LT supply, f_min = 10%
//!
//! All fractions are 1e18-scaled fixed-point.

use starknet::ContractAddress;

/// Minimal Staker facade — query total staked amount
#[starknet::interface]
trait IStakerQuery<TContractState> {
    fn get_total_staked(self: @TContractState) -> u256;
}

/// Minimal ERC-20 facade — query total supply + transfer
#[starknet::interface]
trait IERC20SupplyQuery<TContractState> {
    fn total_supply(self: @TContractState) -> u256;
}

/// Minimal ERC-20 facade — transfer
#[starknet::interface]
trait IERC20Transfer<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}

/// LtToken facade for distributing fees
#[starknet::interface]
trait ILtTokenFacade<TContractState> {
    fn distribute_fees(ref self: TContractState, amount: u256);
}

#[starknet::interface]
pub trait IFeeDistributor<TContractState> {
    /// Compute the dynamic admin fee fraction (1e18-scaled).
    /// f_a = 1 - (1 - f_min) * sqrt(1 - s/T)
    fn compute_admin_fee(self: @TContractState, staked_lt: u256, total_lt: u256) -> u256;

    /// Distribute the 50% distribution share of trading fees.
    /// Called by LEVAMM.collect_fees() after auto-recycling the pool share.
    fn distribute(ref self: TContractState, dist_amount: u256);

    /// Record CDP interest recycled into pool (accounting only).
    fn record_interest(ref self: TContractState, interest_amount: u256);

    /// Record volatility decay costs (deducted from next distribution).
    fn record_volatility_decay(ref self: TContractState, decay_amount: u256);

    // ── Getters ──────────────────────────────────────────────────────────
    fn get_accumulated_holder_fees(self: @TContractState) -> u256;
    fn get_accumulated_vesy_fees(self: @TContractState) -> u256;
    fn get_accumulated_recovery_fees(self: @TContractState) -> u256;
    fn get_accumulated_interest(self: @TContractState) -> u256;
    fn get_pending_volatility_decay(self: @TContractState) -> u256;
    fn get_total_fees_distributed(self: @TContractState) -> u256;
    fn is_recovery_mode(self: @TContractState) -> bool;

    // ── Claims ─────────────────────────────────────────────────────────────
    /// Permissionless: anyone can trigger holder fee distribution to LtToken.
    fn claim_holder_fees(ref self: TContractState) -> u256;
    /// Permissionless harvest: claim_holder_fees in one convenient call.
    fn harvest(ref self: TContractState);
    fn claim_vesy_fees(ref self: TContractState) -> u256;
    fn claim_recovery_fees(ref self: TContractState) -> u256;
    fn claim_interest(ref self: TContractState) -> u256;

    // ── Admin ────────────────────────────────────────────────────────────
    fn set_recovery_mode(ref self: TContractState, enabled: bool);
    fn set_staker(ref self: TContractState, staker: ContractAddress);
    fn set_lt_token(ref self: TContractState, lt_token: ContractAddress);
    fn set_usdc_token(ref self: TContractState, usdc_token: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod FeeDistributor {
    use super::{
        IFeeDistributor, ContractAddress,
        IStakerQueryDispatcher, IStakerQueryDispatcherTrait,
        IERC20SupplyQueryDispatcher, IERC20SupplyQueryDispatcherTrait,
        IERC20TransferDispatcher, IERC20TransferDispatcherTrait,
        ILtTokenFacadeDispatcher, ILtTokenFacadeDispatcherTrait,
    };
    use starknet::get_caller_address;
    use starkyield::utils::constants::Constants;
    use starkyield::utils::math::Math;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        staker: ContractAddress,
        lt_token: ContractAddress,
        usdc_token: ContractAddress,
        // Fee accumulators
        accumulated_holder_fees: u256,   // for unstaked LT holders
        accumulated_vesy_fees: u256,     // for veSY holders (admin fee)
        accumulated_recovery_fees: u256, // held during recovery mode
        accumulated_interest: u256,      // CDP interest accounting
        pending_volatility_decay: u256,  // rebalancing costs to deduct
        total_fees_distributed: u256,
        // High Watermark recovery mode
        recovery_mode: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        FeesDistributed: FeesDistributed,
        RecoveryFeesAccrued: RecoveryFeesAccrued,
        InterestRecorded: InterestRecorded,
        VolatilityDecayRecorded: VolatilityDecayRecorded,
        HolderFeesClaimed: HolderFeesClaimed,
        VesyFeesClaimed: VesyFeesClaimed,
        RecoveryFeesClaimed: RecoveryFeesClaimed,
        InterestClaimed: InterestClaimed,
        RecoveryModeChanged: RecoveryModeChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct FeesDistributed {
        dist_amount: u256,
        volatility_decay_deducted: u256,
        holder_share: u256,
        vesy_share: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RecoveryFeesAccrued { amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct InterestRecorded { amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct VolatilityDecayRecorded { amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct HolderFeesClaimed { amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct VesyFeesClaimed { amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct RecoveryFeesClaimed { amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct InterestClaimed { amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct RecoveryModeChanged { enabled: bool }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, usdc_token: ContractAddress) {
        self.owner.write(owner);
        self.usdc_token.write(usdc_token);
        self.recovery_mode.write(false);
    }

    #[abi(embed_v0)]
    impl FeeDistributorImpl of IFeeDistributor<ContractState> {
        /// Dynamic admin fee: f_a = 1 - (1 - f_min) * sqrt(1 - s/T)
        /// All values 1e18-scaled.
        fn compute_admin_fee(self: @ContractState, staked_lt: u256, total_lt: u256) -> u256 {
            if total_lt == 0 {
                return Constants::MIN_ADMIN_FEE;
            }
            let scale = Constants::SCALE;
            let ratio = Math::div_fixed(staked_lt, total_lt);
            let one_minus_ratio = if ratio >= scale { 0 } else { scale - ratio };
            // sqrt(one_minus_ratio * SCALE) = sqrt(r) * 1e18 — already 1e18-scaled
            let sqrt_val = Math::sqrt(one_minus_ratio * scale);
            let one_minus_fmin = scale - Constants::MIN_ADMIN_FEE;
            let term = Math::mul_fixed(one_minus_fmin, sqrt_val);
            if term >= scale { 0 } else { scale - term }
        }

        /// Distribute the 50% distribution share (StarkYield model).
        ///
        /// 1. Recovery mode → 100% to recovery, admin fee waived
        /// 2. Subtract pending volatility decay
        /// 3. Split: f_a → veSY, (1-f_a) → unstaked holders
        fn distribute(ref self: ContractState, dist_amount: u256) {
            if dist_amount == 0 { return; }

            self.total_fees_distributed.write(self.total_fees_distributed.read() + dist_amount);

            // ── Recovery Mode: 100% to restore LP value, admin fee waived ──
            if self.recovery_mode.read() {
                self.accumulated_recovery_fees.write(
                    self.accumulated_recovery_fees.read() + dist_amount
                );
                self.emit(RecoveryFeesAccrued { amount: dist_amount });
                return;
            }

            // ── Subtract volatility decay (rebalancing costs) ──
            let decay = self.pending_volatility_decay.read();
            let decay_deducted = if decay > dist_amount { dist_amount } else { decay };
            let net_amount = dist_amount - decay_deducted;
            self.pending_volatility_decay.write(decay - decay_deducted);

            if net_amount == 0 {
                self.emit(FeesDistributed {
                    dist_amount, volatility_decay_deducted: decay_deducted,
                    holder_share: 0, vesy_share: 0,
                });
                return;
            }

            // ── Dynamic admin fee split ──
            let (staked_lt, total_lt) = self._get_staking_info();
            let admin_fee_frac = self.compute_admin_fee(staked_lt, total_lt);
            let vesy_share = Math::mul_fixed(net_amount, admin_fee_frac);
            let holder_share = net_amount - vesy_share;

            // veSY holders get admin fee portion
            self.accumulated_vesy_fees.write(self.accumulated_vesy_fees.read() + vesy_share);
            // Unstaked LT holders get the rest
            self.accumulated_holder_fees.write(self.accumulated_holder_fees.read() + holder_share);

            self.emit(FeesDistributed {
                dist_amount, volatility_decay_deducted: decay_deducted,
                holder_share, vesy_share,
            });
        }

        /// Record CDP interest recycled into pool (accounting).
        fn record_interest(ref self: ContractState, interest_amount: u256) {
            if interest_amount == 0 { return; }
            self.accumulated_interest.write(self.accumulated_interest.read() + interest_amount);
            self.emit(InterestRecorded { amount: interest_amount });
        }

        /// Record volatility decay costs to deduct from next distribution.
        fn record_volatility_decay(ref self: ContractState, decay_amount: u256) {
            if decay_amount == 0 { return; }
            self.pending_volatility_decay.write(
                self.pending_volatility_decay.read() + decay_amount
            );
            self.emit(VolatilityDecayRecorded { amount: decay_amount });
        }

        // ── Getters ──────────────────────────────────────────────────────

        fn get_accumulated_holder_fees(self: @ContractState) -> u256 {
            self.accumulated_holder_fees.read()
        }
        fn get_accumulated_vesy_fees(self: @ContractState) -> u256 {
            self.accumulated_vesy_fees.read()
        }
        fn get_accumulated_recovery_fees(self: @ContractState) -> u256 {
            self.accumulated_recovery_fees.read()
        }
        fn get_accumulated_interest(self: @ContractState) -> u256 {
            self.accumulated_interest.read()
        }
        fn get_pending_volatility_decay(self: @ContractState) -> u256 {
            self.pending_volatility_decay.read()
        }
        fn get_total_fees_distributed(self: @ContractState) -> u256 {
            self.total_fees_distributed.read()
        }
        fn is_recovery_mode(self: @ContractState) -> bool {
            self.recovery_mode.read()
        }

        // ── Claims ──────────────────────────────────────────────────────────

        /// Claim holder fees — transfers USDC to LtToken for pro-rata distribution.
        /// Permissionless: anyone can trigger this to flush accumulated fees to LT holders.
        fn claim_holder_fees(ref self: ContractState) -> u256 {
            let amount = self.accumulated_holder_fees.read();
            if amount > 0 {
                self.accumulated_holder_fees.write(0);
                // Transfer USDC to LtToken and trigger distribution
                let lt_addr = self.lt_token.read();
                let usdc = IERC20TransferDispatcher { contract_address: self.usdc_token.read() };
                let zero: ContractAddress = 0.try_into().unwrap();
                if lt_addr != zero {
                    usdc.transfer(lt_addr, amount);
                    ILtTokenFacadeDispatcher { contract_address: lt_addr }.distribute_fees(amount);
                }
            }
            self.emit(HolderFeesClaimed { amount });
            amount
        }

        /// Permissionless harvest: flush accumulated holder fees to LtToken.
        fn harvest(ref self: ContractState) {
            self.claim_holder_fees();
        }

        /// Claim veSY fees — transfers USDC to caller (owner/treasury).
        fn claim_vesy_fees(ref self: ContractState) -> u256 {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            let amount = self.accumulated_vesy_fees.read();
            if amount > 0 {
                self.accumulated_vesy_fees.write(0);
                IERC20TransferDispatcher { contract_address: self.usdc_token.read() }
                    .transfer(get_caller_address(), amount);
            }
            self.emit(VesyFeesClaimed { amount });
            amount
        }

        /// Claim recovery fees — transfers USDC to caller (for LP restoration).
        fn claim_recovery_fees(ref self: ContractState) -> u256 {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            let amount = self.accumulated_recovery_fees.read();
            if amount > 0 {
                self.accumulated_recovery_fees.write(0);
                IERC20TransferDispatcher { contract_address: self.usdc_token.read() }
                    .transfer(get_caller_address(), amount);
            }
            self.emit(RecoveryFeesClaimed { amount });
            amount
        }

        /// Claim interest — distributes accumulated interest to LT holders.
        /// Permissionless. Interest is already recycled into collateral_value by LEVAMM
        /// (increases share price), so this only redistributes any USDC that was
        /// explicitly sent to FeeDistributor for interest. Resets the counter regardless.
        fn claim_interest(ref self: ContractState) -> u256 {
            let amount = self.accumulated_interest.read();
            if amount > 0 {
                self.accumulated_interest.write(0);
                // Route to LT holders via LtToken (same path as holder fees)
                let lt_addr = self.lt_token.read();
                let usdc = IERC20TransferDispatcher { contract_address: self.usdc_token.read() };
                let zero: ContractAddress = 0.try_into().unwrap();
                if lt_addr != zero {
                    usdc.transfer(lt_addr, amount);
                    ILtTokenFacadeDispatcher { contract_address: lt_addr }.distribute_fees(amount);
                }
            }
            self.emit(InterestClaimed { amount });
            amount
        }

        // ── Admin ────────────────────────────────────────────────────────

        /// Toggle recovery mode (High Watermark mechanism).
        /// When enabled: 100% of fees go to restore LP value, admin fee waived.
        fn set_recovery_mode(ref self: ContractState, enabled: bool) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.recovery_mode.write(enabled);
            self.emit(RecoveryModeChanged { enabled });
        }

        fn set_staker(ref self: ContractState, staker: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.staker.write(staker);
        }

        fn set_lt_token(ref self: ContractState, lt_token: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.lt_token.write(lt_token);
        }

        fn set_usdc_token(ref self: ContractState, usdc_token: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.usdc_token.write(usdc_token);
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Query staker and LT token for current staking info.
        fn _get_staking_info(self: @ContractState) -> (u256, u256) {
            let staker_addr = self.staker.read();
            let lt_addr = self.lt_token.read();
            let zero: ContractAddress = 0.try_into().unwrap();

            let staked = if staker_addr != zero {
                IStakerQueryDispatcher { contract_address: staker_addr }.get_total_staked()
            } else {
                0
            };

            let total = if lt_addr != zero {
                IERC20SupplyQueryDispatcher { contract_address: lt_addr }.total_supply()
            } else {
                0
            };

            (staked, total)
        }
    }
}
