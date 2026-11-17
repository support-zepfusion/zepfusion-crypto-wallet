# ADR-001: Cofinex Wallet Core Architecture Decisions

**Status:** Accepted (compliance item open)
**Date:** 17 November 2026
**Decider:** Santosh Padhi, CTO, Cofinex Online India Pvt Ltd
**Source:** Cofinex Wallet Product Vision & Architecture Reference v1.0, section 25 (Open Decisions)

> These are design decisions. Nothing here is implemented, audited, or verified yet.

---

## 1. Custody model (25.1)

**Decision:** Hybrid, three tiers.

- **Retail (default):** 2-of-3 MPC. Share 1 on the user's device, share 2 with a Cofinex signing service, share 3 as an encrypted recovery share the user controls. Cofinex can never sign alone.
- **Power users (opt-in):** classic seed-phrase self-custody.
- **Business treasury:** on-chain multisig (Safe on EVM chains, native multisig on Bitcoin, Squads on Solana) with approval policies on top.

**Why:** Keeps the wallet non-custodial while removing seed-phrase friction for most users, and gives businesses auditable on-chain approvals.

**Consequences:** Needs both ECDSA and EdDSA threshold schemes (see 3). The Cofinex share has regulatory implications (see 8).

## 2. Token Registry database (25.2)

**Decision:** PostgreSQL.

- One canonical asset maps to many chain deployments (contract or mint address, decimals, verification status, source).
- Unique constraint on (chain, address).
- Reads served through an API with a Redis cache.
- The app ships a signed registry snapshot so it can flag unverified or fake tokens offline or when the API is down.

**Why:** The data is relational and needs joins, uniqueness and ad-hoc review queries, which DynamoDB handles poorly.

## 3. MPC protocols (25.3)

**Decision:** Open-source, Rust-native, audited libraries.

- **ECDSA chains** (Bitcoin, Ethereum, TRON, BNB Smart Chain, Polygon): CGGMP21 via Dfns' `cggmp21` crate (audited by Kudelski Security), 2-of-3 with key refresh.
- **EdDSA chains** (Solana, Sui): FROST via the Zcash Foundation `frost` crates (audited by NCC Group). FROST can later cover Bitcoin Taproot.
- **Fallback:** a commercial SDK (e.g. Silence Laboratories DKLs23) only if owning the crypto proves too costly.

**Consequences:** We own the integration and must commission our own audit of how the libraries are used.

## 4. Identity resolver (25.4)

**Decision:** Hashed lookup with signed ownership proofs and claimable escrow.

- Server stores only a salted hash of each verified email, linked to the user's per-chain wallet addresses.
- Each address carries a wallet signature proving ownership.
- The sender's app resolves the hash, verifies the signature, and shows the recipient's name for confirmation before signing.
- **Unregistered recipient:** funds go to a claimable escrow (smart contract on EVM chains). The recipient claims after sign-up; otherwise funds are auto-refunded after about 14 days.

**Consequences:** Escrow contracts are needed per chain family and must be audited. Escrow has regulatory implications (see 8).

## 5. Recovery (25.5)

**Decision:** Share-based recovery with a time delay.

- New device signs in with ICP Internet Identity plus a verified email code.
- The Cofinex share and the user's recovery share re-create a fresh device share.
- All shares are rotated immediately, so the lost device becomes useless.
- A **24 to 48 hour delay** with email and push alerts runs before recovery completes, so a hijacked account cannot drain funds instantly.
- Recovery share is encrypted and stored in the user's own iCloud or Google Drive, with an optional passkey or printed recovery code as a second copy.

## 6. Blockchain data providers (25.6)

**Decision:** Multi-provider behind our own gateway.

- A primary and a backup provider per chain, behind a Cofinex RPC gateway handling failover, caching and rate limits.
- Candidates: Alchemy or QuickNode for EVM and Solana; QuickNode or the official Sui RPC for Sui; TronGrid for TRON; our own Bitcoin node plus an Electrum-style indexer.
- Portfolio balances and history come from provider token and transfer APIs, cached per user.

**Deferred:** provider pricing and India latency comparison.

## 7. Cross-chain routing (25.7)

**Decision:** Not in v1.

- **v1:** unified view of the same asset across chains; sends within one chain only.
- **Later:** swaps and bridging through aggregators (LI.FI or Socket for EVM, Jupiter for Solana), not our own bridges.
- Every route shows fees, estimated time and the bridge it trusts before the user signs.

## 8. Regulatory and compliance (25.8)

**Status:** Open. Legal opinion required before launch.

- Since March 2023, Indian VDA service providers that safekeep or administer crypto for others must register with FIU-IND under the PMLA.
- A purely non-custodial wallet usually sits outside this, but two decisions above need review:
  1. The Cofinex-held MPC share (even though it cannot sign alone).
  2. The email escrow, which holds funds for not-yet-registered recipients.
- Swaps (post-v1) will add further questions.
- **Mitigation:** design the escrow as a self-executing smart contract that Cofinex cannot move funds out of.

**Action:** obtain a written opinion from a crypto-specialist lawyer on items 1 and 2 before launch.

---

## Summary

| # | Area | Decision |
|---|---|---|
| 1 | Custody | Hybrid: 2-of-3 MPC default, optional seed phrase, multisig for business |
| 2 | Token Registry | PostgreSQL + Redis cache + signed in-app snapshot |
| 3 | MPC | CGGMP21 (ECDSA) + FROST (EdDSA), open source |
| 4 | Identity resolver | Salted email hash + signed address proofs + claimable escrow (~14 day refund) |
| 5 | Recovery | Internet Identity + email, share rotation, 24 to 48 hour delay |
| 6 | Data providers | Primary + backup per chain behind own gateway; pricing deferred |
| 7 | Cross-chain | Deferred past v1; aggregators later |
| 8 | Compliance | Open; legal opinion on MPC share and escrow before launch |
