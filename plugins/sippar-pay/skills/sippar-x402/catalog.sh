#!/usr/bin/env bash
# Browse the LIVE Sippar marketplace as CAPABILITIES a vibe coder can drop into an app.
# Public, no token, no payment.
#
#   ./catalog.sh            # capabilities overview — "what can my agent do?"
#   ./catalog.sh search     # every service in a capability, with a one-line description
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"
URL="${SIPPAR_CATALOG_URL:-https://sippar.network/api/sippar/marketplace}"

CATALOG_JSON="$(curl -sS --max-time 30 "$URL")" FILTER="$FILTER" DESC_FILE="$HERE/descriptions.json" python3 <<'PY'
import os, json
from collections import defaultdict
d = json.loads(os.environ["CATALOG_JSON"])
svcs = d.get("data", d).get("services") or []
flt = os.environ.get("FILTER", "").strip().lower()
try:
    DESC = json.load(open(os.environ["DESC_FILE"]))
except Exception:
    DESC = {}

CAP = {
    "ai":       ("Generate & transform text",   "summarize, translate, moderate, extract, classify"),
    "search":   ("Search the web & research",    "answer questions with live web + research results"),
    "data":     ("Look up & enrich data",        "validate/clean records, enrich a person/company/IP"),
    "defi":     ("Crypto prices & on-chain data","token prices, wallet activity, trending tokens"),
    "trading":  ("Market data & quotes",         "stock/FX quotes, time series, prediction markets"),
    "image":    ("Generate & read images",       "make images, extract images/data from a page"),
    "security": ("Redact & screen",              "strip PII, sanctions/threat checks"),
    "news":     ("News & sentiment",             "latest headlines + market sentiment"),
    "infra":    ("Run code & tooling",           "execute code, sandboxes, dev utilities"),
    "web":      ("Scrape & extract from pages",  "pull metadata/structured data from any URL"),
    "other":    ("Misc",                          ""),
}
by = defaultdict(list)
for s in svcs:
    by[(s.get("category") or "other")].append(s)
def price(s): return s.get("priceUSD", 0)

if not flt:
    print(f"\n  Your agent can pay for {len(svcs)} services. What do you want to build?\n")
    for cat in sorted(by, key=lambda c: -len(by[c])):
        rows = sorted(by[cat], key=price)
        label, build = CAP.get(cat, (cat.title(), ""))
        print(f"  {label:28} {len(rows):>3} services   ${price(rows[0]):.3f}-${price(rows[-1]):.3f}")
        if build: print(f"  {'':28} -> {build}")
        print(f"  {'':28}    ./catalog.sh {cat}\n")
    print("  Each is one pay-per-call HTTP request. No API key, no subscription.\n")
else:
    rows = sorted(by.get(flt, []), key=price)
    label, build = CAP.get(flt, (flt.title(), ""))
    if not rows:
        print("\n  No capability \"%s\". Try: %s\n" % (flt, ", ".join(sorted(by)))); raise SystemExit
    print(f"\n  {label} - {len(rows)} services" + (f"  ({build})" if build else "") + "\n")
    for s in rows:
        info = DESC.get(s.get("id"), {})
        print("  $%-6s %-9s %s" % (price(s), s.get("chain",""), s.get("name","?")))
        desc = info.get("d") or s.get("usage")
        if desc:
            line = desc if len(desc) <= 92 else desc[:89] + "..."
            print("           %s" % line)
        ex = info.get("x")
        if ex: print("           e.g. \"%s\"" % ex)
        cmds = s.get("commands")
        if cmds and not info.get("d"): print("           try: %s" % ", ".join(cmds[:6]))
    print("\n  To buy one, ask the agent in plain English (e.g. \"search the web for X\").\n")
PY
