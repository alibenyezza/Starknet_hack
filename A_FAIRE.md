# A FAIRE — StarkYield

## Pour byezz : Instructions de deploiement + cleanup

---

## 1. DEPLOIEMENT (priorite 1)

### 1.1 Build les contrats

```bash
cd contracts
scarb build
```

Verifie que ca compile sans erreur. Les 2 fixes sont deja dans le code :
- **LP consolidation** (`vault_manager.cairo` lignes 216-237) — plus de LP orphelin
- **Staker rewards** (`staker.cairo` lignes 172, 233) — `reward_rate * blocks` au lieu de `Math::mul_fixed`

### 1.2 Lancer le redeploy

```bash
cd ..
sed -i 's/\r$//' scripts/redeploy_final.sh
bash scripts/redeploy_final.sh
```

Le script fait 14 etapes automatiquement :
1. Declare + deploy **LtToken** (fresh)
2. Declare + deploy **VaultManager** (LP fix)
3. Declare + deploy **Staker** (rewards fix, rate=1e14)
4. Wire : LT.set_vault, LT.set_usdc_token, LT.set_staker
5. Wire : VaultManager.set_fee_distributor, VaultManager.set_levamm
6. Wire : SyToken.transfer_ownership → Staker
7. Wire : FeeDistributor.set_lt_token, FeeDistributor.set_staker

### 1.3 Mettre a jour le frontend

Copie les 3 adresses affichees par le script dans `frontend/src/config/constants.ts` :
```
VAULT_MANAGER:  '0x...',
LT_TOKEN:       '0x...',
STAKER:         '0x...',
```

### 1.4 Verifier

1. Deposer 5 wBTC × 4 fois → withdraw 3 wBTC → balance devrait etre 2 wBTC
2. Chaque deposit consolide avec l'ancien LP (pas d'orphan)
3. Stake LT → attendre quelques blocks → `pending_rewards()` > 0
4. `claim_rewards()` devrait minter des sy-WBTC

---

## 2. NETTOYAGE DU PROJET (priorite 2)

### 2.1 Scripts obsoletes a supprimer ou archiver

Deplacer dans `scripts/archive/` (ou supprimer) ces vieux scripts :

| Script | Raison |
|--------|--------|
| `deploy.sh` | Remplace par deploy_all.sh |
| `deploy_v6.sh` | Version obsolete |
| `deploy_v7.sh` | Version obsolete |
| `deploy_only_v12.sh` | Remplace par deploy_all.sh |
| `deploy_vault_only.sh` | Partiel, obsolete |
| `deploy_strategy.sh` | Obsolete |
| `redeploy_v7_remaining.sh` | Version obsolete |
| `redeploy_v10.sh` | Version obsolete |
| `redeploy_v11.sh` | Version obsolete |
| `redeploy_v12.sh` | Remplace par redeploy_final.sh |
| `redeploy_vault.sh` | Partiel, obsolete |
| `redeploy_vault_v10.sh` | Version obsolete |
| `redeploy_lt_vault_staker.sh` | Remplace par redeploy_final.sh |
| `redeploy_ekubo.sh` | Composant unique, obsolete |
| `redeploy_lending.sh` | Composant unique, obsolete |
| `redeploy_pragma.sh` | Composant unique, obsolete |
| `redeploy_staker_and_swap.sh` | Remplace par redeploy_final.sh |

**Scripts a garder :**
- `redeploy_final.sh` — Script actuel de deploiement
- `deploy_all.sh` — Full deploy de reference
- `fund_vpool.sh` — Funder le VirtualPool
- `generate_swap_fees.sh` — Generer du volume pour l'APR
- `setup_account.sh` — Setup initial du compte Starknet
- `build_check.sh` — Verification de build (fixer le path hardcode)
- `wsl_build.sh` — Build WSL

### 2.2 Fixer les chemins hardcodes

Plusieurs scripts ont des chemins hardcodes `/mnt/c/Users/byezz/Desktop/...`. Remplacer par :
```bash
cd "$(dirname "${BASH_SOURCE[0]}")/../contracts"
```

Scripts concernes : `build_check.sh`, `deploy_strategy.sh`, `redeploy_ekubo.sh`, `redeploy_lending.sh`

### 2.3 Dependencies npm inutilisees

Dans `frontend/package.json`, ces packages sont installes mais jamais utilises :
```
@lifi/wallet-management
@mysten/dapp-kit
@mysten/sui
@solana/wallet-adapter-react
wagmi
```

Commande : `cd frontend && npm uninstall @lifi/wallet-management @mysten/dapp-kit @mysten/sui @solana/wallet-adapter-react wagmi`

### 2.4 ResourcesPage.tsx

Les adresses dans ResourcesPage etaient obsoletes (v6). Elles ont ete mises a jour pour matcher `constants.ts`. Apres le redeploy, il faudra aussi les mettre a jour avec les nouvelles adresses (ou importer depuis constants.ts).

---

## 3. ETAT ACTUEL DU CODE

### Ce qui marche (testable sur le frontend)
- Deposit/Withdraw wBTC (Yield Bearing Vault)
- Stake/Unstake LT (Staked Vault, multicall depositAndStake)
- Faucet wBTC testnet
- APR dynamique (LEVAMM trading fees + Staker reward_rate)
- Claim sy-WBTC rewards (Staked Vault)
- Claim USDC fees (Yield Bearing Vault)
- Collect Fees + Harvest (permissionless)
- Auto-harvest a chaque deposit/withdraw
- Pause/unpause du VaultManager (owner)

### Ce qui est deploye (Starknet Sepolia)
Tous les contrats sont sur Sepolia. Voir `frontend/src/config/constants.ts` pour les adresses.

### Fixes appliques dans le code source (pas encore deployes)
1. **VaultManager LP consolidation** — `deposit()` consolide les LP au lieu d'en creer un nouveau (lignes 216-237)
2. **Staker reward calculation** — `reward_rate * blocks` au lieu de `Math::mul_fixed(rate, blocks)` qui tronquait a 0

---

## 4. HORS-SCOPE HACKATHON

- [ ] Remplacer MockEkubo par EkuboAdapter (code ecrit : `ekubo.cairo`)
- [ ] Remplacer MockLending par VesuAdapter (code ecrit : `vesu.cairo`)
- [ ] Brancher PragmaAdapter (code ecrit : `pragma_oracle.cairo`)
- [ ] Deployer LPOracle (`oracle/lp_oracle.cairo`)

---

## Recap : Compliance Protocol (95%)

| Aspect | Statut |
|--------|--------|
| CDP + Leveraged LP | OK |
| LT Token (vault shares + fee accumulator) | OK |
| Fee split 50/50 | OK |
| Dynamic admin fee | OK |
| Recovery mode / High Watermark | OK |
| Staked vs Unstaked earning paths | OK |
| Governance (veSyWBTC) | OK |
| EkuboLPWrapper (Bunni-inspired) | OK |
| APR time-normalized | OK |
| Active CDP rebalancing | OK |

---

## 5. SUBMISSION REQUIREMENTS (hackathon)

- [ ] **Working demo** deployed on Starknet testnet (Sepolia) — lancer `redeploy_final.sh` + verifier le frontend
- [ ] **Public GitHub repository** with source code — push la branche propre sur main
- [ ] **Project description** (max 500 words) — a rediger
- [ ] **3-minute video demo** — montrer deposit, withdraw, stake, claim rewards, APR dynamique

---

## 6. AVANT SUBMISSION : NETTOYAGE FINAL

> **IMPORTANT : Une fois tout deploye et verifie, faire ce cleanup puis supprimer ce fichier A_FAIRE.md du repo.**

- [ ] Archiver ou supprimer les ~17 scripts obsoletes (voir section 2.1)
- [ ] Supprimer les deps npm inutilisees (voir section 2.3)
- [ ] Fixer les chemins hardcodes `/mnt/c/Users/byezz/...` dans les scripts restants
- [ ] Supprimer le dead code / console.log inutiles dans le frontend
- [ ] Supprimer `CHANGEMENTS.md` (historique interne, pas utile pour la soumission)
- [ ] Supprimer ce fichier `A_FAIRE.md`
- [ ] Verifier qu'aucun secret n'est dans le repo (`grep -r "PRIVATE" .`)
- [ ] Push final sur main
