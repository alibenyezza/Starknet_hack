//! Tests for syBTC Token contract

use starknet::ContractAddress;
use starknet::testing::set_caller_address;
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

    #[test]
    fn test_deploy() {
        let owner = test_address();
        let token = deploy_sy_btc_token(owner);
        
        // Check name
        let name = token.name();
        assert(name == ByteArray::from("StarkYield BTC"), 'Wrong name');
        
        // Check symbol
        let symbol = token.symbol();
        assert(symbol == ByteArray::from("syBTC"), 'Wrong symbol');
        
        // Check decimals
        let decimals = token.decimals();
        assert(decimals == 18, 'Wrong decimals');
        
        // Check initial supply
        let total_supply = token.total_supply();
        assert(total_supply == 0, 'Initial supply should be 0');
    }

    #[test]
    fn test_mint() {
        let owner = test_address();
        let user: ContractAddress = 0x123.try_into().unwrap();
        let token = deploy_sy_btc_token(owner);
        
        set_caller_address(owner);
        
        // Mint 1000 tokens
        let amount = 1000 * 10_u256.pow(18);
        token.mint(user, amount);
        
        // Check balance
        let balance = token.balance_of(user);
        assert(balance == amount, 'Wrong balance');
        
        // Check total supply
        let total_supply = token.total_supply();
        assert(total_supply == amount, 'Wrong total supply');
    }

    #[test]
    #[should_panic]
    fn test_mint_only_owner() {
        let owner = test_address();
        let user: ContractAddress = 0x123.try_into().unwrap();
        let token = deploy_sy_btc_token(owner);
        
        set_caller_address(user);
        
        // Try to mint as non-owner (should fail)
        let amount = 1000 * 10_u256.pow(18);
        token.mint(user, amount);
    }

    #[test]
    fn test_burn() {
        let owner = test_address();
        let user: ContractAddress = 0x123.try_into().unwrap();
        let token = deploy_sy_btc_token(owner);
        
        set_caller_address(owner);
        
        // Mint first
        let amount = 1000 * 10_u256.pow(18);
        token.mint(user, amount);
        
        // Burn half
        let burn_amount = amount / 2;
        token.burn(user, burn_amount);
        
        // Check balance
        let balance = token.balance_of(user);
        assert(balance == amount - burn_amount, 'Wrong balance after burn');
        
        // Check total supply
        let total_supply = token.total_supply();
        assert(total_supply == amount - burn_amount, 'Wrong total supply after burn');
    }

    #[test]
    fn test_transfer() {
        let owner = test_address();
        let user1: ContractAddress = 0x123.try_into().unwrap();
        let user2: ContractAddress = 0x456.try_into().unwrap();
        let token = deploy_sy_btc_token(owner);
        
        set_caller_address(owner);
        let amount = 1000 * 10_u256.pow(18);
        token.mint(user1, amount);
        
        // Transfer
        set_caller_address(user1);
        let transfer_amount = 500 * 10_u256.pow(18);
        token.transfer(user2, transfer_amount);
        
        // Check balances
        assert(token.balance_of(user1) == amount - transfer_amount, 'Wrong sender balance');
        assert(token.balance_of(user2) == transfer_amount, 'Wrong recipient balance');
    }
}
