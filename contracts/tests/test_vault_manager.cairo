//! Tests for Vault Manager contract

use starknet::ContractAddress;
use starknet::testing::set_caller_address;
use starkyield::vault::vault_manager::{VaultManagerDispatcher, VaultManagerDispatcherTrait, IVaultManagerDispatcher, IVaultManagerDispatcherTrait};
use starkyield::vault::sy_btc_token::{SyBtcTokenDispatcher, SyBtcTokenDispatcherTrait};
use core::byte_array::ByteArray;
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, deploy, DeployResultTrait, test_address};

    fn deploy_sy_btc_token(owner: ContractAddress) -> SyBtcTokenDispatcher {
        let name = ByteArray::from("StarkYield BTC");
        let symbol = ByteArray::from("syBTC");
        
        let contract_class = declare("SyBtcToken").unwrap().contract_class();
        let (contract_address, _) = deploy(@contract_class, array![name.into(), symbol.into(), owner.into()]).unwrap();
        
        SyBtcTokenDispatcher { contract_address }
    }

    fn deploy_vault_manager(
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        sy_btc_token: ContractAddress,
        ekubo_pool: ContractAddress,
        vesu_lending: ContractAddress,
        pragma_oracle: ContractAddress,
        owner: ContractAddress
    ) -> VaultManagerDispatcher {
        let contract_class = declare("VaultManager").unwrap().contract_class();
        let (contract_address, _) = deploy(
            @contract_class,
            array![
                btc_token.into(),
                usdc_token.into(),
                sy_btc_token.into(),
                ekubo_pool.into(),
                vesu_lending.into(),
                pragma_oracle.into(),
                owner.into()
            ]
        ).unwrap();
        
        VaultManagerDispatcher { contract_address }
    }

    #[test]
    fn test_deploy() {
        let owner = test_address();
        let btc_token: ContractAddress = 1.try_into().unwrap();
        let usdc_token: ContractAddress = 2.try_into().unwrap();
        let ekubo_pool: ContractAddress = 3.try_into().unwrap();
        let vesu_lending: ContractAddress = 4.try_into().unwrap();
        let pragma_oracle: ContractAddress = 5.try_into().unwrap();
        
        let sy_btc_token = deploy_sy_btc_token(owner);
        let vault = deploy_vault_manager(
            btc_token,
            usdc_token,
            sy_btc_token.contract_address,
            ekubo_pool,
            vesu_lending,
            pragma_oracle,
            owner
        );
        
        // Check initial state
        let dispatcher = IVaultManagerDispatcher { contract_address: vault.contract_address };
        let total_shares = dispatcher.get_total_shares();
        assert(total_shares == 0, 'Initial shares should be 0');
        
        let total_assets = dispatcher.get_total_assets();
        assert(total_assets == 0, 'Initial assets should be 0');
    }

    #[test]
    fn test_get_share_price_first_deposit() {
        let owner = test_address();
        let btc_token: ContractAddress = 1.try_into().unwrap();
        let usdc_token: ContractAddress = 2.try_into().unwrap();
        let ekubo_pool: ContractAddress = 3.try_into().unwrap();
        let vesu_lending: ContractAddress = 4.try_into().unwrap();
        let pragma_oracle: ContractAddress = 5.try_into().unwrap();
        
        let sy_btc_token = deploy_sy_btc_token(owner);
        let vault = deploy_vault_manager(
            btc_token,
            usdc_token,
            sy_btc_token.contract_address,
            ekubo_pool,
            vesu_lending,
            pragma_oracle,
            owner
        );
        
        // Share price should be 1.0 (1e18) when no shares exist
        let dispatcher = IVaultManagerDispatcher { contract_address: vault.contract_address };
        let share_price = dispatcher.get_share_price();
        let scale = 1000000000000000000; // 1e18
        assert(share_price == scale, 'Share price should be 1.0');
    }

    #[test]
    fn test_set_paused() {
        let owner = test_address();
        let btc_token: ContractAddress = 1.try_into().unwrap();
        let usdc_token: ContractAddress = 2.try_into().unwrap();
        let ekubo_pool: ContractAddress = 3.try_into().unwrap();
        let vesu_lending: ContractAddress = 4.try_into().unwrap();
        let pragma_oracle: ContractAddress = 5.try_into().unwrap();
        
        let sy_btc_token = deploy_sy_btc_token(owner);
        let vault = deploy_vault_manager(
            btc_token,
            usdc_token,
            sy_btc_token.contract_address,
            ekubo_pool,
            vesu_lending,
            pragma_oracle,
            owner
        );
        
        set_caller_address(owner);
        let mut dispatcher = IVaultManagerDispatcher { contract_address: vault.contract_address };
        dispatcher.set_paused(true);
        
        // Try to deposit while paused (should fail)
        // Note: This test would need proper error handling in real scenario
    }

    #[test]
    fn test_set_target_leverage() {
        let owner = test_address();
        let btc_token: ContractAddress = 1.try_into().unwrap();
        let usdc_token: ContractAddress = 2.try_into().unwrap();
        let ekubo_pool: ContractAddress = 3.try_into().unwrap();
        let vesu_lending: ContractAddress = 4.try_into().unwrap();
        let pragma_oracle: ContractAddress = 5.try_into().unwrap();
        
        let sy_btc_token = deploy_sy_btc_token(owner);
        let vault = deploy_vault_manager(
            btc_token,
            usdc_token,
            sy_btc_token.contract_address,
            ekubo_pool,
            vesu_lending,
            pragma_oracle,
            owner
        );
        
        set_caller_address(owner);
        let new_leverage = 2500000000000000000; // 2.5x
        let mut dispatcher = IVaultManagerDispatcher { contract_address: vault.contract_address };
        dispatcher.set_target_leverage(new_leverage);
        
        // Verify leverage was set (would need getter function)
    }
}
