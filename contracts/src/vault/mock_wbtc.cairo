//! Mock wBTC Token for testnet
//!
//! ERC20 token with public mint/faucet for testing.
//! Uses 8 decimals — matching real wBTC on mainnet.

use openzeppelin::token::erc20::ERC20HooksEmptyImpl;

#[starknet::interface]
pub trait IMockWBTC<TContractState> {
    fn faucet(ref self: TContractState, amount: u256);
}

#[starknet::contract]
pub mod MockWBTC {
    use super::IMockWBTC;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::get_caller_address;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    /// Custom config: 8 decimals to match real wBTC.
    pub impl Config of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 8;
    }
    impl ERC20HooksImpl = ERC20HooksEmptyImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc20.initializer("Wrapped BTC", "wBTC");
    }

    #[abi(embed_v0)]
    impl MockWBTCImpl of IMockWBTC<ContractState> {
        /// Faucet: mint tokens to caller (testnet only, no restrictions)
        fn faucet(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            self.erc20.mint(caller, amount);
        }
    }
}
