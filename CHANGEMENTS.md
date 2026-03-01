# CHANGEMENTS — StarkYield → YieldBasis sur Starknet

## Objectif

Transposer le protocole YieldBasis (Curve/Ethereum) sur Starknet en reutilisant l'infrastructure existante de StarkYield. Le changement fondamental est le **flow de depot** : passer d'un split 50/50 (LP + leverage separes) a un flow atomique ou **100% du BTC va en LP** et le levier vient d'un **CDP contre le LP token**.

---

## Flow actuel (StarkYield)

```
User depose 1 BTC
  └─ LeverageManager.allocate() split 50/50 :
      ├─ 0.5 BTC → Ekubo LP (swap 0.25 BTC en USDC + add_liquidity)
      └─ 0.5 BTC → Vesu (collateral BTC → borrow USDC → swap → re-collateral)
```

## Flow cible (YieldBasis)

```
User depose 1 BTC ($100k)
  1. VirtualPool.flash_loan(100k USDC) — pret sans frais
  2. 1 BTC + 100k USDC → Ekubo add_liquidity → LP token ($200k)
  3. LP token depose comme collateral dans le CDP (Vesu)
  4. Emprunter 100k USDC contre le LP
  5. Rembourser le flash loan avec les USDC empruntes
  → Position finale : LP $200k, dette $100k, DTV = 50%, levier 2x
```

---

## 1. vault_manager.cairo — Refonte du depot/retrait

### Depot (a remplacer)

Supprimer l'appel a `LeverageManager.allocate()` avec son split 50/50.

Nouveau flow `deposit(btc_amount)` :

```
1. Transferer BTC du user vers le vault
2. Calculer usdc_needed = btc_amount * btc_price (via oracle Pragma)
3. Appeler VirtualPool.flash_loan(usdc_needed)
4. Appeler EkuboAdapter.add_liquidity(btc_amount, usdc_needed) → lp_token_id
5. Appeler VesuAdapter.deposit_collateral(lp_token_id)  // LP comme collateral
6. Appeler VesuAdapter.borrow_usdc(usdc_needed)
7. Rembourser le flash loan a la VirtualPool
8. Mint syBTC (LT) shares au user
```

Tout cela doit etre **atomique** (une seule transaction).

### Retrait (a remplacer)

Nouveau flow `withdraw(shares)` :

```
1. Calculer btc_amount proportionnel aux shares
2. Calculer usdc_debt = dette proportionnelle aux shares
3. Appeler VirtualPool.flash_loan(usdc_debt)
4. Rembourser la dette Vesu avec les USDC flash-loanes
5. Retirer le LP du CDP (VesuAdapter.withdraw_collateral)
6. Appeler EkuboAdapter.remove_liquidity(lp_token_id) → recuperer BTC + USDC
7. Rembourser le flash loan avec les USDC recuperes du LP
8. Burn les syBTC shares
9. Transferer le BTC au user
```

### Storage a modifier

Supprimer :
- `btc_in_lp` (plus de split)
- `btc_leveraged` (plus de split)

Ajouter :
- `lp_token_id` : felt252 — ID de la position LP Ekubo
- `total_lp_value` : u256 — valeur totale du LP en USD
- `total_debt` : u256 — dette totale USDC du CDP
- `user_debt` : mapping(address → u256) — dette par user (ou calculee via shares)

---

## 2. leverage_manager.cairo — Supprimer ou refondre

### Option A : Supprimer

Le LeverageManager n'a plus de raison d'exister. Toute la logique (flash loan → LP → CDP → repay) est dans le VaultManager.

### Option B : Refondre en PositionManager

Si on le garde, renommer en `position_manager.cairo` et refondre :
- `open_position(btc_amount)` : flash loan → LP → CDP → repay (logique du depot)
- `close_position(shares)` : flash loan → repay debt → withdraw LP → burn LP → return BTC (logique du retrait)
- Supprimer `allocate()`, `deallocate()`, `increase_leverage()`, `reduce_leverage()` (plus utilises)

---

## 3. virtual_pool.cairo — Ajouter flash_loan()

### Actuellement

Ne fait que du reequilibrage quand le DTV derive. Pas de flash loan reel.

### A ajouter

**Fonction `flash_loan(amount, callback_data)` :**

```cairo
fn flash_loan(ref self: ContractState, amount: u256, callback_data: felt252) {
    // 1. Transferer `amount` USDC au caller
    // 2. Executer le callback (le caller fait ce qu'il veut avec les USDC)
    // 3. Verifier que le caller a rembourse `amount` USDC (pas de frais)
    // 4. Si pas rembourse → revert
}
```

- Fee-less (0% de frais) — c'est le principe cle de YieldBasis
- Utilise pour les depots, retraits ET le reequilibrage
- La VirtualPool doit avoir une reserve de USDC ou pouvoir en minter via le CDP

### Modifier rebalance()

Le reequilibrage actuel simule un swap correctif. Le nouveau flow :

```
fn rebalance(ref self: ContractState) {
    // 1. Verifier que DTV est hors bande [6.25%, 53.125%]
    // 2. Flash-borrow USDC de la reserve
    // 3. Si sous-levier (DTV < 50%) :
    //    a. Mint nouveau LP sur Ekubo (BTC + USDC flash-loanes)
    //    b. Poster LP comme collateral supplementaire
    //    c. Emprunter plus d'USDC contre le nouveau LP
    //    d. Rembourser le flash loan
    // 4. Si sur-levier (DTV > 50%) :
    //    a. Retirer du LP du CDP
    //    b. Burn LP → recuperer BTC + USDC
    //    c. Rembourser une partie de la dette
    //    d. Rembourser le flash loan
    // 5. Distribuer le profit a l'arbitrageur (caller)
}
```

---

## 4. levamm.cairo — Swap LP/USDC au lieu de BTC/USDC

### Actuellement

Le LEVAMM echange BTC contre USDC. L'invariant utilise `d_btc = debt / btc_price`.

### A changer

Le LEVAMM doit echanger des **LP tokens contre USDC** :
- `x` = quantite de LP disponible (pas de BTC)
- `y` = quantite de USDC
- `d` = dette USDC du CDP

Invariant (inchange mathematiquement) :
```
(x0 - d) * y = I(p0)
```

Mais les variables representent des choses differentes :
- `x0` = anchor LP calculee a partir du prix oracle
- `d` = dette USDC totale

Comportement du pricing :
- DTV < 50% (prix BTC monte) → LP cote **cher** en USDC → arbitrageurs achetent LP → dette augmente
- DTV > 50% (prix BTC baisse) → LP cote **pas cher** → arbitrageurs vendent LP → dette diminue

### Modifier swap()

```cairo
fn swap(ref self: ContractState, is_buy: bool, amount: u256) -> u256 {
    // is_buy = true : arbitrageur envoie USDC, recoit LP
    // is_buy = false : arbitrageur envoie LP, recoit USDC
    // Le swap doit passer par la VirtualPool pour etre atomique
}
```

---

## 5. Adaptateurs d'integration

### ekubo.cairo / mock_ekubo.cairo

Ajouter :
- `get_lp_value(position_id) -> u256` : retourne la valeur USD du LP token (necessaire pour le health factor du CDP)
- `transfer_lp(position_id, to)` : transferer le LP au CDP comme collateral
- Le LP Ekubo est un NFT (position). Il faut pouvoir le deposer dans Vesu comme collateral

### vesu.cairo / mock_lending.cairo

Modifier :
- `deposit_collateral()` doit accepter un **LP token** (pas du BTC brut)
- Le LTV est calcule sur la **valeur du LP** (pas la valeur du BTC)
- Ajouter `get_collateral_value() -> u256` : valeur actuelle du LP depose

### pragma_oracle.cairo / mock_pragma.cairo

Ajouter :
- `get_lp_price(lp_value, btc_price) -> u256` : oracle pour le pricing du LP
- Equivalent du `CryptopoolLPOracle.vy` de YieldBasis
- Formule : prix LP = f(btc_price, reserves_btc, reserves_usdc, total_supply_lp)

---

## 6. Systeme de fees — A implementer

### Actuellement

Aucun systeme de fees dans le protocole.

### A implementer

**Distribution des trading fees Ekubo (3 niveaux) :**

```
Trading fees de la pool Ekubo
  ├─ 50% → reinjectes dans la pool Ekubo (rebalancing / deepening)
  └─ 50% → distribuables :
       ├─ Soustraire volatility decay (cout du reequilibrage)
       └─ Reste distribue :
            ├─ (1 - f_a) → holders de LT non stakes
            └─ f_a → holders de vesyYB (governance)
```

**Formule admin fee dynamique :**

```
f_a = 1 - (1 - f_min) * sqrt(1 - s/T)
```

- `T` = total LT supply
- `s` = LT stakes (dans LiquidityGauge)
- `f_min` = 10% (minimum, configurable par governance)
- `s = 0` → `f_a = 10%` (90% aux LT holders)
- `s = T` → `f_a = 100%` (tout aux vesyYB)

**Recycling des interets d'emprunt :**

```
100% des interets du CDP → donnes a la pool Ekubo via add_liquidity(donation=true)
```

Ajouter une fonction `distribute_borrower_fees()` :
1. Calculer les interets accumules : `d_new - d_old`
2. Harvest les interets
3. Les ajouter comme liquidite dans la pool Ekubo (deepening)

### Fichiers a creer/modifier

- Creer `fees/fee_distributor.cairo` : logique de distribution des fees
- Modifier `levamm.cairo` : `accrue_interest()` doit recycler les interets dans la pool
- Modifier `sy_btc_token.cairo` (LT) : ajouter la logique de distribution de fees aux holders

---

## 7. Tokens — Renommage et adaptation

### syBTC → LT (Liquidity Token)

- Renommer `sy_btc_token.cairo` en `lt_token.cairo`
- Le LT represente une claim sur une position LP 2x leveragee
- Sa valeur suit le prix du BTC 1:1 (grace au levier 2x)
- Ajouter la distribution de fees aux holders (pro-rata)

### syYB → YB (Governance Token)

- Renommer `sy_yb_token.cairo` en `yb_token.cairo` (optionnel)
- Distribue aux stakers de LT via le LiquidityGauge
- Lockable dans VotingEscrow pour vesyYB (voting power)

---

## 8. Governance — Completer les stubs

### voting_escrow.cairo

Implementer :
- `lock(amount, duration)` : locker YB pour 1 semaine a 4 ans → recevoir vesyYB
- Voting power decroissant lineairement avec le temps
- `withdraw()` : recuperer YB apres expiration du lock

### gauge_controller.cairo

Implementer :
- `vote_for_gauge(gauge_id, weight)` : voter pour allouer les emissions YB
- `get_gauge_weight(gauge_id) -> u256` : poids du gauge
- `checkpoint()` : mettre a jour les poids

### liquidity_gauge.cairo

Implementer :
- ERC4626 vault : staker LT → recevoir YB emissions proportionnelles au poids du gauge
- `deposit(lt_amount)` : staker LT
- `withdraw(lt_amount)` : unstaker
- `claim_rewards()` : reclamer les YB accumules

---

## 9. risk_manager.cairo — Adapter les seuils

### Actuellement

Health factor base sur collateral BTC / dette USDC.

### A changer

- Health factor base sur **valeur LP / dette USDC**
- La valeur du LP varie avec le prix du BTC ET les reserves de la pool
- Les seuils restent :
  - Safe >= 2.0
  - Moderate 1.5 a 2.0
  - Warning 1.2 a 1.5
  - Danger 1.0 a 1.2
  - Liquidation < 1.0

---

## 10. il_eliminator.cairo — Simplifier

### Actuellement

Calcule l'IL avec `IL = 1 - 2*sqrt(r)/(1+r)` et ajuste le levier.

### A changer

Dans le flow YieldBasis, l'IL est eliminee **structurellement** par le levier 2x. Ce contrat devient du monitoring pur (pas de logique active). Le reequilibrage est pilote par le **DTV du CDP** via la VirtualPool, pas par un calcul d'IL.

---

## 11. constants.cairo — Ajouter les constantes YieldBasis

```cairo
// Fee structure
const FEE_POOL_SHARE: u256 = 500_000_000_000_000_000;   // 50% des fees → pool
const FEE_DIST_SHARE: u256 = 500_000_000_000_000_000;   // 50% des fees → distribution
const MIN_ADMIN_FEE: u256 = 100_000_000_000_000_000;    // f_min = 10%
const FLASH_LOAN_FEE: u256 = 0;                          // 0% — fee-less

// DTV (inchanges)
const TARGET_DTV: u256 = 500_000_000_000_000_000;        // 50%
const DTV_MIN_2X: u256 = 62_500_000_000_000_000;         // 6.25%
const DTV_MAX_2X: u256 = 531_250_000_000_000_000;        // 53.125%

// Interest recycling
const INTEREST_RECYCLE_RATE: u256 = 1_000_000_000_000_000_000; // 100% → pool
```

---

## 12. Frontend — Adapter les hooks et l'UI

### useVaultManager.ts

- Le deposit n'a plus de split visible. Un seul appel `vault.deposit(btcAmount)`
- Les stats affichees doivent montrer :
  - Valeur LP totale (pas `btc_in_lp` + `btc_leveraged`)
  - Dette CDP totale
  - DTV actuel (%)
  - Health factor du CDP
- Le bouton "Rebalance" dans le vault page est pour les **keepers** (reequilibrage du leverage)
- Le bouton "VirtualPool" est pour les **arbitrageurs** (reequilibrage du DTV)

### VaultPage.tsx

- Supprimer l'affichage separe LP / Leverage
- Afficher : "Your LP Position" avec valeur, dette, DTV
- Le yield vient des trading fees de la pool (pas juste d'un APY fixe simule)

---

## 13. Fichiers a creer

| Fichier | Role |
|---------|------|
| `fees/fee_distributor.cairo` | Distribution des fees (50/50 + admin fee dynamique) |
| `vault/lt_token.cairo` | LT token (remplace syBTC) avec distribution de fees |
| `oracle/lp_oracle.cairo` | Oracle pour pricer le LP token (equivalent CryptopoolLPOracle) |

---

## 14. Fichiers a supprimer ou deprecier

| Fichier | Raison |
|---------|--------|
| `strategy/leverage_manager.cairo` | Le split 50/50 n'existe plus |
| `strategy/il_eliminator.cairo` | L'IL est eliminee structurellement, plus besoin de calcul actif |

---

## Resume du flow final

```
DEPOT :
  User → deposit(1 BTC)
    → VirtualPool.flash_loan(100k USDC)
    → Ekubo.add_liquidity(1 BTC + 100k USDC) → LP ($200k)
    → Vesu.deposit_collateral(LP)
    → Vesu.borrow(100k USDC)
    → Rembourser flash loan
    → Mint LT au user

REEQUILIBRAGE (arbitrageur, permissionless) :
  Arbitrageur → VirtualPool.rebalance()
    → Flash-borrow USDC
    → Mint/burn LP sur Ekubo
    → Mint/repay dette sur Vesu CDP
    → Rembourser flash loan
    → Profit pour l'arbitrageur

RETRAIT :
  User → withdraw(LT shares)
    → VirtualPool.flash_loan(dette proportionnelle)
    → Vesu.repay(dette)
    → Vesu.withdraw_collateral(LP)
    → Ekubo.remove_liquidity(LP) → BTC + USDC
    → Rembourser flash loan avec USDC
    → Burn LT
    → Transferer BTC au user

FEES :
  Trading fees Ekubo
    → 50% deepening pool
    → 50% distribues (apres volatility decay)
        → (1 - f_a) holders LT
        → f_a vesyYB holders

INTERETS :
  Interets CDP accumules
    → 100% recycles dans la pool Ekubo (donation)
```
