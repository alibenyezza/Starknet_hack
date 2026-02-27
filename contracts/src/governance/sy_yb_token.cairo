//! syYB Token - Governance token for StarkYield protocol
//!
//! ERC-20 governance token distributed to syBTC stakers.
//! Identical structure to SyBtcToken — owner (Staker contract) can mint/burn.

use starknet::ContractAddress;
use core::byte_array::ByteArray;
use openzeppelin::token::erc20::{ERC20HooksEmptyImpl, DefaultConfig};

#[starknet::interface]
pub trait ISyYbToken<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod SyYbToken {
    use super::{ISyYbToken, ContractAddress, ByteArray};
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig};
    use openzeppelin::access::ownable::OwnableComponent;

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

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray, owner: ContractAddress) {
        self.ownable.initializer(owner);
        self.erc20.initializer(name, symbol);
    }

    #[abi(embed_v0)]
    impl SyYbTokenImpl of ISyYbToken<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            assert(amount > 0, 'Amount must be > 0');
            self.erc20.mint(to, amount);
        }

        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            assert(amount > 0, 'Amount must be > 0');
            self.erc20.burn(from, amount);
        }
    }
}
