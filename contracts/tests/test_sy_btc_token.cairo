//! Tests for syBTC Token contract

use starknet::ContractAddress;
use starkyield::vault::sy_btc_token::{ISyBtcTokenDispatcher, ISyBtcTokenDispatcherTrait};
use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use core::traits::TryInto;

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait, test_address,
        start_cheat_caller_address, stop_cheat_caller_address,
    };

    fn deploy_sy_btc_token(owner: ContractAddress) -> (ISyBtcTokenDispatcher, IERC20Dispatcher) {
        let contract_class = declare("SyBtcToken").unwrap().contract_class();
        let mut calldata: Array<felt252> = array![];
        calldata.append(0);
        calldata.append('StarkYield BTC');
        calldata.append(14);
        calldata.append(0);
        calldata.append('syBTC');
        calldata.append(5);
        calldata.append(owner.into());

        let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
        (
            ISyBtcTokenDispatcher { contract_address },
            IERC20Dispatcher { contract_address },
        )
    }

    #[test]
    fn test_deploy() {
        let owner = test_address();
        let (_token, erc20) = deploy_sy_btc_token(owner);

        let total_supply = erc20.total_supply();
        assert(total_supply == 0, 'Initial supply should be 0');
    }

    #[test]
    fn test_mint() {
        let owner = test_address();
        let user: ContractAddress = 0x123.try_into().unwrap();
        let (token, erc20) = deploy_sy_btc_token(owner);

        start_cheat_caller_address(token.contract_address, owner);

        let amount = 1000 * 1_000000000000000000_u256;
        token.mint(user, amount);

        stop_cheat_caller_address(token.contract_address);

        let balance = erc20.balance_of(user);
        assert(balance == amount, 'Wrong balance');

        let total_supply = erc20.total_supply();
        assert(total_supply == amount, 'Wrong total supply');
    }

    #[test]
    #[should_panic]
    fn test_mint_only_owner() {
        let owner = test_address();
        let user: ContractAddress = 0x123.try_into().unwrap();
        let (token, _erc20) = deploy_sy_btc_token(owner);

        start_cheat_caller_address(token.contract_address, user);
        let amount = 1000 * 1_000000000000000000_u256;
        token.mint(user, amount);
    }

    #[test]
    fn test_burn() {
        let owner = test_address();
        let user: ContractAddress = 0x123.try_into().unwrap();
        let (token, erc20) = deploy_sy_btc_token(owner);

        start_cheat_caller_address(token.contract_address, owner);

        let amount = 1000 * 1_000000000000000000_u256;
        token.mint(user, amount);

        let burn_amount = amount / 2;
        token.burn(user, burn_amount);

        stop_cheat_caller_address(token.contract_address);

        let balance = erc20.balance_of(user);
        assert(balance == amount - burn_amount, 'Wrong balance after burn');

        let total_supply = erc20.total_supply();
        assert(total_supply == amount - burn_amount, 'Wrong supply after burn');
    }

    #[test]
    fn test_transfer() {
        let owner = test_address();
        let user1: ContractAddress = 0x123.try_into().unwrap();
        let user2: ContractAddress = 0x456.try_into().unwrap();
        let (token, erc20) = deploy_sy_btc_token(owner);

        start_cheat_caller_address(token.contract_address, owner);
        let amount = 1000 * 1_000000000000000000_u256;
        token.mint(user1, amount);
        stop_cheat_caller_address(token.contract_address);

        start_cheat_caller_address(erc20.contract_address, user1);
        let transfer_amount = 500 * 1_000000000000000000_u256;
        erc20.transfer(user2, transfer_amount);
        stop_cheat_caller_address(erc20.contract_address);

        assert(erc20.balance_of(user1) == amount - transfer_amount, 'Wrong sender balance');
        assert(erc20.balance_of(user2) == transfer_amount, 'Wrong recipient balance');
    }
}
