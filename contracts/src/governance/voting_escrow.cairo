//! VotingEscrow — Stub
//! Lock syYB to receive vesyYB voting power (governance). Full logic TBD.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IVotingEscrow<TContractState> {
    fn lock(ref self: TContractState, amount: u256, unlock_time: u64);
    fn unlock(ref self: TContractState);
    fn get_voting_power(self: @TContractState, user: ContractAddress) -> u256;
    fn get_lock_end(self: @TContractState, user: ContractAddress) -> u64;
}

#[starknet::contract]
pub mod VotingEscrow {
    use super::{IVotingEscrow, ContractAddress};
    use starknet::get_caller_address;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        sy_yb_token: ContractAddress,
        locked_balances: Map<ContractAddress, u256>,
        lock_end: Map<ContractAddress, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Locked: Locked,
        Unlocked: Unlocked,
    }

    #[derive(Drop, starknet::Event)]
    struct Locked { user: ContractAddress, amount: u256, unlock_time: u64 }

    #[derive(Drop, starknet::Event)]
    struct Unlocked { user: ContractAddress }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, sy_yb_token: ContractAddress) {
        self.owner.write(owner);
        self.sy_yb_token.write(sy_yb_token);
    }

    #[abi(embed_v0)]
    impl VotingEscrowImpl of IVotingEscrow<ContractState> {
        fn lock(ref self: ContractState, amount: u256, unlock_time: u64) {
            let user = get_caller_address();
            self.locked_balances.write(user, self.locked_balances.read(user) + amount);
            self.lock_end.write(user, unlock_time);
            self.emit(Locked { user, amount, unlock_time });
        }

        fn unlock(ref self: ContractState) {
            let user = get_caller_address();
            self.locked_balances.write(user, 0);
            self.lock_end.write(user, 0);
            self.emit(Unlocked { user });
        }

        fn get_voting_power(self: @ContractState, user: ContractAddress) -> u256 {
            self.locked_balances.read(user)
        }

        fn get_lock_end(self: @ContractState, user: ContractAddress) -> u64 {
            self.lock_end.read(user)
        }
    }
}
