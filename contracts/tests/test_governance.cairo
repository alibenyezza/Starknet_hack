//! Tests for Governance contracts (VotingEscrow + GaugeController)

use starknet::ContractAddress;
use starkyield::governance::voting_escrow::{
    IVotingEscrowDispatcher, IVotingEscrowDispatcherTrait,
};
use starkyield::governance::gauge_controller::{
    IGaugeControllerDispatcher, IGaugeControllerDispatcherTrait,
};
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    const SCALE: u256 = 1_000000000000000000;

    // ═══════════════════════════════════════════════════════
    // DEPLOY HELPERS
    // ═══════════════════════════════════════════════════════

    /// Deploy VotingEscrow with constructor(owner, sy_token).
    fn deploy_voting_escrow(
        owner: ContractAddress,
        sy_token: ContractAddress,
    ) -> IVotingEscrowDispatcher {
        let contract_class = declare("VotingEscrow").unwrap().contract_class();
        let calldata = array![
            owner.into(),       // owner
            sy_token.into(), // sy_token
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        IVotingEscrowDispatcher { contract_address }
    }

    /// Deploy GaugeController with constructor(owner, vesy_token).
    fn deploy_gauge_controller(
        owner: ContractAddress,
        vesy_token: ContractAddress,
    ) -> IGaugeControllerDispatcher {
        let contract_class = declare("GaugeController").unwrap().contract_class();
        let calldata = array![
            owner.into(),        // owner
            vesy_token.into(), // vesy_token
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        IGaugeControllerDispatcher { contract_address }
    }

    // ═══════════════════════════════════════════════════════
    // VOTING ESCROW — DEPLOY & INITIAL STATE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_voting_escrow_deploy() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let ve = deploy_voting_escrow(owner, zero);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        assert(ve.get_locked_balance(user) == 0, 'Locked balance should be 0');
        assert(ve.get_voting_power(user) == 0, 'Voting power should be 0');
        assert(ve.get_lock_end(user) == 0, 'Lock end should be 0');
    }

    #[test]
    fn test_voting_escrow_locked_balance_initially_zero() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let ve = deploy_voting_escrow(owner, zero);

        assert(ve.get_locked_balance(owner) == 0, 'Owner locked should be 0');

        let random: ContractAddress = 0xABC.try_into().unwrap();
        assert(ve.get_locked_balance(random) == 0, 'Random locked should be 0');
    }

    #[test]
    fn test_voting_escrow_voting_power_zero_no_lock() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let ve = deploy_voting_escrow(owner, zero);

        assert(ve.get_voting_power(owner) == 0, 'Power should be 0 with no lock');
    }

    #[test]
    fn test_voting_escrow_lock_end_zero() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let ve = deploy_voting_escrow(owner, zero);

        assert(ve.get_lock_end(owner) == 0, 'Lock end should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // VOTING ESCROW — LOCK VALIDATION
    // ═══════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Amount must be > 0')]
    fn test_voting_escrow_lock_zero_amount() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let ve = deploy_voting_escrow(owner, zero);

        start_cheat_caller_address(ve.contract_address, owner);
        ve.lock(0, 1000000);
    }

    #[test]
    #[should_panic(expected: 'Nothing locked')]
    fn test_voting_escrow_unlock_without_lock() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let ve = deploy_voting_escrow(owner, zero);

        start_cheat_caller_address(ve.contract_address, owner);
        ve.unlock();
    }

    #[test]
    #[should_panic(expected: 'No existing lock')]
    fn test_voting_escrow_increase_without_lock() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let ve = deploy_voting_escrow(owner, zero);

        start_cheat_caller_address(ve.contract_address, owner);
        ve.increase_amount(100 * SCALE);
    }

    // ═══════════════════════════════════════════════════════
    // GAUGE CONTROLLER — DEPLOY & INITIAL STATE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_gauge_controller_deploy() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        assert(gc.get_total_weight() == 0, 'Total weight should be 0');
    }

    #[test]
    fn test_gauge_controller_total_weight_zero() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        assert(gc.get_total_weight() == 0, 'Total weight should be 0');
    }

    #[test]
    fn test_gauge_controller_gauge_weight_zero() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let gauge: ContractAddress = 0x1234.try_into().unwrap();
        assert(gc.get_gauge_weight(gauge) == 0, 'Gauge weight should be 0');
    }

    #[test]
    fn test_gauge_controller_voter_weight_zero() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let voter: ContractAddress = 0x1234.try_into().unwrap();
        let gauge: ContractAddress = 0x5678.try_into().unwrap();
        assert(gc.get_voter_weight(voter, gauge) == 0, 'Voter weight should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // GAUGE CONTROLLER — ADD GAUGE (owner only)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_add_gauge_by_owner() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let gauge: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(gc.contract_address, owner);
        gc.add_gauge(gauge, 1);
        stop_cheat_caller_address(gc.contract_address);

        // Gauge was added — weight still 0 but gauge is active (no panic on vote)
        assert(gc.get_gauge_weight(gauge) == 0, 'Weight should be 0');
        assert(gc.get_total_weight() == 0, 'Total weight should still be 0');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_add_gauge_not_owner() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        let gauge: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(gc.contract_address, attacker);
        gc.add_gauge(gauge, 1);
    }

    // ═══════════════════════════════════════════════════════
    // GAUGE CONTROLLER — VOTE VALIDATION
    // ═══════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Gauge not active')]
    fn test_vote_for_inactive_gauge() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let gauge: ContractAddress = 0x1234.try_into().unwrap();
        // Don't add gauge → it's not active
        start_cheat_caller_address(gc.contract_address, owner);
        gc.vote_for_gauge(gauge, 100 * SCALE);
    }

    #[test]
    fn test_vote_with_zero_weight() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let gauge: ContractAddress = 0x1234.try_into().unwrap();

        // Add gauge first
        start_cheat_caller_address(gc.contract_address, owner);
        gc.add_gauge(gauge, 1);

        // Vote with 0 weight (vesy_token is zero → balance check skipped)
        gc.vote_for_gauge(gauge, 0);
        stop_cheat_caller_address(gc.contract_address);

        assert(gc.get_gauge_weight(gauge) == 0, 'Weight should remain 0');
        assert(gc.get_total_weight() == 0, 'Total weight should remain 0');
    }

    // ═══════════════════════════════════════════════════════
    // GAUGE CONTROLLER — MULTIPLE GAUGES
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_add_multiple_gauges() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let gauge1: ContractAddress = 0x1111.try_into().unwrap();
        let gauge2: ContractAddress = 0x2222.try_into().unwrap();

        start_cheat_caller_address(gc.contract_address, owner);
        gc.add_gauge(gauge1, 1);
        gc.add_gauge(gauge2, 2);
        stop_cheat_caller_address(gc.contract_address);

        // Both gauges added with zero weight
        assert(gc.get_gauge_weight(gauge1) == 0, 'Gauge1 weight should be 0');
        assert(gc.get_gauge_weight(gauge2) == 0, 'Gauge2 weight should be 0');
        assert(gc.get_total_weight() == 0, 'Total weight should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // GAUGE CONTROLLER — VOTE (vesy_token = zero → skip balance check)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_vote_for_gauge_updates_weights() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let gauge: ContractAddress = 0x1234.try_into().unwrap();
        let voter: ContractAddress = 0xABCD.try_into().unwrap();

        start_cheat_caller_address(gc.contract_address, owner);
        gc.add_gauge(gauge, 1);
        stop_cheat_caller_address(gc.contract_address);

        // Vote (vesy_token is zero → balance check is skipped)
        let weight: u256 = 500 * SCALE;
        start_cheat_caller_address(gc.contract_address, voter);
        gc.vote_for_gauge(gauge, weight);
        stop_cheat_caller_address(gc.contract_address);

        assert(gc.get_gauge_weight(gauge) == weight, 'Gauge weight should match');
        assert(gc.get_total_weight() == weight, 'Total weight should match');
        assert(gc.get_voter_weight(voter, gauge) == weight, 'Voter weight should match');
    }

    #[test]
    fn test_vote_retract_previous() {
        let owner = test_address();
        let zero: ContractAddress = 0.try_into().unwrap();
        let gc = deploy_gauge_controller(owner, zero);

        let gauge: ContractAddress = 0x1234.try_into().unwrap();
        let voter: ContractAddress = 0xABCD.try_into().unwrap();

        start_cheat_caller_address(gc.contract_address, owner);
        gc.add_gauge(gauge, 1);
        stop_cheat_caller_address(gc.contract_address);

        // First vote
        start_cheat_caller_address(gc.contract_address, voter);
        gc.vote_for_gauge(gauge, 500 * SCALE);

        // Second vote (should retract first)
        gc.vote_for_gauge(gauge, 300 * SCALE);
        stop_cheat_caller_address(gc.contract_address);

        assert(gc.get_gauge_weight(gauge) == 300 * SCALE, 'Weight should be updated');
        assert(gc.get_total_weight() == 300 * SCALE, 'Total should be updated');
        assert(gc.get_voter_weight(voter, gauge) == 300 * SCALE, 'Voter weight updated');
    }
}
