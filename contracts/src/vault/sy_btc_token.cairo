//! syBTC Token - Receipt token for StarkYield vault
//!
//! This is an ERC20 token that represents shares in the StarkYield vault.
//! Users receive syBTC tokens when they deposit BTC into the vault.
//! The token can be minted (on deposit) and burned (on withdrawal).

use starknet::ContractAddress;
use core::byte_array::ByteArray;
use openzeppelin::token::erc20::{ERC20HooksEmptyImpl, DefaultConfig};

#[starknet::interface]
pub trait ISyBtcToken<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod SyBtcToken {
    use super::{ISyBtcToken, ContractAddress, ByteArray};
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig};
    use openzeppelin::access::ownable::OwnableComponent;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // Use DefaultConfig for ImmutableConfig (provides DECIMALS = 18)
    impl Config = DefaultConfig;

    // Use empty hooks implementation
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
    impl SyBtcTokenImpl of ISyBtcToken<ContractState> {
        /// Mints new tokens (only callable by owner/vault)
        /// 
        /// # Arguments
        /// * `to` - Address to mint tokens to
        /// * `amount` - Amount of tokens to mint
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Only owner (vault manager) can mint
            self.ownable.assert_only_owner();
            assert(amount > 0, 'Amount must be > 0');
            
            self.erc20.mint(to, amount);
        }

        /// Burns tokens from an address (only callable by owner/vault)
        /// 
        /// # Arguments
        /// * `from` - Address to burn tokens from
        /// * `amount` - Amount of tokens to burn
        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            // Only owner (vault manager) can burn
            self.ownable.assert_only_owner();
            assert(amount > 0, 'Amount must be > 0');
            
            self.erc20.burn(from, amount);
        }
    }
}
