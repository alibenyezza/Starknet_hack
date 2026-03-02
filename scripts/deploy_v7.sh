#!/bin/bash
# ============================================================
# YieldBasis v7 — Full redeployment: MockEkubo + MockLending
#                 + LtToken + VirtualPool + VaultManager
#
# What changed vs v6:
#   - MockEkuboAdapter:  new IMockEkuboLP interface (get_lp_value, transfer_lp)
#   - MockLendingAdapter: new IMockLendingLP interface (deposit_collateral_lp, etc.)
#   - LtToken:            new contract (replaces SyBtcToken as vault share)
#   - VirtualPool:        new flash_loan / repay_flash_loan functions
#   - VaultManager:       full YieldBasis rewrite (CDP + flash loan flow)
#
# Usage (from WSL):
#   cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
#   bash ../scripts/deploy_v7.sh
# ============================================================

set -e

# ── PATH (requis pour sncast/scarb depuis WSL) ───────────────
export HOME=/home/byezz
export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Adresses stables (tokens + oracle, inchangées) ────────────
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"
MOCK_PRAGMA_ADAPTER="0x069751dd1f1d78907f361a725af5d06937e5c25839fcffaf898fbd1e79fd49c2"
# LevAMM from v6 (unchanged — only used for VirtualPool rebalance, not deposit/withdraw)
LEVAMM_ADDRESS="0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af"

SNCAST_ACCOUNT="sepolia"
WAIT_TIME=45
TMP=$(mktemp)

REBALANCE_COOLDOWN="10"

# ── Helpers ───────────────────────────────────────────────────
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

echo -e "${BLUE}=== YieldBasis v7 Deployment ===${NC}"
echo ""

# ============================================================
# 1. MockEkuboAdapter
#    constructor(btc_token, usdc_token, owner)
# ============================================================
echo -e "${GREEN}[1/5] Declaring MockEkuboAdapter...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockEkuboAdapter \
    2>&1 | tee "$TMP" || true
EKUBO_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $EKUBO_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[1/5] Deploying MockEkuboAdapter...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$EKUBO_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
MOCK_EKUBO_ADAPTER=$(get_address); echo -e "${GREEN}MockEkuboAdapter: $MOCK_EKUBO_ADAPTER${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 2. MockLendingAdapter
#    constructor(btc_token, usdc_token, ekubo_adapter, owner)
# ============================================================
echo -e "${GREEN}[2/5] Declaring MockLendingAdapter...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockLendingAdapter \
    2>&1 | tee "$TMP" || true
LENDING_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $LENDING_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[2/5] Deploying MockLendingAdapter...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LENDING_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $MOCK_EKUBO_ADAPTER, $OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
MOCK_LENDING_ADAPTER=$(get_address); echo -e "${GREEN}MockLendingAdapter: $MOCK_LENDING_ADAPTER${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 3. LtToken  (vault share token, replaces SyBtcToken)
#    constructor(name: ByteArray, symbol: ByteArray, owner)
#    owner starts as OWNER_ADDRESS, transferred to VaultManager at step 6
# ============================================================
echo -e "${GREEN}[3/5] Declaring LtToken...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LtToken \
    2>&1 | tee "$TMP" || true
LT_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $LT_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[3/5] Deploying LtToken...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LT_CLASS" \
    --arguments "\"YieldBasis LT\", \"LT\", $OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
LT_TOKEN=$(get_address); echo -e "${GREEN}LtToken: $LT_TOKEN${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 4. VirtualPool  (flash loan provider + LEVAMM rebalancer)
#    constructor(owner, btc_token, usdc_token, lending_adapter,
#                ekubo_adapter, levamm, rebalance_cooldown: u64)
# ============================================================
echo -e "${GREEN}[4/5] Declaring VirtualPool...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VirtualPool \
    2>&1 | tee "$TMP" || true
VPOOL_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $VPOOL_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[4/5] Deploying VirtualPool...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VPOOL_CLASS" \
    --arguments "$OWNER_ADDRESS, $WBTC_ADDRESS, $USDC_ADDRESS, $MOCK_LENDING_ADAPTER, $MOCK_EKUBO_ADAPTER, $LEVAMM_ADDRESS, $REBALANCE_COOLDOWN" \
    2>&1 | tee "$TMP" || true
VIRTUAL_POOL=$(get_address); echo -e "${GREEN}VirtualPool: $VIRTUAL_POOL${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 5. VaultManager  (YieldBasis core: CDP + flash-loan deposit/withdraw)
#    constructor(btc_token, usdc_token, lt_token, ekubo_adapter,
#                lending_adapter, virtual_pool, pragma_adapter, owner)
# ============================================================
echo -e "${GREEN}[5/5] Declaring VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager \
    2>&1 | tee "$TMP" || true
VAULT_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $VAULT_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[5/5] Deploying VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $LT_TOKEN, $MOCK_EKUBO_ADAPTER, $MOCK_LENDING_ADAPTER, $VIRTUAL_POOL, $MOCK_PRAGMA_ADAPTER, $OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
VAULT_MANAGER=$(get_address); echo -e "${GREEN}VaultManager: $VAULT_MANAGER${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 6. Wire-up: transfer LtToken ownership to VaultManager
#    so vault can mint (on deposit) and burn (on withdraw)
# ============================================================
echo -e "${GREEN}[6] LtToken.transfer_ownership → VaultManager...${NC}"
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
echo -e "${GREEN}    DEPLOYMENT v7 COMPLETE (YieldBasis)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "MockEkuboAdapter:   ${YELLOW}$MOCK_EKUBO_ADAPTER${NC}"
echo -e "MockLendingAdapter: ${YELLOW}$MOCK_LENDING_ADAPTER${NC}"
echo -e "LtToken:            ${YELLOW}$LT_TOKEN${NC}"
echo -e "VirtualPool:        ${YELLOW}$VIRTUAL_POOL${NC}"
echo -e "VaultManager:       ${YELLOW}$VAULT_MANAGER${NC}"
echo ""
echo -e "${BLUE}Update frontend/src/config/constants.ts:${NC}"
echo "  VAULT_MANAGER:       '$VAULT_MANAGER',"
echo "  LT_TOKEN:            '$LT_TOKEN',"
echo "  VIRTUAL_POOL:        '$VIRTUAL_POOL',"
echo "  MOCK_EKUBO_ADAPTER:  '$MOCK_EKUBO_ADAPTER',"
echo "  MOCK_LENDING_ADAPTER:'$MOCK_LENDING_ADAPTER',"
echo ""
echo "Explorer:"
echo "  https://sepolia.starkscan.co/contract/$VAULT_MANAGER"
echo "  https://sepolia.starkscan.co/contract/$LT_TOKEN"
echo "  https://sepolia.starkscan.co/contract/$VIRTUAL_POOL"
