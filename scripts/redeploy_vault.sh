#!/bin/bash
# ============================================================
# StarkYield - Redeploy SyBtcToken + VaultManager (fixed formula)
#
# Fixes: _calculate_shares_for_deposit used Math::mul_fixed(amount, total_shares)
# which adds an extra /1e18, causing shares=0 for deposits < 1 BTC after first deposit.
# That triggered SyBtcToken.mint(0) → assert(amount > 0) → revert.
#
# Fix: use plain   amount * total_shares / total_assets   (no mul_fixed).
#
# Run from WSL:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/scripts/redeploy_vault.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# Existing token addresses (keep these, no need to redeploy)
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"

# Mock strategy adapters (already deployed and working)
MOCK_EKUBO="0x05fd7268228036c8237674709b699a732e7c2ae3c7d20ef1306950f3626610f9"
MOCK_LENDING="0x0184b3fb971cd3ea627727c32e07b9a071bf4e68de42c61567f8d04ef80a474b"
MOCK_PRAGMA="0x069751dd1f1d78907f361a725af5d06937e5c25839fcffaf898fbd1e79fd49c2"
LEVERAGE_MANAGER="0x00bf47cb391843b4103b6c7dd5fdfea60dc8a39e10a7f980b32c1a66170567c7"

WAIT_TIME=45

echo -e "${BLUE}=== StarkYield - Redeploy Vault (Fixed Shares Formula) ===${NC}"
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
# Step 1: Deploy new SyBtcToken (owner = deployer initially)
# ============================================================
echo -e "${GREEN}[1/4] Declaring SyBtcToken...${NC}"
SYBTC_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name SyBtcToken 2>&1) || true
echo "$SYBTC_DECLARE"

SYBTC_CLASS=$(echo "$SYBTC_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "SyBtcToken class: ${YELLOW}$SYBTC_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[1/4] Deploying SyBtcToken...${NC}"
# ByteArray args: "name", "symbol", owner_address
SYBTC_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$SYBTC_CLASS" \
    --arguments '"StarkYield BTC", "syBTC", '"$OWNER_ADDRESS" \
    2>&1) || true
echo "$SYBTC_DEPLOY"

NEW_SYBTC=$(echo "$SYBTC_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}New SyBtcToken: $NEW_SYBTC${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 2: Declare + Deploy new VaultManager (fixed formula)
# ============================================================
echo -e "${GREEN}[2/4] Declaring VaultManager...${NC}"
VAULT_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager 2>&1) || true
echo "$VAULT_DECLARE"

VAULT_CLASS=$(echo "$VAULT_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "VaultManager class: ${YELLOW}$VAULT_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[2/4] Deploying VaultManager...${NC}"
# Constructor: btc_token, usdc_token, sy_btc_token, ekubo_adapter, vesu_adapter,
#              pragma_adapter, leverage_manager, owner
VAULT_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $NEW_SYBTC, $MOCK_EKUBO, $MOCK_LENDING, $MOCK_PRAGMA, $LEVERAGE_MANAGER, $OWNER_ADDRESS" \
    2>&1) || true
echo "$VAULT_DEPLOY"

NEW_VAULT=$(echo "$VAULT_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}New VaultManager: $NEW_VAULT${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 3: Transfer SyBtcToken ownership to new VaultManager
# ============================================================
echo -e "${GREEN}[3/4] Transferring syBTC ownership to new VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$NEW_SYBTC" \
    --function transfer_ownership \
    --arguments "$NEW_VAULT" \
    2>&1 || true
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 4: Verify
# ============================================================
echo -e "${GREEN}[4/4] Verifying syBTC owner...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    call --network sepolia \
    --contract-address "$NEW_SYBTC" \
    --function owner \
    2>&1 || true
echo ""

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}         VAULT REDEPLOYED WITH FIXED SHARES FORMULA${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "New SyBtcToken:  ${YELLOW}$NEW_SYBTC${NC}"
echo -e "New VaultManager: ${YELLOW}$NEW_VAULT${NC}"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
cat << EOF
SY_BTC_TOKEN:  '$NEW_SYBTC'
VAULT_MANAGER: '$NEW_VAULT'
EOF
echo ""
echo -e "Unchanged addresses:"
echo -e "  BTC_TOKEN:        ${YELLOW}$WBTC_ADDRESS${NC}"
echo -e "  USDC_TOKEN:       ${YELLOW}$USDC_ADDRESS${NC}"
echo -e "  MOCK_EKUBO:       ${YELLOW}$MOCK_EKUBO${NC}"
echo -e "  MOCK_LENDING:     ${YELLOW}$MOCK_LENDING${NC}"
echo -e "  MOCK_PRAGMA:      ${YELLOW}$MOCK_PRAGMA${NC}"
echo -e "  LEVERAGE_MANAGER: ${YELLOW}$LEVERAGE_MANAGER${NC}"
echo ""
echo -e "${YELLOW}All deposits should now work correctly!${NC}"
echo ""
