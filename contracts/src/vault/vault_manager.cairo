//! Vault Manager — YieldBasis v10 (correct CDP + flash loan order)
//!
//! Deposit:  flash_loan(usdc) → add_liquidity(BTC+USDC→LP) → deposit_collateral_lp
//!           → borrow_usdc → repay_flash_loan → mint LT
//!
//! Withdraw: flash_loan(debt) → repay_usdc → withdraw_collateral_lp → remove_liquidity
//!           → repay_flash_loan → burn LT → send BTC
//!
//! The VirtualPool provides fee-less flash loans (mock: USDC minted via faucet).
//! Borrowing occurs AFTER the LP is posted as collateral (correct CDP semantics).

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

/// MockEkuboAdapter: price + liquidity
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

/// VirtualPool: fee-less flash loans
#[starknet::interface]
trait IVirtualPoolFacade<TContractState> {
    fn flash_loan(ref self: TContractState, amount: u256);
    fn repay_flash_loan(ref self: TContractState, amount: u256);
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
        IERC20MinDispatcher,           IERC20MinDispatcherTrait,
        ILtMinDispatcher,              ILtMinDispatcherTrait,
        IEkuboFacadeDispatcher,        IEkuboFacadeDispatcherTrait,
        ILendingFacadeDispatcher,      ILendingFacadeDispatcherTrait,
        IVirtualPoolFacadeDispatcher,  IVirtualPoolFacadeDispatcherTrait,
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
        virtual_pool:    ContractAddress,
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
        virtual_pool:    ContractAddress,
        owner:           ContractAddress,
    ) {
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.lt_token.write(lt_token);
        self.ekubo_adapter.write(ekubo_adapter);
        self.lending_adapter.write(lending_adapter);
        self.virtual_pool.write(virtual_pool);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl VaultManagerImpl of IVaultManager<ContractState> {
        /// Deposit BTC — correct YieldBasis CDP flow.
        ///
        /// Order: flash_loan → add_liquidity → deposit_collateral_lp → borrow_usdc → repay_flash_loan
        ///
        /// The LP is posted as collateral BEFORE borrowing — economically sound.
        /// The borrowed USDC exactly covers the flash loan repayment.
        fn deposit(ref self: ContractState, amount: u256) -> u256 {
            assert(amount > 0, 'Amount must be > 0');

            let caller     = get_caller_address();
            let this       = get_contract_address();
            let btc_addr   = self.btc_token.read();
            let usdc_addr  = self.usdc_token.read();
            let ekubo_addr = self.ekubo_adapter.read();
            let lend_addr  = self.lending_adapter.read();
            let vpool_addr = self.virtual_pool.read();
            let lt_addr    = self.lt_token.read();

            let btc     = IERC20MinDispatcher           { contract_address: btc_addr };
            let usdc    = IERC20MinDispatcher           { contract_address: usdc_addr };
            let ekubo   = IEkuboFacadeDispatcher        { contract_address: ekubo_addr };
            let lending = ILendingFacadeDispatcher      { contract_address: lend_addr };
            let vpool   = IVirtualPoolFacadeDispatcher  { contract_address: vpool_addr };
            let lt      = ILtMinDispatcher              { contract_address: lt_addr };

            // 1. Pull BTC from user
            let ok = btc.transfer_from(caller, this, amount);
            assert(ok, 'BTC transfer_from failed');

            // 2. USDC needed = amount × raw BTC price (e.g. 1 BTC × 96000 = 96000 USDC)
            let usdc_needed = amount * ekubo.get_btc_price();

            // 3. Flash loan: VirtualPool mints usdc_needed and sends to vault
            //    (vault temporarily holds BTC + USDC, net cost = 0 at end)
            vpool.flash_loan(usdc_needed);

            // 4. Add LP: vault provides BTC + USDC → receives LP token
            btc.approve(ekubo_addr, amount);
            usdc.approve(ekubo_addr, usdc_needed);
            let lp_id = ekubo.add_liquidity(amount, usdc_needed);

            // 5. Post LP as CDP collateral — BEFORE borrowing (correct CDP semantics)
            lending.deposit_collateral_lp(lp_id.into());

            // 6. Borrow USDC against LP collateral (mock: mints USDC to vault)
            //    This USDC is used to repay the flash loan.
            lending.borrow_usdc(usdc_needed);

            // 7. Repay flash loan with borrowed USDC
            usdc.approve(vpool_addr, usdc_needed);
            vpool.repay_flash_loan(usdc_needed);

            // 8. Mint LT shares 1:1 with deposited BTC + update accounting
            let shares = amount;
            lt.mint(caller, shares);
            let cur = self.user_shares.read(caller);
            self.user_shares.write(caller, cur + shares);
            self.total_shares.write(self.total_shares.read() + shares);
            self.total_debt.write(self.total_debt.read() + usdc_needed);

            shares
        }

        /// Withdraw BTC — correct YieldBasis CDP flow.
        ///
        /// Order: flash_loan(debt) → repay_usdc → withdraw_collateral_lp
        ///        → remove_liquidity → [re-add remaining LP] → repay_flash_loan → burn LT → send BTC
        ///
        /// Flash loan covers the CDP debt repayment. After LP removal, the
        /// recovered USDC repays the flash loan. Net: vault → user gets BTC back.
        ///
        /// For partial withdrawals, the remaining (non-withdrawn) portion of BTC+USDC
        /// is re-added to the LP so the remaining depositors' position stays intact.
        fn withdraw(ref self: ContractState, shares: u256) -> u256 {
            assert(shares > 0, 'Shares must be > 0');

            let caller   = get_caller_address();
            let user_bal = self.user_shares.read(caller);
            assert(shares <= user_bal, 'Insufficient shares');

            let total      = self.total_shares.read();
            let total_debt = self.total_debt.read();
            let debt_share = if total > 0 { shares * total_debt / total } else { 0 };

            let btc_addr   = self.btc_token.read();
            let usdc_addr  = self.usdc_token.read();
            let ekubo_addr = self.ekubo_adapter.read();
            let lend_addr  = self.lending_adapter.read();
            let vpool_addr = self.virtual_pool.read();
            let lt_addr    = self.lt_token.read();

            let btc     = IERC20MinDispatcher           { contract_address: btc_addr };
            let usdc    = IERC20MinDispatcher           { contract_address: usdc_addr };
            let ekubo   = IEkuboFacadeDispatcher        { contract_address: ekubo_addr };
            let lending = ILendingFacadeDispatcher      { contract_address: lend_addr };
            let vpool   = IVirtualPoolFacadeDispatcher  { contract_address: vpool_addr };
            let lt      = ILtMinDispatcher              { contract_address: lt_addr };

            // 1. Flash loan: get USDC to repay CDP debt
            if debt_share > 0 { vpool.flash_loan(debt_share); }

            // 2. Repay CDP debt (mock: counter-only; vault still holds flash loan USDC)
            if debt_share > 0 { lending.repay_usdc(debt_share); }

            // 3. Withdraw LP collateral (CDP now cleared)
            let lp_felt   = lending.withdraw_collateral_lp();
            let lp_id_u64: u64 = lp_felt.try_into().unwrap_or(1_u64);

            // 4. Remove ALL LP → get BTC + USDC back from Ekubo (mock always removes full pool)
            let (btc_all, usdc_all) = ekubo.remove_liquidity(lp_id_u64);

            // 5. Re-add proportional LP for remaining depositors (partial withdraw fix).
            //    Without this, remove_liquidity clears the entire pool and remaining
            //    depositors have no LP backing — causing DTV to blow up on next deposit.
            let remaining = total - shares;
            if remaining > 0 && btc_all > 0 {
                let btc_re  = btc_all  * remaining / total;
                let usdc_re = usdc_all * remaining / total;
                if btc_re  > 0 { btc.approve(ekubo_addr,  btc_re);  }
                if usdc_re > 0 { usdc.approve(ekubo_addr, usdc_re); }
                let new_lp_id = ekubo.add_liquidity(btc_re, usdc_re);
                // Re-register remaining LP as CDP collateral for remaining depositors
                lending.deposit_collateral_lp(new_lp_id.into());
            }

            // 6. User's proportional BTC (rest stays in vault as stranded dust for mock)
            let btc_out = if total > 0 { btc_all * shares / total } else { btc_all };

            // 7. Repay flash loan (vault still has debt_share USDC since repay_usdc is counter-only)
            if debt_share > 0 {
                usdc.approve(vpool_addr, debt_share);
                vpool.repay_flash_loan(debt_share);
            }

            // 8. Burn LT + update accounting
            lt.burn(caller, shares);
            self.user_shares.write(caller, user_bal - shares);
            self.total_shares.write(total - shares);
            self.total_debt.write(if total_debt >= debt_share { total_debt - debt_share } else { 0 });

            // 9. Transfer BTC to user
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
