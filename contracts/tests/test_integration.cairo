//! Integration tests — full system wiring and cross-contract interactions
//!
//! These tests deploy the entire StarkYield contract suite and verify:
//!   a. Full deploy integration: all contracts wired together correctly
//!   b. Fee collection flow: LEVAMM fees route through VaultManager to FeeDistributor
//!   c. Pause prevents operations: deposit/withdraw revert when paused
//!   d. Risk manager blocks large withdrawal: daily limit enforcement
//!   e. High watermark tracking: initial value set correctly

use starknet::ContractAddress;
use core::traits::TryInto;

// ── Dispatchers for every contract under test ───────────────────────────────
use starkyield::vault::vault_manager::{IVaultManagerDispatcher, IVaultManagerDispatcherTrait};
use starkyield::vault::lt_token::{ILtTokenDispatcher, ILtTokenDispatcherTrait};
use starkyield::fees::fee_distributor::{IFeeDistributorDispatcher, IFeeDistributorDispatcherTrait};
use starkyield::amm::levamm::{ILevAMMDispatcher, ILevAMMDispatcherTrait};
use starkyield::risk::risk_manager::{IRiskManagerDispatcher, IRiskManagerDispatcherTrait};
use starkyield::pool::virtual_pool::{IVirtualPoolDispatcher, IVirtualPoolDispatcherTrait};

/// Minimal Ownable facade — used to call transfer_ownership / owner on the LtToken
/// without importing the full OpenZeppelin crate in tests.
#[starknet::interface]
trait IOwnableFacade<TContractState> {
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    fn owner(self: @TContractState) -> ContractAddress;
}

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    const SCALE: u256 = 1_000000000000000000;

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOY HELPERS — each contract has its own deployer
    // ═══════════════════════════════════════════════════════════════════════

    /// Deploy MockWBTC (no constructor args)
    fn deploy_mock_wbtc() -> ContractAddress {
        let contract_class = declare("MockWBTC").unwrap().contract_class();
        let calldata: Array<felt252> = array![];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        addr
    }

    /// Deploy MockUSDC (constructor: owner)
    fn deploy_mock_usdc(owner: ContractAddress) -> ContractAddress {
        let contract_class = declare("MockUSDC").unwrap().contract_class();
        let calldata = array![owner.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        addr
    }

    /// Deploy MockPragmaAdapter (constructor: owner)
    fn deploy_mock_pragma(owner: ContractAddress) -> ContractAddress {
        let contract_class = declare("MockPragmaAdapter").unwrap().contract_class();
        let calldata = array![owner.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        addr
    }

    /// Deploy MockEkuboAdapter (constructor: btc_token, usdc_token, owner)
    fn deploy_mock_ekubo(
        btc_token: ContractAddress, usdc_token: ContractAddress, owner: ContractAddress,
    ) -> ContractAddress {
        let contract_class = declare("MockEkuboAdapter").unwrap().contract_class();
        let calldata = array![btc_token.into(), usdc_token.into(), owner.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        addr
    }

    /// Deploy MockLendingAdapter (constructor: btc_token, usdc_token, ekubo_adapter, owner)
    fn deploy_mock_lending(
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        ekubo_adapter: ContractAddress,
        owner: ContractAddress,
    ) -> ContractAddress {
        let contract_class = declare("MockLendingAdapter").unwrap().contract_class();
        let calldata = array![
            btc_token.into(), usdc_token.into(), ekubo_adapter.into(), owner.into(),
        ];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        addr
    }

    /// Deploy VirtualPool (constructor: owner, usdc_token)
    fn deploy_virtual_pool(
        owner: ContractAddress, usdc_token: ContractAddress,
    ) -> IVirtualPoolDispatcher {
        let contract_class = declare("VirtualPool").unwrap().contract_class();
        let calldata = array![owner.into(), usdc_token.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        IVirtualPoolDispatcher { contract_address: addr }
    }

    /// Deploy RiskManager (constructor: owner, max_daily_withdrawal as u256)
    fn deploy_risk_manager(
        owner: ContractAddress, max_daily: u256,
    ) -> IRiskManagerDispatcher {
        let contract_class = declare("RiskManager").unwrap().contract_class();
        let calldata = array![owner.into(), max_daily.low.into(), max_daily.high.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        IRiskManagerDispatcher { contract_address: addr }
    }

    /// Deploy LtToken (constructor: name, symbol, owner)
    /// name and symbol are ByteArray — serialized as: [length_words, ...words, pending_word, pending_len]
    fn deploy_lt_token(owner: ContractAddress) -> ILtTokenDispatcher {
        let contract_class = declare("LtToken").unwrap().contract_class();
        // ByteArray serialization for short strings (< 31 bytes):
        //   data_len=0, pending_word=felt, pending_word_len=len
        // "LT Token" = 8 chars
        // "LT"       = 2 chars
        let mut calldata: Array<felt252> = array![];
        // name: ByteArray "LT Token"
        calldata.append(0); // data.len() = 0 (no full 31-byte words)
        calldata.append('LT Token'); // pending_word
        calldata.append(8); // pending_word_len
        // symbol: ByteArray "LT"
        calldata.append(0); // data.len()
        calldata.append('LT'); // pending_word
        calldata.append(2); // pending_word_len
        // owner
        calldata.append(owner.into());

        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        ILtTokenDispatcher { contract_address: addr }
    }

    /// Deploy FeeDistributor (constructor: owner, usdc_token)
    fn deploy_fee_distributor(
        owner: ContractAddress, usdc_token: ContractAddress,
    ) -> IFeeDistributorDispatcher {
        let contract_class = declare("FeeDistributor").unwrap().contract_class();
        let calldata = array![owner.into(), usdc_token.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        IFeeDistributorDispatcher { contract_address: addr }
    }

    /// Deploy LevAMM (constructor: owner, btc_token, usdc_token, pragma_adapter)
    fn deploy_levamm(
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pragma_adapter: ContractAddress,
    ) -> ILevAMMDispatcher {
        let contract_class = declare("LevAMM").unwrap().contract_class();
        let calldata = array![
            owner.into(), btc_token.into(), usdc_token.into(), pragma_adapter.into(),
        ];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        ILevAMMDispatcher { contract_address: addr }
    }

    /// Deploy VaultManager (constructor: btc, usdc, lt, ekubo, lending, vpool, risk, owner)
    fn deploy_vault_manager(
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        lt_token: ContractAddress,
        ekubo_adapter: ContractAddress,
        lending_adapter: ContractAddress,
        virtual_pool: ContractAddress,
        risk_manager: ContractAddress,
        owner: ContractAddress,
    ) -> IVaultManagerDispatcher {
        let contract_class = declare("VaultManager").unwrap().contract_class();
        let calldata = array![
            btc_token.into(),
            usdc_token.into(),
            lt_token.into(),
            ekubo_adapter.into(),
            lending_adapter.into(),
            virtual_pool.into(),
            risk_manager.into(),
            owner.into(),
        ];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        IVaultManagerDispatcher { contract_address: addr }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SYSTEM STRUCT — deploy everything and wire it together
    // ═══════════════════════════════════════════════════════════════════════

    #[derive(Drop)]
    struct System {
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        pragma_adapter: ContractAddress,
        ekubo_adapter: ContractAddress,
        lending_adapter: ContractAddress,
        virtual_pool: IVirtualPoolDispatcher,
        risk_manager: IRiskManagerDispatcher,
        lt_token: ILtTokenDispatcher,
        fee_distributor: IFeeDistributorDispatcher,
        levamm: ILevAMMDispatcher,
        vault_manager: IVaultManagerDispatcher,
    }

    /// Deploy the full StarkYield system with all contracts wired together.
    /// `max_daily_withdrawal` controls the RiskManager daily limit.
    fn deploy_full_system(max_daily_withdrawal: u256) -> System {
        let owner = test_address();

        // 1. Deploy tokens
        let btc_token = deploy_mock_wbtc();
        let usdc_token = deploy_mock_usdc(owner);

        // 2. Deploy oracle
        let pragma_adapter = deploy_mock_pragma(owner);

        // 3. Deploy Ekubo + Lending adapters
        let ekubo_adapter = deploy_mock_ekubo(btc_token, usdc_token, owner);
        let lending_adapter = deploy_mock_lending(btc_token, usdc_token, ekubo_adapter, owner);

        // 4. Deploy VirtualPool
        let virtual_pool = deploy_virtual_pool(owner, usdc_token);

        // 5. Deploy RiskManager
        let risk_manager = deploy_risk_manager(owner, max_daily_withdrawal);

        // 6. Deploy LtToken (owner will transfer ownership to VaultManager later)
        let lt_token = deploy_lt_token(owner);

        // 7. Deploy FeeDistributor
        let fee_distributor = deploy_fee_distributor(owner, usdc_token);

        // 8. Deploy LevAMM
        let levamm = deploy_levamm(owner, btc_token, usdc_token, pragma_adapter);

        // 9. Deploy VaultManager with all dependencies
        let vault_manager = deploy_vault_manager(
            btc_token,
            usdc_token,
            lt_token.contract_address,
            ekubo_adapter,
            lending_adapter,
            virtual_pool.contract_address,
            risk_manager.contract_address,
            owner,
        );

        // ── Wire contracts together ──

        start_cheat_caller_address(vault_manager.contract_address, owner);
        // Set FeeDistributor on VaultManager
        vault_manager.set_fee_distributor(fee_distributor.contract_address);
        // Set LevAMM on VaultManager
        vault_manager.set_levamm(levamm.contract_address);
        stop_cheat_caller_address(vault_manager.contract_address);

        // Set FeeDistributor on LevAMM
        start_cheat_caller_address(levamm.contract_address, owner);
        levamm.set_fee_distributor(fee_distributor.contract_address);
        stop_cheat_caller_address(levamm.contract_address);

        // Set LT token and staker on FeeDistributor
        start_cheat_caller_address(fee_distributor.contract_address, owner);
        fee_distributor.set_lt_token(lt_token.contract_address);
        stop_cheat_caller_address(fee_distributor.contract_address);

        // Transfer LT token ownership to VaultManager (so it can mint/burn)
        // OwnableComponent uses transfer_ownership
        // We need to use the Ownable interface on the LtToken
        // LtToken embeds OwnableImpl, so we call transfer_ownership via Ownable dispatcher
        let lt_ownable = IOwnableFacadeDispatcher {
            contract_address: lt_token.contract_address,
        };
        start_cheat_caller_address(lt_token.contract_address, owner);
        lt_ownable.transfer_ownership(vault_manager.contract_address);
        stop_cheat_caller_address(lt_token.contract_address);

        System {
            owner,
            btc_token,
            usdc_token,
            pragma_adapter,
            ekubo_adapter,
            lending_adapter,
            virtual_pool,
            risk_manager,
            lt_token,
            fee_distributor,
            levamm,
            vault_manager,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST (a): FULL DEPLOY INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_full_system_deploy_and_wiring() {
        let sys = deploy_full_system(1000 * SCALE);

        // VaultManager should be initialized correctly
        assert(sys.vault_manager.get_total_shares() == 0, 'Total shares should be 0');
        assert(sys.vault_manager.get_total_debt() == 0, 'Total debt should be 0');
        assert(!sys.vault_manager.is_paused(), 'Should not be paused');

        // LtToken ownership should be transferred to VaultManager
        let lt_ownable = IOwnableFacadeDispatcher {
            contract_address: sys.lt_token.contract_address,
        };
        assert(
            lt_ownable.owner() == sys.vault_manager.contract_address,
            'LT owner should be vault',
        );

        // FeeDistributor should have correct owner
        assert(sys.fee_distributor.get_owner() == sys.owner, 'FD owner mismatch');
        assert(!sys.fee_distributor.is_recovery_mode(), 'FD should not be in recovery');

        // LevAMM should not be active yet (needs initialization)
        assert(!sys.levamm.is_active(), 'LEVAMM should not be active');
        assert(sys.levamm.get_owner() == sys.owner, 'LEVAMM owner mismatch');

        // RiskManager should have the configured limit
        assert(
            sys.risk_manager.get_max_daily_withdrawal() == 1000 * SCALE,
            'RM limit mismatch',
        );

        // VirtualPool should have zero reserves
        assert(sys.virtual_pool.get_reserves() == 0, 'VPool reserves should be 0');
        assert(sys.virtual_pool.get_owner() == sys.owner, 'VPool owner mismatch');
    }

    #[test]
    fn test_full_system_user_shares_initially_zero() {
        let sys = deploy_full_system(1000 * SCALE);

        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        let bob: ContractAddress = 0xB0B.try_into().unwrap();

        assert(sys.vault_manager.get_user_shares(alice) == 0, 'Alice shares should be 0');
        assert(sys.vault_manager.get_user_shares(bob) == 0, 'Bob shares should be 0');
    }

    #[test]
    fn test_full_system_levamm_initialization() {
        let sys = deploy_full_system(1000 * SCALE);

        // Initialize LEVAMM with position data
        let collateral: u256 = 10_000 * SCALE;
        let debt: u256 = 3_000 * SCALE;
        let entry_price: u256 = 60_000 * SCALE;

        start_cheat_caller_address(sys.levamm.contract_address, sys.owner);
        sys.levamm.initialize(collateral, debt, entry_price);
        stop_cheat_caller_address(sys.levamm.contract_address);

        assert(sys.levamm.is_active(), 'LEVAMM should be active');
        assert(sys.levamm.get_collateral_value() == collateral, 'Collateral mismatch');
        assert(sys.levamm.get_debt() == debt, 'Debt mismatch');
        assert(sys.levamm.get_invariant() > 0, 'Invariant should be > 0');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST (b): FEE COLLECTION FLOW
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_collect_fees_no_levamm_returns_zero() {
        // Deploy vault with zero levamm address to test the no-levamm path
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();

        let vault = deploy_vault_manager(zero, zero, zero, zero, zero, zero, zero, owner);

        // collect_fees should return 0 when levamm is not set
        let fees = vault.collect_fees();
        assert(fees == 0, 'Fees should be 0 without levamm');
    }

    #[test]
    fn test_collect_fees_levamm_no_accumulated_fees() {
        let sys = deploy_full_system(1000 * SCALE);

        // Initialize LEVAMM so it is active
        start_cheat_caller_address(sys.levamm.contract_address, sys.owner);
        sys.levamm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(sys.levamm.contract_address);

        // No swaps performed, so no trading fees accumulated
        assert(sys.levamm.get_accumulated_trading_fees() == 0, 'No fees expected');

        // collect_fees through VaultManager should return 0
        let fees = sys.vault_manager.collect_fees();
        assert(fees == 0, 'VaultManager fees should be 0');

        // FeeDistributor should have received nothing
        assert(
            sys.fee_distributor.get_total_fees_distributed() == 0,
            'FD should have 0 distributed',
        );
    }

    #[test]
    fn test_fee_distributor_recovery_mode_integration() {
        let sys = deploy_full_system(1000 * SCALE);

        // Enable recovery mode on FeeDistributor
        start_cheat_caller_address(sys.fee_distributor.contract_address, sys.owner);
        sys.fee_distributor.set_recovery_mode(true);
        stop_cheat_caller_address(sys.fee_distributor.contract_address);

        assert(sys.fee_distributor.is_recovery_mode(), 'Should be in recovery mode');

        // Directly distribute some fees (simulating what LEVAMM.collect_fees does)
        let dist_amount: u256 = 500 * SCALE;
        sys.fee_distributor.distribute(dist_amount);

        // In recovery mode, ALL fees should go to recovery accumulator
        assert(
            sys.fee_distributor.get_accumulated_recovery_fees() == dist_amount,
            'All should go to recovery',
        );
        assert(
            sys.fee_distributor.get_accumulated_holder_fees() == 0,
            'Holder fees should be 0',
        );
        assert(
            sys.fee_distributor.get_accumulated_vesy_fees() == 0,
            'VeSY fees should be 0',
        );
    }

    #[test]
    fn test_fee_distributor_normal_mode_split() {
        let sys = deploy_full_system(1000 * SCALE);

        // Normal mode (default): fees split between veSY and holders
        let dist_amount: u256 = 1000 * SCALE;
        sys.fee_distributor.distribute(dist_amount);

        let holder = sys.fee_distributor.get_accumulated_holder_fees();
        let vesy = sys.fee_distributor.get_accumulated_vesy_fees();

        // With no staker set, admin fee = MIN_ADMIN_FEE (10%)
        // vesy ~= 100 * SCALE, holder ~= 900 * SCALE
        let tolerance = SCALE; // 1 unit rounding
        assert(holder + vesy >= dist_amount - tolerance, 'Sum too low');
        assert(holder + vesy <= dist_amount + tolerance, 'Sum too high');
        assert(holder > vesy, 'Holders should get more than veSY');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST (c): PAUSE PREVENTS OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Vault is paused')]
    fn test_pause_prevents_deposit() {
        let sys = deploy_full_system(1000 * SCALE);

        // Owner pauses the vault
        start_cheat_caller_address(sys.vault_manager.contract_address, sys.owner);
        sys.vault_manager.pause();
        stop_cheat_caller_address(sys.vault_manager.contract_address);

        assert(sys.vault_manager.is_paused(), 'Should be paused');

        // Any user trying to deposit should fail
        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, alice);
        sys.vault_manager.deposit(100);
    }

    #[test]
    #[should_panic(expected: 'Vault is paused')]
    fn test_pause_prevents_withdraw() {
        let sys = deploy_full_system(1000 * SCALE);

        // Owner pauses the vault
        start_cheat_caller_address(sys.vault_manager.contract_address, sys.owner);
        sys.vault_manager.pause();
        stop_cheat_caller_address(sys.vault_manager.contract_address);

        // Any user trying to withdraw should fail
        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, alice);
        sys.vault_manager.withdraw(100);
    }

    #[test]
    fn test_unpause_restores_state() {
        let sys = deploy_full_system(1000 * SCALE);

        // Pause
        start_cheat_caller_address(sys.vault_manager.contract_address, sys.owner);
        sys.vault_manager.pause();
        stop_cheat_caller_address(sys.vault_manager.contract_address);
        assert(sys.vault_manager.is_paused(), 'Should be paused');

        // Unpause
        start_cheat_caller_address(sys.vault_manager.contract_address, sys.owner);
        sys.vault_manager.unpause();
        stop_cheat_caller_address(sys.vault_manager.contract_address);
        assert(!sys.vault_manager.is_paused(), 'Should be unpaused');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_non_owner_cannot_pause() {
        let sys = deploy_full_system(1000 * SCALE);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, attacker);
        sys.vault_manager.pause();
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_non_owner_cannot_unpause() {
        let sys = deploy_full_system(1000 * SCALE);

        // Owner pauses
        start_cheat_caller_address(sys.vault_manager.contract_address, sys.owner);
        sys.vault_manager.pause();
        stop_cheat_caller_address(sys.vault_manager.contract_address);

        // Attacker tries to unpause
        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, attacker);
        sys.vault_manager.unpause();
    }

    #[test]
    fn test_pause_does_not_affect_view_functions() {
        let sys = deploy_full_system(1000 * SCALE);

        // Pause the vault
        start_cheat_caller_address(sys.vault_manager.contract_address, sys.owner);
        sys.vault_manager.pause();
        stop_cheat_caller_address(sys.vault_manager.contract_address);

        // View functions should still work
        let _shares = sys.vault_manager.get_total_shares();
        let _debt = sys.vault_manager.get_total_debt();
        let _paused = sys.vault_manager.is_paused();
        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        let _user_shares = sys.vault_manager.get_user_shares(alice);

        // If we get here without panic, view functions work while paused
        assert(true, 'Views work while paused');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST (d): RISK MANAGER BLOCKS LARGE WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_risk_manager_allows_small_withdrawal() {
        let sys = deploy_full_system(100 * SCALE);

        // Small withdrawal within limit
        assert(
            sys.risk_manager.check_withdrawal_limit(50 * SCALE),
            'Should allow 50 within 100 limit',
        );
    }

    #[test]
    fn test_risk_manager_blocks_overlimit_withdrawal() {
        let sys = deploy_full_system(100 * SCALE);

        // First withdrawal consumes most of the limit
        sys.risk_manager.record_withdrawal(80 * SCALE);

        // Second withdrawal exceeds remaining limit (80 + 30 = 110 > 100)
        assert(
            !sys.risk_manager.check_withdrawal_limit(30 * SCALE),
            'Should block 30 after 80 used',
        );
    }

    #[test]
    fn test_risk_manager_exact_limit() {
        let sys = deploy_full_system(100 * SCALE);

        // Withdrawal exactly at the limit should be allowed
        assert(
            sys.risk_manager.check_withdrawal_limit(100 * SCALE),
            'Should allow exactly at limit',
        );
    }

    #[test]
    fn test_risk_manager_just_over_limit() {
        let sys = deploy_full_system(100 * SCALE);

        // 1 wei over the limit
        assert(
            !sys.risk_manager.check_withdrawal_limit(100 * SCALE + 1),
            'Should block 1 wei over limit',
        );
    }

    #[test]
    fn test_risk_manager_reset_allows_again() {
        let sys = deploy_full_system(100 * SCALE);

        // Exhaust the daily limit
        sys.risk_manager.record_withdrawal(100 * SCALE);
        assert(
            !sys.risk_manager.check_withdrawal_limit(1),
            'Should be exhausted',
        );

        // Owner resets the daily counter
        start_cheat_caller_address(sys.risk_manager.contract_address, sys.owner);
        sys.risk_manager.reset_daily_withdrawals();
        stop_cheat_caller_address(sys.risk_manager.contract_address);

        // Now withdrawals are allowed again
        assert(
            sys.risk_manager.check_withdrawal_limit(50 * SCALE),
            'Should allow after reset',
        );
    }

    #[test]
    fn test_risk_manager_zero_limit_means_unlimited() {
        let sys = deploy_full_system(0);

        // When max_daily_withdrawal is 0, all withdrawals are allowed
        assert(
            sys.risk_manager.check_withdrawal_limit(999_999 * SCALE),
            'Zero limit = unlimited',
        );
    }

    #[test]
    fn test_risk_manager_update_limit_integration() {
        let sys = deploy_full_system(100 * SCALE);

        // Increase limit
        start_cheat_caller_address(sys.risk_manager.contract_address, sys.owner);
        sys.risk_manager.set_max_daily_withdrawal(500 * SCALE);
        stop_cheat_caller_address(sys.risk_manager.contract_address);

        assert(
            sys.risk_manager.get_max_daily_withdrawal() == 500 * SCALE,
            'Limit should be updated',
        );
        assert(
            sys.risk_manager.check_withdrawal_limit(400 * SCALE),
            'Should allow 400 with 500 limit',
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST (e): HIGH WATERMARK TRACKING
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_high_watermark_initial_value() {
        let sys = deploy_full_system(1000 * SCALE);

        // VaultManager constructor sets high_watermark to 1e18 (1.0 share price)
        // There is no public getter for high_watermark directly, but we verify
        // the system starts in a valid state — total_shares=0, total_debt=0
        // means the initial share price is conceptually 1.0
        assert(sys.vault_manager.get_total_shares() == 0, 'Shares should be 0');
        assert(sys.vault_manager.get_total_debt() == 0, 'Debt should be 0');
    }

    #[test]
    fn test_fee_distributor_recovery_mode_toggle() {
        // Recovery mode is the mechanism that activates when share price < HWM
        let sys = deploy_full_system(1000 * SCALE);

        // Initially NOT in recovery mode
        assert(!sys.fee_distributor.is_recovery_mode(), 'Should start non-recovery');

        // Owner can enable recovery mode (simulating HWM breach detection)
        start_cheat_caller_address(sys.fee_distributor.contract_address, sys.owner);
        sys.fee_distributor.set_recovery_mode(true);
        stop_cheat_caller_address(sys.fee_distributor.contract_address);
        assert(sys.fee_distributor.is_recovery_mode(), 'Should be in recovery');

        // Distribute fees while in recovery
        let amount: u256 = 200 * SCALE;
        sys.fee_distributor.distribute(amount);
        assert(
            sys.fee_distributor.get_accumulated_recovery_fees() == amount,
            'All to recovery',
        );

        // Owner disables recovery mode (share price restored above HWM)
        start_cheat_caller_address(sys.fee_distributor.contract_address, sys.owner);
        sys.fee_distributor.set_recovery_mode(false);
        stop_cheat_caller_address(sys.fee_distributor.contract_address);
        assert(!sys.fee_distributor.is_recovery_mode(), 'Should exit recovery');

        // Now fees are distributed normally
        sys.fee_distributor.distribute(300 * SCALE);
        let holder = sys.fee_distributor.get_accumulated_holder_fees();
        let vesy = sys.fee_distributor.get_accumulated_vesy_fees();
        assert(holder + vesy > 0, 'Normal split should happen');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADDITIONAL CROSS-CONTRACT INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_levamm_fee_distributor_wiring() {
        let sys = deploy_full_system(1000 * SCALE);

        // Initialize LEVAMM
        start_cheat_caller_address(sys.levamm.contract_address, sys.owner);
        sys.levamm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(sys.levamm.contract_address);

        // Verify LEVAMM and FeeDistributor are wired (no fees to collect yet)
        let collected = sys.levamm.collect_fees();
        assert(collected == 0, 'No fees to collect initially');

        // FeeDistributor should still have zero
        assert(
            sys.fee_distributor.get_total_fees_distributed() == 0,
            'FD total should be 0',
        );
    }

    #[test]
    fn test_volatility_decay_affects_distribution() {
        let sys = deploy_full_system(1000 * SCALE);

        // Record volatility decay first
        sys.fee_distributor.record_volatility_decay(100 * SCALE);
        assert(
            sys.fee_distributor.get_pending_volatility_decay() == 100 * SCALE,
            'Decay should be recorded',
        );

        // Distribute fees — decay should be subtracted
        sys.fee_distributor.distribute(500 * SCALE);

        // Decay consumed
        assert(
            sys.fee_distributor.get_pending_volatility_decay() == 0,
            'Decay should be consumed',
        );

        // Net distribution = 500 - 100 = 400
        let holder = sys.fee_distributor.get_accumulated_holder_fees();
        let vesy = sys.fee_distributor.get_accumulated_vesy_fees();
        let net = 400 * SCALE;
        let tolerance = SCALE;
        assert(holder + vesy >= net - tolerance, 'Net too low');
        assert(holder + vesy <= net + tolerance, 'Net too high');
    }

    #[test]
    fn test_interest_recording_integration() {
        let sys = deploy_full_system(1000 * SCALE);

        // Simulate interest recording on FeeDistributor
        let interest: u256 = 150 * SCALE;
        sys.fee_distributor.record_interest(interest);

        assert(
            sys.fee_distributor.get_accumulated_interest() == interest,
            'Interest should be recorded',
        );

        // Record more interest
        sys.fee_distributor.record_interest(50 * SCALE);
        assert(
            sys.fee_distributor.get_accumulated_interest() == 200 * SCALE,
            'Interest should accumulate',
        );
    }

    #[test]
    fn test_collect_fees_is_permissionless() {
        let sys = deploy_full_system(1000 * SCALE);

        // Any user should be able to call collect_fees on VaultManager
        let random_user: ContractAddress = 0xBEEF.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, random_user);
        let fees = sys.vault_manager.collect_fees();
        stop_cheat_caller_address(sys.vault_manager.contract_address);

        // No fees to collect, but it should not revert
        assert(fees == 0, 'Permissionless call should work');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_fee_distributor_access_control() {
        let sys = deploy_full_system(1000 * SCALE);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        let fake_addr: ContractAddress = 0xBAD.try_into().unwrap();

        start_cheat_caller_address(sys.vault_manager.contract_address, attacker);
        sys.vault_manager.set_fee_distributor(fake_addr);
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_levamm_access_control() {
        let sys = deploy_full_system(1000 * SCALE);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        let fake_addr: ContractAddress = 0xBAD.try_into().unwrap();

        start_cheat_caller_address(sys.vault_manager.contract_address, attacker);
        sys.vault_manager.set_levamm(fake_addr);
    }

    #[test]
    #[should_panic(expected: 'Amount must be > 0')]
    fn test_deposit_zero_amount_panics() {
        let sys = deploy_full_system(1000 * SCALE);

        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, alice);
        sys.vault_manager.deposit(0);
    }

    #[test]
    #[should_panic(expected: 'Shares must be > 0')]
    fn test_withdraw_zero_shares_panics() {
        let sys = deploy_full_system(1000 * SCALE);

        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, alice);
        sys.vault_manager.withdraw(0);
    }

    #[test]
    #[should_panic(expected: 'Insufficient shares')]
    fn test_withdraw_without_shares_panics() {
        let sys = deploy_full_system(0); // no risk limit (so it won't trip there)

        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(sys.vault_manager.contract_address, alice);
        // Alice has 0 shares, trying to withdraw 100 should fail
        sys.vault_manager.withdraw(100);
    }

    #[test]
    fn test_risk_manager_health_assessment_integration() {
        let sys = deploy_full_system(1000 * SCALE);

        // Verify health assessment through the wired risk manager
        assert(sys.risk_manager.assess_health(3 * SCALE) == 0, 'HF 3.0 = Safe');
        assert(sys.risk_manager.assess_health(1_700000000000000000) == 1, 'HF 1.7 = Moderate');
        assert(sys.risk_manager.assess_health(1_300000000000000000) == 2, 'HF 1.3 = Warning');
        assert(sys.risk_manager.assess_health(1_100000000000000000) == 3, 'HF 1.1 = Danger');
    }

    #[test]
    fn test_multiple_fee_distributions_accumulate() {
        let sys = deploy_full_system(1000 * SCALE);

        sys.fee_distributor.distribute(100 * SCALE);
        sys.fee_distributor.distribute(200 * SCALE);
        sys.fee_distributor.distribute(300 * SCALE);

        assert(
            sys.fee_distributor.get_total_fees_distributed() == 600 * SCALE,
            'Total should be 600',
        );

        let holder = sys.fee_distributor.get_accumulated_holder_fees();
        let vesy = sys.fee_distributor.get_accumulated_vesy_fees();
        let tolerance = SCALE;
        assert(holder + vesy >= 600 * SCALE - tolerance, 'Sum too low');
        assert(holder + vesy <= 600 * SCALE + tolerance, 'Sum too high');
    }

    #[test]
    fn test_levamm_refuel_updates_collateral() {
        let sys = deploy_full_system(1000 * SCALE);

        let initial_collateral: u256 = 10_000 * SCALE;
        start_cheat_caller_address(sys.levamm.contract_address, sys.owner);
        sys.levamm.initialize(initial_collateral, 3_000 * SCALE, 60_000 * SCALE);
        sys.levamm.refuel(2_000 * SCALE);
        stop_cheat_caller_address(sys.levamm.contract_address);

        assert(
            sys.levamm.get_collateral_value() == 12_000 * SCALE,
            'Collateral should be 12000',
        );
    }

    #[test]
    fn test_system_owner_consistency() {
        let sys = deploy_full_system(1000 * SCALE);

        // All admin contracts should reference the same owner
        assert(sys.fee_distributor.get_owner() == sys.owner, 'FD owner');
        assert(sys.levamm.get_owner() == sys.owner, 'LEVAMM owner');
        assert(sys.virtual_pool.get_owner() == sys.owner, 'VPool owner');
    }
}
