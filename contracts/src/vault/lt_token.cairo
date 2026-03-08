//! LT Token — Liquidity Token for StarkYield vault
//!
//! Replaces syBTC as the vault share token. LT tokens represent a user's
//! proportional claim on the LP position + CDP collateral in the vault.
//! The vault mints LT on deposit and burns LT on withdrawal.
//!
//! Fee distribution: uses a per-share accumulator pattern. When distribute_fees()
//! is called (by FeeDistributor), it increases acc_fees_per_share. Users call
//! claim_fees() to collect their proportional USDC.

use starknet::ContractAddress;
use core::byte_array::ByteArray;
use openzeppelin::token::erc20::{ERC20HooksEmptyImpl, DefaultConfig};

/// Minimal ERC-20 facade for USDC transfers
#[starknet::interface]
trait IERC20Facade<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait ILtToken<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
    /// Called by FeeDistributor to distribute USDC fees to LT holders.
    /// USDC must already be transferred to this contract before calling.
    fn distribute_fees(ref self: TContractState, amount: u256);
    /// Claim accumulated USDC fees for the caller.
    fn claim_fees(ref self: TContractState) -> u256;
    /// View: pending claimable USDC fees for a user.
    fn get_claimable_fees(self: @TContractState, user: ContractAddress) -> u256;
    /// Set USDC token address (admin).
    fn set_usdc_token(ref self: TContractState, usdc_token: ContractAddress);
}

#[starknet::contract]
pub mod LtToken {
    use super::{ILtToken, ContractAddress, ByteArray, IERC20FacadeDispatcher, IERC20FacadeDispatcherTrait};
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig};
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::{get_caller_address, get_contract_address};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    impl Config = DefaultConfig;
    impl ERC20HooksImpl = ERC20HooksEmptyImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl = OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    const SCALE: u256 = 1_000000000000000000;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        usdc_token: ContractAddress,
        // Accumulated USDC fees per LT share (1e18-scaled)
        acc_fees_per_share: u256,
        // Per-user fee debt (snapshot of acc_fees_per_share * balance at last claim)
        fee_debt: Map<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        FeesDistributed: FeesDistributed,
        FeesClaimed: FeesClaimed,
    }

    #[derive(Drop, starknet::Event)]
    struct FeesDistributed { amount: u256, new_acc_per_share: u256 }

    #[derive(Drop, starknet::Event)]
    struct FeesClaimed { user: ContractAddress, amount: u256 }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        owner: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.erc20.initializer(name, symbol);
    }

    #[abi(embed_v0)]
    impl LtTokenImpl of ILtToken<ContractState> {
        /// Mint LT shares to a depositor (only vault/owner).
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            assert(amount > 0, 'Amount must be > 0');
            // Settle pending fees before changing balance
            let bal = self.erc20.balance_of(to);
            if bal > 0 {
                let acc = self.acc_fees_per_share.read();
                self.fee_debt.write(to, bal * acc / SCALE);
            }
            self.erc20.mint(to, amount);
            // Update fee debt for new balance
            let new_bal = self.erc20.balance_of(to);
            let acc = self.acc_fees_per_share.read();
            self.fee_debt.write(to, new_bal * acc / SCALE);
        }

        /// Burn LT shares from a withdrawer (only vault/owner).
        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            assert(amount > 0, 'Amount must be > 0');
            self.erc20.burn(from, amount);
            // Update fee debt for new balance
            let new_bal = self.erc20.balance_of(from);
            let acc = self.acc_fees_per_share.read();
            self.fee_debt.write(from, new_bal * acc / SCALE);
        }

        /// Distribute USDC fee revenue to LT holders.
        /// USDC must already be in this contract. Increases acc_fees_per_share.
        /// Permissionless — safe because USDC must be transferred before calling,
        /// and the function only increases the per-share accumulator.
        fn distribute_fees(ref self: ContractState, amount: u256) {
            if amount == 0 { return; }
            let total_supply = self.erc20.total_supply();
            if total_supply == 0 { return; }
            // Increase accumulated fees per share
            let addition = amount * SCALE / total_supply;
            let new_acc = self.acc_fees_per_share.read() + addition;
            self.acc_fees_per_share.write(new_acc);
            self.emit(FeesDistributed { amount, new_acc_per_share: new_acc });
        }

        /// Claim accumulated USDC fees for the caller.
        fn claim_fees(ref self: ContractState) -> u256 {
            let user = get_caller_address();
            let bal = self.erc20.balance_of(user);
            if bal == 0 { return 0; }

            let acc = self.acc_fees_per_share.read();
            let gross = bal * acc / SCALE;
            let debt = self.fee_debt.read(user);
            let pending = if gross > debt { gross - debt } else { 0 };

            if pending > 0 {
                // Update debt
                self.fee_debt.write(user, gross);
                // Transfer USDC to user
                let usdc_addr = self.usdc_token.read();
                let zero: ContractAddress = 0.try_into().unwrap();
                if usdc_addr != zero {
                    IERC20FacadeDispatcher { contract_address: usdc_addr }
                        .transfer(user, pending);
                }
                self.emit(FeesClaimed { user, amount: pending });
            }
            pending
        }

        fn get_claimable_fees(self: @ContractState, user: ContractAddress) -> u256 {
            let bal = self.erc20.balance_of(user);
            if bal == 0 { return 0; }
            let acc = self.acc_fees_per_share.read();
            let gross = bal * acc / SCALE;
            let debt = self.fee_debt.read(user);
            if gross > debt { gross - debt } else { 0 }
        }

        fn set_usdc_token(ref self: ContractState, usdc_token: ContractAddress) {
            self.ownable.assert_only_owner();
            self.usdc_token.write(usdc_token);
        }
    }
}
