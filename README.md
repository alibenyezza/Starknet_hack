# StarkYield — IL-Free BTC Leveraged Liquidity on Starknet

StarkYield is an IL-free BTC yield protocol on Starknet. Users deposit wBTC and receive **syBTC** (a yield-bearing receipt token). The protocol automatically deploys the BTC into an Ekubo LP + Vesu leveraged position at **2× leverage**, which mathematically eliminates impermanent loss.

**Live on Starknet Sepolia testnet.**

---

## Why 2× Leverage Eliminates IL

In a standard AMM, LP value grows as √p (square root of price). With 2× leverage applied to the LP:

```
V(p) ∝ (√p)^L = (√p)^2 = p
```

The position scales **linearly** with BTC price — identical to just holding BTC — so there is zero impermanent loss.

---

## Architecture

```
wBTC deposit
    │
    ▼
VaultManager ──────────────────────────────────────────────────────────
    │ mints syBTC shares                                               │
    │                                                                  │
    ▼                                                                  │
LeverageManager (allocate)                                             │
    ├── MockEkuboAdapter ──→ Ekubo BTC/USDC LP                         │
    └── MockVesuAdapter  ──→ Vesu CDP (borrow USDC against LP)         │
                                                                       │
LEVAMM (Constant Leverage AMM)  ←── VirtualPool (arbitrage rebalance) │
    ├── x0 bonding curve (LEV_RATIO = 4/9)                            │
    ├── DTV safety bands [6.25%, 53.125%]                              │
    └── Interest accrual + refueling                                   │
                                                                       │
Factory (market registry) ─────────────────────────────────────────────
    └── registers markets, blueprint class hashes, debt ceilings

Staker
    ├── stake syBTC → earn syYB emissions (MasterChef)
    └── unstake / claim_rewards

Governance (stubs)
    ├── syYB token (ERC-20)
    ├── VotingEscrow (lock syYB → vesyYB voting power)
    ├── GaugeController (vote on emission weights)
    └── LiquidityGauge (emission distribution)
```

---

## Repository Structure

```
Starknet_hack/
├── contracts/
│   └── src/
│       ├── vault/          VaultManager, SyBtcToken, MockWBTC, MockUSDC
│       ├── strategy/       LeverageManager, ILEliminator
│       ├── risk/           RiskManager
│       ├── integrations/   Ekubo, Vesu, Pragma adapters + mocks
│       ├── amm/            levamm.cairo   ← LEVAMM (2× bonding curve)
│       ├── pool/           virtual_pool.cairo ← Flash-loan rebalancer
│       ├── factory/        factory.cairo  ← Market registry
│       ├── staker/         staker.cairo   ← syBTC staking → syYB
│       ├── governance/     sy_yb_token, voting_escrow, gauge_controller, liquidity_gauge
│       └── utils/          constants.cairo, math.cairo
├── frontend/
│   └── src/
│       ├── hooks/          useVaultManager (deposit/withdraw/LEVAMM/Staker)
│       ├── pages/          VaultPage (full UI)
│       └── config/         constants.ts (contract addresses)
└── scripts/                Deploy/redeploy scripts
```

---

## Deployed Contracts — Sepolia

### v5 (working deposit/withdraw, LM=0 fallback)

| Contract | Address |
|---|---|
| VaultManager | `0x040489e90e3cafad2446fecb229bc06fea17f535788135469f12a15b983ef976` |
| SyBtcToken | `0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3` |
| MockWBTC (faucet) | `0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163` |
| MockUSDC | `0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb` |

### v6 (LEVAMM + VirtualPool + Staker + Governance — deployed 2026-02-27)

| Contract | Address |
|---|---|
| Factory | `0x0253d30100bd7cbbc2bf146bdddcbb4adfc0cae0dc3d2a3ab172a1b4e21c8780` |
| LevAMM | `0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af` |
| VirtualPool | `0x00f720c999fdedd3d4a1e393dda0ce1a4e5b0bf079a8608d61f19ba5e77a190c` |
| Staker | `0x04620f57ef40e7e2293ca6d06153930697bcb88d173f1634ba5cff768acec273` |
| SyYbToken | `0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e` |

---

## Quick Start

### Frontend

```bash
cd frontend
npm install
npm run dev
# Visit http://localhost:3000
```

Connect Argent or Braavos wallet on Starknet Sepolia, then:
1. **Faucet** — get testnet wBTC
2. **Deposit** — specify amount → approve + deposit
3. **Withdraw** — specify amount to redeem

### Contracts (requires Scarb + sncast in WSL)

```bash
cd contracts
scarb build
```

---

## LEVAMM Math

```
LEV_RATIO = (L/(L+1))^2 = (2/3)^2 = 4/9   (for L=2)

x0 = (C + sqrt(C^2 - 4·C·LEV_RATIO·D)) / (2·LEV_RATIO)

Invariant I(p0) = (x0 - d_btc) · y

Safety bands: DTV ∈ [6.25%, 53.125%]
```

Where:
- `C` = collateral value (USDC, 1e18)
- `D` = debt (USDC, 1e18)
- `d_btc` = D / BTC_price (debt in BTC units)
- `y` = collateral value (= C at initialization)

---

## Tech Stack

| Component | Tech |
|---|---|
| Smart Contracts | Cairo 2, Scarb, OpenZeppelin Cairo |
| DEX | Ekubo (BTC/USDC pool) |
| Lending | Vesu (CDP: LP collateral → USDC borrow) |
| Oracle | Pragma Network (BTC/USD) |
| Rebalancing | Arbitrageurs via VirtualPool (atomic flash loans) |
| Frontend | Next.js 14, starknet-react, starknet.js |
| Network | Starknet Sepolia |

---

## Hackathon

Built for the Starknet hackathon. Demonstrates an IL-free BTC yield strategy using 2× leveraged liquidity, a Constant Leverage AMM (LEVAMM), atomic VirtualPool rebalancing, and a syYB governance token system.
