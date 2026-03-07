//! GaugeController — Controls emission weights per gauge, voted by vesyYB holders.
//!
//! Security fixes (v2):
//!   - vote_for_gauge() checks caller's vesyYB balance (weight <= balance)
//!   - Per-voter, per-gauge weight tracking prevents double-voting
//!   - total_weight correctly updated (old voter weight removed, new added)

use starknet::ContractAddress;

/// Minimal ERC-20 balance query (for vesyYB token)
#[starknet::interface]
trait IERC20Balance<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IGaugeController<TContractState> {
    fn add_gauge(ref self: TContractState, gauge: ContractAddress, gauge_type: u8);
    fn vote_for_gauge(ref self: TContractState, gauge: ContractAddress, weight: u256);
    fn get_gauge_weight(self: @TContractState, gauge: ContractAddress) -> u256;
    fn get_total_weight(self: @TContractState) -> u256;
    fn get_voter_weight(self: @TContractState, voter: ContractAddress, gauge: ContractAddress) -> u256;
}

#[starknet::contract]
pub mod GaugeController {
    use super::{IGaugeController, ContractAddress, IERC20BalanceDispatcher, IERC20BalanceDispatcherTrait};
    use starknet::get_caller_address;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        owner:         ContractAddress,
        vesyyb_token:  ContractAddress,
        gauge_weights: Map<ContractAddress, u256>,
        gauge_active:  Map<ContractAddress, bool>,
        total_weight:  u256,
        /// Per-voter, per-gauge weight to prevent double-voting.
        voter_weight:  Map<(ContractAddress, ContractAddress), u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GaugeAdded: GaugeAdded,
        VoteCast:   VoteCast,
    }

    #[derive(Drop, starknet::Event)]
    struct GaugeAdded { gauge: ContractAddress, gauge_type: u8 }

    #[derive(Drop, starknet::Event)]
    struct VoteCast { voter: ContractAddress, gauge: ContractAddress, weight: u256 }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner:        ContractAddress,
        vesyyb_token: ContractAddress,
    ) {
        self.owner.write(owner);
        self.vesyyb_token.write(vesyyb_token);
    }

    #[abi(embed_v0)]
    impl GaugeControllerImpl of IGaugeController<ContractState> {
        fn add_gauge(ref self: ContractState, gauge: ContractAddress, gauge_type: u8) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.gauge_active.write(gauge, true);
            self.emit(GaugeAdded { gauge, gauge_type });
        }

        /// Vote for a gauge with a given weight.
        ///
        /// Security: weight is bounded by the caller's vesyYB balance.
        /// Previous vote by this caller for this gauge is retracted first.
        fn vote_for_gauge(ref self: ContractState, gauge: ContractAddress, weight: u256) {
            assert(self.gauge_active.read(gauge), 'Gauge not active');

            let caller = get_caller_address();

            // Bound weight to caller's vesyYB balance (skip if token not set)
            let vesyyb = self.vesyyb_token.read();
            let zero: ContractAddress = 0.try_into().unwrap();
            if vesyyb != zero {
                let balance = IERC20BalanceDispatcher { contract_address: vesyyb }
                    .balance_of(caller);
                assert(weight <= balance, 'Weight exceeds vesyYB balance');
            }

            // Retract caller's previous vote for this gauge
            let prev = self.voter_weight.read((caller, gauge));
            let gauge_w = self.gauge_weights.read(gauge);
            let total   = self.total_weight.read();

            self.voter_weight.write((caller, gauge), weight);
            self.gauge_weights.write(gauge, gauge_w - prev + weight);
            self.total_weight.write(total - prev + weight);

            self.emit(VoteCast { voter: caller, gauge, weight });
        }

        fn get_gauge_weight(self: @ContractState, gauge: ContractAddress) -> u256 {
            self.gauge_weights.read(gauge)
        }

        fn get_total_weight(self: @ContractState) -> u256 {
            self.total_weight.read()
        }

        fn get_voter_weight(
            self: @ContractState, voter: ContractAddress, gauge: ContractAddress,
        ) -> u256 {
            self.voter_weight.read((voter, gauge))
        }
    }
}
