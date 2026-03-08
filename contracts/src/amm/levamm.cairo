//! LEVAMM — Constant Leverage AMM (2× IL-free) — StarkYield semantics
//!
//! In StarkYield: x = LP token quantity (not raw BTC), d = USDC debt, C = LP value in USDC.
//! The bonding curve math is unchanged; only the collateral asset interpretation differs.
//! LP tokens from the Ekubo BTC/USDC pool serve as collateral in the CDP, making
//! impermanent loss a non-event (the LP position is always hedged by the debt).
//!
//! Mathematical foundation (invariant in LP-token space):
//!   LEV_RATIO = (L/(L+1))^2 = (2/3)^2 = 4/9  (for L=2)
//!   x0 = (C + sqrt(C^2 - 4·C·LEV_RATIO·D)) / (2·LEV_RATIO)
//!   Invariant I(p0) = (x0(p0) - d_lp) · y  where d_lp = D / lp_price
//!
//! Safety bands: DTV (Debt-To-Value) must stay in [6.25%, 53.125%] for 2× leverage.
//!
//! Active rebalancing (StarkYield-compliant):
//!   After each swap, _rebalance_cdp() restores DTV to ~50% using:
//!   - VirtualPool flash loans for USDC liquidity
//!   - MockEkubo for LP addition/removal
//!   - MockLending for CDP debt adjustment

use starknet::ContractAddress;

/// Minimal FeeDistributor facade for cross-contract calls
#[starknet::interface]
trait IFeeDistributorFacade<TContractState> {
    fn distribute(ref self: TContractState, fee_amount: u256);
    fn record_interest(ref self: TContractState, interest_amount: u256);
}

/// VirtualPool facade — flash loans for rebalancing
#[starknet::interface]
trait IVirtualPoolRebalance<TContractState> {
    fn flash_loan(ref self: TContractState, amount: u256);
    fn repay_flash_loan(ref self: TContractState, amount: u256);
}

/// Ekubo facade — LP operations for rebalancing
#[starknet::interface]
trait IEkuboRebalance<TContractState> {
    fn add_liquidity(ref self: TContractState, btc_amount: u256, usdc_amount: u256) -> u64;
    fn remove_liquidity(ref self: TContractState, token_id: u64) -> (u256, u256);
}

/// Lending facade — CDP debt management for rebalancing
#[starknet::interface]
trait ILendingRebalance<TContractState> {
    fn borrow_usdc(ref self: TContractState, usdc_amount: u256);
    fn repay_usdc(ref self: TContractState, usdc_amount: u256);
}

/// Minimal ERC-20 facade for approve calls during rebalancing
#[starknet::interface]
trait IERC20Approve<TContractState> {
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait ILevAMM<TContractState> {
    // ── View functions ──────────────────────────────────────────────────────
    /// Returns the anchor value x0 based on current collateral and debt
    fn get_x0(self: @TContractState) -> u256;
    /// Returns current Debt-To-Value ratio (1e18-scaled, e.g. 0.5e18 = 50%)
    fn get_dtv(self: @TContractState) -> u256;
    /// Returns true if DTV > DTV_MAX_2X (system is over-levered)
    fn is_over_levered(self: @TContractState) -> bool;
    /// Returns true if DTV < DTV_MIN_2X (system is under-levered)
    fn is_under_levered(self: @TContractState) -> bool;
    /// Returns the USDC cost to buy `btc_amount` BTC via the bonding curve
    fn get_price(self: @TContractState, btc_amount: u256) -> u256;
    /// Returns current collateral value (USDC 1e18)
    fn get_collateral_value(self: @TContractState) -> u256;
    /// Returns current debt (USDC 1e18)
    fn get_debt(self: @TContractState) -> u256;
    /// Returns the stored invariant I(p0)
    fn get_invariant(self: @TContractState) -> u256;
    /// Returns entry price (BTC/USD 1e18)
    fn get_entry_price(self: @TContractState) -> u256;
    /// Returns current BTC price from oracle
    fn get_current_btc_price(self: @TContractState) -> u256;
    /// Returns whether the LEVAMM is initialized
    fn is_active(self: @TContractState) -> bool;
    /// Returns accrued interest since last settlement
    fn get_accrued_interest(self: @TContractState) -> u256;
    /// Returns the LP token ID from the last rebalancing operation
    fn get_rebalance_lp_id(self: @TContractState) -> u64;

    // ── Mutating functions ──────────────────────────────────────────────────
    /// Initialize the LEVAMM with starting collateral value, debt, and oracle price
    fn initialize(
        ref self: TContractState,
        collateral_value: u256,
        debt: u256,
        entry_price: u256,
    );
    /// Execute a bonding-curve swap. direction=true → buy BTC (USDC in), false → sell BTC (USDC out)
    fn swap(ref self: TContractState, direction: bool, btc_amount: u256) -> u256;
    /// Accrue interest on the debt (block-based rate)
    fn accrue_interest(ref self: TContractState);
    /// Donate USDC to deepen pool liquidity (refueling mechanism)
    fn refuel(ref self: TContractState, usdc_amount: u256);

    // ── Fee management (StarkYield) ─────────────────────────────────────
    /// Returns accumulated trading fees not yet distributed
    fn get_accumulated_trading_fees(self: @TContractState) -> u256;
    /// Returns total trading fees generated since initialization (never resets)
    fn get_total_fees_generated(self: @TContractState) -> u256;
    /// Returns the block number at which the LEVAMM was initialized
    fn get_init_block(self: @TContractState) -> u64;
    /// Collect accumulated trading fees and route to FeeDistributor
    fn collect_fees(ref self: TContractState) -> u256;

    // ── Admin ──────────────────────────────────────────────────────────────
    fn set_interest_rate(ref self: TContractState, rate: u256);
    fn set_pragma_adapter(ref self: TContractState, adapter: ContractAddress);
    fn set_fee_distributor(ref self: TContractState, fee_distributor: ContractAddress);
    fn set_virtual_pool(ref self: TContractState, addr: ContractAddress);
    fn set_ekubo_adapter(ref self: TContractState, addr: ContractAddress);
    fn set_lending_adapter(ref self: TContractState, addr: ContractAddress);
    fn set_owner(ref self: TContractState, new_owner: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod LevAMM {
    use super::{
        ILevAMM, ContractAddress,
        IFeeDistributorFacadeDispatcher, IFeeDistributorFacadeDispatcherTrait,
        IVirtualPoolRebalanceDispatcher, IVirtualPoolRebalanceDispatcherTrait,
        IEkuboRebalanceDispatcher, IEkuboRebalanceDispatcherTrait,
        ILendingRebalanceDispatcher, ILendingRebalanceDispatcherTrait,
        IERC20ApproveDispatcher, IERC20ApproveDispatcherTrait,
    };
    use starknet::{get_caller_address, get_block_number};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkyield::utils::constants::Constants;
    use starkyield::utils::math::Math;
    use starkyield::integrations::pragma_oracle::{IPragmaAdapterDispatcher, IPragmaAdapterDispatcherTrait};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pragma_adapter: ContractAddress,
        // Position state (all 1e18-scaled)
        collateral_value: u256,   // C: USDC value of LP tokens held as CDP collateral
        debt: u256,               // D: USDC borrowed (outstanding)
        invariant: u256,          // I(p0): (x0 - d_btc) * y at initialization
        entry_price: u256,        // p0: BTC/USD price at initialization
        // Interest accrual
        accrued_interest: u256,
        last_interest_block: u64,
        interest_rate: u256,      // per-block rate (1e18-scaled)
        // Fee management (StarkYield / time-normalized)
        fee_distributor: ContractAddress,
        accumulated_trading_fees: u256,   // resets on collect_fees()
        total_fees_generated: u256,       // all-time counter (never resets) — used for APR
        init_block: u64,                  // block at initialization — used for time-normalized APR
        // Rebalancing integrations (StarkYield-compliant)
        virtual_pool: ContractAddress,
        ekubo_adapter: ContractAddress,
        lending_adapter: ContractAddress,
        rebalance_lp_id: u64,     // LP token ID from last rebalance add_liquidity
        // State flag
        is_active: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Initialized: Initialized,
        Swapped: Swapped,
        InterestAccrued: InterestAccrued,
        Refueled: Refueled,
        InterestRateSet: InterestRateSet,
        FeeCollected: FeeCollected,
        Rebalanced: Rebalanced,
    }

    #[derive(Drop, starknet::Event)]
    struct Initialized {
        collateral_value: u256,
        debt: u256,
        invariant: u256,
        entry_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Swapped {
        direction: bool,
        btc_amount: u256,
        usdc_amount: u256,
        new_dtv: u256,
        fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct FeeCollected { total_fees: u256, pool_recycled: u256, distributed: u256 }

    #[derive(Drop, starknet::Event)]
    struct InterestAccrued { interest: u256, new_debt: u256 }

    #[derive(Drop, starknet::Event)]
    struct Refueled { usdc_amount: u256, new_collateral: u256 }

    #[derive(Drop, starknet::Event)]
    struct InterestRateSet { new_rate: u256 }

    /// Emitted when active CDP rebalancing adjusts debt and collateral.
    /// direction=true → leverage up (added debt + LP), false → deleverage
    #[derive(Drop, starknet::Event)]
    struct Rebalanced {
        direction: bool,
        adjustment_scaled: u256,
        adjustment_raw: u256,
        new_dtv: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pragma_adapter: ContractAddress,
    ) {
        self.owner.write(owner);
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.pragma_adapter.write(pragma_adapter);
        self.is_active.write(false);
        self.accrued_interest.write(0);
        self.interest_rate.write(0);
        self.accumulated_trading_fees.write(0);
        self.total_fees_generated.write(0);
        self.init_block.write(0);
        self.rebalance_lp_id.write(0);
    }

    #[abi(embed_v0)]
    impl LevAMMImpl of ILevAMM<ContractState> {
        // ── View ──────────────────────────────────────────────────────────

        fn get_x0(self: @ContractState) -> u256 {
            self._calculate_x0(self.collateral_value.read(), self.debt.read())
        }

        fn get_dtv(self: @ContractState) -> u256 {
            let c = self.collateral_value.read();
            if c == 0 { return 0; }
            Math::div_fixed(self.debt.read(), c)
        }

        fn is_over_levered(self: @ContractState) -> bool {
            self.get_dtv() > Constants::DTV_MAX_2X
        }

        fn is_under_levered(self: @ContractState) -> bool {
            let dtv = self.get_dtv();
            dtv > 0 && dtv < Constants::DTV_MIN_2X
        }

        fn get_price(self: @ContractState, btc_amount: u256) -> u256 {
            assert(self.is_active.read(), 'LEVAMM not initialized');
            assert(btc_amount > 0, 'Amount must be > 0');

            let c = self.collateral_value.read();
            let d = self.debt.read();
            let p = self._get_btc_price();
            let inv = self.invariant.read();

            let x0 = self._calculate_x0(c, d);
            // d_btc = D / p  (debt in BTC units)
            let d_btc = Math::div_fixed(d, p);

            assert(x0 > d_btc + btc_amount, 'Insufficient liquidity');

            let new_x_minus_d = x0 - d_btc - btc_amount;
            // new_y = inv / new_x_minus_d
            let new_y = Math::div_fixed(inv, new_x_minus_d);
            // cost in USDC = new_y - current_y  (buying BTC makes y grow)
            if new_y > c { new_y - c } else { 0 }
        }

        fn get_collateral_value(self: @ContractState) -> u256 { self.collateral_value.read() }
        fn get_debt(self: @ContractState) -> u256 { self.debt.read() }
        fn get_invariant(self: @ContractState) -> u256 { self.invariant.read() }
        fn get_entry_price(self: @ContractState) -> u256 { self.entry_price.read() }
        fn is_active(self: @ContractState) -> bool { self.is_active.read() }
        fn get_accrued_interest(self: @ContractState) -> u256 { self.accrued_interest.read() }
        fn get_rebalance_lp_id(self: @ContractState) -> u64 { self.rebalance_lp_id.read() }

        fn get_current_btc_price(self: @ContractState) -> u256 {
            self._get_btc_price()
        }

        // ── Mutating ──────────────────────────────────────────────────────

        fn initialize(
            ref self: ContractState,
            collateral_value: u256,
            debt: u256,
            entry_price: u256,
        ) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            assert(!self.is_active.read(), 'Already initialized');
            assert(collateral_value > 0 && entry_price > 0, 'Invalid init params');
            assert(debt < collateral_value, 'Debt exceeds collateral');

            self.collateral_value.write(collateral_value);
            self.debt.write(debt);
            self.entry_price.write(entry_price);

            // Compute invariant: I = (x0 - d_btc) * y
            let x0 = self._calculate_x0(collateral_value, debt);
            let d_btc = Math::div_fixed(debt, entry_price);
            assert(x0 > d_btc, 'x0 must exceed d_btc');
            let x_minus_d = x0 - d_btc;
            let inv = Math::mul_fixed(x_minus_d, collateral_value);

            self.invariant.write(inv);
            self.is_active.write(true);
            let current_block = get_block_number();
            self.last_interest_block.write(current_block);
            self.init_block.write(current_block);

            self.emit(Initialized { collateral_value, debt, invariant: inv, entry_price });
        }

        fn swap(ref self: ContractState, direction: bool, btc_amount: u256) -> u256 {
            assert(self.is_active.read(), 'LEVAMM not initialized');
            assert(btc_amount > 0, 'Amount must be > 0');

            let dtv = self.get_dtv();

            if direction {
                // Buying BTC (USDC in): only valid when under-levered (DTV < target)
                assert(dtv <= Constants::DTV_MAX_2X, 'Cannot buy: over-levered');
            } else {
                // Selling BTC (USDC out): only valid when over-levered (DTV > target)
                assert(dtv >= Constants::DTV_MIN_2X, 'Cannot sell: under-levered');
            }

            let base_usdc = self.get_price(btc_amount);
            assert(base_usdc > 0, 'Zero output');

            // StarkYield trading fee (0.3%)
            let fee = Math::mul_fixed(base_usdc, Constants::SWAP_FEE);

            // Update collateral (bonding curve amount only — fee is separate)
            let c = self.collateral_value.read();
            if direction {
                // Buy BTC: collateral increases by bonding curve amount
                self.collateral_value.write(c + base_usdc);
            } else {
                // Sell BTC: collateral decreases by bonding curve amount
                let new_c = if c > base_usdc { c - base_usdc } else { 0 };
                self.collateral_value.write(new_c);
            }

            // Accumulate trading fees for batch distribution
            if fee > 0 {
                self.accumulated_trading_fees.write(
                    self.accumulated_trading_fees.read() + fee
                );
                // time-normalized: all-time counter for time-normalized APR (never resets)
                self.total_fees_generated.write(
                    self.total_fees_generated.read() + fee
                );
            }

            // User-facing amount includes fee
            let usdc_amount = if direction {
                base_usdc + fee  // buyer pays bonding curve price + fee
            } else {
                if base_usdc > fee { base_usdc - fee } else { 0 }  // seller receives less
            };

            let new_dtv = self.get_dtv();
            self.emit(Swapped { direction, btc_amount, usdc_amount, new_dtv, fee });

            // ── Active CDP rebalancing (StarkYield-compliant) ──
            // After the swap changes accounting, restore DTV to ~50% using
            // flash loans + LP + CDP operations.
            self._rebalance_cdp();

            usdc_amount
        }

        fn accrue_interest(ref self: ContractState) {
            let current_block = get_block_number();
            let last_block = self.last_interest_block.read();
            if current_block <= last_block { return; }

            let blocks: u256 = (current_block - last_block).into();
            let rate = self.interest_rate.read();
            if rate == 0 {
                self.last_interest_block.write(current_block);
                return;
            }

            let debt = self.debt.read();
            // interest = debt * rate * blocks / SCALE
            let interest = Math::mul_fixed(Math::mul_fixed(debt, rate), blocks);
            let new_debt = debt + interest;
            self.debt.write(new_debt);
            self.accrued_interest.write(self.accrued_interest.read() + interest);
            self.last_interest_block.write(current_block);

            // StarkYield: 100% of CDP interest recycled into pool collateral
            let recycled = Math::mul_fixed(interest, Constants::INTEREST_RECYCLE_RATE);
            if recycled > 0 {
                self.collateral_value.write(self.collateral_value.read() + recycled);
            }

            // Notify FeeDistributor for accounting
            let fd_addr = self.fee_distributor.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if fd_addr != zero && interest > 0 {
                IFeeDistributorFacadeDispatcher { contract_address: fd_addr }
                    .record_interest(interest);
            }

            self.emit(InterestAccrued { interest, new_debt });
        }

        fn refuel(ref self: ContractState, usdc_amount: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            assert(usdc_amount > 0, 'Amount must be > 0');
            let new_c = self.collateral_value.read() + usdc_amount;
            self.collateral_value.write(new_c);
            self.emit(Refueled { usdc_amount, new_collateral: new_c });
        }

        fn set_interest_rate(ref self: ContractState, rate: u256) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            // Accrue before changing rate
            self.accrue_interest();
            self.interest_rate.write(rate);
            self.emit(InterestRateSet { new_rate: rate });
        }

        // ── Fee management (StarkYield) ─────────────────────────────────

        fn get_accumulated_trading_fees(self: @ContractState) -> u256 {
            self.accumulated_trading_fees.read()
        }

        fn get_total_fees_generated(self: @ContractState) -> u256 {
            self.total_fees_generated.read()
        }

        fn get_init_block(self: @ContractState) -> u64 {
            self.init_block.read()
        }

        /// Collect accumulated trading fees: 50% auto-recycled into pool,
        /// 50% routed to FeeDistributor for holder/veSY distribution.
        /// Permissionless — anyone can trigger fee distribution.
        fn collect_fees(ref self: ContractState) -> u256 {
            let fees = self.accumulated_trading_fees.read();
            if fees == 0 { return 0; }

            self.accumulated_trading_fees.write(0);

            // StarkYield: 50% donated back to pool (deepens liquidity)
            let pool_recycled = Math::mul_fixed(fees, Constants::FEE_POOL_SHARE);
            self.collateral_value.write(self.collateral_value.read() + pool_recycled);

            // 50% to FeeDistributor for holder/veSY split
            let dist_share = fees - pool_recycled;
            let fd_addr = self.fee_distributor.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if fd_addr != zero && dist_share > 0 {
                IFeeDistributorFacadeDispatcher { contract_address: fd_addr }
                    .distribute(dist_share);
            }

            self.emit(FeeCollected { total_fees: fees, pool_recycled, distributed: dist_share });
            fees
        }

        // ── Admin ────────────────────────────────────────────────────────

        fn set_pragma_adapter(ref self: ContractState, adapter: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.pragma_adapter.write(adapter);
        }

        fn set_fee_distributor(ref self: ContractState, fee_distributor: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.fee_distributor.write(fee_distributor);
        }

        fn set_virtual_pool(ref self: ContractState, addr: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.virtual_pool.write(addr);
        }

        fn set_ekubo_adapter(ref self: ContractState, addr: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.ekubo_adapter.write(addr);
        }

        fn set_lending_adapter(ref self: ContractState, addr: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.lending_adapter.write(addr);
        }

        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.owner.write(new_owner);
        }

        fn get_owner(self: @ContractState) -> ContractAddress { self.owner.read() }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Compute x0 given collateral C and debt D (both 1e18-scaled USDC values)
        ///
        /// Formula: x0 = (C + sqrt(C^2 - 4·C·LEV_RATIO·D)) / (2·LEV_RATIO)
        fn _calculate_x0(self: @ContractState, c: u256, d: u256) -> u256 {
            if c == 0 { return 0; }
            if d == 0 { return c; }  // no debt → x0 = C

            let lev = Constants::LEV_RATIO_2X;   // 4/9 * 1e18

            // c_squared = C^2 / SCALE  (1e18-scaled)
            let c_squared = Math::mul_fixed(c, c);

            // four_c_lev_d = 4 * C * LEV_RATIO * D / SCALE^2
            let c_lev = Math::mul_fixed(c, lev);
            let c_lev_d = Math::mul_fixed(c_lev, d);
            let four_c_lev_d = 4_u256 * c_lev_d;

            // Guard: discriminant must be non-negative (valid leverage regime)
            if four_c_lev_d >= c_squared {
                return Math::div_fixed(c, 2_u256 * lev);
            }

            let discriminant = c_squared - four_c_lev_d;

            // sqrt of a 1e18-scaled value: multiply by SCALE first, then sqrt
            let sqrt_disc = Math::sqrt(discriminant * Constants::SCALE);

            let numerator = c + sqrt_disc;
            let denominator = 2_u256 * lev;

            Math::div_fixed(numerator, denominator)
        }

        /// Get BTC price from pragma adapter
        fn _get_btc_price(self: @ContractState) -> u256 {
            let adapter = self.pragma_adapter.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if adapter == zero {
                return self.entry_price.read();
            }
            IPragmaAdapterDispatcher { contract_address: adapter }.get_btc_price()
        }

        /// Active CDP rebalancing — StarkYield-compliant.
        ///
        /// After each swap, check if DTV has deviated from TARGET_DTV (50%).
        /// If deviation > threshold, use flash loans + LP + debt operations
        /// to restore DTV to ~50%.
        ///
        /// Leverage up (DTV < 50%):
        ///   1. Flash-borrow X USDC from VirtualPool
        ///   2. Add USDC-only LP on Ekubo → get LP token
        ///   3. Borrow X USDC from lending (new debt)
        ///   4. Repay flash loan
        ///   Result: debt += X, collateral += X → DTV closer to 50%
        ///
        /// Deleverage (DTV > 50%):
        ///   1. Flash-borrow Y USDC from VirtualPool
        ///   2. Repay Y USDC debt (mock: decrements counter)
        ///   3. Remove old rebalance LP if any
        ///   4. Repay flash loan
        ///   Result: debt -= Y, collateral -= Y → DTV closer to 50%
        fn _rebalance_cdp(ref self: ContractState) {
            let c = self.collateral_value.read();
            let d = self.debt.read();
            if c == 0 { return; }

            let dtv = Math::div_fixed(d, c);
            let target = Constants::TARGET_DTV;
            let threshold = Constants::REBALANCE_DTV_THRESHOLD;

            // Check if DTV is close enough to target — skip if within threshold
            let diff = if dtv >= target { dtv - target } else { target - dtv };
            if diff <= threshold { return; }

            // Check integrations are wired — graceful skip if not configured
            let vpool_addr = self.virtual_pool.read();
            let ekubo_addr = self.ekubo_adapter.read();
            let lend_addr = self.lending_adapter.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if vpool_addr == zero || lend_addr == zero { return; }

            let usdc_addr = self.usdc_token.read();
            let usdc = IERC20ApproveDispatcher { contract_address: usdc_addr };
            let vpool = IVirtualPoolRebalanceDispatcher { contract_address: vpool_addr };
            let lending = ILendingRebalanceDispatcher { contract_address: lend_addr };

            if dtv < target {
                // ── Leverage up: need more debt to reach 50% DTV ──
                //
                // Math: We want (D + X) / (C + X) = TARGET_DTV
                //   D + X = TARGET_DTV * (C + X)
                //   D + X = TARGET_DTV * C + TARGET_DTV * X
                //   X * (1 - TARGET_DTV) = TARGET_DTV * C - D
                //   X = (TARGET_DTV * C - D) / (1 - TARGET_DTV)
                //
                // For TARGET_DTV = 0.5: X = (0.5*C - D) / 0.5 = C - 2D

                let target_debt = Math::mul_fixed(target, c);
                if target_debt <= d { return; }  // safety check

                let numerator = target_debt - d;
                let denominator = Constants::SCALE - target;
                let x = Math::div_fixed(numerator, denominator);
                if x == 0 { return; }

                // Convert from 1e18-scaled to raw USDC (6 decimals)
                let x_raw = x / Constants::USDC_SCALE_FACTOR;
                if x_raw == 0 { return; }

                // 1. Flash-borrow X USDC from VirtualPool
                vpool.flash_loan(x_raw);

                // 2. Add USDC-only LP on Ekubo (if adapter is set)
                //    This demonstrates the real token flow for leveraged LP
                if ekubo_addr != zero {
                    // Remove old rebalance LP if any (merge into new)
                    let old_lp = self.rebalance_lp_id.read();
                    if old_lp > 0 {
                        let ekubo = IEkuboRebalanceDispatcher { contract_address: ekubo_addr };
                        ekubo.remove_liquidity(old_lp);
                        // Recovered tokens stay in LEVAMM, available for new LP
                    }

                    usdc.approve(ekubo_addr, x_raw);
                    let ekubo = IEkuboRebalanceDispatcher { contract_address: ekubo_addr };
                    let lp_id = ekubo.add_liquidity(0, x_raw);
                    self.rebalance_lp_id.write(lp_id);
                }

                // 3. Borrow X USDC from lending (increases real CDP debt)
                //    Mock mints USDC and sends to LEVAMM
                lending.borrow_usdc(x_raw);

                // 4. Repay flash loan with borrowed USDC
                usdc.approve(vpool_addr, x_raw);
                vpool.repay_flash_loan(x_raw);

                // 5. Update 1e18-scaled accounting
                self.debt.write(d + x);
                self.collateral_value.write(c + x);

                let new_dtv = self.get_dtv();
                self.emit(Rebalanced {
                    direction: true, adjustment_scaled: x, adjustment_raw: x_raw, new_dtv,
                });
            } else {
                // ── Deleverage: need less debt to reach 50% DTV ──
                //
                // Math: We want (D - Y) / (C - Y) = TARGET_DTV
                //   D - Y = TARGET_DTV * (C - Y)
                //   D - Y = TARGET_DTV * C - TARGET_DTV * Y
                //   -Y + TARGET_DTV * Y = TARGET_DTV * C - D
                //   Y * (TARGET_DTV - 1) = TARGET_DTV * C - D
                //   Y = (D - TARGET_DTV * C) / (1 - TARGET_DTV)
                //
                // For TARGET_DTV = 0.5: Y = (D - 0.5*C) / 0.5 = 2D - C

                let target_debt = Math::mul_fixed(target, c);
                if d <= target_debt { return; }  // safety check

                let numerator = d - target_debt;
                let denominator = Constants::SCALE - target;
                let y = Math::div_fixed(numerator, denominator);
                if y == 0 { return; }

                // Cap at current debt
                let y = Math::min(y, d);

                // Convert from 1e18-scaled to raw USDC (6 decimals)
                let y_raw = y / Constants::USDC_SCALE_FACTOR;
                if y_raw == 0 { return; }

                // 1. Flash-borrow Y USDC from VirtualPool
                vpool.flash_loan(y_raw);

                // 2. Repay Y USDC debt (mock: just decrements counter, no token pull)
                lending.repay_usdc(y_raw);

                // 3. Remove old rebalance LP if any → recovered tokens stay in LEVAMM
                let old_lp = self.rebalance_lp_id.read();
                if old_lp > 0 && ekubo_addr != zero {
                    let ekubo = IEkuboRebalanceDispatcher { contract_address: ekubo_addr };
                    ekubo.remove_liquidity(old_lp);
                    self.rebalance_lp_id.write(0);
                }

                // 4. Repay flash loan (USDC from step 1 is still in LEVAMM since
                //    mock repay_usdc doesn't actually pull tokens)
                usdc.approve(vpool_addr, y_raw);
                vpool.repay_flash_loan(y_raw);

                // 5. Update 1e18-scaled accounting
                let new_d = if d >= y { d - y } else { 0 };
                let new_c = if c >= y { c - y } else { 0 };
                self.debt.write(new_d);
                self.collateral_value.write(new_c);

                let new_dtv = self.get_dtv();
                self.emit(Rebalanced {
                    direction: false, adjustment_scaled: y, adjustment_raw: y_raw, new_dtv,
                });
            }
        }
    }
}
