use starknet::ContractAddress;

// ─── Ekubo primitive types ────────────────────────────────────────────────────

/// Ekubo signed 129-bit integer (sign-magnitude representation)
/// Used for all token amounts and deltas in the protocol
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct i129 {
    pub mag: u128,
    pub sign: bool, // false = positive, true = negative
}

/// Pool identifier — token0 must be the lower felt252 address
#[derive(Drop, Copy, Serde)]
pub struct PoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,               // fee in 1/2^128 units (0.3% ≈ 1020847100762815390390123822295304634)
    pub tick_spacing: u128,      // 60 for 0.3% fee tier
    pub extension: ContractAddress, // 0x0 for vanilla pools
}

/// Tick range for LP position
#[derive(Drop, Copy, Serde)]
pub struct Bounds {
    pub lower: i129,
    pub upper: i129,
}

/// Input token + amount for a single-hop swap via Router
#[derive(Drop, Copy, Serde)]
pub struct TokenAmount {
    pub token: ContractAddress,
    pub amount: i129, // positive = exact input
}

/// Single swap hop specification
#[derive(Drop, Copy, Serde)]
pub struct RouteNode {
    pub pool_key: PoolKey,
    pub sqrt_ratio_limit: u256, // price limit; 0 = no limit (use MAX/MIN constant)
    pub skip_ahead: u128,       // optimization hint; 0 for most cases
}

/// Result of a swap — signed token deltas
#[derive(Drop, Copy, Serde)]
pub struct Delta {
    pub amount0: i129, // negative = protocol sends token0 out
    pub amount1: i129,
}

// sqrt_ratio limits for no-price-constraint swaps
// Selling token0 (price goes up) → use MAX
// Selling token1 (price goes down) → use MIN
const MAX_SQRT_RATIO: u256 = 6277100250585753475930931601400621808602321654880405518632;
const MIN_SQRT_RATIO: u256 = 18446748437148339061;

// ─── Ekubo Router interface ────────────────────────────────────────────────────
// Preferred for external callers — handles locker callback internally.
// Caller must approve input token to Router before calling swap.

#[starknet::interface]
pub trait IEkuboRouter<TContractState> {
    /// Single-hop swap. token_amount.token is the input token.
    /// Caller must approve token_amount.amount to this contract first.
    fn swap(
        ref self: TContractState,
        node: RouteNode,
        token_amount: TokenAmount,
    ) -> Delta;

    /// Multi-hop swap along a route.
    fn multihop_swap(
        ref self: TContractState,
        route: Array<RouteNode>,
        token_amount: TokenAmount,
    ) -> Array<Delta>;
}

// ─── Ekubo Positions interface ─────────────────────────────────────────────────
// Manages concentrated liquidity NFT positions.
// Caller must approve both tokens to Positions contract before mint_and_deposit.

#[starknet::interface]
pub trait IEkuboPositions<TContractState> {
    /// Mint a new LP position and deposit liquidity.
    /// Returns (token_id, liquidity_added, delta_token0, delta_token1).
    /// min_liquidity = 0 disables slippage check.
    fn mint_and_deposit(
        ref self: TContractState,
        pool_key: PoolKey,
        bounds: Bounds,
        min_liquidity: u128,
    ) -> (u64, u128, i129, i129);

    /// Withdraw liquidity from a position and collect fees.
    /// Pass u128::MAX as liquidity to withdraw everything.
    /// Returns (amount0_received, amount1_received).
    fn withdraw(
        ref self: TContractState,
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128,
        collect_fees: bool,
    ) -> (u128, u128);

    /// Collect only fees without removing liquidity.
    fn collect_fees(
        ref self: TContractState,
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
    ) -> (u128, u128);
}

// ─── StarkYield Ekubo Adapter interface ───────────────────────────────────────

#[starknet::interface]
pub trait IEkuboAdapter<TContractState> {
    fn swap_btc_to_usdc(ref self: TContractState, btc_amount: u256, min_usdc_out: u256) -> u256;
    fn swap_usdc_to_btc(ref self: TContractState, usdc_amount: u256, min_btc_out: u256) -> u256;
    fn add_liquidity(ref self: TContractState, btc_amount: u256, usdc_amount: u256) -> u64;
    fn remove_liquidity(ref self: TContractState, token_id: u64) -> (u256, u256);
}

// ─── EkuboAdapter contract ────────────────────────────────────────────────────

#[starknet::contract]
pub mod EkuboAdapter {
    use super::{
        ContractAddress, IEkuboAdapter, IEkuboRouterDispatcher, IEkuboRouterDispatcherTrait,
        IEkuboPositionsDispatcher, IEkuboPositionsDispatcherTrait,
        PoolKey, Bounds, RouteNode, TokenAmount, Delta, i129,
        MAX_SQRT_RATIO, MIN_SQRT_RATIO,
    };
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    // 0.3% fee tier — use u128::MAX as sentinel when not set
    // 0.3% in Ekubo units: fee = floor(0.003 * 2^128) ≈ 1020847100762815390390123822295304634
    const FEE_0_3_PCT: u128 = 1020847100762815390390123822295304634_u128;
    const TICK_SPACING_0_3: u128 = 60_u128;

    // Full range ticks
    const FULL_RANGE_LOWER_MAG: u128 = 887272_u128;
    const FULL_RANGE_UPPER_MAG: u128 = 887272_u128;

    // u128 max for withdraw all liquidity
    const U128_MAX: u128 = 340282366920938463463374607431768211455_u128;

    #[storage]
    struct Storage {
        ekubo_router: ContractAddress,
        ekubo_positions: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pool_fee: u128,
        tick_spacing: u128,
        active_position_id: u64,
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        ekubo_router: ContractAddress,
        ekubo_positions: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pool_fee: u128,
        tick_spacing: u128,
        owner: ContractAddress,
    ) {
        self.ekubo_router.write(ekubo_router);
        self.ekubo_positions.write(ekubo_positions);
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.pool_fee.write(pool_fee);
        self.tick_spacing.write(tick_spacing);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl EkuboAdapterImpl of IEkuboAdapter<ContractState> {
        /// Swap BTC → USDC via Ekubo Router.
        /// BTC must already be in this contract (transferred by LeverageManager).
        fn swap_btc_to_usdc(
            ref self: ContractState, btc_amount: u256, min_usdc_out: u256,
        ) -> u256 {
            assert(btc_amount > 0, 'Amount must be > 0');

            let router_addr = self.ekubo_router.read();
            let btc_token = self.btc_token.read();
            let usdc_token = self.usdc_token.read();

            // Approve Router to spend BTC
            let btc = IERC20Dispatcher { contract_address: btc_token };
            btc.approve(router_addr, btc_amount);

            let router = IEkuboRouterDispatcher { contract_address: router_addr };
            let pool_key = self._get_pool_key(btc_token, usdc_token);

            // Selling BTC (token0 if btc < usdc) → price going up → MAX_SQRT_RATIO
            let (_sorted_token0, is_btc_token0) = self._sort_tokens(btc_token, usdc_token);
            let sqrt_limit = if is_btc_token0 { MAX_SQRT_RATIO } else { MIN_SQRT_RATIO };

            let node = RouteNode {
                pool_key,
                sqrt_ratio_limit: sqrt_limit,
                skip_ahead: 0,
            };
            let amount_i129 = self._to_i129_positive(btc_amount);
            let token_amount = TokenAmount { token: btc_token, amount: amount_i129 };

            let delta = router.swap(node, token_amount);

            // Extract USDC received (the output delta for usdc token)
            let usdc_received = self._extract_output_amount(delta, is_btc_token0);
            assert(usdc_received >= min_usdc_out, 'Slippage too high');

            usdc_received
        }

        /// Swap USDC → BTC via Ekubo Router.
        /// USDC must already be in this contract.
        fn swap_usdc_to_btc(
            ref self: ContractState, usdc_amount: u256, min_btc_out: u256,
        ) -> u256 {
            assert(usdc_amount > 0, 'Amount must be > 0');

            let router_addr = self.ekubo_router.read();
            let btc_token = self.btc_token.read();
            let usdc_token = self.usdc_token.read();

            // Approve Router to spend USDC
            let usdc = IERC20Dispatcher { contract_address: usdc_token };
            usdc.approve(router_addr, usdc_amount);

            let router = IEkuboRouterDispatcher { contract_address: router_addr };
            let pool_key = self._get_pool_key(btc_token, usdc_token);

            // Selling USDC → buying BTC
            let (_, is_btc_token0) = self._sort_tokens(btc_token, usdc_token);
            // If BTC is token0, selling USDC (token1) makes price go DOWN → MIN_SQRT_RATIO
            let sqrt_limit = if is_btc_token0 { MIN_SQRT_RATIO } else { MAX_SQRT_RATIO };

            let node = RouteNode {
                pool_key,
                sqrt_ratio_limit: sqrt_limit,
                skip_ahead: 0,
            };
            let amount_i129 = self._to_i129_positive(usdc_amount);
            let token_amount = TokenAmount { token: usdc_token, amount: amount_i129 };

            let delta = router.swap(node, token_amount);

            // BTC received is the opposite side
            let btc_received = self._extract_output_amount_for_token0(delta, is_btc_token0);
            assert(btc_received >= min_btc_out, 'Slippage too high');

            btc_received
        }

        /// Add liquidity to the BTC/USDC pool.
        /// BTC and USDC must already be in this contract.
        /// Returns the NFT token_id of the created position.
        fn add_liquidity(
            ref self: ContractState, btc_amount: u256, usdc_amount: u256,
        ) -> u64 {
            let positions_addr = self.ekubo_positions.read();
            let btc_token = self.btc_token.read();
            let usdc_token = self.usdc_token.read();

            // Approve Positions contract for both tokens
            let btc = IERC20Dispatcher { contract_address: btc_token };
            let usdc = IERC20Dispatcher { contract_address: usdc_token };
            btc.approve(positions_addr, btc_amount);
            usdc.approve(positions_addr, usdc_amount);

            let positions = IEkuboPositionsDispatcher { contract_address: positions_addr };
            let pool_key = self._get_pool_key(btc_token, usdc_token);

            // Full range position
            let bounds = Bounds {
                lower: i129 { mag: FULL_RANGE_LOWER_MAG, sign: true },  // -887272
                upper: i129 { mag: FULL_RANGE_UPPER_MAG, sign: false }, // +887272
            };

            // min_liquidity = 0: no slippage protection (fine for hackathon)
            let (token_id, _liquidity, _delta0, _delta1) = positions
                .mint_and_deposit(pool_key, bounds, 0);

            self.active_position_id.write(token_id);
            token_id
        }

        /// Remove all liquidity from a position.
        /// Returns (btc_received, usdc_received).
        fn remove_liquidity(
            ref self: ContractState, token_id: u64,
        ) -> (u256, u256) {
            let positions_addr = self.ekubo_positions.read();
            let btc_token = self.btc_token.read();
            let usdc_token = self.usdc_token.read();

            let positions = IEkuboPositionsDispatcher { contract_address: positions_addr };
            let pool_key = self._get_pool_key(btc_token, usdc_token);

            let bounds = Bounds {
                lower: i129 { mag: FULL_RANGE_LOWER_MAG, sign: true },
                upper: i129 { mag: FULL_RANGE_UPPER_MAG, sign: false },
            };

            // Withdraw all liquidity and collect fees
            let (amount0, amount1) = positions
                .withdraw(token_id, pool_key, bounds, U128_MAX, 0, 0, true);

            self.active_position_id.write(0);

            // Determine which amount is BTC and which is USDC
            let (_, is_btc_token0) = self._sort_tokens(btc_token, usdc_token);
            if is_btc_token0 {
                (amount0.into(), amount1.into())
            } else {
                (amount1.into(), amount0.into())
            }
        }
    }

    // ─── Internal helpers ────────────────────────────────────────────────────

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Build PoolKey — tokens MUST be sorted (token0 < token1 by felt252 value)
        fn _get_pool_key(
            self: @ContractState,
            btc_token: ContractAddress,
            usdc_token: ContractAddress,
        ) -> PoolKey {
            let (token0, token1) = if self._felt_lt(btc_token, usdc_token) {
                (btc_token, usdc_token)
            } else {
                (usdc_token, btc_token)
            };

            PoolKey {
                token0,
                token1,
                fee: self.pool_fee.read(),
                tick_spacing: self.tick_spacing.read(),
                extension: 0.try_into().unwrap(),
            }
        }

        /// Returns (sorted_token0, is_btc_token0)
        fn _sort_tokens(
            self: @ContractState,
            btc_token: ContractAddress,
            usdc_token: ContractAddress,
        ) -> (ContractAddress, bool) {
            if self._felt_lt(btc_token, usdc_token) {
                (btc_token, true)
            } else {
                (usdc_token, false)
            }
        }

        /// Compare two ContractAddresses as felt252
        fn _felt_lt(
            self: @ContractState,
            a: ContractAddress,
            b: ContractAddress,
        ) -> bool {
            let a_felt: felt252 = a.into();
            let b_felt: felt252 = b.into();
            let a_u256: u256 = a_felt.into();
            let b_u256: u256 = b_felt.into();
            a_u256 < b_u256
        }

        /// Convert u256 to positive i129 (asserts no overflow above u128)
        fn _to_i129_positive(self: @ContractState, amount: u256) -> i129 {
            let mag: u128 = amount.try_into().expect('Amount exceeds u128');
            i129 { mag, sign: false }
        }

        /// Extract USDC received from a Delta after selling BTC
        fn _extract_output_amount(
            self: @ContractState, delta: Delta, is_btc_token0: bool,
        ) -> u256 {
            // When selling BTC, the USDC delta is negative (protocol sends it out)
            if is_btc_token0 {
                // BTC = token0 sold, USDC = token1 received (delta1 is negative = output)
                delta.amount1.mag.into()
            } else {
                // BTC = token1 sold, USDC = token0 received (delta0 is negative = output)
                delta.amount0.mag.into()
            }
        }

        /// Extract BTC received from a Delta after selling USDC
        fn _extract_output_amount_for_token0(
            self: @ContractState, delta: Delta, is_btc_token0: bool,
        ) -> u256 {
            if is_btc_token0 {
                // BTC = token0, USDC = token1 sold → BTC delta0 is the output (negative)
                delta.amount0.mag.into()
            } else {
                // BTC = token1, USDC = token0 sold → BTC delta1 is the output (negative)
                delta.amount1.mag.into()
            }
        }
    }
}
