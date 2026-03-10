#!/bin/bash
# ============================================================
# StarkYield — Final Redeploy: LT + VaultManager + Staker
#
# Fixes:
#   1. VaultManager LP consolidation (no more orphaned LPs)
#   2. Staker pending_rewards > 0 (reward_rate * blocks, no truncation)
#
# Run from WSL:
#   sed -i 's/\r$//' scripts/redeploy_final.sh
#   cd contracts && scarb build && cd ..
#   bash scripts/redeploy_final.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"

# ── Unchanged addresses ──────────────────────────────────────
OWNER="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"
BTC_TOKEN="0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b"
USDC_TOKEN="0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306"
EKUBO_ADAPTER="0x013a15529211d5a2775bd698609b379ca1ff70ffa65b8d5f81485b9837c0ee12"
LENDING_ADAPTER="0x001b376346f9b24aca87c85c3a2780bea4941727fbc2a9e821b423d38cc4eb79"
VIRTUAL_POOL="0x0190f9b1eeef43f98b96bc0d4c8dc0b9b2c008013975b1b1061d8564a1cc4753"
RISK_MANAGER="0x0481a49142bec3d6c68c77ec5ab1002c5f438aa55766c3efebbd741d35f25a25"
FEE_DIST="0x0360f009cf2e29fb8a30e133cc7c32783409d341286560114ccff9e3c7fc7362"
LEVAMM="0x007b1a0774303f1a9f5ead5ced7d67bf2ced3ecab52b9095501349b753b67a88"
SY_TOKEN="0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e"

# Reward rate: 1e11 as u256 — APR: ~52.6% with 1 LT, ~5.3% with 10 LT
REWARD_RATE_LOW="100000000000"
REWARD_RATE_HIGH="0"

TMP=$(mktemp)

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
get_tx_hash() {
    grep -oP 'transaction_hash:\s+\K0x[0-9a-fA-F]+' "$TMP" 2>/dev/null | head -1 \
    || grep -oP 'Transaction Hash:\s+\K0x[0-9a-fA-F]+' "$TMP" 2>/dev/null | head -1 \
    || echo ""
}

wait_for_tx() {
    local tx_hash="$1"
    local label="$2"
    if [ -z "$tx_hash" ]; then
        echo -e "${YELLOW}  No tx hash for $label, sleeping 45s...${NC}"
        sleep 45
        return
    fi
    echo -e "${CYAN}  Waiting for tx $tx_hash ($label)...${NC}"
    local attempts=0
    while [ $attempts -lt 30 ]; do
        local status
        status=$(sncast --account "$SNCAST_ACCOUNT" tx-status --network sepolia "$tx_hash" 2>&1 || true)
        if echo "$status" | grep -qiE "accepted|succeeded|AcceptedOnL2|AcceptedOnL1|ACCEPTED_ON_L2|ACCEPTED_ON_L1|SUCCEEDED"; then
            echo -e "${GREEN}  TX confirmed ($label)${NC}"
            return 0
        fi
        if echo "$status" | grep -qiE "rejected|reverted|REJECTED|REVERTED"; then
            echo -e "${RED}  TX REJECTED ($label): $status${NC}"
            return 1
        fi
        attempts=$((attempts + 1))
        sleep 10
    done
    echo -e "${YELLOW}  TX wait timeout ($label), continuing...${NC}"
}

do_declare() {
    local contract_name="$1"
    local label="$2"
    echo -e "${BLUE}Declaring $label...${NC}"
    sncast --account "$SNCAST_ACCOUNT" \
        declare --network sepolia --contract-name "$contract_name" \
        2>&1 | tee "$TMP" || true
    local ch=$(get_class_hash)
    local th=$(get_tx_hash)
    echo -e "  Class hash: ${YELLOW}$ch${NC}"
    if grep -q "is already declared" "$TMP" 2>/dev/null; then
        echo -e "  ${CYAN}(already declared)${NC}"
    elif [ -n "$th" ]; then
        wait_for_tx "$th" "declare $label"
    else
        sleep 45
    fi
    echo "$ch"
}

do_deploy() {
    local class_hash="$1"
    local label="$2"
    shift 2
    local args="$*"
    echo -e "${BLUE}Deploying $label...${NC}"
    sncast --account "$SNCAST_ACCOUNT" \
        deploy --network sepolia \
        --class-hash "$class_hash" \
        --arguments "$args" \
        2>&1 | tee "$TMP" || true
    local addr=$(get_address)
    local th=$(get_tx_hash)
    echo -e "  Address: ${YELLOW}$addr${NC}"
    if [ -n "$th" ]; then
        wait_for_tx "$th" "deploy $label"
    else
        sleep 45
    fi
    echo "$addr"
}

do_invoke() {
    local contract="$1"
    local fn="$2"
    local label="$3"
    shift 3
    local args="$*"
    echo -e "${GREEN}  $label${NC}"
    if [ -n "$args" ]; then
        sncast --account "$SNCAST_ACCOUNT" \
            invoke --network sepolia \
            --contract-address "$contract" \
            --function "$fn" \
            --arguments "$args" \
            2>&1 | tee "$TMP" || true
    else
        sncast --account "$SNCAST_ACCOUNT" \
            invoke --network sepolia \
            --contract-address "$contract" \
            --function "$fn" \
            2>&1 | tee "$TMP" || true
    fi
    local th=$(get_tx_hash)
    if [ -n "$th" ]; then
        wait_for_tx "$th" "$label"
    else
        echo -e "${YELLOW}    No tx hash, sleeping 30s...${NC}"
        sleep 30
    fi
}

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  StarkYield — Final Redeploy (LP fix + Staker rewards fix)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ── Step 0: Build ─────────────────────────────────────────────
echo -e "${GREEN}[0/14] Building contracts...${NC}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTRACT_DIR="$(cd "$SCRIPT_DIR/../contracts" && pwd)"
cd "$CONTRACT_DIR"
scarb build
echo -e "${GREEN}  Build OK${NC}"
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 1: Declare + Deploy (steps 1-6)
# ══════════════════════════════════════════════════════════════

# ── 1. Declare LtToken ────────────────────────────────────────
echo -e "${BLUE}[1/14] Declaring LtToken...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LtToken \
    2>&1 | tee "$TMP" || true
LT_CLASS=$(get_class_hash)
DECLARE_TX=$(get_tx_hash)
echo -e "  Class hash: ${YELLOW}$LT_CLASS${NC}"
if grep -q "is already declared" "$TMP" 2>/dev/null; then
    echo -e "  ${CYAN}(already declared)${NC}"
elif [ -n "$DECLARE_TX" ]; then
    wait_for_tx "$DECLARE_TX" "declare LtToken"
else
    sleep 45
fi
echo ""

# ── 2. Deploy LtToken ────────────────────────────────────────
echo -e "${BLUE}[2/14] Deploying LtToken...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LT_CLASS" \
    --arguments "\"StarkYield LT\", \"LT\", $OWNER" \
    2>&1 | tee "$TMP" || true
LT=$(get_address)
DEPLOY_TX=$(get_tx_hash)
echo -e "  LT address: ${YELLOW}$LT${NC}"
if [ -n "$DEPLOY_TX" ]; then
    wait_for_tx "$DEPLOY_TX" "deploy LtToken"
else
    sleep 45
fi
echo ""

# ── 3. Declare VaultManager ──────────────────────────────────
echo -e "${BLUE}[3/14] Declaring VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager \
    2>&1 | tee "$TMP" || true
VAULT_CLASS=$(get_class_hash)
DECLARE_TX=$(get_tx_hash)
echo -e "  Class hash: ${YELLOW}$VAULT_CLASS${NC}"
if grep -q "is already declared" "$TMP" 2>/dev/null; then
    echo -e "  ${CYAN}(already declared)${NC}"
elif [ -n "$DECLARE_TX" ]; then
    wait_for_tx "$DECLARE_TX" "declare VaultManager"
else
    sleep 45
fi
echo ""

# ── 4. Deploy VaultManager ───────────────────────────────────
echo -e "${BLUE}[4/14] Deploying VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$BTC_TOKEN, $USDC_TOKEN, $LT, $EKUBO_ADAPTER, $LENDING_ADAPTER, $VIRTUAL_POOL, $RISK_MANAGER, $OWNER" \
    2>&1 | tee "$TMP" || true
VAULT=$(get_address)
DEPLOY_TX=$(get_tx_hash)
echo -e "  VaultManager address: ${YELLOW}$VAULT${NC}"
if [ -n "$DEPLOY_TX" ]; then
    wait_for_tx "$DEPLOY_TX" "deploy VaultManager"
else
    sleep 45
fi
echo ""

# ── 5. Declare Staker ────────────────────────────────────────
echo -e "${BLUE}[5/14] Declaring Staker...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name Staker \
    2>&1 | tee "$TMP" || true
STAKER_CLASS=$(get_class_hash)
DECLARE_TX=$(get_tx_hash)
echo -e "  Class hash: ${YELLOW}$STAKER_CLASS${NC}"
if grep -q "is already declared" "$TMP" 2>/dev/null; then
    echo -e "  ${CYAN}(already declared)${NC}"
elif [ -n "$DECLARE_TX" ]; then
    wait_for_tx "$DECLARE_TX" "declare Staker"
else
    sleep 45
fi
echo ""

# ── 6. Deploy Staker ─────────────────────────────────────────
echo -e "${BLUE}[6/14] Deploying Staker...${NC}"
# Constructor: owner, stake_token=LT, sy_token, initial_reward_rate (u256 = low, high)
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$STAKER_CLASS" \
    --arguments "$OWNER, $LT, $SY_TOKEN, $REWARD_RATE_LOW, $REWARD_RATE_HIGH" \
    2>&1 | tee "$TMP" || true
STAKER=$(get_address)
DEPLOY_TX=$(get_tx_hash)
echo -e "  Staker address: ${YELLOW}$STAKER${NC}"
if [ -n "$DEPLOY_TX" ]; then
    wait_for_tx "$DEPLOY_TX" "deploy Staker"
else
    sleep 45
fi
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 2: Wiring (steps 7-14)
# ══════════════════════════════════════════════════════════════
echo -e "${BLUE}── Wiring contracts ──${NC}"
echo ""

# ── 7. LT.set_vault(VAULT) ───────────────────────────────────
echo -e "${BLUE}[7/14]${NC}"
do_invoke "$LT" "set_vault" "LT.set_vault → VaultManager" "$VAULT"
echo ""

# ── 8. LT.set_usdc_token(USDC) ───────────────────────────────
echo -e "${BLUE}[8/14]${NC}"
do_invoke "$LT" "set_usdc_token" "LT.set_usdc_token → USDC" "$USDC_TOKEN"
echo ""

# ── 9. LT.set_staker(STAKER) ─────────────────────────────────
echo -e "${BLUE}[9/14]${NC}"
do_invoke "$LT" "set_staker" "LT.set_staker → Staker (fee exclusion)" "$STAKER"
echo ""

# ── 10. VaultManager.set_fee_distributor(FEE_DIST) ────────────
echo -e "${BLUE}[10/14]${NC}"
do_invoke "$VAULT" "set_fee_distributor" "VaultManager.set_fee_distributor" "$FEE_DIST"
echo ""

# ── 11. VaultManager.set_levamm(LEVAMM) ──────────────────────
echo -e "${BLUE}[11/14]${NC}"
do_invoke "$VAULT" "set_levamm" "VaultManager.set_levamm" "$LEVAMM"
echo ""

# ── 12. SyToken.transfer_ownership(STAKER) ───────────────────
echo -e "${BLUE}[12/14]${NC}"
do_invoke "$SY_TOKEN" "transfer_ownership" "SyToken.transfer_ownership → Staker" "$STAKER"
echo ""

# ── 13. FeeDistributor.set_lt_token(LT) ──────────────────────
echo -e "${BLUE}[13/14]${NC}"
do_invoke "$FEE_DIST" "set_lt_token" "FeeDistributor.set_lt_token → new LT" "$LT"
echo ""

# ── 14. FeeDistributor.set_staker(STAKER) ────────────────────
echo -e "${BLUE}[14/14]${NC}"
do_invoke "$FEE_DIST" "set_staker" "FeeDistributor.set_staker → new Staker" "$STAKER"
echo ""

rm -f "$TMP"

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}            REDEPLOY COMPLETE${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "${CYAN}New addresses:${NC}"
echo -e "  LT_TOKEN:      ${YELLOW}$LT${NC}"
echo -e "  VAULT_MANAGER:  ${YELLOW}$VAULT${NC}"
echo -e "  STAKER:         ${YELLOW}$STAKER${NC}"
echo ""
echo -e "${CYAN}Reward rate:${NC}"
echo -e "  ${YELLOW}$REWARD_RATE_LOW${NC} (1e11 → ~52.6% APR with 1 LT, ~5.3% with 10 LT)"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
echo ""
echo -e "  VAULT_MANAGER:  '${YELLOW}$VAULT${NC}',"
echo -e "  LT_TOKEN:       '${YELLOW}$LT${NC}',"
echo -e "  STAKER:         '${YELLOW}$STAKER${NC}',"
echo ""
echo -e "${CYAN}All other contracts unchanged (BTC, USDC, EKUBO, LENDING, VPOOL, RISK, FEE_DIST, LEVAMM, SY_TOKEN).${NC}"
echo ""
echo -e "${CYAN}Verification checklist:${NC}"
echo -e "  1. Deposit 5 wBTC × 4 times → withdraw 3 wBTC → balance should be 2 wBTC"
echo -e "  2. Each deposit should consolidate with existing LP (no orphans)"
echo -e "  3. Stake LT → wait a few blocks → pending_rewards() > 0"
echo -e "  4. claim_rewards() should mint sy-WBTC"
echo ""
