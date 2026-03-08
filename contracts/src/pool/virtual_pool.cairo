//! VirtualPool — Fee-less flash loan provider for StarkYield vault
//!
//! On deposit:  vault calls flash_loan(usdc_needed)  → USDC transferred from reserves
//! On withdraw: vault calls flash_loan(debt_share)   → USDC transferred from reserves
//! After use:   vault calls repay_flash_loan(amount) → USDC returned to reserves
//!
//! The owner must pre-fund the pool with USDC via fund() before any flash loans.
//! get_reserves() lets callers check available liquidity.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IVirtualPool<TContractState> {
    /// Transfer USDC from reserves to caller (fee-less flash loan).
    /// Reverts if reserves < amount.
    fn flash_loan(ref self: TContractState, amount: u256);
    /// Caller transfers USDC back to VirtualPool to repay flash loan.
    /// Caller must approve this contract for `amount` before calling.
    fn repay_flash_loan(ref self: TContractState, amount: u256);
    /// Owner deposits USDC into the reserve pool.
    /// Caller must approve this contract for `amount` before calling.
    fn fund(ref self: TContractState, amount: u256);
    /// Returns total USDC held in reserves.
    fn get_reserves(self: @TContractState) -> u256;
    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod VirtualPool {
    use super::{IVirtualPool, ContractAddress};
    use starknet::{get_caller_address, get_contract_address};
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        usdc_token: ContractAddress,
        reserves: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Funded: Funded,
        FlashLoan: FlashLoan,
        Repaid: Repaid,
    }

    #[derive(Drop, starknet::Event)]
    struct Funded { amount: u256, new_reserves: u256 }

    #[derive(Drop, starknet::Event)]
    struct FlashLoan { borrower: ContractAddress, amount: u256, reserves_after: u256 }

    #[derive(Drop, starknet::Event)]
    struct Repaid { repayer: ContractAddress, amount: u256, reserves_after: u256 }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        usdc_token: ContractAddress,
    ) {
        self.owner.write(owner);
        self.usdc_token.write(usdc_token);
        self.reserves.write(0);
    }

    #[abi(embed_v0)]
    impl VirtualPoolImpl of IVirtualPool<ContractState> {
        /// Fee-less flash loan: transfers USDC from reserves to caller.
        fn flash_loan(ref self: ContractState, amount: u256) {
            if amount == 0 {
                return;
            }
            let current = self.reserves.read();
            assert(current >= amount, 'Insufficient reserves');
            let usdc = self.usdc_token.read();
            let caller = get_caller_address();
            let new_reserves = current - amount;
            self.reserves.write(new_reserves);
            IERC20Dispatcher { contract_address: usdc }.transfer(caller, amount);
            self.emit(FlashLoan { borrower: caller, amount, reserves_after: new_reserves });
        }

        /// Repay flash loan: caller transfers USDC back to this contract.
        fn repay_flash_loan(ref self: ContractState, amount: u256) {
            if amount == 0 {
                return;
            }
            let usdc = self.usdc_token.read();
            let caller = get_caller_address();
            IERC20Dispatcher { contract_address: usdc }
                .transfer_from(caller, get_contract_address(), amount);
            let new_reserves = self.reserves.read() + amount;
            self.reserves.write(new_reserves);
            self.emit(Repaid { repayer: caller, amount, reserves_after: new_reserves });
        }

        /// Fund the pool — owner-only, pulls USDC from caller into reserves.
        fn fund(ref self: ContractState, amount: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            assert(amount > 0, 'Amount must be > 0');
            let usdc = self.usdc_token.read();
            IERC20Dispatcher { contract_address: usdc }
                .transfer_from(get_caller_address(), get_contract_address(), amount);
            let new_reserves = self.reserves.read() + amount;
            self.reserves.write(new_reserves);
            self.emit(Funded { amount, new_reserves });
        }

        fn get_reserves(self: @ContractState) -> u256 {
            self.reserves.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
