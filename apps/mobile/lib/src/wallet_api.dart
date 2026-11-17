import 'dart:convert';

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

/// One chain inside a unified asset. Amounts are decimal strings.
class ChainHoldingSnapshot {
  const ChainHoldingSnapshot({
    required this.chainId,
    required this.label,
    required this.decimals,
    this.address,
    this.contract,
    this.baseUnits,
    this.display,
    this.error,
  });

  final String chainId;
  final String label;
  final String? address;
  final String? contract;
  final int decimals;
  final String? baseUnits;
  final String? display;
  final String? error;

  factory ChainHoldingSnapshot.fromJson(Map<String, dynamic> json) {
    return ChainHoldingSnapshot(
      chainId: json['chainId'] as String,
      label: json['label'] as String,
      address: json['address'] as String?,
      contract: json['contract'] as String?,
      decimals: json['decimals'] as int,
      baseUnits: json['baseUnits'] as String?,
      display: json['display'] as String?,
      error: json['error'] as String?,
    );
  }
}

/// One canonical asset, with a total and a per-chain breakdown.
class UnifiedAssetSnapshot {
  const UnifiedAssetSnapshot({
    required this.assetId,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.complete,
    required this.chains,
    this.totalBaseUnits,
    this.display,
  });

  final String assetId;
  final String symbol;
  final String name;
  final int decimals;
  final String? totalBaseUnits;
  final String? display;
  final bool complete;
  final List<ChainHoldingSnapshot> chains;

  factory UnifiedAssetSnapshot.fromJson(Map<String, dynamic> json) {
    final chains = json['chains'] as List<dynamic>;
    return UnifiedAssetSnapshot(
      assetId: json['assetId'] as String,
      symbol: json['symbol'] as String,
      name: json['name'] as String,
      decimals: json['decimals'] as int,
      totalBaseUnits: json['totalBaseUnits'] as String?,
      display: json['display'] as String?,
      complete: json['complete'] as bool,
      chains: chains
          .map(
            (item) => ChainHoldingSnapshot.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

/// Decode the JSON produced by the Rust `unified_assets` function.
List<UnifiedAssetSnapshot> parseUnifiedAssets(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('portfolio response is not an object');
  }
  final assets = decoded['assets'];
  if (assets is! List<dynamic>) {
    throw const FormatException('portfolio response has no assets');
  }
  return assets
      .map((item) => UnifiedAssetSnapshot.fromJson(item as Map<String, dynamic>))
      .toList();
}

abstract class WalletApi {
  Future<WalletSnapshot> createTestWallet();

  Future<WalletSnapshot> importTestWallet(String mnemonic);

  Future<BalanceSnapshot> sepoliaBalance({
    required String address,
    required String rpcUrl,
  });

  /// Read-only unified balances. `mnemonic` is used to derive addresses and
  /// is not retained by the API.
  Future<List<UnifiedAssetSnapshot>> unifiedAssets({required String mnemonic});
}
