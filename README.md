# Cofinex Wallet

One Wallet. Every Chain. One Seamless Experience.

Non-custodial multichain wallet. Flutter UI, Rust core, chain adapters behind a swappable signer. This repository is the foundation scaffold from [ADR-001](docs/adr/ADR-001-cofinex-wallet-architecture.md). It is testnet-only and not ready for mainnet funds.

## What is built

- Cargo workspace (`crates/keys`, `crates/signer`, `crates/core`, `crates/chains`, `apps/mobile/rust`).
- `ChainAdapter`: derive an address, read a balance, build an unsigned transfer, broadcast a signed transaction, and read transaction status. The same trait covers secp256k1 (Bitcoin, EVM, TRON) and ed25519 (Solana, Sui).
- `Signer`: `LocalSigner` (BIP-39 + BIP-32 / SLIP-0010) is the only implementation. `MpcSigner::two_of_three` is a documented stub that returns "not implemented". Adapters depend on the trait, so replacing the local signer with CGGMP21 (ECDSA) or FROST (EdDSA) does not require adapter changes.
- Secrets sit in `zeroize` buffers. `Debug` redacts mnemonics and private keys. Errors do not echo a recovery phrase.
- One signing adapter: Ethereum Sepolia (chain id `11155111`). The RPC URL comes from `COFINEX_SEPOLIA_RPC_URL` or an argument. The adapter checks `eth_chainId` before any other call and embeds that chain id in the EIP-1559 payload, so a mainnet endpoint is refused for signing.
- The same EVM adapter reads native balances and ERC-20 `balanceOf` on Ethereum, BNB Smart Chain, Polygon, and their testnets. Each network is chain id plus an RPC URL (`COFINEX_ETHEREUM_RPC_URL`, `COFINEX_BSC_RPC_URL`, `COFINEX_POLYGON_RPC_URL`, and the testnet names in `.env.example`). Those networks cannot build, sign, or broadcast.
- TRON reads native TRX and TRC-20 `balanceOf` through a TronGrid-compatible HTTP API (`COFINEX_TRON_RPC_URL`). Addresses are base58check at `m/44'/195'/0'/0/0`. TRON does not sign.
- A core `unified_portfolio` function sums one asset across chains with decimal strings. Testnet rows cannot be folded into a mainnet total. Solana SPL balances are still a stub, so a Solana USDT row is reported as unavailable rather than zero.
- Flutter shell (`apps/mobile`) generated with flutter_rust_bridge 2.13.0. The screen creates or imports a test wallet, shows a unified asset list (USDT total, chain chips, expandable per-chain balances), and can still read the Sepolia ETH balance.
- PostgreSQL token registry (`services/registry`): chains, canonical assets, deployments, verification, and a unified-balance view that excludes testnets. Seed data is native assets, USDC from Circle's list, and USDT from Tether's supported-protocols page. Sources are cited in the seed migrations. No invented contract addresses.

## What is stubbed

- MPC signing, key refresh, and share storage.
- Bitcoin, Solana, and Sui balance, build, broadcast, and status. Solana SPL `balanceOf` is not implemented.
- TRON build, broadcast, and status. Balance reads are implemented.
- Token transfers (the Sepolia adapter sends native ETH only). ERC-20 and TRC-20 reads do not send.
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

Ignored live tests read a public address and do not sign or spend. One test per network:

```bash
export COFINEX_SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
export COFINEX_ETHEREUM_RPC_URL=https://ethereum-rpc.publicnode.com
export COFINEX_BSC_RPC_URL=https://bsc-rpc.publicnode.com
export COFINEX_BSC_TESTNET_RPC_URL=https://bsc-testnet-rpc.publicnode.com
export COFINEX_POLYGON_RPC_URL=https://polygon-bor-rpc.publicnode.com
export COFINEX_POLYGON_AMOY_RPC_URL=https://polygon-amoy-bor-rpc.publicnode.com
export COFINEX_TRON_RPC_URL=https://api.trongrid.io
cargo test -p cofinex-chains -- --ignored
```

Copy `.env.example` if you want the variables written down. Do not commit a `.env` or an API key. The URLs above are public read-only endpoints. The signer still refuses every chain id other than Sepolia.

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
export COFINEX_ETHEREUM_RPC_URL=https://ethereum-rpc.publicnode.com
export COFINEX_TRON_RPC_URL=https://api.trongrid.io
flutter run -d linux
```

The create button generates a new BIP-39 phrase and shows it once. It is not written to disk. Do not reuse it on mainnet. "Refresh unified assets" derives addresses from that phrase and reads USDT. Leave the Sepolia RPC field empty to use `COFINEX_SEPOLIA_RPC_URL`. A chain with no RPC URL shows an error on that row; it is not treated as a zero balance. Solana stays on the row and reports that SPL balance reading is not implemented.

## Token registry

```bash
export DATABASE_URL=postgres://cofinex:cofinex@localhost:5432/cofinex_registry
./services/registry/apply.sh
```

The script applies `services/registry/migrations/*.sql` in order, records them, and runs `verify.sql`. A second run skips files that are already applied. `verify.sql` fails if a testnet deployment is included in the unified-balance view, or if USDT is missing one of the three cited mainnet deployments (Ethereum, TRON, Solana).

USDT addresses are copied from [Tether's supported protocols page](https://tether.to/supported-protocols/) and checked against the chain. Decimals are 6 on all three. BSC and Polygon are not seeded: that page publishes no USD₮ contract for either chain. The BSC token named USDT is Binance-Peg (18 decimals on chain id 56) and is not in Tether's USD₮ list. The Polygon contract at `0xc2132D05D31c914a87C6611C10748AEb04B58e8F` answers name `USDT0`. No official testnet USD₮ deployment is on the page, so none is inserted. Solscan returned HTTP 403 while checking the Solana mint; the cross-check that landed is the Solana RPC (`getAccountInfo` decimals 6, `getAsset` name USDT) plus Tether's [explorer.solana.com](https://explorer.solana.com/address/Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB) link.

The CI job uses a throwaway `postgres:16` service (`postgres` / `postgres` on localhost). That password is not a credential for any deployed database.

## Layout

```
crates/keys      BIP-39, BIP-32 secp256k1, SLIP-0010 ed25519
crates/signer    Signer, LocalSigner, MpcSigner stub
crates/core      ChainAdapter, Wallet, amounts
crates/chains    EVM and TRON balance adapters; Solana and the others are stubs
apps/mobile      Flutter shell and the flutter_rust_bridge crate
services/registry  PostgreSQL migrations, seed, and checks
docs/adr         ADR-001
docs/ROADMAP.md  v1 scope and what comes later
```
