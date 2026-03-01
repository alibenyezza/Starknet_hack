use starknet::ContractAddress;

// ─── Vesu primitive types ─────────────────────────────────────────────────────

/// Vesu signed 257-bit integer (sign-magnitude representation)
#[derive(Copy, Drop, Serde)]
pub struct i257 {
    pub abs: u256,
    pub is_negative: bool, // false = positive, true = negative
}

/// Whether the amount is a delta (relative change) or absolute target
#[derive(Copy, Drop, Serde)]
pub enum AmountType {
    Delta,  // change by this amount (positive = increase, negative = decrease)
    Target, // set position to exactly this amount
}

/// Token denomination for the amount
#[derive(Copy, Drop, Serde)]
pub enum AmountDenomination {
    Native, // raw token units (wei)
    Assets, // underlying asset units (same as Native for standard ERC20)
}

/// Unified amount struct used for all position changes
#[derive(Copy, Drop, Serde)]
pub struct Amount {
    pub amount_type: AmountType,
    pub denomination: AmountDenomination,
    pub value: i257,
}

/// Parameters for modify_position — handles all position operations
#[derive(Copy, Drop, Serde)]
pub struct ModifyPositionParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub collateral: Amount,
    pub debt: Amount,
    pub data: Span<felt252>, // extra data for extensions; pass array![].span()
}

/// Current state of a position (returned by position() view)
#[derive(Copy, Drop, Serde)]
pub struct Position {
    pub collateral_shares: u256,
    pub nominal_debt: u256,
}

/// ERC20 amount delta (returned alongside position from modify_position)
#[derive(Copy, Drop, Serde)]
pub struct ERC20Amount {
    pub token: ContractAddress,
    pub amount: i257,
}

// ─── Vesu Singleton interface ─────────────────────────────────────────────────
// One contract handles all pools, assets, and positions.
// Singleton Sepolia: 0x02545b2e5d519fc230e9cd781046d9a64a2f027bbf34769c48fc7e54bfacf1a8

#[starknet::interface]
pub trait IVesuSingleton<TContractState> {
    /// Universal position modification: deposit, withdraw, borrow, repay.
    /// Returns (updated_position, collateral_delta, debt_delta).
    fn modify_position(
        ref self: TContractState,
        params: ModifyPositionParams,
    ) -> (Position, ERC20Amount, ERC20Amount);

    /// Read the current position for (pool, collateral, debt, user).
    fn position(
        self: @TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> Position;
}

// ─── StarkYield Vesu Adapter interface ────────────────────────────────────────

#[starknet::interface]
pub trait IVesuAdapter<TContractState> {
    fn deposit_collateral(ref self: TContractState, btc_amount: u256);
    fn withdraw_collateral(ref self: TContractState, btc_amount: u256);
    fn borrow_usdc(ref self: TContractState, usdc_amount: u256);
    fn repay_usdc(ref self: TContractState, usdc_amount: u256);
    fn get_collateral_balance(self: @TContractState) -> u256;
    fn get_debt_balance(self: @TContractState) -> u256;
    // Admin: set the Vesu pool ID (must be called after deployment)
    fn set_pool_id(ref self: TContractState, pool_id: felt252);
}

// ─── VesuAdapter contract ─────────────────────────────────────────────────────

#[starknet::contract]
pub mod VesuAdapter {
    use super::{
        ContractAddress, IVesuAdapter, IVesuSingletonDispatcher, IVesuSingletonDispatcherTrait,
        ModifyPositionParams, Amount, AmountType, AmountDenomination, i257,
    };
    use starknet::{get_contract_address, get_caller_address};
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        vesu_singleton: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pool_id: felt252,
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        vesu_singleton: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pool_id: felt252,
        owner: ContractAddress,
    ) {
        self.vesu_singleton.write(vesu_singleton);
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.pool_id.write(pool_id);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl VesuAdapterImpl of IVesuAdapter<ContractState> {
        /// Deposit BTC as collateral on Vesu.
        /// BTC must already be in this contract (transferred by LeverageManager).
        fn deposit_collateral(ref self: ContractState, btc_amount: u256) {
            assert(btc_amount > 0, 'Amount must be > 0');

            let singleton_addr = self.vesu_singleton.read();
            let btc_token = self.btc_token.read();

            // Approve Singleton to pull BTC
            let btc = IERC20Dispatcher { contract_address: btc_token };
            btc.approve(singleton_addr, btc_amount);

            let singleton = IVesuSingletonDispatcher { contract_address: singleton_addr };
            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: btc_token,
                debt_asset: self.usdc_token.read(),
                user: get_contract_address(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: btc_amount, is_negative: false }, // positive = deposit
                },
                debt: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: 0, is_negative: false },
                },
                data: array![].span(),
            };

            singleton.modify_position(params);
        }

        /// Withdraw BTC collateral from Vesu.
        fn withdraw_collateral(ref self: ContractState, btc_amount: u256) {
            assert(btc_amount > 0, 'Amount must be > 0');

            let singleton = IVesuSingletonDispatcher {
                contract_address: self.vesu_singleton.read(),
            };
            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: self.btc_token.read(),
                debt_asset: self.usdc_token.read(),
                user: get_contract_address(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: btc_amount, is_negative: true }, // negative = withdraw
                },
                debt: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: 0, is_negative: false },
                },
                data: array![].span(),
            };

            singleton.modify_position(params);
        }

        /// Borrow USDC against BTC collateral.
        /// Positive debt delta = increase debt = borrow.
        fn borrow_usdc(ref self: ContractState, usdc_amount: u256) {
            assert(usdc_amount > 0, 'Amount must be > 0');

            let singleton = IVesuSingletonDispatcher {
                contract_address: self.vesu_singleton.read(),
            };
            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: self.btc_token.read(),
                debt_asset: self.usdc_token.read(),
                user: get_contract_address(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: 0, is_negative: false },
                },
                debt: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: usdc_amount, is_negative: false }, // positive = borrow
                },
                data: array![].span(),
            };

            singleton.modify_position(params);
        }

        /// Repay USDC debt.
        /// Negative debt delta = decrease debt = repay.
        /// USDC must already be in this contract.
        fn repay_usdc(ref self: ContractState, usdc_amount: u256) {
            assert(usdc_amount > 0, 'Amount must be > 0');

            let singleton_addr = self.vesu_singleton.read();
            let usdc_token = self.usdc_token.read();

            // Approve Singleton to pull USDC for repayment
            let usdc = IERC20Dispatcher { contract_address: usdc_token };
            usdc.approve(singleton_addr, usdc_amount);

            let singleton = IVesuSingletonDispatcher { contract_address: singleton_addr };
            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: self.btc_token.read(),
                debt_asset: usdc_token,
                user: get_contract_address(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: 0, is_negative: false },
                },
                debt: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257 { abs: usdc_amount, is_negative: true }, // negative = repay
                },
                data: array![].span(),
            };

            singleton.modify_position(params);
        }

        /// Get current BTC collateral balance from Vesu.
        fn get_collateral_balance(self: @ContractState) -> u256 {
            let singleton = IVesuSingletonDispatcher {
                contract_address: self.vesu_singleton.read(),
            };
            let pos = singleton.position(
                self.pool_id.read(),
                self.btc_token.read(),
                self.usdc_token.read(),
                get_contract_address(),
            );
            pos.collateral_shares
        }

        /// Get current USDC debt balance from Vesu.
        fn get_debt_balance(self: @ContractState) -> u256 {
            let singleton = IVesuSingletonDispatcher {
                contract_address: self.vesu_singleton.read(),
            };
            let pos = singleton.position(
                self.pool_id.read(),
                self.btc_token.read(),
                self.usdc_token.read(),
                get_contract_address(),
            );
            pos.nominal_debt
        }

        /// Update the Vesu pool ID (admin only).
        /// Must be called after deployment to configure the correct pool.
        fn set_pool_id(ref self: ContractState, pool_id: felt252) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.pool_id.write(pool_id);
        }
    }
}
