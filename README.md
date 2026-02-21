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

## Live Demo (Sepolia Testnet)

### Deployed Contracts

| Contract | Address | Explorer |
|----------|---------|----------|
| MockWBTC (Faucet) | `0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163` | [View](https://sepolia.starkscan.co/contract/0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163) |
| SyBtcToken | `0x05cda6e0cf0c7656d76c61bfbd7d138532b6aa8245dbb070f50f015e689c2afd` | [View](https://sepolia.starkscan.co/contract/0x05cda6e0cf0c7656d76c61bfbd7d138532b6aa8245dbb070f50f015e689c2afd) |
| VaultManager | `0x02d74eea61e7d67bd9f3b54973bc9cd51d8a7526bc93168dce622647c630f83f` | [View](https://sepolia.starkscan.co/contract/0x02d74eea61e7d67bd9f3b54973bc9cd51d8a7526bc93168dce622647c630f83f) |
| MockPragmaAdapter | `0x069751dd1f1d78907f361a725af5d06937e5c25839fcffaf898fbd1e79fd49c2` | [View](https://sepolia.starkscan.co/contract/0x069751dd1f1d78907f361a725af5d06937e5c25839fcffaf898fbd1e79fd49c2) |
| MockEkuboAdapter | `0x05fd7268228036c8237674709b699a732e7c2ae3c7d20ef1306950f3626610f9` | [View](https://sepolia.starkscan.co/contract/0x05fd7268228036c8237674709b699a732e7c2ae3c7d20ef1306950f3626610f9) |
| MockLendingAdapter | `0x0184b3fb971cd3ea627727c32e07b9a071bf4e68de42c61567f8d04ef80a474b` | [View](https://sepolia.starkscan.co/contract/0x0184b3fb971cd3ea627727c32e07b9a071bf4e68de42c61567f8d04ef80a474b) |
| LeverageManager | `0x00bf47cb391843b4103b6c7dd5fdfea60dc8a39e10a7f980b32c1a66170567c7` | [View](https://sepolia.starkscan.co/contract/0x00bf47cb391843b4103b6c7dd5fdfea60dc8a39e10a7f980b32c1a66170567c7) |

### Try It Out

1. Install [Braavos](https://braavos.app/) or [ArgentX](https://www.argent.xyz/argent-x/) wallet
2. Switch to **Sepolia testnet**
3. Run the frontend: `cd frontend && npm install && npm run dev`
4. Connect your wallet
5. Click **"Faucet 1 wBTC"** to mint test tokens
6. Deposit wBTC into the vault and receive syBTC shares

### Add wBTC to Your Wallet

To see your MockWBTC balance in Braavos/ArgentX:

1. Open your wallet
2. Go to **Settings** > **Manage tokens** (or click **+ Add token**)
3. Paste the MockWBTC contract address:
   ```
   0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163
   ```
4. Token name: **Wrapped BTC**, symbol: **wBTC**, decimals: **18**

To also see your syBTC shares:
```
0x05cda6e0cf0c7656d76c61bfbd7d138532b6aa8245dbb070f50f015e689c2afd
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  VAULT LAYER                      │
│  VaultManager ─── deposit/withdraw/rebalance      │
│  SyBtcToken   ─── ERC20 receipt token (syBTC)     │
│  MockWBTC     ─── ERC20 testnet faucet token      │
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
│  MockPragmaAdapter ─── BTC/USD price (hardcoded)  │
│  MockEkuboAdapter  ─── simulated swaps + LP       │
│  MockLendingAdapter─── simulated lending          │
└──────────────────────────────────────────────────┘
```

> **Note:** The integration layer currently uses mock adapters on Sepolia testnet.
> Real Ekubo, Vesu and Pragma adapter contracts are written and ready to swap in for mainnet.

## Project Structure

```
contracts/src/
├── lib.cairo                          # Module root
├── vault/
│   ├── vault_manager.cairo            # Main contract: deposit, withdraw, rebalance
│   ├── sy_btc_token.cairo             # ERC20 receipt token
│   ├── mock_usdc.cairo                # ERC20 testnet USDC faucet
│   └── mock_wbtc.cairo                # ERC20 testnet faucet token
├── strategy/
│   ├── il_eliminator.cairo            # IL calculation engine
│   └── leverage_manager.cairo         # Strategy execution (Ekubo + Vesu)
├── risk/
│   └── risk_manager.cairo             # Health factor, limits, price checks
├── integrations/
│   ├── ierc20.cairo                   # ERC20 interface
│   ├── pragma_oracle.cairo            # Pragma price feed adapter (real)
│   ├── ekubo.cairo                    # Ekubo DEX adapter (real)
│   ├── vesu.cairo                     # Vesu lending adapter (real)
│   ├── mock_pragma.cairo              # Mock oracle (testnet)
│   ├── mock_ekubo.cairo               # Mock DEX (testnet)
│   └── mock_lending.cairo             # Mock lending (testnet)
└── utils/
    ├── constants.cairo                # Protocol parameters
    └── math.cairo                     # Fixed-point arithmetic (sqrt, mul, div)

frontend/src/
├── abi/                               # Contract ABIs
│   ├── vaultManager.ts
│   ├── erc20.ts
│   └── mockWbtc.ts
├── hooks/                             # React hooks for contract interaction
│   ├── useVaultManager.ts             # Deposit, withdraw, vault stats
│   ├── useERC20.ts                    # Token balances, approvals
│   └── useBTCPrice.ts                 # BTC/USD price feed
├── pages/
│   ├── VaultPage.tsx                  # Main vault UI (deposit/withdraw/faucet)
│   └── ...
├── config/
│   └── constants.ts                   # Contract addresses, network config
└── providers/
    └── StarknetProvider.tsx            # Wallet connection (Braavos/ArgentX)

scripts/
├── deploy.sh                          # Full deployment script
├── redeploy_vault.sh                  # Redeploy SyBtcToken + VaultManager only
├── redeploy_ekubo.sh                  # Redeploy MockEkuboAdapter only
├── redeploy_lending.sh                # Redeploy MockLendingAdapter only
└── redeploy_pragma.sh                 # Redeploy MockPragmaAdapter only
```

## What's Implemented

### Smart Contracts

#### Vault (fully functional on Sepolia)
- `deposit()` — transfer BTC, mint syBTC, allocate to strategy
- `withdraw()` — burn syBTC, deallocate, transfer BTC back
- `rebalance()` — permissionless keeper function, adjusts leverage to target
- `emergency_withdraw()` — admin closes all positions, pauses vault
- View functions: total assets, share price, health factor, leverage ratio, BTC price

#### IL Eliminator (code complete, not yet wired into vault)
- `calculate_il()` — exact IL formula with fixed-point sqrt
- `calculate_leverage_pnl()` — leveraged position P&L
- `calculate_optimal_leverage()` — volatility-based optimal leverage (clamped 1.5x-3x)
- `calculate_net_position()` — net result after IL and leverage gains

#### Leverage Manager (fully functional on Sepolia)
- `allocate()` — split 50/50 between Ekubo LP and Vesu leverage
- `deallocate()` — proportional withdrawal, repay debt first
- `increase_leverage()` / `reduce_leverage()` — adjust positions
- `close_all_positions()` — emergency unwinding

#### Risk Manager (code complete, not yet wired into vault)
- Health factor classification (Safe > 2.0, Moderate > 1.5, Warning > 1.2, Danger)
- Deleverage amount calculation
- Price sanity checks (max 10% deviation)
- Daily withdrawal limits with reset

#### Integration Adapters
- **Real adapters** (written, ready for mainnet): Pragma Oracle, Ekubo DEX, Vesu Lending
- **Mock adapters** (active on Sepolia testnet): simulate all flows using faucet tokens

### Frontend
- Wallet connection (Braavos / ArgentX) on Sepolia
- wBTC faucet for testnet
- Deposit wBTC → receive syBTC shares
- Withdraw syBTC → receive wBTC back
- Live vault stats: share price, total assets, health factor, leverage, user position
- Toast notifications for transaction status
- Auto-refresh every 15 seconds

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) (v18+)
- [Scarb](https://docs.swmansion.com/scarb/) (Cairo package manager)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) (snforge for testing)

### Frontend

```bash
cd frontend
npm install
npm run dev
```

Open http://localhost:3000 and connect your Sepolia wallet.

### Build Contracts

```bash
cd contracts
scarb build
```

### Run Tests

```bash
cd contracts
snforge test
```

### Deploy to Sepolia

```bash
cd contracts
bash ../scripts/deploy.sh
```

## Tech Stack

- **Language:** Cairo 2.x
- **Framework:** Starknet
- **Frontend:** React + TypeScript + Vite
- **Wallet:** starknet-react + starknet.js
- **Dependencies:** OpenZeppelin Cairo Contracts
- **Oracles:** Pragma Network (mock on testnet)
- **DEX:** Ekubo Protocol (mock on testnet)
- **Lending:** Vesu Finance (mock on testnet)
- **RPC:** Cartridge (Sepolia)
