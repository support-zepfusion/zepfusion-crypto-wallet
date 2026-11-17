import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../money.dart';
import '../theme.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, required this.address});

  final String address;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  bool _copied = false;

  Future<void> _copy() async {
    setState(() => _copied = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.address));
    } catch (_) {
      // The button state already confirms the tap. A missing clipboard
      // channel should not trap the address on screen.
    }
    if (!mounted) {
      return;
    }
    showCofinexMessage(context, 'Address copied');
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Cofinex Wallet Sepolia address\n${widget.address}\n\nTestnet only. Do not send mainnet funds.',
        ),
      );
    } catch (error) {
      if (mounted) {
        showCofinexMessage(context, friendlyError(error), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A2A12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Sepolia testnet only. Send only Sepolia ETH to this address. Mainnet assets sent here will not appear, and this wallet cannot recover them.',
                  key: Key('receive-warning'),
                  style: TextStyle(color: CofinexColors.warning, height: 1.4),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: widget.address,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF07111F),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF07111F),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Account 1 · Sepolia',
                textAlign: TextAlign.center,
                style: TextStyle(color: CofinexColors.muted),
              ),
              const SizedBox(height: 6),
              SelectableText(
                widget.address,
                key: const Key('receive-address'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('receive-copy'),
                      onPressed: _copy,
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(_copied ? 'Copied' : 'Copy'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('receive-share'),
                      onPressed: _share,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
