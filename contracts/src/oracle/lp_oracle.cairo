//! LP Oracle — values a Ekubo BTC/USDC LP position
//!
//! Formula (constant-product AMM, balanced pool):
//!   lp_price = 2 * sqrt(reserves_btc * reserves_usdc) / lp_supply * btc_price
//!
//! For the mock / simplified case we use:
//!   lp_value = reserves_btc * btc_price + reserves_usdc
//!   lp_price = lp_value / lp_supply (if lp_supply > 0)

#[starknet::interface]
pub trait ILpOracle<TContractState> {
    /// Returns the total LP pool value in USDC (18-decimal).
    /// reserves_btc, reserves_usdc, lp_supply all in 18-decimal units.
    /// btc_price is NOT 1e18-scaled (raw multiplier, e.g. 96000).
    fn get_lp_pool_value(
        self: @TContractState,
        reserves_btc: u256,
        reserves_usdc: u256,
        btc_price: u256,
    ) -> u256;

    /// Returns price per LP token in USDC (18-decimal).
    fn get_lp_price(
        self: @TContractState,
        reserves_btc: u256,
        reserves_usdc: u256,
        lp_supply: u256,
        btc_price: u256,
    ) -> u256;
}

#[starknet::contract]
pub mod LpOracle {
    use super::ILpOracle;
    use starkyield::utils::math::Math;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl LpOracleImpl of ILpOracle<ContractState> {
        fn get_lp_pool_value(
            self: @ContractState,
            reserves_btc: u256,
            reserves_usdc: u256,
            btc_price: u256,
        ) -> u256 {
            // pool_value = btc_reserves * price + usdc_reserves (both 18 dec)
            reserves_btc * btc_price + reserves_usdc
        }

        fn get_lp_price(
            self: @ContractState,
            reserves_btc: u256,
            reserves_usdc: u256,
            lp_supply: u256,
            btc_price: u256,
        ) -> u256 {
            if lp_supply == 0 {
                return 0;
            }
            let pool_value = self.get_lp_pool_value(reserves_btc, reserves_usdc, btc_price);
            // price_per_lp = pool_value * SCALE / lp_supply
            Math::div_fixed(pool_value, lp_supply)
        }
    }
}
