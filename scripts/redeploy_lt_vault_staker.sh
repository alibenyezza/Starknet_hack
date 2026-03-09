#!/bin/bash
# Redeploy LT (with set_vault) + VaultManager + Staker
# sed -i 's/\r$//' scripts/redeploy_lt_vault_staker.sh
# bash scripts/redeploy_lt_vault_staker.sh

set -e

ACC="sepolia"
OWNER="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# Existing contracts (unchanged)
WBTC="0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b"
USDC="0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306"
EKUBO="0x013a15529211d5a2775bd698609b379ca1ff70ffa65b8d5f81485b9837c0ee12"
LENDING="0x001b376346f9b24aca87c85c3a2780bea4941727fbc2a9e821b423d38cc4eb79"
VPOOL="0x0190f9b1eeef43f98b96bc0d4c8dc0b9b2c008013975b1b1061d8564a1cc4753"
RISK="0x0481a49142bec3d6c68c77ec5ab1002c5f438aa55766c3efebbd741d35f25a25"
FEE_DIST="0x0360f009cf2e29fb8a30e133cc7c32783409d341286560114ccff9e3c7fc7362"
LEVAMM="0x007b1a0774303f1a9f5ead5ced7d67bf2ced3ecab52b9095501349b753b67a88"
SY_TOKEN="0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e"

# Existing class hashes (reuse for VaultManager and Staker)
VAULT_CLASS="0x514d8c62a8ea552e33bb44f9a3d1882100fb8a598e4c2af71905f0cde6a2949"
STAKER_CLASS="0x5726afb9a9a0849064f14786fdf7f47bb1d8ace93dfbb740b8d502c3107b952"

TMP=$(mktemp)

echo "============================================"
echo "  Redeploy LT + VaultManager + Staker"
echo "============================================"
echo ""

# ── 1. Declare new LT class ──────────────────────────────────
echo "[1/8] Declaring LtToken..."
sncast --account "$ACC" declare --network sepolia \
    --contract-name LtToken \
    2>&1 | tee "$TMP"
LT_CLASS=$(grep -oiP 'Class Hash:\s+\K0x[0-9a-fA-F]+' "$TMP" | head -1)
if [ -z "$LT_CLASS" ]; then
    LT_CLASS=$(grep -oiP '0x[0-9a-fA-F]{50,}' "$TMP" | head -1)
    echo "  (possibly already declared)"
fi
echo "  => LT_CLASS: $LT_CLASS"
sleep 15
echo ""

# ── 2. Deploy new LT ─────────────────────────────────────────
echo "[2/8] Deploying LtToken..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$LT_CLASS" \
    --arguments "\"StarkYield LT\", \"LT\", $OWNER" \
    2>&1 | tee "$TMP"
LT=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP" | head -1)
echo "  => LT: $LT"
sleep 15
echo ""

# ── 3. Deploy new VaultManager with new LT ────────────────────
echo "[3/8] Deploying VaultManager..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$VAULT_CLASS" \
    --arguments "$WBTC, $USDC, $LT, $EKUBO, $LENDING, $VPOOL, $RISK, $OWNER" \
    2>&1 | tee "$TMP"
VAULT=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP" | head -1)
echo "  => VAULT: $VAULT"
sleep 15
echo ""

# ── 4. LT.set_vault(VaultManager) ────────────────────────────
echo "[4/8] LT.set_vault -> VaultManager..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$LT" --function set_vault \
    --arguments "$VAULT" 2>&1 | tee "$TMP" || true
sleep 10

# ── 5. VaultManager.set_fee_distributor ───────────────────────
echo "[5/8] VaultManager.set_fee_distributor..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$VAULT" --function set_fee_distributor \
    --arguments "$FEE_DIST" 2>&1 | tee "$TMP" || true
sleep 10

# ── 6. VaultManager.set_levamm ───────────────────────────────
echo "[6/8] VaultManager.set_levamm..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$VAULT" --function set_levamm \
    --arguments "$LEVAMM" 2>&1 | tee "$TMP" || true
sleep 10

# ── 7. Deploy new Staker with new LT ─────────────────────────
echo "[7/8] Deploying Staker..."
sncast --account "$ACC" deploy --network sepolia \
    --class-hash "$STAKER_CLASS" \
    --arguments "$OWNER, $LT, $SY_TOKEN, 100000000000" \
    2>&1 | tee "$TMP"
STAKER=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP" | head -1)
echo "  => STAKER: $STAKER"
sleep 15

# ── 8. FeeDistributor.set_staker ─────────────────────────────
echo "[8/8] FeeDistributor.set_staker..."
sncast --account "$ACC" invoke --network sepolia \
    --contract-address "$FEE_DIST" --function set_staker \
    --arguments "$STAKER" 2>&1 | tee "$TMP" || true
sleep 10

rm -f "$TMP"

echo ""
echo "============================================"
echo "  REDEPLOY COMPLETE"
echo "============================================"
echo ""
echo "  LT_TOKEN:      '$LT',"
echo "  VAULT_MANAGER:  '$VAULT',"
echo "  STAKER:         '$STAKER',"
echo ""
echo "  (All other contracts unchanged)"
echo "  Update frontend/src/config/constants.ts with these 3 addresses."
echo ""
