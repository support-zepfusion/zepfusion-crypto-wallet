import 'package:material_ui/material_ui.dart';

import 'wallet_api.dart';

/// Test wallet shell: create or import a wallet, then read balances.
///
/// Unified assets are read-only. Signing stays on Sepolia.
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
  String? _phrase;
  BalanceSnapshot? _balance;
  List<UnifiedAssetSnapshot> _assets = const [];
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
        _phrase = wallet.mnemonic;
        _balance = null;
        _assets = const [];
      });
    });
  }

  Future<void> _import() {
    return _run(() async {
      final wallet = await widget.api.importTestWallet(_mnemonic.text);
      setState(() {
        _wallet = wallet;
        _phrase = _mnemonic.text.trim();
        _balance = null;
        _assets = const [];
      });
    });
  }

  Future<void> _refreshUnified() {
    final phrase = _phrase;
    if (phrase == null || phrase.isEmpty) {
      setState(() => _error = 'Create or import a wallet first.');
      return Future<void>.value();
    }
    return _run(() async {
      final assets = await widget.api.unifiedAssets(mnemonic: phrase);
      setState(() => _assets = assets);
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
                  'Read-only balances. Signing stays on Sepolia. '
                  'Do not send mainnet funds.',
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
              Text('Sepolia address', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              SelectableText(
                wallet.sepoliaAddress,
                key: const Key('address'),
              ),
              if (wallet.mnemonic != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Test phrase. It is not stored. Do not reuse it on mainnet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(wallet.mnemonic!, key: const Key('mnemonic')),
              ],
              const SizedBox(height: 24),
              Text('Unified assets', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'One total per asset. Chain chips are the registry deployments. '
                'Testnet balances are not added to a mainnet total.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const Key('refresh-unified'),
                onPressed: _busy ? null : _refreshUnified,
                child: const Text('Refresh unified assets'),
              ),
              if (_assets.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No unified balances loaded yet.'),
                )
              else
                ..._assets.map((asset) => _AssetCard(asset: asset)),
              const SizedBox(height: 24),
              TextField(
                key: const Key('rpc-field'),
                controller: _rpc,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Sepolia RPC URL',
                  helperText: 'Leave empty to use COFINEX_SEPOLIA_RPC_URL.',
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

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset});

  final UnifiedAssetSnapshot asset;

  @override
  Widget build(BuildContext context) {
    final total = asset.display == null
        ? 'Balance unavailable'
        : '${asset.display} ${asset.symbol}';
    final headline = asset.complete ? total : '$total · incomplete';
    return Card(
      key: Key('asset-${asset.symbol}'),
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        key: Key('expand-${asset.symbol}'),
        title: Text(asset.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, key: Key('asset-total-${asset.symbol}')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chain in asset.chains)
                  Chip(
                    key: Key('chip-${asset.symbol}-${chain.chainId}'),
                    label: Text(
                      chain.display == null
                          ? chain.label
                          : '${chain.label} ${chain.display}',
                    ),
                  ),
              ],
            ),
          ],
        ),
        children: [
          for (final chain in asset.chains)
            ListTile(
              key: Key('chain-${asset.symbol}-${chain.chainId}'),
              title: Text(chain.label),
              subtitle: Text(
                chain.error ??
                    '${chain.display} ${asset.symbol}'
                        '${chain.baseUnits == null ? '' : '\n${chain.baseUnits} base units'}',
              ),
            ),
        ],
      ),
    );
  }
}
