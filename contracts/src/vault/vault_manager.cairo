//! Vault Manager - Main contract for StarkYield protocol
//!
//! This contract manages deposits, withdrawals, and strategy allocation
//! for the IL-free BTC liquidity protocol.

use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::get_contract_address;
use starkyield::utils::constants::Constants;
use starkyield::utils::math::Math;
use starkyield::vault::sy_btc_token::ISyBtcTokenDispatcher;
use starkyield::vault::sy_btc_token::ISyBtcTokenDispatcherTrait;
use starkyield::integrations::ierc20::IERC20Dispatcher;
use starkyield::integrations::ierc20::IERC20DispatcherTrait;
use starkyield::integrations::pragma_oracle::IPragmaAdapterDispatcher;
use starkyield::integrations::pragma_oracle::IPragmaAdapterDispatcherTrait;
use starkyield::strategy::leverage_manager::ILeverageManagerDispatcher;
use starkyield::strategy::leverage_manager::ILeverageManagerDispatcherTrait;

#[starknet::interface]
pub trait IVaultManager<TContractState> {
    // Main functions
    fn deposit(ref self: TContractState, amount: u256) -> u256;
    fn withdraw(ref self: TContractState, shares: u256) -> u256;
    fn rebalance(ref self: TContractState);

    // Admin functions
    fn emergency_withdraw(ref self: TContractState);
    fn set_paused(ref self: TContractState, paused: bool);
    fn set_target_leverage(ref self: TContractState, leverage: u256);
    fn set_leverage_manager(ref self: TContractState, leverage_manager: ContractAddress);
    fn set_pragma_adapter(ref self: TContractState, pragma_adapter: ContractAddress);

    // View functions
    fn get_total_assets(self: @TContractState) -> u256;
    fn get_share_price(self: @TContractState) -> u256;
    fn get_health_factor(self: @TContractState) -> u256;
    fn get_user_shares(self: @TContractState, user: ContractAddress) -> u256;
    fn get_total_shares(self: @TContractState) -> u256;
    fn get_btc_price(self: @TContractState) -> u256;
    fn get_current_leverage(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod VaultManager {
    use super::{
        IVaultManager, ContractAddress, get_caller_address, get_contract_address, Constants, Math,
        ISyBtcTokenDispatcher, ISyBtcTokenDispatcherTrait,
        IERC20Dispatcher, IERC20DispatcherTrait,
        IPragmaAdapterDispatcher, IPragmaAdapterDispatcherTrait,
        ILeverageManagerDispatcher, ILeverageManagerDispatcherTrait,
    };
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        // Tokens
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        sy_btc_token: ContractAddress,

        // Tracking
        total_btc_deposited: u256,
        total_shares: u256,
        user_shares: Map<ContractAddress, u256>,

        // Strategy allocation
        btc_in_lp: u256,
        btc_leveraged: u256,
        usdc_borrowed: u256,

        // Risk parameters
        target_leverage: u256,
        max_leverage: u256,
        min_health_factor: u256,

        // External contracts
        ekubo_adapter: ContractAddress,
        vesu_adapter: ContractAddress,
        pragma_adapter: ContractAddress,
        leverage_manager: ContractAddress,

        // Admin
        owner: ContractAddress,
        is_paused: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
        Rebalance: Rebalance,
        Paused: Paused,
        EmergencyWithdraw: EmergencyWithdraw,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        user: ContractAddress,
        amount: u256,
        shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        user: ContractAddress,
        shares: u256,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Rebalance {
        old_leverage: u256,
        new_leverage: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Paused {
        paused: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdraw {
        total_btc_recovered: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        sy_btc_token: ContractAddress,
        ekubo_adapter: ContractAddress,
        vesu_adapter: ContractAddress,
        pragma_adapter: ContractAddress,
        leverage_manager: ContractAddress,
        owner: ContractAddress,
    ) {
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.sy_btc_token.write(sy_btc_token);
        self.ekubo_adapter.write(ekubo_adapter);
        self.vesu_adapter.write(vesu_adapter);
        self.pragma_adapter.write(pragma_adapter);
        self.leverage_manager.write(leverage_manager);
        self.owner.write(owner);
        self.is_paused.write(false);

        // Set default risk parameters
        self.target_leverage.write(Constants::TARGET_LEVERAGE);
        self.max_leverage.write(Constants::MAX_LEVERAGE);
        self.min_health_factor.write(Constants::MIN_HEALTH_FACTOR);
    }

    #[abi(embed_v0)]
    impl VaultManagerImpl of IVaultManager<ContractState> {
        /// Deposit BTC and receive syBTC shares
        fn deposit(ref self: ContractState, amount: u256) -> u256 {
            assert(!self.is_paused.read(), 'Vault is paused');
            assert(amount > 0, 'Amount must be > 0');

            let caller = get_caller_address();
            let shares = self._calculate_shares_for_deposit(amount);

            // Transfer BTC from user to vault
            self._transfer_btc_from_user(caller, amount);

            // Mint syBTC shares to user
            self._mint_shares(caller, shares);

            // Allocate to strategy via LeverageManager
            self._allocate_to_strategy(amount);

            // Update tracking
            self.total_btc_deposited.write(self.total_btc_deposited.read() + amount);

            self.emit(Deposit { user: caller, amount, shares });

            shares
        }

        /// Withdraw BTC by burning syBTC shares
        fn withdraw(ref self: ContractState, shares: u256) -> u256 {
            assert(!self.is_paused.read(), 'Vault is paused');
            assert(shares > 0, 'Shares must be > 0');

            let caller = get_caller_address();
            let user_shares = self.user_shares.read(caller);
            assert(shares <= user_shares, 'Insufficient shares');

            // Calculate BTC amount
            let btc_amount = self._calculate_btc_for_shares(shares);

            // Withdraw from strategy via LeverageManager
            self._withdraw_from_strategy(btc_amount);

            // Burn shares
            self._burn_shares(caller, shares);

            // Transfer BTC to user
            self._transfer_btc_to_user(caller, btc_amount);

            // Update tracking
            self.total_btc_deposited.write(self.total_btc_deposited.read() - btc_amount);

            self.emit(Withdraw { user: caller, shares, amount: btc_amount });

            btc_amount
        }

        /// Rebalance the position to match target leverage
        /// Callable by anyone — permissionless keeper function
        fn rebalance(ref self: ContractState) {
            assert(!self.is_paused.read(), 'Vault is paused');

            let lm = ILeverageManagerDispatcher {
                contract_address: self.leverage_manager.read(),
            };

            let current_leverage = lm.get_current_leverage();
            let target = self.target_leverage.read();

            // Check if rebalance is needed (deviation > REBALANCE_THRESHOLD)
            let deviation = Math::abs_diff(current_leverage, target);
            assert(deviation > Constants::REBALANCE_THRESHOLD, 'No rebalance needed');

            let old_leverage = current_leverage;

            if current_leverage > target {
                // Leverage too high — reduce by repaying USDC debt
                let excess = current_leverage - target;
                let usdc_borrowed = self.usdc_borrowed.read();
                let repay_ratio = Math::div_fixed(excess, current_leverage);
                let repay_amount = Math::mul_fixed(usdc_borrowed, repay_ratio);
                if repay_amount > 0 {
                    lm.reduce_leverage(repay_amount);
                }
            } else {
                // Leverage too low — increase by borrowing more
                let deficit = target - current_leverage;
                let btc_price = self._get_btc_price();
                let total_btc = self.btc_in_lp.read() + self.btc_leveraged.read();
                let additional_borrow_btc = Math::mul_fixed(
                    Math::div_fixed(deficit, target), total_btc
                );
                let additional_borrow_usdc = Math::mul_fixed(additional_borrow_btc, btc_price);
                if additional_borrow_usdc > 0 {
                    lm.increase_leverage(additional_borrow_usdc);
                }
            }

            // Sync state from leverage manager
            let (btc_lp, btc_lev, usdc_debt) = lm.get_position_info();
            self.btc_in_lp.write(btc_lp);
            self.btc_leveraged.write(btc_lev);
            self.usdc_borrowed.write(usdc_debt);

            let new_leverage = lm.get_current_leverage();

            // Safety: health factor must remain acceptable
            assert(
                self.get_health_factor() >= self.min_health_factor.read(),
                'HF too low after rebalance'
            );

            self.emit(Rebalance { old_leverage, new_leverage });
        }

        /// Emergency withdrawal — close all positions (admin only)
        fn emergency_withdraw(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');

            self.is_paused.write(true);
            self.emit(Paused { paused: true });

            // Close all positions via leverage manager
            let lm = ILeverageManagerDispatcher {
                contract_address: self.leverage_manager.read(),
            };
            lm.close_all_positions();

            // Reset strategy tracking
            self.btc_in_lp.write(0);
            self.btc_leveraged.write(0);
            self.usdc_borrowed.write(0);

            let recovered = self._get_btc_balance();
            self.emit(EmergencyWithdraw { total_btc_recovered: recovered });
        }

        /// Pause/unpause the vault (admin only)
        fn set_paused(ref self: ContractState, paused: bool) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.is_paused.write(paused);
            self.emit(Paused { paused });
        }

        /// Set target leverage (admin only)
        fn set_target_leverage(ref self: ContractState, leverage: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            assert(leverage >= Constants::MIN_LEVERAGE, 'Leverage too low');
            assert(leverage <= self.max_leverage.read(), 'Leverage too high');
            self.target_leverage.write(leverage);
        }

        /// Update the LeverageManager address (admin only).
        /// Allows connecting a newly deployed LeverageManager without redeploying the vault.
        fn set_leverage_manager(ref self: ContractState, leverage_manager: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.leverage_manager.write(leverage_manager);
        }

        /// Update the Pragma oracle adapter address (admin only).
        fn set_pragma_adapter(ref self: ContractState, pragma_adapter: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.pragma_adapter.write(pragma_adapter);
        }

        // ═══════════════════════════════════════════════════════
        // VIEW FUNCTIONS
        // ═══════════════════════════════════════════════════════

        /// Total assets = vault BTC balance + LP BTC + leveraged BTC - debt in BTC
        fn get_total_assets(self: @ContractState) -> u256 {
            let vault_balance = self._get_btc_balance();
            let lp = self.btc_in_lp.read();
            let leveraged = self.btc_leveraged.read();
            let debt_btc = self._convert_usdc_to_btc(self.usdc_borrowed.read());

            vault_balance + lp + leveraged - debt_btc
        }

        /// Price of 1 share in BTC terms (scaled 1e18)
        fn get_share_price(self: @ContractState) -> u256 {
            let total = self.total_shares.read();
            if total == 0 {
                return Constants::SCALE;
            }
            Math::div_fixed(self.get_total_assets(), total)
        }

        /// Health factor = collateral_value / (debt * liquidation_threshold)
        fn get_health_factor(self: @ContractState) -> u256 {
            let collateral = self._get_collateral_value();
            let debt = self.usdc_borrowed.read();
            if debt == 0 {
                return 999 * Constants::SCALE;
            }
            let debt_with_threshold = Math::mul_fixed(debt, Constants::LIQUIDATION_THRESHOLD);
            Math::div_fixed(collateral, debt_with_threshold)
        }

        fn get_user_shares(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_shares.read(user)
        }

        fn get_total_shares(self: @ContractState) -> u256 {
            self.total_shares.read()
        }

        /// Get current BTC/USD price from oracle
        fn get_btc_price(self: @ContractState) -> u256 {
            self._get_btc_price()
        }

        /// Get current leverage ratio
        fn get_current_leverage(self: @ContractState) -> u256 {
            let total_exposure = self.btc_in_lp.read() + self.btc_leveraged.read();
            if total_exposure == 0 {
                return Constants::SCALE;
            }

            let debt = self.usdc_borrowed.read();
            if debt == 0 {
                return Constants::SCALE;
            }

            let debt_in_btc = self._convert_usdc_to_btc(debt);
            let equity = if total_exposure > debt_in_btc {
                total_exposure - debt_in_btc
            } else {
                1
            };

            Math::div_fixed(total_exposure, equity)
        }
    }

    // ═══════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Calculate shares to mint for a deposit
        fn _calculate_shares_for_deposit(self: @ContractState, amount: u256) -> u256 {
            let total_shares = self.total_shares.read();
            let total_assets = self.get_total_assets();

            if total_shares == 0 {
                return amount;
            }

            // Direct proportion — do NOT use mul_fixed here.
            // total_shares is a raw count, not a 1e18-scaled fixed-point value.
            // Wrong formula: Math::mul_fixed(amount, total_shares) / total_assets
            //   = amount * total_shares / 1e18 / total_assets  (double division!)
            // Correct: shares = amount * total_shares / total_assets
            amount * total_shares / total_assets
        }

        /// Calculate BTC amount for shares
        fn _calculate_btc_for_shares(self: @ContractState, shares: u256) -> u256 {
            let total_shares = self.total_shares.read();
            assert(total_shares > 0, 'No shares exist');

            let total_assets = self.get_total_assets();
            // Direct proportion: btc = shares * total_assets / total_shares
            shares * total_assets / total_shares
        }

        /// Transfer BTC from user to vault
        fn _transfer_btc_from_user(
            ref self: ContractState, user: ContractAddress, amount: u256
        ) {
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            let vault_address = get_contract_address();
            let success = btc.transfer_from(user, vault_address, amount);
            assert(success, 'BTC transfer_from failed');
        }

        /// Transfer BTC from vault to user
        fn _transfer_btc_to_user(
            ref self: ContractState, user: ContractAddress, amount: u256
        ) {
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            let success = btc.transfer(user, amount);
            assert(success, 'BTC transfer failed');
        }

        /// Mint syBTC shares to user
        fn _mint_shares(
            ref self: ContractState, user: ContractAddress, shares: u256
        ) {
            let sy_btc = ISyBtcTokenDispatcher {
                contract_address: self.sy_btc_token.read()
            };
            sy_btc.mint(user, shares);

            let current = self.user_shares.read(user);
            self.user_shares.write(user, current + shares);
            self.total_shares.write(self.total_shares.read() + shares);
        }

        /// Burn syBTC shares from user
        fn _burn_shares(
            ref self: ContractState, user: ContractAddress, shares: u256
        ) {
            let sy_btc = ISyBtcTokenDispatcher {
                contract_address: self.sy_btc_token.read()
            };
            sy_btc.burn(user, shares);

            let current = self.user_shares.read(user);
            assert(current >= shares, 'Insufficient shares');
            self.user_shares.write(user, current - shares);
            self.total_shares.write(self.total_shares.read() - shares);
        }

        /// Allocate BTC to strategy via LeverageManager
        fn _allocate_to_strategy(ref self: ContractState, amount: u256) {
            let lm_address = self.leverage_manager.read();
            let zero_address: ContractAddress = 0.try_into().unwrap();

            if lm_address == zero_address {
                // No LM: BTC stays in vault. get_total_assets() captures it via vault_balance.
                return;
            }

            // Transfer BTC to leverage manager for allocation
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            btc.transfer(lm_address, amount);

            let lm = ILeverageManagerDispatcher { contract_address: lm_address };
            lm.allocate(amount);

            // Sync state
            let (btc_lp, btc_lev, usdc_debt) = lm.get_position_info();
            self.btc_in_lp.write(btc_lp);
            self.btc_leveraged.write(btc_lev);
            self.usdc_borrowed.write(usdc_debt);
        }

        /// Withdraw BTC from strategy via LeverageManager
        fn _withdraw_from_strategy(ref self: ContractState, amount: u256) {
            let lm_address = self.leverage_manager.read();
            let zero_address: ContractAddress = 0.try_into().unwrap();

            if lm_address == zero_address {
                // No LM: BTC stays in vault. _transfer_btc_to_user handles the transfer.
                return;
            }

            let lm = ILeverageManagerDispatcher { contract_address: lm_address };
            lm.deallocate(amount);

            // Sync state
            let (btc_lp, btc_lev, usdc_debt) = lm.get_position_info();
            self.btc_in_lp.write(btc_lp);
            self.btc_leveraged.write(btc_lev);
            self.usdc_borrowed.write(usdc_debt);
        }

        /// Get BTC balance of vault
        fn _get_btc_balance(self: @ContractState) -> u256 {
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            btc.balance_of(get_contract_address())
        }

        /// Get collateral value in USDC terms
        fn _get_collateral_value(self: @ContractState) -> u256 {
            let total_btc = self.btc_in_lp.read() + self.btc_leveraged.read();
            let btc_price = self._get_btc_price();
            Math::mul_fixed(total_btc, btc_price)
        }

        /// Convert USDC amount to BTC equivalent using oracle
        fn _convert_usdc_to_btc(self: @ContractState, usdc_amount: u256) -> u256 {
            if usdc_amount == 0 {
                return 0;
            }

            let btc_price = self._get_btc_price();
            if btc_price == 0 {
                return 0;
            }

            Math::div_fixed(usdc_amount, btc_price)
        }

        /// Get BTC/USD price from Pragma oracle (with fallback)
        fn _get_btc_price(self: @ContractState) -> u256 {
            let pragma_address = self.pragma_adapter.read();
            let zero_address: ContractAddress = 0.try_into().unwrap();

            if pragma_address == zero_address {
                // Fallback: hardcoded price for testing
                return 60000 * Constants::SCALE;
            }

            let pragma = IPragmaAdapterDispatcher { contract_address: pragma_address };
            pragma.get_btc_price()
        }
    }
}
