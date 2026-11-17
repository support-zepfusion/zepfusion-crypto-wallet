import 'package:material_ui/material_ui.dart';

import 'wallet_api.dart';

/// Testnet shell: create or import a wallet, then read its Sepolia balance.
class WalletHome extends StatefulWidget {
  const WalletHome({super.key, required this.api});

  final WalletApi api;

  @override
  State<WalletHome> createState() => _WalletHomeState();
}

class _WalletHomeState extends State<WalletHome> {
  final _mnemonic = TextEditingController();
  final _rpc = TextEditingController();
  WalletSnapshot? _wallet;
  BalanceSnapshot? _balance;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _mnemonic.dispose();
    _rpc.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create() {
    return _run(() async {
      final wallet = await widget.api.createTestWallet();
      setState(() {
        _wallet = wallet;
        _balance = null;
      });
    });
  }

  Future<void> _import() {
    return _run(() async {
      final wallet = await widget.api.importTestWallet(_mnemonic.text);
      setState(() {
        _wallet = wallet;
        _balance = null;
      });
    });
  }

  Future<void> _refresh() {
    final address = _wallet?.sepoliaAddress;
    if (address == null) {
      setState(() => _error = 'Create or import a wallet first.');
      return Future<void>.value();
    }
    return _run(() async {
      final balance = await widget.api.sepoliaBalance(
        address: address,
        rpcUrl: _rpc.text,
      );
      setState(() => _balance = balance);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    final balance = _balance;
    return Scaffold(
      appBar: AppBar(title: const Text('Cofinex Wallet')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Sepolia testnet only. Do not send mainnet funds. '
                  'This screen is a foundation scaffold.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('create-wallet'),
              onPressed: _busy ? null : _create,
              child: const Text('Create test wallet'),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('mnemonic-field'),
              controller: _mnemonic,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Import recovery phrase',
                helperText: 'English BIP-39 words. Nothing is written to disk.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('import-wallet'),
              onPressed: _busy ? null : _import,
              child: const Text('Import test wallet'),
            ),
            if (wallet != null) ...[
              const SizedBox(height: 24),
              Text(
                'Sepolia address',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(wallet.sepoliaAddress, key: const Key('address')),
              if (wallet.mnemonic != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Test phrase. It is not stored. Do not reuse it on mainnet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(wallet.mnemonic!, key: const Key('mnemonic')),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('rpc-field'),
                controller: _rpc,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Sepolia RPC URL',
                  helperText:
                      'Leave empty to use --dart-define=COFINEX_SEPOLIA_RPC_URL, '
                      'the desktop COFINEX_SEPOLIA_RPC_URL variable, or the public Sepolia endpoint.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const Key('refresh-balance'),
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh Sepolia balance'),
              ),
              if (balance != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${balance.display} ${balance.symbol}',
                  key: const Key('balance'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('${balance.baseUnits} wei'),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const Key('error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
