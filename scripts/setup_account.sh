#!/bin/bash
# ============================================================
# StarkYield - Account Setup for Starknet Sepolia
# ============================================================
# Run this ONCE to create your deployer account.
#
# Usage (from WSL Ubuntu):
#   cd /mnt/c/Users/byezz/Desktop/starknet_hack
#   bash scripts/setup_account.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RPC_URL="https://starknet-sepolia.public.blastapi.io/rpc/v0_8"
KEYSTORE_FILE="./keystore.json"
ACCOUNT_FILE="./account.json"

echo -e "${BLUE}=== StarkYield - Account Setup ===${NC}"
echo ""

# Check starkli
if ! command -v starkli &> /dev/null; then
    echo -e "${RED}starkli not found!${NC}"
    echo "Install: curl https://get.starkli.sh | sh && starkliup"
    exit 1
fi

# ============================================================
# Step 1: Create keystore (new private key)
# ============================================================
if [ -f "$KEYSTORE_FILE" ]; then
    echo -e "${YELLOW}Keystore already exists at $KEYSTORE_FILE${NC}"
    echo "Delete it first if you want to create a new one."
else
    echo -e "${GREEN}[1/3] Creating new keystore...${NC}"
    echo "You will be asked to set a PASSWORD. Remember it!"
    echo ""
    starkli signer keystore new "$KEYSTORE_FILE"
    echo ""
    echo -e "${GREEN}Keystore created at $KEYSTORE_FILE${NC}"
fi
echo ""

# ============================================================
# Step 2: Init OpenZeppelin account
# ============================================================
if [ -f "$ACCOUNT_FILE" ]; then
    echo -e "${YELLOW}Account file already exists at $ACCOUNT_FILE${NC}"
    echo "Delete it first if you want to create a new one."
else
    echo -e "${GREEN}[2/3] Initializing OpenZeppelin account...${NC}"
    starkli account oz init \
        --keystore "$KEYSTORE_FILE" \
        "$ACCOUNT_FILE"
    echo ""
    echo -e "${GREEN}Account initialized at $ACCOUNT_FILE${NC}"
fi
echo ""

# ============================================================
# Show the address to fund
# ============================================================
# The account file contains the computed address
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}IMPORTANT: Fund your account before deploying!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Your account file: $ACCOUNT_FILE"
echo ""

# Try to extract the address
ADDRESS=$(starkli account oz address --keystore "$KEYSTORE_FILE" "$ACCOUNT_FILE" 2>/dev/null || echo "")
if [ -z "$ADDRESS" ]; then
    # Fallback: compute from account file
    echo "Check your account.json for the computed address."
    echo "Then fund it at the Starknet Sepolia faucet."
else
    echo -e "Your account address: ${GREEN}$ADDRESS${NC}"
    echo ""
    echo "Fund this address with STRK tokens using one of these faucets:"
fi

echo ""
echo "  Faucet 1: https://starknet-faucet.vercel.app/"
echo "  Faucet 2: https://faucet.starknet.io/"
echo ""
echo -e "${YELLOW}After funding, run:${NC}"
echo ""
echo "  starkli account deploy \\"
echo "    --keystore $KEYSTORE_FILE \\"
echo "    --rpc $RPC_URL \\"
echo "    $ACCOUNT_FILE"
echo ""
echo "Then run the deployment:"
echo "  bash scripts/deploy.sh"
echo ""
