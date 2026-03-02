//! Vault Manager — YieldBasis v9 (ultra-slim for mock adapters)
//!
//! Deposit:  borrow_usdc (uncollateralized mock) → add_liquidity → deposit_lp → mint LT
//! Withdraw: withdraw_lp → remove_liquidity → repay_usdc (counter-only) → burn LT → send BTC
//!
//! No flash loan needed: MockLendingAdapter.borrow_usdc mints USDC directly (no collateral
//! check), and repay_usdc only decrements a counter (no token transfer).
//! No events. No pause. 4 dispatcher types, 13 total external calls vs 24 before.

use starknet::ContractAddress;

// ── Minimal local facade interfaces ─────────────────────────────────────────

/// Minimal ERC-20: only 3 functions used by VaultManager
#[starknet::interface]
trait IERC20Min<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

/// Minimal LT token: mint + burn
#[starknet::interface]
trait ILtMin<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
}

/// MockEkuboAdapter: price + liquidity only (no get_lp_value — read from adapter directly)
#[starknet::interface]
trait IEkuboFacade<TContractState> {
    fn get_btc_price(self: @TContractState) -> u256;
    fn add_liquidity(ref self: TContractState, btc_amount: u256, usdc_amount: u256) -> u64;
    fn remove_liquidity(ref self: TContractState, token_id: u64) -> (u256, u256);
}

/// MockLendingAdapter: CDP lifecycle
#[starknet::interface]
trait ILendingFacade<TContractState> {
    fn deposit_collateral_lp(ref self: TContractState, lp_id: felt252);
    fn withdraw_collateral_lp(ref self: TContractState) -> felt252;
    fn borrow_usdc(ref self: TContractState, amount: u256);
    fn repay_usdc(ref self: TContractState, amount: u256);
}

// ── Public interface ─────────────────────────────────────────────────────────

#[starknet::interface]
pub trait IVaultManager<TContractState> {
    fn deposit(ref self: TContractState, amount: u256) -> u256;
    fn withdraw(ref self: TContractState, shares: u256) -> u256;
    fn get_user_shares(self: @TContractState, user: ContractAddress) -> u256;
    fn get_total_shares(self: @TContractState) -> u256;
    fn get_total_debt(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod VaultManager {
    use super::{
        IVaultManager, ContractAddress,
        IERC20MinDispatcher,      IERC20MinDispatcherTrait,
        ILtMinDispatcher,         ILtMinDispatcherTrait,
        IEkuboFacadeDispatcher,   IEkuboFacadeDispatcherTrait,
        ILendingFacadeDispatcher, ILendingFacadeDispatcherTrait,
    };
    use starknet::{get_caller_address, get_contract_address};
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        btc_token:       ContractAddress,
        usdc_token:      ContractAddress,
        lt_token:        ContractAddress,
        ekubo_adapter:   ContractAddress,
        lending_adapter: ContractAddress,
        owner:           ContractAddress,
        total_shares:    u256,
        user_shares:     Map<ContractAddress, u256>,
        total_debt:      u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(
        ref self: ContractState,
        btc_token:       ContractAddress,
        usdc_token:      ContractAddress,
        lt_token:        ContractAddress,
        ekubo_adapter:   ContractAddress,
        lending_adapter: ContractAddress,
        virtual_pool:    ContractAddress, // kept for deploy-script compat, ignored in v9
        owner:           ContractAddress,
    ) {
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.lt_token.write(lt_token);
        self.ekubo_adapter.write(ekubo_adapter);
        self.lending_adapter.write(lending_adapter);
        self.owner.write(owner);
        let _ = virtual_pool; // no flash loan in v9
    }

    #[abi(embed_v0)]
    impl VaultManagerImpl of IVaultManager<ContractState> {
        /// Deposit BTC — YieldBasis CDP flow (mock-simplified, no flash loan).
        /// MockLendingAdapter.borrow_usdc mints USDC directly without collateral check.
        fn deposit(ref self: ContractState, amount: u256) -> u256 {
            assert(amount > 0, 'Amount must be > 0');

            let caller     = get_caller_address();
            let this       = get_contract_address();
            let btc_addr   = self.btc_token.read();
            let usdc_addr  = self.usdc_token.read();
            let ekubo_addr = self.ekubo_adapter.read();
            let lend_addr  = self.lending_adapter.read();
            let lt_addr    = self.lt_token.read();

            let btc     = IERC20MinDispatcher     { contract_address: btc_addr };
            let usdc    = IERC20MinDispatcher     { contract_address: usdc_addr };
            let ekubo   = IEkuboFacadeDispatcher  { contract_address: ekubo_addr };
            let lending = ILendingFacadeDispatcher{ contract_address: lend_addr };
            let lt      = ILtMinDispatcher        { contract_address: lt_addr };

            // 1. Pull BTC from user
            let ok = btc.transfer_from(caller, this, amount);
            assert(ok, 'BTC transfer_from failed');

            // 2. USDC needed = amount × raw BTC price (e.g. 1e18 × 96000 = 96000e18)
            let usdc_needed = amount * ekubo.get_btc_price();

            // 3. Borrow USDC from lending (mock: mints USDC, no collateral check)
            lending.borrow_usdc(usdc_needed);

            // 4. Add LP: vault → Ekubo (BTC + USDC → LP token)
            btc.approve(ekubo_addr, amount);
            usdc.approve(ekubo_addr, usdc_needed);
            let lp_id = ekubo.add_liquidity(amount, usdc_needed);

            // 5. Record LP as CDP collateral
            lending.deposit_collateral_lp(lp_id.into());

            // 6. Mint LT shares 1:1 with deposited BTC + update accounting
            let shares = amount;
            lt.mint(caller, shares);
            let cur = self.user_shares.read(caller);
            self.user_shares.write(caller, cur + shares);
            self.total_shares.write(self.total_shares.read() + shares);
            self.total_debt.write(self.total_debt.read() + usdc_needed);

            shares
        }

        /// Withdraw BTC — simplified (no flash loan needed with mock).
        /// MockLendingAdapter.withdraw_collateral_lp does not enforce debt repayment.
        /// MockLendingAdapter.repay_usdc only decrements a counter (no token transfer).
        fn withdraw(ref self: ContractState, shares: u256) -> u256 {
            assert(shares > 0, 'Shares must be > 0');

            let caller   = get_caller_address();
            let user_bal = self.user_shares.read(caller);
            assert(shares <= user_bal, 'Insufficient shares');

            let total      = self.total_shares.read();
            let total_debt = self.total_debt.read();
            let debt_share = if total > 0 { shares * total_debt / total } else { 0 };

            let btc_addr   = self.btc_token.read();
            let ekubo_addr = self.ekubo_adapter.read();
            let lend_addr  = self.lending_adapter.read();
            let lt_addr    = self.lt_token.read();

            let btc     = IERC20MinDispatcher     { contract_address: btc_addr };
            let ekubo   = IEkuboFacadeDispatcher  { contract_address: ekubo_addr };
            let lending = ILendingFacadeDispatcher{ contract_address: lend_addr };
            let lt      = ILtMinDispatcher        { contract_address: lt_addr };

            // 1. Withdraw LP collateral (mock: no debt check)
            let lp_felt   = lending.withdraw_collateral_lp();
            let lp_id_u64: u64 = lp_felt.try_into().unwrap_or(1_u64);

            // 2. Remove LP → BTC + USDC (USDC stays in vault, not needed for repay)
            let (btc_all, _) = ekubo.remove_liquidity(lp_id_u64);

            // 3. User's proportional BTC
            let btc_out = if total > 0 { btc_all * shares / total } else { btc_all };

            // 4. Repay debt (mock: counter-only, no token transfer required)
            if debt_share > 0 { lending.repay_usdc(debt_share); }

            // 5. Burn LT + update accounting
            lt.burn(caller, shares);
            self.user_shares.write(caller, user_bal - shares);
            self.total_shares.write(total - shares);
            self.total_debt.write(if total_debt >= debt_share { total_debt - debt_share } else { 0 });

            // 6. Transfer BTC to user
            if btc_out > 0 { btc.transfer(caller, btc_out); }

            btc_out
        }

        fn get_user_shares(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_shares.read(user)
        }

        fn get_total_shares(self: @ContractState) -> u256 { self.total_shares.read() }

        fn get_total_debt(self: @ContractState) -> u256 { self.total_debt.read() }
    }
}
