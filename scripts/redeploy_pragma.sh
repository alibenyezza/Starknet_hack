#!/bin/bash
# ============================================================
# StarkYield - Deploy MockPragmaAdapter + new LeverageManager
# Replaces real PragmaAdapter (which panics on Sepolia with no
# BTC/USD feed) with a mock returning hardcoded $96k price.
# ============================================================
# Run from WSL:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/scripts/redeploy_pragma.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="${OWNER_ADDRESS:-0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653}"

WBTC_ADDRESS="${WBTC_ADDRESS:-0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163}"
USDC_ADDRESS="${USDC_ADDRESS:-0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb}"
VAULT_ADDRESS="${VAULT_ADDRESS:-0x02b60ddbe16a4d28b94934c16995000f070168c774caf41d2ec5135bd406ca03}"

# Already deployed mocks (from previous steps)
MOCK_EKUBO="${MOCK_EKUBO:-0x05fd7268228036c8237674709b699a732e7c2ae3c7d20ef1306950f3626610f9}"
MOCK_LENDING="${MOCK_LENDING:-0x0184b3fb971cd3ea627727c32e07b9a071bf4e68de42c61567f8d04ef80a474b}"

WAIT_TIME=45

echo -e "${BLUE}=== StarkYield - Deploy MockPragmaAdapter ===${NC}"
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
# Step 1: Deploy MockPragmaAdapter
# ============================================================
echo -e "${GREEN}[1/3] Deploying MockPragmaAdapter...${NC}"

MP_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockPragmaAdapter 2>&1) || true
echo "$MP_DECLARE"
MP_CLASS=$(echo "$MP_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
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
    || echo "$MP_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}MockPragmaAdapter: $MOCK_PRAGMA${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 2: Deploy new LeverageManager with all 3 mocks
# ============================================================
echo -e "${GREEN}[2/3] Deploying new LeverageManager (ekubo=mock, vesu=mock, pragma=mock)...${NC}"

LM_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LeverageManager 2>&1) || true
echo "$LM_DECLARE"
LM_CLASS=$(echo "$LM_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

# Constructor: ekubo_adapter, vesu_adapter, pragma_adapter, btc, usdc, owner
LM_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LM_CLASS" \
    --arguments "$MOCK_EKUBO, $MOCK_LENDING, $MOCK_PRAGMA, $WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
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
echo -e "${GREEN}[3/3] Wiring into VaultManager...${NC}"
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
echo -e "${GREEN}           FULL MOCK STRATEGY (with mock Pragma) DEPLOYED${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "MockPragmaAdapter:  ${YELLOW}$MOCK_PRAGMA${NC}"
echo -e "MockEkuboAdapter:   ${YELLOW}$MOCK_EKUBO${NC}  (unchanged)"
echo -e "MockLendingAdapter: ${YELLOW}$MOCK_LENDING${NC}  (unchanged)"
echo -e "LeverageManager:    ${YELLOW}$NEW_LM${NC}"
echo -e "VaultManager:       ${YELLOW}$VAULT_ADDRESS${NC}  (unchanged)"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
cat << EOF
PRAGMA_ORACLE:    '$MOCK_PRAGMA'
LEVERAGE_MANAGER: '$NEW_LM'
EOF
echo ""
echo -e "${YELLOW}Deposit flow is now FULLY functional — no real oracle needed!${NC}"
echo ""
