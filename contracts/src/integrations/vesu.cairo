use starknet::ContractAddress;

/// Interface for Vesu Lending protocol on Starknet
#[starknet::interface]
pub trait IVesuLending<TContractState> {
    fn deposit(ref self: TContractState, token: ContractAddress, amount: u256);
    fn withdraw(ref self: TContractState, token: ContractAddress, amount: u256);
    fn borrow(ref self: TContractState, token: ContractAddress, amount: u256);
    fn repay(ref self: TContractState, token: ContractAddress, amount: u256);
    fn get_deposit_balance(self: @TContractState, user: ContractAddress, token: ContractAddress) -> u256;
    fn get_borrow_balance(self: @TContractState, user: ContractAddress, token: ContractAddress) -> u256;
}

/// StarkYield Vesu Adapter interface
#[starknet::interface]
pub trait IVesuAdapter<TContractState> {
    fn deposit_collateral(ref self: TContractState, btc_amount: u256);
    fn withdraw_collateral(ref self: TContractState, btc_amount: u256);
    fn borrow_usdc(ref self: TContractState, usdc_amount: u256);
    fn repay_usdc(ref self: TContractState, usdc_amount: u256);
    fn get_collateral_balance(self: @TContractState) -> u256;
    fn get_debt_balance(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod VesuAdapter {
    use super::{
        ContractAddress, IVesuAdapter,
        IVesuLendingDispatcher, IVesuLendingDispatcherTrait,
    };
    use starknet::get_contract_address;
    use starkyield::integrations::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        vesu_lending: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        vesu_lending: ContractAddress,
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        owner: ContractAddress,
    ) {
        self.vesu_lending.write(vesu_lending);
        self.btc_token.write(btc_token);
        self.usdc_token.write(usdc_token);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl VesuAdapterImpl of IVesuAdapter<ContractState> {
        /// Deposit BTC as collateral on Vesu
        fn deposit_collateral(ref self: ContractState, btc_amount: u256) {
            assert(btc_amount > 0, 'Amount must be > 0');

            let vesu = IVesuLendingDispatcher {
                contract_address: self.vesu_lending.read(),
            };

            // Approve Vesu to spend BTC
            let btc = IERC20Dispatcher { contract_address: self.btc_token.read() };
            btc.approve(self.vesu_lending.read(), btc_amount);

            vesu.deposit(self.btc_token.read(), btc_amount);
        }

        /// Withdraw BTC collateral from Vesu
        fn withdraw_collateral(ref self: ContractState, btc_amount: u256) {
            assert(btc_amount > 0, 'Amount must be > 0');

            let vesu = IVesuLendingDispatcher {
                contract_address: self.vesu_lending.read(),
            };

            vesu.withdraw(self.btc_token.read(), btc_amount);
        }

        /// Borrow USDC against BTC collateral
        fn borrow_usdc(ref self: ContractState, usdc_amount: u256) {
            assert(usdc_amount > 0, 'Amount must be > 0');

            let vesu = IVesuLendingDispatcher {
                contract_address: self.vesu_lending.read(),
            };

            vesu.borrow(self.usdc_token.read(), usdc_amount);
        }

        /// Repay USDC debt
        fn repay_usdc(ref self: ContractState, usdc_amount: u256) {
            assert(usdc_amount > 0, 'Amount must be > 0');

            let vesu = IVesuLendingDispatcher {
                contract_address: self.vesu_lending.read(),
            };

            // Approve Vesu to spend USDC for repayment
            let usdc = IERC20Dispatcher { contract_address: self.usdc_token.read() };
            usdc.approve(self.vesu_lending.read(), usdc_amount);

            vesu.repay(self.usdc_token.read(), usdc_amount);
        }

        /// Get current BTC collateral deposited
        fn get_collateral_balance(self: @ContractState) -> u256 {
            let vesu = IVesuLendingDispatcher {
                contract_address: self.vesu_lending.read(),
            };
            vesu.get_deposit_balance(get_contract_address(), self.btc_token.read())
        }

        /// Get current USDC debt
        fn get_debt_balance(self: @ContractState) -> u256 {
            let vesu = IVesuLendingDispatcher {
                contract_address: self.vesu_lending.read(),
            };
            vesu.get_borrow_balance(get_contract_address(), self.usdc_token.read())
        }
    }
}
