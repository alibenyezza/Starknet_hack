//! VirtualPool — Atomic flash-loan rebalancer for LEVAMM
//!
//! Arbitrageurs call rebalance() when the LEVAMM DTV is outside its safety bands.
//! The contract:
//!   1. Detects the imbalance direction
//!   2. Executes the corrective swap (using mock adapters on testnet)
//!   3. Distributes a small profit to the caller as incentive
//!
//! On testnet, "flash loans" are simulated via MockLendingAdapter.borrow_usdc()
//! which mints tokens freely. A real implementation would use an actual flash-loan provider.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IVirtualPool<TContractState> {
    // ── View ──────────────────────────────────────────────────────────────
    fn can_rebalance(self: @TContractState) -> bool;
    fn get_imbalance_direction(self: @TContractState) -> bool; // true=under-levered, false=over-levered
    fn get_total_profit_distributed(self: @TContractState) -> u256;
    fn get_last_rebalance_block(self: @TContractState) -> u64;
    fn get_rebalance_cooldown(self: @TContractState) -> u64;

    // ── Mutating ──────────────────────────────────────────────────────────
    /// Execute rebalance: corrects LEVAMM DTV and pays profit to caller
    fn rebalance(ref self: TContractState) -> u256;

    // ── Admin ──────────────────────────────────────────────────────────────
    fn set_rebalance_cooldown(ref self: TContractState, blocks: u64);
    fn set_levamm(ref self: TContractState, levamm: ContractAddress);
    fn set_active(ref self: TContractState, active: bool);
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn set_owner(ref self: TContractState, new_owner: ContractAddress);
}

#[starknet::contract]
pub mod VirtualPool {
    use super::{IVirtualPool, ContractAddress};
    use starknet::{get_caller_address, get_block_number, get_contract_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starkyield::integrations::vesu::{IVesuAdapterDispatcher, IVesuAdapterDispatcherTrait};
    use starkyield::integrations::ekubo::{IEkuboAdapterDispatcher, IEkuboAdapterDispatcherTrait};
    use starkyield::amm::levamm::{ILevAMMDispatcher, ILevAMMDispatcherTrait};
    use starkyield::utils::constants::Constants;
    use starkyield::utils::math::Math;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        lending_adapter: ContractAddress,  // MockLendingAdapter (IVesuAdapter)
        ekubo_adapter: ContractAddress,    // MockEkuboAdapter (IEkuboAdapter)
        levamm: ContractAddress,           // LevAMM to rebalance
        last_rebalance_block: u64,
        rebalance_cooldown: u64,           // min blocks between rebalances
        total_profit_distributed: u256,
        is_active: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Rebalanced: Rebalanced,
        CooldownSet: CooldownSet,
        LevAMMSet: LevAMMSet,
        ActiveSet: ActiveSet,
    }

    #[derive(Drop, starknet::Event)]
    struct Rebalanced {
        direction: bool,       // true=under-levered correction, false=over-levered correction
        flash_amount: u256,
        profit: u256,
        caller: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct CooldownSet { blocks: u64 }

    #[derive(Drop, starknet::Event)]
    struct LevAMMSet { levamm: ContractAddress }

    #[derive(Drop, starknet::Event)]
    struct ActiveSet { active: bool }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        lending_adapter: ContractAddress,
        ekubo_adapter: ContractAddress,
        levamm: ContractAddress,
        rebalance_cooldown: u64,
    ) {
        self.owner.write(owner);
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.lending_adapter.write(lending_adapter);
        self.ekubo_adapter.write(ekubo_adapter);
        self.levamm.write(levamm);
        self.rebalance_cooldown.write(rebalance_cooldown);
        self.last_rebalance_block.write(0);
        self.total_profit_distributed.write(0);
        self.is_active.write(true);
    }

    #[abi(embed_v0)]
    impl VirtualPoolImpl of IVirtualPool<ContractState> {
        fn can_rebalance(self: @ContractState) -> bool {
            if !self.is_active.read() { return false; }
            let lev = self.levamm.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if lev == zero { return false; }
            let levamm = ILevAMMDispatcher { contract_address: lev };
            if !levamm.is_active() { return false; }
            let current = get_block_number();
            let last = self.last_rebalance_block.read();
            let cooldown = self.rebalance_cooldown.read();
            if current < last + cooldown { return false; }
            // Check if actually imbalanced
            levamm.is_over_levered() || levamm.is_under_levered()
        }

        fn get_imbalance_direction(self: @ContractState) -> bool {
            // true = under-levered (DTV too low, need to increase debt)
            let lev = self.levamm.read();
            let zero: ContractAddress = 0_felt252.try_into().unwrap();
            if lev == zero { return false; }
            ILevAMMDispatcher { contract_address: lev }.is_under_levered()
        }

        fn get_total_profit_distributed(self: @ContractState) -> u256 {
            self.total_profit_distributed.read()
        }

        fn get_last_rebalance_block(self: @ContractState) -> u64 {
            self.last_rebalance_block.read()
        }

        fn get_rebalance_cooldown(self: @ContractState) -> u64 {
            self.rebalance_cooldown.read()
        }

        fn rebalance(ref self: ContractState) -> u256 {
            assert(self.can_rebalance(), 'Cannot rebalance now');

            let levamm = ILevAMMDispatcher { contract_address: self.levamm.read() };
            let caller = get_caller_address();

            // Accrue interest first so DTV is up-to-date
            levamm.accrue_interest();

            let dtv = levamm.get_dtv();
            let c = levamm.get_collateral_value();

            // Cairo requires all let bindings to be initialized at declaration.
            // Use if/else expressions returning a (direction, flash_amount, profit) tuple.
            let (direction, flash_amount, profit) = if dtv < Constants::DTV_MIN_2X {
                // ── Under-levered: DTV too low ──────────────────────────────
                // The LP position grew in value but debt stayed fixed.
                // Solution: borrow more USDC (flash), provide more liquidity,
                //           capture the premium from buying LP at current price.
                let target_dtv = (Constants::DTV_MAX_2X + Constants::DTV_MIN_2X) / 2;
                let dtv_delta = target_dtv - dtv;
                let fa: u256 = Math::mul_fixed(dtv_delta, c);

                let p: u256 = if fa > 0 {
                    // 1. Flash-borrow USDC via MockLending (mints freely on testnet)
                    let lending = IVesuAdapterDispatcher { contract_address: self.lending_adapter.read() };
                    lending.borrow_usdc(fa);

                    // 2. Swap half USDC → BTC via MockEkubo (deepens the LP position)
                    let ekubo = IEkuboAdapterDispatcher { contract_address: self.ekubo_adapter.read() };
                    let half = fa / 2;
                    if half > 0 {
                        ekubo.swap_usdc_to_btc(half, 0);
                    }

                    // 3. Capture 1% of half as arbitrage profit
                    let arb_amount: u256 = if half > 0 { half / 100 } else { 0 };

                    // 4. Repay flash loan
                    lending.repay_usdc(fa);

                    arb_amount
                } else {
                    0_u256
                };

                (true, fa, p)
            } else {
                // ── Over-levered: DTV too high ──────────────────────────────
                // Debt grew faster than collateral (e.g. BTC price dropped).
                // Solution: unwind some LP, repay debt, capture the discount.
                let target_dtv = (Constants::DTV_MAX_2X + Constants::DTV_MIN_2X) / 2;
                let dtv_delta = dtv - target_dtv;
                let fa: u256 = Math::mul_fixed(dtv_delta, c);

                let p: u256 = if fa > 0 {
                    // 1. Swap BTC → USDC via MockEkubo (simulate LP unwind)
                    let ekubo = IEkuboAdapterDispatcher { contract_address: self.ekubo_adapter.read() };
                    let price = levamm.get_current_btc_price();
                    let btc_to_sell: u256 = if price > 0 {
                        Math::div_fixed(fa, price)
                    } else {
                        0_u256
                    };
                    if btc_to_sell > 0 {
                        ekubo.swap_btc_to_usdc(btc_to_sell, 0);
                    }

                    // 2. Repay portion of LEVAMM debt
                    let lending = IVesuAdapterDispatcher { contract_address: self.lending_adapter.read() };
                    lending.repay_usdc(fa);

                    // 3. Profit = 1% discount captured from selling into over-levered LEVAMM
                    fa / 100
                } else {
                    0_u256
                };

                (false, fa, p)
            };

            // Transfer profit to caller (arbitrageur incentive)
            if profit > 0 {
                let usdc = IERC20Dispatcher { contract_address: self.usdc_token.read() };
                // Best-effort transfer — don't fail the rebalance if balance is low
                let balance = usdc.balance_of(get_contract_address());
                let actual_profit = if balance >= profit { profit } else { balance };
                if actual_profit > 0 {
                    usdc.transfer(caller, actual_profit);
                    self.total_profit_distributed.write(
                        self.total_profit_distributed.read() + actual_profit
                    );
                }
            }

            self.last_rebalance_block.write(get_block_number());
            self.emit(Rebalanced { direction, flash_amount, profit, caller });

            profit
        }

        fn set_rebalance_cooldown(ref self: ContractState, blocks: u64) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.rebalance_cooldown.write(blocks);
            self.emit(CooldownSet { blocks });
        }

        fn set_levamm(ref self: ContractState, levamm: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.levamm.write(levamm);
            self.emit(LevAMMSet { levamm });
        }

        fn set_active(ref self: ContractState, active: bool) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.is_active.write(active);
            self.emit(ActiveSet { active });
        }

        fn get_owner(self: @ContractState) -> ContractAddress { self.owner.read() }

        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.owner.write(new_owner);
        }
    }
}
