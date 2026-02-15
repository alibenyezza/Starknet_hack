//! Tests for IL Eliminator engine

use starkyield::strategy::il_eliminator::{IILEliminatorDispatcher, IILEliminatorDispatcherTrait};

#[cfg(test)]
mod tests {
    use super::*;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

    const SCALE: u256 = 1_000000000000000000;

    fn deploy_il_eliminator() -> IILEliminatorDispatcher {
        let contract_class = declare("ILEliminator").unwrap().contract_class();
        let (contract_address, _) = contract_class.deploy(@array![]).unwrap();
        IILEliminatorDispatcher { contract_address }
    }

    // ═══════════════════════════════════════════════════════
    // IL CALCULATION TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_il_no_price_change() {
        let il_engine = deploy_il_eliminator();
        let entry_price = 60000 * SCALE;
        let current_price = 60000 * SCALE;

        let (il, is_loss) = il_engine.calculate_il(entry_price, current_price);
        assert(il == 0, 'IL should be 0 when no change');
        assert(!is_loss, 'Should not be loss');
    }

    #[test]
    fn test_il_price_increase_50pct() {
        let il_engine = deploy_il_eliminator();
        let entry_price = 60000 * SCALE;
        let current_price = 90000 * SCALE;

        let (il, is_loss) = il_engine.calculate_il(entry_price, current_price);

        assert(is_loss, 'Should be a loss');
        // IL for 50% increase ≈ 2%
        let min_il = SCALE * 15 / 1000; // 1.5%
        let max_il = SCALE * 25 / 1000; // 2.5%
        assert(il >= min_il, 'IL too low for 50pct increase');
        assert(il <= max_il, 'IL too high for 50pct increase');
    }

    #[test]
    fn test_il_price_decrease_50pct() {
        let il_engine = deploy_il_eliminator();
        let entry_price = 60000 * SCALE;
        let current_price = 30000 * SCALE;

        let (il, is_loss) = il_engine.calculate_il(entry_price, current_price);

        assert(is_loss, 'Should be a loss');
        let min_il = SCALE * 50 / 1000; // 5%
        let max_il = SCALE * 65 / 1000; // 6.5%
        assert(il >= min_il, 'IL too low for 50pct decrease');
        assert(il <= max_il, 'IL too high for 50pct decrease');
    }

    #[test]
    fn test_il_price_double() {
        let il_engine = deploy_il_eliminator();
        let entry_price = 60000 * SCALE;
        let current_price = 120000 * SCALE;

        let (il, is_loss) = il_engine.calculate_il(entry_price, current_price);

        assert(is_loss, 'Should be a loss');
        let min_il = SCALE * 50 / 1000;
        let max_il = SCALE * 65 / 1000;
        assert(il >= min_il, 'IL too low for 2x price');
        assert(il <= max_il, 'IL too high for 2x price');
    }

    // ═══════════════════════════════════════════════════════
    // LEVERAGE PNL TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_leverage_pnl_price_up() {
        let il_engine = deploy_il_eliminator();
        let entry_price = 60000 * SCALE;
        let current_price = 90000 * SCALE;
        let leverage = 2 * SCALE;
        let position_size = 1 * SCALE;

        let (pnl, is_profit) = il_engine.calculate_leverage_pnl(
            entry_price, current_price, leverage, position_size
        );

        assert(is_profit, 'Should be profit on price up');
        assert(pnl > 0, 'PnL should be positive');
    }

    #[test]
    fn test_leverage_pnl_price_down() {
        let il_engine = deploy_il_eliminator();
        let entry_price = 60000 * SCALE;
        let current_price = 48000 * SCALE;
        let leverage = 2 * SCALE;
        let position_size = 1 * SCALE;

        let (pnl, is_profit) = il_engine.calculate_leverage_pnl(
            entry_price, current_price, leverage, position_size
        );

        assert(!is_profit, 'Should be loss on price down');
        assert(pnl > 0, 'PnL magnitude should be > 0');
    }

    #[test]
    fn test_leverage_pnl_no_change() {
        let il_engine = deploy_il_eliminator();
        let entry_price = 60000 * SCALE;
        let current_price = 60000 * SCALE;
        let leverage = 2 * SCALE;
        let position_size = 1 * SCALE;

        let (pnl, _is_profit) = il_engine.calculate_leverage_pnl(
            entry_price, current_price, leverage, position_size
        );

        assert(pnl == 0, 'PnL should be 0 with no change');
    }

    // ═══════════════════════════════════════════════════════
    // OPTIMAL LEVERAGE TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_optimal_leverage_low_volatility() {
        let il_engine = deploy_il_eliminator();
        let volatility = 0;
        let fees_apr = SCALE / 10;

        let optimal = il_engine.calculate_optimal_leverage(volatility, fees_apr);
        assert(optimal == 2 * SCALE, 'Should be 2x for zero vol');
    }

    #[test]
    fn test_optimal_leverage_clamped_max() {
        let il_engine = deploy_il_eliminator();
        let volatility = SCALE / 100;
        let fees_apr = SCALE;

        let optimal = il_engine.calculate_optimal_leverage(volatility, fees_apr);
        let max_leverage = 3 * SCALE;
        assert(optimal <= max_leverage, 'Should be at most 3x');
    }

    // ═══════════════════════════════════════════════════════
    // NET POSITION TESTS
    // ═══════════════════════════════════════════════════════

    #[test]
    fn test_net_position_leverage_covers_il() {
        let il_engine = deploy_il_eliminator();
        let il_loss = SCALE * 2 / 100;
        let leverage_gain = SCALE * 4 / 100;

        let (net, is_positive) = il_engine.calculate_net_position(il_loss, leverage_gain, true);
        assert(is_positive, 'Should be net positive');
        assert(net == SCALE * 2 / 100, 'Net should be 2%');
    }

    #[test]
    fn test_net_position_il_exceeds_leverage() {
        let il_engine = deploy_il_eliminator();
        let il_loss = SCALE * 5 / 100;
        let leverage_gain = SCALE * 2 / 100;

        let (net, is_positive) = il_engine.calculate_net_position(il_loss, leverage_gain, true);
        assert(!is_positive, 'Should be net negative');
        assert(net == SCALE * 3 / 100, 'Net loss should be 3%');
    }

    #[test]
    fn test_net_position_both_losses() {
        let il_engine = deploy_il_eliminator();
        let il_loss = SCALE * 3 / 100;
        let leverage_loss = SCALE * 2 / 100;

        let (net, is_positive) = il_engine.calculate_net_position(il_loss, leverage_loss, false);
        assert(!is_positive, 'Should be net negative');
        assert(net == SCALE * 5 / 100, 'Total loss should be 5%');
    }
}
