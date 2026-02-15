use starknet::ContractAddress;
use starkyield::utils::constants::Constants;
use starkyield::utils::math::Math;

/// Leverage Manager - Strategy execution engine
///
/// Manages the 50/50 split between Ekubo LP and Vesu leverage positions.
/// Handles allocation, deallocation, and leverage adjustments.

#[starknet::interface]
pub trait ILeverageManager<TContractState> {
    /// Allocate BTC to strategy (50% LP, 50% leverage)
    fn allocate(ref self: TContractState, btc_amount: u256);
    /// Deallocate BTC from strategy proportionally
    fn deallocate(ref self: TContractState, btc_amount: u256);
    /// Increase leverage towards target
    fn increase_leverage(ref self: TContractState, additional_borrow: u256);
    /// Reduce leverage towards target
    fn reduce_leverage(ref self: TContractState, repay_amount: u256);
    /// Close all positions (emergency)
    fn close_all_positions(ref self: TContractState);
    /// Get current leverage ratio
    fn get_current_leverage(self: @TContractState) -> u256;
    /// Get position breakdown
    fn get_position_info(self: @TContractState) -> (u256, u256, u256);
}

#[starknet::contract]
pub mod LeverageManager {
    use super::{ContractAddress, ILeverageManager, Constants, Math};
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starkyield::integrations::ekubo::{IEkuboAdapterDispatcher, IEkuboAdapterDispatcherTrait};
    use starkyield::integrations::vesu::{IVesuAdapterDispatcher, IVesuAdapterDispatcherTrait};
    use starkyield::integrations::pragma_oracle::{
        IPragmaAdapterDispatcher, IPragmaAdapterDispatcherTrait,
    };

    #[storage]
    struct Storage {
        // External adapters
        ekubo_adapter: ContractAddress,
        vesu_adapter: ContractAddress,
        pragma_adapter: ContractAddress,
        // Tokens
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        // Position tracking
        btc_in_lp: u256,
        btc_leveraged: u256,
        usdc_borrowed: u256,
        lp_token_id: u64,
        // Entry price for IL calculations
        entry_price: u256,
        // Admin
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Allocated: Allocated,
        Deallocated: Deallocated,
        LeverageAdjusted: LeverageAdjusted,
        PositionsClosed: PositionsClosed,
    }

    #[derive(Drop, starknet::Event)]
    struct Allocated {
        btc_to_lp: u256,
        btc_to_leverage: u256,
        usdc_borrowed: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Deallocated {
        btc_from_lp: u256,
        btc_from_leverage: u256,
        usdc_repaid: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LeverageAdjusted {
        old_leverage: u256,
        new_leverage: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PositionsClosed {
        total_btc_recovered: u256,
        total_usdc_repaid: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        ekubo_adapter: ContractAddress,
        vesu_adapter: ContractAddress,
        pragma_adapter: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        owner: ContractAddress,
    ) {
        self.ekubo_adapter.write(ekubo_adapter);
        self.vesu_adapter.write(vesu_adapter);
        self.pragma_adapter.write(pragma_adapter);
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl LeverageManagerImpl of ILeverageManager<ContractState> {
        /// Allocate BTC to the dual strategy:
        /// - 50% → Ekubo LP (BTC/USDC pool)
        /// - 50% → Vesu leverage (deposit BTC, borrow USDC, buy more BTC)
        fn allocate(ref self: ContractState, btc_amount: u256) {
            assert(btc_amount > 0, 'Amount must be > 0');

            let btc_price = self._get_btc_price();

            // Record entry price on first allocation
            if self.entry_price.read() == 0 {
                self.entry_price.write(btc_price);
            }

            // Split 50/50
            let lp_amount = btc_amount / 2;
            let leverage_amount = btc_amount - lp_amount;

            // --- LP Allocation (Ekubo) ---
            // Convert half of LP BTC to USDC for paired liquidity
            let btc_for_usdc = lp_amount / 2;
            let btc_for_lp = lp_amount - btc_for_usdc;

            let ekubo = IEkuboAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };

            // Transfer BTC to ekubo adapter for swap
            self._transfer_btc_to(self.ekubo_adapter.read(), btc_for_usdc);
            let usdc_from_swap = ekubo.swap_btc_to_usdc(btc_for_usdc, 0);

            // Add liquidity with remaining BTC + swapped USDC
            self._transfer_btc_to(self.ekubo_adapter.read(), btc_for_lp);
            let token_id = ekubo.add_liquidity(btc_for_lp, usdc_from_swap);
            self.lp_token_id.write(token_id);

            // --- Leverage Allocation (Vesu) ---
            let vesu = IVesuAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };

            // Deposit BTC as collateral
            self._transfer_btc_to(self.vesu_adapter.read(), leverage_amount);
            vesu.deposit_collateral(leverage_amount);

            // Borrow USDC at 50% LTV
            let collateral_value_usdc = Math::mul_fixed(leverage_amount, btc_price);
            let borrow_amount = collateral_value_usdc / 2; // 50% LTV
            vesu.borrow_usdc(borrow_amount);

            // Swap borrowed USDC to BTC for additional exposure
            // Transfer USDC from vesu adapter to ekubo adapter
            let additional_btc = ekubo.swap_usdc_to_btc(borrow_amount, 0);

            // Update tracking
            self.btc_in_lp.write(self.btc_in_lp.read() + lp_amount);
            self.btc_leveraged.write(self.btc_leveraged.read() + leverage_amount + additional_btc);
            self.usdc_borrowed.write(self.usdc_borrowed.read() + borrow_amount);

            self.emit(Allocated {
                btc_to_lp: lp_amount,
                btc_to_leverage: leverage_amount + additional_btc,
                usdc_borrowed: borrow_amount,
            });
        }

        /// Deallocate BTC from strategy proportionally
        /// Repays debt before withdrawing collateral
        fn deallocate(ref self: ContractState, btc_amount: u256) {
            assert(btc_amount > 0, 'Amount must be > 0');

            let total_in_strategy = self.btc_in_lp.read() + self.btc_leveraged.read();
            assert(total_in_strategy > 0, 'No funds in strategy');

            // Calculate proportional amounts
            let lp_ratio = Math::div_fixed(self.btc_in_lp.read(), total_in_strategy);
            let lp_withdraw = Math::mul_fixed(btc_amount, lp_ratio);
            let leverage_withdraw = btc_amount - lp_withdraw;

            let ekubo = IEkuboAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };
            let vesu = IVesuAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };

            // --- Withdraw from LP ---
            let token_id = self.lp_token_id.read();
            if token_id != 0 && lp_withdraw > 0 {
                let (_btc_received, _usdc_received) = ekubo.remove_liquidity(token_id);
                // Swap USDC back to BTC if needed
            }

            // --- Withdraw from Leverage ---
            if leverage_withdraw > 0 {
                // First repay proportional debt
                let debt = self.usdc_borrowed.read();
                if debt > 0 {
                    let debt_ratio = Math::div_fixed(
                        leverage_withdraw, self.btc_leveraged.read()
                    );
                    let repay_amount = Math::mul_fixed(debt, debt_ratio);

                    // Sell some BTC to get USDC for repayment
                    self._transfer_btc_to(self.ekubo_adapter.read(), leverage_withdraw);
                    let usdc_received = ekubo.swap_btc_to_usdc(leverage_withdraw, 0);
                    let actual_repay = Math::min(repay_amount, usdc_received);

                    vesu.repay_usdc(actual_repay);
                    self.usdc_borrowed.write(debt - actual_repay);
                }

                // Withdraw collateral
                vesu.withdraw_collateral(leverage_withdraw);
            }

            // Update tracking
            self.btc_in_lp.write(self.btc_in_lp.read() - lp_withdraw);
            self.btc_leveraged.write(self.btc_leveraged.read() - leverage_withdraw);

            self.emit(Deallocated {
                btc_from_lp: lp_withdraw,
                btc_from_leverage: leverage_withdraw,
                usdc_repaid: 0,
            });
        }

        /// Increase leverage by borrowing more USDC and buying BTC
        fn increase_leverage(ref self: ContractState, additional_borrow: u256) {
            assert(additional_borrow > 0, 'Amount must be > 0');

            let old_leverage = self.get_current_leverage();

            let vesu = IVesuAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };
            let ekubo = IEkuboAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };

            // Borrow more USDC
            vesu.borrow_usdc(additional_borrow);

            // Swap to BTC
            let additional_btc = ekubo.swap_usdc_to_btc(additional_borrow, 0);

            // Deposit additional BTC as collateral
            self._transfer_btc_to(self.vesu_adapter.read(), additional_btc);
            vesu.deposit_collateral(additional_btc);

            // Update tracking
            self.usdc_borrowed.write(self.usdc_borrowed.read() + additional_borrow);
            self.btc_leveraged.write(self.btc_leveraged.read() + additional_btc);

            let new_leverage = self.get_current_leverage();
            self.emit(LeverageAdjusted { old_leverage, new_leverage });
        }

        /// Reduce leverage by selling BTC and repaying USDC
        fn reduce_leverage(ref self: ContractState, repay_amount: u256) {
            assert(repay_amount > 0, 'Amount must be > 0');

            let old_leverage = self.get_current_leverage();

            let vesu = IVesuAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };
            let ekubo = IEkuboAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };

            // Calculate BTC to sell for repayment
            let btc_price = self._get_btc_price();
            let btc_to_sell = Math::div_fixed(repay_amount, btc_price);

            // Withdraw BTC from Vesu collateral
            vesu.withdraw_collateral(btc_to_sell);

            // Swap BTC to USDC
            self._transfer_btc_to(self.ekubo_adapter.read(), btc_to_sell);
            let usdc_received = ekubo.swap_btc_to_usdc(btc_to_sell, 0);

            // Repay debt
            let actual_repay = Math::min(repay_amount, usdc_received);
            vesu.repay_usdc(actual_repay);

            // Update tracking
            self.usdc_borrowed.write(self.usdc_borrowed.read() - actual_repay);
            self.btc_leveraged.write(self.btc_leveraged.read() - btc_to_sell);

            let new_leverage = self.get_current_leverage();
            self.emit(LeverageAdjusted { old_leverage, new_leverage });
        }

        /// Emergency: close all positions
        fn close_all_positions(ref self: ContractState) {
            let ekubo = IEkuboAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };
            let vesu = IVesuAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };

            let mut total_btc_recovered: u256 = 0;
            let total_usdc_repaid = self.usdc_borrowed.read();

            // 1. Remove all LP
            let token_id = self.lp_token_id.read();
            if token_id != 0 {
                let (btc_from_lp, usdc_from_lp) = ekubo.remove_liquidity(token_id);
                total_btc_recovered += btc_from_lp;
                // Use USDC from LP to repay debt if needed
                if total_usdc_repaid > 0 && usdc_from_lp > 0 {
                    let repay = Math::min(total_usdc_repaid, usdc_from_lp);
                    vesu.repay_usdc(repay);
                }
                self.lp_token_id.write(0);
            }

            // 2. Repay remaining debt
            let remaining_debt = self.usdc_borrowed.read();
            if remaining_debt > 0 {
                // Sell some leveraged BTC to cover remaining debt
                let btc_leveraged = self.btc_leveraged.read();
                if btc_leveraged > 0 {
                    vesu.withdraw_collateral(btc_leveraged);
                    self._transfer_btc_to(self.ekubo_adapter.read(), btc_leveraged);
                    let usdc_from_sale = ekubo.swap_btc_to_usdc(btc_leveraged, 0);
                    let repay = Math::min(remaining_debt, usdc_from_sale);
                    vesu.repay_usdc(repay);

                    // Swap remaining USDC back to BTC
                    if usdc_from_sale > repay {
                        let excess_btc = ekubo.swap_usdc_to_btc(usdc_from_sale - repay, 0);
                        total_btc_recovered += excess_btc;
                    }
                }
            }

            // 3. Withdraw remaining collateral
            let remaining_collateral = vesu.get_collateral_balance();
            if remaining_collateral > 0 {
                vesu.withdraw_collateral(remaining_collateral);
                total_btc_recovered += remaining_collateral;
            }

            // Reset all tracking
            self.btc_in_lp.write(0);
            self.btc_leveraged.write(0);
            self.usdc_borrowed.write(0);
            self.entry_price.write(0);

            self.emit(PositionsClosed {
                total_btc_recovered,
                total_usdc_repaid,
            });
        }

        /// Calculate current leverage ratio
        /// Leverage = total_exposure / equity
        /// where equity = total_exposure - debt_in_btc
        fn get_current_leverage(self: @ContractState) -> u256 {
            let total_exposure = self.btc_in_lp.read() + self.btc_leveraged.read();
            if total_exposure == 0 {
                return Constants::SCALE; // 1x when no position
            }

            let debt = self.usdc_borrowed.read();
            if debt == 0 {
                return Constants::SCALE; // 1x when no debt
            }

            let btc_price = self._get_btc_price();
            let debt_in_btc = Math::div_fixed(debt, btc_price);

            let equity = if total_exposure > debt_in_btc {
                total_exposure - debt_in_btc
            } else {
                1 // Avoid division by zero — underwater position
            };

            Math::div_fixed(total_exposure, equity)
        }

        /// Get position breakdown: (btc_in_lp, btc_leveraged, usdc_borrowed)
        fn get_position_info(self: @ContractState) -> (u256, u256, u256) {
            (self.btc_in_lp.read(), self.btc_leveraged.read(), self.usdc_borrowed.read())
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _get_btc_price(self: @ContractState) -> u256 {
            let pragma = IPragmaAdapterDispatcher {
                contract_address: self.pragma_adapter.read(),
            };
            pragma.get_btc_price()
        }

        fn _transfer_btc_to(ref self: ContractState, to: ContractAddress, amount: u256) {
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            btc.transfer(to, amount);
        }
    }
}
