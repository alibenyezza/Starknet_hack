# StarkYield - IL-Free BTC Liquidity Protocol on Starknet

> **Document complet** : Architecture, Mécanismes, Implémentation et Déploiement

---

## Table des Matières

1. [Vue d'Ensemble](#1-vue-densemble)
2. [Concepts Fondamentaux](#2-concepts-fondamentaux)
3. [Architecture Technique](#3-architecture-technique)
4. [Mécanisme IL-Eliminator](#4-mécanisme-il-eliminator)
5. [Smart Contracts Cairo](#5-smart-contracts-cairo)
6. [Intégrations Externes](#6-intégrations-externes)
7. [Frontend](#7-frontend)
8. [Sécurité](#8-sécurité)
9. [Déploiement](#9-déploiement)
10. [Roadmap](#10-roadmap)

---

## 1. Vue d'Ensemble

### 1.1 Concept

StarkYield est un **protocole de liquidité Bitcoin sans perte impermanente** sur Starknet, exploitant :

- Le BTC staking natif de Starknet
- Les wrapped BTC disponibles (WBTC, tBTC, Lombard LBTC, xyBTC)
- La sécurité et scalabilité de Starknet (ZK-proofs)

### 1.2 Proposition de Valeur

| Avantage | Description |
|----------|-------------|
| **IL-Free** | Élimination de l'Impermanent Loss via leverage dynamique |
| **First-mover** | Premier protocole IL-free sur Starknet |
| **Coûts réduits** | Gas fees 50-100x moins cher qu'Ethereum |
| **Sécurité ZK** | Preuves cryptographiques pour la gestion du risque |

### 1.3 Architecture Haut Niveau

```
┌─────────────────────────────────────────┐
│   User Interface (React + Starknet.js)  │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│     Cairo Smart Contracts               │
│  - Vault Manager                        │
│  - IL Eliminator Engine                 │
│  - Yield Distribution                   │
│  - Risk Management                      │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│   Integration Layer                     │
│  - Pragma Oracles                       │
│  - Ekubo DEX                            │
│  - Vesu Lending                         │
│  - Endur Liquid Staking                 │
└─────────────────────────────────────────┘
```

---

## 2. Concepts Fondamentaux

### 2.1 Qu'est-ce que l'Impermanent Loss (IL) ?

L'IL est la perte subie par les fournisseurs de liquidité quand le prix des actifs change.

**Exemple concret :**

```
Dépôt initial dans pool BTC/USDC :
├── 1 BTC (valeur : 60,000$)
├── 60,000 USDC
└── Total : 120,000$

Si BTC monte à 90,000$ :
├── Sans pool : 1 BTC + 60,000 USDC = 150,000$
├── Avec pool AMM : ~0.816 BTC + 73,485 USDC = 146,970$
└── IL = 3,030$ perdus (2%)
```

**Formule mathématique de l'IL :**

```
IL = 2 × √(price_ratio) / (1 + price_ratio) - 1

où price_ratio = nouveau_prix / prix_initial
```

### 2.2 Méthodes d'Élimination de l'IL

| Méthode | Principe | Inconvénient |
|---------|----------|--------------|
| Concentrated Liquidity | Limiter la range de prix | Gestion active requise |
| Single-Sided Deposits | Un seul actif déposé | Rendements plus faibles |
| Dynamic Hedging | Positions dérivées opposées | Coûts de hedging |
| Protocol Insurance | Le protocole absorbe l'IL | Risque pour le protocole |
| **Leverage Rebalancing** | Notre approche | Complexité technique |

### 2.3 Notre Solution : Leverage Rebalancing

**Principe :** Compenser l'IL par des gains de trading amplifiés.

```
Position classique :          Position avec leverage 2x :
Prix BTC +50%                 Prix BTC +50%
├── IL = -2%                  ├── Trading gains = +4%
└── Net = -2%                 ├── IL = -2%
                              └── Net = +2%
```

---

## 3. Architecture Technique

### 3.1 Composants du Système

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRONTEND LAYER                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Deposit    │  │   Dashboard  │  │   Withdraw   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                     CAIRO SMART CONTRACTS                       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    VAULT MANAGER                         │   │
│  │  • Gère les dépôts/retraits                             │   │
│  │  • Calcule les parts (shares)                           │   │
│  │  • Émet des receipt tokens (syBTC)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────┐     │
│  │  ┌─────────────┐  ┌───────▼─────┐  ┌─────────────┐   │     │
│  │  │   LEVERAGE  │  │     IL      │  │   YIELD     │   │     │
│  │  │   MANAGER   │◄─┤  ELIMINATOR │─►│ DISTRIBUTOR │   │     │
│  │  └─────────────┘  └─────────────┘  └─────────────┘   │     │
│  │                                                       │     │
│  │  ┌─────────────────────────────────────────────┐     │     │
│  │  │           RISK MANAGEMENT MODULE            │     │     │
│  │  │  • Health Factor Calculator                 │     │     │
│  │  │  • Liquidation Engine                       │     │     │
│  │  │  • Emergency Shutdown                       │     │     │
│  │  └─────────────────────────────────────────────┘     │     │
│  └───────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Flux de Dépôt

```
User dépose 1 BTC
       │
       ▼
┌───────────────┐
│ Vault Manager │ ──► Calcule shares à minter
└───────┬───────┘
       │
       ▼
┌───────────────┐
│  Mint syBTC   │ ──► User reçoit receipt token
└───────┬───────┘
       │
       ▼
┌───────────────┐
│   Strategy    │
│  Allocation   │
└───────┬───────┘
       │
  ┌────┴────┐
  ▼         ▼
┌─────┐  ┌─────┐
│ 50% │  │ 50% │
│ LP  │  │Lend │
│Ekubo│  │Vesu │
└─────┘  └─────┘
```

### 3.3 Structure des Fichiers

```
starkyield/
├── contracts/
│   └── src/
│       ├── lib.cairo
│       ├── vault/
│       │   ├── vault_manager.cairo
│       │   └── sy_btc_token.cairo
│       ├── strategy/
│       │   ├── leverage_manager.cairo
│       │   ├── il_eliminator.cairo
│       │   └── yield_distributor.cairo
│       ├── risk/
│       │   ├── health_calculator.cairo
│       │   ├── liquidation_engine.cairo
│       │   └── emergency_shutdown.cairo
│       ├── integrations/
│       │   ├── pragma_oracle.cairo
│       │   ├── ekubo_adapter.cairo
│       │   ├── vesu_adapter.cairo
│       │   └── endur_adapter.cairo
│       └── utils/
│           ├── math.cairo
│           └── constants.cairo
├── frontend/
│   └── src/
│       ├── components/
│       ├── hooks/
│       ├── utils/
│       └── abis/
├── tests/
├── scripts/
├── Scarb.toml
└── README.md
```

---

## 4. Mécanisme IL-Eliminator

### 4.1 Fonctionnement Détaillé

```
┌─────────────────────────────────────────────────────────────────┐
│                    IL ELIMINATOR ENGINE                         │
│                                                                 │
│   ÉTAPE 1: Calcul de l'exposition                              │
│   ─────────────────────────────                                │
│   Position LP = $100,000 (50% BTC / 50% USDC)                  │
│   Exposition BTC directe = 0.5                                 │
│                                                                 │
│   ÉTAPE 2: Création du leverage                                │
│   ────────────────────────────                                 │
│   ┌─────────────────┐      ┌─────────────────┐                 │
│   │  Collatéral     │      │   Emprunt       │                 │
│   │  50,000 USDC    │─────►│   50,000 USDC   │                 │
│   └─────────────────┘      └────────┬────────┘                 │
│                                     │                          │
│                                     ▼                          │
│                            ┌─────────────────┐                 │
│                            │  Achat BTC      │                 │
│                            │  = 0.83 BTC     │                 │
│                            └─────────────────┘                 │
│                                                                 │
│   ÉTAPE 3: Résultat (BTC +50%)                                 │
│   ────────────────────────────                                 │
│   Position LP seule:                                           │
│   ├── Valeur théorique: $175,000                               │
│   ├── Valeur réelle: $170,700                                  │
│   └── IL = -$4,300                                             │
│                                                                 │
│   Position leverage:                                           │
│   ├── Gain BTC: +$24,900                                       │
│   ├── Coût emprunt: -$500                                      │
│   └── Net: +$24,400                                            │
│                                                                 │
│   TOTAL: $170,700 + $24,400 = $195,100                         │
│   (au lieu de $170,700 avec IL)                                │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Gestion du Health Factor

```
┌────────────────────────────────────────────────────────────┐
│  Health Factor = Collateral / (Dette × Seuil Liquidation)  │
├────────────────────────────────────────────────────────────┤
│  HF > 2.0     │  SAFE      │  🟢  │  Aucune action        │
│  1.5 < HF < 2 │  MODERATE  │  🟡  │  Alerte               │
│  1.2 < HF <1.5│  WARNING   │  🟠  │  Rééquilibrage        │
│  HF < 1.2     │  DANGER    │  🔴  │  Deleveraging         │
│  HF < 1.0     │  LIQUIDATE │  ☠️   │  Position fermée      │
└────────────────────────────────────────────────────────────┘
```

### 4.3 Mécanisme de Protection

```
Prix BTC descend
      │
      ▼
Oracle Pragma détecte
      │
      ▼
┌─────────────────┐
│ HF < 1.5 ?      │──Non──► Continuer monitoring
└────────┬────────┘
         │ Oui
         ▼
┌─────────────────┐
│ Vendre portion  │
│ BTC leverage    │
│ Rembourser dette│
└────────┬────────┘
         │
         ▼
Nouveau HF > 1.5 ✓
```

---

## 5. Smart Contracts Cairo

### 5.1 Vault Manager (Contrat Principal)

```cairo
#[starknet::contract]
mod VaultManager {
    use starknet::ContractAddress;
    
    #[storage]
    struct Storage {
        // Tokens
        btc_token: ContractAddress,
        usdc_token: ContractAddress,
        sy_btc_token: ContractAddress,
        
        // Tracking
        total_btc_deposited: u256,
        total_shares: u256,
        user_shares: LegacyMap<ContractAddress, u256>,
        
        // Strategy
        btc_in_lp: u256,
        btc_leveraged: u256,
        usdc_borrowed: u256,
        
        // Risk parameters
        target_leverage: u256,     // 2x (scaled 1e18)
        max_leverage: u256,        // 3x max
        min_health_factor: u256,   // 1.2 min
        
        // External contracts
        ekubo_pool: ContractAddress,
        vesu_lending: ContractAddress,
        pragma_oracle: ContractAddress,
        
        // Admin
        owner: ContractAddress,
        is_paused: bool,
    }

    #[abi(embed_v0)]
    impl VaultManagerImpl of IVaultManager<ContractState> {
        
        /// Dépose des BTC et reçoit des syBTC
        fn deposit(ref self: ContractState, amount: u256) -> u256 {
            assert(!self.is_paused.read(), 'Vault is paused');
            assert(amount > 0, 'Amount must be > 0');
            
            let shares = self._calculate_shares_for_deposit(amount);
            self._transfer_btc_from_user(get_caller_address(), amount);
            self._mint_shares(get_caller_address(), shares);
            self._allocate_to_strategy(amount);
            
            shares
        }

        /// Retire des BTC en brûlant des syBTC
        fn withdraw(ref self: ContractState, shares: u256) -> u256 {
            let btc_amount = self._calculate_btc_for_shares(shares);
            self._withdraw_from_strategy(btc_amount);
            self._burn_shares(get_caller_address(), shares);
            self._transfer_btc_to_user(get_caller_address(), btc_amount);
            
            btc_amount
        }

        /// Rééquilibre la position (callable par tous)
        fn rebalance(ref self: ContractState) {
            let current_leverage = self._calculate_current_leverage();
            let target = self.target_leverage.read();
            
            if current_leverage > target + 1e17 {
                self._reduce_leverage(current_leverage, target);
            } else if current_leverage < target - 1e17 {
                self._increase_leverage(current_leverage, target);
            }
            
            assert(
                self.get_health_factor() >= self.min_health_factor.read(),
                'HF too low'
            );
        }

        /// Retrait d'urgence (admin only)
        fn emergency_withdraw(ref self: ContractState) {
            assert(get_caller_address() == self.owner.read(), 'Only owner');
            self.is_paused.write(true);
            self._close_all_positions();
        }

        // ═══════════════════════════════════════════════════════
        // VIEW FUNCTIONS
        // ═══════════════════════════════════════════════════════

        fn get_total_assets(self: @ContractState) -> u256 {
            self._get_btc_balance() 
            + self.btc_in_lp.read() 
            + self.btc_leveraged.read() 
            - self._convert_usdc_to_btc(self.usdc_borrowed.read())
        }

        fn get_share_price(self: @ContractState) -> u256 {
            let total = self.total_shares.read();
            if total == 0 { return 1e18; }
            (self.get_total_assets() * 1e18) / total
        }

        fn get_health_factor(self: @ContractState) -> u256 {
            let collateral = self._get_collateral_value();
            let debt = self.usdc_borrowed.read();
            if debt == 0 { return 999e18; }
            (collateral * 1e18) / ((debt * 85e16) / 1e18)
        }
    }
}
```

### 5.2 IL Eliminator Engine

```cairo
#[starknet::contract]
mod ILEliminator {
    const SCALE: u256 = 1_000000000000000000; // 1e18

    #[abi(embed_v0)]
    impl ILEliminatorImpl of IILEliminator<ContractState> {
        
        /// Calcule l'Impermanent Loss
        /// Formule: IL = 2 × √(price_ratio) / (1 + price_ratio) - 1
        fn calculate_il(
            self: @ContractState,
            entry_price: u256,
            current_price: u256
        ) -> (u256, bool) {
            let price_ratio = (current_price * SCALE) / entry_price;
            let sqrt_ratio = self._sqrt(price_ratio);
            let numerator = 2 * sqrt_ratio;
            let denominator = SCALE + price_ratio;
            let ratio = (numerator * SCALE) / denominator;
            
            if ratio >= SCALE {
                (0, false)
            } else {
                (SCALE - ratio, true) // true = perte
            }
        }

        /// Calcule le profit/perte de la position leverage
        fn calculate_leverage_profit(
            self: @ContractState,
            entry_price: u256,
            current_price: u256,
            leverage: u256,
            position_size: u256
        ) -> (u256, bool) {
            let (price_change, is_increase) = if current_price >= entry_price {
                (((current_price - entry_price) * SCALE) / entry_price, true)
            } else {
                (((entry_price - current_price) * SCALE) / entry_price, false)
            };
            
            let pnl = (position_size * price_change * leverage) / (SCALE * SCALE);
            (pnl, is_increase)
        }

        /// Calcule le leverage optimal selon la volatilité
        fn calculate_optimal_leverage(
            self: @ContractState,
            volatility: u256,
            trading_fees_apr: u256
        ) -> u256 {
            let expected_il = (volatility * volatility) / (8 * SCALE);
            if expected_il == 0 { return 2 * SCALE; }
            
            let optimal = SCALE + (trading_fees_apr * SCALE) / expected_il;
            
            // Plafonner entre 1.5x et 3x
            if optimal < 15e17 { 15e17 }
            else if optimal > 3e18 { 3e18 }
            else { optimal }
        }
    }
}
```

### 5.3 Pragma Oracle Adapter

```cairo
#[starknet::contract]
mod PragmaAdapter {
    const BTC_USD_PAIR_ID: felt252 = 'BTC/USD';

    #[storage]
    struct Storage {
        pragma_oracle: ContractAddress,
        price_staleness_threshold: u64,
    }

    #[abi(embed_v0)]
    impl PragmaAdapterImpl of IPragmaAdapter<ContractState> {
        
        fn get_btc_price(self: @ContractState) -> u256 {
            let oracle = IPragmaOracleDispatcher { 
                contract_address: self.pragma_oracle.read() 
            };
            
            let price_data = oracle.get_spot_median(BTC_USD_PAIR_ID);
            assert(!self.is_price_stale(), 'Price is stale');
            
            self._normalize_price(price_data.price, price_data.decimals)
        }

        fn is_price_stale(self: @ContractState) -> bool {
            let oracle = IPragmaOracleDispatcher { 
                contract_address: self.pragma_oracle.read() 
            };
            let price_data = oracle.get_spot_median(BTC_USD_PAIR_ID);
            let threshold = self.price_staleness_threshold.read();
            
            get_block_timestamp() - price_data.last_updated_timestamp > threshold
        }
    }
}
```

---

## 6. Intégrations Externes

### 6.1 Ekubo DEX

**Fonctions utilisées :**

| Fonction | Usage |
|----------|-------|
| `swap()` | Conversion BTC ↔ USDC |
| `add_liquidity()` | Dépôt dans le pool |
| `remove_liquidity()` | Retrait du pool |
| `get_pool_state()` | État actuel du pool |

```cairo
// Exemple d'intégration Ekubo
fn _swap_btc_to_usdc(ref self: ContractState, amount: u256) -> u256 {
    let ekubo = IEkuboDispatcher { 
        contract_address: self.ekubo_pool.read() 
    };
    
    ekubo.swap(
        token_in: self.btc_token.read(),
        token_out: self.usdc_token.read(),
        amount_in: amount,
        min_amount_out: 0, // Calculer avec slippage
    )
}
```

### 6.2 Vesu Lending

**Fonctions utilisées :**

| Fonction | Usage |
|----------|-------|
| `deposit()` | Déposer collatéral |
| `borrow()` | Emprunter USDC |
| `repay()` | Rembourser dette |
| `withdraw()` | Retirer collatéral |

```cairo
fn _create_leverage_position(ref self: ContractState, btc_amount: u256) {
    let vesu = IVesuDispatcher { 
        contract_address: self.vesu_lending.read() 
    };
    
    // 1. Déposer BTC comme collatéral
    vesu.deposit(self.btc_token.read(), btc_amount);
    
    // 2. Calculer montant à emprunter (50% LTV)
    let btc_price = self._get_btc_price();
    let borrow_amount = (btc_amount * btc_price * 50) / (100 * 1e18);
    
    // 3. Emprunter USDC
    vesu.borrow(self.usdc_token.read(), borrow_amount);
    
    // 4. Acheter plus de BTC
    let additional_btc = self._swap_usdc_to_btc(borrow_amount);
    
    // 5. Tracker
    self.usdc_borrowed.write(self.usdc_borrowed.read() + borrow_amount);
    self.btc_leveraged.write(self.btc_leveraged.read() + additional_btc);
}
```

### 6.3 Endur Liquid Staking (xyBTC)

```cairo
fn _stake_btc_endur(ref self: ContractState, amount: u256) -> u256 {
    let endur = IEndurDispatcher { 
        contract_address: self.endur_staking.read() 
    };
    
    // Stake BTC et recevoir xyBTC
    endur.stake(amount)
}
```

---

## 7. Frontend

### 7.1 Stack Technique

- **Framework:** React 18 + TypeScript
- **Starknet:** starknet-react, starknet.js
- **Styling:** Tailwind CSS
- **Build:** Vite

### 7.2 Composants Principaux

```tsx
// Dashboard.tsx
export function Dashboard() {
  const { totalAssets, userShares, sharePrice, healthFactor, apy } = useVault();

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      <div className="grid grid-cols-4 gap-4">
        <StatCard title="Your Position" value={formatBTC(userShares * sharePrice)} />
        <StatCard title="Current APY" value={`${apy}%`} highlight />
        <StatCard title="Protocol TVL" value={formatBTC(totalAssets)} />
        <StatCard title="Health Factor" value={formatHF(healthFactor)} />
      </div>

      {/* Health Factor Gauge */}
      <HealthFactorGauge value={healthFactor} />

      {/* Strategy Allocation */}
      <StrategyBreakdown />
    </div>
  );
}
```

### 7.3 Hook useVault

```typescript
// hooks/useVault.ts
export function useVault() {
  const { contract } = useContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
  });

  const { data: totalAssets } = useContractRead({
    functionName: 'get_total_assets',
    watch: true,
  });

  const { writeAsync: deposit } = useContractWrite({
    calls: [contract.populate('deposit', [])],
  });

  const { writeAsync: withdraw } = useContractWrite({
    calls: [contract.populate('withdraw', [])],
  });

  return {
    totalAssets,
    deposit,
    withdraw,
    // ...
  };
}
```

---

## 8. Sécurité

### 8.1 Matrice des Risques

| Risque | Probabilité | Impact | Mitigation |
|--------|-------------|--------|------------|
| Oracle Failure | Moyenne | Élevé | Multi-oracle, circuit breaker |
| Smart Contract Bug | Faible | Critique | Audits, tests, bug bounty |
| Liquidation Cascade | Moyenne | Élevé | Buffer HF, monitoring 24/7 |
| Flash Loan Attack | Faible | Moyen | Délai de retrait |
| Bridge Hack | Faible | Critique | Multi-bridge, limits |
| Stablecoin Depeg | Faible | Élevé | USDC natif, monitoring |

### 8.2 Mécanismes de Protection

```cairo
mod SecurityModule {
    #[storage]
    struct Storage {
        // Circuit Breakers
        is_paused: bool,
        max_daily_withdrawal: u256,
        daily_withdrawal_used: u256,
        
        // Price Guards
        max_price_deviation: u256,  // 10% max
        last_known_price: u256,
        price_staleness_limit: u64, // 1 heure
        
        // Timelock
        timelock_delay: u64,        // 24h pour actions critiques
        guardians: LegacyMap<ContractAddress, bool>,
    }

    fn check_withdrawal_limit(ref self: ContractState, amount: u256) {
        // Reset journalier
        if needs_reset() {
            self.daily_withdrawal_used.write(0);
        }
        
        let new_total = self.daily_withdrawal_used.read() + amount;
        assert(new_total <= self.max_daily_withdrawal.read(), 'Daily limit');
        self.daily_withdrawal_used.write(new_total);
    }

    fn check_price_sanity(ref self: ContractState, new_price: u256) {
        let last = self.last_known_price.read();
        let deviation = abs_diff(new_price, last) * 1e18 / last;
        assert(deviation <= self.max_price_deviation.read(), 'Price deviation');
    }
}
```

### 8.3 Checklist Audit

- [ ] Reentrancy protection
- [ ] Integer overflow/underflow
- [ ] Access control
- [ ] Oracle manipulation
- [ ] Flash loan attacks
- [ ] Precision loss
- [ ] Front-running
- [ ] Griefing attacks

---

## 9. Déploiement

### 9.1 Configuration Scarb

```toml
# Scarb.toml
[package]
name = "starkyield"
version = "0.1.0"
edition = "2023_11"

[dependencies]
starknet = "2.6.3"
openzeppelin = { git = "https://github.com/OpenZeppelin/cairo-contracts.git", tag = "v0.12.0" }

[dev-dependencies]
snforge_std = { git = "https://github.com/foundry-rs/starknet-foundry", tag = "v0.21.0" }

[[target.starknet-contract]]
casm = true
sierra = true
```

### 9.2 Script de Déploiement

```bash
#!/bin/bash
# deploy.sh

NETWORK="sepolia"
RPC="https://starknet-sepolia.public.blastapi.io"

# Compiler
scarb build

# Déclarer
VAULT_CLASS=$(starkli declare target/dev/starkyield_VaultManager.contract_class.json)

# Déployer
VAULT=$(starkli deploy $VAULT_CLASS \
  $BTC_TOKEN $USDC_TOKEN $EKUBO_POOL $VESU_LENDING $PRAGMA_ORACLE $OWNER)

echo "Vault deployed at: $VAULT"
```

### 9.3 Adresses Testnet (Sepolia)

```
BTC_TOKEN:     0x... (WBTC)
USDC_TOKEN:    0x... (USDC)
EKUBO_POOL:    0x... (BTC/USDC)
VESU_LENDING:  0x...
PRAGMA_ORACLE: 0x...
```

---

## 10. Roadmap

### Phase 1 : MVP (4-6 semaines)

- [ ] Contrats Cairo de base (Vault, IL Eliminator)
- [ ] Intégration Ekubo (swap uniquement)
- [ ] Frontend basique
- [ ] Tests unitaires

### Phase 2 : Beta (6-8 semaines)

- [ ] Intégration Vesu (lending)
- [ ] Intégration Pragma (oracles)
- [ ] Rebalancing automatique
- [ ] Audit de sécurité
- [ ] Déploiement testnet

### Phase 3 : Launch (4-6 semaines)

- [ ] Bug bounty program
- [ ] Déploiement mainnet
- [ ] Documentation utilisateur
- [ ] Support multi-token (WBTC, xyBTC, tBTC)

### Phase 4 : Growth

- [ ] Intégration Endur (liquid staking)
- [ ] Gouvernance décentralisée
- [ ] Stratégies additionnelles
- [ ] Cross-chain bridges

---

## Ressources

### Documentation Officielle

- [Starknet Docs](https://docs.starknet.io/)
- [Cairo Book](https://book.cairo-lang.org/)
- [Pragma Oracle](https://docs.pragma.build/)
- [Ekubo Protocol](https://docs.ekubo.org/)
- [Vesu Finance](https://docs.vesu.xyz/)

### Outils de Développement

- [Scarb](https://docs.swmansion.com/scarb/) - Package manager Cairo
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) - Testing framework
- [Starkli](https://github.com/xJonathanLEI/starkli) - CLI Starknet

### Communauté

- [Starknet Discord](https://discord.gg/starknet)
- [Cairo Telegram](https://t.me/CairoLang)

---

## Conclusion

StarkYield représente une innovation majeure dans l'écosystème DeFi Bitcoin sur Starknet :

1. **Premier protocole IL-free** sur Starknet
2. **Mécanisme de leverage dynamique** pour compenser les pertes
3. **Intégration native** avec l'écosystème Starknet (Ekubo, Vesu, Pragma)
4. **Sécurité ZK-native** pour la gestion du risque

Le projet est techniquement ambitieux mais réalisable avec les outils disponibles. La clé du succès réside dans une exécution progressive (MVP → Beta → Launch) et des audits de sécurité rigoureux.

---

*Document généré pour le hackathon Starknet BTC Track*
*Version 1.0 - 2024*
