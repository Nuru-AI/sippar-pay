---
name: sippar-x402
description: The one Sippar payment skill. Use it whenever an agent needs to pay for something over HTTP, get paid for its own output, or buy one of Sippar's own products. Covers x402, MPP (Machine Payments Protocol), any "402 Payment Required" response, per-call data and inference endpoints, pay.sh services reached from a non-Solana chain, and agent-to-agent commerce. The agent's wallet is keyless (Sippar-managed, with a scoped path to non-custody): no seed phrase, no private key in .env, a server-enforced cap on every payment. Also the onboarding surface: when the user says "show me sippar", "how does sippar work", "onboard me", or invokes the skill with no payment target named, show the free catalog and wallet reads before spending any money. Trigger for: pay this API, handle a 402, machine payments, agent commerce, micropayments, x402, MPP, pay.sh, pay per call, fund an agent wallet, sell agent output, buy from Sippar, agent wallet address, payment session, batch payout, show me sippar, onboard me, demo the rail.
version: 3.0.0
author: Sippar
homepage: https://sippar.network
updated: 2026-08-17
---

# Sippar x402 / MPP

One skill for every payment an agent makes or receives through Sippar: paying an x402 or MPP
service, buying one of Sippar's own products, getting paid for your own output, and reaching pay.sh
from a chain it does not settle on.

Installed from the `sippar-pay` plugin. The skill was renamed `sippar-x402` when the older
`sippar-pay` and `paysphere` skills were folded into it, so if you have either of those vendored
anywhere, this replaces both. pay.sh is a source inside the one pay namespace now, not a separate
product surface, and the old `/mcp/tools/paysphere` endpoints no longer exist.

Sippar derives a wallet per agent identity using ICP Chain Fusion threshold signatures. The chain
key is never assembled anywhere, so there is nothing to leak from a repo, a CI job, or an agent's
environment. Custody, stated plainly: the wallet is Sippar-managed, with a scoped path to
non-custody. Every payment runs under a server-enforced cap plus whatever per-call ceiling you set.

**Chains**: Ethereum, Base, Arbitrum, Optimism, Polygon, BNB (t-ECDSA secp256k1,
`ethereum_signer` `4yiex-siaaa-aaaak-qxbwq-cai`) · Solana, Stellar, Algorand, TON (t-Schnorr
Ed25519, `threshold_signer` `vj7ly-diaaa-aaaae-abvoq-cai`) · Tempo for MPP, signed by
`ethereum_signer`.

---

## 0. First-time invocation: look before you spend

**When this skill is invoked without a specific pay-for-X request** (the user says "sippar-pay",
"show me sippar", "how does sippar work", "let me see it", "onboard me", or just triggers the skill
with no payment target named), the correct first action is **NOT** to run a script that spends real
money. Show them the shape of it for free first.

Everything needed to do that costs nothing:

```bash
./catalog.sh                                          # what is payable, as capabilities
curl https://sippar.network/mcp/tools/pay/products    # what Sippar itself sells, live prices
./fund.sh                                             # the agent's wallet address and balance
```

That answers "what can I buy, what does it cost, and where does the money come from" without a
payment, an account or a key. Only move to a paid call once the user has asked for something
specific ("pay for a web search on X", "call this 402 URL", "fund my wallet"). Never chain
"onboard me" straight into a real payment.

**There is no `sippar.network/demo` page.** Do not send anyone there and do not test for it: that
path returns HTTP 200 because the site serves its single-page app for every unknown route, so a
"did it 404" check will never tell you the page is missing. Re-verified 2026-08-17. The guided
visual demo referenced in some Sippar material is internal and is not available with this plugin.

### Using this skill in your own project

Installed as a plugin, everything is already in place. To vendor it instead, copy the
`skills/sippar-x402/` folder into your repo's `.claude/skills/`. Then ask your agent in plain
English ("what can I pay for?", "pay for a web search on X", "extract the metadata from this URL")
and it runs the bundled scripts in section 7. Everything the skill needs is in that one folder,
with nothing else to install and no key to obtain.

---

## 1. Read this first: which door, and what it costs you in credentials

There are two MCP doors over the same tools, and they do not have the same auth. Pick the door
before you write a call, because the wrong one returns `-32001 Unauthorized` and no explanation.

### Door A: the REST tools. No credential at all.

`https://sippar.network/mcp/tools/pay/...`

Nothing here asks for an API key. This is the door a skill user actually uses, and everything in
sections 2 to 6 below is written against it.

| Verb and path | What it does | Who pays |
|---|---|---|
| `GET /manifest` | every tool with its live input schema | free |
| `GET /health`, `GET /health/deep` | MCP health, and the MCP-to-backend hop | free |
| `GET /products`, `GET /products/:id` | Sippar's own storefront, read live | free |
| `POST /buy` | buy a Sippar product | **you**, from your own wallet |
| `GET /wallet/:principal` | an agent's derived address and live balance | free |
| `POST /pay` | pay an external x402/MPP service | **Sippar's treasury**, see the limits below |
| `POST /serve` | list your output behind a real 402 | free to list, a peer pays you |
| `POST /publish/:reportId`, `GET /publish/:reportId` | sell a report you bought | held, see section 6 |
| `POST /session/open`, `GET /session/:id`, `POST /session/:id/draw`, `DELETE /session/:id` | MPP sessions | treasury, or an agent wallet |

### Door B: the JSON-RPC protocol. `tools/call` needs a key.

`https://sippar.network/mcp/protocol/pay`

`initialize`, `notifications/initialized`, `tools/list` and `ping` are open, so any MCP client can
connect and read the 18 tools. `tools/call` is gated: without a valid key you get
`{"code":-32001,"message":"Unauthorized: Invalid or missing API key"}`.

**What you do about that.** The key is issued by Sippar, from the server's own allowlist. There is
no self-serve signup and no way to mint one client-side. Ask for one at elad@sippar.network with a
line about the use case. Until you hold one, use Door A, which covers ten of the eighteen tools
with no credential.

Send it as `X-Api-Key: <key>` (a `?apiKey=` query parameter also works and is for testing only).

**The eight tools that exist only on Door B**, so a keyless agent cannot reach them:
`discover_services`, `transfer`, `relay_pay`, `batch_pay`, and the four pay.sh tools
(`discover_paysh_services`, `list_paysh_endpoints`, `quote_paysh_service`, `pay_paysh_service`).
The pay.sh four are deliberately absent from the REST manifest, which is why that manifest lists
14 tools and `tools/list` returns 18.

For keyless discovery of what Sippar can pay for, `GET https://sippar.network/api/sippar/marketplace`
is open and needs nothing.

### The one thing about `POST /mcp/tools/pay/pay` you must not miss

That route is credential-free because **Sippar's treasury is the payer**, not you. It is not a
cheaper way to buy something. Three consequences:

1. **Attested hosts only.** The host in `serviceUrl` has to be in Sippar's attested catalog
   (`GET /api/sippar/marketplace/attested`). Anything else is refused with a policy error, not a
   bug: Sippar will not spend its own money on a host it has not attested.
2. **It refuses `sippar.network`.** Verified live 2026-08-17: it answers
   `serviceUrl host "sippar.network" is not in Sippar's attested catalog`. So this hop **cannot buy
   Sippar's own products**. Use `POST /mcp/tools/pay/buy` for those, where you pay and Sippar is the
   payee.
3. **It is bounded.** 10 calls per minute per IP, and every caller shares one daily treasury
   ceiling. A 429 means the day is spent.

If you need Sippar to pay a host that is not attested, that is the token-gated backend route
`POST /api/sippar/agent/pay` behind the `X-Sippar-Access` gate, not this one.

---

## 2. The agent's wallet

The identity is an ICP principal. Generate one locally, no signup and no website:

```typescript
import { Ed25519KeyIdentity } from "@dfinity/identity";
const identity = Ed25519KeyIdentity.generate();
console.log(identity.getPrincipal().toText());
```

Then look up the wallet derived from it, and fund the address it names:

```bash
curl https://sippar.network/mcp/tools/pay/wallet/<principal>
# -> { "principal": "...", "address": "0x...", "balanceUSD": 0.001, "fundToken": "0x...", "chain": "tempo" }
```

Secp256k1 derivation gives the **same 0x address on every EVM chain Sippar supports**, so one
lookup answers "where do I send funds" for all of them. The default balance shown is Tempo USDC.e,
which is what `pay` spends.

On Door B, `get_agent_wallet` does the same job and adds two things: `create: true` mints a brand
new principal and returns it (persist it, because under threshold signing the principal **is** the
credential and it is not recoverable), and `chain: "base"` returns the Base USDC and ETH balances
with a `ready` flag. One tool answers the whole "which address is mine, and can it pay" question.

The agent's on-chain balance is its real budget. Pay responses report what is left, so the agent can
decide against ground truth rather than a guess.

---

## 3. Buy one of Sippar's own products

Sippar sells a small storefront of its own. `list_products` and the REST `/products` route read
`https://sippar.network/api/sippar/sell/catalog` live, so the ids, prices and input shapes are
always today's. **Never hardcode a price from this file or anywhere else.** Read the catalog.

```bash
curl https://sippar.network/mcp/tools/pay/products              # the whole shelf
curl https://sippar.network/mcp/tools/pay/products/<id>         # one product, full schema
```

Buying is two calls, because you pay with your own wallet and Sippar never touches it:

```bash
# 1. Ask, get the real 402 challenge back (payTo, exact amount, and the Base/Solana/Tempo rails)
curl -X POST https://sippar.network/mcp/tools/pay/buy \
  -H 'Content-Type: application/json' \
  -d '{"productId":"<id>","input":{ ... }}'

# 2. Pay that challenge from your wallet, then repeat the call with the credential
curl -X POST https://sippar.network/mcp/tools/pay/buy \
  -H 'Content-Type: application/json' \
  -H 'X-PAYMENT: <base tx hash | solana signature | base64 x402 v2 payload>' \
  -d '{"productId":"<id>","input":{ ... }}'
```

Tempo MPP instead of x402: send the credential from the `WWW-Authenticate` challenge as
`Authorization: Payment <credential>`. Only a Payment authorization is read from that header; any
other bearer token is ignored rather than forwarded.

Two skills cover the products themselves in depth, with the request shapes already verified:
**`sippar-social-data`** for social listening, **`sippar-enrich`** for company, property, web,
market and grounded-search data. Use those when the job is the data. Use this skill when the job is
the payment.

---

## 4. Pay an external x402 or MPP service

```bash
curl -X POST https://sippar.network/mcp/tools/pay/pay \
  -H 'Content-Type: application/json' \
  -d '{
    "principal": "<your principal>",
    "serviceUrl": "<the 402-protected url>",
    "maxAmountUSD": 0.05,
    "method": "POST",
    "payload": { }
  }'
```

Sippar detects the 402 or MPP challenge, signs with threshold signatures, settles on the right
chain, and returns the service response with a receipt. Read section 1 before using this: on this
route the treasury is the payer and the attested-host rule applies.

Fields worth knowing:

- `maxAmountUSD` is your hard per-call ceiling. The server enforces its own cap on top; the live
  value is in the manifest.
- `principal` is optional. Omit it and the call takes the treasury-paid anonymous path.
- `payFromChain` names the chain Sippar settles from, for a service that prices itself on more than
  one. Omit it and Sippar uses the chain it attested the service on, which is the right answer for
  anything in the catalog. An unknown value is refused, never substituted.
- `preferTempo` takes the MPP challenge on a service that advertises both. An explicit value wins
  over `payFromChain`.
- `sessionId` pays through an open MPP session, with zero threshold signatures. See section 5.

**The brokered tier is off.** `pay` still accepts a `brokeredId` instead of a `serviceUrl`, for
upstreams Sippar fronts with its own supplier credential rather than paying over x402. It is
switched off pending Sippar's legal entity and returns 503 today, so do not offer it. Use
`serviceUrl`.

**Paid is not rendered.** A payment can settle on-chain while the service still serves you nothing.
Treat a call as successful only on a real 200 with a real body. `paymentSucceeded: true` with a 402
or an empty response means you paid and got nothing: stop, do not re-pay, and report it.

### pay.sh, as a source inside this namespace

pay.sh is the Solana Foundation's machine-payment marketplace and its services settle on Solana.
Sippar relays into it from Base, Arbitrum, Optimism, Polygon, BNB, Ethereum, Solana and Stellar, so
an agent holding stablecoins elsewhere reaches those services without bridging.

**These four tools live only on Door B and need a key** (see section 1):

| Tool | What it does |
|---|---|
| `discover_paysh_services` | list pay.sh providers, with filters |
| `list_paysh_endpoints` | the actual endpoints for a provider. Call this before quoting or paying: endpoint names are not guessable from a service description |
| `quote_paysh_service` | price a call before making it, and get the treasury address plus exact amount if you intend to fund it yourself |
| `pay_paysh_service` | make the call and pay for it |

Two funding paths on `pay_paysh_service`, pick exactly one. Passing both is refused rather than
guessed at, because both move money.

- **A: Sippar signs for you.** Pass `principal`, and Sippar threshold-signs a transfer from that
  principal's own derived address, then relays. Check the address first with `get_agent_wallet`
  using `chain: "base"`, which returns a `ready` flag for exactly this.
- **B: you already hold a wallet.** Get the treasury address from `quote_paysh_service`, send the
  USDC yourself, then pass `sourceChain` and `sourceTxHash`.

Either way you get the service response plus on-chain receipts for both legs. The relay fee is
returned as `feeBps` in the quote; read it from the response rather than assuming a number.

Endpoint names are the part most likely to be stale in any written guide, including this one.
`list_paysh_endpoints` is the only thing that knows what a provider exposes today, so call it
rather than trusting a name you read somewhere.

---

## 5. Many payments: sessions and batches

Every payment above costs one ICP threshold signature. For many payments, amortize it.

**MPP sessions (Tempo TIP-1011 access keys).** One signature opens a budget; every draw after that
settles with no threshold signature at all. Best for streaming and sub-cent spending.

```bash
curl -X POST https://sippar.network/mcp/tools/pay/session/open \
  -H 'Content-Type: application/json' \
  -d '{"budgetUSD":0.5,"expirySecs":3600,"principal":"<principal>"}'

curl -X POST https://sippar.network/mcp/tools/pay/session/<id>/draw \
  -H 'Content-Type: application/json' \
  -d '{"toAddress":"0x<recipient>","amountUSD":0.01}'

curl https://sippar.network/mcp/tools/pay/session/<id>          # status
curl -X DELETE https://sippar.network/mcp/tools/pay/session/<id> # close
```

To buy a service through the session instead of paying an address, pass `sessionId` to
`POST /mcp/tools/pay/pay`. The session budget and expiry are enforced on-chain and are the hard
cap; per-draw and per-session ceilings are server-enforced, with live values in the manifest. The
session store is in memory, so a backend restart orphans open sessions and the on-chain key expires
on its own. If a draw 404s, open a new session. Tempo only.

**Batch settle** puts N payments in one signed transaction: one signature, atomic. Best for a known
set at once, such as splits and payouts. It is `batch_pay` on Door B and needs a key. Default is
Tempo with EVM addresses; `"chain":"solana"` does a Solana USDC batch, up to 10 transfers on one
Ed25519 signature, with an optional per-transfer `createDestATA` for brand new recipients.

**Direct transfer** to a peer, no service and no 402, is `transfer` on Door B. For a recipient
wallet that has never been seen, pass `gasLimit` around 700000, because the default reverts.

---

## 6. Getting paid: sell your own output

`serve_output` lists any JSON behind a real 402 payable to **your own** threshold wallet. A peer
pays it with the `pay` call above and gets the content only after settling on-chain. This is the
producer side of agent-to-agent commerce, and it is free to list.

```bash
curl -X POST https://sippar.network/mcp/tools/pay/serve \
  -H 'Content-Type: application/json' \
  -d '{"producerPrincipal":"<your principal>","output":{"answer":"..."},"priceUSD":0.02}'
# -> { "outputUrl": "https://..." }
```

`publish_report` is the same idea for a Sippar report you bought: pass the report id and the pack
session of the wallet that bought it, and your own copy is listed for sale. What gets listed is the
derived report Sippar builds server-side, meaning the analysis, the takeaway, the per-platform
counts and the sources as links. Post text from the underlying platforms is never included.

**Report publishing is not available yet.** The backend door is off by default
(`SOCIAL_REPORT_PUBLISH_ENABLED`) and answers 404 until Sippar flips it. Verified live 2026-08-17:
`GET /mcp/tools/pay/publish/<id>` returns `{"error":"Report publishing is not available.","code":"E_NOT_FOUND"}`.
Document it as built and held, never as a working feature.

---

## 7. Bundled scripts

Four scripts sit next to this file. They need no token, no `.env` and no wallet key, only `bash`,
`curl` and `python3`. They run against Door A.

```bash
./catalog.sh                 # what can my agent pay for, as capabilities
./catalog.sh data            # drill into one capability
./fund.sh                    # the agent's wallet address and live balance
./fund.sh <principal>        # a specific identity
./pay.sh '{"principal":"2vxsx-fae","serviceUrl":"...","method":"GET","payFromChain":"base","maxAmountUSD":0.04}'
./selftest.sh                # one real payment end to end, with a block-explorer link
```

`pay.sh` prints the service response plus a receipt with the amount, the chain, whether the service
actually rendered, and an explorer link for on-chain settlements. MPP payments on Tempo present a
signed authorization rather than broadcasting a transaction, so the receipt says so instead of
printing a dead link. Surface the explorer link to the user whenever there is one.

`selftest.sh` and `pay.sh` spend real money. Everything else here is free.

---

## 8. Spend safety

- `maxAmountUSD` on every call is a ceiling you control.
- The server enforces its own per-payment cap and rate limits on top.
- The derived wallet's balance is a physical cap: an agent cannot spend what it does not hold.
- The treasury hop is attested-hosts-only, rate-limited per IP, and shares one daily ceiling.
- Paid is not rendered. See section 4.
- Never loop. Do not re-run a call that already returned an answer.

## 9. Errors

| What you see | Cause | What to do |
|---|---|---|
| `-32001 Unauthorized` on `tools/call` | Door B without a key | use Door A, or request a key |
| `host ... is not in Sippar's attested catalog` | treasury hop, non-attested host | pay from your own wallet, or ask for attestation |
| 429 on `/pay` or `/session/open` | per-IP limit or the daily treasury ceiling | back off; check `GET /api/sippar/agent/health` for headroom |
| `E_INSUFFICIENT_BALANCE` | derived wallet underfunded | fund the address from the wallet lookup |
| session not found on draw | expired, or the backend restarted | open a new session |
| `paymentSucceeded: true`, service 402 | facilitator or upstream fault | do not re-pay, report it |
| 502 `BACKEND_ERROR` on Door A | the MCP-to-backend hop token drifted | operator issue, check `GET /mcp/tools/pay/health/deep` |
| `Sign failed: ... Couldn't send message` | Sippar's signer canister is low on cycles | transient on Sippar's side, report it |
| brokered tier returns 503 | switched off pending Sippar's legal entity | use `serviceUrl`, not `brokeredId` |

> **"No credential" is client-side only.** On Door A *you* send nothing, but the MCP front still
> authenticates to the Sippar backend on your behalf on every call that reaches it. If that
> server-side secret drifts, these routes return 502 even though the public surface needs no auth.
> `manifest` and `health` do not exercise that hop, so they can look healthy while it is broken.
> `health/deep` is the one that tests it.

## 10. Appendix: if you run your own signer

Everything above goes through Sippar's deployed endpoints, which is the path almost every caller
wants. This section only matters if you build an x402 client against ICP threshold signatures
yourself rather than using those endpoints.

### Two patterns that cost real time to rediscover

**EVM recovery id.** ICP's `recovery_id` is not Ethereum's `v`. Recover against the expected
address rather than trusting the value:

```typescript
for (const v of [27, 28]) {
  if (recoverAddress(hash, `0x${r}${s}${v.toString(16)}`).toLowerCase() === expected.toLowerCase()) return `0x${r}${s}${v.toString(16)}`;
}
```

**Ed25519 (Solana, Stellar, TON, Algorand).** Attach the threshold signature directly. There is no
recovery step.

### Finding services elsewhere

| Registry | URL |
|---|---|
| PayAI | `https://facilitator.payai.network/discovery/resources` |
| Coinbase Bazaar | `https://api.cdp.coinbase.com/platform/v2/x402/discovery/resources` |

Sippar keeps its own render-verified catalog. The public registries are noisy, on the order of most
entries being junk on some of them, so verify before relying on anything found there. Sippar's
attested set is `GET https://sippar.network/api/sippar/marketplace/attested`, and it is the set the
treasury hop will pay.

### Treasury addresses (the shared-custody path)

`quote_paysh_service` returns the right address for your source chain, so an agent never needs to
hardcode one. For reference:

| Chain | Address |
|---|---|
| EVM (all) and Tempo | `0x07fBca218b0a0a35244e0025a036Fa85a6dC97DC` |
| Solana | `6JBm9umc9KAHYAJdqAVWAqhChGDvYKtwtAe7bpPk29HX` |
| Stellar | `GC443QVFP3646SNLKH2IL46XK67I4EE3YZQX6MY37PTWZGB5QNAK5DKO` |
| TON | `UQDDi8tXR5Z9FV2SGj2wZpxQaKJ1q7snb36XBKVjxENJD0Jc` |

Buying a Sippar product is different: the sell storefront has its own dedicated receive-only payTo
on Base, deliberately not the shared treasury, so a treasury-bound transfer cannot satisfy a
purchase. Always read `payTo` from the 402 challenge and send there, never to a table.

### What actually caps your spend

Not a signer-side rate limit. Sippar's signer supports a per-principal cap but it is not configured
on mainnet today, so it bounds nothing. What does bound you: the `maxAmountUSD` you pass, the
server's own per-payment cap (live value in the manifest), and the on-chain balance of your derived
wallet, which is the only physical limit. Fund the wallet with what you are willing to lose.

## Related

- Site and browsable catalog: `https://sippar.network` and `https://sippar.network/marketplace/`
  (the trailing slash matters, the bare path 301s to it)
- Live tool list, always current: `https://sippar.network/mcp/tools/pay/manifest`
- Live product catalog: `https://sippar.network/api/sippar/sell/catalog`
- Attested hosts the treasury will pay: `https://sippar.network/api/sippar/marketplace/attested`
- Questions, access keys, or a service you want attested: elad@sippar.network
- x402: `https://x402.org` · MPP: `https://mpp.dev` · pay.sh: `https://pay.sh`
