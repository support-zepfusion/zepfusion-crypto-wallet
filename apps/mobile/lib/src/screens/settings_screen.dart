import 'package:material_ui/material_ui.dart';

import '../money.dart';
import '../theme.dart';
import '../vault/wallet_controller.dart';
import 'create_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final WalletController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final address = controller.session?.address;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              ListTile(
                title: const Text('Account 1'),
                subtitle: Text(address ?? ''),
              ),
              const ListTile(
                title: Text('Network'),
                subtitle: Text('Sepolia testnet. Mainnet sends are disabled.'),
              ),
              ListTile(
                title: const Text('Auto-lock'),
                subtitle: Text(
                  controller.inactivityTimeout == null
                      ? 'Auto-lock is off for this session.'
                      : 'Locks after ${controller.inactivityTimeout!.inSeconds} seconds without activity.',
                ),
              ),
              SwitchListTile(
                key: const Key('biometric-switch'),
                value: controller.biometricEnabled,
                title: const Text('Biometric unlock'),
                subtitle: const Text('Optional. The password still works.'),
                onChanged: (value) => _toggleBiometric(context, value),
              ),
              ListTile(
                key: const Key('reveal-secret'),
                leading: const Icon(
                  Icons.key_outlined,
                  color: CofinexColors.teal,
                ),
                title: const Text('Reveal secret recovery phrase'),
                subtitle: const Text('Requires your password'),
                onTap: () => _reveal(context),
              ),
              const SizedBox(height: 12),
              ListTile(
                key: const Key('reset-wallet'),
                leading: const Icon(
                  Icons.delete_outline,
                  color: CofinexColors.danger,
                ),
                title: const Text(
                  'Reset wallet',
                  style: TextStyle(color: CofinexColors.danger),
                ),
                subtitle: const Text(
                  'Removes the encrypted phrase from this device',
                ),
                onTap: () => _reset(context),
              ),
              const SizedBox(height: 24),
              const Text(
                'Testnet build. This wallet refuses Ethereum mainnet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CofinexColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleBiometric(BuildContext context, bool enabled) async {
    if (!enabled) {
      await controller.setBiometricEnabled(false);
      return;
    }
    if (!context.mounted) {
      return;
    }
    final password = await _askPassword(context, 'Turn on biometric unlock');
    if (password == null) {
      return;
    }
    try {
      await controller.setBiometricEnabled(true, password: password);
    } catch (error) {
      if (context.mounted) {
        showCofinexMessage(context, friendlyError(error), error: true);
      }
    }
  }

  Future<void> _reveal(BuildContext context) async {
    final password = await _askPassword(context, 'Reveal recovery phrase');
    if (password == null || !context.mounted) {
      return;
    }
    try {
      final phrase = await controller.revealMnemonic(password);
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context)
          .push(cofinexRoute(PhraseRevealScreen(phrase: phrase)));
    } catch (error) {
      if (context.mounted) {
        showCofinexMessage(context, friendlyError(error), error: true);
      }
    }
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset wallet?'),
          content: const Text(
            'This deletes the encrypted recovery phrase from this device. Without your written phrase, the funds cannot be recovered.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('reset-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: CofinexColors.danger,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete wallet'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await controller.reset();
    }
  }
}

Future<String?> _askPassword(BuildContext context, String title) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('settings-password'),
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('settings-password-submit'),
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Continue'),
          ),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}

class PhraseRevealScreen extends StatefulWidget {
  const PhraseRevealScreen({super.key, required this.phrase});

  final String phrase;

  @override
  State<PhraseRevealScreen> createState() => _PhraseRevealScreenState();
}

class _PhraseRevealScreenState extends State<PhraseRevealScreen> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final words = widget.phrase.split(RegExp(r'\s+'));
    return Scaffold(
      appBar: AppBar(title: const Text('Secret recovery phrase')),
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Never share these words. Anyone who has them can take your funds.',
                style: TextStyle(color: CofinexColors.warning, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (!_revealed)
                GestureDetector(
                  key: const Key('settings-reveal-phrase'),
                  onTap: () => setState(() => _revealed = true),
                  child: Container(
                    height: 180,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CofinexColors.card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Tap to reveal',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else
                PhraseWordGrid(words: words),
            ],
          ),
        ),
      ),
    );
  }
}
