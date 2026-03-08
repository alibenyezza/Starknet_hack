# A FAIRE — StarkYield

## Etat actuel

### Ce qui marche (testable sur le frontend)
- Deposit wBTC dans le vault (v12, decimals BTC=8)
- Withdraw wBTC (burn LT shares)
- Stake / Unstake LT shares dans le Staker
- Faucet BTC testnet
- APR dynamique : yieldAPR (LEVAMM trading fees) + stakedAPR (Staker reward_rate)
- Pause / unpause du VaultManager (owner)
- Claim sy-WBTC rewards (bouton dans le panel Staked Vault + affichage pending rewards)
- Claim USDC fees pour LT holders (banner + bouton dans le panel Yield Bearing Vault)
- Collect Fees + Harvest depuis le frontend (boutons permissionless)
- Auto-harvest a chaque deposit/withdraw (collect_fees + harvest automatiques)

### Ce qui est deploye (Starknet Sepolia)
- **v12** : VaultManager, LT Token, VirtualPool, MockEkubo, MockLending, BTC (8 dec), USDC (6 dec), EkuboLPWrapper, GaugeController v2
- **v6** : LEVAMM, Staker, SyYbToken, Factory

### Ce qui est code mais PAS encore compile / deploye
- Rebalancing actif (P7) — `levamm.cairo`, `mock_ekubo.cairo`, `mock_lending.cairo`, `constants.cairo`
- APR time-normalized (P9) — `levamm.cairo` (`total_fees_generated`, `init_block`), frontend time-normalized
- FeeDistributor permissionless — `fee_distributor.cairo`
- Staker assert SY token — `staker.cairo`
- Tests LEVAMM rebalancing — `test_levamm.cairo`

---

# CE QUI RESTE A FAIRE

---

## 1. Bugs code ~~a fixer~~ ✅ FIXES

### 1.1 ~~LtToken.distribute_fees() bloque par assert_only_owner()~~ ✅
- **Fichier** : `contracts/src/vault/lt_token.cairo`
- **Fix** : `assert_only_owner()` retire de `distribute_fees()`. Rendu permissionless — safe car les USDC doivent deja etre dans le contrat avant l'appel.

### 1.2 ~~Staker approve le mauvais token~~ ✅
- **Fichiers** : `contracts/src/staker/staker.cairo` + `frontend/src/hooks/useVaultManager.ts`
- **Fix** : Staker renomme `sy_btc_token` → `stake_token` (generique). Frontend modifie pour approve `LT_TOKEN` au lieu de `SY_BTC_TOKEN`. Deploy script `redeploy_staker_and_swap.sh` mis a jour. compliant : on stake LT (= ybBTC).

### 1.3 ~~Interest accrual deconnecte~~ ✅
- **Fichier** : `contracts/src/fees/fee_distributor.cairo`
- **Fix** : `claim_interest()` rendu permissionless et route vers LtToken.distribute_fees() (meme chemin que `claim_holder_fees()`). L'interet est aussi recycle dans collateral_value par LEVAMM (double benefice : NAV + distribution directe).

---

## 2. Compilation & Tests

### 2.1 Installer scarb
```bash
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh
```

### 2.2 Build & test
```bash
cd contracts
scarb build
snforge test
```

### 2.3 Fichiers modifies a verifier a la compilation
| Fichier | Changement | Risque |
|---------|-----------|--------|
| `amm/levamm.cairo` | Rebalancing + APR tracking (`total_fees_generated`, `init_block`, getters) | Haut — jamais compile |
| `integrations/mock_ekubo.cairo` | Multi-position LP (`Map<u64, u256>`) | Moyen — API Map |
| `integrations/mock_lending.cairo` | Per-caller CDP (`Map<ContractAddress, felt252>`) | Moyen — API Map |
| `utils/constants.cairo` | `REBALANCE_DTV_THRESHOLD` ajoute | Faible |
| `vault/lt_token.cairo` | Fix `distribute_fees()` (a faire) | Faible |
| `fees/fee_distributor.cairo` | Permissionless claims | Faible |
| `staker/staker.cairo` | Assert SY token non-zero | Faible |

### 2.4 Tests a valider
- **Existants** : `test_vault_manager`, `test_fee_distributor`, `test_staker`, `test_governance`, `test_integration`, `test_ekubo_lp_wrapper`
- **Nouveaux (P7)** : `test_rebalance_leverage_up`, `test_rebalance_deleverage`, `test_no_rebalance_when_near_target`, `test_swap_no_rebalance_when_not_wired`, `test_rebalance_replaces_old_lp`, `test_set_rebalance_adapters` + 3 access control

---

## 3. Deploiement on-chain (Starknet Sepolia)

### 3.1 Declare les class hashes
```bash
scarb build
sncast --account sepolia declare --contract-name MockEkuboAdapter
sncast --account sepolia declare --contract-name MockLendingAdapter
sncast --account sepolia declare --contract-name LtToken
sncast --account sepolia declare --contract-name VirtualPool
sncast --account sepolia declare --contract-name VaultManager
sncast --account sepolia declare --contract-name FeeDistributor
sncast --account sepolia declare --contract-name RiskManager
sncast --account sepolia declare --contract-name LevAMM
# ... etc pour tous les contrats modifies
```

### 3.2 Executer deploy_all.sh
```bash
sed -i 's/\r$//' scripts/deploy_all.sh
# Mettre a jour les CLASS HASHES dans le script (y compris LEVAMM_CLASS)
bash scripts/deploy_all.sh
```

Le script deploie dans l'ordre :
1. MockEkuboAdapter
2. MockLendingAdapter
3. LtToken
4. VirtualPool
5. RiskManager
5b. **LevAMM** (redeploy — nouveau storage APR StarkYield)
6. VaultManager
7. FeeDistributor
8. EkuboLPWrapper
9. GaugeController
10. VotingEscrow
11. LiquidityGauge

Puis wire tout automatiquement, initialise le LEVAMM, et genere 10 rounds de swaps pour l'APR.

### 3.3 Funder le VirtualPool
```bash
# Mint USDC au owner via faucet
sncast --account sepolia invoke --contract-address $USDC --function faucet --arguments "1000000000000"
# Approve VirtualPool
sncast --account sepolia invoke --contract-address $USDC --function approve --arguments "$VPOOL, 1000000000000"
# Fund
sncast --account sepolia invoke --contract-address $VPOOL --function fund --arguments "1000000000000"
```
Sans ca, les flash loans (deposit, withdraw, rebalancing) revertent.

### 3.4 ~~Deployer RiskManager~~ ✅ (inclus dans deploy_all.sh)
Le `deploy_all.sh` deploie un RiskManager (etape 5) et le passe au VaultManager dans ses arguments de constructeur.

### 3.5 Initialiser le LEVAMM ✅ (inclus dans deploy_all.sh)
Le script `deploy_all.sh` initialise automatiquement le LEVAMM apres le wiring :
```bash
# collateral=10,000 USDC, debt=5,000 USDC, entry_price=$96,000 (tous en 1e18)
sncast --account sepolia invoke --contract-address $LEVAMM --function initialize \
  --arguments "10000000000000000000000, 5000000000000000000000, 96000000000000000000000"
```
Cela set aussi `init_block` (utilise par la formule APR StarkYield).

### 3.6 Executer des swaps LEVAMM ✅ (inclus dans deploy_all.sh)

Le `deploy_all.sh` genere automatiquement 10 rounds de swaps apres l'initialisation.

**Formule APR (time-normalized, time-normalized) :**
```
r_pool = (totalFeesAllTime / collateral) × (BLOCKS_PER_YEAR / blocksSinceInit) × 100
APR = 2 × r_pool − (r_borrow + 0.5)
```

- `total_fees_generated` ne reset jamais (meme apres `collect_fees()`)
- L'APR est annualise selon le temps reel ecoule depuis `initialize()`
- Plus de swaps = APR plus eleve. Plus de temps sans swaps = APR decay naturel.

Pour generer plus de volume apres le deploy :
```bash
# Passer l'adresse du nouveau LEVAMM (affichee par deploy_all.sh)
LEVAMM=0x... bash scripts/generate_swap_fees.sh
LEVAMM=0x... ROUNDS=20 bash scripts/generate_swap_fees.sh
```

---

## 4. Frontend

### 4.1 Mettre a jour constants.ts
Apres redeploiement, copier les nouvelles adresses dans `frontend/src/config/constants.ts` :
- `FEE_DISTRIBUTOR` — actuellement `0x0...` (placeholder, toutes les calls echouent) ⚠ **CRITIQUE**
- `LEVAMM` — **nouvelle adresse** (redeploy pour APR StarkYield)
- `STAKER` — verifier que l'adresse est correcte
- Tous les contrats redeploys (MockEkubo, MockLending, LtToken, VaultManager, etc.)

Le `deploy_all.sh` affiche toutes les adresses a copier a la fin.

### ~~4.2 Fixer le token approve dans stakeShares()~~ ✅
Deja fait — `useVaultManager.ts` approve `LT_TOKEN` (pas `SY_BTC_TOKEN`).

---

## 5. Hors-scope hackathon (nice-to-have)

### Differences de design acceptables
- **Fees en USDC vs BTC** — StarkYield distribue en ybBTC, StarkYield en USDC. Simplifie la logique.
- **veYB admin fees en USDC** — Idem.
- **veSyWBTC non-transferable** — StarkYield a des veYB NFTs transferables. Pas dans StarkYield.
- **Pas de max-lock (permalock)** — StarkYield offre un "max lock" sans decay. StarkYield : decay lineaire (MAX_LOCK = 4 ans).
- **Distribution instantanee vs hebdomadaire** — StarkYield distribue chaque jeudi sur 4 semaines. StarkYield : instantane.

### Migration mocks vers vrais protocoles
- [ ] Remplacer MockEkubo par EkuboAdapter — code ecrit (`ekubo.cairo`, 417 lignes), pas deploye. Necessite adresses Ekubo Router/Positions Sepolia.
- [ ] Remplacer MockLending par VesuAdapter — code ecrit (`vesu.cairo`, 297 lignes), pas deploye.
- [ ] Brancher PragmaAdapter — code ecrit (`pragma_oracle.cairo`, 117 lignes), pas deploye.
- [ ] Deployer LPOracle — code ecrit (`oracle/lp_oracle.cairo`, 75 lignes), pas deploye.
- [ ] Deplacer les mock adapters hors du code source principal.

---

# HISTORIQUE — Taches completees

<details>
<summary>P0 — Bugs critiques (completes)</summary>

- [x] Bug de scaling decimal dans mock_ekubo.cairo — `get_lp_value()` additionnait BTC(8dec) et USDC(6dec) sans conversion. Corrige via `DECIMAL_BRIDGE`.
- [x] RiskManager: signature mismatch — `check_withdrawal_limit()` alignee sur l'implementation reelle.
- [x] Staker: get_reward_rate / set_reward_rate — Deja present dans le code.
- [x] Staker: _mint_reward() silent return — Remplace par `assert(sy_yb != zero, 'SY token not set')`.
- [x] FeeDistributor.claim_holder_fees() owner-only — Rendu permissionless. `harvest()` ajoutee.
</details>

<details>
<summary>P1 — Integrations manquantes (completes)</summary>

- [x] LEVAMM jamais appele par VaultManager — `levamm` ajoute au storage VaultManager. `accrue_interest()` + `collect_fees()` wires.
- [x] RiskManager jamais invoque — `check_withdrawal_limit()` + `record_withdrawal()` appeles dans withdraw.
- [x] Pragma staleness check — `_check_price_staleness()` dans deposit/withdraw. Backwards compatible.
- [x] FeeDistributor.distribute() = stub — Claim functions transferent du vrai USDC. `usdc_token` ajoute.
- [x] LtToken.distribute_fees() = stub — Accumulateur per-share (MasterChef). `claim_fees()` + `get_claimable_fees()`.
</details>

<details>
<summary>P2 — Systeme de fees (complet)</summary>

- [x] Fee collection depuis Ekubo — `VaultManager.collect_fees()` trigger LEVAMM.
- [x] Wire VaultManager → FeeDistributor.
- [x] distribute() transfere du vrai USDC.
- [x] Compound 50% back to LP — `LEVAMM.collect_fees()` recycle 50%.
- [x] High watermark dans VaultManager.
- [x] Routing des fees autour des stakers.
- [x] veSY fee claim.
- [x] claim_holder_fees permissionless + harvest().
- [x] Wiring deploy: Staker.set_sy_yb_token + LtToken.set_usdc_token dans deploy_all.sh.
</details>

<details>
<summary>P3 — Governance (complet)</summary>

- [x] VotingEscrow — lock/unlock, voting power avec decay lineaire, increase_amount().
- [x] GaugeController — v12 avec verification balance veSyWBTC.
- [x] LiquidityGauge — deposit/withdraw avec transfer_from/transfer, MasterChef rewards.
</details>

<details>
<summary>P4 — Frontend (complet sauf adresses)</summary>

- [x] rebalance() dead code supprime.
- [x] isRebalancing state supprime.
- [x] BTC price — `useBTCPrice.ts` (Binance + fallback on-chain).
- [x] Claim Rewards UI (Staked Vault).
- [x] Claim Fees UI (Yield Bearing Vault).
- [x] Collect Fees + Harvest boutons permissionless.
</details>

<details>
<summary>P5 — Tests (complets)</summary>

- [x] test_vault_manager — 205 lignes, interface v12.
- [x] test_fee_distributor — 368 lignes (admin_fee, distribute, recovery, volatility decay).
- [x] test_levamm — 770 lignes (deploy, init, DTV, swap, fees, rebalancing).
- [x] test_staker — 242 lignes (deploy, reward_rate, total_staked).
- [x] test_governance — 327 lignes (VotingEscrow, GaugeController).
- [x] test_integration — 906 lignes (~30 tests, full system).
- [x] test_ekubo_lp_wrapper — 674 lignes (20 tests, Bunni pattern).
</details>

<details>
<summary>P6 — Cleanup (complet)</summary>

- [x] Supprimer LeverageManager (module + fichier).
- [x] Consolider scripts — `deploy_all.sh` cree.
- [x] Factory supprimee.
</details>

<details>
<summary>P7 — Rebalancing actif compliant (code complet)</summary>

Implementation dans `LEVAMM.swap()` → `_rebalance_cdp()` restaure DTV a ~50%.

**Contrats modifies :**
| Contrat | Changement |
|---------|-----------|
| `amm/levamm.cairo` | `_rebalance_cdp()`, facades, storage `virtual_pool`/`ekubo_adapter`/`lending_adapter`/`rebalance_lp_id`, setters owner-only |
| `integrations/mock_ekubo.cairo` | Multi-position LP : `Map<u64, u256>` par token_id |
| `integrations/mock_lending.cairo` | Per-caller CDP : `Map<ContractAddress, felt252>` |
| `utils/constants.cairo` | `REBALANCE_DTV_THRESHOLD = 0.01e18` |

**Math :**
- Leverage up : `X = (TARGET_DTV * C - D) / (1 - TARGET_DTV)` → flash loan → add LP → borrow → repay
- Deleverage : `Y = (D - TARGET_DTV * C) / (1 - TARGET_DTV)` → flash loan → repay debt → remove LP → repay

**8 tests** couvrent leverage up, deleverage, threshold skip, graceful skip, LP replacement, access control.

**Wiring deploy :** 3 commandes ajoutees dans `deploy_all.sh` (set_virtual_pool, set_ekubo_adapter, set_lending_adapter).
</details>

<details>
<summary>P8 — Auto-harvest + Rename sySY → sy-WBTC (complet)</summary>

**Auto-harvest dans VaultManager :**
- [x] `IFeeDistributorFacade` : ajout `harvest()` dans le trait facade.
- [x] `_auto_harvest()` : methode interne — `collect_fees()` + `FeeDistributor.harvest()`. No-op graceful si LEVAMM=0 ou FeeDistributor=0.
- [x] `deposit()` : appel `_auto_harvest()` avant le flow CDP (les fees existantes sont distribuees avant le nouveau deposit).
- [x] `withdraw()` : appel `_auto_harvest()` apres risk check, avant calcul des shares (remplace l'ancien `accrue_interest()` standalone).

**Rename sySY → sy-WBTC, vesySY → veSyWBTC :**
- [x] Frontend : `VaultPage.tsx` (7 occurrences), `constants.ts` (commentaire).
- [x] Contrats (commentaires/docs) : `staker.cairo`, `sy_yb_token.cairo`, `voting_escrow.cairo`, `gauge_controller.cairo`, `liquidity_gauge.cairo`, `governance.cairo`, `constants.cairo`.
- [x] Deploy scripts : `deploy_v6.sh` (symbol `"sy-WBTC"`), `redeploy_staker_and_swap.sh`, `redeploy_v12.sh`.
- [x] Note : le nom/symbole on-chain est passe au constructeur — pas hardcode. `deploy_all.sh` utilise deja l'adresse existante.
</details>

<details>
<summary>P9 — APR time-normalized (complet)</summary>

**Probleme :** L'ancienne formule APR utilisait `accumulated_trading_fees` (reset a 0 par `collect_fees()`) et multipliait par 365 sans normalisation temporelle. L'APR tombait a 0 apres chaque collect.

**Fix (a la StarkYield) :**
- [x] `levamm.cairo` : ajout `total_fees_generated: u256` (compteur all-time, jamais reset)
- [x] `levamm.cairo` : ajout `init_block: u64` (block d'initialisation)
- [x] `levamm.cairo` : getters `get_total_fees_generated()` + `get_init_block()`
- [x] `levamm.cairo` : `swap()` incremente `total_fees_generated` en plus de `accumulated_trading_fees`
- [x] `useVaultManager.ts` : lit `total_fees_generated`, `init_block`, `getBlockNumber()`
- [x] `VaultPage.tsx` : formule APR time-normalized :
  ```
  r_pool = (totalFeesAllTime / collateral) × (BLOCKS_PER_YEAR / blocksSinceInit) × 100
  ```
- [x] `deploy_all.sh` : redeploy LEVAMM + initialisation + generation de swaps
- [x] `generate_swap_fees.sh` : mis a jour (plus de warning collect_fees)

**Impact :** Le LEVAMM doit etre redeploy (nouveau storage). L'adresse change.
</details>

---

## Recap audit — Ce qui est bien reproduit (95%)

| Aspect | Statut | Detail |
|--------|--------|--------|
| CDP + Leveraged LP | ✅ | Flash loan → LP → collateral → borrow → repay. Fidele a StarkYield. |
| LT Token = ybBTC | ✅ | Shares + fee accumulator (MasterChef pattern). |
| Fee split 50/50 | ✅ | 50% recycle pool, 50% distribue via FeeDistributor. |
| Dynamic admin fee | ✅ | `f_a = 1 - (1 - 0.10) * sqrt(1 - s/T)`. Meme formule. |
| Recovery mode / HWM | ✅ | 100% fees → restauration quand sous le high watermark. |
| Staked vs Unstaked | ✅ | Emissions (sy-WBTC) vs trading fees (USDC). |
| veYB equivalent | ✅ | VotingEscrow + GaugeController + LiquidityGauge. |
| EkuboLPWrapper | ✅ | Adaptation Starknet des LP NFTs en ERC-20 fungibles. |
| APR formula | ✅ | `2*r_pool - (r_borrow + r_releverage)` — time-normalized time-normalized (`total_fees_generated / elapsed`). |
| Rebalancing actif | ✅ | `_rebalance_cdp()` apres chaque swap. |
