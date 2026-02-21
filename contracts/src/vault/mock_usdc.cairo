//! Mock USDC Token for testnet
//!
//! ERC20 token with public faucet for testing.
//! Uses 18 decimals to match MockWBTC and simplify math on testnet.

use openzeppelin::token::erc20::{ERC20HooksEmptyImpl, DefaultConfig};

#[starknet::interface]
pub trait IMockUSDC<TContractState> {
    fn faucet(ref self: TContractState, amount: u256);
    fn mint_to(ref self: TContractState, recipient: starknet::ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod MockUSDC {
    use super::IMockUSDC;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig};
    use starknet::{get_caller_address, ContractAddress};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    impl Config = DefaultConfig;
    impl ERC20HooksImpl = ERC20HooksEmptyImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.erc20.initializer("Mock USD Coin", "USDC");
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl MockUSDCImpl of IMockUSDC<ContractState> {
        /// Faucet: mint tokens to caller (testnet only)
        fn faucet(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            self.erc20.mint(caller, amount);
        }

        /// Mint to a specific address — callable by owner only.
        /// Used by the VesuAdapter (or tests) to simulate lending USDC.
        fn mint_to(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.erc20.mint(recipient, amount);
        }
    }
}
