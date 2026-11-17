import 'package:material_ui/material_ui.dart';

import '../money.dart';
import '../theme.dart';
import '../vault/wallet_controller.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});

  final WalletController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.unlockWithPassword(_password.text);
    } catch (error) {
      if (mounted) {
        final message = friendlyError(error);
        setState(() => _error = message);
        showCofinexMessage(context, message, error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _biometric() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.controller.unlockWithBiometric();
      if (!ok && mounted) {
        setState(() => _error = 'Biometric unlock was cancelled.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = widget.controller.addressHint;
    return Scaffold(
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            children: [
              const Center(child: CofinexMark(size: 72)),
              const SizedBox(height: 24),
              Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                address == null
                    ? 'Unlock Cofinex Wallet'
                    : 'Account 1 · ${shortAddress(address)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: CofinexColors.muted),
              ),
              const SizedBox(height: 28),
              TextField(
                key: const Key('unlock-password'),
                controller: _password,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _unlock(),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              InlineError(message: _error),
              const SizedBox(height: 16),
              CofinexButton(
                key: const Key('unlock-submit'),
                label: 'Unlock',
                busy: _busy,
                onPressed: _unlock,
              ),
              if (widget.controller.biometricEnabled) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('unlock-biometric'),
                  onPressed: _busy ? null : _biometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock with biometrics'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
