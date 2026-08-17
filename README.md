# sippar-pay

The agent payment skill that needs no private key.

Use it whenever an agent needs to pay for something over HTTP: an x402 or MPP (Machine Payments
Protocol) service, a "402 Payment Required" response, a per-call data or inference endpoint, or
another agent selling its output. It also buys Sippar's own products and lets your agent sell its
own work behind a real 402.

The wallet is keyless (Sippar-managed, with a scoped path to non-custody): no seed phrase, no
private key in your environment, and a server-enforced spend cap on every payment. The agent's
identity is an ICP principal; the wallet is derived from it by threshold signatures, so the chain
key is never assembled anywhere.

## Install

```
/plugin marketplace add Nuru-AI/sippar-pay
```

Then install the `sippar-pay` plugin. It triggers on any "pay this API" or 402 scenario.

## What you get

The plugin ships one skill, `sippar-x402`, plus four zero-config scripts that need only `bash`,
`curl` and `python3`:

| Script | What it does | Costs |
|---|---|---|
| `catalog.sh` | what your agent can pay for, as capabilities | nothing |
| `fund.sh` | your agent's wallet address and live balance | nothing |
| `pay.sh` | pay a service, print the response and a receipt with an explorer link | a real payment |
| `selftest.sh` | prove the whole path end to end | a real payment |

`references/ensure-identity.ts` generates an agent principal locally if you want one minted on your
own machine rather than server-side.

## Two doors, and only one needs a credential

- `https://sippar.network/mcp/tools/pay/*` is plain REST and needs **no API key**. Manifest,
  products, wallet lookup, buy, pay, serve and sessions all live there. Everything in the skill is
  written against this door.
- `https://sippar.network/mcp/protocol/pay` is MCP over JSON-RPC. `initialize`, `tools/list` and
  `ping` are open, but `tools/call` needs a Sippar-issued key. Eight tools live only there,
  including the pay.sh ones. Ask at elad@sippar.network if you need it.

The skill's section 1 explains which is which and why the credential-free `pay` route is Sippar's
treasury paying rather than a free tier.

## Version 2.0.0

`sippar-pay` and `paysphere` were folded into one skill, now named `sippar-x402`. pay.sh is a
source inside the single pay namespace rather than a separate product surface, and the old
`/mcp/tools/paysphere` endpoints have been removed. If you installed version 1, upgrade: it
referenced those endpoints and they return 404.

## Links

- Sippar: https://sippar.network
- Live tool manifest: https://sippar.network/mcp/tools/pay/manifest
- Live product catalog: https://sippar.network/api/sippar/sell/catalog
- x402: https://x402.org
- MPP: https://mpp.dev
- pay.sh: https://pay.sh
