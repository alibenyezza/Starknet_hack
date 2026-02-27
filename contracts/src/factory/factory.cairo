//! Factory — Central market registry for StarkYield
//!
//! Registers and manages StarkYield markets (BTC, ETH, etc.).
//! Each market gets an isolated set of contracts (LT, LEVAMM, VirtualPool, Staker).
//! Blueprint class hashes are stored for future deployments/upgrades.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IFactory<TContractState> {
    /// Register a new market for the given asset token
    fn deploy_market(ref self: TContractState, asset: ContractAddress) -> u64;
    /// Set USDC allocation available for a market
    fn set_allocation(ref self: TContractState, market_id: u64, amount: u256);
    /// Set maximum USDC debt ceiling for a market
    fn set_debt_ceiling(ref self: TContractState, market_id: u64, ceiling: u256);
    /// Register deployed contract addresses for a market
    fn set_market_contracts(
        ref self: TContractState,
        market_id: u64,
        lt: ContractAddress,
        levamm: ContractAddress,
        virtual_pool: ContractAddress,
        staker: ContractAddress,
    );
    /// Read market info: (asset, lt, levamm, vpool, staker, allocation, ceiling, active)
    fn get_market_info(self: @TContractState, market_id: u64)
        -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress, ContractAddress, u256, u256, bool);
    fn get_market_count(self: @TContractState) -> u64;
    /// Store a blueprint class hash for a contract type ('levamm', 'virtual_pool', etc.)
    fn upgrade_implementation(ref self: TContractState, contract_type: felt252, class_hash: felt252);
    fn get_implementation(self: @TContractState, contract_type: felt252) -> felt252;
    fn set_owner(ref self: TContractState, new_owner: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod Factory {
    use super::{IFactory, ContractAddress};
    use starknet::get_caller_address;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        owner: ContractAddress,
        // Market count
        market_count: u64,
        // Per-market: asset token
        market_asset: Map<u64, ContractAddress>,
        // Per-market: deployed contracts
        market_lt: Map<u64, ContractAddress>,
        market_levamm: Map<u64, ContractAddress>,
        market_vpool: Map<u64, ContractAddress>,
        market_staker: Map<u64, ContractAddress>,
        // Per-market: risk params
        market_allocation: Map<u64, u256>,
        market_debt_ceiling: Map<u64, u256>,
        market_active: Map<u64, bool>,
        // Blueprint class hashes
        implementations: Map<felt252, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MarketDeployed: MarketDeployed,
        AllocationSet: AllocationSet,
        DebtCeilingSet: DebtCeilingSet,
        ImplementationUpgraded: ImplementationUpgraded,
        OwnershipTransferred: OwnershipTransferred,
    }

    #[derive(Drop, starknet::Event)]
    struct MarketDeployed { market_id: u64, asset: ContractAddress }

    #[derive(Drop, starknet::Event)]
    struct AllocationSet { market_id: u64, amount: u256 }

    #[derive(Drop, starknet::Event)]
    struct DebtCeilingSet { market_id: u64, ceiling: u256 }

    #[derive(Drop, starknet::Event)]
    struct ImplementationUpgraded { contract_type: felt252, class_hash: felt252 }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred { previous: ContractAddress, new_owner: ContractAddress }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.market_count.write(0);
    }

    #[abi(embed_v0)]
    impl FactoryImpl of IFactory<ContractState> {
        fn deploy_market(ref self: ContractState, asset: ContractAddress) -> u64 {
            self._assert_owner();
            let id = self.market_count.read();
            self.market_asset.write(id, asset);
            self.market_active.write(id, true);
            self.market_count.write(id + 1);
            self.emit(MarketDeployed { market_id: id, asset });
            id
        }

        fn set_allocation(ref self: ContractState, market_id: u64, amount: u256) {
            self._assert_owner();
            assert(self.market_active.read(market_id), 'Market not active');
            self.market_allocation.write(market_id, amount);
            self.emit(AllocationSet { market_id, amount });
        }

        fn set_debt_ceiling(ref self: ContractState, market_id: u64, ceiling: u256) {
            self._assert_owner();
            assert(self.market_active.read(market_id), 'Market not active');
            self.market_debt_ceiling.write(market_id, ceiling);
            self.emit(DebtCeilingSet { market_id, ceiling });
        }

        fn set_market_contracts(
            ref self: ContractState,
            market_id: u64,
            lt: ContractAddress,
            levamm: ContractAddress,
            virtual_pool: ContractAddress,
            staker: ContractAddress,
        ) {
            self._assert_owner();
            assert(self.market_active.read(market_id), 'Market not active');
            self.market_lt.write(market_id, lt);
            self.market_levamm.write(market_id, levamm);
            self.market_vpool.write(market_id, virtual_pool);
            self.market_staker.write(market_id, staker);
        }

        fn get_market_info(self: @ContractState, market_id: u64)
            -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress, ContractAddress, u256, u256, bool) {
            (
                self.market_asset.read(market_id),
                self.market_lt.read(market_id),
                self.market_levamm.read(market_id),
                self.market_vpool.read(market_id),
                self.market_staker.read(market_id),
                self.market_allocation.read(market_id),
                self.market_debt_ceiling.read(market_id),
                self.market_active.read(market_id),
            )
        }

        fn get_market_count(self: @ContractState) -> u64 {
            self.market_count.read()
        }

        fn upgrade_implementation(ref self: ContractState, contract_type: felt252, class_hash: felt252) {
            self._assert_owner();
            self.implementations.write(contract_type, class_hash);
            self.emit(ImplementationUpgraded { contract_type, class_hash });
        }

        fn get_implementation(self: @ContractState, contract_type: felt252) -> felt252 {
            self.implementations.read(contract_type)
        }

        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            self._assert_owner();
            let previous = self.owner.read();
            self.owner.write(new_owner);
            self.emit(OwnershipTransferred { previous, new_owner });
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_owner(self: @ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
        }
    }
}
