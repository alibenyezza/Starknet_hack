//! Tests for Staker contract (MasterChef-style staking)
//!
//! Covers: deployment, view-only state, full stake/unstake flows with real tokens,
//! reward accumulation, multi-user proportionality, zero-address validation.

use starknet::ContractAddress;
use starkyield::staker::staker::{IStakerDispatcher, IStakerDispatcherTrait};
use starkyield::vault::lt_token::{ILtTokenDispatcher, ILtTokenDispatcherTrait};
use starkyield::governance::sy_token::ISyTokenDispatcher;
use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use core::traits::TryInto;

/// Minimal Ownable facade — used to call transfer_ownership on SyToken
#[starknet::interface]
trait IOwnableFacade<TContractState> {
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    fn owner(self: @TContractState) -> ContractAddress;
}

/// Minimal ERC20 balance facade
#[starknet::interface]
trait IERC20BalanceFacade<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_number_global,
    };

    const SCALE: u256 = 1_000000000000000000;

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOY HELPERS
    // ═══════════════════════════════════════════════════════════════════════

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

    /// Deploy Staker with real token addresses
    fn deploy_staker_full(
        owner: ContractAddress,
        lt_addr: ContractAddress,
        sy_addr: ContractAddress,
        rate: u256,
    ) -> IStakerDispatcher {
        let contract_class = declare("Staker").unwrap().contract_class();
        let calldata = array![
            owner.into(),
            lt_addr.into(),
            sy_addr.into(),
            rate.low.into(),
            rate.high.into(),
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        IStakerDispatcher { contract_address }
    }

    /// Deploy LtToken (constructor: name, symbol, owner)
    fn deploy_lt_token(owner: ContractAddress) -> (ContractAddress, ILtTokenDispatcher) {
        let contract_class = declare("LtToken").unwrap().contract_class();
        let mut calldata: Array<felt252> = array![];
        // name: ByteArray "LT Token"
        calldata.append(0);
        calldata.append('LT Token');
        calldata.append(8);
        // symbol: ByteArray "LT"
        calldata.append(0);
        calldata.append('LT');
        calldata.append(2);
        // owner
        calldata.append(owner.into());
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        (addr, ILtTokenDispatcher { contract_address: addr })
    }

    /// Deploy SyToken (constructor: name, symbol, owner)
    fn deploy_sy_token(owner: ContractAddress) -> (ContractAddress, ISyTokenDispatcher) {
        let contract_class = declare("SyToken").unwrap().contract_class();
        let mut calldata: Array<felt252> = array![];
        // name: ByteArray "sy-WBTC"
        calldata.append(0);
        calldata.append('sy-WBTC');
        calldata.append(7);
        // symbol: ByteArray "syWBTC"
        calldata.append(0);
        calldata.append('syWBTC');
        calldata.append(6);
        // owner
        calldata.append(owner.into());
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        (addr, ISyTokenDispatcher { contract_address: addr })
    }

    /// Full staker setup: deploy LT + SY + Staker, wire ownership, mint LT to user, approve
    fn setup_full_staker() -> (
        IStakerDispatcher, ILtTokenDispatcher, ContractAddress, ContractAddress,
        ContractAddress, ContractAddress,
    ) {
        let owner = test_address();
        let rate: u256 = 1_000_000_000_000_000; // 1e15 raw sy-WBTC per block

        let (lt_addr, lt) = deploy_lt_token(owner);
        let (sy_addr, _sy) = deploy_sy_token(owner);
        let staker = deploy_staker_full(owner, lt_addr, sy_addr, rate);

        // Transfer SyToken ownership to Staker (so it can mint rewards)
        start_cheat_caller_address(sy_addr, owner);
        IOwnableFacadeDispatcher { contract_address: sy_addr }
            .transfer_ownership(staker.contract_address);
        stop_cheat_caller_address(sy_addr);

        // Mint LT to user via owner (vault=zero fallback)
        let user: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(lt_addr, owner);
        lt.mint(user, 1_000_000_000); // 10 LT (8 dec)
        stop_cheat_caller_address(lt_addr);

        // User approves Staker to pull LT
        start_cheat_caller_address(lt_addr, user);
        IERC20Dispatcher { contract_address: lt_addr }
            .approve(staker.contract_address, 1_000_000_000);
        stop_cheat_caller_address(lt_addr);

        (staker, lt, user, owner, lt_addr, sy_addr)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT & INITIAL STATE (view-only, no real tokens)
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    // GET REWARD RATE
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_get_reward_rate_returns_initial() {
        let owner = test_address();
        let reward_rate: u256 = 5_000_000_000_000; // 5e12
        let staker = deploy_staker(owner, reward_rate);

        assert(staker.get_reward_rate() == reward_rate, 'Should return initial rate');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SET REWARD RATE (owner only)
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    // GET TOTAL STAKED
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_get_total_staked_initially_zero() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        assert(staker.get_total_staked() == 0, 'Total staked should be 0');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GET STAKED BALANCE
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_get_staked_balance_unknown_user() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let random_user: ContractAddress = 0x1234.try_into().unwrap();
        assert(staker.get_staked_balance(random_user) == 0, 'Balance should be 0');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PENDING REWARDS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_pending_rewards_no_stake() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        assert(staker.pending_rewards(user) == 0, 'No pending for unstaked user');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SET SY_TOKEN (owner only)
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    // SET OWNER (owner only)
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    // STAKE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Amount must be > 0')]
    fn test_stake_zero_amount() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UNSTAKE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Insufficient staked balance')]
    fn test_unstake_without_stake() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, user);
        staker.unstake(100 * SCALE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DIFFERENT INITIAL REWARD RATES
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    // ZERO-ADDRESS VALIDATION (BUG 10)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Cannot set zero address')]
    fn test_set_owner_zero_panics() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let zero: ContractAddress = 0.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, owner);
        staker.set_owner(zero);
    }

    #[test]
    #[should_panic(expected: 'Cannot set zero address')]
    fn test_set_sy_token_zero_panics() {
        let owner = test_address();
        let staker = deploy_staker(owner, 1_000_000_000_000);

        let zero: ContractAddress = 0.try_into().unwrap();
        start_cheat_caller_address(staker.contract_address, owner);
        staker.set_sy_token(zero);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FULL FLOW TESTS (with real tokens)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_stake_full_flow() {
        let (staker, _lt, user, _owner, lt_addr, _sy_addr) = setup_full_staker();

        let stake_amount: u256 = 100_000_000; // 1 LT (8 dec)

        // Check LT balance before
        let lt_bal_before = IERC20BalanceFacadeDispatcher { contract_address: lt_addr }
            .balance_of(user);
        assert(lt_bal_before == 1_000_000_000, 'Should have 10 LT');

        // Stake
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(stake_amount);
        stop_cheat_caller_address(staker.contract_address);

        // Verify staked balance
        assert(staker.get_staked_balance(user) == stake_amount, 'Staked balance wrong');
        assert(staker.get_total_staked() == stake_amount, 'Total staked wrong');

        // LT transferred to staker
        let lt_bal_after = IERC20BalanceFacadeDispatcher { contract_address: lt_addr }
            .balance_of(user);
        assert(lt_bal_after == 1_000_000_000 - stake_amount, 'LT not transferred');
    }

    #[test]
    fn test_unstake_full_flow() {
        let (staker, _lt, user, _owner, lt_addr, _sy_addr) = setup_full_staker();

        let stake_amount: u256 = 100_000_000; // 1 LT

        // Stake first
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(stake_amount);

        // Unstake
        staker.unstake(stake_amount);
        stop_cheat_caller_address(staker.contract_address);

        // Verify balances restored
        assert(staker.get_staked_balance(user) == 0, 'Staked should be 0');
        assert(staker.get_total_staked() == 0, 'Total staked should be 0');

        // LT returned to user
        let lt_bal = IERC20BalanceFacadeDispatcher { contract_address: lt_addr }
            .balance_of(user);
        assert(lt_bal == 1_000_000_000, 'LT not returned');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REWARD ACCUMULATION (BUG 1 — precision fix verification)
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_reward_accumulation_100_blocks() {
        let (staker, _lt, user, _owner, _lt_addr, _sy_addr) = setup_full_staker();

        let stake_amount: u256 = 100_000_000; // 1 LT (8 dec)
        let rate: u256 = 1_000_000_000_000_000; // 1e15 (set in setup)

        // Set initial block
        start_cheat_block_number_global(1000);

        // Stake at block 1000
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(stake_amount);
        stop_cheat_caller_address(staker.contract_address);

        // Advance 100 blocks
        start_cheat_block_number_global(1100);

        // Check pending rewards
        let pending = staker.pending_rewards(user);
        // Expected: rate * blocks = 1e15 * 100 = 1e17 raw sy-WBTC
        let expected: u256 = rate * 100;
        assert(pending == expected, 'Pending rewards wrong');
    }

    #[test]
    fn test_claim_rewards_mints_sy_wbtc() {
        let (staker, _lt, user, _owner, _lt_addr, sy_addr) = setup_full_staker();

        let stake_amount: u256 = 100_000_000; // 1 LT

        // Set initial block
        start_cheat_block_number_global(1000);

        // Stake
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(stake_amount);
        stop_cheat_caller_address(staker.contract_address);

        // Advance 50 blocks
        start_cheat_block_number_global(1050);

        // Claim rewards
        start_cheat_caller_address(staker.contract_address, user);
        let claimed = staker.claim_rewards();
        stop_cheat_caller_address(staker.contract_address);

        // Expected: 1e15 * 50 = 5e16
        let expected: u256 = 1_000_000_000_000_000 * 50;
        assert(claimed == expected, 'Claimed amount wrong');

        // Check sy-WBTC balance was minted
        let sy_bal = IERC20BalanceFacadeDispatcher { contract_address: sy_addr }
            .balance_of(user);
        assert(sy_bal == expected, 'sy-WBTC not minted');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MULTI-USER PROPORTIONAL REWARDS
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_multi_user_proportional() {
        let owner = test_address();
        let rate: u256 = 1_000_000_000_000_000; // 1e15

        let (lt_addr, lt) = deploy_lt_token(owner);
        let (sy_addr, _sy) = deploy_sy_token(owner);
        let staker = deploy_staker_full(owner, lt_addr, sy_addr, rate);

        // Transfer SyToken ownership to Staker
        start_cheat_caller_address(sy_addr, owner);
        IOwnableFacadeDispatcher { contract_address: sy_addr }
            .transfer_ownership(staker.contract_address);
        stop_cheat_caller_address(sy_addr);

        let alice: ContractAddress = 0xA11CE.try_into().unwrap();
        let bob: ContractAddress = 0xB0B.try_into().unwrap();

        // Mint LT to both users
        start_cheat_caller_address(lt_addr, owner);
        lt.mint(alice, 300_000_000); // 3 LT
        lt.mint(bob, 100_000_000);   // 1 LT
        stop_cheat_caller_address(lt_addr);

        // Both approve staker
        start_cheat_caller_address(lt_addr, alice);
        IERC20Dispatcher { contract_address: lt_addr }
            .approve(staker.contract_address, 300_000_000);
        stop_cheat_caller_address(lt_addr);

        start_cheat_caller_address(lt_addr, bob);
        IERC20Dispatcher { contract_address: lt_addr }
            .approve(staker.contract_address, 100_000_000);
        stop_cheat_caller_address(lt_addr);

        // Both stake at block 1000
        start_cheat_block_number_global(1000);

        start_cheat_caller_address(staker.contract_address, alice);
        staker.stake(300_000_000); // Alice stakes 3 LT
        stop_cheat_caller_address(staker.contract_address);

        start_cheat_caller_address(staker.contract_address, bob);
        staker.stake(100_000_000); // Bob stakes 1 LT
        stop_cheat_caller_address(staker.contract_address);

        // Advance 100 blocks
        start_cheat_block_number_global(1100);

        let alice_pending = staker.pending_rewards(alice);
        let bob_pending = staker.pending_rewards(bob);

        // Total rewards = 1e15 * 100 = 1e17
        // Alice has 3/4 of total staked → 75e15
        // Bob has 1/4 of total staked → 25e15
        assert(alice_pending == 75_000_000_000_000_000, 'Alice should get 3/4');
        assert(bob_pending == 25_000_000_000_000_000, 'Bob should get 1/4');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════

    #[test]
    fn test_last_user_unstakes() {
        let (staker, _lt, user, _owner, _lt_addr, sy_addr) = setup_full_staker();

        let stake_amount: u256 = 100_000_000;

        start_cheat_block_number_global(1000);

        // Stake
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(stake_amount);
        stop_cheat_caller_address(staker.contract_address);

        // Advance blocks
        start_cheat_block_number_global(1010);

        // Unstake all (should auto-claim rewards)
        start_cheat_caller_address(staker.contract_address, user);
        staker.unstake(stake_amount);
        stop_cheat_caller_address(staker.contract_address);

        assert(staker.get_total_staked() == 0, 'Total should be 0');
        assert(staker.get_staked_balance(user) == 0, 'User staked should be 0');

        // Rewards should have been paid (10 blocks * 1e15 = 1e16)
        let sy_bal = IERC20BalanceFacadeDispatcher { contract_address: sy_addr }
            .balance_of(user);
        assert(sy_bal == 10_000_000_000_000_000, 'Rewards not paid on unstake');
    }

    #[test]
    fn test_zero_reward_rate_no_rewards() {
        let owner = test_address();
        let (lt_addr, lt) = deploy_lt_token(owner);
        let (sy_addr, _sy) = deploy_sy_token(owner);
        let staker = deploy_staker_full(owner, lt_addr, sy_addr, 0); // rate = 0

        // Transfer SyToken ownership
        start_cheat_caller_address(sy_addr, owner);
        IOwnableFacadeDispatcher { contract_address: sy_addr }
            .transfer_ownership(staker.contract_address);
        stop_cheat_caller_address(sy_addr);

        let user: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(lt_addr, owner);
        lt.mint(user, 100_000_000);
        stop_cheat_caller_address(lt_addr);

        start_cheat_caller_address(lt_addr, user);
        IERC20Dispatcher { contract_address: lt_addr }
            .approve(staker.contract_address, 100_000_000);
        stop_cheat_caller_address(lt_addr);

        start_cheat_block_number_global(1000);

        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(100_000_000);
        stop_cheat_caller_address(staker.contract_address);

        // Advance 1000 blocks
        start_cheat_block_number_global(2000);

        let pending = staker.pending_rewards(user);
        assert(pending == 0, 'Should be 0 with zero rate');
    }

    #[test]
    fn test_stake_then_stake_more() {
        let (staker, _lt, user, _owner, _lt_addr, sy_addr) = setup_full_staker();

        start_cheat_block_number_global(1000);

        // First stake: 1 LT
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(100_000_000);
        stop_cheat_caller_address(staker.contract_address);

        // Advance 10 blocks
        start_cheat_block_number_global(1010);

        // Second stake: 1 more LT (should settle rewards from first stake)
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(100_000_000);
        stop_cheat_caller_address(staker.contract_address);

        // Rewards from first 10 blocks should be settled (minted as sy-WBTC)
        let sy_bal = IERC20BalanceFacadeDispatcher { contract_address: sy_addr }
            .balance_of(user);
        // 10 blocks * 1e15 = 1e16
        assert(sy_bal == 10_000_000_000_000_000, 'Rewards not settled on re-stake');

        // Total staked should be 2 LT
        assert(staker.get_staked_balance(user) == 200_000_000, 'Total staked wrong');
    }

    #[test]
    fn test_claim_then_continue_earning() {
        let (staker, _lt, user, _owner, _lt_addr, sy_addr) = setup_full_staker();

        start_cheat_block_number_global(1000);

        // Stake 1 LT
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(100_000_000);
        stop_cheat_caller_address(staker.contract_address);

        // Advance 10 blocks → claim
        start_cheat_block_number_global(1010);

        start_cheat_caller_address(staker.contract_address, user);
        staker.claim_rewards();
        stop_cheat_caller_address(staker.contract_address);

        let sy_bal_1 = IERC20BalanceFacadeDispatcher { contract_address: sy_addr }
            .balance_of(user);
        assert(sy_bal_1 == 10_000_000_000_000_000, 'First claim wrong');

        // Advance 20 more blocks → claim again
        start_cheat_block_number_global(1030);

        start_cheat_caller_address(staker.contract_address, user);
        staker.claim_rewards();
        stop_cheat_caller_address(staker.contract_address);

        let sy_bal_2 = IERC20BalanceFacadeDispatcher { contract_address: sy_addr }
            .balance_of(user);
        // Total: 10e15 + 20e15 = 30e15
        assert(sy_bal_2 == 30_000_000_000_000_000, 'Second claim wrong');
    }

    #[test]
    fn test_reward_precision_small_amounts() {
        let owner = test_address();
        let rate: u256 = 1_000; // very small rate

        let (lt_addr, lt) = deploy_lt_token(owner);
        let (sy_addr, _sy) = deploy_sy_token(owner);
        let staker = deploy_staker_full(owner, lt_addr, sy_addr, rate);

        start_cheat_caller_address(sy_addr, owner);
        IOwnableFacadeDispatcher { contract_address: sy_addr }
            .transfer_ownership(staker.contract_address);
        stop_cheat_caller_address(sy_addr);

        let user: ContractAddress = 0xA11CE.try_into().unwrap();
        start_cheat_caller_address(lt_addr, owner);
        lt.mint(user, 1); // 1 raw LT (smallest unit)
        stop_cheat_caller_address(lt_addr);

        start_cheat_caller_address(lt_addr, user);
        IERC20Dispatcher { contract_address: lt_addr }
            .approve(staker.contract_address, 1);
        stop_cheat_caller_address(lt_addr);

        start_cheat_block_number_global(1000);

        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(1);
        stop_cheat_caller_address(staker.contract_address);

        // Advance 10 blocks
        start_cheat_block_number_global(1010);

        let pending = staker.pending_rewards(user);
        // rate * blocks = 1000 * 10 = 10000
        assert(pending == 10_000, 'Small precision wrong');
    }

    #[test]
    #[should_panic(expected: 'Insufficient staked balance')]
    fn test_unstake_exceeds_balance_panics() {
        let (staker, _lt, user, _owner, _lt_addr, _sy_addr) = setup_full_staker();

        // Stake 1 LT
        start_cheat_caller_address(staker.contract_address, user);
        staker.stake(100_000_000);

        // Try to unstake 2 LT
        staker.unstake(200_000_000);
    }
}
