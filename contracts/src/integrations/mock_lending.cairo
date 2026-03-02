//! Mock Lending Adapter for testnet
//!
//! Simulates Vesu lending using MockUSDC's public faucet — no real Vesu pool needed.
//! Implements IVesuAdapter so it is a drop-in replacement for VesuAdapter.
//!
//! Key behaviour:
//! - deposit_collateral: tracks incoming BTC internally (already in contract)
//! - withdraw_collateral: sends tracked BTC back to caller
//! - borrow_usdc: mints USDC via MockUSDC.faucet(), forwards it directly to
//!   EkuboAdapter (bypassing the missing USDC transfer in LeverageManager)
//! - repay_usdc: no-op on tokens, just decrements debt counter
//! - set_pool_id: no-op (kept for interface compatibility)

use starknet::ContractAddress;

/// Admin interface (extra functions not in IVesuAdapter)
#[starknet::interface]
pub trait IMockLendingAdmin<TContractState> {
    fn set_ekubo_adapter(ref self: TContractState, ekubo_adapter: ContractAddress);
}

/// LP collateral interface (YieldBasis extension)
#[starknet::interface]
pub trait IMockLendingLP<TContractState> {
    /// Records LP token ID as CDP collateral (mock: no NFT transfer needed).
    fn deposit_collateral_lp(ref self: TContractState, lp_id: felt252);
    /// Returns stored LP token ID and clears it (mock CDP withdrawal).
    fn withdraw_collateral_lp(ref self: TContractState) -> felt252;
    /// Queries LP value from MockEkubo using stored LP token ID.
    fn get_lp_collateral_value(self: @TContractState) -> u256;
}

/// Minimal faucet interface — avoids circular import with vault::mock_usdc
#[starknet::interface]
trait IFaucet<TContractState> {
    fn faucet(ref self: TContractState, amount: u256);
}

#[starknet::contract]
pub mod MockLendingAdapter {
    use super::{ContractAddress, IMockLendingAdmin, IMockLendingLP, IFaucetDispatcher, IFaucetDispatcherTrait};
    use starkyield::integrations::vesu::IVesuAdapter;
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starkyield::integrations::mock_ekubo::{IMockEkuboLPDispatcher, IMockEkuboLPDispatcherTrait};
    use starknet::get_caller_address;

    #[storage]
    struct Storage {
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        /// EkuboAdapter address — borrowed USDC is forwarded here directly
        ekubo_adapter: ContractAddress,
        collateral_balance: u256,
        debt_balance: u256,
        /// LP token ID used as CDP collateral (YieldBasis flow)
        lp_token_id: felt252,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(
        ref self: ContractState,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        ekubo_adapter: ContractAddress,
        owner: ContractAddress,
    ) {
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.ekubo_adapter.write(ekubo_adapter);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl VesuAdapterImpl of IVesuAdapter<ContractState> {
        /// BTC is already in this contract (transferred by LeverageManager).
        /// Just track the balance.
        fn deposit_collateral(ref self: ContractState, btc_amount: u256) {
            self.collateral_balance.write(self.collateral_balance.read() + btc_amount);
        }

        /// Transfer BTC back to caller (LeverageManager).
        fn withdraw_collateral(ref self: ContractState, btc_amount: u256) {
            let bal = self.collateral_balance.read();
            let actual = if btc_amount > bal {
                bal
            } else {
                btc_amount
            };
            if actual > 0 {
                IERC20Dispatcher { contract_address: self.btc_token.read() }
                    .transfer(get_caller_address(), actual);
                self.collateral_balance.write(bal - actual);
            }
        }

        /// Simulate borrowing:
        /// 1. Mint USDC to self via MockUSDC public faucet
        /// 2. Forward USDC to caller (YieldBasis: VaultManager repays flash loan)
        fn borrow_usdc(ref self: ContractState, usdc_amount: u256) {
            if usdc_amount == 0 {
                return;
            }
            let usdc_addr = self.usdc_token.read();
            // Mint to self
            IFaucetDispatcher { contract_address: usdc_addr }.faucet(usdc_amount);
            // Forward to caller (VaultManager or VirtualPool)
            IERC20Dispatcher { contract_address: usdc_addr }
                .transfer(get_caller_address(), usdc_amount);
            self.debt_balance.write(self.debt_balance.read() + usdc_amount);
        }

        /// No real burn — just decrement the debt counter.
        fn repay_usdc(ref self: ContractState, usdc_amount: u256) {
            let debt = self.debt_balance.read();
            let actual = if usdc_amount > debt {
                debt
            } else {
                usdc_amount
            };
            self.debt_balance.write(debt - actual);
        }

        fn get_collateral_balance(self: @ContractState) -> u256 {
            self.collateral_balance.read()
        }

        fn get_debt_balance(self: @ContractState) -> u256 {
            self.debt_balance.read()
        }

        /// No-op: mock mode has no Vesu pool.
        fn set_pool_id(ref self: ContractState, pool_id: felt252) {
            let _ = pool_id;
        }
    }

    #[abi(embed_v0)]
    impl MockLendingAdminImpl of IMockLendingAdmin<ContractState> {
        fn set_ekubo_adapter(ref self: ContractState, ekubo_adapter: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.ekubo_adapter.write(ekubo_adapter);
        }
    }

    #[abi(embed_v0)]
    impl MockLendingLPImpl of IMockLendingLP<ContractState> {
        /// Records LP token ID as CDP collateral (mock: no NFT transfer needed).
        fn deposit_collateral_lp(ref self: ContractState, lp_id: felt252) {
            self.lp_token_id.write(lp_id);
        }

        /// Returns stored LP token ID and clears it.
        fn withdraw_collateral_lp(ref self: ContractState) -> felt252 {
            let lp_id = self.lp_token_id.read();
            self.lp_token_id.write(0);
            lp_id
        }

        /// Queries LP value from MockEkubo using the stored LP token ID.
        fn get_lp_collateral_value(self: @ContractState) -> u256 {
            let lp_id = self.lp_token_id.read();
            if lp_id == 0 {
                return 0;
            }
            let lp_id_u64: u64 = lp_id.try_into().unwrap_or(1_u64);
            IMockEkuboLPDispatcher { contract_address: self.ekubo_adapter.read() }
                .get_lp_value(lp_id_u64)
        }
    }
}
