#!/bin/bash
# ============================================================
# StarkYield v12 — Deploy remaining 7 contracts
# Fix: explicit --nonce to avoid stale RPC nonce issue
#
# sed -i 's/\r$//' /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/deploy_only_v12.sh
# bash /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/deploy_only_v12.sh
# ============================================================

set -e

ACC="sepolia"
OWNER="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"
SY="0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e"

# Already deployed
WBTC="0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b"
USDC="0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306"

# Class hashes (all declared on-chain)
EKUBO_CLASS="0x018e29ea516009de68e441c574105413c08c3255343ff76b99f522f73ed4ec61"
LENDING_CLASS="0x019656f1a0446889690a603184af6ac200e6b2d54c30af976d760f1c54b9a858"
LT_CLASS="0x07c9a44437d4c419c95c161893f39054bd56054ddd189be944c155c63c516595"
VPOOL_CLASS="0x076d84bd3f021c6e66091d7ea4476b4bec6ce607a4ea6fca6defa3515fb4969c"
VAULT_CLASS="0x00c31ffdea69caa1adfb7810e5335524aa352bb03a9cfa399d2b15236a2dc583"
WRAPPER_CLASS="0x04e46473ae46d1004b77219ced6e1d94fd176636cbc9deae45316e68933c6780"
GAUGE_CLASS="0x02a8dedfdc7c7e641140f4ae571a99171f605ef29b8d2cf3bec38c2ae2361932"

TMP=$(mktemp)

# Nonce 0x86 = 134 (from last error: "Account nonce: 0x86")
NONCE=134

echo "============================================"
echo "  v12 Deploy — 7 remaining contracts"
echo "  WBTC: $WBTC"
echo "  USDC: $USDC"
echo "  Starting nonce: $NONCE"
echo "============================================"
echo ""

# ── 3. MockEkuboAdapter ──────────────────────────────────────
echo "[3/9] Deploying MockEkuboAdapter (nonce=$NONCE)..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$EKUBO_CLASS" \
    --arguments "$WBTC, $USDC, $OWNER" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP"
EKUBO=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => EKUBO: $EKUBO"
NONCE=$((NONCE + 1))
sleep 15
echo ""

# ── 4. MockLendingAdapter ─────────────────────────────────────
echo "[4/9] Deploying MockLendingAdapter (nonce=$NONCE)..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$LENDING_CLASS" \
    --arguments "$WBTC, $USDC, $EKUBO, $OWNER" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP"
LENDING=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => LENDING: $LENDING"
NONCE=$((NONCE + 1))
sleep 15
echo ""

# ── 5. LtToken ────────────────────────────────────────────────
echo "[5/9] Deploying LtToken (nonce=$NONCE)..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$LT_CLASS" \
    --arguments "\"StarkYield LT\", \"LT\", $OWNER" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP"
LT=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => LT: $LT"
NONCE=$((NONCE + 1))
sleep 15
echo ""

# ── 6. VirtualPool ────────────────────────────────────────────
echo "[6/9] Deploying VirtualPool (nonce=$NONCE)..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$VPOOL_CLASS" \
    --arguments "$OWNER, $USDC" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP"
VPOOL=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => VPOOL: $VPOOL"
NONCE=$((NONCE + 1))
sleep 15
echo ""

# ── 7. VaultManager ───────────────────────────────────────────
echo "[7/9] Deploying VaultManager (nonce=$NONCE)..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC, $USDC, $LT, $EKUBO, $LENDING, $VPOOL, 0x0, $OWNER" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP"
VAULT=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => VAULT: $VAULT"
NONCE=$((NONCE + 1))
sleep 15
echo ""

# ── 8. EkuboLPWrapper ─────────────────────────────────────────
echo "[8/9] Deploying EkuboLPWrapper (nonce=$NONCE)..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$WRAPPER_CLASS" \
    --arguments "$OWNER, $WBTC, $USDC, $EKUBO" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP"
WRAPPER=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => WRAPPER: $WRAPPER"
NONCE=$((NONCE + 1))
sleep 15
echo ""

# ── 9. GaugeController ────────────────────────────────────────
echo "[9/9] Deploying GaugeController (nonce=$NONCE)..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$GAUGE_CLASS" \
    --arguments "$OWNER, $SY" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP"
GAUGE=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP")
echo "  => GAUGE: $GAUGE"
NONCE=$((NONCE + 1))
sleep 15
echo ""

# ── Wire-up: LtToken ownership → VaultManager ────────────────
echo "[Wire] LtToken.transfer_ownership -> VaultManager (nonce=$NONCE)..."
sncast --account "$ACC" \
    invoke --network sepolia \
    --contract-address "$LT" \
    --function transfer_ownership \
    --arguments "$VAULT" \
    --nonce "$NONCE" \
    2>&1 | tee "$TMP" || true
echo "  Done."
echo ""

rm -f "$TMP"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  v12 DEPLOY COMPLETE"
echo "============================================"
echo ""
echo "  MockWBTC (8 dec):     $WBTC"
echo "  MockUSDC (6 dec):     $USDC"
echo "  MockEkuboAdapter:     $EKUBO"
echo "  MockLendingAdapter:   $LENDING"
echo "  LtToken:              $LT"
echo "  VirtualPool:          $VPOOL"
echo "  VaultManager:         $VAULT"
echo "  EkuboLPWrapper:       $WRAPPER"
echo "  GaugeController:      $GAUGE"
echo ""
