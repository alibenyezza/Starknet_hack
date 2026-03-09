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
SY_TOKEN="0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e"

# ── Existing v12 tokens (not redeployed) ─────────────────────
WBTC="0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b"
USDC="0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306"

# ── Class hashes (update after `scarb build && sncast declare`) ──
EKUBO_CLASS="0x2d7d5edae063d465d2ee3e7214762f1984e8ea08161bf2b57065f135699a1f6"
LENDING_CLASS="0x5573c7ed3b8544aa307250a20f24acf09a5b1883eb807ae4a963087cec77a41"
LT_CLASS="0x456a0d7fc5cbd4ba70a619e50b9b0e19f62711c08e01c43532ee73a56699ee8"
VPOOL_CLASS="0x076d84bd3f021c6e66091d7ea4476b4bec6ce607a4ea6fca6defa3515fb4969c"
VAULT_CLASS="0x514d8c62a8ea552e33bb44f9a3d1882100fb8a598e4c2af71905f0cde6a2949"
WRAPPER_CLASS="0x04e46473ae46d1004b77219ced6e1d94fd176636cbc9deae45316e68933c6780"
GAUGE_CLASS="0x2bb7dcd4f63ff487f753edfe89458e93175a90a86abcc8fe2fb1c07b1c680fd"
FEE_DIST_CLASS="0x467fb860b6fafaea9309545126d40976d29961516327cbd215d0c92d02da6eb"
RISK_CLASS="0x2a08be346dbf2c89d60434964bf2359d9d87646156bc4ffc2a232ed3e72fbb6"
LEVAMM_CLASS="0x5980c914b0ad9c33de0d0af021ae1b08aa0b45a414ba0ff86d4225adf7e7bc6"
VOTING_ESCROW_CLASS="0x543e1e9568b5ff380ded59a161491232c4c70d1fafab396f5ea40558bc0d48a"
LIQUIDITY_GAUGE_CLASS="0x63226e9e816e497aef7c65b2b5f69fa649a41367870bcde0257aca3e27e6701"

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
    --arguments "$OWNER, $SY_TOKEN" \
    2>&1 | tee "$TMP"
GAUGE=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => GAUGE: $GAUGE"
sleep 15

# ── 10. VotingEscrow ──────────────────────────────────────────
echo "[10] Deploying VotingEscrow..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$VOTING_ESCROW_CLASS" \
    --arguments "$OWNER, $SY_TOKEN" \
    2>&1 | tee "$TMP"
VOTING_ESCROW=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => VOTING_ESCROW: $VOTING_ESCROW"
sleep 15

# ── 11. LiquidityGauge ────────────────────────────────────────
echo "[11] Deploying LiquidityGauge..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$LIQUIDITY_GAUGE_CLASS" \
    --arguments "$OWNER, $LT, $SY_TOKEN" \
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

echo "[Wire] Staker.set_sy_token..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$STAKER" --function set_sy_token \
    --arguments "$SY_TOKEN" 2>&1 | tee "$TMP" || true
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
echo "  SY_TOKEN: '$SY_TOKEN',"
echo ""
echo "Copy the addresses above into frontend/src/config/constants.ts"
