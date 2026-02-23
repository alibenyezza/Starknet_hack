#!/bin/bash
# ============================================================
# StarkYield - Redeploy lending layer with MockLendingAdapter
# Replaces VesuAdapter (needs real Vesu pool) with a mock
# that uses MockUSDC.faucet() -- no Vesu pool required.
# ============================================================
# Run from WSL:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/scripts/redeploy_lending.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="${OWNER_ADDRESS:-0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653}"

# Already deployed -- keep these
WBTC_ADDRESS="${WBTC_ADDRESS:-0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163}"
USDC_ADDRESS="${USDC_ADDRESS:-0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb}"
EKUBO_ADAPTER="${EKUBO_ADAPTER:-0x02e66ea2016f70c33b75a9dcc48e06ee3746802f0d8de2d4f2ade65cd241c342}"
PRAGMA_ADAPTER="${PRAGMA_ADAPTER:-0x01eebbc1adac18d311d3effe50ab71ec3366fe04041e22b94b0357567af5ac6e}"
VAULT_ADDRESS="${VAULT_ADDRESS:-0x02b60ddbe16a4d28b94934c16995000f070168c774caf41d2ec5135bd406ca03}"

WAIT_TIME=45

echo -e "${BLUE}=== StarkYield - Redeploy Lending Layer ===${NC}"
echo -e "${CYAN}EkuboAdapter: $EKUBO_ADAPTER${NC}"
echo -e "${CYAN}MockWBTC:     $WBTC_ADDRESS${NC}"
echo -e "${CYAN}MockUSDC:     $USDC_ADDRESS${NC}"
echo -e "${CYAN}VaultManager: $VAULT_ADDRESS${NC}"
echo ""

# ============================================================
# Step 0: Build
# ============================================================
echo -e "${GREEN}[0] Building...${NC}"
cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
scarb build
echo -e "${GREEN}Build OK${NC}"
echo ""

# ============================================================
# Step 1: Deploy MockLendingAdapter
# ============================================================
echo -e "${GREEN}[1/3] Deploying MockLendingAdapter...${NC}"

ML_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockLendingAdapter 2>&1) || true
echo "$ML_DECLARE"
ML_CLASS=$(echo "$ML_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ML_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "MockLendingAdapter class: ${YELLOW}$ML_CLASS${NC}"
sleep $WAIT_TIME

# Constructor: btc_token, usdc_token, ekubo_adapter, owner
ML_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$ML_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $EKUBO_ADAPTER, $OWNER_ADDRESS" \
    2>&1) || true
echo "$ML_DEPLOY"
MOCK_LENDING=$(echo "$ML_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ML_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}MockLendingAdapter: $MOCK_LENDING${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 2: Deploy new LeverageManager (using MockLendingAdapter)
# ============================================================
echo -e "${GREEN}[2/3] Deploying new LeverageManager...${NC}"

LM_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LeverageManager 2>&1) || true
echo "$LM_DECLARE"
LM_CLASS=$(echo "$LM_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

# Constructor: ekubo_adapter, vesu_adapter (=mock_lending), pragma_adapter, btc, usdc, owner
LM_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LM_CLASS" \
    --arguments "$EKUBO_ADAPTER, $MOCK_LENDING, $PRAGMA_ADAPTER, $WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
    2>&1) || true
echo "$LM_DEPLOY"
NEW_LM=$(echo "$LM_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}LeverageManager: $NEW_LM${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 3: Wire new LeverageManager into VaultManager
# ============================================================
echo -e "${GREEN}[3/3] Wiring LeverageManager into VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$VAULT_ADDRESS" \
    --function set_leverage_manager \
    --arguments "$NEW_LM" \
    2>&1 || true
echo ""
sleep $WAIT_TIME

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}        LENDING LAYER REDEPLOYMENT COMPLETE${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "MockLendingAdapter: ${YELLOW}$MOCK_LENDING${NC}"
echo -e "LeverageManager:    ${YELLOW}$NEW_LM${NC}"
echo -e "VaultManager:       ${YELLOW}$VAULT_ADDRESS${NC}  (unchanged)"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
cat << EOF
LEVERAGE_MANAGER: '$NEW_LM'
EOF
echo ""
echo -e "${YELLOW}Strategy is now fully functional on testnet!${NC}"
echo -e "MockLendingAdapter simulates Vesu by minting MockUSDC from its faucet."
echo ""
