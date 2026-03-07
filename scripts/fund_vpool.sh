#!/bin/bash
# Fund VirtualPool with 100,000 USDC
# sed -i 's/\r$//' /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/fund_vpool.sh
# bash /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/fund_vpool.sh

set -e

ACC="sepolia"
USDC="0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306"
VPOOL="0x034bbd3d99c00f36773e712bbb8cba7022ee97746326cffda0af1c2efcb1a3c3"

# 100,000 USDC = 100_000 * 10^6 = 100000000000
AMOUNT="100000000000"

NONCE=142

echo "=== Fund VirtualPool with 100,000 USDC ==="
echo ""

# Step 1: Faucet — mint 100k USDC to our wallet
echo "[1/3] MockUSDC.faucet(100000 USDC) — nonce=$NONCE"
sncast --account "$ACC" \
    invoke --network sepolia \
    --contract-address "$USDC" \
    --function faucet \
    --arguments "$AMOUNT" \
    --nonce "$NONCE" \
    2>&1
NONCE=$((NONCE + 1))
sleep 15
echo ""

# Step 2: Approve VirtualPool to spend our USDC
echo "[2/3] MockUSDC.approve(VirtualPool, 100000 USDC) — nonce=$NONCE"
sncast --account "$ACC" \
    invoke --network sepolia \
    --contract-address "$USDC" \
    --function approve \
    --arguments "$VPOOL, $AMOUNT" \
    --nonce "$NONCE" \
    2>&1
NONCE=$((NONCE + 1))
sleep 15
echo ""

# Step 3: Fund the VirtualPool
echo "[3/3] VirtualPool.fund(100000 USDC) — nonce=$NONCE"
sncast --account "$ACC" \
    invoke --network sepolia \
    --contract-address "$VPOOL" \
    --function fund \
    --arguments "$AMOUNT" \
    --nonce "$NONCE" \
    2>&1
echo ""

echo "=== Done! VirtualPool funded with 100,000 USDC ==="
