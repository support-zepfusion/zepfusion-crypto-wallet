import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../money.dart';
import '../theme.dart';
import '../vault/wallet_controller.dart';
import '../wallet_api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onReceive,
    required this.onSettings,
  });

  final WalletController controller;
  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BalanceSnapshot? _balance;
  bool _loading = true;
  bool _ethExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final address = widget.controller.session?.address;
    if (address == null) {
      return;
    }
    setState(() {
      _loading = _balance == null;
      _error = null;
    });
    try {
      final balance = await widget.controller.api.sepoliaBalance(
        address: address,
        rpcUrl: '',
      );
      if (mounted) {
        setState(() {
          _balance = balance;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        final message = friendlyError(error);
        setState(() {
          _error = message;
          _loading = false;
        });
        showCofinexMessage(context, message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final session = widget.controller.session;
    final address = session?.address ?? '';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: CofinexFrame(
            maxWidth: 560,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TopChip(
                          buttonKey: const Key('account-selector'),
                          title: 'Account 1',
                          subtitle: address.isEmpty
                              ? ''
                              : shortAddress(address),
                          onTap: () => _accountSheet(context, address),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TopChip(
                        buttonKey: const Key('network-selector'),
                        title: 'Sepolia',
                        subtitle: 'Testnet',
                        onTap: () => _networkSheet(context),
                      ),
                      IconButton(
                        key: const Key('settings-button'),
                        onPressed: widget.onSettings,
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: NestedScrollView(
                    headerSliverBuilder: (context, inner) => [
                      SliverToBoxAdapter(child: _balanceHeader()),
                      SliverToBoxAdapter(child: _actions()),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _TabHeader(),
                      ),
                    ],
                    body: TabBarView(children: [_tokens(), _activity()]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceHeader() {
    final balance = _balance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total balance',
            style: TextStyle(color: CofinexColors.muted),
          ),
          const SizedBox(height: 6),
          if (_loading && balance == null)
            const SkeletonBox(height: 48, width: 180)
          else
            Text(
              balance == null ? '—' : balance.display,
              key: const Key('home-balance'),
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            balance == null ? 'ETH on Sepolia' : '${balance.symbol} on Sepolia',
            style: const TextStyle(color: CofinexColors.muted),
          ),
          const Text(
            'USD value arrives later',
            style: TextStyle(color: CofinexColors.muted, fontSize: 13),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: CofinexColors.danger),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundAction(
            buttonKey: const Key('action-send'),
            icon: Icons.arrow_upward,
            label: 'Send',
            onPressed: widget.onSend,
          ),
          _RoundAction(
            buttonKey: const Key('action-receive'),
            icon: Icons.arrow_downward,
            label: 'Receive',
            onPressed: widget.onReceive,
          ),
          const _RoundAction(
            buttonKey: Key('action-swap'),
            icon: Icons.swap_horiz,
            label: 'Swap',
            soon: true,
          ),
          const _RoundAction(
            buttonKey: Key('action-buy'),
            icon: Icons.add_card,
            label: 'Buy',
            soon: true,
          ),
        ],
      ),
    );
  }

  Widget _tokens() {
    final balance = _balance;
    return RefreshIndicator(
      key: const Key('token-refresh'),
      onRefresh: _refresh,
      child: ListView(
        key: const Key('token-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Material(
            color: CofinexColors.card,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: const Key('token-eth'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _ethExpanded = !_ethExpanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const _AssetBadge(label: 'ETH'),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ETH',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Ethereum',
                                style: TextStyle(color: CofinexColors.muted),
                              ),
                            ],
                          ),
                        ),
                        if (_loading && balance == null)
                          const SkeletonBox(height: 18, width: 72)
                        else
                          Text(
                            balance == null ? '—' : '${balance.display} ETH',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    if (_ethExpanded) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ChainChip(
                          key: const Key('token-eth-chains'),
                          label: 'Sepolia',
                          detail: balance == null
                              ? '—'
                              : '${balance.display} ETH',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activity() {
    final items = widget.controller.activity;
    if (items.isEmpty) {
      return ListView(
        key: const Key('activity-empty'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 48),
          Icon(
            Icons.receipt_long_outlined,
            color: CofinexColors.muted,
            size: 42,
          ),
          SizedBox(height: 12),
          Text(
            'No activity yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Sepolia transfers you send will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CofinexColors.muted, height: 1.4),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          key: Key('activity-$index'),
          tileColor: CofinexColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Sent ${item.amountEth} ETH'),
          subtitle: Text('To ${shortAddress(item.to)}'),
          trailing: const Icon(Icons.north_east, color: CofinexColors.teal),
        );
      },
    );
  }

  void _accountSheet(BuildContext context, String address) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Accounts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: CofinexColors.teal,
                    child: Text(
                      '1',
                      style: TextStyle(color: CofinexColors.ink),
                    ),
                  ),
                  title: const Text('Account 1'),
                  subtitle: Text(address, key: const Key('home-address')),
                  trailing: IconButton(
                    key: const Key('copy-address'),
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: address));
                      if (!mounted) {
                        return;
                      }
                      showCofinexMessage(this.context, 'Address copied');
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
                const Text(
                  'Additional accounts arrive later.',
                  style: TextStyle(color: CofinexColors.muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _networkSheet(BuildContext context) {
    const networks = <(String, String, bool)>[
      ('Sepolia', 'Ethereum testnet', true),
      ('Ethereum', 'Mainnet disabled', false),
      ('Bitcoin', 'Coming soon', false),
      ('TRON', 'Coming soon', false),
      ('BNB Smart Chain', 'Coming soon', false),
      ('Polygon', 'Coming soon', false),
      ('Solana', 'Coming soon', false),
      ('Sui', 'Coming soon', false),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'Network',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              for (final network in networks)
                ListTile(
                  enabled: network.$3,
                  title: Text(network.$1),
                  subtitle: Text(network.$2),
                  trailing: network.$3
                      ? const Icon(Icons.check, color: CofinexColors.teal)
                      : null,
                  onTap: network.$3 ? () => Navigator.pop(context) : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TopChip extends StatelessWidget {
  const _TopChip({
    required this.buttonKey,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key buttonKey;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CofinexColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          cofinexHaptic();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                subtitle,
                style: const TextStyle(
                  color: CofinexColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.buttonKey,
    required this.icon,
    required this.label,
    this.onPressed,
    this.soon = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !soon;
    final color = enabled ? CofinexColors.teal : CofinexColors.muted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: soon ? '$label, soon' : label,
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(40),
        onTap: enabled
            ? () {
                cofinexHaptic();
                onPressed!();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: enabled
                          ? CofinexColors.teal.withValues(alpha: 0.14)
                          : CofinexColors.card,
                      border: Border.all(
                        color: enabled
                            ? CofinexColors.teal
                            : CofinexColors.line,
                      ),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  if (soon)
                    const Positioned(
                      right: -6,
                      top: -4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CofinexColors.cardHigh,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          child: Text(
                            'Soon',
                            style: TextStyle(
                              fontSize: 9,
                              color: CofinexColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetBadge extends StatelessWidget {
  const _AssetBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: CofinexColors.cardHigh,
        shape: BoxShape.circle,
      ),
      child: Text(
        label.substring(0, 1),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: CofinexColors.teal,
        ),
      ),
    );
  }
}

class _ChainChip extends StatelessWidget {
  const _ChainChip({super.key, required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CofinexColors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label · $detail',
        style: const TextStyle(
          color: CofinexColors.teal,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return const ColoredBox(
      color: CofinexColors.navy,
      child: TabBar(
        tabs: [
          Tab(key: Key('tab-tokens'), text: 'Tokens'),
          Tab(key: Key('tab-activity'), text: 'Activity'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}
