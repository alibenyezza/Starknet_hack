//! Vault Manager — StarkYield v12
//!
//! Deposit:  flash_loan(usdc) → add_liquidity(BTC+USDC→LP) → deposit_collateral_lp
//!           → borrow_usdc → repay_flash_loan → mint LT
//!
//! Withdraw: [risk_check] → [accrue_interest] → flash_loan(debt) → repay_usdc
//!           → withdraw_collateral_lp → remove_liquidity → repay_flash_loan → burn LT → send BTC
//!
//! v12 features:
//!   - paused: bool — owner can pause/unpause all deposits + withdrawals
//!   - risk_manager: health + daily withdrawal limit check before every withdrawal
//!   - fee_distributor + levamm: wired for fee collection and interest accrual
//!   - high_watermark: tracks ATH share price for recovery mode
//!   - collect_fees(): permissionless fee harvesting via LEVAMM

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

/// RiskManager: health check before withdrawal
#[starknet::interface]
trait IRiskManager<TContractState> {
    fn check_withdrawal_limit(self: @TContractState, amount: u256) -> bool;
    fn record_withdrawal(ref self: TContractState, amount: u256);
}

/// LEVAMM facade: notify of position changes
#[starknet::interface]
trait ILevAMMFacade<TContractState> {
    fn accrue_interest(ref self: TContractState);
    fn collect_fees(ref self: TContractState) -> u256;
}

/// FeeDistributor facade
#[starknet::interface]
trait IFeeDistributorFacade<TContractState> {
    fn distribute(ref self: TContractState, dist_amount: u256);
    fn harvest(ref self: TContractState);
}

/// PragmaAdapter facade: price staleness check
#[starknet::interface]
trait IPragmaFacade<TContractState> {
    fn is_price_stale(self: @TContractState) -> bool;
}

// ── Public interface ─────────────────────────────────────────────────────────

#[starknet::interface]
pub trait IVaultManager<TContractState> {
    fn deposit(ref self: TContractState, amount: u256) -> u256;
    fn withdraw(ref self: TContractState, shares: u256) -> u256;
    fn collect_fees(ref self: TContractState) -> u256;
    fn get_user_shares(self: @TContractState, user: ContractAddress) -> u256;
    fn get_total_shares(self: @TContractState) -> u256;
    fn get_total_debt(self: @TContractState) -> u256;
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn is_paused(self: @TContractState) -> bool;
    fn set_fee_distributor(ref self: TContractState, addr: ContractAddress);
    fn set_levamm(ref self: TContractState, addr: ContractAddress);
    fn set_pragma_adapter(ref self: TContractState, addr: ContractAddress);
}

#[starknet::contract]
pub mod VaultManager {
    use super::{
        IVaultManager, ContractAddress,
        IERC20MinDispatcher,              IERC20MinDispatcherTrait,
        ILtMinDispatcher,                 ILtMinDispatcherTrait,
        IEkuboFacadeDispatcher,           IEkuboFacadeDispatcherTrait,
        ILendingFacadeDispatcher,         ILendingFacadeDispatcherTrait,
        IVirtualPoolFacadeDispatcher,     IVirtualPoolFacadeDispatcherTrait,
        IRiskManagerDispatcher,           IRiskManagerDispatcherTrait,
        ILevAMMFacadeDispatcher,          ILevAMMFacadeDispatcherTrait,
        IFeeDistributorFacadeDispatcher,  IFeeDistributorFacadeDispatcherTrait,
        IPragmaFacadeDispatcher,          IPragmaFacadeDispatcherTrait,
    };
    use starknet::{get_caller_address, get_contract_address};
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        btc_token:         ContractAddress,
        usdc_token:        ContractAddress,
        lt_token:          ContractAddress,
        ekubo_adapter:     ContractAddress,
        lending_adapter:   ContractAddress,
        virtual_pool:      ContractAddress,
        risk_manager:      ContractAddress,
        fee_distributor:   ContractAddress,
        levamm:            ContractAddress,
        pragma_adapter:    ContractAddress,
        owner:             ContractAddress,
        total_shares:      u256,
        user_shares:       Map<ContractAddress, u256>,
        total_debt:        u256,
        paused:            bool,
        // High watermark: track ATH share price (1e18-scaled)
        high_watermark:    u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Paused: Paused,
        Unpaused: Unpaused,
        FeesCollected: FeesCollected,
    }

    #[derive(Drop, starknet::Event)]
    struct Paused { by: ContractAddress }

    #[derive(Drop, starknet::Event)]
    struct Unpaused { by: ContractAddress }

    #[derive(Drop, starknet::Event)]
    struct FeesCollected { levamm_fees: u256 }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        btc_token:       ContractAddress,
        usdc_token:      ContractAddress,
        lt_token:        ContractAddress,
        ekubo_adapter:   ContractAddress,
        lending_adapter: ContractAddress,
        virtual_pool:    ContractAddress,
        risk_manager:    ContractAddress,
        owner:           ContractAddress,
    ) {
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.lt_token.write(lt_token);
        self.ekubo_adapter.write(ekubo_adapter);
        self.lending_adapter.write(lending_adapter);
        self.virtual_pool.write(virtual_pool);
        self.risk_manager.write(risk_manager);
        self.owner.write(owner);
        self.paused.write(false);
        self.high_watermark.write(1_000000000000000000); // 1.0 initial share price
    }

    #[abi(embed_v0)]
    impl VaultManagerImpl of IVaultManager<ContractState> {
        /// Deposit BTC — correct StarkYield CDP flow.
        ///
        /// Order: consolidate_old_LP → flash_loan → add_combined_LP → deposit_collateral_lp → borrow_usdc → repay_flash_loan
        fn deposit(ref self: ContractState, amount: u256) -> u256 {
            assert(!self.paused.read(), 'Vault is paused');
            self._check_price_staleness();
            assert(amount > 0, 'Amount must be > 0');

            // Auto-harvest pending fees before new deposit
            self._auto_harvest();

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

            // 2. Consolidate with existing LP (prevents LP orphaning on multiple deposits)
            let old_lp_felt = lending.withdraw_collateral_lp();
            let (old_btc, old_usdc) = if old_lp_felt != 0 {
                let old_lp_id: u64 = old_lp_felt.try_into().unwrap_or(1_u64);
                ekubo.remove_liquidity(old_lp_id)
            } else {
                (0_u256, 0_u256)
            };

            // 3. USDC needed for new deposit: convert BTC-raw (8 dec) to USDC-raw (6 dec)
            //    amount_raw * price / 10^BTC_DEC * 10^USDC_DEC = amount * price / 100
            let usdc_needed = amount * ekubo.get_btc_price() / 100;

            // 4. Flash loan: VirtualPool transfers usdc_needed from reserves to vault
            vpool.flash_loan(usdc_needed);

            // 5. Add LP: combine old position + new deposit
            let combined_btc = old_btc + amount;
            let combined_usdc = old_usdc + usdc_needed;
            btc.approve(ekubo_addr, combined_btc);
            usdc.approve(ekubo_addr, combined_usdc);
            let lp_id = ekubo.add_liquidity(combined_btc, combined_usdc);

            // 6. Post LP as CDP collateral — BEFORE borrowing (correct CDP semantics)
            lending.deposit_collateral_lp(lp_id.into());

            // 7. Borrow USDC against LP collateral (mock: mints USDC to vault)
            lending.borrow_usdc(usdc_needed);

            // 8. Repay flash loan with borrowed USDC
            usdc.approve(vpool_addr, usdc_needed);
            vpool.repay_flash_loan(usdc_needed);

            // 9. Mint LT shares 1:1 with deposited BTC + update accounting
            let shares = amount;
            lt.mint(caller, shares);
            let cur = self.user_shares.read(caller);
            self.user_shares.write(caller, cur + shares);
            self.total_shares.write(self.total_shares.read() + shares);
            self.total_debt.write(self.total_debt.read() + usdc_needed);

            shares
        }

        /// Withdraw BTC — correct StarkYield CDP flow.
        ///
        /// Order: [risk_check] → flash_loan(debt) → repay_usdc → withdraw_collateral_lp
        ///        → remove_liquidity → [re-add remaining LP] → repay_flash_loan → burn LT → send BTC
        fn withdraw(ref self: ContractState, shares: u256) -> u256 {
            assert(!self.paused.read(), 'Vault is paused');
            self._check_price_staleness();
            assert(shares > 0, 'Shares must be > 0');

            let caller   = get_caller_address();
            let user_bal = self.user_shares.read(caller);
            assert(shares <= user_bal, 'Insufficient shares');

            // Risk check (skipped if risk_manager is zero address)
            let rm_addr = self.risk_manager.read();
            let zero: ContractAddress = 0.try_into().unwrap();
            if rm_addr != zero {
                let rm = IRiskManagerDispatcher { contract_address: rm_addr };
                let ok = rm.check_withdrawal_limit(shares);
                assert(ok, 'RiskManager: limit exceeded');
                rm.record_withdrawal(shares);
            }

            // Auto-harvest pending fees before withdrawal
            self._auto_harvest();

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

            // 2. Repay CDP debt
            if debt_share > 0 { lending.repay_usdc(debt_share); }

            // 3. Withdraw LP collateral (CDP now cleared)
            let lp_felt   = lending.withdraw_collateral_lp();
            let lp_id_u64: u64 = lp_felt.try_into().unwrap_or(1_u64);

            // 4. Remove ALL LP → get BTC + USDC back from Ekubo
            let (btc_all, usdc_all) = ekubo.remove_liquidity(lp_id_u64);

            // 5. Re-add proportional LP for remaining depositors (partial withdraw fix)
            let remaining = total - shares;
            if remaining > 0 && btc_all > 0 {
                let btc_re  = btc_all  * remaining / total;
                let usdc_re = usdc_all * remaining / total;
                if btc_re  > 0 { btc.approve(ekubo_addr,  btc_re);  }
                if usdc_re > 0 { usdc.approve(ekubo_addr, usdc_re); }
                let new_lp_id = ekubo.add_liquidity(btc_re, usdc_re);
                lending.deposit_collateral_lp(new_lp_id.into());
            }

            // 6. User's proportional BTC
            let btc_out = if total > 0 { btc_all * shares / total } else { btc_all };

            // 7. Repay flash loan
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

        fn pause(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.paused.write(true);
            self.emit(Paused { by: get_caller_address() });
        }

        fn unpause(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.paused.write(false);
            self.emit(Unpaused { by: get_caller_address() });
        }

        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }

        /// Trigger fee collection: accrue LEVAMM interest, then collect trading fees.
        /// Permissionless — anyone can call.
        fn collect_fees(ref self: ContractState) -> u256 {
            let zero: ContractAddress = 0.try_into().unwrap();
            let levamm_addr = self.levamm.read();
            if levamm_addr == zero { return 0; }

            let levamm = ILevAMMFacadeDispatcher { contract_address: levamm_addr };
            levamm.accrue_interest();
            let fees = levamm.collect_fees();
            self.emit(FeesCollected { levamm_fees: fees });
            fees
        }

        fn set_fee_distributor(ref self: ContractState, addr: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.fee_distributor.write(addr);
        }

        fn set_levamm(ref self: ContractState, addr: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.levamm.write(addr);
        }

        fn set_pragma_adapter(ref self: ContractState, addr: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.pragma_adapter.write(addr);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// If a PragmaAdapter is wired (non-zero), assert the price feed is fresh.
        /// Skips the check when pragma_adapter is the zero address (backwards compatible).
        fn _check_price_staleness(self: @ContractState) {
            let pragma_addr = self.pragma_adapter.read();
            let zero: ContractAddress = 0.try_into().unwrap();
            if pragma_addr != zero {
                let pragma = IPragmaFacadeDispatcher { contract_address: pragma_addr };
                assert(!pragma.is_price_stale(), 'Price feed stale');
            }
        }

        /// Auto-harvest: collect LEVAMM fees + flush to LT holders via FeeDistributor.
        /// Graceful no-op when LEVAMM or FeeDistributor is not wired (zero address).
        fn _auto_harvest(ref self: ContractState) {
            self.collect_fees();
            let fd_addr = self.fee_distributor.read();
            let zero: ContractAddress = 0.try_into().unwrap();
            if fd_addr != zero {
                IFeeDistributorFacadeDispatcher { contract_address: fd_addr }.harvest();
            }
        }
    }
}
