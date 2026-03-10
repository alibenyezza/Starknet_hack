//! Tests for FeeDistributor contract

use starknet::ContractAddress;
use starkyield::fees::fee_distributor::{IFeeDistributorDispatcher, IFeeDistributorDispatcherTrait};
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    const SCALE: u256 = 1_000000000000000000;

    /// Deploy FeeDistributor with constructor(owner, usdc_token).
    fn deploy_fee_distributor(owner: ContractAddress) -> IFeeDistributorDispatcher {
        let zero: ContractAddress = 0.try_into().unwrap();
        let contract_class = declare("FeeDistributor").unwrap().contract_class();
        let calldata = array![
            owner.into(),  // owner
            zero.into(),   // usdc_token
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        IFeeDistributorDispatcher { contract_address }
    }

    // ═══════════════════════════════════════════════════════
    // DEPLOYMENT & INITIAL STATE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_deploy_initial_state() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        assert(!fd.is_recovery_mode(), 'Recovery mode should be false');
        assert(fd.get_accumulated_holder_fees() == 0, 'Holder fees should be 0');
        assert(fd.get_accumulated_vesy_fees() == 0, 'VeSY fees should be 0');
        assert(fd.get_accumulated_recovery_fees() == 0, 'Recovery fees should be 0');
        assert(fd.get_accumulated_interest() == 0, 'Interest should be 0');
        assert(fd.get_pending_volatility_decay() == 0, 'Volatility decay should be 0');
        assert(fd.get_total_fees_distributed() == 0, 'Total distributed should be 0');
    }

    #[test]
    fn test_deploy_owner() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        assert(fd.get_owner() == owner, 'Owner should match');
    }

    // ═══════════════════════════════════════════════════════
    // COMPUTE ADMIN FEE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_compute_admin_fee_zero_staked() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // 0% staked → f_a = 1 - (1 - 0.1) * sqrt(1 - 0) = 1 - 0.9 * 1 = 0.1 (10%)
        let fee = fd.compute_admin_fee(0, 100 * SCALE);
        let min_admin = SCALE / 10; // 0.1e18 = 10%

        // Should be approximately 10% (MIN_ADMIN_FEE)
        let tolerance = SCALE / 100; // 1%
        assert(fee >= min_admin - tolerance, 'Fee too low for 0% staked');
        assert(fee <= min_admin + tolerance, 'Fee too high for 0% staked');
    }

    #[test]
    fn test_compute_admin_fee_all_staked() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // 100% staked → f_a = 1 - (1 - 0.1) * sqrt(1 - 1) = 1 - 0 = 1 (100%)
        let fee = fd.compute_admin_fee(100 * SCALE, 100 * SCALE);

        assert(fee == SCALE, 'Fee 100% when all staked');
    }

    #[test]
    fn test_compute_admin_fee_zero_total() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // total_lt = 0 → returns MIN_ADMIN_FEE
        let fee = fd.compute_admin_fee(0, 0);
        let min_admin = SCALE / 10;
        assert(fee == min_admin, 'Should return min fee 0 total');
    }

    #[test]
    fn test_compute_admin_fee_half_staked() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // 50% staked: f_a = 1 - 0.9 * sqrt(0.5)
        // sqrt(0.5) ≈ 0.7071 → f_a ≈ 1 - 0.6364 ≈ 0.3636 (36.36%)
        let fee = fd.compute_admin_fee(50 * SCALE, 100 * SCALE);

        let min_expected = SCALE * 30 / 100; // 30%
        let max_expected = SCALE * 40 / 100; // 40%
        assert(fee >= min_expected, 'Fee too low for 50% staked');
        assert(fee <= max_expected, 'Fee too high for 50% staked');
    }

    // ═══════════════════════════════════════════════════════
    // DISTRIBUTE — RECOVERY MODE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_distribute_recovery_mode() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // Enable recovery mode
        start_cheat_caller_address(fd.contract_address, owner);
        fd.set_recovery_mode(true);
        stop_cheat_caller_address(fd.contract_address);

        assert(fd.is_recovery_mode(), 'Recovery mode should be true');

        // Distribute — all should go to recovery accumulator
        let dist_amount: u256 = 1000 * SCALE;
        fd.distribute(dist_amount);

        assert(fd.get_accumulated_recovery_fees() == dist_amount, 'All should go to recovery');
        assert(fd.get_accumulated_holder_fees() == 0, 'Holder fees should be 0');
        assert(fd.get_accumulated_vesy_fees() == 0, 'VeSY fees should be 0');
        assert(fd.get_total_fees_distributed() == dist_amount, 'Total should match');
    }

    // ═══════════════════════════════════════════════════════
    // DISTRIBUTE — NORMAL MODE (no staker/lt_token set → 0/0)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_distribute_normal_mode_no_staker() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // No staker or lt_token set → _get_staking_info returns (0, 0)
        // compute_admin_fee(0, 0) → MIN_ADMIN_FEE (10%)
        let dist_amount: u256 = 1000 * SCALE;
        fd.distribute(dist_amount);

        // With min admin fee (10%):
        // vesy_share = dist_amount * 0.1 = 100 * SCALE
        // holder_share = dist_amount * 0.9 = 900 * SCALE
        let vesy = fd.get_accumulated_vesy_fees();
        let holder = fd.get_accumulated_holder_fees();

        // Allow small tolerance for fixed-point rounding
        let tolerance = SCALE; // 1 unit
        let expected_vesy = 100 * SCALE;
        let expected_holder = 900 * SCALE;

        assert(vesy >= expected_vesy - tolerance, 'VeSY share too low');
        assert(vesy <= expected_vesy + tolerance, 'VeSY share too high');
        assert(holder >= expected_holder - tolerance, 'Holder share too low');
        assert(holder <= expected_holder + tolerance, 'Holder share too high');

        // Total should always match
        assert(fd.get_total_fees_distributed() == dist_amount, 'Total should match');
    }

    #[test]
    fn test_distribute_zero_amount() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        fd.distribute(0);

        assert(fd.get_total_fees_distributed() == 0, 'No fees on zero dist');
        assert(fd.get_accumulated_holder_fees() == 0, 'Holder should be 0');
        assert(fd.get_accumulated_vesy_fees() == 0, 'VeSY should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // RECORD VOLATILITY DECAY
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_record_volatility_decay() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        let decay: u256 = 50 * SCALE;
        fd.record_volatility_decay(decay);

        assert(fd.get_pending_volatility_decay() == decay, 'Decay should be recorded');
    }

    #[test]
    fn test_distribute_with_volatility_decay() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // Record 200 decay first
        let decay: u256 = 200 * SCALE;
        fd.record_volatility_decay(decay);

        // Distribute 1000 — should deduct 200 decay, net = 800
        let dist_amount: u256 = 1000 * SCALE;
        fd.distribute(dist_amount);

        // After deduction, pending_volatility_decay should be 0
        assert(fd.get_pending_volatility_decay() == 0, 'Decay should be consumed');

        // Sum of holder + vesy should equal 800 * SCALE (net after decay)
        let holder = fd.get_accumulated_holder_fees();
        let vesy = fd.get_accumulated_vesy_fees();
        let net_amount = 800 * SCALE;

        let tolerance = SCALE; // 1 unit for rounding
        assert(holder + vesy >= net_amount - tolerance, 'Net too low after decay');
        assert(holder + vesy <= net_amount + tolerance, 'Net too high after decay');
    }

    #[test]
    fn test_distribute_decay_exceeds_amount() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        // Decay is larger than dist_amount → net = 0, all absorbed
        let decay: u256 = 2000 * SCALE;
        fd.record_volatility_decay(decay);

        let dist_amount: u256 = 500 * SCALE;
        fd.distribute(dist_amount);

        // Remaining decay = 2000 - 500 = 1500
        assert(fd.get_pending_volatility_decay() == 1500 * SCALE, 'Remaining decay wrong');
        assert(fd.get_accumulated_holder_fees() == 0, 'Holder should be 0');
        assert(fd.get_accumulated_vesy_fees() == 0, 'VeSY should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // RECORD INTEREST
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_record_interest() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        let interest: u256 = 300 * SCALE;
        fd.record_interest(interest);

        assert(fd.get_accumulated_interest() == interest, 'Interest should be recorded');
    }

    #[test]
    fn test_record_interest_zero() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        fd.record_interest(0);
        assert(fd.get_accumulated_interest() == 0, 'Interest should remain 0');
    }

    // ═══════════════════════════════════════════════════════
    // SET RECOVERY MODE (owner only)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_set_recovery_mode_owner() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        start_cheat_caller_address(fd.contract_address, owner);
        fd.set_recovery_mode(true);
        stop_cheat_caller_address(fd.contract_address);

        assert(fd.is_recovery_mode(), 'Should be in recovery mode');

        start_cheat_caller_address(fd.contract_address, owner);
        fd.set_recovery_mode(false);
        stop_cheat_caller_address(fd.contract_address);

        assert(!fd.is_recovery_mode(), 'Should not be in recovery mode');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_recovery_mode_not_owner() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(fd.contract_address, attacker);
        fd.set_recovery_mode(true);
    }

    // ═══════════════════════════════════════════════════════
    // SET STAKER / SET LT TOKEN (owner only)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_set_staker_owner() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        let staker_addr: ContractAddress = 0xABC.try_into().unwrap();
        start_cheat_caller_address(fd.contract_address, owner);
        fd.set_staker(staker_addr);
        stop_cheat_caller_address(fd.contract_address);
        // No panic = success (staker is internal, no getter)
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_staker_not_owner() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(fd.contract_address, attacker);
        fd.set_staker(0xABC.try_into().unwrap());
    }

    #[test]
    fn test_set_lt_token_owner() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        let lt_addr: ContractAddress = 0xDEF.try_into().unwrap();
        start_cheat_caller_address(fd.contract_address, owner);
        fd.set_lt_token(lt_addr);
        stop_cheat_caller_address(fd.contract_address);
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_lt_token_not_owner() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(fd.contract_address, attacker);
        fd.set_lt_token(0xDEF.try_into().unwrap());
    }

    // ═══════════════════════════════════════════════════════
    // MULTIPLE DISTRIBUTIONS ACCUMULATE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_multiple_distributions_accumulate() {
        let owner = test_address();
        let fd = deploy_fee_distributor(owner);

        fd.distribute(100 * SCALE);
        fd.distribute(200 * SCALE);

        assert(fd.get_total_fees_distributed() == 300 * SCALE, 'Total should accumulate');

        let holder = fd.get_accumulated_holder_fees();
        let vesy = fd.get_accumulated_vesy_fees();
        let tolerance = SCALE; // rounding tolerance
        assert(holder + vesy >= 300 * SCALE - tolerance, 'Sum too low');
        assert(holder + vesy <= 300 * SCALE + tolerance, 'Sum too high');
    }
}
