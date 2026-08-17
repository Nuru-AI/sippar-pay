#!/usr/bin/env bash
# Show the agent's keyless wallet: its derived address and live balance, and how to top it up.
# The agent NEVER needs a wallet key to pay — this address only matters if you want to ADD funds.
# You can fund it from any wallet you already have (send the named token on the named chain).
#
#   ./fund.sh                       # default demo principal
#   ./fund.sh <ICP_PRINCIPAL>       # a specific agent identity
set -euo pipefail
PRINCIPAL="${1:-${DEMO_PRINCIPAL:-2vxsx-fae}}"
URL="${SIPPAR_WALLET_URL:-https://sippar.network/mcp/tools/pay/wallet}"

curl -sS --max-time 30 "$URL/$PRINCIPAL" | python3 -c '
import sys, json
d = json.load(sys.stdin)
x = d.get("data", d)
if not x.get("address"):
    print("  could not read wallet:", json.dumps(d)[:200]); sys.exit(1)
print(f"""
  Agent identity : {x.get("principal","?")}
  Wallet address : {x.get("address")}
  Live balance   : ${x.get("balanceUSD",0):.4f}
  Fund it with   : send the funding token on {x.get("chain","?")} to the address above
  Fund token     : {x.get("fundToken","(see marketplace)")}

  No key, no seed phrase. The agent pays from this wallet under a per-call cap.
  Topping up is optional and can come from any wallet you already have.
""")
'
