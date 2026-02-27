//! Staker — Stake syBTC to earn syYB emissions (MasterChef pattern)
//!
//! Users stake syBTC here instead of earning trading fees directly.
//! In return they receive syYB governance tokens at a configurable rate.
//! The Staker contract must own the SyYbToken to be able to mint rewards.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<TContractState> {
    fn stake(ref self: TContractState, sy_btc_amount: u256);
    fn unstake(ref self: TContractState, sy_btc_amount: u256);
    fn claim_rewards(ref self: TContractState) -> u256;
    fn pending_rewards(self: @TContractState, user: ContractAddress) -> u256;
    fn get_total_staked(self: @TContractState) -> u256;
    fn get_staked_balance(self: @TContractState, user: ContractAddress) -> u256;
    fn get_acc_reward_per_share(self: @TContractState) -> u256;
    fn set_reward_rate(ref self: TContractState, rate: u256);
    fn set_sy_yb_token(ref self: TContractState, sy_yb: ContractAddress);
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
    use starkyield::governance::sy_yb_token::{ISyYbTokenDispatcher, ISyYbTokenDispatcherTrait};
    use starkyield::utils::constants::Constants;
    use starkyield::utils::math::Math;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        sy_btc_token: ContractAddress,
        sy_yb_token: ContractAddress,
        total_staked: u256,
        reward_rate: u256,            // syYB minted per block per SCALE unit of staked syBTC
        last_reward_block: u64,
        acc_reward_per_share: u256,   // accumulated syYB per share (1e18-scaled)
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
        sy_btc_token: ContractAddress,
        sy_yb_token: ContractAddress,
        initial_reward_rate: u256,
    ) {
        self.owner.write(owner);
        self.sy_btc_token.write(sy_btc_token);
        self.sy_yb_token.write(sy_yb_token);
        self.reward_rate.write(initial_reward_rate);
        self.last_reward_block.write(get_block_number());
        self.acc_reward_per_share.write(0);
        self.total_staked.write(0);
    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
        fn stake(ref self: ContractState, sy_btc_amount: u256) {
            assert(sy_btc_amount > 0, 'Amount must be > 0');
            self._update_rewards();

            let caller = get_caller_address();

            // Transfer syBTC from user to this contract
            IERC20Dispatcher { contract_address: self.sy_btc_token.read() }
                .transfer_from(caller, get_contract_address(), sy_btc_amount);

            // Settle pending rewards before changing balance
            let staked = self.staked_balances.read(caller);
            if staked > 0 {
                let pending = self._calc_pending(caller, staked);
                if pending > 0 { self._mint_reward(caller, pending); }
            }

            // Update balances
            let new_staked = staked + sy_btc_amount;
            self.staked_balances.write(caller, new_staked);
            self.total_staked.write(self.total_staked.read() + sy_btc_amount);

            // Reset reward debt to current accumulated level
            let acc = self.acc_reward_per_share.read();
            self.reward_debt.write(caller, Math::mul_fixed(new_staked, acc));

            self.emit(Staked { user: caller, amount: sy_btc_amount });
        }

        fn unstake(ref self: ContractState, sy_btc_amount: u256) {
            let caller = get_caller_address();
            let staked = self.staked_balances.read(caller);
            assert(staked >= sy_btc_amount, 'Insufficient staked balance');

            self._update_rewards();

            // Settle pending rewards
            let pending = self._calc_pending(caller, staked);
            if pending > 0 { self._mint_reward(caller, pending); }

            // Update balances
            let new_staked = staked - sy_btc_amount;
            self.staked_balances.write(caller, new_staked);
            self.total_staked.write(self.total_staked.read() - sy_btc_amount);

            // Reset reward debt
            let acc = self.acc_reward_per_share.read();
            self.reward_debt.write(caller, Math::mul_fixed(new_staked, acc));

            // Return syBTC
            IERC20Dispatcher { contract_address: self.sy_btc_token.read() }
                .transfer(caller, sy_btc_amount);

            self.emit(Unstaked { user: caller, amount: sy_btc_amount });
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
                    let new_rewards = Math::mul_fixed(self.reward_rate.read(), blocks);
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

        fn set_reward_rate(ref self: ContractState, rate: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self._update_rewards();
            self.reward_rate.write(rate);
            self.emit(RewardRateSet { new_rate: rate });
        }

        fn set_sy_yb_token(ref self: ContractState, sy_yb: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.sy_yb_token.write(sy_yb);
        }

        fn get_owner(self: @ContractState) -> ContractAddress { self.owner.read() }

        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
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
            // new_rewards = rate * blocks (rate is 1e18-scaled per-block unit)
            let new_rewards = Math::mul_fixed(self.reward_rate.read(), blocks);
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

        /// Mint syYB to a user (requires Staker to own SyYbToken)
        fn _mint_reward(ref self: ContractState, to: ContractAddress, amount: u256) {
            if amount == 0 { return; }
            let sy_yb = self.sy_yb_token.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if sy_yb == zero { return; }
            ISyYbTokenDispatcher { contract_address: sy_yb }.mint(to, amount);
        }
    }
}
