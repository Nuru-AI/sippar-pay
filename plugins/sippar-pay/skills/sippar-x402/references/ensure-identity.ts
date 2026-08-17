#!/usr/bin/env -S bun run
/**
 * ensure-identity.ts
 *
 * Generates an Ed25519 keypair locally, persists it to `.sippar/identity.json`, prints the
 * agent's ICP principal and the Sippar-derived wallet address for it.
 *
 * The principal is a self-authenticating 29-byte hash of the Ed25519 public key. There is no
 * website and no registration: the keypair IS the identity.
 *
 * Optional. `get_agent_wallet({ create: true })` on the MCP protocol surface does the same in one
 * call, but that surface needs an API key and mints the principal server-side. Use this script
 * when you want the principal generated on your own machine and no key of your own to request.
 *
 * Run modes (in order of preference based on what is installed):
 *   bun references/ensure-identity.ts
 *   pnpm tsx references/ensure-identity.ts
 *   npx tsx references/ensure-identity.ts
 *
 * Required deps:
 *   bun add @dfinity/identity @dfinity/principal
 */

import { Ed25519KeyIdentity } from '@dfinity/identity';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const IDENTITY_DIR = resolve(process.cwd(), '.sippar');
const IDENTITY_PATH = resolve(IDENTITY_DIR, 'identity.json');

// The credential-free REST surface. Verified live 2026-08-17.
const SIPPAR_MCP = process.env.SIPPAR_MCP ?? 'https://sippar.network/mcp/tools/pay';

interface PersistedIdentity {
  principal: string;
  publicKey: string;   // hex
  privateKey: string;  // hex, KEEP SECRET, never commit
  createdAt: string;
}

function loadOrCreate(): { identity: Ed25519KeyIdentity; persisted: PersistedIdentity; isNew: boolean } {
  if (existsSync(IDENTITY_PATH)) {
    const persisted = JSON.parse(readFileSync(IDENTITY_PATH, 'utf8')) as PersistedIdentity;
    const identity = Ed25519KeyIdentity.fromParsedJson([persisted.publicKey, persisted.privateKey]);
    return { identity, persisted, isNew: false };
  }

  const identity = Ed25519KeyIdentity.generate();
  const principal = identity.getPrincipal().toText();
  const [publicKey, privateKey] = identity.toJSON();
  const persisted: PersistedIdentity = { principal, publicKey, privateKey, createdAt: new Date().toISOString() };

  if (!existsSync(IDENTITY_DIR)) mkdirSync(IDENTITY_DIR, { recursive: true, mode: 0o700 });
  writeFileSync(IDENTITY_PATH, JSON.stringify(persisted, null, 2), { mode: 0o600 });
  return { identity, persisted, isNew: true };
}

async function lookupWallet(principal: string): Promise<{ address?: string; balanceUSD?: number; chain?: string; fundToken?: string } | null> {
  try {
    const res = await fetch(`${SIPPAR_MCP}/wallet/${encodeURIComponent(principal)}`);
    const j = (await res.json()) as { success?: boolean; data?: Record<string, unknown> };
    return (j.data as any) ?? null;
  } catch {
    return null;
  }
}

(async () => {
  const { persisted, isNew } = loadOrCreate();
  const wallet = await lookupWallet(persisted.principal);

  console.log(isNew ? '\nGenerated NEW Sippar agent identity.' : '\nLoaded existing Sippar agent identity.');
  console.log('  identity file:   ', IDENTITY_PATH);
  console.log('  ICP principal:   ', persisted.principal);
  console.log('  wallet address:  ', wallet?.address ?? '(could not reach the Sippar MCP; retry the wallet lookup below)');
  console.log('  live balance:    ', wallet?.balanceUSD !== undefined ? `$${wallet.balanceUSD}` : 'unknown');
  console.log('  fund it on:      ', wallet?.chain ?? 'unknown', wallet?.fundToken ? `(token ${wallet.fundToken})` : '');
  console.log('  created at:      ', persisted.createdAt);
  console.log();
  console.log('The same address is derived on every EVM chain Sippar supports.');
  console.log('Re-read the wallet at any time:');
  console.log(`  curl ${SIPPAR_MCP}/wallet/${persisted.principal}`);
  console.log();
  console.log('NEXT STEP: fund that address, then pay a service:');
  console.log(`  curl -X POST ${SIPPAR_MCP}/pay \\`);
  console.log(`    -H 'Content-Type: application/json' \\`);
  console.log(`    -d '{"principal":"${persisted.principal}","serviceUrl":"<402-url>","maxAmountUSD":0.05}'`);
  console.log();
  console.log('Security note: identity.json contains your Ed25519 PRIVATE KEY. Treat it like a wallet seed.');
  console.log('  - Add ".sippar/" to .gitignore');
  console.log('  - Set restrictive permissions: chmod 600', IDENTITY_PATH);
  console.log('  - Back up to a secrets manager for production agents');
  console.log('  - The principal is NOT recoverable from Sippar. Lose it and you lose the wallet.');
})().catch((err) => {
  console.error('ensure-identity failed:', err?.message ?? err);
  process.exit(1);
});
