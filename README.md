# Cofinex Wallet

One Wallet. Every Chain. One Seamless Experience.

Non-custodial multichain wallet. Flutter UI, Rust core, chain adapters behind a swappable signer. This repository is the foundation scaffold from [ADR-001](docs/adr/ADR-001-cofinex-wallet-architecture.md). It is testnet-only and not ready for mainnet funds.

## What is built

- Cargo workspace (`crates/keys`, `crates/signer`, `crates/core`, `crates/chains`, `apps/mobile/rust`).
- `ChainAdapter`: derive an address, read a balance, build an unsigned transfer, broadcast a signed transaction, and read transaction status. The same trait covers secp256k1 (Bitcoin, EVM, TRON) and ed25519 (Solana, Sui).
- `Signer`: `LocalSigner` (BIP-39 + BIP-32 / SLIP-0010) is the only implementation. `MpcSigner::two_of_three` is a documented stub that returns "not implemented". Adapters depend on the trait, so replacing the local signer with CGGMP21 (ECDSA) or FROST (EdDSA) does not require adapter changes.
- Secrets sit in `zeroize` buffers. `Debug` redacts mnemonics and private keys. Errors do not echo a recovery phrase.
- One working adapter: Ethereum Sepolia (chain id `11155111`). The RPC URL comes from `COFINEX_SEPOLIA_RPC_URL` or an argument. The adapter checks `eth_chainId` before any other call and embeds that chain id in the EIP-1559 payload, so a mainnet endpoint is refused. Bitcoin, TRON, Solana, and Sui compile and return "not implemented".
- Flutter shell (`apps/mobile`) generated with flutter_rust_bridge 2.13.0. The screen creates or imports a test wallet and shows the Sepolia address and native balance.
- PostgreSQL token registry (`services/registry`): chains, canonical assets, deployments, verification, and a unified-balance view that excludes testnets. Seed data is native assets plus USDC addresses copied from Circle's published list. Sources are cited in the seed migration. No invented contract addresses.

## What is stubbed

- MPC signing, key refresh, and share storage.
- Bitcoin, TRON, Solana, and Sui balance, build, broadcast, and status.
- Token transfers (the Sepolia adapter sends native ETH only).
- Registry HTTP API, Redis cache, and the signed snapshot.
- Recovery, email transfers, escrow, and cross-chain routing. See [docs/ROADMAP.md](docs/ROADMAP.md).
- Android and iOS packaging of the Rust library (cargokit is not wired). The shell loads `libcofinex_wallet_bridge.so` on the desktop via `COFINEX_RUST_LIB` or a path under the workspace `target/` directory.

## Requirements

- Rust 1.100.0 (pinned in `rust-toolchain.toml`; the workspace MSRV is 1.85).
- Flutter 3.50.0 for the app shell. CI uses that version.
- PostgreSQL 16 for the registry.

## Rust

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

The ignored Sepolia test reads a public address and does not sign or spend:

```bash
export COFINEX_SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
cargo test -p cofinex-chains -- --ignored live_sepolia_balance
```

Copy `.env.example` if you want the variable written down. Do not commit a `.env`, an API key, or a mainnet URL.

## Flutter

Widget tests use a fake API and do not load the native library.

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

To regenerate the bridge after an API change (codegen 2.13.0 must be on `PATH`):

```bash
cd apps/mobile
flutter_rust_bridge_codegen generate
```

A desktop run needs the cdylib. From the repository root:

```bash
cargo build -p cofinex-wallet-bridge
cd apps/mobile
export COFINEX_RUST_LIB="$PWD/../../target/debug/libcofinex_wallet_bridge.so"
export COFINEX_SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
flutter run -d linux
```

The create button generates a new BIP-39 phrase and shows it once. It is not written to disk. Do not reuse it on mainnet. Leave the RPC field empty to use `COFINEX_SEPOLIA_RPC_URL`.

## Token registry

```bash
export DATABASE_URL=postgres://cofinex:cofinex@localhost:5432/cofinex_registry
./services/registry/apply.sh
```

The script applies `services/registry/migrations/*.sql` in order, records them, and runs `verify.sql`. A second run skips files that are already applied. `verify.sql` fails if a testnet deployment is included in the unified-balance view.

The CI job uses a throwaway `postgres:16` service (`postgres` / `postgres` on localhost). That password is not a credential for any deployed database.

## Layout

```
crates/keys      BIP-39, BIP-32 secp256k1, SLIP-0010 ed25519
crates/signer    Signer, LocalSigner, MpcSigner stub
crates/core      ChainAdapter, Wallet, amounts
crates/chains    Sepolia adapter and the other-chain stubs
apps/mobile      Flutter shell and the flutter_rust_bridge crate
services/registry  PostgreSQL migrations, seed, and checks
docs/adr         ADR-001
docs/ROADMAP.md  v1 scope and what comes later
```
