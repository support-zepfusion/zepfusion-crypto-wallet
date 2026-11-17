# Cofinex Wallet mobile shell

Flutter UI for the foundation scaffold. It talks to the Rust core through flutter_rust_bridge.

Setup, the desktop `COFINEX_RUST_LIB` path, Android emulator commands, and the Sepolia-only warning are in the [repository README](../../README.md). Widget tests use a fake API and do not load the native library:

```bash
flutter pub get
flutter analyze
flutter test
```
