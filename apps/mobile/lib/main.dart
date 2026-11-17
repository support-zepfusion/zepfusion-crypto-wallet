import 'package:material_ui/material_ui.dart';

import 'src/rust_wallet_api.dart';
import 'src/wallet_home.dart';

void main() {
  runApp(const CofinexApp());
}

class CofinexApp extends StatelessWidget {
  const CofinexApp({super.key, this.home});

  /// Widget tests pass a home that uses a fake API. The process default
  /// talks to the Rust core.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cofinex Wallet',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
        useMaterial3: true,
      ),
      home: home ?? WalletHome(api: RustWalletApi()),
    );
  }
}
