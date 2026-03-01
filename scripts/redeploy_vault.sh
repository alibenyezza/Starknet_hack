#!/bin/bash
# ============================================================
# StarkYield - Full redeploy: MockPragma + LM + SyBTC + Vault
#
# Deploys everything fresh using only mock adapters (no real oracles).
# Keeps: MockWBTC, MockUSDC, MockEkubo, MockLending
#
# Run from WSL:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH
#   bash /mnt/c/.../scripts/redeploy_vault.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# Keep existing mock tokens + Ekubo + Lending
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"
MOCK_EKUBO="0x02e66ea2016f70c33b75a9dcc48e06ee3746802f0d8de2d4f2ade65cd241c342"
MOCK_LENDING="0x013640d5dd280ee163b531c13758d737ee00983488cb3858f3dafdf981bf5822"

WAIT_TIME=45

echo -e "${BLUE}=== StarkYield - Full Redeploy (All Mocks) ===${NC}"
echo ""

# ============================================================
# Step 0: Build
# ============================================================
echo -e "${GREEN}[0] Building contracts...${NC}"
cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
scarb build
echo -e "${GREEN}Build OK${NC}"
echo ""

# ============================================================
# Step 1: Deploy MockPragmaAdapter (no real oracle needed)
# ============================================================
echo -e "${GREEN}[1/5] Deploying MockPragmaAdapter...${NC}"
MP_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockPragmaAdapter 2>&1) || true
echo "$MP_DECLARE"
MP_CLASS=$(echo "$MP_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$MP_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$MP_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "MockPragmaAdapter class: ${YELLOW}$MP_CLASS${NC}"
sleep $WAIT_TIME

# Constructor: owner
MP_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$MP_CLASS" \
    --arguments "$OWNER_ADDRESS" \
    2>&1) || true
echo "$MP_DEPLOY"
MOCK_PRAGMA=$(echo "$MP_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$MP_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$MP_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}MockPragmaAdapter: $MOCK_PRAGMA${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 2: Deploy LeverageManager (with MockPragma)
# ============================================================
echo -e "${GREEN}[2/5] Deploying LeverageManager...${NC}"
LM_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LeverageManager 2>&1) || true
echo "$LM_DECLARE"
LM_CLASS=$(echo "$LM_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

# Constructor: ekubo_adapter, vesu_adapter, pragma_adapter, btc_token, usdc_token, owner
LM_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LM_CLASS" \
    --arguments "$MOCK_EKUBO, $MOCK_LENDING, $MOCK_PRAGMA, $WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
    2>&1) || true
echo "$LM_DEPLOY"
NEW_LM=$(echo "$LM_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}LeverageManager: $NEW_LM${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 3: Deploy SyBtcToken
# ============================================================
echo -e "${GREEN}[3/5] Deploying SyBtcToken...${NC}"
SYBTC_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name SyBtcToken 2>&1) || true
echo "$SYBTC_DECLARE"
SYBTC_CLASS=$(echo "$SYBTC_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

SYBTC_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$SYBTC_CLASS" \
    --arguments '"StarkYield BTC", "syBTC", '"$OWNER_ADDRESS" \
    2>&1) || true
echo "$SYBTC_DEPLOY"
NEW_SYBTC=$(echo "$SYBTC_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}SyBtcToken: $NEW_SYBTC${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 4: Deploy VaultManager (all mocks)
# ============================================================
echo -e "${GREEN}[4/5] Deploying VaultManager...${NC}"
VAULT_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager 2>&1) || true
echo "$VAULT_DECLARE"
VAULT_CLASS=$(echo "$VAULT_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

# Constructor: btc, usdc, sybtc, ekubo, vesu, pragma, leverage_manager=0 (no-LM fallback), owner
VAULT_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $NEW_SYBTC, $MOCK_EKUBO, $MOCK_LENDING, $MOCK_PRAGMA, 0x0, $OWNER_ADDRESS" \
    2>&1) || true
echo "$VAULT_DEPLOY"
NEW_VAULT=$(echo "$VAULT_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}VaultManager: $NEW_VAULT${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 5: Transfer SyBTC ownership to VaultManager
# ============================================================
echo -e "${GREEN}[5/5] Transferring syBTC ownership to VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$NEW_SYBTC" \
    --function transfer_ownership \
    --arguments "$NEW_VAULT" \
    2>&1 || true
echo ""
sleep $WAIT_TIME

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}   FULL REDEPLOY COMPLETE (ALL MOCKS - NO REAL ORACLES)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "MockPragmaAdapter: ${YELLOW}$MOCK_PRAGMA${NC}"
echo -e "LeverageManager:   ${YELLOW}$NEW_LM${NC}"
echo -e "SyBtcToken:        ${YELLOW}$NEW_SYBTC${NC}"
echo -e "VaultManager:      ${YELLOW}$NEW_VAULT${NC}"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
cat << EOF
  VAULT_MANAGER: '$NEW_VAULT',
  SY_BTC_TOKEN:  '$NEW_SYBTC',
EOF
echo ""
echo -e "Unchanged:"
echo -e "  BTC_TOKEN:    ${YELLOW}$WBTC_ADDRESS${NC}"
echo -e "  USDC_TOKEN:   ${YELLOW}$USDC_ADDRESS${NC}"
echo -e "  MOCK_EKUBO:   ${YELLOW}$MOCK_EKUBO${NC}"
echo -e "  MOCK_LENDING: ${YELLOW}$MOCK_LENDING${NC}"
echo ""
echo -e "${YELLOW}Restart dev server, then: Faucet -> Deposit -> Withdraw${NC}"
echo ""
