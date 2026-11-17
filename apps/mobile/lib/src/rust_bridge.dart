import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'rust/frb_generated.dart';

/// Loads `libcofinex_wallet_bridge` once for every Rust call.
///
/// Android and iOS use the library packaged into the app. Desktop builds still
/// honor `COFINEX_RUST_LIB`, then a workspace `target/` path.
Future<void> ensureRustLib() {
  return _ready ??= _init();
}

Future<void>? _ready;

Future<void> _init() async {
  final path = _libraryPath();
  await RustLib.init(
    externalLibrary: path == null ? null : ExternalLibrary.open(path),
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
