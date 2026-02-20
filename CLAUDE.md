# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**StarkYield** — IL-Free BTC Liquidity Protocol on Starknet. Eliminates Impermanent Loss (IL) for BTC liquidity providers by using dynamic leverage rebalancing: 50% of deposits go into Ekubo DEX LP positions, 50% into Vesu Finance leveraged positions, with the leverage automatically offsetting IL using the formula `IL = 1 - 2*sqrt(r) / (1+r)` where `r = current/entry price ratio`.

## Commands

### Frontend

```bash
cd frontend
npm install          # Install dependencies
npm run dev          # Start dev server on port 3000
npm run build        # TypeScript check + Vite build
npm run lint         # ESLint
npm run preview      # Preview production build
```

Environment: copy `frontend/.env.example` to `frontend/.env` and configure RPC URL and contract addresses.

### Smart Contracts (Cairo/Starknet)

Requires [Scarb](https://docs.swmansion.com/scarb/) and [Starknet Foundry](https://foundry-book.starknet.io/) installed.

```bash
# From repo root
scarb build              # Compile Cairo contracts
snforge test             # Run all 61 tests
snforge test <test_name> # Run a single test
scarb fmt                # Format Cairo code
```

Deployment scripts are in `scripts/`: `deploy.sh`, `setup_account.sh`, `wsl_build.sh`.

## Architecture

### Smart Contracts (`contracts/src/`)

Four-layer architecture:

- **Vault** (`vault/`) — Entry point. `vault_manager.cairo` handles deposits/withdrawals, mints/burns `syBTC` receipt tokens (`sy_btc_token.cairo`), and triggers rebalancing. Stores shares, asset amounts, strategy allocation, and risk parameters.

- **Strategy** (`strategy/`) — `il_eliminator.cairo` calculates IL and optimal leverage. `leverage_manager.cairo` executes allocations (50% Ekubo LP / 50% Vesu leverage) and position management.

- **Risk** (`risk/`) — `risk_manager.cairo` enforces health factors (Safe >2.0, Moderate >1.5, Warning >1.2, Danger <1.2), calculates deleveraging amounts, validates price sanity.

- **Integrations** (`integrations/`) — Adapters for Pragma Oracle (BTC/USD price, 3600s staleness threshold), Ekubo DEX, and Vesu Finance lending.

Fixed-point arithmetic uses `SCALE = 1e18`. Protocol constants (leverage targets, health thresholds, slippage) are in `utils/constants.cairo`. Math utilities in `utils/math.cairo`.

### Frontend (`frontend/src/`)

Single-page React app with section-based navigation (no router):

- **`App.tsx`** — Root component. Manages current page state, wallet modal visibility, and renders `StaggeredMenu` (fixed right-side nav), `WalletModal`, and page components.

- **`providers/StarknetProvider.tsx`** — Wraps app with Starknet config (Sepolia chain, public RPC, ArgentX + Braavos connectors).

- **`config/constants.ts`** — Contract addresses (currently placeholder zeros for testnet), network config, health factor thresholds, decimal settings.

- **Pages**: `VaultPage` (deposit/withdraw UI with BTC input), `ResourcesPage`, `TeamPage`. The landing view is composed of `Hero` + `FeaturesSection` components.

- **`hooks/useBTCPrice.ts`** — Polls CoinGecko every 15 seconds for live BTC price displayed in the header.

### Styling

Uses Tailwind CSS with custom theme (defined in `tailwind.config.js`): primary purple palette, Times New Roman serif font (intentional design choice), JetBrains Mono for code. Additional per-component `.css` files coexist with Tailwind utility classes. Path alias `@` maps to `src/`.

### Testing

All 61 tests are in `contracts/tests/`. Test files map 1:1 to source modules: `test_sy_btc_token` (5), `test_vault_manager` (10), `test_il_eliminator` (12), `test_risk_manager` (16), `test_math` (14).
