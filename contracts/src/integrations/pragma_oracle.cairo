use starknet::ContractAddress;

/// Pragma Oracle data structure for price feeds
/// Matches the real PragmaPricesResponse returned by get_spot_median on Sepolia
#[derive(Drop, Copy, Serde)]
pub struct PragmaPrice {
    pub price: u128,
    pub decimals: u32,
    pub last_updated_timestamp: u64,
    pub num_sources_aggregated: u32,
    pub expiration_timestamp: Option<u64>, // required field in real Pragma response
}

/// Interface for Pragma Oracle on Starknet
#[starknet::interface]
pub trait IPragmaOracle<TContractState> {
    fn get_spot_median(self: @TContractState, pair_id: felt252) -> PragmaPrice;
}

/// StarkYield Pragma Oracle Adapter interface
#[starknet::interface]
pub trait IPragmaAdapter<TContractState> {
    fn get_btc_price(self: @TContractState) -> u256;
    fn is_price_stale(self: @TContractState) -> bool;
    fn get_btc_price_with_check(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod PragmaAdapter {
    use super::{
        ContractAddress, IPragmaAdapter,
        IPragmaOracleDispatcher, IPragmaOracleDispatcherTrait,
    };
    use starknet::get_block_timestamp;
    use starkyield::utils::constants::Constants;

    const BTC_USD_PAIR_ID: felt252 = 'BTC/USD';
    const TARGET_DECIMALS: u32 = 18;

    #[storage]
    struct Storage {
        pragma_oracle: ContractAddress,
        price_staleness_threshold: u64,
        last_known_price: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        pragma_oracle: ContractAddress,
    ) {
        self.pragma_oracle.write(pragma_oracle);
        self.price_staleness_threshold.write(Constants::PRICE_STALENESS_THRESHOLD);
    }

    #[abi(embed_v0)]
    impl PragmaAdapterImpl of IPragmaAdapter<ContractState> {
        /// Get BTC/USD price normalized to 18 decimals
        fn get_btc_price(self: @ContractState) -> u256 {
            let oracle = IPragmaOracleDispatcher {
                contract_address: self.pragma_oracle.read(),
            };

            let price_data = oracle.get_spot_median(BTC_USD_PAIR_ID);
            self._normalize_price(price_data.price, price_data.decimals)
        }

        /// Check if the latest price is stale
        fn is_price_stale(self: @ContractState) -> bool {
            let oracle = IPragmaOracleDispatcher {
                contract_address: self.pragma_oracle.read(),
            };
            let price_data = oracle.get_spot_median(BTC_USD_PAIR_ID);
            let threshold = self.price_staleness_threshold.read();

            get_block_timestamp() - price_data.last_updated_timestamp > threshold
        }

        /// Get BTC price with staleness check — reverts if stale
        fn get_btc_price_with_check(self: @ContractState) -> u256 {
            assert(!self.is_price_stale(), 'Price is stale');
            self.get_btc_price()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Normalize price from oracle decimals to 18 decimals
        fn _normalize_price(self: @ContractState, price: u128, decimals: u32) -> u256 {
            let price_u256: u256 = price.into();
            if decimals < TARGET_DECIMALS {
                let scale_up = self._pow10(TARGET_DECIMALS - decimals);
                price_u256 * scale_up
            } else if decimals > TARGET_DECIMALS {
                let scale_down = self._pow10(decimals - TARGET_DECIMALS);
                price_u256 / scale_down
            } else {
                price_u256
            }
        }

        /// Calculate 10^n
        fn _pow10(self: @ContractState, n: u32) -> u256 {
            let mut result: u256 = 1;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                result = result * 10;
                i += 1;
            };
            result
        }
    }
}
