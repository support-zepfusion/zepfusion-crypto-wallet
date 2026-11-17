Builds `libcofinex_wallet_bridge` during `flutter run` and `flutter build apk`.

`cargokit/` is [fzyzcjy/cargokit](https://github.com/fzyzcjy/cargokit) commit `6f7144d192b04075acd73af2656cdebb1d3e4055`, the revision flutter_rust_bridge 2.13.0 vendors. Local edits:

- Cargo is invoked from `apps/mobile/rust` so `rust-toolchain.toml` (channel 1.100.0) applies. The stock tool runs `rustup run stable`.
- `cargo` and `rustup` are resolved from `%USERPROFILE%\.cargo\bin` on Windows and `~/.cargo/bin` elsewhere, then from `PATH`.
- The NDK prebuilt directory is chosen from the host that is actually installed (including `darwin-arm64`).
- Android output is limited to `arm64-v8a` and `x86_64`.
- The copied library name follows `[lib] name` (`cofinex_wallet_bridge`), not the hyphenated package name.
- An installed NDK is recognized by `package.xml` or `source.properties` (Android Studio omits `package.xml`).
- A failed build tool, or a run that does not emit `libcofinex_wallet_bridge.so`, fails the Gradle task.
