//! EkuboLPWrapper — Bunni-inspired ERC-20 wrapper for Ekubo LP positions
//!
//! Wraps an Ekubo LP position (BTC + USDC) into fungible ERC-20 shares so that
//! Vesu can accept it as collateral (Vesu requires ERC-20, not NFT).
//!
//! Share pricing (Bunni pattern):
//!   First deposit: shares = liquidity - MIN_INITIAL_SHARES  (MIN_INITIAL_SHARES burned → address(0))
//!   Later deposits: shares = totalSupply × addedLiquidity / existingLiquidity
//!
//! LP value proxy: we use the mock Ekubo adapter's get_lp_value() which returns
//! total USD value of the tracked BTC+USDC reserves.

use starknet::ContractAddress;

// ── Interfaces ────────────────────────────────────────────────────────────────

#[starknet::interface]
pub trait IEkuboLPWrapper<TContractState> {
    /// Deposit BTC + USDC, receive ERC-20 shares.
    /// Caller must approve this contract for both tokens.
    fn deposit(ref self: TContractState, btc_amount: u256, usdc_amount: u256) -> u256;
    /// Burn `shares`, receive proportional BTC + USDC.
    fn withdraw(ref self: TContractState, shares: u256) -> (u256, u256);
    /// Current total LP value in USDC units (proxy for NAV).
    fn get_lp_value(self: @TContractState) -> u256;
    fn get_owner(self: @TContractState) -> ContractAddress;
}

// ── Minimal local facades ─────────────────────────────────────────────────────

#[starknet::interface]
trait IERC20Facade<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn total_supply(self: @TContractState) -> u256;
}

#[starknet::interface]
trait IEkuboFacade<TContractState> {
    fn add_liquidity(ref self: TContractState, btc_amount: u256, usdc_amount: u256) -> u64;
    fn remove_liquidity(ref self: TContractState, token_id: u64) -> (u256, u256);
    fn get_lp_value(self: @TContractState, token_id: u64) -> u256;
}

// ── Minimal ERC-20 for the wrapper shares ─────────────────────────────────────

use openzeppelin::token::erc20::{ERC20HooksEmptyImpl, ERC20Component};

#[starknet::contract]
pub mod EkuboLPWrapper {
    use super::{
        IEkuboLPWrapper, ContractAddress,
        IERC20FacadeDispatcher,   IERC20FacadeDispatcherTrait,
        IEkuboFacadeDispatcher,   IEkuboFacadeDispatcherTrait,
        ERC20Component, ERC20HooksEmptyImpl,
    };
    use starknet::{get_caller_address, get_contract_address};
    use starkyield::utils::constants::Constants;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    /// Wrapper shares: 18 decimals (internal precision).
    pub impl Config of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 18;
    }
    impl ERC20HooksImpl = ERC20HooksEmptyImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        owner:         ContractAddress,
        btc_token:     ContractAddress,
        usdc_token:    ContractAddress,
        ekubo_adapter: ContractAddress,
        /// LP token_id currently held (mock: always 1)
        lp_token_id:   u64,
        /// Total BTC deposited into this wrapper (tracks our share of the LP)
        lp_btc:        u256,
        /// Total USDC deposited into this wrapper
        lp_usdc:       u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        Deposited: Deposited,
        Withdrawn: Withdrawn,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposited {
        depositor: ContractAddress,
        btc_in:    u256,
        usdc_in:   u256,
        shares:    u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        withdrawer: ContractAddress,
        shares:     u256,
        btc_out:    u256,
        usdc_out:   u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner:         ContractAddress,
        btc_token:     ContractAddress,
        usdc_token:    ContractAddress,
        ekubo_adapter: ContractAddress,
    ) {
        self.erc20.initializer("Ekubo LP Wrapper", "wELP");
        self.owner.write(owner);
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.ekubo_adapter.write(ekubo_adapter);
        self.lp_token_id.write(0);
        self.lp_btc.write(0);
        self.lp_usdc.write(0);
    }

    #[abi(embed_v0)]
    impl EkuboLPWrapperImpl of IEkuboLPWrapper<ContractState> {
        /// Deposit BTC + USDC → ERC-20 shares.
        ///
        /// First deposit:
        ///   liquidity = btc_amount (proxy — we track BTC units as liquidity)
        ///   shares_minted = liquidity - MIN_INITIAL_SHARES
        ///   MIN_INITIAL_SHARES burned to zero address (inflation guard)
        ///
        /// Subsequent deposits:
        ///   shares_minted = totalSupply × btc_amount / existing_btc_lp
        fn deposit(ref self: ContractState, btc_amount: u256, usdc_amount: u256) -> u256 {
            assert(btc_amount > 0, 'BTC amount must be > 0');

            let caller  = get_caller_address();
            let this    = get_contract_address();
            let btc_tok = self.btc_token.read();
            let usd_tok = self.usdc_token.read();
            let ekubo   = IEkuboFacadeDispatcher { contract_address: self.ekubo_adapter.read() };
            let btc     = IERC20FacadeDispatcher { contract_address: btc_tok };
            let usdc    = IERC20FacadeDispatcher { contract_address: usd_tok };

            // Pull tokens from caller
            let ok_btc = btc.transfer_from(caller, this, btc_amount);
            assert(ok_btc, 'BTC transfer_from failed');
            if usdc_amount > 0 {
                let ok_usd = usdc.transfer_from(caller, this, usdc_amount);
                assert(ok_usd, 'USDC transfer_from failed');
            }

            // Approve ekubo adapter and add liquidity
            btc.approve(self.ekubo_adapter.read(), btc_amount);
            if usdc_amount > 0 {
                usdc.approve(self.ekubo_adapter.read(), usdc_amount);
            }
            let new_lp_id = ekubo.add_liquidity(btc_amount, usdc_amount);
            self.lp_token_id.write(new_lp_id);

            // Calculate shares (Bunni pattern)
            let total_supply = self.erc20.total_supply();
            let existing_btc = self.lp_btc.read();

            let shares: u256 = if total_supply == 0 || existing_btc == 0 {
                // First deposit: burn MIN_INITIAL_SHARES as inflation guard
                let liquidity = btc_amount;
                assert(liquidity > Constants::MIN_INITIAL_SHARES, 'Deposit too small');
                let dead: ContractAddress = 0.try_into().unwrap();
                self.erc20.mint(dead, Constants::MIN_INITIAL_SHARES);
                liquidity - Constants::MIN_INITIAL_SHARES
            } else {
                // Pro-rata: shares = totalSupply * btc_in / existing_btc
                total_supply * btc_amount / existing_btc
            };

            assert(shares > 0, 'Zero shares minted');

            // Update tracked reserves
            self.lp_btc.write(existing_btc + btc_amount);
            self.lp_usdc.write(self.lp_usdc.read() + usdc_amount);

            // Mint shares to depositor
            self.erc20.mint(caller, shares);

            self.emit(Deposited { depositor: caller, btc_in: btc_amount, usdc_in: usdc_amount, shares });

            shares
        }

        /// Burn shares → proportional BTC + USDC returned to caller.
        fn withdraw(ref self: ContractState, shares: u256) -> (u256, u256) {
            assert(shares > 0, 'Shares must be > 0');

            let caller       = get_caller_address();
            let total_supply = self.erc20.total_supply();
            assert(shares <= total_supply, 'Shares exceed supply');

            let existing_btc  = self.lp_btc.read();
            let existing_usdc = self.lp_usdc.read();

            // Pro-rata amounts
            let btc_out  = existing_btc  * shares / total_supply;
            let usdc_out = existing_usdc * shares / total_supply;

            // Remove full LP from ekubo, re-add remainder
            let lp_id = self.lp_token_id.read();
            let ekubo = IEkuboFacadeDispatcher { contract_address: self.ekubo_adapter.read() };
            let btc   = IERC20FacadeDispatcher { contract_address: self.btc_token.read() };
            let usdc  = IERC20FacadeDispatcher { contract_address: self.usdc_token.read() };
            // Remove all LP (mock returns everything)
            ekubo.remove_liquidity(lp_id);

            // Re-add remaining LP for other share-holders
            let remaining_btc  = existing_btc  - btc_out;
            let remaining_usdc = existing_usdc - usdc_out;
            if remaining_btc > 0 {
                btc.approve(self.ekubo_adapter.read(), remaining_btc);
                if remaining_usdc > 0 {
                    usdc.approve(self.ekubo_adapter.read(), remaining_usdc);
                }
                let new_lp_id = ekubo.add_liquidity(remaining_btc, remaining_usdc);
                self.lp_token_id.write(new_lp_id);
            } else {
                self.lp_token_id.write(0);
            }

            // Update tracked reserves
            self.lp_btc.write(remaining_btc);
            self.lp_usdc.write(remaining_usdc);

            // Burn shares
            self.erc20.burn(caller, shares);

            // Transfer tokens to caller
            if btc_out > 0 {
                btc.transfer(caller, btc_out);
            }
            if usdc_out > 0 {
                usdc.transfer(caller, usdc_out);
            }

            self.emit(Withdrawn { withdrawer: caller, shares, btc_out, usdc_out });

            (btc_out, usdc_out)
        }

        fn get_lp_value(self: @ContractState) -> u256 {
            let ekubo = IEkuboFacadeDispatcher { contract_address: self.ekubo_adapter.read() };
            ekubo.get_lp_value(self.lp_token_id.read())
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
