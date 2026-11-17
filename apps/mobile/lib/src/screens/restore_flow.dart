import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bip39.dart';
import '../money.dart';
import '../theme.dart';
import '../vault/wallet_controller.dart';

class RestoreFlow extends StatefulWidget {
  const RestoreFlow({super.key, required this.controller});

  final WalletController controller;

  @override
  State<RestoreFlow> createState() => _RestoreFlowState();
}

class _RestoreFlowState extends State<RestoreFlow> {
  final _paste = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  int _length = 12;
  bool _onPassword = false;
  bool _terms = false;
  bool _busy = false;
  String? _error;
  late List<TextEditingController> _wordControllers;

  @override
  void initState() {
    super.initState();
    _wordControllers = List.generate(12, (_) => TextEditingController());
  }

  List<String> get _words => [
    for (final controller in _wordControllers)
      controller.text.trim().toLowerCase(),
  ];

  @override
  void dispose() {
    _paste.dispose();
    _password.dispose();
    _confirm.dispose();
    for (final controller in _wordControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setLength(int length) {
    setState(() {
      if (length > _wordControllers.length) {
        _wordControllers.addAll(
          List.generate(
            length - _wordControllers.length,
            (_) => TextEditingController(),
          ),
        );
      } else if (length < _wordControllers.length) {
        for (final extra in _wordControllers.sublist(length)) {
          extra.dispose();
        }
        _wordControllers = _wordControllers.sublist(0, length);
      }
      _length = length;
      _error = null;
    });
  }

  void _applyPaste(String raw) {
    final parts = splitPhrase(raw);
    final length = parts.length == 24 || parts.length == 12
        ? parts.length
        : _length;
    _setLength(length);
    for (var index = 0; index < _wordControllers.length; index++) {
      _wordControllers[index].text = index < parts.length ? parts[index] : '';
    }
  }

  void _continueWords() {
    final errors = phraseWordErrors(_words, expected: _length);
    if (errors.any((error) => error != null)) {
      setState(() => _error = 'Check the highlighted words.');
      return;
    }
    setState(() {
      _error = null;
      _onPassword = true;
    });
  }

  Future<void> _finish() async {
    final password = _password.text;
    if (!passwordIsAcceptable(password)) {
      setState(
        () => _error =
            'Use at least 8 characters and mix two kinds of characters.',
      );
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (!_terms) {
      setState(
        () => _error =
            'Confirm that you understand Cofinex cannot recover this password.',
      );
      return;
    }
    final phrase = _words.join(' ');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final imported = await widget.controller.api.importTestWallet(phrase);
      await widget.controller.saveNewWallet(
        mnemonic: phrase,
        password: password,
        address: imported.sepoliaAddress,
      );
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

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (mounted) {
        showCofinexMessage(context, 'Clipboard is empty.', error: true);
      }
      return;
    }
    _paste.text = text;
    _applyPaste(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restore wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_onPassword) {
              setState(() => _onPassword = false);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: _onPassword ? _passwordChildren() : _wordChildren(),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: _onPassword
              ? CofinexButton(
                  key: const Key('restore-finish'),
                  label: 'Restore wallet',
                  busy: _busy,
                  onPressed: _finish,
                )
              : CofinexButton(
                  key: const Key('restore-continue'),
                  label: 'Continue',
                  onPressed: _continueWords,
                ),
        ),
      ),
    );
  }

  List<Widget> _wordChildren() {
    final errors = phraseWordErrors(_words, expected: _length);
    return [
      const Text(
        'Enter your 12 or 24 word recovery phrase. Each word is checked against the BIP-39 list.',
        style: TextStyle(color: CofinexColors.muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 12, label: Text('12 words'), enabled: true),
          ButtonSegment(value: 24, label: Text('24 words')),
        ],
        selected: {_length},
        onSelectionChanged: (value) => _setLength(value.first),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('restore-phrase'),
        controller: _paste,
        minLines: 2,
        maxLines: 4,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: _applyPaste,
        decoration: const InputDecoration(
          labelText: 'Paste recovery phrase',
          helperText: 'Or type each word below.',
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('restore-paste'),
          onPressed: _pasteClipboard,
          child: const Text('Paste from clipboard'),
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < _length; index++)
                SizedBox(
                  width: width,
                  child: TextField(
                    key: Key('restore-word-$index'),
                    controller: _wordControllers[index],
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      labelText: '${index + 1}',
                      errorText: _words[index].isEmpty ? null : errors[index],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      InlineError(message: _error),
    ];
  }

  List<Widget> _passwordChildren() {
    return [
      const Text(
        'Create a password for this device. It encrypts the phrase you just entered.',
        style: TextStyle(color: CofinexColors.muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('restore-password'),
        controller: _password,
        obscureText: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'New password'),
      ),
      const SizedBox(height: 8),
      _miniStrength(_password.text),
      const SizedBox(height: 12),
      TextField(
        key: const Key('restore-password-confirm'),
        controller: _confirm,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Confirm password'),
      ),
      CheckboxListTile(
        key: const Key('restore-terms'),
        contentPadding: EdgeInsets.zero,
        value: _terms,
        onChanged: (value) => setState(() => _terms = value ?? false),
        title: const Text(
          'I understand that Cofinex cannot recover this password or my secret recovery phrase.',
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      InlineError(message: _error),
    ];
  }

  Widget _miniStrength(String value) {
    final strength = scorePassword(value);
    return Text(
      passwordStrengthLabel(strength),
      key: const Key('restore-strength'),
      style: const TextStyle(color: CofinexColors.muted, fontSize: 12),
    );
  }
}
