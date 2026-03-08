#!/bin/bash
# ============================================================
# StarkYield — Swap Fee Generator
#
# Generates LEVAMM trading fees to produce a non-zero APR.
# The APR formula is time-normalized (time-normalized):
#   r_pool = (totalFeesAllTime / collateral) × (BLOCKS_PER_YEAR / blocksSinceInit)
#
# More swaps = higher APR. More time without swaps = APR decays.
# collect_fees() does NOT affect the APR (total_fees_generated never resets).
#
# Usage:
#   sed -i 's/\r$//' scripts/generate_swap_fees.sh
#   bash scripts/generate_swap_fees.sh
#   ROUNDS=20 bash scripts/generate_swap_fees.sh
#   LEVAMM=0x... bash scripts/generate_swap_fees.sh
# ============================================================

set -e

LEVAMM="${LEVAMM:-0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af}"

# btc_amount = 36 × 1e18
# Each swap: base_usdc ≈ 24 USDC, fee ≈ 0.072 USDC (0.3%)
AMOUNT="36000000000000000000"

ROUNDS=${ROUNDS:-10}     # more rounds = higher APR (time-normalized)
DELAY=${DELAY:-8}        # seconds between txs (allow confirmation)

echo "============================================"
echo "  StarkYield — Swap Fee Generator"
echo "  LEVAMM:  $LEVAMM"
echo "  Amount:  36 units (≈24 USDC per swap)"
echo "  Rounds:  $ROUNDS (buy+sell each)"
echo "  Target:  ~${ROUNDS}% APR"
echo "============================================"
echo ""

SUCCESS=0
FAIL=0

for i in $(seq 1 $ROUNDS); do
  echo "=== Round $i/$ROUNDS ==="

  echo "  [BUY]  direction=1, btc_amount=36..."
  if sncast --account sepolia invoke \
    --contract-address $LEVAMM \
    --function swap \
    --arguments "1, $AMOUNT" 2>&1; then
    ((SUCCESS++))
  else
    echo "  ⚠ Buy failed"
    ((FAIL++))
  fi
  sleep $DELAY

  echo "  [SELL] direction=0, btc_amount=36..."
  if sncast --account sepolia invoke \
    --contract-address $LEVAMM \
    --function swap \
    --arguments "0, $AMOUNT" 2>&1; then
    ((SUCCESS++))
  else
    echo "  ⚠ Sell failed"
    ((FAIL++))
  fi
  sleep $DELAY

  echo "  Round $i done"
  echo ""
done

TOTAL=$((SUCCESS + FAIL))
EST_FEES=$(echo "scale=3; $SUCCESS * 0.072" | bc 2>/dev/null || echo "~$((SUCCESS * 72 / 1000))")
EST_APR=$(echo "scale=1; $SUCCESS * 0.072 / 10000 * 365 * 100 * 2 - 0.5" | bc 2>/dev/null || echo "~${ROUNDS}")

echo "============================================"
echo "  DONE"
echo "  Swaps: $SUCCESS/$TOTAL succeeded"
echo "  Estimated fees: ~${EST_FEES} USDC"
echo ""
echo "  APR is time-normalized (time-normalized)."
echo "  collect_fees() does NOT reset APR."
echo "  Run more rounds anytime to increase APR."
echo "============================================"
