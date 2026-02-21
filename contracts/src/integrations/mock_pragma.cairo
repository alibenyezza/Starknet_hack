//! Mock Pragma Adapter for testnet
//!
//! Returns a hardcoded BTC/USD price — no real oracle needed.
//! Implements IPragmaAdapter so it is a drop-in replacement.
//!
//! Default price: 96,000 USDC per BTC, normalized to 18 decimals
//!   = 96000 * 10^18 = 96000_000000000000000000
//!
//! This is consistent with MockEkuboAdapter's internal price (96000).

use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockPragmaAdmin<TContractState> {
    /// Update the hardcoded price (owner only).
    /// Pass price as USDC_per_BTC * 10^18 (e.g. 96000_000000000000000000 for $96k)
    fn set_btc_price(ref self: TContractState, price: u256);
    fn get_raw_price(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod MockPragmaAdapter {
    use super::{ContractAddress, IMockPragmaAdmin};
    use starkyield::integrations::pragma_oracle::IPragmaAdapter;
    use starknet::get_caller_address;

    // 96000 * 10^18  (both tokens have 18 decimals)
    // This makes Math::mul_fixed(btc_amount, price) return the USDC value:
    //   e.g. mul_fixed(2e18, 96000e18) = 2e18 * 96000e18 / 1e18 = 192000e18 ✓
    const DEFAULT_PRICE: u256 = 96000_000000000000000000_u256;

    #[storage]
    struct Storage {
        btc_price: u256,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.btc_price.write(DEFAULT_PRICE);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl PragmaAdapterImpl of IPragmaAdapter<ContractState> {
        fn get_btc_price(self: @ContractState) -> u256 {
            self.btc_price.read()
        }

        fn is_price_stale(self: @ContractState) -> bool {
            false // mock never goes stale
        }

        fn get_btc_price_with_check(self: @ContractState) -> u256 {
            self.btc_price.read()
        }
    }

    #[abi(embed_v0)]
    impl MockPragmaAdminImpl of IMockPragmaAdmin<ContractState> {
        fn set_btc_price(ref self: ContractState, price: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            assert(price > 0, 'Price must be > 0');
            self.btc_price.write(price);
        }

        fn get_raw_price(self: @ContractState) -> u256 {
            self.btc_price.read()
        }
    }
}
