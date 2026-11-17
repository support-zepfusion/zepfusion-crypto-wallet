# Cofinex Wallet

One Wallet. Every Chain. One Seamless Experience.

Non-custodial multichain wallet. Flutter UI, Rust core, chain adapters behind a swappable signer. This repository is the foundation scaffold from [ADR-001](docs/adr/ADR-001-cofinex-wallet-architecture.md). It is testnet-only and not ready for mainnet funds.

## What is built

- Cargo workspace (`crates/keys`, `crates/signer`, `crates/core`, `crates/chains`, `apps/mobile/rust`).
- `ChainAdapter`: derive an address, read a balance, build an unsigned transfer, broadcast a signed transaction, and read transaction status. The same trait covers secp256k1 (Bitcoin, EVM, TRON) and ed25519 (Solana, Sui).
- `Signer`: `LocalSigner` (BIP-39 + BIP-32 / SLIP-0010) is the only implementation. `MpcSigner::two_of_three` is a documented stub that returns "not implemented". Adapters depend on the trait, so replacing the local signer with CGGMP21 (ECDSA) or FROST (EdDSA) does not require adapter changes.
- Secrets sit in `zeroize` buffers. `Debug` redacts mnemonics and private keys. Errors do not echo a recovery phrase.
- One working adapter: Ethereum Sepolia (chain id `11155111`). The RPC URL comes from `COFINEX_SEPOLIA_RPC_URL` or an argument. The adapter checks `eth_chainId` before any other call and embeds that chain id in the EIP-1559 payload, so a mainnet endpoint is refused. Bitcoin, TRON, Solana, and Sui compile and return "not implemented".
- Flutter wallet (`apps/mobile`) on flutter_rust_bridge 2.13.0. Self-custody create and restore, encrypted phrase storage, unlock, Sepolia balance, receive, and a Sepolia ETH send. Email sign-in and business multisig are coming-soon screens.
- Android packaging of that bridge. Gradle builds `libcofinex_wallet_bridge.so` for `arm64-v8a` and `x86_64` with cargokit and NDK `28.2.13676358`. The debug APK is built in CI.
- PostgreSQL token registry (`services/registry`): chains, canonical assets, deployments, verification, and a unified-balance view that excludes testnets. Seed data is native assets plus USDC addresses copied from Circle's published list. Sources are cited in the seed migration. No invented contract addresses.

## What is stubbed

- Email sign-in and the 2-of-3 MPC signer (`MpcSigner::two_of_three` returns "not implemented"). The welcome screen collects an email address and does not send it.
- Business multisig. The setup sheet opens a coming-soon screen.
- Swap and buy. The home actions stay disabled.
- Fiat prices. Balances are shown in the asset's own units.
- Non-Sepolia networks. The network sheet lists them and leaves them disabled.
- An activity indexer. The activity tab shows transfers this install broadcast.
- Bitcoin, TRON, Solana, and Sui balance, build, broadcast, and status.
- Token transfers (the Sepolia adapter sends native ETH only).
- Registry HTTP API, Redis cache, and the signed snapshot.
- Recovery, email transfers, escrow, and cross-chain routing. See [docs/ROADMAP.md](docs/ROADMAP.md).
- iOS packaging is wired through the same cargokit pod (`apps/mobile/rust_builder`) but is not built in CI. Desktop builds still load `libcofinex_wallet_bridge.so` via `COFINEX_RUST_LIB` or a path under the workspace `target/` directory.

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

Creating or restoring a wallet seals the BIP-39 phrase before it is stored. The bridge runs PBKDF2-HMAC-SHA256 (600,000 iterations) and AES-256-GCM, and Flutter writes that payload with `flutter_secure_storage` (Android Keystore). The phrase is not stored in plaintext. Unlock asks for the password again. Optional biometric unlock stores the AES key in the same Keystore and asks `local_auth` before using it. The app locks after 60 seconds without a touch, and again when it returns to the foreground after that idle window. Reset wallet deletes the stored payload. Do not reuse a test phrase on mainnet.

Sepolia is the only network that can send. Quote and broadcast go through the existing `Signer` and `ChainAdapter` (EIP-1559, `LocalSigner`). Bitcoin, TRON, Solana, and Sui stay disabled in the network sheet.

The RPC URL is, in order, `--dart-define=COFINEX_SEPOLIA_RPC_URL`, the desktop `COFINEX_SEPOLIA_RPC_URL` environment variable, or `https://ethereum-sepolia-rpc.publicnode.com`. Android and iOS have no process environment, so the dart-define or the public endpoint is what the Rust adapter receives. Widget tests use a fake API and a test cipher. They do not run the production KDF and they do not load the native library.

## Android

`flutter run` and `flutter build apk` compile the bridge for `arm64-v8a` and `x86_64` with NDK `28.2.13676358`. The app loads `libcofinex_wallet_bridge.so` by that name. Rust stays on channel `1.100.0` (`rust-toolchain.toml`), including the Android targets. The first cargo invocation installs that toolchain.

Install Flutter 3.50.0, the Rustup default (so `cargo` exists), and Android SDK command-line tools. Install NDK `28.2.13676358`, platform `android-36`, and build-tools `36.0.0`. The SDK's default location is `%LOCALAPPDATA%\Android\Sdk` on Windows and `$HOME/Android/Sdk` on Linux. Point `ANDROID_HOME` at it. An x86_64 emulator image is required for `emulator-5554`.

### Linux

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
yes | sdkmanager --licenses
sdkmanager --install \
  "platform-tools" \
  "emulator" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "ndk;28.2.13676358" \
  "system-images;android-35;google_apis;x86_64"
echo no | avdmanager create avd --name cofinex_x86_64 --package "system-images;android-35;google_apis;x86_64" --device pixel
cd apps/mobile
flutter pub get
flutter emulators --launch cofinex_x86_64
flutter run -d emulator-5554
```

Override the Sepolia endpoint at build time:

```bash
flutter run -d emulator-5554 --dart-define=COFINEX_SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
```

A debug APK with both ABIs:

```bash
cd apps/mobile
flutter build apk --debug
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libcofinex_wallet_bridge.so
```

### Windows (PowerShell)

Cargo is resolved from `%USERPROFILE%\.cargo\bin` even when that directory is not on `PATH`. Adding it for the session makes `cargo` available in the shell too.

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\emulator;$env:Path"
cmd /c "echo y| sdkmanager --licenses"
sdkmanager --install "platform-tools" "emulator" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" "system-images;android-35;google_apis;x86_64"
echo no | avdmanager create avd --name cofinex_x86_64 --package "system-images;android-35;google_apis;x86_64" --device pixel
Set-Location apps\mobile
flutter pub get
flutter emulators --launch cofinex_x86_64
flutter run -d emulator-5554
```

Same dart-define as on Linux:

```powershell
flutter run -d emulator-5554 --dart-define=COFINEX_SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
```

Open the app, choose **Other ways to set up**, then **Self-custody wallet**. After the password and the recovery phrase, the home screen shows Account 1, the Sepolia address, and the ETH balance. The encrypted phrase is stored on the device. Unlock with the password on the next launch. Do not reuse the phrase on mainnet.

macOS uses the Linux commands with `ANDROID_HOME` at `$HOME/Library/Android/sdk` when Android Studio created the SDK there. The NDK prebuilt is selected from the host (`darwin-arm64` or `darwin-x86_64`).

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
