//! Tests for Vault Manager contract

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

    fn deploy_vault_manager(owner: ContractAddress) -> IVaultManagerDispatcher {
        let zero: ContractAddress = 0.try_into().unwrap();

        let contract_class = declare("VaultManager").unwrap().contract_class();
        let calldata = array![
            zero.into(),  // btc_token (zero = no real ERC20 calls in view tests)
            zero.into(),  // usdc_token
            zero.into(),  // sy_btc_token
            zero.into(),  // ekubo_adapter
            zero.into(),  // vesu_adapter
            zero.into(),  // pragma_adapter
            zero.into(),  // leverage_manager
            owner.into()
        ];
        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();

        IVaultManagerDispatcher { contract_address }
    }

    #[test]
    fn test_deploy() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let total_shares = vault.get_total_shares();
        assert(total_shares == 0, 'Initial shares should be 0');
    }

    #[test]
    fn test_get_share_price_initial() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let share_price = vault.get_share_price();
        let scale = 1_000000000000000000_u256;
        assert(share_price == scale, 'Share price should be 1.0');
    }

    #[test]
    fn test_get_health_factor_no_debt() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let hf = vault.get_health_factor();
        let expected = 999 * 1_000000000000000000_u256;
        assert(hf == expected, 'HF should be 999x with no debt');
    }

    #[test]
    fn test_get_current_leverage_no_position() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let leverage = vault.get_current_leverage();
        let scale = 1_000000000000000000_u256;
        assert(leverage == scale, 'Leverage should be 1x');
    }

    #[test]
    fn test_get_btc_price_fallback() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let btc_price = vault.get_btc_price();
        let expected = 60000 * 1_000000000000000000_u256;
        assert(btc_price == expected, 'Should use fallback BTC price');
    }

    #[test]
    fn test_set_paused() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        start_cheat_caller_address(vault.contract_address, owner);
        vault.set_paused(true);
        stop_cheat_caller_address(vault.contract_address);
    }

    #[test]
    #[should_panic(expected: 'Only owner')]
    fn test_set_paused_not_owner() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        let attacker: ContractAddress = 0x999.try_into().unwrap();
        start_cheat_caller_address(vault.contract_address, attacker);
        vault.set_paused(true);
    }

    #[test]
    fn test_set_target_leverage() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        start_cheat_caller_address(vault.contract_address, owner);
        vault.set_target_leverage(2_500000000000000000);
        stop_cheat_caller_address(vault.contract_address);
    }

    #[test]
    #[should_panic(expected: 'Leverage too low')]
    fn test_set_target_leverage_too_low() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        start_cheat_caller_address(vault.contract_address, owner);
        vault.set_target_leverage(1_000000000000000000);
    }

    #[test]
    #[should_panic(expected: 'Leverage too high')]
    fn test_set_target_leverage_too_high() {
        let owner = test_address();
        let vault = deploy_vault_manager(owner);

        start_cheat_caller_address(vault.contract_address, owner);
        vault.set_target_leverage(4_000000000000000000);
    }
}
