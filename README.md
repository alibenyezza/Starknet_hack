# StarkYield - IL-Free BTC Liquidity Protocol on Starknet

StarkYield is a DeFi protocol that eliminates Impermanent Loss for BTC liquidity providers on Starknet. It uses dynamic leverage rebalancing to compensate IL with amplified trading gains.

## How It Works

Users deposit BTC into the vault and receive syBTC receipt tokens. The vault splits deposits 50/50:

- **50% into Ekubo LP** (BTC/USDC pool) — earns trading fees
- **50% into Vesu leverage** — deposits BTC as collateral, borrows USDC, buys more BTC

When BTC price moves, the LP position suffers Impermanent Loss, but the leveraged position generates amplified gains that compensate the IL.

```
IL Formula: IL = 1 - 2*sqrt(r) / (1+r)

BTC +50% → IL = ~2%, Leverage gain (2x) = ~4% → Net = +2%
```

A permissionless `rebalance()` function keeps the leverage ratio at target (2x default) by adjusting positions when deviation exceeds 10%.

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  VAULT LAYER                      │
│  VaultManager ─── deposit/withdraw/rebalance      │
│  SyBtcToken   ─── ERC20 receipt token (syBTC)     │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│                STRATEGY LAYER                     │
│  ILEliminator    ─── IL math + optimal leverage   │
│  LeverageManager ─── allocate/deallocate/adjust   │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│              RISK MANAGEMENT                      │
│  RiskManager ─── health factor, deleverage,       │
│                  price sanity, withdrawal limits   │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│             INTEGRATION LAYER                     │
│  PragmaAdapter ─── BTC/USD price oracle           │
│  EkuboAdapter  ─── DEX swaps + LP positions       │
│  VesuAdapter   ─── lending/borrowing              │
└──────────────────────────────────────────────────┘
```

## Project Structure

```
contracts/src/
├── lib.cairo                          # Module root
├── vault/
│   ├── vault_manager.cairo            # Main contract: deposit, withdraw, rebalance
│   └── sy_btc_token.cairo             # ERC20 receipt token
├── strategy/
│   ├── il_eliminator.cairo            # IL calculation engine
│   └── leverage_manager.cairo         # Strategy execution (Ekubo + Vesu)
├── risk/
│   └── risk_manager.cairo             # Health factor, limits, price checks
├── integrations/
│   ├── ierc20.cairo                   # ERC20 interface
│   ├── pragma_oracle.cairo            # Pragma price feed adapter
│   ├── ekubo.cairo                    # Ekubo DEX adapter
│   └── vesu.cairo                     # Vesu lending adapter
└── utils/
    ├── constants.cairo                # Protocol parameters
    └── math.cairo                     # Fixed-point arithmetic (sqrt, mul, div)

contracts/tests/
├── test_sy_btc_token.cairo            # 5 tests
├── test_vault_manager.cairo           # 10 tests
├── test_il_eliminator.cairo           # 12 tests
├── test_risk_manager.cairo            # 16 tests
└── test_math.cairo                    # 14 tests
```

## What's Implemented

### Vault (100%)
- `deposit()` — transfer BTC, mint syBTC, allocate to strategy
- `withdraw()` — burn syBTC, deallocate, transfer BTC back
- `rebalance()` — permissionless keeper function, adjusts leverage to target
- `emergency_withdraw()` — admin closes all positions, pauses vault
- View functions: total assets, share price, health factor, leverage ratio, BTC price

### IL Eliminator (100%)
- `calculate_il()` — exact IL formula with fixed-point sqrt
- `calculate_leverage_pnl()` — leveraged position P&L
- `calculate_optimal_leverage()` — volatility-based optimal leverage (clamped 1.5x-3x)
- `calculate_net_position()` — net result after IL and leverage gains

### Leverage Manager (100%)
- `allocate()` — split 50/50 between Ekubo LP and Vesu leverage
- `deallocate()` — proportional withdrawal, repay debt first
- `increase_leverage()` / `reduce_leverage()` — adjust positions
- `close_all_positions()` — emergency unwinding

### Risk Manager (100%)
- Health factor classification (Safe > 2.0, Moderate > 1.5, Warning > 1.2, Danger)
- Deleverage amount calculation
- Price sanity checks (max 10% deviation)
- Daily withdrawal limits with reset

### Integration Adapters (100%)
- Pragma Oracle — BTC/USD price with staleness check, decimal normalization
- Ekubo DEX — swap BTC/USDC, add/remove liquidity
- Vesu Lending — deposit collateral, borrow, repay, withdraw

### Tests (61 tests, all passing)
- Math utilities, IL calculations, risk management, vault operations, token mechanics

## Deployed on Sepolia

| Contract | Address |
|----------|---------|
| SyBtcToken | `0x0536b7...bff278` |
| VaultManager | `0x01d230...d98a6` |

## Getting Started

### Prerequisites

- [Scarb](https://docs.swmansion.com/scarb/) (Cairo package manager)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) (snforge for testing)
- [Starkli](https://github.com/xJonathanLEI/starkli) (for deployment)

### Build

```bash
cd contracts
scarb build
```

### Run Tests

```bash
cd contracts
snforge test
```

Expected output: `Tests: 61 passed, 0 failed, 0 ignored, 0 filtered out`

### Deploy to Sepolia

```bash
cd scripts
chmod +x deploy.sh
./deploy.sh
```

## Tech Stack

- **Language:** Cairo 2.x
- **Framework:** Starknet
- **Dependencies:** OpenZeppelin Cairo Contracts, Starknet Foundry
- **Oracles:** Pragma Network
- **DEX:** Ekubo Protocol
- **Lending:** Vesu Finance
