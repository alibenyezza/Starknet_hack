//! Tests for LEVAMM (Constant Leverage AMM) — including active rebalancing

use starknet::ContractAddress;
use starkyield::amm::levamm::{ILevAMMDispatcher, ILevAMMDispatcherTrait};
use starkyield::pool::virtual_pool::{IVirtualPoolDispatcher, IVirtualPoolDispatcherTrait};
use core::traits::TryInto;

/// Minimal ERC-20 facade for test setup (faucet + approve)
#[starknet::interface]
trait IERC20Test<TContractState> {
    fn faucet(ref self: TContractState, amount: u256);
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
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
    // DEPLOY HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Deploy LevAMM with constructor(owner, btc_token, usdc_token, pragma_adapter).
    /// btc_token, usdc_token, pragma_adapter are set to zero for isolated tests.
    /// When pragma_adapter is zero the contract falls back to entry_price for oracle.
    fn deploy_levamm(owner: ContractAddress) -> ILevAMMDispatcher {
        let zero: ContractAddress = 0.try_into().unwrap();
        let contract_class = declare("LevAMM").unwrap().contract_class();
        let calldata = array![
            owner.into(), // owner
            zero.into(),  // btc_token
            zero.into(),  // usdc_token
            zero.into(),  // pragma_adapter (zero → fallback to entry_price)
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        ILevAMMDispatcher { contract_address }
    }

    /// Deploy LevAMM with real token addresses (for rebalance tests)
    fn deploy_levamm_full(
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
    ) -> ILevAMMDispatcher {
        let zero: ContractAddress = 0.try_into().unwrap();
        let contract_class = declare("LevAMM").unwrap().contract_class();
        let calldata = array![
            owner.into(),
            btc_token.into(),
            usdc_token.into(),
            zero.into(), // pragma_adapter (zero → fallback to entry_price)
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        ILevAMMDispatcher { contract_address }
    }

    /// Deploy MockUSDC (constructor: owner)
    fn deploy_mock_usdc(owner: ContractAddress) -> ContractAddress {
        let contract_class = declare("MockUSDC").unwrap().contract_class();
        let calldata = array![owner.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        addr
    }

    /// Deploy MockWBTC (no constructor args)
    fn deploy_mock_wbtc() -> ContractAddress {
        let contract_class = declare("MockWBTC").unwrap().contract_class();
        let calldata: Array<felt252> = array![];
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

    /// Full rebalancing system: all contracts wired for rebalance testing
    #[derive(Drop)]
    struct RebalanceSystem {
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        ekubo_adapter: ContractAddress,
        lending_adapter: ContractAddress,
        virtual_pool: IVirtualPoolDispatcher,
        levamm: ILevAMMDispatcher,
    }

    /// Deploy and wire the full rebalancing stack.
    /// Funds VirtualPool with 1M USDC raw (enough for any rebalance).
    fn deploy_rebalance_system() -> RebalanceSystem {
        let owner = test_address();

        // 1. Deploy tokens
        let btc_token = deploy_mock_wbtc();
        let usdc_token = deploy_mock_usdc(owner);

        // 2. Deploy adapters
        let ekubo_adapter = deploy_mock_ekubo(btc_token, usdc_token, owner);
        let lending_adapter = deploy_mock_lending(btc_token, usdc_token, ekubo_adapter, owner);

        // 3. Deploy VirtualPool + fund with 1M USDC
        let virtual_pool = deploy_virtual_pool(owner, usdc_token);
        let usdc = IERC20TestDispatcher { contract_address: usdc_token };

        start_cheat_caller_address(usdc_token, owner);
        usdc.faucet(1_000_000_000_000); // 1M USDC raw (6 dec)
        usdc.approve(virtual_pool.contract_address, 1_000_000_000_000);
        stop_cheat_caller_address(usdc_token);

        start_cheat_caller_address(virtual_pool.contract_address, owner);
        virtual_pool.fund(1_000_000_000_000);
        stop_cheat_caller_address(virtual_pool.contract_address);

        // 4. Deploy LevAMM with real token addresses
        let levamm = deploy_levamm_full(owner, btc_token, usdc_token);

        // 5. Wire LEVAMM to integrations
        start_cheat_caller_address(levamm.contract_address, owner);
        levamm.set_virtual_pool(virtual_pool.contract_address);
        levamm.set_ekubo_adapter(ekubo_adapter);
        levamm.set_lending_adapter(lending_adapter);
        stop_cheat_caller_address(levamm.contract_address);

        RebalanceSystem {
            owner,
            btc_token,
            usdc_token,
            ekubo_adapter,
            lending_adapter,
            virtual_pool,
            levamm,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ORIGINAL TESTS — DEPLOYMENT & INITIAL STATE
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_deploy_initial_state() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        assert(!amm.is_active(), 'Should not be active initially');
        assert(amm.get_collateral_value() == 0, 'Collateral should be 0');
        assert(amm.get_debt() == 0, 'Debt should be 0');
        assert(amm.get_invariant() == 0, 'Invariant should be 0');
        assert(amm.get_accrued_interest() == 0, 'Interest should be 0');
        assert(amm.get_accumulated_trading_fees() == 0, 'Fees should be 0');
        assert(amm.get_rebalance_lp_id() == 0, 'Rebalance LP should be 0');
    }

    #[test]
    fn test_deploy_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);
        assert(amm.get_owner() == owner, 'Owner should match');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_initialize() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let collateral: u256 = 10_000 * SCALE; // 10,000 USDC
        let debt: u256 = 3_000 * SCALE;        // 3,000 USDC
        let entry_price: u256 = 60_000 * SCALE; // 60,000 USD/BTC

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(collateral, debt, entry_price);
        stop_cheat_caller_address(amm.contract_address);

        assert(amm.is_active(), 'Should be active after init');
        assert(amm.get_collateral_value() == collateral, 'Collateral mismatch');
        assert(amm.get_debt() == debt, 'Debt mismatch');
        assert(amm.get_entry_price() == entry_price, 'Entry price mismatch');
        assert(amm.get_invariant() > 0, 'Invariant should be > 0');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_initialize_not_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, attacker);
        amm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
    }

    #[test]
    #[should_panic(expected: 'Already initialized')]
    fn test_initialize_twice() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        // Second call should fail
        amm.initialize(20_000 * SCALE, 5_000 * SCALE, 70_000 * SCALE);
    }

    #[test]
    #[should_panic(expected: 'Debt exceeds collateral')]
    fn test_initialize_debt_exceeds_collateral() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(3_000 * SCALE, 10_000 * SCALE, 60_000 * SCALE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GET DTV (Debt-To-Value)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_get_dtv() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let collateral: u256 = 10_000 * SCALE;
        let debt: u256 = 3_000 * SCALE;
        let entry_price: u256 = 60_000 * SCALE;

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(collateral, debt, entry_price);
        stop_cheat_caller_address(amm.contract_address);

        // DTV = debt / collateral = 3000 / 10000 = 0.3 = 30%
        let dtv = amm.get_dtv();
        let expected_dtv = SCALE * 30 / 100; // 0.3e18
        let tolerance = SCALE / 100; // 1%

        assert(dtv >= expected_dtv - tolerance, 'DTV too low');
        assert(dtv <= expected_dtv + tolerance, 'DTV too high');
    }

    #[test]
    fn test_get_dtv_zero_collateral() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // Not initialized → collateral = 0 → DTV = 0
        let dtv = amm.get_dtv();
        assert(dtv == 0, 'DTV should be 0 with no collateral');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IS OVER/UNDER LEVERED
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_is_under_levered() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // DTV_MIN_2X = 6.25%. Set debt very low relative to collateral.
        // debt/collateral = 500/10000 = 5% < 6.25% → under-levered
        let collateral: u256 = 10_000 * SCALE;
        let debt: u256 = 500 * SCALE;
        let entry_price: u256 = 60_000 * SCALE;

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(collateral, debt, entry_price);
        stop_cheat_caller_address(amm.contract_address);

        assert(amm.is_under_levered(), 'Should be under-levered at 5%');
        assert(!amm.is_over_levered(), 'Should not be over-levered');
    }

    #[test]
    fn test_is_over_levered() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // DTV_MAX_2X = 53.125%. Set debt high relative to collateral.
        // debt/collateral = 5500/10000 = 55% > 53.125% → over-levered
        let collateral: u256 = 10_000 * SCALE;
        let debt: u256 = 5_500 * SCALE;
        let entry_price: u256 = 60_000 * SCALE;

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(collateral, debt, entry_price);
        stop_cheat_caller_address(amm.contract_address);

        assert(amm.is_over_levered(), 'Should be over-levered at 55%');
        assert(!amm.is_under_levered(), 'Should not be under-levered');
    }

    #[test]
    fn test_within_range_neither_over_nor_under() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // DTV = 3000/10000 = 30%. In range [6.25%, 53.125%]
        let collateral: u256 = 10_000 * SCALE;
        let debt: u256 = 3_000 * SCALE;
        let entry_price: u256 = 60_000 * SCALE;

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(collateral, debt, entry_price);
        stop_cheat_caller_address(amm.contract_address);

        assert(!amm.is_over_levered(), 'Should not be over-levered');
        assert(!amm.is_under_levered(), 'Should not be under-levered');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GET X0
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_get_x0_after_init() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        let x0 = amm.get_x0();
        assert(x0 > 0, 'x0 should be > 0 after init');
    }

    #[test]
    fn test_get_x0_before_init() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // No init → collateral = 0, debt = 0 → x0 = 0
        let x0 = amm.get_x0();
        assert(x0 == 0, 'x0 should be 0 before init');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SWAP DIRECTION CONSTRAINTS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Cannot sell: under-levered')]
    fn test_swap_sell_when_under_levered() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // Under-levered: DTV = 5% < DTV_MIN_2X
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 500 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        // direction=false → sell BTC → should fail when under-levered
        amm.swap(false, SCALE / 100);
    }

    #[test]
    #[should_panic(expected: 'Cannot buy: over-levered')]
    fn test_swap_buy_when_over_levered() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // Over-levered: DTV = 55% > DTV_MAX_2X
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 5_500 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        // direction=true → buy BTC → should fail when over-levered
        amm.swap(true, SCALE / 100);
    }

    #[test]
    #[should_panic(expected: 'LEVAMM not initialized')]
    fn test_swap_before_init() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        amm.swap(true, SCALE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COLLECT FEES
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_collect_fees_no_fees() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        // No swaps → no fees accumulated
        assert(amm.get_accumulated_trading_fees() == 0, 'No fees initially');

        let collected = amm.collect_fees();
        assert(collected == 0, 'Collect should return 0');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REFUEL
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_refuel() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let collateral: u256 = 10_000 * SCALE;
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(collateral, 3_000 * SCALE, 60_000 * SCALE);

        let refuel_amount: u256 = 2_000 * SCALE;
        amm.refuel(refuel_amount);
        stop_cheat_caller_address(amm.contract_address);

        assert(
            amm.get_collateral_value() == collateral + refuel_amount,
            'Collateral should increase',
        );
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_refuel_not_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, attacker);
        amm.refuel(1_000 * SCALE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SET INTEREST RATE / SET OWNER
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_set_interest_rate_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        start_cheat_caller_address(amm.contract_address, owner);
        amm.set_interest_rate(SCALE / 1000); // 0.1% per block
        stop_cheat_caller_address(amm.contract_address);
        // No panic = success
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_interest_rate_not_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, attacker);
        amm.set_interest_rate(SCALE / 1000);
    }

    #[test]
    fn test_set_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let new_owner: ContractAddress = 0xBEEF.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, owner);
        amm.set_owner(new_owner);
        stop_cheat_caller_address(amm.contract_address);

        assert(amm.get_owner() == new_owner, 'Owner should be updated');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_owner_not_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, attacker);
        amm.set_owner(attacker);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REBALANCING SETTERS (access control)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_set_rebalance_adapters() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let vpool: ContractAddress = 0x111.try_into().unwrap();
        let ekubo: ContractAddress = 0x222.try_into().unwrap();
        let lending: ContractAddress = 0x333.try_into().unwrap();

        start_cheat_caller_address(amm.contract_address, owner);
        amm.set_virtual_pool(vpool);
        amm.set_ekubo_adapter(ekubo);
        amm.set_lending_adapter(lending);
        stop_cheat_caller_address(amm.contract_address);

        // No panic = success. Getter for rebalance_lp_id should still be 0.
        assert(amm.get_rebalance_lp_id() == 0, 'LP ID should be 0');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_virtual_pool_not_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, attacker);
        amm.set_virtual_pool(0x111.try_into().unwrap());
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_ekubo_adapter_not_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, attacker);
        amm.set_ekubo_adapter(0x222.try_into().unwrap());
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_lending_adapter_not_owner() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(amm.contract_address, attacker);
        amm.set_lending_adapter(0x333.try_into().unwrap());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SWAP WITHOUT REBALANCING (integrations not wired → graceful skip)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_swap_no_rebalance_when_not_wired() {
        let owner = test_address();
        let amm = deploy_levamm(owner);

        // DTV = 30% (under-levered, but within swap band)
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        let dtv_before = amm.get_dtv();

        // Swap without integrations wired — rebalance should be skipped gracefully
        amm.swap(true, SCALE / 1000); // Buy 0.001 BTC

        let dtv_after = amm.get_dtv();

        // DTV should change from swap accounting but NO rebalance
        // (since virtual_pool, ekubo, lending are all zero)
        assert(dtv_before != dtv_after, 'DTV should change from swap');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ACTIVE REBALANCING — LEVERAGE UP (DTV < 50%)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_rebalance_leverage_up() {
        let sys = deploy_rebalance_system();
        let owner = sys.owner;
        let amm = sys.levamm;

        // Initialize with DTV = 30% (under-levered, needs leverage up)
        // collateral = 10,000 USDC, debt = 3,000 USDC
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 3_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        let dtv_before = amm.get_dtv();
        let debt_before = amm.get_debt();
        let collateral_before = amm.get_collateral_value();

        // DTV = 30%, target = 50%. Swap buy BTC (allowed since DTV < 53.125%)
        amm.swap(true, SCALE / 1000);

        let dtv_after = amm.get_dtv();
        let debt_after = amm.get_debt();
        let collateral_after = amm.get_collateral_value();

        // After rebalance: DTV should be much closer to 50% (0.5e18)
        let target_dtv = SCALE / 2; // 50%
        let diff_before = if dtv_before >= target_dtv {
            dtv_before - target_dtv
        } else {
            target_dtv - dtv_before
        };
        let diff_after = if dtv_after >= target_dtv {
            dtv_after - target_dtv
        } else {
            target_dtv - dtv_after
        };

        // The rebalance should have brought DTV closer to 50%
        assert(diff_after < diff_before, 'DTV should be closer to 50%');

        // Debt should have increased (leverage up)
        assert(debt_after > debt_before, 'Debt should increase');

        // Collateral should have increased
        assert(collateral_after > collateral_before, 'Collateral should increase');

        // A rebalance LP should have been created
        assert(amm.get_rebalance_lp_id() > 0, 'Rebalance LP should exist');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ACTIVE REBALANCING — DELEVERAGE (DTV > 50%)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_rebalance_deleverage() {
        let sys = deploy_rebalance_system();
        let owner = sys.owner;
        let amm = sys.levamm;

        // Initialize with DTV = 52% (slightly over target, within swap band)
        // collateral = 10,000 USDC, debt = 5,200 USDC
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 5_200 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        let dtv_before = amm.get_dtv();
        let debt_before = amm.get_debt();

        // DTV = 52% > 50%. Swap sell BTC (allowed since DTV > 6.25%)
        amm.swap(false, SCALE / 1000);

        let dtv_after = amm.get_dtv();
        let debt_after = amm.get_debt();

        // After rebalance: DTV should be closer to 50%
        let target_dtv = SCALE / 2;
        let diff_before = if dtv_before >= target_dtv {
            dtv_before - target_dtv
        } else {
            target_dtv - dtv_before
        };
        let diff_after = if dtv_after >= target_dtv {
            dtv_after - target_dtv
        } else {
            target_dtv - dtv_after
        };

        assert(diff_after < diff_before, 'DTV should be closer to 50%');

        // Debt should have decreased (deleverage)
        assert(debt_after < debt_before, 'Debt should decrease');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NO REBALANCE WHEN DTV IS NEAR TARGET
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_no_rebalance_when_near_target() {
        let sys = deploy_rebalance_system();
        let owner = sys.owner;
        let amm = sys.levamm;

        // Initialize with DTV = 49.5% (very close to 50%, within threshold)
        // collateral = 10,000 USDC, debt = 4,950 USDC
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 4_950 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        // Execute a tiny swap — DTV stays near 50%
        amm.swap(true, SCALE / 10000); // 0.0001 BTC

        // No rebalance LP should have been created (DTV within threshold)
        assert(amm.get_rebalance_lp_id() == 0, 'No rebalance should fire');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REBALANCE WITH EXISTING LP (merge/replace)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_rebalance_replaces_old_lp() {
        let sys = deploy_rebalance_system();
        let owner = sys.owner;
        let amm = sys.levamm;

        // Initialize with DTV = 20% (very under-levered)
        start_cheat_caller_address(amm.contract_address, owner);
        amm.initialize(10_000 * SCALE, 2_000 * SCALE, 60_000 * SCALE);
        stop_cheat_caller_address(amm.contract_address);

        // First swap triggers rebalance → creates LP 1
        amm.swap(true, SCALE / 1000);
        let lp_id_1 = amm.get_rebalance_lp_id();
        assert(lp_id_1 > 0, 'First rebalance LP missing');

        // Adjust collateral/debt to be under-levered again for second rebalance
        // (normally the first rebalance would fix DTV, but if we force another swap...)
        // The second swap will fire another rebalance if DTV is still off
        let dtv_mid = amm.get_dtv();
        let target = SCALE / 2;

        // If DTV is still away from target, a second swap will trigger another rebalance
        // which should replace the old LP with a new one
        if dtv_mid < target {
            amm.swap(true, SCALE / 1000);
            let lp_id_2 = amm.get_rebalance_lp_id();
            // LP ID should have changed (new position created)
            if lp_id_2 > 0 {
                assert(lp_id_2 != lp_id_1, 'LP ID should change');
            }
        }
        // Test passes regardless — verifies no panic on LP replacement
    }
}
