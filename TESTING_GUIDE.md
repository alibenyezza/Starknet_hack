# Guide de Test - StarkYield

Ce guide explique comment tester les contrats StarkYield localement et sur le testnet.

## 📋 Prérequis

1. **Scarb** installé (via starkup)
2. **Starknet Foundry (snforge)** pour les tests unitaires
3. **Starkli** pour le déploiement sur testnet
4. **Compte Starknet** avec des fonds sur Sepolia testnet

## 🧪 Tests Unitaires Locaux

### 1. Lancer les tests

```bash
cd contracts
snforge test
```

### 2. Tests disponibles

- **test_sy_btc_token.cairo** : Tests pour le token syBTC
  - Déploiement
  - Mint/Burn
  - Transfer
  - Access control

- **test_vault_manager.cairo** : Tests pour le VaultManager
  - Déploiement
  - Share price calculation
  - Admin functions

### 3. Exécuter un test spécifique

```bash
snforge test test_sy_btc_token::test_mint
```

## 🚀 Déploiement sur Testnet (Sepolia)

### 1. Installation de Starkli

```bash
curl https://get.starkli.sh | sh
source ~/.bashrc
```

### 2. Configuration du compte

```bash
# Créer un nouveau compte (si nécessaire)
starkli account new

# Ou utiliser un compte existant
starkli account fetch <ACCOUNT_ADDRESS> --output account.json
```

### 3. Configuration de l'environnement

```bash
# Copier le fichier d'exemple
cp scripts/.env.example scripts/.env

# Éditer scripts/.env avec vos adresses testnet
nano scripts/.env
```

### 4. Déploiement

```bash
# Rendre le script exécutable
chmod +x scripts/deploy.sh

# Lancer le déploiement
./scripts/deploy.sh
```

Le script va :
1. Compiler les contrats
2. Déclarer les classes de contrats
3. Déployer SyBtcToken
4. Déployer VaultManager
5. Transférer la propriété de syBTC au VaultManager

### 5. Vérification du déploiement

```bash
# Vérifier le nom du token
starkli call <SYBTC_ADDRESS> name

# Vérifier le total supply
starkli call <SYBTC_ADDRESS> total_supply

# Vérifier les shares totales
starkli call <VAULT_ADDRESS> get_total_shares
```

## 🧪 Tests sur Testnet

### 1. Test de Mint (via VaultManager)

```bash
# Approuver le VaultManager pour dépenser vos BTC
starkli invoke <BTC_TOKEN_ADDRESS> \
  approve <VAULT_ADDRESS> 1000000000000000000

# Déposer 1 BTC
starkli invoke <VAULT_ADDRESS> \
  deposit 1000000000000000000
```

### 2. Vérifier les shares reçues

```bash
# Vérifier votre balance de syBTC
starkli call <SYBTC_ADDRESS> balance_of <YOUR_ADDRESS>

# Vérifier vos shares dans le vault
starkli call <VAULT_ADDRESS> get_user_shares <YOUR_ADDRESS>
```

### 3. Test de Withdraw

```bash
# Retirer vos shares (exemple: 50% de vos shares)
starkli invoke <VAULT_ADDRESS> \
  withdraw <SHARES_AMOUNT>
```

### 4. Vérifier le Health Factor

```bash
starkli call <VAULT_ADDRESS> get_health_factor
```

## 📊 Monitoring

### Vérifier l'état du vault

```bash
# Total assets
starkli call <VAULT_ADDRESS> get_total_assets

# Share price
starkli call <VAULT_ADDRESS> get_share_price

# Health factor
starkli call <VAULT_ADDRESS> get_health_factor

# Total shares
starkli call <VAULT_ADDRESS> get_total_shares
```

## 🔧 Dépannage

### Erreur: "Account not found"
- Vérifiez que votre compte est bien configuré avec `starkli account fetch`

### Erreur: "Insufficient balance"
- Assurez-vous d'avoir des fonds sur Sepolia testnet
- Obtenez des ETH de test: https://starknet-faucet.vercel.app/

### Erreur: "Class already declared"
- Le contrat a déjà été déclaré, utilisez le hash existant

### Erreur: "Contract deployment failed"
- Vérifiez que toutes les adresses dans `.env` sont valides
- Vérifiez que vous avez assez de fonds pour le déploiement

## 📝 Checklist de Test

- [ ] Tests unitaires passent (`snforge test`)
- [ ] Contrats compilent sans erreur (`scarb build`)
- [ ] Déploiement sur testnet réussi
- [ ] Test de deposit fonctionne
- [ ] Test de withdraw fonctionne
- [ ] Share price calculé correctement
- [ ] Health factor calculé correctement
- [ ] Admin functions (pause, set_leverage) fonctionnent
- [ ] Access control fonctionne (seul owner peut mint/burn)

## 🔗 Ressources

- [Starknet Docs](https://docs.starknet.io/)
- [Starkli Docs](https://book.starkli.rs/)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/)
- [Sepolia Testnet Explorer](https://sepolia.starkscan.co/)
