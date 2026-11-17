import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'rust/api/wallet.dart' as rust;
import 'rust/frb_generated.dart';
import 'sepolia_rpc.dart';
import 'wallet_api.dart';

/// Live adapter. Loads `libcofinex_wallet_bridge`.
///
/// Android and iOS use the library packaged into the app (its default name).
/// Desktop builds still honor `COFINEX_RUST_LIB`, then a workspace `target/`
/// path.
class RustWalletApi implements WalletApi {
  Future<void>? _ready;

  Future<void> _ensureReady() {
    return _ready ??= _init();
  }

  Future<void> _init() async {
    final path = _libraryPath();
    await RustLib.init(
      externalLibrary: path == null ? null : ExternalLibrary.open(path),
    );
  }

  String _rpcUrl(String field) {
    final mobile = Platform.isAndroid || Platform.isIOS;
    return resolveSepoliaRpcUrl(
      field,
      environmentUrl: mobile
          ? null
          : Platform.environment['COFINEX_SEPOLIA_RPC_URL'],
      allowEnvironment: !mobile,
    );
  }

  String? _libraryPath() {
    if (Platform.isAndroid || Platform.isIOS) {
      return null;
    }
    final override = Platform.environment['COFINEX_RUST_LIB'];
    if (override != null && override.isNotEmpty) {
      return override;
    }
    const candidates = <String>[
      '../../target/debug/libcofinex_wallet_bridge.so',
      '../../target/release/libcofinex_wallet_bridge.so',
      'rust/target/debug/libcofinex_wallet_bridge.so',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Future<WalletSnapshot> createTestWallet() async {
    await _ensureReady();
    final created = await rust.createTestWallet();
    return WalletSnapshot(
      mnemonic: created.mnemonic,
      sepoliaAddress: created.sepoliaAddress,
    );
  }

  @override
  Future<WalletSnapshot> importTestWallet(String mnemonic) async {
    await _ensureReady();
    final imported = await rust.importTestWallet(mnemonic: mnemonic);
    return WalletSnapshot(sepoliaAddress: imported.sepoliaAddress);
  }

  @override
  Future<BalanceSnapshot> sepoliaBalance({
    required String address,
    required String rpcUrl,
  }) async {
    await _ensureReady();
    final balance = await rust.sepoliaBalance(
      address: address,
      rpcUrl: _rpcUrl(rpcUrl),
    );
    return BalanceSnapshot(
      symbol: balance.symbol,
      baseUnits: balance.baseUnits,
      display: balance.display,
    );
  }
}
