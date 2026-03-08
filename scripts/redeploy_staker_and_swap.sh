#!/bin/bash
# ============================================================
# StarkYield — Redeploy Staker (with get_reward_rate) + set rate + swap on LEVAMM
#
# PURPOSE:
#   1. Redeploy Staker contract with new get_reward_rate() getter
#   2. Call set_reward_rate(1e14) → ~52.56% APR for staked vault
#   3. Transfer SyYbToken ownership to new Staker (so it can mint rewards)
#   4. Execute swaps on LEVAMM to generate real accumulated_trading_fees
#
# Run from WSL Ubuntu:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.asdf/bin:/home/byezz/.local/bin:/usr/bin:/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/redeploy_staker_and_swap.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# ── Existing contract addresses (from v6 / v12) ──
LEVAMM_ADDRESS="0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af"
SY_YB_TOKEN="0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e"
SY_BTC_TOKEN="0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3"
LT_TOKEN="0x018a65f5987d06a1e6d537a50ed7c8e4ea5869722f0f3772551e25f81efd4406"
OLD_STAKER="0x04620f57ef40e7e2293ca6d06153930697bcb88d173f1634ba5cff768acec273"

# reward_rate = 1e14 = 100_000_000_000_000 (0.0001 sy-WBTC per block → ~52.56% APR)
REWARD_RATE="100000000000000"

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
        echo -e "${YELLOW}  No tx hash to wait for ($label), sleeping 60s...${NC}"
        sleep 60
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
    echo -e "${YELLOW}  TX wait timeout ($label), continuing anyway...${NC}"
}

do_invoke() {
    local contract="$1"
    local fn="$2"
    local label="$3"
    shift 3
    local args="$*"
    echo -e "${GREEN}Invoking $label...${NC}"
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
        echo -e "${YELLOW}  No tx hash found, sleeping 30s...${NC}"
        sleep 30
    fi
}

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}    StarkYield — Redeploy Staker + LEVAMM Swaps${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ── Step 0: Build ─────────────────────────────────────────────
echo -e "${GREEN}[0] Building contracts...${NC}"
cd /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/contracts
scarb clean
scarb build
echo -e "${GREEN}Build OK${NC}"
echo ""

# ── Step 1: Declare + Deploy new Staker ──────────────────────
echo -e "${BLUE}[1/4] Declaring Staker (with get_reward_rate)...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name Staker \
    2>&1 | tee "$TMP" || true
STAKER_CLASS=$(get_class_hash)
DECLARE_TX=$(get_tx_hash)
echo -e "  Class hash: ${YELLOW}$STAKER_CLASS${NC}"
if grep -q "is already declared" "$TMP" 2>/dev/null; then
    echo -e "  ${CYAN}(already declared, no wait needed)${NC}"
elif [ -n "$DECLARE_TX" ]; then
    wait_for_tx "$DECLARE_TX" "declare Staker"
else
    sleep 60
fi
echo ""

echo -e "${BLUE}[2/4] Deploying new Staker...${NC}"
# Constructor: owner, stake_token (LT), sy_yb_token, initial_reward_rate (u256 = low, high)
# NOTE: stake_token should be LT_TOKEN address (not SY_BTC_TOKEN) for StarkYield staking
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$STAKER_CLASS" \
    --arguments "$OWNER_ADDRESS, $LT_TOKEN, $SY_YB_TOKEN, $REWARD_RATE, 0" \
    2>&1 | tee "$TMP" || true
NEW_STAKER=$(get_address)
DEPLOY_TX=$(get_tx_hash)
echo -e "  New Staker: ${YELLOW}$NEW_STAKER${NC}"
if [ -n "$DEPLOY_TX" ]; then
    wait_for_tx "$DEPLOY_TX" "deploy Staker"
else
    sleep 60
fi
echo ""

# ── Step 2: Transfer SyYbToken ownership to new Staker ──────
echo -e "${BLUE}[3/4] Transferring SyYbToken ownership to new Staker...${NC}"
do_invoke "$SY_YB_TOKEN" "transfer_ownership" "SyYbToken.transfer_ownership → new Staker" "$NEW_STAKER"
echo ""

# ── Step 3: Execute swaps on LEVAMM to generate trading fees ──
echo -e "${BLUE}[4/4] Executing swaps on LEVAMM to generate trading fees...${NC}"

# Swap amount: 0.01 BTC in 1e18 internal units (LEVAMM uses 1e18 internally)
# 0.01 * 1e18 = 10_000_000_000_000_000
SWAP_AMOUNT="10000000000000000"

# Try buy swap (direction=true)
echo -e "${CYAN}  Attempting buy swap (0.01 BTC)...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$LEVAMM_ADDRESS" \
    --function "swap" \
    --arguments "true, $SWAP_AMOUNT, 0" \
    2>&1 | tee "$TMP" || true
BUY_TX=$(get_tx_hash)
if [ -n "$BUY_TX" ]; then
    wait_for_tx "$BUY_TX" "LEVAMM buy swap"
fi

# Try sell swap (direction=false) — opposite direction to balance
echo -e "${CYAN}  Attempting sell swap (0.01 BTC)...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$LEVAMM_ADDRESS" \
    --function "swap" \
    --arguments "false, $SWAP_AMOUNT, 0" \
    2>&1 | tee "$TMP" || true
SELL_TX=$(get_tx_hash)
if [ -n "$SELL_TX" ]; then
    wait_for_tx "$SELL_TX" "LEVAMM sell swap"
fi

# Do a few more swaps to accumulate more fees
echo -e "${CYAN}  Doing additional swaps for more fee accumulation...${NC}"
for i in 1 2 3; do
    echo -e "${CYAN}  Extra buy swap #$i...${NC}"
    sncast --account "$SNCAST_ACCOUNT" \
        invoke --network sepolia \
        --contract-address "$LEVAMM_ADDRESS" \
        --function "swap" \
        --arguments "true, $SWAP_AMOUNT, 0" \
        2>&1 | tee "$TMP" || true
    TH=$(get_tx_hash)
    if [ -n "$TH" ]; then wait_for_tx "$TH" "extra buy #$i"; fi

    echo -e "${CYAN}  Extra sell swap #$i...${NC}"
    sncast --account "$SNCAST_ACCOUNT" \
        invoke --network sepolia \
        --contract-address "$LEVAMM_ADDRESS" \
        --function "swap" \
        --arguments "false, $SWAP_AMOUNT, 0" \
        2>&1 | tee "$TMP" || true
    TH=$(get_tx_hash)
    if [ -n "$TH" ]; then wait_for_tx "$TH" "extra sell #$i"; fi
done

rm -f "$TMP"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}          STAKER REDEPLOY + SWAPS COMPLETE${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "${CYAN}New Staker address:${NC}"
echo -e "  ${YELLOW}$NEW_STAKER${NC}"
echo ""
echo -e "${CYAN}Reward rate set to:${NC}"
echo -e "  ${YELLOW}$REWARD_RATE (1e14 = ~52.56% APR)${NC}"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
echo -e "  STAKER: '${YELLOW}$NEW_STAKER${NC}',"
echo ""
echo -e "${CYAN}Old Staker (deprecated):${NC}"
echo -e "  ${RED}$OLD_STAKER${NC}"
echo ""
echo -e "${CYAN}LEVAMM swaps executed — accumulated_trading_fees should be > 0 now${NC}"
echo -e "${CYAN}The frontend will automatically pick up the real APR values${NC}"
echo ""
