//! VotingEscrow — Lock sy-WBTC to receive veSyWBTC voting power (governance).
//!
//! Users lock sy-WBTC tokens for a duration (1 week to 4 years).
//! Voting power decays linearly: power = locked_amount * (time_remaining / MAX_LOCK).
//! Tokens are transferred into this contract on lock() and returned on unlock().
//!
//! MAX_LOCK = 4 years = 126_144_000 seconds.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IVotingEscrow<TContractState> {
    fn lock(ref self: TContractState, amount: u256, unlock_time: u64);
    fn increase_amount(ref self: TContractState, amount: u256);
    fn unlock(ref self: TContractState);
    fn get_voting_power(self: @TContractState, user: ContractAddress) -> u256;
    fn get_lock_end(self: @TContractState, user: ContractAddress) -> u64;
    fn get_locked_balance(self: @TContractState, user: ContractAddress) -> u256;
}

/// Minimal ERC-20 facade for sy-WBTC token transfers
#[starknet::interface]
trait IERC20Facade<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}

#[starknet::contract]
pub mod VotingEscrow {
    use super::{IVotingEscrow, ContractAddress, IERC20FacadeDispatcher, IERC20FacadeDispatcherTrait};
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};

    /// Minimum lock duration: 1 week
    const MIN_LOCK_DURATION: u64 = 604_800;
    /// Maximum lock duration: 4 years (365.25 * 4 * 86400)
    const MAX_LOCK_DURATION: u64 = 126_144_000;

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
        IncreasedAmount: IncreasedAmount,
        Unlocked: Unlocked,
    }

    #[derive(Drop, starknet::Event)]
    struct Locked { user: ContractAddress, amount: u256, unlock_time: u64 }

    #[derive(Drop, starknet::Event)]
    struct IncreasedAmount { user: ContractAddress, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct Unlocked { user: ContractAddress, amount: u256 }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, sy_yb_token: ContractAddress) {
        self.owner.write(owner);
        self.sy_yb_token.write(sy_yb_token);
    }

    #[abi(embed_v0)]
    impl VotingEscrowImpl of IVotingEscrow<ContractState> {
        /// Lock sy-WBTC tokens until unlock_time. Transfers tokens into this contract.
        /// unlock_time must be between now+MIN_LOCK and now+MAX_LOCK.
        fn lock(ref self: ContractState, amount: u256, unlock_time: u64) {
            assert(amount > 0, 'Amount must be > 0');
            let user = get_caller_address();
            let now = get_block_timestamp();

            // Validate lock duration
            let duration = unlock_time - now;
            assert(duration >= MIN_LOCK_DURATION, 'Lock too short (min 1 week)');
            assert(duration <= MAX_LOCK_DURATION, 'Lock too long (max 4 years)');

            // Cannot lock if already locked (use increase_amount instead)
            let existing = self.locked_balances.read(user);
            assert(existing == 0, 'Already locked, use increase');

            // Transfer sy-WBTC from user to this contract
            let token = IERC20FacadeDispatcher { contract_address: self.sy_yb_token.read() };
            let ok = token.transfer_from(user, get_contract_address(), amount);
            assert(ok, 'sy-WBTC transfer_from failed');

            self.locked_balances.write(user, amount);
            self.lock_end.write(user, unlock_time);
            self.emit(Locked { user, amount, unlock_time });
        }

        /// Add more sy-WBTC to an existing lock (same unlock_time).
        fn increase_amount(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            let user = get_caller_address();
            let existing = self.locked_balances.read(user);
            assert(existing > 0, 'No existing lock');
            let lock_end = self.lock_end.read(user);
            assert(get_block_timestamp() < lock_end, 'Lock expired');

            let token = IERC20FacadeDispatcher { contract_address: self.sy_yb_token.read() };
            let ok = token.transfer_from(user, get_contract_address(), amount);
            assert(ok, 'sy-WBTC transfer_from failed');

            self.locked_balances.write(user, existing + amount);
            self.emit(IncreasedAmount { user, amount });
        }

        /// Unlock sy-WBTC after lock_end. Transfers all locked tokens back to user.
        fn unlock(ref self: ContractState) {
            let user = get_caller_address();
            let locked = self.locked_balances.read(user);
            assert(locked > 0, 'Nothing locked');

            let lock_end = self.lock_end.read(user);
            let now = get_block_timestamp();
            assert(now >= lock_end, 'Lock not expired yet');

            // Clear lock
            self.locked_balances.write(user, 0);
            self.lock_end.write(user, 0);

            // Transfer sy-WBTC back to user
            let token = IERC20FacadeDispatcher { contract_address: self.sy_yb_token.read() };
            token.transfer(user, locked);

            self.emit(Unlocked { user, amount: locked });
        }

        /// Voting power with linear decay: locked * (time_remaining / MAX_LOCK).
        /// Returns 0 if lock is expired.
        fn get_voting_power(self: @ContractState, user: ContractAddress) -> u256 {
            let locked = self.locked_balances.read(user);
            if locked == 0 {
                return 0;
            }
            let lock_end = self.lock_end.read(user);
            let now = get_block_timestamp();
            if now >= lock_end {
                return 0; // Lock expired, no voting power
            }
            let remaining: u256 = (lock_end - now).into();
            let max_lock: u256 = MAX_LOCK_DURATION.into();
            // power = locked * remaining / MAX_LOCK
            locked * remaining / max_lock
        }

        fn get_lock_end(self: @ContractState, user: ContractAddress) -> u64 {
            self.lock_end.read(user)
        }

        fn get_locked_balance(self: @ContractState, user: ContractAddress) -> u256 {
            self.locked_balances.read(user)
        }
    }
}
