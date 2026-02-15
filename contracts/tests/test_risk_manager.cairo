//! Tests for Risk Manager

use starknet::ContractAddress;
use starkyield::risk::risk_manager::{IRiskManagerDispatcher, IRiskManagerDispatcherTrait};
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    const SCALE: u256 = 1_000000000000000000;

    fn deploy_risk_manager(owner: ContractAddress, max_daily: u256) -> IRiskManagerDispatcher {
        let contract_class = declare("RiskManager").unwrap().contract_class();
        let calldata = array![
            owner.into(),
            max_daily.low.into(),
            max_daily.high.into()
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        IRiskManagerDispatcher { contract_address }
    }

    #[test]
    fn test_assess_health_safe() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.assess_health(3 * SCALE) == 0, 'HF 3.0 should be Safe');
    }

    #[test]
    fn test_assess_health_moderate() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.assess_health(1_700000000000000000) == 1, 'HF 1.7 should be Moderate');
    }

    #[test]
    fn test_assess_health_warning() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.assess_health(1_300000000000000000) == 2, 'HF 1.3 should be Warning');
    }

    #[test]
    fn test_assess_health_danger() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.assess_health(1_100000000000000000) == 3, 'HF 1.1 should be Danger');
    }

    #[test]
    fn test_price_sanity_small_change() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.check_price_sanity(61000 * SCALE, 60000 * SCALE), 'Small change should be sane');
    }

    #[test]
    fn test_price_sanity_large_change() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(!rm.check_price_sanity(48000 * SCALE, 60000 * SCALE), 'Large change not sane');
    }

    #[test]
    fn test_price_sanity_first_price() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.check_price_sanity(60000 * SCALE, 0), 'First price always sane');
    }

    #[test]
    fn test_withdrawal_within_limit() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.check_withdrawal_limit(50 * SCALE), 'Should allow within limit');
    }

    #[test]
    fn test_withdrawal_exceeds_limit() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);

        start_cheat_caller_address(rm.contract_address, owner);
        rm.record_withdrawal(80 * SCALE);
        stop_cheat_caller_address(rm.contract_address);

        assert(!rm.check_withdrawal_limit(30 * SCALE), 'Should reject over limit');
    }

    #[test]
    fn test_withdrawal_no_limit() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 0);
        assert(rm.check_withdrawal_limit(999999 * SCALE), 'No limit = always allowed');
    }

    #[test]
    fn test_reset_daily_withdrawals() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);

        start_cheat_caller_address(rm.contract_address, owner);
        rm.record_withdrawal(90 * SCALE);

        assert(!rm.check_withdrawal_limit(20 * SCALE), 'Should be over limit');

        rm.reset_daily_withdrawals();
        stop_cheat_caller_address(rm.contract_address);

        assert(rm.check_withdrawal_limit(20 * SCALE), 'Should allow after reset');
    }

    #[test]
    fn test_needs_rebalance_large_deviation() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(rm.needs_rebalance(2_500000000000000000, 2 * SCALE), 'Should need rebalance');
    }

    #[test]
    fn test_no_rebalance_small_deviation() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        assert(!rm.needs_rebalance(2_050000000000000000, 2 * SCALE), 'Should not need rebalance');
    }

    #[test]
    fn test_deleverage_already_at_target() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        let amount = rm.calculate_deleverage_amount(
            2 * SCALE, 1_500000000000000000, 1000 * SCALE, 500 * SCALE
        );
        assert(amount == 0, 'No deleverage if HF is fine');
    }

    #[test]
    fn test_deleverage_no_debt() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);
        let amount = rm.calculate_deleverage_amount(999 * SCALE, SCALE, 1000 * SCALE, 0);
        assert(amount == 0, 'No deleverage if no debt');
    }

    #[test]
    fn test_set_max_daily_withdrawal() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);

        start_cheat_caller_address(rm.contract_address, owner);
        rm.set_max_daily_withdrawal(200 * SCALE);
        stop_cheat_caller_address(rm.contract_address);

        assert(rm.get_max_daily_withdrawal() == 200 * SCALE, 'Max should be updated');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_max_daily_withdrawal_not_owner() {
        let owner = test_address();
        let rm = deploy_risk_manager(owner, 100 * SCALE);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(rm.contract_address, attacker);
        rm.set_max_daily_withdrawal(0);
    }
}
