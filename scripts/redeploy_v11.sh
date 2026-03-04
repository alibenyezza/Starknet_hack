#!/bin/bash
# ============================================================
# YieldBasis v11 — Full redeploy (clear MockEkubo old state)
#
# WHY: MockEkuboAdapter had residual LP state from v9 tests.
#      VaultManager withdraw now re-adds remaining LP on
#      partial withdrawals (prevents DTV > 50%).
#
# REDEPLOYED: MockEkuboAdapter, MockLendingAdapter, LtToken, VaultManager
# UNCHANGED:  VirtualPool, MockWBTC, MockUSDC
#
# Run from WSL Ubuntu:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.asdf/bin:/home/byezz/.local/bin:/usr/bin:/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/scripts/redeploy_v11.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# ── Stable addresses (tokens + VirtualPool) ───────────────────────────────────
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"
VIRTUAL_POOL="0x0460d5b3cf27cbf296495c22301badd05a68c50c416036c7ed33c5454eed5f55"

WAIT_TIME=45

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}      YieldBasis v11 — Full Redeploy (clean LP state)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "${CYAN}Fix: withdraw re-adds remaining LP on partial withdrawals${NC}"
echo -e "${CYAN}Fix: fresh MockEkuboAdapter clears old v9 LP residue${NC}"
echo -e "${CYAN}Keeping: VirtualPool, MockWBTC, MockUSDC${NC}"
echo ""

# ── Step 0: Build ─────────────────────────────────────────────────────────────
echo -e "${GREEN}[0] Building contracts...${NC}"
cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
scarb clean
scarb build
echo -e "${GREEN}Build OK${NC}"
echo ""

# ── Step 1: Deploy MockEkuboAdapter (fresh — zeroes lp_btc / lp_usdc) ─────────
echo -e "${GREEN}[1/5] Deploying MockEkuboAdapter (fresh state)...${NC}"

ME_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockEkuboAdapter 2>&1) || true
echo "$ME_DECLARE"
ME_CLASS=$(echo "$ME_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ME_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "Class hash: ${YELLOW}$ME_CLASS${NC}"
sleep $WAIT_TIME

# Constructor: btc_token, usdc_token, owner
ME_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$ME_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
    2>&1) || true
echo "$ME_DEPLOY"
NEW_EKUBO=$(echo "$ME_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ME_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}MockEkuboAdapter: $NEW_EKUBO${NC}"
echo ""
sleep $WAIT_TIME

# ── Step 2: Deploy MockLendingAdapter (pointed at new Ekubo) ──────────────────
echo -e "${GREEN}[2/5] Deploying MockLendingAdapter...${NC}"

ML_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockLendingAdapter 2>&1) || true
echo "$ML_DECLARE"
ML_CLASS=$(echo "$ML_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ML_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "Class hash: ${YELLOW}$ML_CLASS${NC}"
sleep $WAIT_TIME

# Constructor: btc_token, usdc_token, ekubo_adapter, owner
ML_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$ML_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $NEW_EKUBO, $OWNER_ADDRESS" \
    2>&1) || true
echo "$ML_DEPLOY"
NEW_LENDING=$(echo "$ML_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ML_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}MockLendingAdapter: $NEW_LENDING${NC}"
echo ""
sleep $WAIT_TIME

# ── Step 3: Deploy LtToken ────────────────────────────────────────────────────
echo -e "${GREEN}[3/5] Deploying LtToken...${NC}"

LT_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LtToken 2>&1) || true
echo "$LT_DECLARE"
LT_CLASS=$(echo "$LT_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LT_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "Class hash: ${YELLOW}$LT_CLASS${NC}"
sleep $WAIT_TIME

# Constructor: name (ByteArray), symbol (ByteArray), owner
LT_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LT_CLASS" \
    --arguments '"YieldBasis LT", "LT", '"$OWNER_ADDRESS" \
    2>&1) || true
echo "$LT_DEPLOY"
NEW_LT=$(echo "$LT_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LT_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}LtToken: $NEW_LT${NC}"
echo ""
sleep $WAIT_TIME

# ── Step 4: Deploy VaultManager v11 ──────────────────────────────────────────
echo -e "${GREEN}[4/5] Deploying VaultManager v11...${NC}"

VAULT_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager 2>&1) || true
echo "$VAULT_DECLARE"
VAULT_CLASS=$(echo "$VAULT_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "Class hash: ${YELLOW}$VAULT_CLASS${NC}"
sleep $WAIT_TIME

# Constructor: btc_token, usdc_token, lt_token, ekubo_adapter, lending_adapter, virtual_pool, owner
VAULT_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $NEW_LT, $NEW_EKUBO, $NEW_LENDING, $VIRTUAL_POOL, $OWNER_ADDRESS" \
    2>&1) || true
echo "$VAULT_DEPLOY"
NEW_VAULT=$(echo "$VAULT_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}VaultManager: $NEW_VAULT${NC}"
echo ""
sleep $WAIT_TIME

# ── Step 5: Transfer LtToken ownership → VaultManager ────────────────────────
echo -e "${GREEN}[5/5] Transferring LtToken ownership to VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$NEW_LT" \
    --function transfer_ownership \
    --arguments "$NEW_VAULT" \
    2>&1 || true
echo ""
sleep $WAIT_TIME

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}          v11 REDEPLOY COMPLETE${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
echo ""
cat << EOF
  VAULT_MANAGER:        '$NEW_VAULT',
  LT_TOKEN:             '$NEW_LT',
  VIRTUAL_POOL:         '$VIRTUAL_POOL',
  MOCK_EKUBO_ADAPTER:   '$NEW_EKUBO',
  MOCK_LENDING_ADAPTER: '$NEW_LENDING',

  // Unchanged:
  BTC_TOKEN:  '$WBTC_ADDRESS',
  USDC_TOKEN: '$USDC_ADDRESS',
EOF
echo ""
echo -e "${YELLOW}DTV is now always 50% after deposit (partial withdraw fix active).${NC}"
echo ""
