#!/bin/bash
# ============================================================
# StarkYield - Deploy MockEkuboAdapter + new LeverageManager
# Replaces EkuboAdapter (needs real Ekubo pool) with a mock
# that simulates swaps by minting MockWBTC/MockUSDC via faucet.
# ============================================================
# Run from WSL:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/scripts/redeploy_ekubo.sh
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
PRAGMA_ADAPTER="${PRAGMA_ADAPTER:-0x01eebbc1adac18d311d3effe50ab71ec3366fe04041e22b94b0357567af5ac6e}"
VAULT_ADDRESS="${VAULT_ADDRESS:-0x02b60ddbe16a4d28b94934c16995000f070168c774caf41d2ec5135bd406ca03}"

# MockLendingAdapter from previous deploy
MOCK_LENDING="${MOCK_LENDING:-0x0184b3fb971cd3ea627727c32e07b9a071bf4e68de42c61567f8d04ef80a474b}"

WAIT_TIME=45

echo -e "${BLUE}=== StarkYield - Deploy MockEkuboAdapter ===${NC}"
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
# Step 1: Deploy MockEkuboAdapter
# ============================================================
echo -e "${GREEN}[1/3] Deploying MockEkuboAdapter...${NC}"

ME_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockEkuboAdapter 2>&1) || true
echo "$ME_DECLARE"
ME_CLASS=$(echo "$ME_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ME_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "MockEkuboAdapter class: ${YELLOW}$ME_CLASS${NC}"
sleep $WAIT_TIME

# Constructor: btc_token, usdc_token, owner
ME_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$ME_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
    2>&1) || true
echo "$ME_DEPLOY"
MOCK_EKUBO=$(echo "$ME_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$ME_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}MockEkuboAdapter: $MOCK_EKUBO${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 2: Update MockLendingAdapter to point at new MockEkuboAdapter
# ============================================================
echo -e "${GREEN}[2/4] Updating MockLendingAdapter.ekubo_adapter...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$MOCK_LENDING" \
    --function set_ekubo_adapter \
    --arguments "$MOCK_EKUBO" \
    2>&1 || true
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 3: Deploy new LeverageManager (both mocks)
# ============================================================
echo -e "${GREEN}[3/4] Deploying new LeverageManager...${NC}"

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
    --arguments "$MOCK_EKUBO, $MOCK_LENDING, $PRAGMA_ADAPTER, $WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
    2>&1) || true
echo "$LM_DEPLOY"
NEW_LM=$(echo "$LM_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}LeverageManager: $NEW_LM${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 4: Wire new LeverageManager into VaultManager
# ============================================================
echo -e "${GREEN}[4/4] Wiring into VaultManager...${NC}"
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
echo -e "${GREEN}           FULL MOCK STRATEGY DEPLOYED${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "MockEkuboAdapter:   ${YELLOW}$MOCK_EKUBO${NC}"
echo -e "MockLendingAdapter: ${YELLOW}$MOCK_LENDING${NC}  (updated)"
echo -e "LeverageManager:    ${YELLOW}$NEW_LM${NC}"
echo -e "VaultManager:       ${YELLOW}$VAULT_ADDRESS${NC}  (unchanged)"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
cat << EOF
EKUBO_POOL:       '$MOCK_EKUBO'
LEVERAGE_MANAGER: '$NEW_LM'
EOF
echo ""
echo -e "${YELLOW}Strategy is now FULLY functional on testnet — no real pools needed!${NC}"
echo ""
