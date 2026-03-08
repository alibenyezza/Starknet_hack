#!/bin/bash
# ============================================================
# StarkYield v12 — Full redeploy (decimal fix + new contracts)
#
# WHY: MockWBTC → 8 decimals, MockUSDC → 6 decimals
#      VirtualPool rewritten (reserves-based, no more faucet mint)
#      VaultManager v11 (pause + risk_manager)
#      NEW: EkuboLPWrapper (Bunni-inspired ERC20 LP wrapper)
#      GaugeController security fix (veSyWBTC balance check)
#
# REDEPLOYED: ALL contracts (decimal change propagates everywhere)
#
# Run from WSL Ubuntu:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.asdf/bin:/home/byezz/.local/bin:/usr/bin:/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/redeploy_v12.sh
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

# LevAMM + Staker + SyYB + SyBTC from v6 (unchanged, not redeployed)
LEVAMM_ADDRESS="0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af"
STAKER_ADDRESS="0x04620f57ef40e7e2293ca6d06153930697bcb88d173f1634ba5cff768acec273"
SY_YB_TOKEN="0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e"

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

# Wait for a transaction to be accepted (polls every 10s, max 5min)
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

# Declare + wait
do_declare() {
    local name="$1"
    local label="$2"
    echo -e "${GREEN}Declaring $label...${NC}"
    sncast --account "$SNCAST_ACCOUNT" \
        declare --network sepolia --contract-name "$name" \
        2>&1 | tee "$TMP" || true
    local ch=$(get_class_hash)
    local th=$(get_tx_hash)
    echo -e "  Class hash: ${YELLOW}$ch${NC}"
    # If already declared, no need to wait
    if grep -q "is already declared" "$TMP" 2>/dev/null; then
        echo -e "  ${CYAN}(already declared, no wait needed)${NC}"
    elif [ -n "$th" ]; then
        wait_for_tx "$th" "declare $label"
    else
        echo -e "  ${YELLOW}No tx hash found, sleeping 60s...${NC}"
        sleep 60
    fi
    echo "$ch"
}

# Deploy + wait
do_deploy() {
    local class_hash="$1"
    local label="$2"
    shift 2
    local args="$*"
    echo -e "${GREEN}Deploying $label...${NC}"
    if [ -n "$args" ]; then
        sncast --account "$SNCAST_ACCOUNT" \
            deploy --network sepolia \
            --class-hash "$class_hash" \
            --arguments "$args" \
            2>&1 | tee "$TMP" || true
    else
        sncast --account "$SNCAST_ACCOUNT" \
            deploy --network sepolia \
            --class-hash "$class_hash" \
            2>&1 | tee "$TMP" || true
    fi
    local addr=$(get_address)
    local th=$(get_tx_hash)
    echo -e "  Address: ${YELLOW}$addr${NC}"
    if [ -n "$th" ]; then
        wait_for_tx "$th" "deploy $label"
    else
        echo -e "  ${YELLOW}No tx hash found, sleeping 60s...${NC}"
        sleep 60
    fi
    echo "$addr"
}

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}      StarkYield v12 — Full Redeploy (decimal fix)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "${CYAN}Fix: MockWBTC → 8 decimals, MockUSDC → 6 decimals${NC}"
echo -e "${CYAN}Fix: VirtualPool reserves-based (no faucet mint)${NC}"
echo -e "${CYAN}Fix: VaultManager pause + RiskManager${NC}"
echo -e "${CYAN}New: EkuboLPWrapper (Bunni-inspired ERC20)${NC}"
echo -e "${CYAN}Fix: GaugeController security (veSyWBTC balance check)${NC}"
echo ""

# ── Step 0: Build ─────────────────────────────────────────────────────────────
echo -e "${GREEN}[0] Building contracts...${NC}"
cd /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/contracts
scarb clean
scarb build
echo -e "${GREEN}Build OK${NC}"
echo ""

# ── Step 1: MockWBTC (8 decimals) ─────────────────────────────────────────────
echo -e "${BLUE}[1/9] MockWBTC (8 decimals)${NC}"
WBTC_CLASS=$(do_declare MockWBTC "MockWBTC")
WBTC_ADDRESS=$(do_deploy "$WBTC_CLASS" "MockWBTC")
echo -e "${GREEN}  => MockWBTC: $WBTC_ADDRESS${NC}"
echo ""

# ── Step 2: MockUSDC (6 decimals) ─────────────────────────────────────────────
echo -e "${BLUE}[2/9] MockUSDC (6 decimals)${NC}"
USDC_CLASS=$(do_declare MockUSDC "MockUSDC")
USDC_ADDRESS=$(do_deploy "$USDC_CLASS" "MockUSDC" "$OWNER_ADDRESS")
echo -e "${GREEN}  => MockUSDC: $USDC_ADDRESS${NC}"
echo ""

# ── Step 3: MockEkuboAdapter ─────────────────────────────────────────────────
echo -e "${BLUE}[3/9] MockEkuboAdapter${NC}"
EKUBO_CLASS=$(do_declare MockEkuboAdapter "MockEkuboAdapter")
EKUBO_ADDRESS=$(do_deploy "$EKUBO_CLASS" "MockEkuboAdapter" "$WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS")
echo -e "${GREEN}  => MockEkuboAdapter: $EKUBO_ADDRESS${NC}"
echo ""

# ── Step 4: MockLendingAdapter ────────────────────────────────────────────────
echo -e "${BLUE}[4/9] MockLendingAdapter${NC}"
LENDING_CLASS=$(do_declare MockLendingAdapter "MockLendingAdapter")
LENDING_ADDRESS=$(do_deploy "$LENDING_CLASS" "MockLendingAdapter" "$WBTC_ADDRESS, $USDC_ADDRESS, $EKUBO_ADDRESS, $OWNER_ADDRESS")
echo -e "${GREEN}  => MockLendingAdapter: $LENDING_ADDRESS${NC}"
echo ""

# ── Step 5: LtToken ──────────────────────────────────────────────────────────
echo -e "${BLUE}[5/9] LtToken${NC}"
LT_CLASS=$(do_declare LtToken "LtToken")
LT_ADDRESS=$(do_deploy "$LT_CLASS" "LtToken" "\"StarkYield LT\", \"LT\", $OWNER_ADDRESS")
echo -e "${GREEN}  => LtToken: $LT_ADDRESS${NC}"
echo ""

# ── Step 6: VirtualPool (reserves-based) ─────────────────────────────────────
echo -e "${BLUE}[6/9] VirtualPool${NC}"
VPOOL_CLASS=$(do_declare VirtualPool "VirtualPool")
VPOOL_ADDRESS=$(do_deploy "$VPOOL_CLASS" "VirtualPool" "$OWNER_ADDRESS, $USDC_ADDRESS")
echo -e "${GREEN}  => VirtualPool: $VPOOL_ADDRESS${NC}"
echo ""

# ── Step 7: VaultManager v11 ─────────────────────────────────────────────────
echo -e "${BLUE}[7/9] VaultManager${NC}"
VAULT_CLASS=$(do_declare VaultManager "VaultManager")
VAULT_ADDRESS=$(do_deploy "$VAULT_CLASS" "VaultManager" "$WBTC_ADDRESS, $USDC_ADDRESS, $LT_ADDRESS, $EKUBO_ADDRESS, $LENDING_ADDRESS, $VPOOL_ADDRESS, 0x0, $OWNER_ADDRESS")
echo -e "${GREEN}  => VaultManager: $VAULT_ADDRESS${NC}"
echo ""

# ── Step 8: EkuboLPWrapper (NEW) ─────────────────────────────────────────────
echo -e "${BLUE}[8/9] EkuboLPWrapper (NEW)${NC}"
WRAPPER_CLASS=$(do_declare EkuboLPWrapper "EkuboLPWrapper")
WRAPPER_ADDRESS=$(do_deploy "$WRAPPER_CLASS" "EkuboLPWrapper" "$OWNER_ADDRESS, $WBTC_ADDRESS, $USDC_ADDRESS, $EKUBO_ADDRESS")
echo -e "${GREEN}  => EkuboLPWrapper: $WRAPPER_ADDRESS${NC}"
echo ""

# ── Step 9: GaugeController ──────────────────────────────────────────────────
echo -e "${BLUE}[9/9] GaugeController${NC}"
GAUGE_CLASS=$(do_declare GaugeController "GaugeController")
GAUGE_ADDRESS=$(do_deploy "$GAUGE_CLASS" "GaugeController" "$OWNER_ADDRESS, $SY_YB_TOKEN")
echo -e "${GREEN}  => GaugeController: $GAUGE_ADDRESS${NC}"
echo ""

# ── Wire-up: transfer LtToken ownership → VaultManager ──────────────────────
echo -e "${GREEN}[Wire] LtToken.transfer_ownership → VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$LT_ADDRESS" \
    --function transfer_ownership \
    --arguments "$VAULT_ADDRESS" \
    2>&1 | tee "$TMP" || true
TH=$(get_tx_hash)
if [ -n "$TH" ]; then
    wait_for_tx "$TH" "transfer_ownership"
fi
echo ""

rm -f "$TMP"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}          v12 REDEPLOY COMPLETE (decimal fix)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "${CYAN}NEW contract addresses:${NC}"
echo ""
echo -e "  MockWBTC (8 dec):     ${YELLOW}$WBTC_ADDRESS${NC}"
echo -e "  MockUSDC (6 dec):     ${YELLOW}$USDC_ADDRESS${NC}"
echo -e "  MockEkuboAdapter:     ${YELLOW}$EKUBO_ADDRESS${NC}"
echo -e "  MockLendingAdapter:   ${YELLOW}$LENDING_ADDRESS${NC}"
echo -e "  LtToken:              ${YELLOW}$LT_ADDRESS${NC}"
echo -e "  VirtualPool:          ${YELLOW}$VPOOL_ADDRESS${NC}"
echo -e "  VaultManager:         ${YELLOW}$VAULT_ADDRESS${NC}"
echo -e "  EkuboLPWrapper (NEW): ${YELLOW}$WRAPPER_ADDRESS${NC}"
echo -e "  GaugeController:      ${YELLOW}$GAUGE_ADDRESS${NC}"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
echo ""
cat << EOF
export const CONTRACTS = {
  VAULT_MANAGER:        '$VAULT_ADDRESS',
  LT_TOKEN:             '$LT_ADDRESS',
  VIRTUAL_POOL:         '$VPOOL_ADDRESS',
  MOCK_EKUBO_ADAPTER:   '$EKUBO_ADDRESS',
  MOCK_LENDING_ADAPTER: '$LENDING_ADDRESS',
  BTC_TOKEN:            '$WBTC_ADDRESS',
  USDC_TOKEN:           '$USDC_ADDRESS',
  EKUBO_LP_WRAPPER:     '$WRAPPER_ADDRESS',
  GAUGE_CONTROLLER:     '$GAUGE_ADDRESS',
  // v6 (unchanged)
  FACTORY:       '0x0253d30100bd7cbbc2bf146bdddcbb4adfc0cae0dc3d2a3ab172a1b4e21c8780',
  LEVAMM:        '$LEVAMM_ADDRESS',
  STAKER:        '$STAKER_ADDRESS',
  SY_YB_TOKEN:   '$SY_YB_TOKEN',
  SY_BTC_TOKEN:  '0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3',
} as const;
EOF
echo ""
echo -e "${CYAN}Also update DECIMALS.BTC from 18 to 8 in constants.ts${NC}"
echo ""
echo -e "${CYAN}Explorer links:${NC}"
echo "  https://sepolia.starkscan.co/contract/$VAULT_ADDRESS"
echo "  https://sepolia.starkscan.co/contract/$WRAPPER_ADDRESS"
echo "  https://sepolia.starkscan.co/contract/$VPOOL_ADDRESS"
echo ""
echo -e "${YELLOW}NOTE: VirtualPool needs funding! After deploy, call:${NC}"
echo -e "${YELLOW}  1. MockUSDC.faucet(amount) to get USDC${NC}"
echo -e "${YELLOW}  2. MockUSDC.approve(VirtualPool, amount)${NC}"
echo -e "${YELLOW}  3. VirtualPool.fund(amount) to load reserves${NC}"
echo ""
