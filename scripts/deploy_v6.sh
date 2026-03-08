#!/bin/bash
# ============================================================
# StarkYield v6 — Deploy: SyToken + Factory + LevAMM + Staker + VirtualPool
# Usage (depuis WSL):
#   cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
#   bash ../scripts/deploy_v6.sh
# ============================================================

set -e

# ── PATH (requis pour sncast/scarb depuis WSL) ───────────────
export HOME=/home/byezz
export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Adresses existantes (v5 — ne pas toucher) ────────────────
OWNER_ADDRESS="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"
WBTC_ADDRESS="0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163"
USDC_ADDRESS="0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb"
SYBTC_ADDRESS="0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3"
MOCK_PRAGMA_ADAPTER="0x069751dd1f1d78907f361a725af5d06937e5c25839fcffaf898fbd1e79fd49c2"
MOCK_LENDING_ADAPTER="0x0184b3fb971cd3ea627727c32e07b9a071bf4e68de42c61567f8d04ef80a474b"
MOCK_EKUBO_ADAPTER="0x05fd7268228036c8237674709b699a732e7c2ae3c7d20ef1306950f3626610f9"

SNCAST_ACCOUNT="sepolia"
WAIT_TIME=45
TMP=$(mktemp)

# u256 → deux felts: low high
# collateral=1000 USDC, debt=300 USDC (DTV=30%), btc_price=95000 USDC (6 décimales)
LEVAMM_COLLATERAL="1000000000 0"
LEVAMM_DEBT="300000000 0"
LEVAMM_BTC_PRICE="95000000000 0"
REWARD_RATE="1000000000000 0"   # 1e12 tokens/bloc
REBALANCE_COOLDOWN="10"

# ── Helper : extrait class_hash ou contract_address depuis $TMP ──
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

echo -e "${BLUE}=== StarkYield v6 Deployment ===${NC}"
echo ""

# ============================================================
# 1. SyToken
# ============================================================
echo -e "${GREEN}[1/5] Declaring SyToken...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name SyToken \
    2>&1 | tee "$TMP" || true
SY_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $SY_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[1/5] Deploying SyToken...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$SY_CLASS" \
    --arguments "\"StarkYield SY\", \"sy-WBTC\", $OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
SY_ADDRESS=$(get_address); echo -e "${GREEN}SyToken: $SY_ADDRESS${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 2. Factory
# ============================================================
echo -e "${GREEN}[2/5] Declaring Factory...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name Factory \
    2>&1 | tee "$TMP" || true
FACTORY_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $FACTORY_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[2/5] Deploying Factory...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$FACTORY_CLASS" \
    --arguments "$OWNER_ADDRESS" \
    2>&1 | tee "$TMP" || true
FACTORY_ADDRESS=$(get_address); echo -e "${GREEN}Factory: $FACTORY_ADDRESS${NC}"
sleep $WAIT_TIME
echo ""

# ============================================================
# 3. LevAMM
# constructor(owner, btc_token, usdc_token, pragma_adapter)
# ============================================================
echo -e "${GREEN}[3/5] Declaring LevAMM...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LevAMM \
    2>&1 | tee "$TMP" || true
LEVAMM_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $LEVAMM_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[3/5] Deploying LevAMM...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LEVAMM_CLASS" \
    --arguments "$OWNER_ADDRESS, $WBTC_ADDRESS, $USDC_ADDRESS, $MOCK_PRAGMA_ADAPTER" \
    2>&1 | tee "$TMP" || true
LEVAMM_ADDRESS=$(get_address); echo -e "${GREEN}LevAMM: $LEVAMM_ADDRESS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[3b] Initializing LevAMM (collateral=1000 USDC, debt=300 USDC, price=95000 USDC)...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$LEVAMM_ADDRESS" \
    --function initialize \
    --arguments "$LEVAMM_COLLATERAL, $LEVAMM_DEBT, $LEVAMM_BTC_PRICE" \
    2>&1 || true
sleep $WAIT_TIME
echo ""

# ============================================================
# 4. Staker
# constructor(owner, sy_btc_token, sy_token, initial_reward_rate u256)
# ============================================================
echo -e "${GREEN}[4/5] Declaring Staker...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name Staker \
    2>&1 | tee "$TMP" || true
STAKER_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $STAKER_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[4/5] Deploying Staker...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$STAKER_CLASS" \
    --arguments "$OWNER_ADDRESS, $SYBTC_ADDRESS, $SY_ADDRESS, $REWARD_RATE" \
    2>&1 | tee "$TMP" || true
STAKER_ADDRESS=$(get_address); echo -e "${GREEN}Staker: $STAKER_ADDRESS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[4b] SyToken → transfer_ownership → Staker...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$SY_ADDRESS" \
    --function transfer_ownership \
    --arguments "$STAKER_ADDRESS" \
    2>&1 || true
sleep $WAIT_TIME
echo ""

# ============================================================
# 5. VirtualPool
# constructor(owner, btc_token, usdc_token, lending_adapter, ekubo_adapter, levamm, cooldown u64)
# ============================================================
echo -e "${GREEN}[5/5] Declaring VirtualPool...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VirtualPool \
    2>&1 | tee "$TMP" || true
VPOOL_CLASS=$(get_class_hash); echo -e "${GREEN}class_hash: $VPOOL_CLASS${NC}"
sleep $WAIT_TIME

echo -e "${GREEN}[5/5] Deploying VirtualPool...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VPOOL_CLASS" \
    --arguments "$OWNER_ADDRESS, $WBTC_ADDRESS, $USDC_ADDRESS, $MOCK_LENDING_ADAPTER, $MOCK_EKUBO_ADAPTER, $LEVAMM_ADDRESS, $REBALANCE_COOLDOWN" \
    2>&1 | tee "$TMP" || true
VPOOL_ADDRESS=$(get_address); echo -e "${GREEN}VirtualPool: $VPOOL_ADDRESS${NC}"
sleep $WAIT_TIME
echo ""

rm -f "$TMP"

# ============================================================
# Résumé
# ============================================================
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}    DEPLOYMENT v6 COMPLETE!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "SyToken:   ${YELLOW}$SY_ADDRESS${NC}"
echo -e "Factory:     ${YELLOW}$FACTORY_ADDRESS${NC}"
echo -e "LevAMM:      ${YELLOW}$LEVAMM_ADDRESS${NC}"
echo -e "Staker:      ${YELLOW}$STAKER_ADDRESS${NC}"
echo -e "VirtualPool: ${YELLOW}$VPOOL_ADDRESS${NC}"
echo ""
echo -e "${BLUE}Copie dans frontend/src/config/constants.ts :${NC}"
echo "  FACTORY:      '$FACTORY_ADDRESS',"
echo "  LEVAMM:       '$LEVAMM_ADDRESS',"
echo "  VIRTUAL_POOL: '$VPOOL_ADDRESS',"
echo "  STAKER:       '$STAKER_ADDRESS',"
echo "  SY_TOKEN:  '$SY_ADDRESS',"
echo ""
echo "Explorer:"
echo "  https://sepolia.starkscan.co/contract/$LEVAMM_ADDRESS"
echo "  https://sepolia.starkscan.co/contract/$STAKER_ADDRESS"
echo "  https://sepolia.starkscan.co/contract/$VPOOL_ADDRESS"
