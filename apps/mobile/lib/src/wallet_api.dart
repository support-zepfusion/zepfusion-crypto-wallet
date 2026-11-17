/// Screen-facing wallet operations.
///
/// Widget tests use [FakeWalletApi]. The running app uses [RustWalletApi],
/// which calls the Rust core through flutter_rust_bridge. Sends are Sepolia only.
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

class FeeQuote {
  const FeeQuote({
    required this.gasLimit,
    required this.maxFeePerGasWei,
    required this.maxPriorityFeePerGasWei,
    required this.maxFeeWei,
    required this.maxFeeDisplay,
  });

  final String gasLimit;
  final String maxFeePerGasWei;
  final String maxPriorityFeePerGasWei;
  final String maxFeeWei;
  final String maxFeeDisplay;
}

class SendReceipt {
  const SendReceipt({required this.txHash});

  final String txHash;
}

abstract class WalletApi {
  Future<WalletSnapshot> createTestWallet();

  Future<WalletSnapshot> importTestWallet(String mnemonic);

  Future<BalanceSnapshot> sepoliaBalance({
    required String address,
    required String rpcUrl,
  });

  /// Worst-case fee for a native Sepolia transfer. `amountEth` may be `0`.
  Future<FeeQuote> quoteSepoliaTransfer({
    required String from,
    required String to,
    required String amountEth,
    required String rpcUrl,
  });

  /// Sign and broadcast native Sepolia ETH. The mnemonic is a secret.
  Future<SendReceipt> sendSepoliaEth({
    required String mnemonic,
    required String to,
    required String amountEth,
    required String rpcUrl,
  });
}
