import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class SetupChoice {
  const SetupChoice({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onEmail,
    required this.onSelfCustody,
    required this.onBusiness,
    required this.onRestore,
  });

  final VoidCallback onEmail;
  final VoidCallback onSelfCustody;
  final VoidCallback onBusiness;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CofinexFrame(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 680;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(),
                    CofinexMark(size: compact ? 72 : 104),
                    SizedBox(height: compact ? 20 : 28),
                    Text(
                      'Cofinex Wallet',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'One Wallet. Every Chain.\nOne Seamless Experience.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CofinexColors.muted,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const Spacer(),
                    CofinexButton(
                      key: const Key('continue-with-email'),
                      label: 'Continue with email',
                      onPressed: onEmail,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('other-ways'),
                      onPressed: () => _openSheet(context),
                      child: const Text('Other ways to set up'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Secured by 2-of-3 MPC — no seed phrase to lose.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CofinexColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 20),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    cofinexHaptic();
    final choices = <SetupChoice>[
      SetupChoice(
        key: const Key('setup-email'),
        icon: Icons.mail_outline,
        title: 'Continue with email',
        subtitle: 'Sign in and set up without a seed phrase.',
        badge: 'Recommended',
        onTap: onEmail,
      ),
      SetupChoice(
        key: const Key('setup-self-custody'),
        icon: Icons.key_outlined,
        title: 'Self-custody wallet',
        subtitle: '12/24-word recovery phrase, for experienced users.',
        onTap: onSelfCustody,
      ),
      SetupChoice(
        key: const Key('setup-business'),
        icon: Icons.work_outline,
        title: 'Business wallet',
        subtitle: 'Multisig with approvers.',
        onTap: onBusiness,
      ),
      SetupChoice(
        key: const Key('setup-restore'),
        icon: Icons.restore,
        title: 'Restore existing wallet',
        subtitle: 'Import a backup or recovery phrase.',
        onTap: onRestore,
      ),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return SafeArea(
          child: SizedBox(
            height: sheetHeight,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    'Other ways to set up',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final choice in choices) ...[
                  _ChoiceTile(choice: choice, sheetContext: sheetContext),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.choice, required this.sheetContext});

  final SetupChoice choice;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CofinexColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: choice.key,
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          cofinexHaptic();
          Navigator.pop(sheetContext);
          choice.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: CofinexColors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(choice.icon, color: CofinexColors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          choice.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (choice.badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: CofinexColors.teal,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              choice.badge!,
                              style: const TextStyle(
                                color: CofinexColors.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      choice.subtitle,
                      style: const TextStyle(
                        color: CofinexColors.muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
