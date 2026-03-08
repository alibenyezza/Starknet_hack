#!/bin/bash
# ============================================================
# StarkYield — Consolidated Deploy Script
#
# Deploys ALL contracts in correct order with dependency wiring.
# Edit the CLASS HASHES and EXISTING ADDRESSES sections below.
#
# Usage:
#   sed -i 's/\r$//' scripts/deploy_all.sh
#   bash scripts/deploy_all.sh
# ============================================================

set -e

# ── Configuration ────────────────────────────────────────────
ACC="sepolia"
OWNER="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# ── Existing v6 contracts (not redeployed) ───────────────────
# LEVAMM is now redeployed (new storage: total_fees_generated, init_block for time-normalized APR)
STAKER="0x04620f57ef40e7e2293ca6d06153930697bcb88d173f1634ba5cff768acec273"
SY_YB_TOKEN="0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e"

# ── Existing v12 tokens (not redeployed) ─────────────────────
WBTC="0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b"
USDC="0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306"

# ── Class hashes (update after `scarb build && sncast declare`) ──
EKUBO_CLASS="REPLACE_ME"
LENDING_CLASS="REPLACE_ME"
LT_CLASS="REPLACE_ME"
VPOOL_CLASS="REPLACE_ME"
VAULT_CLASS="REPLACE_ME"
WRAPPER_CLASS="REPLACE_ME"
GAUGE_CLASS="REPLACE_ME"
FEE_DIST_CLASS="REPLACE_ME"
RISK_CLASS="REPLACE_ME"
LEVAMM_CLASS="REPLACE_ME"
VOTING_ESCROW_CLASS="REPLACE_ME"
LIQUIDITY_GAUGE_CLASS="REPLACE_ME"

TMP=$(mktemp)

echo "============================================"
echo "  StarkYield — Full Deploy"
echo "  WBTC: $WBTC"
echo "  USDC: $USDC"
echo "============================================"
echo ""

# ── 1. MockEkuboAdapter ─────────────────────────────────────
echo "[1] Deploying MockEkuboAdapter..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$EKUBO_CLASS" \
    --arguments "$WBTC, $USDC, $OWNER" \
    2>&1 | tee "$TMP"
EKUBO=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => EKUBO: $EKUBO"
sleep 15

# ── 2. MockLendingAdapter ────────────────────────────────────
echo "[2] Deploying MockLendingAdapter..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$LENDING_CLASS" \
    --arguments "$WBTC, $USDC, $EKUBO, $OWNER" \
    2>&1 | tee "$TMP"
LENDING=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => LENDING: $LENDING"
sleep 15

# ── 3. LtToken ──────────────────────────────────────────────
echo "[3] Deploying LtToken..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$LT_CLASS" \
    --arguments "\"StarkYield LT\", \"LT\", $OWNER" \
    2>&1 | tee "$TMP"
LT=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => LT: $LT"
sleep 15

# ── 4. VirtualPool ──────────────────────────────────────────
echo "[4] Deploying VirtualPool..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$VPOOL_CLASS" \
    --arguments "$OWNER, $USDC" \
    2>&1 | tee "$TMP"
VPOOL=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => VPOOL: $VPOOL"
sleep 15

# ── 5. RiskManager ──────────────────────────────────────────
echo "[5] Deploying RiskManager..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$RISK_CLASS" \
    --arguments "$OWNER, 0" \
    2>&1 | tee "$TMP"
RISK=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => RISK: $RISK"
sleep 15

# ── 5b. LevAMM (redeployed — new storage for time-normalized APR) ──
echo "[5b] Deploying LevAMM..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$LEVAMM_CLASS" \
    --arguments "$OWNER, $WBTC, $USDC, 0x0" \
    2>&1 | tee "$TMP"
LEVAMM=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => LEVAMM: $LEVAMM"
sleep 15

# ── 6. VaultManager ─────────────────────────────────────────
echo "[6] Deploying VaultManager..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC, $USDC, $LT, $EKUBO, $LENDING, $VPOOL, $RISK, $OWNER" \
    2>&1 | tee "$TMP"
VAULT=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => VAULT: $VAULT"
sleep 15

# ── 7. FeeDistributor ───────────────────────────────────────
echo "[7] Deploying FeeDistributor..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$FEE_DIST_CLASS" \
    --arguments "$OWNER, $USDC" \
    2>&1 | tee "$TMP"
FEE_DIST=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => FEE_DIST: $FEE_DIST"
sleep 15

# ── 8. EkuboLPWrapper ───────────────────────────────────────
echo "[8] Deploying EkuboLPWrapper..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$WRAPPER_CLASS" \
    --arguments "$OWNER, $WBTC, $USDC, $EKUBO" \
    2>&1 | tee "$TMP"
WRAPPER=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => WRAPPER: $WRAPPER"
sleep 15

# ── 9. GaugeController ──────────────────────────────────────
echo "[9] Deploying GaugeController..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$GAUGE_CLASS" \
    --arguments "$OWNER, $SY_YB_TOKEN" \
    2>&1 | tee "$TMP"
GAUGE=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => GAUGE: $GAUGE"
sleep 15

# ── 10. VotingEscrow ──────────────────────────────────────────
echo "[10] Deploying VotingEscrow..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$VOTING_ESCROW_CLASS" \
    --arguments "$OWNER, $SY_YB_TOKEN" \
    2>&1 | tee "$TMP"
VOTING_ESCROW=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => VOTING_ESCROW: $VOTING_ESCROW"
sleep 15

# ── 11. LiquidityGauge ────────────────────────────────────────
echo "[11] Deploying LiquidityGauge..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$LIQUIDITY_GAUGE_CLASS" \
    --arguments "$OWNER, $LT, $SY_YB_TOKEN" \
    2>&1 | tee "$TMP"
LIQUIDITY_GAUGE=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => LIQUIDITY_GAUGE: $LIQUIDITY_GAUGE"
sleep 15

# ── Wire-up ─────────────────────────────────────────────────
echo ""
echo "=== Wiring contracts ==="

echo "[Wire] LtToken.transfer_ownership -> VaultManager..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LT" --function transfer_ownership \
    --arguments "$VAULT" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] VaultManager.set_fee_distributor..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$VAULT" --function set_fee_distributor \
    --arguments "$FEE_DIST" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] VaultManager.set_levamm..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$VAULT" --function set_levamm \
    --arguments "$LEVAMM" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] FeeDistributor.set_staker..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$FEE_DIST" --function set_staker \
    --arguments "$STAKER" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] FeeDistributor.set_lt_token..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$FEE_DIST" --function set_lt_token \
    --arguments "$LT" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] LEVAMM.set_fee_distributor..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LEVAMM" --function set_fee_distributor \
    --arguments "$FEE_DIST" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] LEVAMM.set_virtual_pool (rebalancing)..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LEVAMM" --function set_virtual_pool \
    --arguments "$VPOOL" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] LEVAMM.set_ekubo_adapter (rebalancing)..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LEVAMM" --function set_ekubo_adapter \
    --arguments "$EKUBO" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] LEVAMM.set_lending_adapter (rebalancing)..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LEVAMM" --function set_lending_adapter \
    --arguments "$LENDING" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] Staker.set_sy_yb_token..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$STAKER" --function set_sy_yb_token \
    --arguments "$SY_YB_TOKEN" 2>&1 | tee "$TMP" || true
sleep 10

echo "[Wire] LtToken.set_usdc_token..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LT" --function set_usdc_token \
    --arguments "$USDC" 2>&1 | tee "$TMP" || true
sleep 10

# ── Initialize LEVAMM ────────────────────────────────────────
echo ""
echo "=== Initializing LEVAMM ==="

echo "[Init] LEVAMM.initialize(collateral=10000, debt=5000, price=96000) all 1e18..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LEVAMM" --function initialize \
    --arguments "10000000000000000000000, 5000000000000000000000, 96000000000000000000000" \
    2>&1 | tee "$TMP" || true
sleep 10

echo "[Init] Generating swap fees for APR (10 rounds)..."
SWAP_AMOUNT="36000000000000000000"
for i in $(seq 1 10); do
  echo "  Swap round $i/10..."
  sncast --account "$ACC" invoke --network sepolia \
      --contract-address "$LEVAMM" --function swap \
      --arguments "1, $SWAP_AMOUNT" 2>/dev/null || true
  sleep 6
  sncast --account "$ACC" invoke --network sepolia \
      --contract-address "$LEVAMM" --function swap \
      --arguments "0, $SWAP_AMOUNT" 2>/dev/null || true
  sleep 6
done
echo "  Swap fee generation done."

rm -f "$TMP"

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  DEPLOY COMPLETE"
echo "============================================"
echo ""
echo "  // v12 contracts"
echo "  VAULT_MANAGER:        '$VAULT',"
echo "  LT_TOKEN:             '$LT',"
echo "  VIRTUAL_POOL:         '$VPOOL',"
echo "  MOCK_EKUBO_ADAPTER:   '$EKUBO',"
echo "  MOCK_LENDING_ADAPTER: '$LENDING',"
echo "  EKUBO_LP_WRAPPER:     '$WRAPPER',"
echo "  GAUGE_CONTROLLER:     '$GAUGE',"
echo "  FEE_DISTRIBUTOR:      '$FEE_DIST',"
echo "  RISK_MANAGER:         '$RISK',"
echo "  VOTING_ESCROW:        '$VOTING_ESCROW',"
echo "  LIQUIDITY_GAUGE:      '$LIQUIDITY_GAUGE',"
echo ""
echo "  // Tokens"
echo "  BTC_TOKEN: '$WBTC',"
echo "  USDC_TOKEN: '$USDC',"
echo "  LEVAMM:               '$LEVAMM',"
echo ""
echo "  // v6 contracts (unchanged)"
echo "  STAKER:      '$STAKER',"
echo "  SY_YB_TOKEN: '$SY_YB_TOKEN',"
echo ""
echo "Copy the addresses above into frontend/src/config/constants.ts"
