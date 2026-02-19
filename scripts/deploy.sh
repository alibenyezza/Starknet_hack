#!/bin/bash
# ============================================================
# StarkYield - Deployment Script for Starknet Sepolia
# Uses sncast (Starknet Foundry) for declare/deploy
# ============================================================
# Usage (from WSL):
#   cd /mnt/c/Users/byezz/Desktop/starknethackathon/Starknet_hack/contracts
#   bash ../scripts/deploy.sh
#
# Must be run from the contracts/ directory (where Scarb.toml is)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# CONFIGURATION
# ============================================================
SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="${OWNER_ADDRESS:-0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653}"

USDC_TOKEN="${USDC_TOKEN:-0x0000000000000000000000000000000000000000000000000000000000000002}"
EKUBO_POOL="${EKUBO_POOL:-0x0000000000000000000000000000000000000000000000000000000000000003}"
VESU_LENDING="${VESU_LENDING:-0x0000000000000000000000000000000000000000000000000000000000000004}"
PRAGMA_ORACLE="${PRAGMA_ORACLE:-0x0000000000000000000000000000000000000000000000000000000000000005}"
LEVERAGE_MANAGER="${LEVERAGE_MANAGER:-0x0000000000000000000000000000000000000000000000000000000000000000}"

WAIT_TIME=45

echo -e "${BLUE}=== StarkYield Full Deployment ===${NC}"
echo ""

# ============================================================
# Step 1: Build
# ============================================================
echo -e "${GREEN}[1/8] Building contracts...${NC}"
scarb build
echo -e "${GREEN}Build OK${NC}"
echo ""

# ============================================================
# Step 2: Declare MockWBTC
# ============================================================
echo -e "${GREEN}[2/8] Declaring MockWBTC...${NC}"
WBTC_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockWBTC 2>&1) || true
echo "$WBTC_DECLARE"

WBTC_CLASS_HASH=$(echo "$WBTC_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' || echo "")
if [ -z "$WBTC_CLASS_HASH" ]; then
    WBTC_CLASS_HASH=$(echo "$WBTC_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
fi
echo -e "${GREEN}MockWBTC class hash: $WBTC_CLASS_HASH${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 3: Deploy MockWBTC (no constructor args)
# ============================================================
echo -e "${GREEN}[3/8] Deploying MockWBTC...${NC}"
WBTC_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$WBTC_CLASS_HASH" \
    2>&1) || true
echo "$WBTC_DEPLOY"

WBTC_ADDRESS=$(echo "$WBTC_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' || echo "")
echo -e "${GREEN}MockWBTC: $WBTC_ADDRESS${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 4: Declare SyBtcToken
# ============================================================
echo -e "${GREEN}[4/8] Declaring SyBtcToken...${NC}"
SYBTC_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name SyBtcToken 2>&1) || true
echo "$SYBTC_DECLARE"

SYBTC_CLASS_HASH=$(echo "$SYBTC_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' || echo "")
if [ -z "$SYBTC_CLASS_HASH" ]; then
    SYBTC_CLASS_HASH=$(echo "$SYBTC_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
fi
echo -e "${GREEN}SyBtcToken class hash: $SYBTC_CLASS_HASH${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 5: Deploy SyBtcToken
# ============================================================
echo -e "${GREEN}[5/8] Deploying SyBtcToken...${NC}"
SYBTC_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$SYBTC_CLASS_HASH" \
    --arguments "\"StarkYield BTC\", \"syBTC\", $OWNER_ADDRESS" \
    2>&1) || true
echo "$SYBTC_DEPLOY"

SYBTC_ADDRESS=$(echo "$SYBTC_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' || echo "")
echo -e "${GREEN}SyBtcToken: $SYBTC_ADDRESS${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 6: Declare VaultManager
# ============================================================
echo -e "${GREEN}[6/8] Declaring VaultManager...${NC}"
VAULT_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager 2>&1) || true
echo "$VAULT_DECLARE"

VAULT_CLASS_HASH=$(echo "$VAULT_DECLARE" | grep -oP 'Class Hash:\s+\K0x[0-9a-fA-F]+' || echo "")
if [ -z "$VAULT_CLASS_HASH" ]; then
    VAULT_CLASS_HASH=$(echo "$VAULT_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
fi
echo -e "${GREEN}VaultManager class hash: $VAULT_CLASS_HASH${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 7: Deploy VaultManager (8 args: btc, usdc, sybtc, ekubo, vesu, pragma, leverage_manager, owner)
# ============================================================
echo -e "${GREEN}[7/8] Deploying VaultManager...${NC}"
VAULT_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS_HASH" \
    --arguments "$WBTC_ADDRESS, $USDC_TOKEN, $SYBTC_ADDRESS, $EKUBO_POOL, $VESU_LENDING, $PRAGMA_ORACLE, $LEVERAGE_MANAGER, $OWNER_ADDRESS" \
    2>&1) || true
echo "$VAULT_DEPLOY"

VAULT_ADDRESS=$(echo "$VAULT_DEPLOY" | grep -oP 'Contract Address:\s+\K0x[0-9a-fA-F]+' || echo "")
echo -e "${GREEN}VaultManager: $VAULT_ADDRESS${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 8: Transfer syBTC ownership to VaultManager
# ============================================================
echo -e "${GREEN}[8/8] Transferring syBTC ownership to VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$SYBTC_ADDRESS" \
    --function transfer_ownership \
    --arguments "$VAULT_ADDRESS" \
    2>&1 || true

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}    DEPLOYMENT COMPLETE!${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "MockWBTC:     ${YELLOW}$WBTC_ADDRESS${NC}"
echo -e "SyBtcToken:   ${YELLOW}$SYBTC_ADDRESS${NC}"
echo -e "VaultManager: ${YELLOW}$VAULT_ADDRESS${NC}"
echo ""
echo -e "${BLUE}Update frontend/src/config/constants.ts:${NC}"
echo "  BTC_TOKEN:      '$WBTC_ADDRESS'"
echo "  SY_BTC_TOKEN:   '$SYBTC_ADDRESS'"
echo "  VAULT_MANAGER:  '$VAULT_ADDRESS'"
echo ""
echo "Verify:"
echo "  https://sepolia.starkscan.co/contract/$WBTC_ADDRESS"
echo "  https://sepolia.starkscan.co/contract/$SYBTC_ADDRESS"
echo "  https://sepolia.starkscan.co/contract/$VAULT_ADDRESS"
