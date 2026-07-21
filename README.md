# sippar-pay

The agent payment skill that needs no private key.

Use it whenever an agent needs to pay for something over HTTP: an x402 or MPP (Machine
Payments Protocol) service, a "402 Payment Required" response, a per-call data or inference
endpoint, a brokered premium AI upstream, or another agent selling its output. The wallet is
keyless (Sippar-managed, with a scoped path to non-custody): no seed phrase, no private key,
and a server-enforced spend cap on every payment.

## Install

```
/plugin marketplace add Nuru-AI/sippar-pay
```

Then install the `sippar-pay` plugin and trigger it on any "pay this API" or 402 scenario.

## Links

- Sippar: https://sippar.network
