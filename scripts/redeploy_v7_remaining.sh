#!/bin/bash
# ============================================================
# StarkYield v7 — Continue from step 4 (VirtualPool + VaultManager)
#
# Steps 1-3 already completed:
#   MockEkuboAdapter:   0x01f46c9c60dca701db51acfdbd17279145f56446d979ec93d1c63a564b18e1a5
#   MockLendingAdapter: 0x01d3c4293e6e7a5de4284947d8ba07b64c026e1da7b535d41439e929f13140a1
#   LtToken:            0x0329ea731410c3544d93a8f7326201634b02f76d146ce572709ae410d6756c47
#
# Uses --fee-token eth for large contract declarations (VirtualPool, VaultManager).
#
# Usage (from WSL):
#   cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
#   bash ../scripts/redeploy_v7_remaining.sh
# ============================================================

set -e

export HOME=/home/byezz
export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Already deployed (steps 1-3) ─────────────────────────────
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"
MOCK_PRAGMA_ADAPTER="0x069751dd1f1d78907f361a725af5d06937e5c25839fcffaf898fbd1e79fd49c2"
LEVAMM_ADDRESS="0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af"

MOCK_EKUBO_ADAPTER="0x01f46c9c60dca701db51acfdbd17279145f56446d979ec93d1c63a564b18e1a5"
MOCK_LENDING_ADAPTER="0x01d3c4293e6e7a5de4284947d8ba07b64c026e1da7b535d41439e929f13140a1"
LT_TOKEN="0x0329ea731410c3544d93a8f7326201634b02f76d146ce572709ae410d6756c47"

SNCAST_ACCOUNT="sepolia"
WAIT_TIME=45
TMP=$(mktemp)

REBALANCE_COOLDOWN="10"

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

echo -e "${BLUE}=== StarkYield v7 — Remaining steps (4 + 5 + 6) ===${NC}"
echo ""

# ============================================================
# 4. VirtualPool  — simplified: flash_loan only (no rebalance)
#    constructor(owner, usdc_token)
# ============================================================
echo -e "${GREEN}[4/3] Declaring VirtualPool...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VirtualPool \
    2>&1 | tee "$TMP" || true
VPOOL_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $VPOOL_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[4/3] Deploying VirtualPool...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VPOOL_CLASS" \
    --arguments "$OWNER_ADDRESS, $USDC_ADDRESS" \
    2>&1 | tee "$TMP" || true
VIRTUAL_POOL=$(get_address); echo -e "${GREEN}VirtualPool: $VIRTUAL_POOL${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 5. VaultManager  — no pragma_adapter (uses MockEkubo price)
#    constructor(btc_token, usdc_token, lt_token, ekubo_adapter,
#                lending_adapter, virtual_pool, owner)
# ============================================================
echo -e "${GREEN}[5/3] Declaring VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager \
    2>&1 | tee "$TMP" || true
VAULT_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $VAULT_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[5/3] Deploying VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $LT_TOKEN, $MOCK_EKUBO_ADAPTER, $MOCK_LENDING_ADAPTER, $VIRTUAL_POOL, $OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
VAULT_MANAGER=$(get_address); echo -e "${GREEN}VaultManager: $VAULT_MANAGER${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 6. Wire-up: LtToken.transfer_ownership → VaultManager
# ============================================================
echo -e "${GREEN}[6/3] LtToken.transfer_ownership → VaultManager...${NC}"
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
echo -e "${GREEN}    v7 REMAINING STEPS COMPLETE${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "MockEkuboAdapter:   ${YELLOW}$MOCK_EKUBO_ADAPTER${NC}"
echo -e "MockLendingAdapter: ${YELLOW}$MOCK_LENDING_ADAPTER${NC}"
echo -e "LtToken:            ${YELLOW}$LT_TOKEN${NC}"
echo -e "VirtualPool:        ${YELLOW}$VIRTUAL_POOL${NC}"
echo -e "VaultManager:       ${YELLOW}$VAULT_MANAGER${NC}"
echo ""
echo -e "${BLUE}Update frontend/src/config/constants.ts:${NC}"
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
