//! LiquidityGauge — Distributes sy-WBTC emissions to LT stakers based on gauge weight.
//!
//! Users deposit LT tokens (transfer_from) and earn sy-WBTC emissions proportional to
//! their share of the gauge. Uses accumulated-reward-per-share (MasterChef) pattern.
//!
//! notify_reward() is called by the emission controller to add new sy-WBTC rewards.

use starknet::ContractAddress;

/// Minimal ERC-20 facade
#[starknet::interface]
trait IERC20Facade<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}

/// Minimal sy-WBTC mint facade
#[starknet::interface]
trait ISyYbMintFacade<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}

#[starknet::interface]
pub trait ILiquidityGauge<TContractState> {
    fn deposit(ref self: TContractState, amount: u256);
    fn withdraw(ref self: TContractState, amount: u256);
    fn claim_rewards(ref self: TContractState) -> u256;
    fn get_claimable_rewards(self: @TContractState, user: ContractAddress) -> u256;
    fn notify_reward(ref self: TContractState, sy_yb_amount: u256);
    fn get_total_staked(self: @TContractState) -> u256;
    fn get_staked_balance(self: @TContractState, user: ContractAddress) -> u256;
}

#[starknet::contract]
pub mod LiquidityGauge {
    use super::{
        ILiquidityGauge, ContractAddress,
        IERC20FacadeDispatcher, IERC20FacadeDispatcherTrait,
        ISyYbMintFacadeDispatcher, ISyYbMintFacadeDispatcherTrait,
    };
    use starknet::{get_caller_address, get_contract_address};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};

    const SCALE: u256 = 1_000000000000000000;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        lt_token: ContractAddress,
        sy_yb_token: ContractAddress,
        staked_balances: Map<ContractAddress, u256>,
        total_staked: u256,
        // MasterChef accumulated reward per share (1e18-scaled)
        acc_reward_per_share: u256,
        // Per-user reward debt
        reward_debt: Map<ContractAddress, u256>,
        // Pending rewards pool (sy-WBTC tokens available for distribution)
        pending_rewards_pool: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        RewardClaimed: RewardClaimed,
        RewardNotified: RewardNotified,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposited { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct RewardClaimed { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct RewardNotified { amount: u256 }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        lt_token: ContractAddress,
        sy_yb_token: ContractAddress,
    ) {
        self.owner.write(owner);
        self.lt_token.write(lt_token);
        self.sy_yb_token.write(sy_yb_token);
    }

    #[abi(embed_v0)]
    impl LiquidityGaugeImpl of ILiquidityGauge<ContractState> {
        /// Deposit LT tokens into the gauge. Transfers LT from caller.
        fn deposit(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            let user = get_caller_address();

            // Settle pending rewards before changing balance
            let staked = self.staked_balances.read(user);
            if staked > 0 {
                let pending = self._calc_pending(user, staked);
                if pending > 0 {
                    self._pay_reward(user, pending);
                }
            }

            // Transfer LT from user to this contract
            IERC20FacadeDispatcher { contract_address: self.lt_token.read() }
                .transfer_from(user, get_contract_address(), amount);

            // Update balances
            let new_staked = staked + amount;
            self.staked_balances.write(user, new_staked);
            self.total_staked.write(self.total_staked.read() + amount);

            // Reset reward debt
            let acc = self.acc_reward_per_share.read();
            self.reward_debt.write(user, new_staked * acc / SCALE);

            self.emit(Deposited { user, amount });
        }

        /// Withdraw LT tokens from the gauge. Transfers LT back to caller.
        fn withdraw(ref self: ContractState, amount: u256) {
            let user = get_caller_address();
            let staked = self.staked_balances.read(user);
            assert(staked >= amount, 'Insufficient balance');

            // Settle pending rewards
            let pending = self._calc_pending(user, staked);
            if pending > 0 {
                self._pay_reward(user, pending);
            }

            // Update balances
            let new_staked = staked - amount;
            self.staked_balances.write(user, new_staked);
            self.total_staked.write(self.total_staked.read() - amount);

            // Reset reward debt
            let acc = self.acc_reward_per_share.read();
            self.reward_debt.write(user, new_staked * acc / SCALE);

            // Transfer LT back to user
            IERC20FacadeDispatcher { contract_address: self.lt_token.read() }
                .transfer(user, amount);

            self.emit(Withdrawn { user, amount });
        }

        /// Claim all pending sy-WBTC rewards.
        fn claim_rewards(ref self: ContractState) -> u256 {
            let user = get_caller_address();
            let staked = self.staked_balances.read(user);
            let pending = self._calc_pending(user, staked);
            if pending > 0 {
                self._pay_reward(user, pending);
                let acc = self.acc_reward_per_share.read();
                self.reward_debt.write(user, staked * acc / SCALE);
                self.emit(RewardClaimed { user, amount: pending });
            }
            pending
        }

        fn get_claimable_rewards(self: @ContractState, user: ContractAddress) -> u256 {
            let staked = self.staked_balances.read(user);
            self._calc_pending(user, staked)
        }

        /// Notify new sy-WBTC rewards available. Called by emission controller.
        /// Distributes rewards instantly across all current stakers by updating
        /// acc_reward_per_share. If no stakers, rewards are held in pool.
        fn notify_reward(ref self: ContractState, sy_yb_amount: u256) {
            if sy_yb_amount == 0 { return; }
            let total = self.total_staked.read();
            if total > 0 {
                // Distribute: increase acc_reward_per_share
                let addition = sy_yb_amount * SCALE / total;
                self.acc_reward_per_share.write(self.acc_reward_per_share.read() + addition);
            } else {
                // No stakers — hold rewards for when someone deposits
                self.pending_rewards_pool.write(self.pending_rewards_pool.read() + sy_yb_amount);
            }
            self.emit(RewardNotified { amount: sy_yb_amount });
        }

        fn get_total_staked(self: @ContractState) -> u256 {
            self.total_staked.read()
        }

        fn get_staked_balance(self: @ContractState, user: ContractAddress) -> u256 {
            self.staked_balances.read(user)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _calc_pending(self: @ContractState, user: ContractAddress, staked: u256) -> u256 {
            if staked == 0 { return 0; }
            let acc = self.acc_reward_per_share.read();
            let gross = staked * acc / SCALE;
            let debt = self.reward_debt.read(user);
            if gross > debt { gross - debt } else { 0 }
        }

        /// Mint sy-WBTC reward to user (gauge must own sy-WBTC minting rights).
        fn _pay_reward(ref self: ContractState, to: ContractAddress, amount: u256) {
            if amount == 0 { return; }
            let sy_yb = self.sy_yb_token.read();
            let zero: ContractAddress = 0.try_into().unwrap();
            if sy_yb == zero { return; }
            ISyYbMintFacadeDispatcher { contract_address: sy_yb }.mint(to, amount);
        }
    }
}
