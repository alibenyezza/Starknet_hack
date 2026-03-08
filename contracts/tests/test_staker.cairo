//! Tests for Staker contract (MasterChef-style staking)

use starknet::ContractAddress;
use starkyield::staker::staker::{IStakerDispatcher, IStakerDispatcherTrait};
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    const SCALE: u256 = 1_000000000000000000;

    /// Deploy Staker with constructor(owner, stake_token, sy_token, initial_reward_rate).
    /// Token addresses set to zero for view-only tests.
    fn deploy_staker(owner: ContractAddress, initial_reward_rate: u256) -> IStakerDispatcher {
        let zero: ContractAddress = 0.try_into().unwrap();
        let contract_class = declare("Staker").unwrap().contract_class();
        let calldata = array![
            owner.into(),                       // owner
            zero.into(),                        // stake_token (LT)
            zero.into(),                        // sy_token
            initial_reward_rate.low.into(),      // initial_reward_rate (u256 low)
            initial_reward_rate.high.into(),     // initial_reward_rate (u256 high)
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        IStakerDispatcher { contract_address }
    }

    // ═══════════════════════════════════════════════════════
    // DEPLOYMENT & INITIAL STATE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_deploy_initial_state() {
        let owner = test_address();
        let reward_rate: u256 = 1_000_000_000_000; // 1e12
        let staker = deploy_staker(owner, reward_rate);

        assert(staker.get_total_staked() == 0, 'Total staked should be 0');
        assert(staker.get_acc_reward_per_share() == 0, 'Acc reward should be 0');
        assert(staker.get_owner() == owner, 'Owner should match');
    }

    #[test]
    fn test_deploy_reward_rate() {
        let owner = test_address();
        let reward_rate: u256 = 1_000_000_000_000; // 1e12
        let staker = deploy_staker(owner, reward_rate);

        assert(staker.get_reward_rate() == reward_rate, 'Reward rate should match');
    }

    // ═══════════════════════════════════════════════════════
    // GET REWARD RATE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_get_reward_rate_returns_initial() {
        let owner = test_address();
        let reward_rate: u256 = 5_000_000_000_000; // 5e12
        let staker = deploy_staker(owner, reward_rate);

        assert(staker.get_reward_rate() == reward_rate, 'Should return initial rate');
    }

    // ═══════════════════════════════════════════════════════
    // SET REWARD RATE (owner only)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_set_reward_rate_owner() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let new_rate: u256 = 2_000_000_000_000;
        start_cheat_caller_address(staker.contract_address, owner);
        staker.set_reward_rate(new_rate);
        stop_cheat_caller_address(staker.contract_address);

        assert(staker.get_reward_rate() == new_rate, 'Rate should be updated');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_reward_rate_not_owner() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, attacker);
        staker.set_reward_rate(0);
    }

    // ═══════════════════════════════════════════════════════
    // GET TOTAL STAKED
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_get_total_staked_initially_zero() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        assert(staker.get_total_staked() == 0, 'Total staked should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // GET STAKED BALANCE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_get_staked_balance_unknown_user() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let random_user: ContractAddress = 0x1234.try_into().unwrap();
        assert(staker.get_staked_balance(random_user) == 0, 'Balance should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // PENDING REWARDS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_pending_rewards_no_stake() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        assert(staker.pending_rewards(user) == 0, 'No pending for unstaked user');
    }

    // ═══════════════════════════════════════════════════════
    // SET SY_TOKEN (owner only)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_set_sy_token_owner() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let new_token: ContractAddress = 0xABC.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, owner);
        staker.set_sy_token(new_token);
        stop_cheat_caller_address(staker.contract_address);
        // No panic = success
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_sy_token_not_owner() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, attacker);
        staker.set_sy_token(0xABC.try_into().unwrap());
    }

    // ═══════════════════════════════════════════════════════
    // SET OWNER (owner only)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_set_owner() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let new_owner: ContractAddress = 0xBEEF.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, owner);
        staker.set_owner(new_owner);
        stop_cheat_caller_address(staker.contract_address);

        assert(staker.get_owner() == new_owner, 'Owner should be updated');
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_owner_not_owner() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, attacker);
        staker.set_owner(attacker);
    }

    // ═══════════════════════════════════════════════════════
    // STAKE VALIDATION
    // ═══════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Amount must be > 0')]
    fn test_stake_zero_amount() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(0);
    }

    // ═══════════════════════════════════════════════════════
    // UNSTAKE VALIDATION
    // ═══════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Insufficient staked balance')]
    fn test_unstake_without_stake() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, user);
        staker.unstake(100 * SCALE);
    }

    // ═══════════════════════════════════════════════════════
    // DIFFERENT INITIAL REWARD RATES
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_deploy_with_zero_reward_rate() {
        let owner = test_address();
        let staker = deploy_staker(owner, 0);

        assert(staker.get_reward_rate() == 0, 'Rate should be 0');
        assert(staker.get_total_staked() == 0, 'Total staked should be 0');
    }

    #[test]
    fn test_deploy_with_large_reward_rate() {
        let owner = test_address();
        let large_rate: u256 = SCALE; // 1e18
        let staker = deploy_staker(owner, large_rate);

        assert(staker.get_reward_rate() == large_rate, 'Rate should be 1e18');
    }
}
