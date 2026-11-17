# Cofinex Wallet roadmap

This is the product sequence from the v1 vision. It is not a delivery schedule.
Nothing here is audited or ready for mainnet funds.

ADR-001 is the locked architecture. Compliance (ADR-001 section 8) stays open
until counsel reviews the Cofinex MPC share and the email escrow.

## Foundation (this repository)

Scaffold, plus a read-only unified USDT balance.

- Rust workspace: keys, swappable signer, chain-adapter trait, Sepolia signing adapter.
- The EVM adapter also reads native and ERC-20 balances on Ethereum, BNB Smart Chain, Polygon, and their testnets. It does not sign on those networks.
- TRON reads native TRX and TRC-20 balances, and derives `m/44'/195'/0'/0/0`. It does not sign.
- Solana SPL balances are still a stub. Bitcoin and Sui still return "not implemented".
- `unified_portfolio` sums one asset across chains with decimal strings and refuses to mix a testnet deployment into that total.
- Local BIP-39 signer. The 2-of-3 MPC signer is a stub that cannot sign.
- Flutter shell that can create or import a test wallet, show unified USDT with a per-chain breakdown, and read a Sepolia balance.
- PostgreSQL token-registry schema and a cited seed, including USDT on the chains Tether publishes (Ethereum, TRON, Solana). No registry API. BSC and Polygon USDT are not in that seed.

The only network the signer will talk to is Sepolia (chain id 11155111).
Signed transactions embed that chain id.

## v1 — Multichain view and same-chain sends

What v1 is:

- One screen for a verified asset, with a balance on each supported chain.
- Sends that stay on a single chain. The user picks the chain; the wallet does not bridge.
- Working adapters for the priority networks: Bitcoin, Ethereum (and the EVM networks we turn on), Solana, Sui, TRON.
- Native and token transfers, fees, and transaction status.
- The registry snapshot the app can use offline, fed by the schema in `services/registry`.

What v1 is not:

- MPC signing. The trait is in place; CGGMP21 (ECDSA) and FROST (EdDSA) are not wired up.
- Recovery: Internet Identity, the encrypted recovery share, share rotation, or the 24 to 48 hour delay.
- Email transfers, the identity resolver, and claimable escrow.
- A token-registry HTTP API or its Redis cache. The database is the foundation; the service comes later.
- Cross-chain swaps or bridges. ADR-001 defers routing past v1. Later routes go through aggregators (LI.FI, Socket, Jupiter), not a Cofinex bridge, and every route shows fees, time, and the bridge before the user signs.
- Business multisig (Safe, Bitcoin multisig, Squads) and approval policies.
- Mainnet custody. Testnet first. A mainnet send is a later, explicit change.

## After v1

In the order the vision describes them, still without dates:

1. **Identity and recovery.** ICP Internet Identity for login, separate from signing. Verified email. Share-based recovery with the delay and alerts from ADR-001.
2. **MPC as the default retail signer.** Device share, Cofinex share that cannot sign alone, user-held recovery share, key refresh after recovery. The local seed signer stays as the opt-in power-user path. Adapters stay on the `Signer` trait.
3. **Email transfers.** Salted email hash, signed address proofs, claimable escrow that Cofinex cannot drain, about 14 days then refund. This waits on the legal opinion in ADR-001 section 8.
4. **Registry service.** Read API, Redis cache, signed snapshot the app verifies. Review workflow for new deployments. A matching symbol is not verification.
5. **Cross-chain.** Aggregator routes only, with the fee, time, and bridge shown before signing.
6. **Business treasury, browser extension, dApps, NFTs, staking.** After the wallet can view and send on one chain safely.

## Explicitly out of scope until those land

- Inventing a signing protocol. We use audited libraries or we do not ship MPC.
- Holding a full private key on a Cofinex server.
- Aggregating testnet balances into a mainnet asset. The registry view refuses that.
- Mainnet private keys, and any signer that can build a mainnet transaction. Public read-only RPC URLs are environment configuration for balance display. They are not used to sign.
