//! Mock Ekubo Adapter for testnet
//!
//! Simulates Ekubo DEX swaps and LP — no real pool required.
//! Implements IEkuboAdapter so it is a drop-in replacement for EkuboAdapter.
//!
//! Swap model (both tokens have 18 decimals):
//!   usdc_out = btc_amount  * btc_price       (e.g. 96000)
//!   btc_out  = usdc_amount / btc_price
//!
//! Tokens are minted via their public faucet on each simulated swap.
//! LP is tracked internally; remove_liquidity returns the tracked amounts.

use starknet::ContractAddress;

/// Admin: update the simulated BTC price
#[starknet::interface]
pub trait IMockEkuboAdmin<TContractState> {
    /// Set BTC price in USDC units (both 18 decimals).
    /// E.g. pass 96000 for $96,000 per BTC.
    fn set_btc_price(ref self: TContractState, btc_price: u256);
    fn get_btc_price(self: @TContractState) -> u256;
}

/// Minimal faucet interface — avoids circular imports
#[starknet::interface]
trait IFaucet<TContractState> {
    fn faucet(ref self: TContractState, amount: u256);
}

#[starknet::contract]
pub mod MockEkuboAdapter {
    use super::{ContractAddress, IMockEkuboAdmin, IFaucetDispatcher, IFaucetDispatcherTrait};
    use starkyield::integrations::ekubo::IEkuboAdapter;
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::get_caller_address;

    // Default BTC price: $96,000 (both tokens 18 decimals, so no extra scaling)
    const DEFAULT_BTC_PRICE: u256 = 96000_u256;

    #[storage]
    struct Storage {
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        /// USDC per BTC (e.g. 96000). Both tokens are 18 decimals.
        btc_price: u256,
        /// LP tracking
        lp_btc: u256,
        lp_usdc: u256,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(
        ref self: ContractState,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        owner: ContractAddress,
    ) {
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.btc_price.write(DEFAULT_BTC_PRICE);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl EkuboAdapterImpl of IEkuboAdapter<ContractState> {
        /// Simulate BTC → USDC swap.
        /// BTC already in this contract (transferred by LeverageManager).
        /// Mints USDC via MockUSDC.faucet() and keeps it here for add_liquidity.
        fn swap_btc_to_usdc(
            ref self: ContractState, btc_amount: u256, min_usdc_out: u256,
        ) -> u256 {
            if btc_amount == 0 {
                return 0;
            }
            let usdc_out = btc_amount * self.btc_price.read();
            assert(usdc_out >= min_usdc_out, 'Slippage too high');
            IFaucetDispatcher { contract_address: self.usdc_token.read() }.faucet(usdc_out);
            usdc_out
        }

        /// Simulate USDC → BTC swap.
        /// USDC already in this contract (forwarded by MockLendingAdapter).
        /// Mints BTC via MockWBTC.faucet() and keeps it here.
        fn swap_usdc_to_btc(
            ref self: ContractState, usdc_amount: u256, min_btc_out: u256,
        ) -> u256 {
            if usdc_amount == 0 {
                return 0;
            }
            let price = self.btc_price.read();
            if price == 0 {
                return 0;
            }
            let btc_out = usdc_amount / price;
            assert(btc_out >= min_btc_out, 'Slippage too high');
            IFaucetDispatcher { contract_address: self.btc_token.read() }.faucet(btc_out);
            btc_out
        }

        /// Simulate adding LP.
        /// BTC and USDC already in this contract.
        /// Tracks amounts and returns fixed token_id = 1.
        fn add_liquidity(
            ref self: ContractState, btc_amount: u256, usdc_amount: u256,
        ) -> u64 {
            self.lp_btc.write(self.lp_btc.read() + btc_amount);
            self.lp_usdc.write(self.lp_usdc.read() + usdc_amount);
            1_u64
        }

        /// Simulate removing LP. Returns tracked BTC + USDC to caller.
        fn remove_liquidity(ref self: ContractState, token_id: u64) -> (u256, u256) {
            let btc = self.lp_btc.read();
            let usdc = self.lp_usdc.read();
            if btc > 0 {
                IERC20Dispatcher { contract_address: self.btc_token.read() }
                    .transfer(get_caller_address(), btc);
                self.lp_btc.write(0);
            }
            if usdc > 0 {
                IERC20Dispatcher { contract_address: self.usdc_token.read() }
                    .transfer(get_caller_address(), usdc);
                self.lp_usdc.write(0);
            }
            (btc, usdc)
        }
    }

    #[abi(embed_v0)]
    impl MockEkuboAdminImpl of IMockEkuboAdmin<ContractState> {
        fn set_btc_price(ref self: ContractState, btc_price: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            assert(btc_price > 0, 'Price must be > 0');
            self.btc_price.write(btc_price);
        }

        fn get_btc_price(self: @ContractState) -> u256 {
            self.btc_price.read()
        }
    }
}
