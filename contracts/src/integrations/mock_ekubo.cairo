//! Mock Ekubo Adapter for testnet (v12 — BTC=8 dec, USDC=6 dec)
//!
//! Simulates Ekubo DEX swaps and LP — no real pool required.
//! Implements IEkuboAdapter so it is a drop-in replacement for EkuboAdapter.
//!
//! Multi-position LP: each add_liquidity call returns a unique token_id.
//! remove_liquidity(token_id) only removes that specific position.
//!
//! Swap model (v12 decimals: BTC=8, USDC=6):
//!   usdc_out = btc_amount * btc_price / 100       (8dec→6dec: /10^(8-6))
//!   btc_out  = usdc_amount * 100 / btc_price       (6dec→8dec: *10^(8-6))
//!
//! Tokens are minted via their public faucet on each simulated swap.
//! LP is tracked per position; remove_liquidity returns that position's amounts.

use starknet::ContractAddress;

/// Admin: update the simulated BTC price
#[starknet::interface]
pub trait IMockEkuboAdmin<TContractState> {
    /// Set BTC price in USDC units (both 18 decimals).
    /// E.g. pass 96000 for $96,000 per BTC.
    fn set_btc_price(ref self: TContractState, btc_price: u256);
    fn get_btc_price(self: @TContractState) -> u256;
}

/// LP value query and ownership transfer (StarkYield extension)
#[starknet::interface]
pub trait IMockEkuboLP<TContractState> {
    /// Returns total LP value in USDC units (6-decimal) for the given token_id.
    fn get_lp_value(self: @TContractState, token_id: u64) -> u256;
    /// No-op in mock: ownership is implicit in the single shared pool.
    fn transfer_lp(ref self: TContractState, token_id: u64, to: ContractAddress);
}

/// Minimal faucet interface — avoids circular imports
#[starknet::interface]
trait IFaucet<TContractState> {
    fn faucet(ref self: TContractState, amount: u256);
}

#[starknet::contract]
pub mod MockEkuboAdapter {
    use super::{ContractAddress, IMockEkuboAdmin, IMockEkuboLP, IFaucetDispatcher, IFaucetDispatcherTrait};
    use starkyield::integrations::ekubo::IEkuboAdapter;
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{get_caller_address, get_contract_address};
    use starknet::storage::Map;

    // Default BTC price: $96,000. Raw integer — decimal conversion handled in formulas.
    const DEFAULT_BTC_PRICE: u256 = 96000_u256;

    // Scale factor for BTC(8dec) ↔ USDC(6dec) conversion: 10^(8-6) = 100
    const DECIMAL_BRIDGE: u256 = 100_u256;

    #[storage]
    struct Storage {
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        /// USDC per BTC (e.g. 96000). Both tokens are 18 decimals.
        btc_price: u256,
        /// Multi-position LP tracking (per token_id)
        lp_btc: Map<u64, u256>,
        lp_usdc: Map<u64, u256>,
        next_token_id: u64,
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
        self.next_token_id.write(0);
    }

    #[abi(embed_v0)]
    impl EkuboAdapterImpl of IEkuboAdapter<ContractState> {
        /// Simulate BTC → USDC swap (v12: BTC=8dec, USDC=6dec).
        /// btc_amount is in 8-decimal raw. Output is in 6-decimal raw.
        /// Formula: usdc_out = btc_amount * price / DECIMAL_BRIDGE
        fn swap_btc_to_usdc(
            ref self: ContractState, btc_amount: u256, min_usdc_out: u256,
        ) -> u256 {
            if btc_amount == 0 {
                return 0;
            }
            let usdc_out = btc_amount * self.btc_price.read() / DECIMAL_BRIDGE;
            assert(usdc_out >= min_usdc_out, 'Slippage too high');
            IFaucetDispatcher { contract_address: self.usdc_token.read() }.faucet(usdc_out);
            usdc_out
        }

        /// Simulate USDC → BTC swap (v12: BTC=8dec, USDC=6dec).
        /// usdc_amount is in 6-decimal raw. Output is in 8-decimal raw.
        /// Formula: btc_out = usdc_amount * DECIMAL_BRIDGE / price
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
            let btc_out = usdc_amount * DECIMAL_BRIDGE / price;
            assert(btc_out >= min_btc_out, 'Slippage too high');
            IFaucetDispatcher { contract_address: self.btc_token.read() }.faucet(btc_out);
            btc_out
        }

        /// Simulate adding LP.
        /// Pulls BTC and USDC from caller into this contract and tracks amounts.
        /// Returns a unique token_id for this LP position.
        /// Caller must approve this contract for both tokens before calling.
        fn add_liquidity(
            ref self: ContractState, btc_amount: u256, usdc_amount: u256,
        ) -> u64 {
            let caller = get_caller_address();
            let this = get_contract_address();
            if btc_amount > 0 {
                IERC20Dispatcher { contract_address: self.btc_token.read() }
                    .transfer_from(caller, this, btc_amount);
            }
            if usdc_amount > 0 {
                IERC20Dispatcher { contract_address: self.usdc_token.read() }
                    .transfer_from(caller, this, usdc_amount);
            }
            let token_id = self.next_token_id.read() + 1;
            self.next_token_id.write(token_id);
            self.lp_btc.write(token_id, btc_amount);
            self.lp_usdc.write(token_id, usdc_amount);
            token_id
        }

        /// Simulate removing LP for a specific position.
        /// Returns tracked BTC + USDC for that token_id to caller.
        fn remove_liquidity(ref self: ContractState, token_id: u64) -> (u256, u256) {
            let btc = self.lp_btc.read(token_id);
            let usdc = self.lp_usdc.read(token_id);
            if btc > 0 {
                IERC20Dispatcher { contract_address: self.btc_token.read() }
                    .transfer(get_caller_address(), btc);
                self.lp_btc.write(token_id, 0);
            }
            if usdc > 0 {
                IERC20Dispatcher { contract_address: self.usdc_token.read() }
                    .transfer(get_caller_address(), usdc);
                self.lp_usdc.write(token_id, 0);
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

    #[abi(embed_v0)]
    impl MockEkuboLPImpl of IMockEkuboLP<ContractState> {
        /// Returns total LP value in USDC (6-decimal) for a specific position.
        /// Converts BTC(8dec) to USDC(6dec) before summing with USDC reserves.
        fn get_lp_value(self: @ContractState, token_id: u64) -> u256 {
            let btc_in_usdc = self.lp_btc.read(token_id) * self.btc_price.read() / DECIMAL_BRIDGE;
            btc_in_usdc + self.lp_usdc.read(token_id)
        }

        /// No-op: mock uses implicit shared-pool ownership.
        fn transfer_lp(ref self: ContractState, token_id: u64, to: ContractAddress) {
            let _ = token_id;
            let _ = to;
        }
    }
}
