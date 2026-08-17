#!/usr/bin/env bash
# Sippar Pay demo wrapper. Zero config: no token, no .env, no wallet key.
# Prints the service response AND a receipt with a block-explorer link for the chain paid.
#
# Usage:
#   ./pay.sh '{"principal":"...","serviceUrl":"...","payload":{...},"maxAmountUSD":0.0015,"preferTempo":true}'
set -euo pipefail

BODY="${1:?Pass a JSON body, e.g. ./pay.sh '{\"principal\":\"...\",\"serviceUrl\":\"...\",\"maxAmountUSD\":0.0015}'}"
URL="${SIPPAR_PAY_URL:-https://sippar.network/mcp/tools/pay/pay}"

RESP="$(curl -sS --max-time 60 -X POST "$URL" -H "Content-Type: application/json" -d "$BODY")"

RESP="$RESP" python3 <<'PY'
import os, json, re
try:
    d = json.loads(os.environ["RESP"])
except Exception:
    print(os.environ["RESP"]); raise SystemExit
x = d.get("data", d)
print(json.dumps(d, indent=2))

# --- Receipt with block-explorer link ---
EXPLORER = {
    "base":     "https://basescan.org/tx/",
    "arbitrum": "https://arbiscan.io/tx/",
    "optimism": "https://optimistic.etherscan.io/tx/",
    "polygon":  "https://polygonscan.com/tx/",
    "bnb":      "https://bscscan.com/tx/",
    "ethereum": "https://etherscan.io/tx/",
    "solana":   "https://solscan.io/tx/",
    "stellar":  "https://stellar.expert/explorer/public/tx/",
    "ton":      "https://tonviewer.com/transaction/",
    "algorand": "https://allo.info/tx/",
}
chain = (x.get("chain") or "").lower()
tx    = x.get("paymentTx") or x.get("txHash") or ""
paid  = x.get("amountPaid")
ok    = x.get("paymentSucceeded")
svc   = x.get("serviceStatus")
bal   = x.get("agentBalanceUSD")

print("\n" + "-" * 56)
print("  RECEIPT")
if paid is not None: print(f"  Paid        : ${paid}  on {chain or '?'}")
if svc  is not None: print(f"  Service     : HTTP {svc}" + ("  (rendered)" if svc == 200 else "  (NOT rendered - do not re-pay)"))
if bal  is not None: print(f"  Balance now : ${bal}")

is_onchain_hash = bool(re.fullmatch(r"0x[0-9a-fA-F]{64}", tx)) or (chain == "solana" and 40 <= len(tx) <= 100 and not tx.startswith("0x"))
if chain in EXPLORER and is_onchain_hash:
    print(f"  Transaction : {EXPLORER[chain]}{tx}")
elif chain == "tempo" or (tx.startswith("0x") and len(tx) > 100):
    # MPP settlement presents a signed authorization to the service; it is not a
    # broadcast on-chain transaction, so there is no public explorer page for it.
    print(f"  Transaction : settled via MPP on {chain or 'tempo'} (signed authorization, no on-chain explorer tx)")
elif tx:
    print(f"  Transaction : {tx}")
print("-" * 56)
PY
