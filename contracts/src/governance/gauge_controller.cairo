//! GaugeController — Stub
//! Controls emission weights per gauge, voted by vesyYB holders.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IGaugeController<TContractState> {
    fn add_gauge(ref self: TContractState, gauge: ContractAddress, gauge_type: u8);
    fn vote_for_gauge(ref self: TContractState, gauge: ContractAddress, weight: u256);
    fn get_gauge_weight(self: @TContractState, gauge: ContractAddress) -> u256;
    fn get_total_weight(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod GaugeController {
    use super::{IGaugeController, ContractAddress};
    use starknet::get_caller_address;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        gauge_weights: Map<ContractAddress, u256>,
        gauge_active: Map<ContractAddress, bool>,
        total_weight: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GaugeAdded: GaugeAdded,
        VoteCast: VoteCast,
    }

    #[derive(Drop, starknet::Event)]
    struct GaugeAdded { gauge: ContractAddress, gauge_type: u8 }

    #[derive(Drop, starknet::Event)]
    struct VoteCast { voter: ContractAddress, gauge: ContractAddress, weight: u256 }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl GaugeControllerImpl of IGaugeController<ContractState> {
        fn add_gauge(ref self: ContractState, gauge: ContractAddress, gauge_type: u8) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.gauge_active.write(gauge, true);
            self.emit(GaugeAdded { gauge, gauge_type });
        }

        fn vote_for_gauge(ref self: ContractState, gauge: ContractAddress, weight: u256) {
            assert(self.gauge_active.read(gauge), 'Gauge not active');
            let old_weight = self.gauge_weights.read(gauge);
            let total = self.total_weight.read();
            self.total_weight.write(total - old_weight + weight);
            self.gauge_weights.write(gauge, weight);
            self.emit(VoteCast { voter: get_caller_address(), gauge, weight });
        }

        fn get_gauge_weight(self: @ContractState, gauge: ContractAddress) -> u256 {
            self.gauge_weights.read(gauge)
        }

        fn get_total_weight(self: @ContractState) -> u256 {
            self.total_weight.read()
        }
    }
}
