# Cofinex Wallet mobile shell

Flutter UI for the Cofinex wallet. It talks to the Rust core through flutter_rust_bridge 2.13.0.

The welcome screen offers email sign-in (coming soon; the address is not sent) and a sheet for self-custody, business multisig (coming soon), and restore. Self-custody creates a 12-word phrase, confirms three positions, and opens the home screen. Restore checks each word against the English BIP-39 list. The phrase is sealed in Rust (PBKDF2-HMAC-SHA256, 600,000 iterations, AES-256-GCM) and stored with `flutter_secure_storage`. It is not written as plaintext. Settings can reveal it after the password, or reset the wallet.

Home shows the Sepolia ETH balance from the Rust adapter, with pull to refresh. Send quotes an EIP-1559 fee and broadcasts a signed Sepolia transfer. Swap, buy, fiat prices, and every chain except Sepolia are visible and disabled. Receive shows the address as a QR code.

Setup, the desktop `COFINEX_RUST_LIB` path, Android emulator commands, and the Sepolia-only warning are in the [repository README](../../README.md).

Widget tests use `FakeWalletApi` and `TestVaultCipher`. They do not load the native library and they do not run the production KDF.

```bash
flutter pub get
flutter analyze
flutter test
```
