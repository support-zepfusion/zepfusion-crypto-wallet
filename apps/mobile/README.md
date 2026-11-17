# Cofinex Wallet mobile shell

Flutter UI for the foundation scaffold. It talks to the Rust core through flutter_rust_bridge.

Setup, the `COFINEX_RUST_LIB` path, and the read-only balance warnings are in the [repository README](../../README.md). The home screen lists unified USDT with chain chips. Widget tests use a fake API and do not load the native library:

```bash
flutter pub get
flutter analyze
flutter test
```
