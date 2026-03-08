#!/bin/bash
# ============================================================
# StarkYield v7 — Deploy VaultManager only (all others done)
#
# Already deployed:
#   MockEkuboAdapter:   0x01f46c9c60dca701db51acfdbd17279145f56446d979ec93d1c63a564b18e1a5
#   MockLendingAdapter: 0x01d3c4293e6e7a5de4284947d8ba07b64c026e1da7b535d41439e929f13140a1
#   LtToken:            0x0329ea731410c3544d93a8f7326201634b02f76d146ce572709ae410d6756c47
#   VirtualPool:        0x0460d5b3cf27cbf296495c22301badd05a68c50c416036c7ed33c5454eed5f55
#
# IMPORTANT: scarb clean is called first to bust the release-profile cache
#            so the rewritten VaultManager Sierra is compiled fresh.
#
# Usage (from WSL):
#   cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
#   bash ../scripts/deploy_vault_only.sh
# ============================================================

set -e

export HOME=/home/byezz
export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ── Known addresses ──────────────────────────────────────────
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"

MOCK_EKUBO_ADAPTER="0x01f46c9c60dca701db51acfdbd17279145f56446d979ec93d1c63a564b18e1a5"
MOCK_LENDING_ADAPTER="0x01d3c4293e6e7a5de4284947d8ba07b64c026e1da7b535d41439e929f13140a1"
LT_TOKEN="0x0329ea731410c3544d93a8f7326201634b02f76d146ce572709ae410d6756c47"
VIRTUAL_POOL="0x0460d5b3cf27cbf296495c22301badd05a68c50c416036c7ed33c5454eed5f55"

SNCAST_ACCOUNT="sepolia"
WAIT_TIME=45
TMP=$(mktemp)

get_class_hash() {
    grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' "$TMP" 2>/dev/null \
    || grep -oP '0x[0-9a-fA-F]{50,}' "$TMP" 2>/dev/null | head -1 \
    || echo ""
}
get_address() {
    grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' "$TMP" 2>/dev/null \
    || grep -oP '0x[0-9a-fA-F]{50,}' "$TMP" 2>/dev/null | head -1 \
    || echo ""
}

echo -e "${BLUE}=== StarkYield v7 — VaultManager deploy ===${NC}"
echo ""

# ============================================================
# 0. Clean release cache — CRITICAL: forces fresh Sierra compile
#    Without this, sncast declare reuses old cached bytecode
#    (same l2_gas as before despite code changes)
# ============================================================
echo -e "${RED}[0] scarb clean — busting release-profile cache...${NC}"
scarb clean
echo -e "${GREEN}Cache cleared.${NC}"
echo ""

# ============================================================
# 1. Declare VaultManager (rewritten: local facades, no Math/Constants)
#    constructor(btc_token, usdc_token, lt_token, ekubo_adapter,
#                lending_adapter, virtual_pool, owner)
# ============================================================
echo -e "${GREEN}[1/2] Declaring VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager \
    2>&1 | tee "$TMP" || true
VAULT_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $VAULT_CLASS${NC}"

if [ -z "$VAULT_CLASS" ]; then
    echo -e "${RED}ERROR: Failed to get VaultManager class hash. Check output above.${NC}"
    cat "$TMP"
    rm -f "$TMP"
    exit 1
fi
sleep $WAIT_TIME

# ============================================================
# 2. Deploy VaultManager
# ============================================================
echo -e "${GREEN}[2/2] Deploying VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $LT_TOKEN, $MOCK_EKUBO_ADAPTER, $MOCK_LENDING_ADAPTER, $VIRTUAL_POOL, $OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
VAULT_MANAGER=$(get_address); echo -e "${GREEN}VaultManager: $VAULT_MANAGER${NC}"

if [ -z "$VAULT_MANAGER" ]; then
    echo -e "${RED}ERROR: Failed to get VaultManager address. Check output above.${NC}"
    cat "$TMP"
    rm -f "$TMP"
    exit 1
fi
sleep $WAIT_TIME
echo ""

# ============================================================
# 3. Wire-up: LtToken.transfer_ownership → VaultManager
#    (so vault can mint on deposit and burn on withdraw)
# ============================================================
echo -e "${GREEN}[3/3] LtToken.transfer_ownership → VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$LT_TOKEN" \
    --function transfer_ownership \
    --arguments "$VAULT_MANAGER" \
    2>&1 || true
sleep $WAIT_TIME
echo ""

rm -f "$TMP"

# ============================================================
# Summary
# ============================================================
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}    VAULT DEPLOY COMPLETE${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "MockEkuboAdapter:   ${YELLOW}$MOCK_EKUBO_ADAPTER${NC}"
echo -e "MockLendingAdapter: ${YELLOW}$MOCK_LENDING_ADAPTER${NC}"
echo -e "LtToken:            ${YELLOW}$LT_TOKEN${NC}"
echo -e "VirtualPool:        ${YELLOW}$VIRTUAL_POOL${NC}"
echo -e "VaultManager:       ${YELLOW}$VAULT_MANAGER${NC}"
echo ""
echo -e "${BLUE}Paste into frontend/src/config/constants.ts:${NC}"
echo "  VAULT_MANAGER:        '$VAULT_MANAGER',"
echo "  LT_TOKEN:             '$LT_TOKEN',"
echo "  VIRTUAL_POOL:         '$VIRTUAL_POOL',"
echo "  MOCK_EKUBO_ADAPTER:   '$MOCK_EKUBO_ADAPTER',"
echo "  MOCK_LENDING_ADAPTER: '$MOCK_LENDING_ADAPTER',"
echo ""
echo "Explorer:"
echo "  https://sepolia.starkscan.co/contract/$VAULT_MANAGER"
echo "  https://sepolia.starkscan.co/contract/$VIRTUAL_POOL"
echo "  https://sepolia.starkscan.co/contract/$LT_TOKEN"
