---
name: sippar-pay
description: The agent payment skill that needs no private key. Use it whenever an agent needs to pay for something over HTTP: an x402 or MPP (Machine Payments Protocol) service, a "402 Payment Required" response, a per-call data or inference endpoint, a brokered premium AI upstream, or another agent selling its output. The agent's wallet is keyless (Sippar-managed, with a scoped path to non-custody): no seed phrase, no private key in .env, and a server-enforced spend cap on every payment. Trigger this skill for: pay this API, handle a 402, machine payments, agent commerce, micropayments, x402, MPP, pay.sh, pay per call, fund an agent wallet, sell agent output.
version: 1.0.0
author: Sippar
homepage: https://sippar.network
---

# sippar-pay

Pay for x402 and MPP services from an agent wallet with no private key to manage. Sippar derives a wallet per agent identity using ICP Chain Fusion threshold signatures: the chain key is never assembled anywhere, so there is nothing to leak from your repo, your CI, or your agent's environment. Custody model, stated plainly: the wallet is keyless (Sippar-managed, with a scoped path to non-custody), and every payment runs under a server-enforced spend cap plus the per-call ceiling you set yourself.

Two things this rail does that a plain x402 client does not:

1. **No `PRIVATE_KEY` in .env.** The usual x402 setup needs a funded EVM key sitting in the agent's environment. Here the agent's identity is an ICP principal; the wallet is derived from it, and signing happens through threshold cryptography on the ICP network.
2. **Premium upstreams beyond x402.** Sippar's catalog includes brokered services where Sippar fronts upstreams that do not accept x402 at all (premium AI model and media APIs). The same `pay` call reaches both tiers.

## Quickstart: pay a service in one call

The tool surface below is public HTTP, no token needed, rate-limited. The manifest is the source of truth for request shapes and current server caps; fetch it first:

```bash
curl https://sippar.network/mcp/tools/pay/manifest
```

Pay any x402/MPP service (or another agent's priced output) from the wallet tied to your principal:

```bash
curl -X POST https://sippar.network/mcp/tools/pay/pay \
  -H "Content-Type: application/json" \
  -d '{
    "principal": "<your-agent-principal>",
    "serviceUrl": "<the-402-protected-url>",
    "maxAmountUSD": 0.05
  }'
```

Sippar detects the 402 or MPP challenge, signs, settles, and returns the service response with a payment receipt. `maxAmountUSD` is your hard per-call ceiling; the server enforces its own per-payment cap on top (current value in the manifest).

For a brokered service, swap `serviceUrl` for `brokeredId`. Brokered chat services take a `prompt` directly:

```bash
curl -X POST https://sippar.network/mcp/tools/pay/pay \
  -H "Content-Type: application/json" \
  -d '{
    "principal": "<your-agent-principal>",
    "brokeredId": "ai-premium",
    "prompt": "Summarize the x402 protocol in three sentences.",
    "maxAmountUSD": 0.10
  }'
```

Browse what is payable, with prices and tier badges, at https://sippar.network/marketplace.

## Get an agent identity and wallet

The identity is an ICP principal. Generate one locally; no signup, no website:

```typescript
import { Ed25519KeyIdentity } from "@dfinity/identity";

const identity = Ed25519KeyIdentity.generate();
console.log(identity.getPrincipal().toText());
// Persist the identity JSON only if you need the same principal later.
```

Look up the wallet derived from that principal, then fund the address it returns (the response names the chain and token to send):

```bash
curl https://sippar.network/mcp/tools/pay/wallet/<your-agent-principal>
# -> { "address": "0x...", "balanceUSD": 0.05, "fundToken": "0x...", "chain": "tempo" }
```

The agent's on-chain balance is its actual budget: payments come from its own derived wallet, and pay responses report the remaining balance so the agent always knows what it can still spend.

## Sell your agent's output

The same surface works on the sell side. List any JSON output behind a 402 payable to your own wallet; a peer pays it with the `pay` call above:

```bash
curl -X POST https://sippar.network/mcp/tools/pay/serve \
  -H "Content-Type: application/json" \
  -d '{
    "producerPrincipal": "<your-agent-principal>",
    "output": { "answer": "..." },
    "priceUSD": 0.02
  }'
# -> { "outputUrl": "https://..." }
```

## Many small payments: sessions

Per-payment threshold signing has a real cost, so for high-frequency or sub-cent spending, open a budgeted session once and then draw many payments under it at near-zero signing cost per draw:

```bash
# Open (one signature; pass "principal" to fund from the agent's own wallet)
curl -X POST https://sippar.network/mcp/tools/pay/session/open \
  -H "Content-Type: application/json" \
  -d '{ "budgetUSD": 0.5, "expirySecs": 3600, "principal": "<your-agent-principal>" }'

# Draw (repeat as needed; zero threshold signatures per draw)
curl -X POST https://sippar.network/mcp/tools/pay/session/<id>/draw \
  -H "Content-Type: application/json" \
  -d '{ "toAddress": "0x<recipient>", "amountUSD": 0.01 }'

# Status / close
curl https://sippar.network/mcp/tools/pay/session/<id>
curl -X DELETE https://sippar.network/mcp/tools/pay/session/<id>
```

The session budget and expiry are enforced on-chain; per-draw and per-session caps are server-enforced, with current values in the manifest.

## Pay pay.sh services from other chains (PaySphere)

pay.sh is the Solana Foundation's machine-payment marketplace, and its services settle on Solana. Sippar's PaySphere relay lets an agent holding stablecoins on another chain (Base, Arbitrum, Optimism, Polygon, BNB Chain, Ethereum, Solana, Stellar) pay those services without bridging: the agent pays on its home chain, Sippar settles the Solana leg, and the agent gets the response with receipts for both legs.

PaySphere is in private beta. The tools (`discover`, `quote`, `pay-direct`, `pay-with-identity`) live at `https://sippar.network/mcp/tools/paysphere/` and need an unlock token; request one at contact@nuru.ai with a line about your use case.

## Spend safety

- `maxAmountUSD` on every call is a hard ceiling you control.
- The server enforces its own per-payment spend cap and rate limits on top.
- The derived wallet's balance is a physical cap: an agent cannot spend what it does not hold.
- **Paid is not rendered.** A payment can settle on-chain while the service still fails to serve. Treat a call as successful only when the service returned a 200 with a real response body. A success flag on the payment plus a 402 or empty body from the service means you paid and got nothing: stop and investigate before paying again.

## Errors

| Error | Meaning | What to do |
|---|---|---|
| Validation error | Request shape mismatch | Re-check against the manifest |
| Insufficient balance | Derived wallet underfunded | Fund the address from the wallet lookup |
| Rate limited | Public-surface rate limit hit | Back off and retry |
| Session not found on draw | Session expired or was reset server-side | Open a new session; the on-chain budget expires on its own |
| Payment succeeded, service returned 402 | Facilitator or upstream fault | Do not re-pay; report it |

## Access levels

- **Public, no token**: everything under `https://sippar.network/mcp/tools/pay/` (manifest, wallet lookup, pay, serve, sessions), rate-limited.
- **Token-gated**: the PaySphere relay tools and the direct backend API for approved integrators (higher limits, batch settlement, cross-chain relay). Request access at contact@nuru.ai.

## Links

- Site and catalog: https://sippar.network and https://sippar.network/marketplace
- Tool manifest: https://sippar.network/mcp/tools/pay/manifest
- x402 protocol: https://x402.org
- MPP: https://mpp.dev
