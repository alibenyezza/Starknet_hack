//! VirtualPool — Fee-less flash loan provider for YieldBasis vault
//!
//! On deposit:  vault calls flash_loan(usdc_needed)  → USDC minted to vault
//! On withdraw: vault calls flash_loan(debt_share)   → USDC minted to vault
//! After use:   vault calls repay_flash_loan(amount) → vault sends USDC back
//!
//! Mock implementation: USDC minted via faucet (no real reserves needed on testnet).

use starknet::ContractAddress;

/// Minimal faucet interface for mock USDC minting
#[starknet::interface]
trait IFaucet<TContractState> {
    fn faucet(ref self: TContractState, amount: u256);
}

#[starknet::interface]
pub trait IVirtualPool<TContractState> {
    /// Mint USDC and transfer to caller (fee-less flash loan, mock only).
    fn flash_loan(ref self: TContractState, amount: u256);
    /// Caller transfers USDC back to VirtualPool to repay flash loan.
    /// Caller must approve this contract for `amount` before calling.
    fn repay_flash_loan(ref self: TContractState, amount: u256);
    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod VirtualPool {
    use super::{IVirtualPool, ContractAddress, IFaucetDispatcher, IFaucetDispatcherTrait};
    use starknet::{get_caller_address, get_contract_address};
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        usdc_token: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        usdc_token: ContractAddress,
    ) {
        self.owner.write(owner);
        self.usdc_token.write(usdc_token);
    }

    #[abi(embed_v0)]
    impl VirtualPoolImpl of IVirtualPool<ContractState> {
        /// Fee-less flash loan: mints USDC via faucet and transfers to caller.
        fn flash_loan(ref self: ContractState, amount: u256) {
            if amount == 0 {
                return;
            }
            let usdc = self.usdc_token.read();
            IFaucetDispatcher { contract_address: usdc }.faucet(amount);
            IERC20Dispatcher { contract_address: usdc }.transfer(get_caller_address(), amount);
        }

        /// Repay flash loan: caller transfers USDC back to this contract.
        fn repay_flash_loan(ref self: ContractState, amount: u256) {
            if amount == 0 {
                return;
            }
            let usdc = self.usdc_token.read();
            IERC20Dispatcher { contract_address: usdc }
                .transfer_from(get_caller_address(), get_contract_address(), amount);
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
