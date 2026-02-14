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
    
    // View functions
    fn get_total_assets(self: @TContractState) -> u256;
    fn get_share_price(self: @TContractState) -> u256;
    fn get_health_factor(self: @TContractState) -> u256;
    fn get_user_shares(self: @TContractState, user: ContractAddress) -> u256;
    fn get_total_shares(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod VaultManager {
    use super::{
        IVaultManager, ContractAddress, get_caller_address, get_contract_address, Constants, Math,
        ISyBtcTokenDispatcher, ISyBtcTokenDispatcherTrait,
        IERC20Dispatcher, IERC20DispatcherTrait,
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
        target_leverage: u256,     // 2x (scaled 1e18)
        max_leverage: u256,        // 3x max
        min_health_factor: u256,   // 1.2 min
        
        // External contracts
        ekubo_pool: ContractAddress,
        vesu_lending: ContractAddress,
        pragma_oracle: ContractAddress,
        
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

    #[constructor]
    fn constructor(
        ref self: ContractState,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        sy_btc_token: ContractAddress,
        ekubo_pool: ContractAddress,
        vesu_lending: ContractAddress,
        pragma_oracle: ContractAddress,
        owner: ContractAddress,
    ) {
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.sy_btc_token.write(sy_btc_token);
        self.ekubo_pool.write(ekubo_pool);
        self.vesu_lending.write(vesu_lending);
        self.pragma_oracle.write(pragma_oracle);
        self.owner.write(owner);
        self.is_paused.write(false);
        
        // Set default risk parameters
        self.target_leverage.write(Constants::TARGET_LEVERAGE);
        self.max_leverage.write(Constants::MAX_LEVERAGE);
        self.min_health_factor.write(Constants::MIN_HEALTH_FACTOR);
    }

    #[abi(embed_v0)]
    impl VaultManagerImpl of IVaultManager<ContractState> {
        /// Dépose des BTC et reçoit des syBTC
        /// 
        /// # Arguments
        /// * `amount` - Montant de BTC à déposer
        /// 
        /// # Returns
        /// Nombre de shares (syBTC) reçues
        fn deposit(ref self: ContractState, amount: u256) -> u256 {
            assert(!self.is_paused.read(), 'Vault is paused');
            assert(amount > 0, 'Amount must be > 0');
            
            let caller = get_caller_address();
            let shares = self._calculate_shares_for_deposit(amount);
            
            // Transfer BTC from user
            self._transfer_btc_from_user(caller, amount);
            
            // Mint syBTC shares to user
            self._mint_shares(caller, shares);
            
            // Allocate to strategy
            self._allocate_to_strategy(amount);
            
            // Update tracking
            self.total_btc_deposited.write(self.total_btc_deposited.read() + amount);
            
            // Emit event
            self.emit(Deposit { user: caller, amount, shares });
            
            shares
        }

        /// Retire des BTC en brûlant des syBTC
        /// 
        /// # Arguments
        /// * `shares` - Nombre de shares (syBTC) à brûler
        /// 
        /// # Returns
        /// Montant de BTC retiré
        fn withdraw(ref self: ContractState, shares: u256) -> u256 {
            assert(!self.is_paused.read(), 'Vault is paused');
            assert(shares > 0, 'Shares must be > 0');
            
            let caller = get_caller_address();
            let user_shares = self.user_shares.read(caller);
            assert(shares <= user_shares, 'Insufficient shares');
            
            // Calculate BTC amount to withdraw
            let btc_amount = self._calculate_btc_for_shares(shares);
            
            // Withdraw from strategy
            self._withdraw_from_strategy(btc_amount);
            
            // Burn shares
            self._burn_shares(caller, shares);
            
            // Transfer BTC to user
            self._transfer_btc_to_user(caller, btc_amount);
            
            // Update tracking
            self.total_btc_deposited.write(self.total_btc_deposited.read() - btc_amount);
            
            // Emit event
            self.emit(Withdraw { user: caller, shares, amount: btc_amount });
            
            btc_amount
        }

        /// Rééquilibre la position (callable par tous)
        fn rebalance(ref self: ContractState) {
            // This will be implemented when we add leverage_manager
            // For now, just a placeholder
        }

        /// Retrait d'urgence (admin only)
        fn emergency_withdraw(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.is_paused.write(true);
            // Close all positions - will be implemented later
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

        // ═══════════════════════════════════════════════════════
        // VIEW FUNCTIONS
        // ═══════════════════════════════════════════════════════

        fn get_total_assets(self: @ContractState) -> u256 {
            self._get_btc_balance() 
            + self.btc_in_lp.read() 
            + self.btc_leveraged.read() 
            - self._convert_usdc_to_btc(self.usdc_borrowed.read())
        }

        fn get_share_price(self: @ContractState) -> u256 {
            let total = self.total_shares.read();
            if total == 0 {
                return Constants::SCALE; // 1e18 = 1.0
            }
            Math::div_fixed(self.get_total_assets(), total)
        }

        fn get_health_factor(self: @ContractState) -> u256 {
            let collateral = self._get_collateral_value();
            let debt = self.usdc_borrowed.read();
            if debt == 0 {
                return 999 * Constants::SCALE; // Very high HF when no debt
            }
            let liquidation_threshold = Constants::LIQUIDATION_THRESHOLD;
            let debt_with_threshold = Math::mul_fixed(debt, liquidation_threshold);
            Math::div_fixed(collateral, debt_with_threshold)
        }

        fn get_user_shares(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_shares.read(user)
        }

        fn get_total_shares(self: @ContractState) -> u256 {
            self.total_shares.read()
        }
    }

    // ═══════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Calculate shares to mint for a deposit
        fn _calculate_shares_for_deposit(
            self: @ContractState, amount: u256
        ) -> u256 {
            let total_shares = self.total_shares.read();
            let total_assets = self.get_total_assets();
            
            if total_shares == 0 {
                // First deposit: 1 share = 1 BTC
                return amount;
            }
            
            // shares = (amount * total_shares) / total_assets
            Math::mul_fixed(amount, total_shares) / total_assets
        }

        /// Calculate BTC amount for shares
        fn _calculate_btc_for_shares(
            self: @ContractState, shares: u256
        ) -> u256 {
            let total_shares = self.total_shares.read();
            assert(total_shares > 0, 'No shares exist');
            
            let total_assets = self.get_total_assets();
            // btc = (shares * total_assets) / total_shares
            Math::mul_fixed(shares, total_assets) / total_shares
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
            
            // Update user shares
            let current = self.user_shares.read(user);
            self.user_shares.write(user, current + shares);
            
            // Update total shares
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
            
            // Update user shares
            let current = self.user_shares.read(user);
            assert(current >= shares, 'Insufficient shares');
            self.user_shares.write(user, current - shares);
            
            // Update total shares
            self.total_shares.write(self.total_shares.read() - shares);
        }

        /// Allocate BTC to strategy (50% LP, 50% leverage)
        fn _allocate_to_strategy(
            ref self: ContractState, amount: u256
        ) {
            // For now, just track - will be implemented with integrations
            // 50% to LP
            let lp_amount = amount / 2;
            self.btc_in_lp.write(self.btc_in_lp.read() + lp_amount);
            
            // 50% to leverage (will be implemented later)
            let leverage_amount = amount - lp_amount;
            self.btc_leveraged.write(self.btc_leveraged.read() + leverage_amount);
        }

        /// Withdraw BTC from strategy
        fn _withdraw_from_strategy(
            ref self: ContractState, amount: u256
        ) {
            // For now, just track - will be implemented with integrations
            // Proportional withdrawal from LP and leverage
            let total_in_strategy = self.btc_in_lp.read() + self.btc_leveraged.read();
            if total_in_strategy == 0 {
                return;
            }
            
            let lp_ratio = Math::div_fixed(self.btc_in_lp.read(), total_in_strategy);
            let lp_withdraw = Math::mul_fixed(amount, lp_ratio);
            let leverage_withdraw = amount - lp_withdraw;
            
            self.btc_in_lp.write(self.btc_in_lp.read() - lp_withdraw);
            self.btc_leveraged.write(self.btc_leveraged.read() - leverage_withdraw);
        }

        /// Get BTC balance of vault
        fn _get_btc_balance(self: @ContractState) -> u256 {
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            btc.balance_of(get_contract_address())
        }

        /// Get collateral value in BTC terms
        fn _get_collateral_value(self: @ContractState) -> u256 {
            self.btc_in_lp.read() + self.btc_leveraged.read()
        }

        /// Convert USDC amount to BTC equivalent
        fn _convert_usdc_to_btc(self: @ContractState, usdc_amount: u256) -> u256 {
            // This will use oracle to get BTC price
            // For now, placeholder - assumes 1 USDC = 1/60000 BTC (placeholder)
            if usdc_amount == 0 {
                return 0;
            }
            // Placeholder: will use oracle later
            usdc_amount / 60000
        }
    }
}
