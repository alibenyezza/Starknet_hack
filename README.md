# StarkYield — IL-Free BTC Liquidity Protocol on Starknet

StarkYield lets users deposit wBTC and earn yield through an automated strategy that provides liquidity on Ekubo while using leveraged collateral on Vesu — all without impermanent loss.

**Live on Starknet Sepolia testnet.**

---

## How It Works

1. **Deposit wBTC** → receive syBTC (yield-bearing receipt token)
2. **Strategy**: BTC liquidity deployed on Ekubo (concentrated LP) + leveraged collateral on Vesu
3. **Withdraw wBTC** anytime by redeeming syBTC shares

The vault tracks share price (`total_assets / total_shares`) so yield accrues automatically.

---

## Repository Structure

```
Starknet_hack/
├── contracts/            # Cairo smart contracts (Scarb)
│   └── src/
│       ├── vault/        # VaultManager, SyBtcToken
│       ├── strategy/     # LeverageManager, RiskManager
│       └── integrations/ # Ekubo, Vesu, Pragma adapters (+ mocks)
├── frontend/             # Next.js + starknet-react UI
│   └── src/
│       ├── hooks/        # useVaultManager, useFaucet, useWallet
│       ├── pages/        # VaultPage (deposit / withdraw / stats)
│       └── config/       # constants.ts (contract addresses)
└── scripts/              # Deploy & redeploy shell scripts (WSL)
```

---

## Deployed Contracts (Sepolia — v5)

| Contract | Address |
|---|---|
| VaultManager | `0x040489e90e3cafad2446fecb229bc06fea17f535788135469f12a15b983ef976` |
| SyBtcToken | `0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3` |
| MockWBTC (faucet) | `0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163` |
| MockUSDC | `0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb` |

---

## Quick Start

### Frontend

```bash
cd frontend
npm install
npm run dev
# Visit http://localhost:3000
```

Connect an Argent or Braavos wallet on Starknet Sepolia, then:
1. **Faucet** — get testnet wBTC
2. **Deposit** — specify an amount and approve + deposit
3. **Withdraw** — specify an amount to redeem

### Contracts (requires Scarb + sncast in WSL)

```bash
cd contracts
scarb build
```

Redeploy everything:
```bash
bash scripts/redeploy_vault.sh
```

---

## Tech Stack

- **Contracts**: Cairo 2, Scarb, OpenZeppelin Cairo components
- **Frontend**: Next.js 14, starknet-react, starknet.js
- **Network**: Starknet Sepolia (testnet)
- **Integrations**: Ekubo (LP), Vesu (lending), Pragma (oracle) — mock adapters on testnet

---

## Hackathon

Built for the Starknet hackathon. This project demonstrates an IL-free BTC yield strategy on Starknet using Cairo smart contracts and a full-stack frontend.
