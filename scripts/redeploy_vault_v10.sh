#!/bin/bash
# ============================================================
# YieldBasis v10 — Deploy VaultManager only (step 3+4 of redeploy_v10)
#
# Run AFTER recharging ETH Sepolia on the owner account.
#
# Run from WSL:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.asdf/bin:/home/byezz/.local/bin:/usr/bin:/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/scripts/redeploy_vault_v10.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# Unchanged
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"
MOCK_EKUBO="0x01f46c9c60dca701db51acfdbd17279145f56446d979ec93d1c63a564b18e1a5"
VIRTUAL_POOL="0x0460d5b3cf27cbf296495c22301badd05a68c50c416036c7ed33c5454eed5f55"

# Deployed in step 1+2 of redeploy_v10
NEW_LENDING="0x01dd29d1a03c90100f76a8a3b9868e7564ffa24c07c7fbfa1f8a4273d99d2fed"
NEW_LT="0x06ca6d8e775e4f9cdb32ac31621b7cc7bae6905b88b8c232846e984396bbab8b"

WAIT_TIME=45

echo -e "${BLUE}=== VaultManager v10 Deploy ===${NC}"
echo -e "${CYAN}LtToken:      $NEW_LT${NC}"
echo -e "${CYAN}Lending:      $NEW_LENDING${NC}"
echo -e "${CYAN}VirtualPool:  $VIRTUAL_POOL${NC}"
echo ""

# Build
cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
scarb build

# ── Step 3: Declare + Deploy VaultManager ────────────────────────────────────
echo -e "${GREEN}[1/2] Declaring VaultManager...${NC}"

VAULT_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager 2>&1) || true
echo "$VAULT_DECLARE"
VAULT_CLASS=$(echo "$VAULT_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "Class hash: ${YELLOW}$VAULT_CLASS${NC}"

if [ -z "$VAULT_CLASS" ]; then
    echo -e "${RED}ERROR: Failed to get class hash. Check ETH balance and retry.${NC}"
    exit 1
fi

sleep $WAIT_TIME

echo -e "${GREEN}Deploying VaultManager...${NC}"
# Constructor: btc_token, usdc_token, lt_token, ekubo_adapter, lending_adapter, virtual_pool, owner
VAULT_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $NEW_LT, $MOCK_EKUBO, $NEW_LENDING, $VIRTUAL_POOL, $OWNER_ADDRESS" \
    2>&1) || true
echo "$VAULT_DEPLOY"
NEW_VAULT=$(echo "$VAULT_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}VaultManager: $NEW_VAULT${NC}"
echo ""

if [ -z "$NEW_VAULT" ]; then
    echo -e "${RED}ERROR: VaultManager deploy failed.${NC}"
    exit 1
fi

sleep $WAIT_TIME

# ── Step 4: Transfer LtToken ownership → VaultManager ────────────────────────
echo -e "${GREEN}[2/2] Transferring LtToken ownership to VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$NEW_LT" \
    --function transfer_ownership \
    --arguments "$NEW_VAULT" \
    2>&1 || true
sleep $WAIT_TIME

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}     v10 COMPLETE — Update frontend/src/config/constants.ts${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
cat << EOF
  VAULT_MANAGER:        '$NEW_VAULT',
  LT_TOKEN:             '$NEW_LT',
  MOCK_LENDING_ADAPTER: '$NEW_LENDING',
  VIRTUAL_POOL:         '$VIRTUAL_POOL',
  MOCK_EKUBO_ADAPTER:   '$MOCK_EKUBO',
  BTC_TOKEN:            '$WBTC_ADDRESS',
  USDC_TOKEN:           '$USDC_ADDRESS',
EOF
echo ""
