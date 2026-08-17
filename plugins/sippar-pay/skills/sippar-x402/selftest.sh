#!/usr/bin/env bash
# End-to-end check: make ONE real payment and print the response + receipt (with tx link).
# Run before demoing live. No setup needed.
#
#   ./verify.sh                     # default: minifetch on Base (x402) -> clickable Basescan link
#   DEMO_SERVICE=ipinfo ./verify.sh # Locus ipinfo (MPP on Tempo) -> no on-chain explorer tx
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINCIPAL="${DEMO_PRINCIPAL:-2vxsx-fae}"

if [ "${DEMO_SERVICE:-base}" = "base" ]; then
  # minifetch url-metadata: x402 GET, settles USDC on Base -> real on-chain tx hash (Basescan link).
  TARGET="${TARGET_URL:-https://sippar.network/manifesto}"
  echo "-> paying (minifetch url-metadata, Base x402, cap \$0.04) ..."
  BODY=$(printf '{"principal":"%s","serviceUrl":"https://minifetch.com/api/v1/x402/extract/url-metadata?url=%s","method":"GET","payFromChain":"base","maxAmountUSD":0.04}' "$PRINCIPAL" "$TARGET")
else
  echo "-> paying (Locus ipinfo MPP, cap \$0.0015) ..."
  BODY=$(printf '{"principal":"%s","serviceUrl":"https://ipinfo.mpp.paywithlocus.com/ipinfo/ip-lite","payload":{"ip":"8.8.8.8"},"maxAmountUSD":0.0015,"preferTempo":true}' "$PRINCIPAL")
fi

"$HERE/pay.sh" "$BODY"
