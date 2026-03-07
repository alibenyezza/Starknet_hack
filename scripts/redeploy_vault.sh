#!/bin/bash
# Redeploy VaultManager only — decimal fix (usdc_needed / 100)
# sed -i 's/\r$//' /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/redeploy_vault.sh
# bash /mnt/c/Users/byezz/Desktop/starknethackathon/lastupdate/Starknet_hack/scripts/redeploy_vault.sh

set -e

ACC="sepolia"
OWNER="0x2b34981d2405a91eb0683fd144707d6ba9b402c7df8f9d3aaa9e359ec628653"

# Existing contracts (unchanged)
WBTC="0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b"
USDC="0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306"
LT="0x035ae494029fd2f4c3b27ed85c78b761c71d8a13e5f81f1180009bd41258b468"
EKUBO="0x06c9c6ce0219d849675c1399a996908ced01aa8ec6660b09ab10bb2276908c48"
LENDING="0x0014c719633c27561470a0b507c4b1458766c6fa4d2b70f979679339e9edb3c7"
VPOOL="0x034bbd3d99c00f36773e712bbb8cba7022ee97746326cffda0af1c2efcb1a3c3"

TMP=$(mktemp)

echo "============================================"
echo "  Redeploy VaultManager (decimal fix)"
echo "============================================"
echo ""

# ── 1. Declare new VaultManager class ────────────────────────
echo "[1/3] Declaring VaultManager..."
sncast --account "$ACC" \
    declare --network sepolia \
    --contract-name VaultManager \
    2>&1 | tee "$TMP"
CLASS=$(grep -oiP 'Class Hash:\s+\K0x[0-9a-fA-F]+' "$TMP" | head -1)
if [ -z "$CLASS" ]; then
    CLASS=$(grep -oiP '0x[0-9a-fA-F]{50,}' "$TMP" | head -1)
    echo "  (possibly already declared)"
fi
echo "  => CLASS: $CLASS"
sleep 15
echo ""

# ── 2. Deploy new VaultManager ───────────────────────────────
echo "[2/3] Deploying VaultManager..."
sncast --account "$ACC" \
    deploy --network sepolia \
    --class-hash "$CLASS" \
    --arguments "$WBTC, $USDC, $LT, $EKUBO, $LENDING, $VPOOL, 0x0, $OWNER" \
    2>&1 | tee "$TMP"
VAULT=$(grep -oiP 'Contract Address:\s+\K0x[0-9a-fA-F]+' "$TMP" | head -1)
echo "  => NEW VAULT: $VAULT"
sleep 15
echo ""

# ── 3. Transfer LtToken ownership to new VaultManager ────────
echo "[3/3] LtToken.transfer_ownership -> new VaultManager..."
sncast --account "$ACC" \
    invoke --network sepolia \
    --contract-address "$LT" \
    --function transfer_ownership \
    --arguments "$VAULT" \
    2>&1
echo "  Done."
echo ""

rm -f "$TMP"

echo "============================================"
echo "  REDEPLOY COMPLETE"
echo "============================================"
echo ""
echo "  New VaultManager: $VAULT"
echo "  (Update frontend/src/config/constants.ts)"
echo ""
