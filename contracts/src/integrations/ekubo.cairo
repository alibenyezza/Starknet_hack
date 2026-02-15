use starknet::ContractAddress;

/// Ekubo pool key identifying a specific pool
#[derive(Drop, Copy, Serde)]
pub struct PoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

/// Interface for Ekubo DEX core router
#[starknet::interface]
pub trait IEkuboRouter<TContractState> {
    fn swap(
        ref self: TContractState,
        pool_key: PoolKey,
        amount: u128,
        is_token1: bool,
        sqrt_ratio_limit: u256,
    ) -> (i128, i128);
}

/// Interface for Ekubo positions (LP management)
#[starknet::interface]
pub trait IEkuboPositions<TContractState> {
    fn mint(
        ref self: TContractState,
        pool_key: PoolKey,
        lower_tick: i128,
        upper_tick: i128,
        liquidity: u128,
    ) -> u64;
    fn burn(
        ref self: TContractState,
        token_id: u64,
    ) -> (u256, u256);
}

/// StarkYield Ekubo Adapter interface
#[starknet::interface]
pub trait IEkuboAdapter<TContractState> {
    fn swap_btc_to_usdc(ref self: TContractState, btc_amount: u256, min_usdc_out: u256) -> u256;
    fn swap_usdc_to_btc(ref self: TContractState, usdc_amount: u256, min_btc_out: u256) -> u256;
    fn add_liquidity(ref self: TContractState, btc_amount: u256, usdc_amount: u256) -> u64;
    fn remove_liquidity(ref self: TContractState, token_id: u64) -> (u256, u256);
}

#[starknet::contract]
pub mod EkuboAdapter {
    use super::{
        ContractAddress, IEkuboAdapter, PoolKey,
        IEkuboRouterDispatcher, IEkuboRouterDispatcherTrait,
        IEkuboPositionsDispatcher, IEkuboPositionsDispatcherTrait,
    };
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        ekubo_router: ContractAddress,
        ekubo_positions: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pool_fee: u128,
        tick_spacing: u128,
        // Track LP positions
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
        /// Swap BTC to USDC via Ekubo
        fn swap_btc_to_usdc(
            ref self: ContractState, btc_amount: u256, min_usdc_out: u256,
        ) -> u256 {
            assert(btc_amount > 0, 'Amount must be > 0');

            let router = IEkuboRouterDispatcher {
                contract_address: self.ekubo_router.read(),
            };

            // Approve router to spend BTC
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            btc.approve(self.ekubo_router.read(), btc_amount);

            let pool_key = self._get_pool_key();
            let amount_u128: u128 = btc_amount.try_into().expect('Amount overflow');

            let (_delta0, delta1) = router.swap(
                pool_key, amount_u128, false, 0, // No price limit
            );

            // delta1 is the USDC received (positive)
            let usdc_received: u256 = self._abs_i128(delta1).into();
            assert(usdc_received >= min_usdc_out, 'Slippage too high');

            usdc_received
        }

        /// Swap USDC to BTC via Ekubo
        fn swap_usdc_to_btc(
            ref self: ContractState, usdc_amount: u256, min_btc_out: u256,
        ) -> u256 {
            assert(usdc_amount > 0, 'Amount must be > 0');

            let router = IEkuboRouterDispatcher {
                contract_address: self.ekubo_router.read(),
            };

            // Approve router to spend USDC
            let usdc = IERC20Dispatcher { contract_address: self.usdc_token.read() };
            usdc.approve(self.ekubo_router.read(), usdc_amount);

            let pool_key = self._get_pool_key();
            let amount_u128: u128 = usdc_amount.try_into().expect('Amount overflow');

            let (delta0, _delta1) = router.swap(
                pool_key, amount_u128, true, 0,
            );

            let btc_received: u256 = self._abs_i128(delta0).into();
            assert(btc_received >= min_btc_out, 'Slippage too high');

            btc_received
        }

        /// Add liquidity to the BTC/USDC pool
        fn add_liquidity(
            ref self: ContractState, btc_amount: u256, usdc_amount: u256,
        ) -> u64 {
            let positions = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };

            // Approve tokens
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            let usdc = IERC20Dispatcher { contract_address: self.usdc_token.read() };
            btc.approve(self.ekubo_positions.read(), btc_amount);
            usdc.approve(self.ekubo_positions.read(), usdc_amount);

            let pool_key = self._get_pool_key();

            // Wide range for simplicity — full range LP
            let lower_tick: i128 = -887272;
            let upper_tick: i128 = 887272;

            let liquidity: u128 = btc_amount.try_into().expect('Liquidity overflow');
            let token_id = positions.mint(pool_key, lower_tick, upper_tick, liquidity);

            self.active_position_id.write(token_id);
            token_id
        }

        /// Remove liquidity from the pool
        fn remove_liquidity(
            ref self: ContractState, token_id: u64,
        ) -> (u256, u256) {
            let positions = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };

            let (btc_received, usdc_received) = positions.burn(token_id);
            self.active_position_id.write(0);

            (btc_received, usdc_received)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _get_pool_key(self: @ContractState) -> PoolKey {
            PoolKey {
                token0: self.btc_token.read(),
                token1: self.usdc_token.read(),
                fee: self.pool_fee.read(),
                tick_spacing: self.tick_spacing.read(),
                extension: 0.try_into().unwrap(),
            }
        }

        fn _abs_i128(self: @ContractState, value: i128) -> u128 {
            if value >= 0 {
                value.try_into().unwrap()
            } else {
                let neg: u128 = (-value).try_into().unwrap();
                neg
            }
        }
    }
}
