/// Screen-facing wallet operations.
///
/// The Flutter tests use a fake. The running app uses [RustWalletApi], which
/// calls the Rust core through flutter_rust_bridge.
class WalletSnapshot {
  const WalletSnapshot({required this.sepoliaAddress, this.mnemonic});

  /// Present only when the wallet was just created. Treat it as a secret.
  final String? mnemonic;
  final String sepoliaAddress;
}

class BalanceSnapshot {
  const BalanceSnapshot({
    required this.symbol,
    required this.baseUnits,
    required this.display,
  });

  final String symbol;
  final String baseUnits;
  final String display;
}

abstract class WalletApi {
  Future<WalletSnapshot> createTestWallet();

  Future<WalletSnapshot> importTestWallet(String mnemonic);

  Future<BalanceSnapshot> sepoliaBalance({
    required String address,
    required String rpcUrl,
  });
}
