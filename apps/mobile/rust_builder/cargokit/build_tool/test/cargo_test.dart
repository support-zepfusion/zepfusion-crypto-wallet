import 'package:build_tool/src/cargo.dart';
import 'package:test/test.dart';

final _cargoToml = """
[workspace]

[profile.release]
lto = true
panic = "abort"
opt-level = "z"
# strip = "symbols"

[package]
name = "super_native_extensions"
version = "0.1.0"
edition = "2021"
resolver = "2"

[lib]
crate-type = ["cdylib", "staticlib"]
""";

void main() {
  test('parseCargoToml', () {
    final info = CrateInfo.parseManifest(_cargoToml);
    expect(info.packageName, 'super_native_extensions');
    expect(info.libName, 'super_native_extensions');
  });

  test('hyphenated package names use the cargo lib stem', () {
    final hyphenated = CrateInfo.parseManifest('''
[package]
name = "cofinex-wallet-bridge"
version.workspace = true

[lib]
name = "cofinex_wallet_bridge"
crate-type = ["cdylib"]
''');
    expect(hyphenated.packageName, 'cofinex-wallet-bridge');
    expect(hyphenated.libName, 'cofinex_wallet_bridge');

    final implicit = CrateInfo.parseManifest('''
[package]
name = "cofinex-wallet-bridge"
version = "0.1.0"
''');
    expect(implicit.libName, 'cofinex_wallet_bridge');
  });
}
