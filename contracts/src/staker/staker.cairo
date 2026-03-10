//! Staker — Stake LT tokens to earn sy-WBTC emissions (MasterChef pattern)
//!
//! Users stake LT (vault share) tokens here instead of earning trading fees directly.
//! In return they receive sy-WBTC governance tokens at a configurable rate.
//! The Staker contract must own the SyToken to be able to mint rewards.
//!
//! Staking LT shares to earn sy-WBTC emissions.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<TContractState> {
    fn stake(ref self: TContractState, amount: u256);
    fn unstake(ref self: TContractState, amount: u256);
    fn claim_rewards(ref self: TContractState) -> u256;
    fn pending_rewards(self: @TContractState, user: ContractAddress) -> u256;
    fn get_total_staked(self: @TContractState) -> u256;
    fn get_staked_balance(self: @TContractState, user: ContractAddress) -> u256;
    fn get_acc_reward_per_share(self: @TContractState) -> u256;
    fn get_reward_rate(self: @TContractState) -> u256;
    fn set_reward_rate(ref self: TContractState, rate: u256);
    fn set_sy_token(ref self: TContractState, sy: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn set_owner(ref self: TContractState, new_owner: ContractAddress);
}

#[starknet::contract]
pub mod Staker {
    use super::{IStaker, ContractAddress};
    use starknet::{get_caller_address, get_block_number, get_contract_address};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starkyield::governance::sy_token::{ISyTokenDispatcher, ISyTokenDispatcherTrait};
    use starkyield::utils::constants::Constants;
    use starkyield::utils::math::Math;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        stake_token: ContractAddress,
        sy_token: ContractAddress,
        total_staked: u256,
        reward_rate: u256,            // raw sy-WBTC tokens emitted per block (NOT 1e18-scaled)
        last_reward_block: u64,
        acc_reward_per_share: u256,   // accumulated sy-WBTC per share (1e18-scaled)
        staked_balances: Map<ContractAddress, u256>,
        reward_debt: Map<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
        RewardClaimed: RewardClaimed,
        RewardRateSet: RewardRateSet,
    }

    #[derive(Drop, starknet::Event)]
    struct Staked { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct Unstaked { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct RewardClaimed { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct RewardRateSet { new_rate: u256 }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        stake_token: ContractAddress,
        sy_token: ContractAddress,
        initial_reward_rate: u256,
    ) {
        self.owner.write(owner);
        self.stake_token.write(stake_token);
        self.sy_token.write(sy_token);
        self.reward_rate.write(initial_reward_rate);
        self.last_reward_block.write(get_block_number());
        self.acc_reward_per_share.write(0);
        self.total_staked.write(0);
    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
        fn stake(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            self._update_rewards();

            let caller = get_caller_address();

            // Transfer stake token (LT) from user to this contract
            IERC20Dispatcher { contract_address: self.stake_token.read() }
                .transfer_from(caller, get_contract_address(), amount);

            // Settle pending rewards before changing balance
            let staked = self.staked_balances.read(caller);
            if staked > 0 {
                let pending = self._calc_pending(caller, staked);
                if pending > 0 { self._mint_reward(caller, pending); }
            }

            // Update balances
            let new_staked = staked + amount;
            self.staked_balances.write(caller, new_staked);
            self.total_staked.write(self.total_staked.read() + amount);

            // Reset reward debt to current accumulated level
            let acc = self.acc_reward_per_share.read();
            self.reward_debt.write(caller, Math::mul_fixed(new_staked, acc));

            self.emit(Staked { user: caller, amount });
        }

        fn unstake(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let staked = self.staked_balances.read(caller);
            assert(staked >= amount, 'Insufficient staked balance');

            self._update_rewards();

            // Settle pending rewards
            let pending = self._calc_pending(caller, staked);
            if pending > 0 { self._mint_reward(caller, pending); }

            // Update balances
            let new_staked = staked - amount;
            self.staked_balances.write(caller, new_staked);
            self.total_staked.write(self.total_staked.read() - amount);

            // Reset reward debt
            let acc = self.acc_reward_per_share.read();
            self.reward_debt.write(caller, Math::mul_fixed(new_staked, acc));

            // Return stake token (LT)
            IERC20Dispatcher { contract_address: self.stake_token.read() }
                .transfer(caller, amount);

            self.emit(Unstaked { user: caller, amount });
        }

        fn claim_rewards(ref self: ContractState) -> u256 {
            self._update_rewards();
            let caller = get_caller_address();
            let staked = self.staked_balances.read(caller);
            let pending = self._calc_pending(caller, staked);
            if pending > 0 {
                self._mint_reward(caller, pending);
                let acc = self.acc_reward_per_share.read();
                self.reward_debt.write(caller, Math::mul_fixed(staked, acc));
                self.emit(RewardClaimed { user: caller, amount: pending });
            }
            pending
        }

        fn pending_rewards(self: @ContractState, user: ContractAddress) -> u256 {
            // Simulate update without state write
            let total = self.total_staked.read();
            let mut acc = self.acc_reward_per_share.read();
            if total > 0 {
                let current_block = get_block_number();
                let last_block = self.last_reward_block.read();
                if current_block > last_block {
                    let blocks: u256 = (current_block - last_block).into();
                    let new_rewards = self.reward_rate.read() * blocks;
                    acc = acc + (new_rewards * Constants::SCALE) / total;
                }
            }
            let staked = self.staked_balances.read(user);
            let gross = Math::mul_fixed(staked, acc);
            let debt = self.reward_debt.read(user);
            if gross > debt { gross - debt } else { 0 }
        }

        fn get_total_staked(self: @ContractState) -> u256 { self.total_staked.read() }

        fn get_staked_balance(self: @ContractState, user: ContractAddress) -> u256 {
            self.staked_balances.read(user)
        }

        fn get_acc_reward_per_share(self: @ContractState) -> u256 {
            self.acc_reward_per_share.read()
        }

        fn get_reward_rate(self: @ContractState) -> u256 {
            self.reward_rate.read()
        }

        fn set_reward_rate(ref self: ContractState, rate: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self._update_rewards();
            self.reward_rate.write(rate);
            self.emit(RewardRateSet { new_rate: rate });
        }

        fn set_sy_token(ref self: ContractState, sy: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            assert(sy != zero, 'Cannot set zero address');
            self.sy_token.write(sy);
        }

        fn get_owner(self: @ContractState) -> ContractAddress { self.owner.read() }

        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            assert(new_owner != zero, 'Cannot set zero address');
            self.owner.write(new_owner);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Update acc_reward_per_share based on blocks elapsed
        fn _update_rewards(ref self: ContractState) {
            let total = self.total_staked.read();
            let current_block = get_block_number();
            let last_block = self.last_reward_block.read();
            if current_block <= last_block || total == 0 {
                self.last_reward_block.write(current_block);
                return;
            }
            let blocks: u256 = (current_block - last_block).into();
            // new_rewards = rate * blocks (rate is raw tokens per block)
            let new_rewards = self.reward_rate.read() * blocks;
            // acc += new_rewards * SCALE / total_staked
            let addition = (new_rewards * Constants::SCALE) / total;
            self.acc_reward_per_share.write(self.acc_reward_per_share.read() + addition);
            self.last_reward_block.write(current_block);
        }

        fn _calc_pending(self: @ContractState, user: ContractAddress, staked: u256) -> u256 {
            if staked == 0 { return 0; }
            let gross = Math::mul_fixed(staked, self.acc_reward_per_share.read());
            let debt = self.reward_debt.read(user);
            if gross > debt { gross - debt } else { 0 }
        }

        /// Mint sy-WBTC to a user (requires Staker to own SyToken)
        fn _mint_reward(ref self: ContractState, to: ContractAddress, amount: u256) {
            if amount == 0 { return; }
            let sy = self.sy_token.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            assert(sy != zero, 'SY token not set');
            ISyTokenDispatcher { contract_address: sy }.mint(to, amount);
        }
    }
}
