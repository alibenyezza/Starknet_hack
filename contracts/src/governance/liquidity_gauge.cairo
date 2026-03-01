//! LiquidityGauge — Stub
//! Distributes syYB emissions to stakers based on gauge weight.

use starknet::ContractAddress;

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
    use super::{ILiquidityGauge, ContractAddress};
    use starknet::get_caller_address;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        sy_yb_token: ContractAddress,
        staked_balances: Map<ContractAddress, u256>,
        total_staked: u256,
        pending_rewards: Map<ContractAddress, u256>,
        total_notified: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        RewardNotified: RewardNotified,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposited { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct RewardNotified { amount: u256 }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, sy_yb_token: ContractAddress) {
        self.owner.write(owner);
        self.sy_yb_token.write(sy_yb_token);
    }

    #[abi(embed_v0)]
    impl LiquidityGaugeImpl of ILiquidityGauge<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            let user = get_caller_address();
            self.staked_balances.write(user, self.staked_balances.read(user) + amount);
            self.total_staked.write(self.total_staked.read() + amount);
            self.emit(Deposited { user, amount });
        }

        fn withdraw(ref self: ContractState, amount: u256) {
            let user = get_caller_address();
            let bal = self.staked_balances.read(user);
            assert(bal >= amount, 'Insufficient balance');
            self.staked_balances.write(user, bal - amount);
            self.total_staked.write(self.total_staked.read() - amount);
            self.emit(Withdrawn { user, amount });
        }

        fn claim_rewards(ref self: ContractState) -> u256 {
            // Stub: no actual distribution yet
            0
        }

        fn get_claimable_rewards(self: @ContractState, user: ContractAddress) -> u256 {
            0
        }

        fn notify_reward(ref self: ContractState, sy_yb_amount: u256) {
            self.total_notified.write(self.total_notified.read() + sy_yb_amount);
            self.emit(RewardNotified { amount: sy_yb_amount });
        }

        fn get_total_staked(self: @ContractState) -> u256 {
            self.total_staked.read()
        }

        fn get_staked_balance(self: @ContractState, user: ContractAddress) -> u256 {
            self.staked_balances.read(user)
        }
    }
}
