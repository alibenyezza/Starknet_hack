//! LEVAMM — Constant Leverage AMM (2× IL-free)
//!
//! Implements the bonding curve that maintains 2× leverage on the BTC/USDC position.
//! The core insight: applying leverage L=2 to the standard AMM (√p curve) yields p^(L/2) = p,
//! which tracks the asset price linearly → zero impermanent loss.
//!
//! Mathematical foundation:
//!   LEV_RATIO = (L/(L+1))^2 = (2/3)^2 = 4/9  (for L=2)
//!   x0 = (C + sqrt(C^2 - 4·C·LEV_RATIO·D)) / (2·LEV_RATIO)
//!   Invariant I(p0) = (x0(p0) - d_btc) · y
//!
//! Safety bands: DTV (Debt-To-Value) must stay in [6.25%, 53.125%] for 2× leverage.

use starknet::ContractAddress;

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

    // ── Admin ──────────────────────────────────────────────────────────────
    fn set_interest_rate(ref self: TContractState, rate: u256);
    fn set_pragma_adapter(ref self: TContractState, adapter: ContractAddress);
    fn set_owner(ref self: TContractState, new_owner: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod LevAMM {
    use super::{ILevAMM, ContractAddress};
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
        collateral_value: u256,   // C: USD value of LP tokens held as collateral
        debt: u256,               // D: USDC borrowed (outstanding)
        invariant: u256,          // I(p0): (x0 - d_btc) * y at initialization
        entry_price: u256,        // p0: BTC/USD price at initialization
        // Interest accrual
        accrued_interest: u256,
        last_interest_block: u64,
        interest_rate: u256,      // per-block rate (1e18-scaled)
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
    }

    #[derive(Drop, starknet::Event)]
    struct InterestAccrued { interest: u256, new_debt: u256 }

    #[derive(Drop, starknet::Event)]
    struct Refueled { usdc_amount: u256, new_collateral: u256 }

    #[derive(Drop, starknet::Event)]
    struct InterestRateSet { new_rate: u256 }

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
            //   x0 is in "BTC units" (1e18)
            //   d_btc = debt / entry_price  (also 1e18)
            //   y = collateral_value (in USDC 1e18)
            let x0 = self._calculate_x0(collateral_value, debt);
            let d_btc = Math::div_fixed(debt, entry_price);
            assert(x0 > d_btc, 'x0 must exceed d_btc');
            let x_minus_d = x0 - d_btc;
            let inv = Math::mul_fixed(x_minus_d, collateral_value);

            self.invariant.write(inv);
            self.is_active.write(true);
            self.last_interest_block.write(get_block_number());

            self.emit(Initialized { collateral_value, debt, invariant: inv, entry_price });
        }

        fn swap(ref self: ContractState, direction: bool, btc_amount: u256) -> u256 {
            assert(self.is_active.read(), 'LEVAMM not initialized');
            assert(btc_amount > 0, 'Amount must be > 0');

            let dtv = self.get_dtv();

            if direction {
                // Buying BTC (USDC in): only valid when under-levered (DTV < target)
                // LP is priced at a premium → arbitrageur buys LP with USDC to re-level
                assert(dtv <= Constants::DTV_MAX_2X, 'Cannot buy: over-levered');
            } else {
                // Selling BTC (USDC out): only valid when over-levered (DTV > target)
                // LP is priced at a discount → arbitrageur sells LP for USDC to de-lever
                assert(dtv >= Constants::DTV_MIN_2X, 'Cannot sell: under-levered');
            }

            let usdc_amount = self.get_price(btc_amount);
            assert(usdc_amount > 0, 'Zero output');

            // Update collateral: buying BTC increases USDC reserves (collateral up)
            //                    selling BTC decreases USDC reserves (collateral down)
            let c = self.collateral_value.read();
            if direction {
                self.collateral_value.write(c + usdc_amount);
            } else {
                let new_c = if c > usdc_amount { c - usdc_amount } else { 0 };
                self.collateral_value.write(new_c);
            }

            let new_dtv = self.get_dtv();
            self.emit(Swapped { direction, btc_amount, usdc_amount, new_dtv });
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

        fn set_pragma_adapter(ref self: ContractState, adapter: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.pragma_adapter.write(adapter);
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
        ///
        /// Note on fixed-point scaling:
        ///   mul_fixed(a, b) = a*b/SCALE  → so mul_fixed(C,C) = C^2/SCALE (still 1e18)
        ///   sqrt(discriminant * SCALE) → gives a 1e18-scaled result
        ///   (same pattern as il_eliminator.cairo: sqrt(price_ratio * SCALE))
        fn _calculate_x0(self: @ContractState, c: u256, d: u256) -> u256 {
            if c == 0 { return 0; }
            if d == 0 { return c; }  // no debt → x0 = C

            let lev = Constants::LEV_RATIO_2X;   // 4/9 * 1e18

            // c_squared = C^2 / SCALE  (1e18-scaled)
            let c_squared = Math::mul_fixed(c, c);

            // four_c_lev_d = 4 * C * LEV_RATIO * D / SCALE^2
            // Step 1: c * lev / SCALE
            let c_lev = Math::mul_fixed(c, lev);
            // Step 2: c_lev * d / SCALE
            let c_lev_d = Math::mul_fixed(c_lev, d);
            // Step 3: 4 * c_lev_d
            let four_c_lev_d = 4_u256 * c_lev_d;

            // Guard: discriminant must be non-negative (valid leverage regime)
            if four_c_lev_d >= c_squared {
                // Edge case: extremely high leverage ratio — return C / (2*LEV_RATIO)
                return Math::div_fixed(c, 2_u256 * lev);
            }

            let discriminant = c_squared - four_c_lev_d;

            // sqrt of a 1e18-scaled value: multiply by SCALE first, then sqrt
            // Result is 1e18-scaled
            let sqrt_disc = Math::sqrt(discriminant * Constants::SCALE);

            // numerator = C + sqrt(discriminant)  [both 1e18-scaled]
            let numerator = c + sqrt_disc;

            // denominator = 2 * LEV_RATIO  [1e18-scaled: 2 * 444...444]
            let denominator = 2_u256 * lev;

            // x0 = numerator / denominator
            Math::div_fixed(numerator, denominator)
        }

        /// Get BTC price from pragma adapter
        fn _get_btc_price(self: @ContractState) -> u256 {
            let adapter = self.pragma_adapter.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if adapter == zero {
                // Fallback: use entry price if adapter not set
                return self.entry_price.read();
            }
            IPragmaAdapterDispatcher { contract_address: adapter }.get_btc_price()
        }
    }
}
