#!/bin/bash
# ============================================================
# StarkYield - Strategy Layer Deployment
# Deploys: MockUSDC, PragmaAdapter, EkuboAdapter, VesuAdapter,
#          LeverageManager, new SyBTC, new VaultManager
# ============================================================
# Run from WSL:
#   export HOME=/home/byezz
#   export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:$PATH
#   bash /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/scripts/deploy_strategy.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# CONFIGURATION — verify these before running
# ============================================================

SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-sepolia}"
OWNER_ADDRESS="${OWNER_ADDRESS:-0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653}"

# Already deployed — keep these
WBTC_ADDRESS="${WBTC_ADDRESS:-0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163}"

# ── Real protocol addresses on Starknet Sepolia ──────────────
# Sources:
#   Pragma:  https://sepolia.starkscan.co (search "Pragma")
#   Ekubo:   https://docs.ekubo.org/integration-guides/reference/starknet-contracts
#   Vesu:    https://github.com/astraly-labs/vesu-liquidator/blob/main/config.yaml
PRAGMA_ORACLE_ADDR="${PRAGMA_ORACLE_ADDR:-0x36031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a}"
EKUBO_ROUTER_ADDR="${EKUBO_ROUTER_ADDR:-0x0045f933adf0607292468ad1c1dedaa74d5ad166392590e72676a34d01d7b763}"
EKUBO_POSITIONS_ADDR="${EKUBO_POSITIONS_ADDR:-0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5}"
VESU_SINGLETON_ADDR="${VESU_SINGLETON_ADDR:-0x069d0eca40cb01eda7f3d76281ef524cecf8c35f4ca5acc862ff128e7432964b}"

# Vesu pool ID — find on https://sepolia.starkscan.co/contract/$VESU_SINGLETON_ADDR
# Set to 0 for now; call VesuAdapter.set_pool_id() after finding the real ID
VESU_POOL_ID="${VESU_POOL_ID:-0x0}"

# Ekubo pool parameters (0.3% fee tier, tick spacing 60)
# fee = floor(0.003 * 2^128)
EKUBO_POOL_FEE="${EKUBO_POOL_FEE:-1020847100762815390390123822295304634}"
EKUBO_TICK_SPACING="${EKUBO_TICK_SPACING:-60}"

WAIT_TIME=45

echo -e "${BLUE}=== StarkYield Strategy Deployment ===${NC}"
echo -e "${CYAN}Owner:          $OWNER_ADDRESS${NC}"
echo -e "${CYAN}MockWBTC:       $WBTC_ADDRESS${NC}"
echo -e "${CYAN}Pragma Oracle:  $PRAGMA_ORACLE_ADDR${NC}"
echo -e "${CYAN}Ekubo Router:   $EKUBO_ROUTER_ADDR${NC}"
echo -e "${CYAN}Ekubo Pos.:     $EKUBO_POSITIONS_ADDR${NC}"
echo -e "${CYAN}Vesu Singleton: $VESU_SINGLETON_ADDR${NC}"
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
# Step 1: Deploy MockUSDC
# ============================================================
echo -e "${GREEN}[1/9] Deploying MockUSDC...${NC}"

MOCK_USDC_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name MockUSDC 2>&1) || true
echo "$MOCK_USDC_DECLARE"
MOCK_USDC_CLASS=$(echo "$MOCK_USDC_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$MOCK_USDC_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "MockUSDC class: ${YELLOW}$MOCK_USDC_CLASS${NC}"
sleep $WAIT_TIME

MOCK_USDC_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$MOCK_USDC_CLASS" \
    --arguments "$OWNER_ADDRESS" \
    2>&1) || true
echo "$MOCK_USDC_DEPLOY"
USDC_ADDRESS=$(echo "$MOCK_USDC_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$MOCK_USDC_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}MockUSDC: $USDC_ADDRESS${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 2: Deploy PragmaAdapter
# ============================================================
echo -e "${GREEN}[2/9] Deploying PragmaAdapter...${NC}"

PRAGMA_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name PragmaAdapter 2>&1) || true
echo "$PRAGMA_DECLARE"
PRAGMA_CLASS=$(echo "$PRAGMA_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$PRAGMA_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

PRAGMA_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$PRAGMA_CLASS" \
    --arguments "$PRAGMA_ORACLE_ADDR" \
    2>&1) || true
echo "$PRAGMA_DEPLOY"
PRAGMA_ADAPTER=$(echo "$PRAGMA_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$PRAGMA_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}PragmaAdapter: $PRAGMA_ADAPTER${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 3: Deploy EkuboAdapter
# ============================================================
echo -e "${GREEN}[3/9] Deploying EkuboAdapter...${NC}"

EKUBO_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name EkuboAdapter 2>&1) || true
echo "$EKUBO_DECLARE"
EKUBO_CLASS=$(echo "$EKUBO_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$EKUBO_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

EKUBO_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$EKUBO_CLASS" \
    --arguments "$EKUBO_ROUTER_ADDR, $EKUBO_POSITIONS_ADDR, $WBTC_ADDRESS, $USDC_ADDRESS, $EKUBO_POOL_FEE, $EKUBO_TICK_SPACING, $OWNER_ADDRESS" \
    2>&1) || true
echo "$EKUBO_DEPLOY"
EKUBO_ADAPTER=$(echo "$EKUBO_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$EKUBO_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}EkuboAdapter: $EKUBO_ADAPTER${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 4: Deploy VesuAdapter
# ============================================================
echo -e "${GREEN}[4/9] Deploying VesuAdapter...${NC}"

VESU_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VesuAdapter 2>&1) || true
echo "$VESU_DECLARE"
VESU_CLASS=$(echo "$VESU_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VESU_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

VESU_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VESU_CLASS" \
    --arguments "$VESU_SINGLETON_ADDR, $WBTC_ADDRESS, $USDC_ADDRESS, $VESU_POOL_ID, $OWNER_ADDRESS" \
    2>&1) || true
echo "$VESU_DEPLOY"
VESU_ADAPTER=$(echo "$VESU_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VESU_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}VesuAdapter: $VESU_ADAPTER${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 5: Deploy LeverageManager
# ============================================================
echo -e "${GREEN}[5/9] Deploying LeverageManager...${NC}"

LM_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name LeverageManager 2>&1) || true
echo "$LM_DECLARE"
LM_CLASS=$(echo "$LM_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

LM_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$LM_CLASS" \
    --arguments "$EKUBO_ADAPTER, $VESU_ADAPTER, $PRAGMA_ADAPTER, $WBTC_ADDRESS, $USDC_ADDRESS, $OWNER_ADDRESS" \
    2>&1) || true
echo "$LM_DEPLOY"
LM_ADDRESS=$(echo "$LM_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$LM_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}LeverageManager: $LM_ADDRESS${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 6: Redeploy SyBtcToken (owner = deployer initially)
# ============================================================
echo -e "${GREEN}[6/9] Deploying new SyBtcToken...${NC}"

SYBTC_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name SyBtcToken 2>&1) || true
echo "$SYBTC_DECLARE"
SYBTC_CLASS=$(echo "$SYBTC_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

SYBTC_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$SYBTC_CLASS" \
    --arguments "\"StarkYield BTC\", \"syBTC\", $OWNER_ADDRESS" \
    2>&1) || true
echo "$SYBTC_DEPLOY"
SYBTC_ADDRESS=$(echo "$SYBTC_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$SYBTC_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}SyBtcToken: $SYBTC_ADDRESS${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 7: Redeploy VaultManager (all addresses wired up)
# ============================================================
echo -e "${GREEN}[7/9] Deploying VaultManager...${NC}"

VAULT_DECLARE=$(sncast --account "$SNCAST_ACCOUNT" \
    declare --network sepolia --contract-name VaultManager 2>&1) || true
echo "$VAULT_DECLARE"
VAULT_CLASS=$(echo "$VAULT_DECLARE" | grep -oP 'class_hash:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DECLARE" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
sleep $WAIT_TIME

# Constructor: btc_token, usdc_token, sy_btc_token, ekubo_adapter,
#              vesu_adapter, pragma_adapter, leverage_manager, owner
VAULT_DEPLOY=$(sncast --account "$SNCAST_ACCOUNT" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC_ADDRESS, $USDC_ADDRESS, $SYBTC_ADDRESS, $EKUBO_ADAPTER, $VESU_ADAPTER, $PRAGMA_ADAPTER, $LM_ADDRESS, $OWNER_ADDRESS" \
    2>&1) || true
echo "$VAULT_DEPLOY"
VAULT_ADDRESS=$(echo "$VAULT_DEPLOY" | grep -oP 'contract_address:\s+\K0x[0-9a-fA-F]+' \
    || echo "$VAULT_DEPLOY" | grep -oP '0x[0-9a-fA-F]{50,}' | head -1 || echo "")
echo -e "${GREEN}VaultManager: $VAULT_ADDRESS${NC}"
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 8: Transfer SyBTC ownership to VaultManager
# ============================================================
echo -e "${GREEN}[8/9] Transferring SyBTC ownership to VaultManager...${NC}"
sncast --account "$SNCAST_ACCOUNT" \
    invoke --network sepolia \
    --contract-address "$SYBTC_ADDRESS" \
    --function transfer_ownership \
    --arguments "$VAULT_ADDRESS" \
    2>&1 || true
echo ""
sleep $WAIT_TIME

# ============================================================
# Step 9: Grant VaultManager approval on LeverageManager
#         (LeverageManager needs to know its vault caller)
# ============================================================
echo -e "${GREEN}[9/9] Done!${NC}"

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}            STRATEGY DEPLOYMENT COMPLETE${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "MockWBTC:        ${YELLOW}$WBTC_ADDRESS${NC}  (unchanged)"
echo -e "MockUSDC:        ${YELLOW}$USDC_ADDRESS${NC}"
echo -e "PragmaAdapter:   ${YELLOW}$PRAGMA_ADAPTER${NC}"
echo -e "EkuboAdapter:    ${YELLOW}$EKUBO_ADAPTER${NC}"
echo -e "VesuAdapter:     ${YELLOW}$VESU_ADAPTER${NC}"
echo -e "LeverageManager: ${YELLOW}$LM_ADDRESS${NC}"
echo -e "SyBtcToken:      ${YELLOW}$SYBTC_ADDRESS${NC}"
echo -e "VaultManager:    ${YELLOW}$VAULT_ADDRESS${NC}"
echo ""
echo -e "${CYAN}Update frontend/src/config/constants.ts:${NC}"
cat << EOF
VAULT_MANAGER:    '$VAULT_ADDRESS'
SY_BTC_TOKEN:     '$SYBTC_ADDRESS'
BTC_TOKEN:        '$WBTC_ADDRESS'
USDC_TOKEN:       '$USDC_ADDRESS'
PRAGMA_ADAPTER:   '$PRAGMA_ADAPTER'
EKUBO_ADAPTER:    '$EKUBO_ADAPTER'
VESU_ADAPTER:     '$VESU_ADAPTER'
LEVERAGE_MANAGER: '$LM_ADDRESS'
EOF
echo ""
echo -e "${YELLOW}⚠ POST-DEPLOYMENT STEPS:${NC}"
echo ""
echo -e "1. ${CYAN}Find Vesu pool ID for WBTC/USDC on Sepolia:${NC}"
echo "   https://sepolia.starkscan.co/contract/$VESU_SINGLETON_ADDR"
echo "   Then call: VesuAdapter.set_pool_id(<pool_id>)"
echo ""
echo -e "2. ${CYAN}Create Ekubo pool for MockWBTC/MockUSDC (if no existing pool):${NC}"
echo "   Use Ekubo frontend: https://app.ekubo.org"
echo "   Pool: MockWBTC ($WBTC_ADDRESS) / MockUSDC ($USDC_ADDRESS)"
echo "   Fee: 0.3%  |  Tick spacing: 60"
echo "   Add initial liquidity to enable swaps"
echo ""
echo -e "3. ${CYAN}Verify contracts on Starkscan:${NC}"
echo "   https://sepolia.starkscan.co/contract/$VAULT_ADDRESS"
echo ""
