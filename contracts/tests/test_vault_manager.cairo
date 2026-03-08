//! Tests for Vault Manager contract (v12 interface)

use starknet::ContractAddress;
use starkyield::vault::vault_manager::{IVaultManagerDispatcher, IVaultManagerDispatcherTrait};
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    /// Deploy VaultManager with the 8-arg constructor.
    /// All token/adapter addresses are zero (safe for view-only tests).
    fn deploy_vault_manager(owner: ContractAddress) -> IVaultManagerDispatcher {
        let zero: ContractAddress = 0.try_into().unwrap();

        let contract_class = declare("VaultManager").unwrap().contract_class();
        let calldata = array![
            zero.into(), // btc_token
            zero.into(), // usdc_token
            zero.into(), // lt_token
            zero.into(), // ekubo_adapter
            zero.into(), // lending_adapter
            zero.into(), // virtual_pool
            zero.into(), // risk_manager
            owner.into() // owner
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();

        IVaultManagerDispatcher { contract_address }
    }

    // ───────────────────── Deployment ─────────────────────

    #[test]
    fn test_deploy() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let total_shares = vault.get_total_shares();
        assert(total_shares == 0, 'Initial shares should be 0');
    }

    // ───────────────────── get_total_shares ─────────────────────

    #[test]
    fn test_get_total_shares_initial() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        assert(vault.get_total_shares() == 0, 'Total shares should be 0');
    }

    // ───────────────────── get_total_debt ─────────────────────

    #[test]
    fn test_get_total_debt_initial() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        assert(vault.get_total_debt() == 0, 'Total debt should be 0');
    }

    // ───────────────────── is_paused ─────────────────────

    #[test]
    fn test_is_paused_initially_false() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        assert(vault.is_paused() == false, 'Should not be paused initially');
    }

    // ───────────────────── pause / unpause (owner) ─────────────────────

    #[test]
    fn test_pause_by_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        start_cheat_caller_address(vault.contract_address, owner);
        vault.pause();
        stop_cheat_caller_address(vault.contract_address);

        assert(vault.is_paused() == true, 'Should be paused after pause()');
    }

    #[test]
    fn test_unpause_by_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        // Pause first
        start_cheat_caller_address(vault.contract_address, owner);
        vault.pause();
        stop_cheat_caller_address(vault.contract_address);

        assert(vault.is_paused() == true, 'Should be paused');

        // Unpause
        start_cheat_caller_address(vault.contract_address, owner);
        vault.unpause();
        stop_cheat_caller_address(vault.contract_address);

        assert(vault.is_paused() == false, 'Should be unpaused');
    }

    // ───────────────────── pause / unpause (non-owner → revert) ─────────────────────

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_pause_not_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(vault.contract_address, attacker);
        vault.pause();
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_unpause_not_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        // Owner pauses first
        start_cheat_caller_address(vault.contract_address, owner);
        vault.pause();
        stop_cheat_caller_address(vault.contract_address);

        // Attacker tries to unpause
        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(vault.contract_address, attacker);
        vault.unpause();
    }

    // ───────────────────── set_fee_distributor (owner only) ─────────────────────

    #[test]
    fn test_set_fee_distributor_by_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let new_addr: ContractAddress = 0xABC.try_into().unwrap();
        start_cheat_caller_address(vault.contract_address, owner);
        vault.set_fee_distributor(new_addr);
        stop_cheat_caller_address(vault.contract_address);
        // No revert means success; fee_distributor is internal storage with no getter,
        // so we just verify the call completes without panic.
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_fee_distributor_not_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        let new_addr: ContractAddress = 0xABC.try_into().unwrap();

        start_cheat_caller_address(vault.contract_address, attacker);
        vault.set_fee_distributor(new_addr);
    }

    // ───────────────────── set_levamm (owner only) ─────────────────────

    #[test]
    fn test_set_levamm_by_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let new_addr: ContractAddress = 0xDEF.try_into().unwrap();
        start_cheat_caller_address(vault.contract_address, owner);
        vault.set_levamm(new_addr);
        stop_cheat_caller_address(vault.contract_address);
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_levamm_not_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        let new_addr: ContractAddress = 0xDEF.try_into().unwrap();

        start_cheat_caller_address(vault.contract_address, attacker);
        vault.set_levamm(new_addr);
    }

    // ───────────────────── get_user_shares ─────────────────────

    #[test]
    fn test_get_user_shares_initially_zero() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let random_user: ContractAddress = 0x1234.try_into().unwrap();
        assert(vault.get_user_shares(random_user) == 0, 'User shares should be 0');
    }
}
