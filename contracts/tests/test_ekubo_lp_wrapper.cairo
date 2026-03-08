//! Tests for EkuboLPWrapper contract (Bunni-style ERC-20 LP wrapper)

use starknet::ContractAddress;
use starkyield::integrations::ekubo_lp_wrapper::{IEkuboLPWrapperDispatcher, IEkuboLPWrapperDispatcherTrait};
use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starkyield::vault::mock_wbtc::{IMockWBTCDispatcher, IMockWBTCDispatcherTrait};
use starkyield::vault::mock_usdc::{IMockUSDCDispatcher, IMockUSDCDispatcherTrait};
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    /// MIN_INITIAL_SHARES from Constants (inflation guard burned on first deposit)
    const MIN_INITIAL_SHARES: u256 = 1_000;

    // ═══════════════════════════════════════════════════════
    // HELPERS — deploy mock tokens and contracts
    // ═══════════════════════════════════════════════════════

    /// Deploy MockWBTC (no constructor args)
    fn deploy_mock_wbtc() -> ContractAddress {
        let contract_class = declare("MockWBTC").unwrap().contract_class();
        let calldata = array![];
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

    /// Deploy MockEkuboAdapter (constructor: btc_token, usdc_token, owner)
    fn deploy_mock_ekubo(
        btc_token: ContractAddress, usdc_token: ContractAddress, owner: ContractAddress
    ) -> ContractAddress {
        let contract_class = declare("MockEkuboAdapter").unwrap().contract_class();
        let calldata = array![btc_token.into(), usdc_token.into(), owner.into()];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        addr
    }

    /// Deploy EkuboLPWrapper (constructor: owner, btc_token, usdc_token, ekubo_adapter)
    fn deploy_wrapper(
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        ekubo_adapter: ContractAddress,
    ) -> IEkuboLPWrapperDispatcher {
        let contract_class = declare("EkuboLPWrapper").unwrap().contract_class();
        let calldata = array![
            owner.into(),
            btc_token.into(),
            usdc_token.into(),
            ekubo_adapter.into(),
        ];
        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        IEkuboLPWrapperDispatcher { contract_address: addr }
    }

    /// Deploy EkuboLPWrapper with zero addresses (for view-only / isolated tests)
    fn deploy_wrapper_zero(owner: ContractAddress) -> IEkuboLPWrapperDispatcher {
        let zero: ContractAddress = 0.try_into().unwrap();
        deploy_wrapper(owner, zero, zero, zero)
    }

    /// Full integration setup: deploy mock tokens, mock ekubo adapter, and wrapper.
    /// Returns (wrapper, btc_token, usdc_token, ekubo_adapter)
    fn deploy_full_setup(
        owner: ContractAddress,
    ) -> (IEkuboLPWrapperDispatcher, ContractAddress, ContractAddress, ContractAddress) {
        let btc_token = deploy_mock_wbtc();
        let usdc_token = deploy_mock_usdc(owner);
        let ekubo_adapter = deploy_mock_ekubo(btc_token, usdc_token, owner);
        let wrapper = deploy_wrapper(owner, btc_token, usdc_token, ekubo_adapter);
        (wrapper, btc_token, usdc_token, ekubo_adapter)
    }

    /// Mint BTC to a user and approve the wrapper to spend it
    fn mint_and_approve_btc(
        btc_token: ContractAddress,
        user: ContractAddress,
        wrapper_addr: ContractAddress,
        amount: u256,
    ) {
        // Faucet: mint to user (caller = user)
        start_cheat_caller_address(btc_token, user);
        IMockWBTCDispatcher { contract_address: btc_token }.faucet(amount);
        // Approve wrapper
        IERC20Dispatcher { contract_address: btc_token }.approve(wrapper_addr, amount);
        stop_cheat_caller_address(btc_token);
    }

    /// Mint USDC to a user and approve the wrapper to spend it
    fn mint_and_approve_usdc(
        usdc_token: ContractAddress,
        user: ContractAddress,
        wrapper_addr: ContractAddress,
        amount: u256,
    ) {
        start_cheat_caller_address(usdc_token, user);
        IMockUSDCDispatcher { contract_address: usdc_token }.faucet(amount);
        IERC20Dispatcher { contract_address: usdc_token }.approve(wrapper_addr, amount);
        stop_cheat_caller_address(usdc_token);
    }

    // ═══════════════════════════════════════════════════════
    // DEPLOYMENT & INITIAL STATE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_deploy_does_not_panic() {
        let owner = test_address();
        let _wrapper = deploy_wrapper_zero(owner);
        // Constructor completed without panic
    }

    #[test]
    fn test_get_owner() {
        let owner = test_address();
        let wrapper = deploy_wrapper_zero(owner);
        assert(wrapper.get_owner() == owner, 'Owner should match');
    }

    #[test]
    fn test_initial_lp_value_zero() {
        // With zero ekubo_adapter, calling get_lp_value will fail due to
        // dispatching to address 0. Instead, deploy with real mock adapter.
        let owner = test_address();
        let (wrapper, _, _, _) = deploy_full_setup(owner);

        let lp_value = wrapper.get_lp_value();
        assert(lp_value == 0, 'Initial LP value should be 0');
    }

    #[test]
    fn test_initial_erc20_total_supply_zero() {
        let owner = test_address();
        let wrapper = deploy_wrapper_zero(owner);

        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        assert(erc20.total_supply() == 0, 'Initial total supply should be 0');
    }

    #[test]
    fn test_initial_erc20_balance_zero() {
        let owner = test_address();
        let wrapper = deploy_wrapper_zero(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        assert(erc20.balance_of(user) == 0, 'Balance should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // DEPLOY WITH FULL SETUP
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_deploy_full_setup() {
        let owner = test_address();
        let (wrapper, _, _, _) = deploy_full_setup(owner);

        assert(wrapper.get_owner() == owner, 'Owner should match');
        assert(wrapper.get_lp_value() == 0, 'LP value should be 0');
    }

    // ═══════════════════════════════════════════════════════
    // DEPOSIT — FIRST DEPOSIT (BUNNI PATTERN)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_first_deposit() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 100_000_000; // 1 BTC (8 decimals)
        let usdc_amount: u256 = 96_000_000_000; // 96,000 USDC (6 decimals)

        // Mint tokens to user and approve wrapper
        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user, wrapper.contract_address, usdc_amount);

        // Deposit
        start_cheat_caller_address(wrapper.contract_address, user);
        let shares = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        // First deposit: shares = btc_amount - MIN_INITIAL_SHARES
        let expected_shares = btc_amount - MIN_INITIAL_SHARES;
        assert(shares == expected_shares, 'Shares mismatch on first dep');

        // Verify ERC20 balance
        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        assert(erc20.balance_of(user) == expected_shares, 'User balance mismatch');

        // Total supply = user shares + MIN_INITIAL_SHARES (burned to address 0)
        assert(erc20.total_supply() == btc_amount, 'Total supply mismatch');
    }

    #[test]
    fn test_first_deposit_lp_value_nonzero() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 100_000_000; // 1 BTC
        let usdc_amount: u256 = 96_000_000_000; // 96,000 USDC

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user, wrapper.contract_address, usdc_amount);

        start_cheat_caller_address(wrapper.contract_address, user);
        wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        let lp_value = wrapper.get_lp_value();
        assert(lp_value > 0, 'LP value should be > 0');
    }

    // ═══════════════════════════════════════════════════════
    // DEPOSIT — SECOND DEPOSIT (PRO-RATA)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_second_deposit_pro_rata() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user1: ContractAddress = 0x1234.try_into().unwrap();
        let user2: ContractAddress = 0x5678.try_into().unwrap();
        let btc_amount: u256 = 100_000_000; // 1 BTC
        let usdc_amount: u256 = 96_000_000_000; // 96,000 USDC

        // First deposit by user1
        mint_and_approve_btc(btc_token, user1, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user1, wrapper.contract_address, usdc_amount);
        start_cheat_caller_address(wrapper.contract_address, user1);
        wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        let supply_after_first = erc20.total_supply();

        // Second deposit by user2 (same amounts)
        mint_and_approve_btc(btc_token, user2, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user2, wrapper.contract_address, usdc_amount);
        start_cheat_caller_address(wrapper.contract_address, user2);
        let shares2 = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        // Pro-rata: shares2 = totalSupply * btc_amount / existing_btc
        // existing_btc = btc_amount (from first deposit)
        // shares2 = supply_after_first * btc_amount / btc_amount = supply_after_first
        assert(shares2 == supply_after_first, 'Pro-rata shares mismatch');

        // User2 balance
        assert(erc20.balance_of(user2) == shares2, 'User2 balance mismatch');
    }

    #[test]
    fn test_second_deposit_half_amount() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user1: ContractAddress = 0x1234.try_into().unwrap();
        let user2: ContractAddress = 0x5678.try_into().unwrap();
        let btc_amount: u256 = 100_000_000; // 1 BTC
        let usdc_amount: u256 = 96_000_000_000;

        // First deposit
        mint_and_approve_btc(btc_token, user1, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user1, wrapper.contract_address, usdc_amount);
        start_cheat_caller_address(wrapper.contract_address, user1);
        wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        let supply_after_first = erc20.total_supply();

        // Second deposit with half the BTC
        let half_btc = btc_amount / 2;
        let half_usdc = usdc_amount / 2;
        mint_and_approve_btc(btc_token, user2, wrapper.contract_address, half_btc);
        mint_and_approve_usdc(usdc_token, user2, wrapper.contract_address, half_usdc);
        start_cheat_caller_address(wrapper.contract_address, user2);
        let shares2 = wrapper.deposit(half_btc, half_usdc);
        stop_cheat_caller_address(wrapper.contract_address);

        // Pro-rata: shares2 = totalSupply * half_btc / btc_amount = totalSupply / 2
        let expected = supply_after_first / 2;
        assert(shares2 == expected, 'Half deposit shares mismatch');
    }

    // ═══════════════════════════════════════════════════════
    // DEPOSIT — VALIDATION
    // ═══════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'BTC amount must be > 0')]
    fn test_deposit_zero_btc() {
        let owner = test_address();
        let (wrapper, _, _, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(wrapper.contract_address, user);
        wrapper.deposit(0, 1_000_000);
    }

    #[test]
    #[should_panic(expected: 'Deposit too small')]
    fn test_deposit_too_small() {
        let owner = test_address();
        let (wrapper, btc_token, _, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        // Deposit exactly MIN_INITIAL_SHARES BTC — should fail because
        // liquidity must be STRICTLY > MIN_INITIAL_SHARES
        let tiny_amount: u256 = MIN_INITIAL_SHARES;
        mint_and_approve_btc(btc_token, user, wrapper.contract_address, tiny_amount);

        start_cheat_caller_address(wrapper.contract_address, user);
        wrapper.deposit(tiny_amount, 0);
    }

    #[test]
    fn test_deposit_btc_only_no_usdc() {
        let owner = test_address();
        let (wrapper, btc_token, _, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 100_000_000; // 1 BTC

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);

        // Deposit with 0 USDC (the contract allows this)
        start_cheat_caller_address(wrapper.contract_address, user);
        let shares = wrapper.deposit(btc_amount, 0);
        stop_cheat_caller_address(wrapper.contract_address);

        let expected = btc_amount - MIN_INITIAL_SHARES;
        assert(shares == expected, 'BTC-only shares mismatch');
    }

    // ═══════════════════════════════════════════════════════
    // WITHDRAW
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_withdraw_full() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 100_000_000;
        let usdc_amount: u256 = 96_000_000_000;

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user, wrapper.contract_address, usdc_amount);

        start_cheat_caller_address(wrapper.contract_address, user);
        let shares = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        let user_shares = erc20.balance_of(user);
        assert(user_shares == shares, 'Shares mismatch before withdraw');

        // Record BTC balance before withdraw
        let btc = IERC20Dispatcher { contract_address: btc_token };
        let btc_before = btc.balance_of(user);
        let usdc = IERC20Dispatcher { contract_address: usdc_token };
        let usdc_before = usdc.balance_of(user);

        // Withdraw all shares
        start_cheat_caller_address(wrapper.contract_address, user);
        let (btc_out, usdc_out) = wrapper.withdraw(shares);
        stop_cheat_caller_address(wrapper.contract_address);

        // Should receive proportional tokens back
        assert(btc_out > 0, 'Should receive BTC back');
        assert(usdc_out > 0, 'Should receive USDC back');

        // Verify token transfers happened
        let btc_after = btc.balance_of(user);
        let usdc_after = usdc.balance_of(user);
        assert(btc_after == btc_before + btc_out, 'BTC balance mismatch');
        assert(usdc_after == usdc_before + usdc_out, 'USDC balance mismatch');

        // User shares should be burned
        assert(erc20.balance_of(user) == 0, 'Shares should be 0 after');
    }

    #[test]
    fn test_withdraw_partial() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 100_000_000;
        let usdc_amount: u256 = 96_000_000_000;

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user, wrapper.contract_address, usdc_amount);

        start_cheat_caller_address(wrapper.contract_address, user);
        let shares = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        // Withdraw half the shares
        let half_shares = shares / 2;
        start_cheat_caller_address(wrapper.contract_address, user);
        let (btc_out, usdc_out) = wrapper.withdraw(half_shares);
        stop_cheat_caller_address(wrapper.contract_address);

        assert(btc_out > 0, 'Should receive partial BTC');
        assert(usdc_out > 0, 'Should receive partial USDC');

        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        let remaining = erc20.balance_of(user);
        assert(remaining == shares - half_shares, 'Remaining shares mismatch');
    }

    // ═══════════════════════════════════════════════════════
    // WITHDRAW — VALIDATION
    // ═══════════════════════════════════════════════════════

    #[test]
    #[should_panic(expected: 'Shares must be > 0')]
    fn test_withdraw_zero_shares() {
        let owner = test_address();
        let (wrapper, _, _, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(wrapper.contract_address, user);
        wrapper.withdraw(0);
    }

    #[test]
    #[should_panic(expected: 'Shares exceed supply')]
    fn test_withdraw_exceeds_supply() {
        let owner = test_address();
        let (wrapper, _, _, _) = deploy_full_setup(owner);

        // No deposits, total supply = 0, try to withdraw 100
        let user: ContractAddress = 0x1234.try_into().unwrap();
        start_cheat_caller_address(wrapper.contract_address, user);
        wrapper.withdraw(100);
    }

    // ═══════════════════════════════════════════════════════
    // DEPOSIT + WITHDRAW ROUND-TRIP
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_deposit_withdraw_round_trip() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 100_000_000; // 1 BTC
        let usdc_amount: u256 = 96_000_000_000;

        // Record initial BTC/USDC balances (both 0)
        let btc = IERC20Dispatcher { contract_address: btc_token };
        let usdc = IERC20Dispatcher { contract_address: usdc_token };

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user, wrapper.contract_address, usdc_amount);

        // Deposit
        start_cheat_caller_address(wrapper.contract_address, user);
        let shares = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        // After deposit: user should have 0 BTC and 0 USDC (all transferred to wrapper)
        assert(btc.balance_of(user) == 0, 'User BTC should be 0 after dep');
        assert(usdc.balance_of(user) == 0, 'User USDC should be 0 after dep');

        // Withdraw all
        start_cheat_caller_address(wrapper.contract_address, user);
        let (btc_out, usdc_out) = wrapper.withdraw(shares);
        stop_cheat_caller_address(wrapper.contract_address);

        // Due to MIN_INITIAL_SHARES being burned, user gets slightly less than deposited
        // because their share of the total supply is (btc_amount - MIN_INITIAL_SHARES) / btc_amount
        // btc_out = btc_amount * shares / total_supply = btc_amount * (btc_amount - 1000) / btc_amount
        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        assert(erc20.balance_of(user) == 0, 'Shares should be 0 after RT');
        assert(btc_out > 0, 'Should get BTC back');
        assert(usdc_out > 0, 'Should get USDC back');
    }

    // ═══════════════════════════════════════════════════════
    // MULTIPLE DEPOSITORS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_two_depositors_withdraw_proportionally() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user1: ContractAddress = 0x1234.try_into().unwrap();
        let user2: ContractAddress = 0x5678.try_into().unwrap();
        let btc_amount: u256 = 100_000_000; // 1 BTC each
        let usdc_amount: u256 = 96_000_000_000;

        // User1 deposits
        mint_and_approve_btc(btc_token, user1, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user1, wrapper.contract_address, usdc_amount);
        start_cheat_caller_address(wrapper.contract_address, user1);
        let shares1 = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        // User2 deposits same amount
        mint_and_approve_btc(btc_token, user2, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user2, wrapper.contract_address, usdc_amount);
        start_cheat_caller_address(wrapper.contract_address, user2);
        let shares2 = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        // User1 withdraws all their shares
        start_cheat_caller_address(wrapper.contract_address, user1);
        let (btc_out_1, usdc_out_1) = wrapper.withdraw(shares1);
        stop_cheat_caller_address(wrapper.contract_address);

        assert(btc_out_1 > 0, 'User1 should get BTC');
        assert(usdc_out_1 > 0, 'User1 should get USDC');

        // User2 withdraws all their shares
        start_cheat_caller_address(wrapper.contract_address, user2);
        let (btc_out_2, usdc_out_2) = wrapper.withdraw(shares2);
        stop_cheat_caller_address(wrapper.contract_address);

        assert(btc_out_2 > 0, 'User2 should get BTC');
        assert(usdc_out_2 > 0, 'User2 should get USDC');

        // Both deposited the same amount, so they should receive similar amounts.
        // User1 got first-mover penalty (MIN_INITIAL_SHARES burned) but user2 got pro-rata
        // from the inflated supply, so their outputs won't be exactly equal.
        // Just verify both got something meaningful.
        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        // After both withdraw, only the MIN_INITIAL_SHARES burned to zero addr remain
        let dead: ContractAddress = 0.try_into().unwrap();
        assert(erc20.balance_of(dead) == MIN_INITIAL_SHARES, 'Dead addr shares mismatch');
    }

    // ═══════════════════════════════════════════════════════
    // ERC20 SHARE TOKEN PROPERTIES
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_erc20_share_transfer() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user1: ContractAddress = 0x1234.try_into().unwrap();
        let user2: ContractAddress = 0x5678.try_into().unwrap();
        let btc_amount: u256 = 100_000_000;
        let usdc_amount: u256 = 96_000_000_000;

        mint_and_approve_btc(btc_token, user1, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user1, wrapper.contract_address, usdc_amount);

        start_cheat_caller_address(wrapper.contract_address, user1);
        let shares = wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        // Transfer half of shares from user1 to user2
        let half = shares / 2;
        let erc20 = IERC20Dispatcher { contract_address: wrapper.contract_address };
        start_cheat_caller_address(wrapper.contract_address, user1);
        erc20.transfer(user2, half);
        stop_cheat_caller_address(wrapper.contract_address);

        assert(erc20.balance_of(user1) == shares - half, 'User1 shares after transfer');
        assert(erc20.balance_of(user2) == half, 'User2 shares after transfer');

        // User2 can now withdraw their received shares
        start_cheat_caller_address(wrapper.contract_address, user2);
        let (btc_out, usdc_out) = wrapper.withdraw(half);
        stop_cheat_caller_address(wrapper.contract_address);

        assert(btc_out > 0, 'User2 should receive BTC');
        assert(usdc_out > 0, 'User2 should receive USDC');
    }

    // ═══════════════════════════════════════════════════════
    // GET LP VALUE
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_get_lp_value_increases_after_deposit() {
        let owner = test_address();
        let (wrapper, btc_token, usdc_token, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 100_000_000;
        let usdc_amount: u256 = 96_000_000_000;

        let value_before = wrapper.get_lp_value();

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);
        mint_and_approve_usdc(usdc_token, user, wrapper.contract_address, usdc_amount);

        start_cheat_caller_address(wrapper.contract_address, user);
        wrapper.deposit(btc_amount, usdc_amount);
        stop_cheat_caller_address(wrapper.contract_address);

        let value_after = wrapper.get_lp_value();
        assert(value_after > value_before, 'LP value should increase');
    }

    // ═══════════════════════════════════════════════════════
    // EDGE CASE: MINIMUM VALID FIRST DEPOSIT
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_minimum_valid_first_deposit() {
        let owner = test_address();
        let (wrapper, btc_token, _, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        // Minimum valid: btc_amount = MIN_INITIAL_SHARES + 1 = 1001
        let btc_amount: u256 = MIN_INITIAL_SHARES + 1;

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);

        start_cheat_caller_address(wrapper.contract_address, user);
        let shares = wrapper.deposit(btc_amount, 0);
        stop_cheat_caller_address(wrapper.contract_address);

        // shares = 1001 - 1000 = 1
        assert(shares == 1, 'Min deposit should yield 1 share');
    }

    // ═══════════════════════════════════════════════════════
    // DEPOSIT — BTC ONLY (USDC = 0)
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_btc_only_deposit_and_withdraw() {
        let owner = test_address();
        let (wrapper, btc_token, _, _) = deploy_full_setup(owner);

        let user: ContractAddress = 0x1234.try_into().unwrap();
        let btc_amount: u256 = 50_000_000; // 0.5 BTC

        mint_and_approve_btc(btc_token, user, wrapper.contract_address, btc_amount);

        start_cheat_caller_address(wrapper.contract_address, user);
        let shares = wrapper.deposit(btc_amount, 0);
        stop_cheat_caller_address(wrapper.contract_address);

        assert(shares == btc_amount - MIN_INITIAL_SHARES, 'BTC-only shares');

        // Withdraw
        start_cheat_caller_address(wrapper.contract_address, user);
        let (btc_out, usdc_out) = wrapper.withdraw(shares);
        stop_cheat_caller_address(wrapper.contract_address);

        assert(btc_out > 0, 'Should receive BTC back');
        assert(usdc_out == 0, 'No USDC deposited, none back');
    }
}
