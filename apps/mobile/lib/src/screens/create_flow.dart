import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bip39.dart';
import '../money.dart';
import '../theme.dart';
import '../vault/wallet_controller.dart';

enum _Step { password, secure, reveal, confirm, success }

class CreateFlow extends StatefulWidget {
  const CreateFlow({
    super.key,
    required this.controller,
    this.quizPositions,
    this.quizSeed,
  });

  final WalletController controller;
  final List<int>? quizPositions;
  final int? quizSeed;

  @override
  State<CreateFlow> createState() => _CreateFlowState();
}

class _CreateFlowState extends State<CreateFlow> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _Step _step = _Step.password;
  bool _terms = false;
  bool _busy = false;
  bool _revealed = false;
  String? _error;
  String? _mnemonic;
  String? _address;
  String _passwordText = '';
  List<int> _positions = const [];
  List<List<String>> _options = const [];
  final Map<int, String> _picks = {};

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  List<String> get _words => _mnemonic?.split(RegExp(r'\s+')) ?? const [];

  Future<void> _continueFromPassword() async {
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
    setState(() {
      _error = null;
      _passwordText = password;
    });
    if (_mnemonic != null) {
      setState(() => _step = _Step.secure);
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await widget.controller.api.createTestWallet();
      final phrase = created.mnemonic;
      if (phrase == null || phrase.trim().isEmpty) {
        throw StateError('The wallet core did not return a recovery phrase.');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _mnemonic = phrase.trim();
        _address = created.sepoliaAddress;
        _step = _Step.secure;
      });
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

  void _prepareQuiz() {
    final words = _words;
    final random = widget.quizSeed == null ? Random() : Random(widget.quizSeed);
    final positions = _pickPositions(words.length, random);
    setState(() {
      _positions = positions;
      _options = [
        for (final index in positions) _pickOptions(words, index, random),
      ];
      _picks.clear();
      _error = null;
      _step = _Step.confirm;
    });
  }

  List<int> _pickPositions(int count, Random random) {
    final fixed = widget.quizPositions;
    if (fixed != null &&
        fixed.length == 3 &&
        fixed.toSet().length == 3 &&
        fixed.every((index) => index >= 0 && index < count)) {
      return List<int>.from(fixed);
    }
    final bag = List<int>.generate(count, (index) => index)..shuffle(random);
    final chosen = bag.take(3).toList()..sort();
    return chosen;
  }

  List<String> _pickOptions(List<String> words, int index, Random random) {
    final correct = words[index];
    final pool = List<String>.from(englishBip39)..shuffle(random);
    final decoys = <String>[];
    for (final word in pool) {
      if (word != correct) {
        decoys.add(word);
      }
      if (decoys.length == 2) {
        break;
      }
    }
    final options = [correct, ...decoys]..shuffle(random);
    return options;
  }

  void _submitQuiz() {
    final words = _words;
    final wrong = _positions.any((index) => _picks[index] != words[index]);
    if (_picks.length < _positions.length || wrong) {
      setState(() => _error = "Those words don't match your recovery phrase.");
      showCofinexMessage(
        context,
        "Those words don't match your recovery phrase.",
        error: true,
      );
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.success;
    });
  }

  Future<void> _finish() async {
    final mnemonic = _mnemonic;
    final address = _address;
    if (mnemonic == null || address == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.saveNewWallet(
        mnemonic: mnemonic,
        password: _passwordText,
        address: address,
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

  Future<void> _copyPhrase() async {
    final phrase = _mnemonic;
    if (phrase == null) {
      return;
    }
    final copy = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Copy recovery phrase?'),
          content: const Text(
            'A copied phrase can be read by other apps. Anyone with these words can take the funds in this wallet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('copy-anyway'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Copy anyway'),
            ),
          ],
        );
      },
    );
    if (copy == true && mounted) {
      await Clipboard.setData(ClipboardData(text: phrase));
      if (mounted) {
        showCofinexMessage(context, 'Copied. Store it offline.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.password => _passwordPage(),
      _Step.secure => _securePage(),
      _Step.reveal => _revealPage(),
      _Step.confirm => _confirmPage(),
      _Step.success => _successPage(),
    };
  }

  Widget _page({
    required String title,
    required List<Widget> children,
    VoidCallback? onBack,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack ?? () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _passwordPage() {
    final strength = scorePassword(_password.text);
    return _page(
      title: 'Create a password',
      children: [
        const Text(
          'This password encrypts your recovery phrase on this device. Cofinex cannot reset it.',
          style: TextStyle(color: CofinexColors.muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('password-field'),
          controller: _password,
          obscureText: true,
          onChanged: (_) => setState(() => _error = null),
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 8),
        _StrengthMeter(strength: strength),
        const SizedBox(height: 12),
        TextField(
          key: const Key('password-confirm-field'),
          controller: _confirm,
          obscureText: true,
          onChanged: (_) => setState(() => _error = null),
          decoration: const InputDecoration(labelText: 'Confirm password'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('terms-checkbox'),
          contentPadding: EdgeInsets.zero,
          value: _terms,
          onChanged: (value) => setState(() {
            _terms = value ?? false;
            _error = null;
          }),
          title: const Text(
            'I understand that Cofinex cannot recover this password or my secret recovery phrase.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        InlineError(message: _error),
        const SizedBox(height: 16),
        CofinexButton(
          key: const Key('password-continue'),
          label: 'Continue',
          busy: _busy,
          onPressed: _continueFromPassword,
        ),
      ],
    );
  }

  Widget _securePage() {
    return _page(
      title: 'Secure your wallet',
      onBack: () => setState(() => _step = _Step.password),
      children: [
        const Text(
          'Your secret recovery phrase is the master key for this self-custody wallet.',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        const _Point(
          icon: Icons.edit_note,
          text: 'Write the 12 words on paper and keep them offline.',
        ),
        const _Point(
          icon: Icons.visibility_off_outlined,
          text: 'Never share them. Cofinex will never ask for them.',
        ),
        const _Point(
          icon: Icons.lock_outline,
          text: 'If you lose the phrase and this device, the funds are gone.',
        ),
        const SizedBox(height: 24),
        CofinexButton(
          key: const Key('secure-continue'),
          label: 'Reveal recovery phrase',
          onPressed: () => setState(() {
            _revealed = false;
            _error = null;
            _step = _Step.reveal;
          }),
        ),
      ],
    );
  }

  Widget _revealPage() {
    final words = _words;
    return _page(
      title: 'Recovery phrase',
      onBack: () => setState(() => _step = _Step.secure),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF3A2A12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Never share these words. Anyone who has them can take your funds.',
            style: TextStyle(color: CofinexColors.warning, height: 1.35),
          ),
        ),
        const SizedBox(height: 16),
        if (!_revealed)
          GestureDetector(
            key: const Key('reveal-phrase'),
            onTap: () {
              cofinexHaptic();
              setState(() => _revealed = true);
            },
            child: Container(
              height: 220,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CofinexColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CofinexColors.line),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    color: CofinexColors.teal,
                    size: 36,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap to reveal',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Make sure no one else can see your screen.',
                    style: TextStyle(color: CofinexColors.muted),
                  ),
                ],
              ),
            ),
          )
        else
          PhraseWordGrid(words: words),
        const SizedBox(height: 12),
        if (_revealed)
          OutlinedButton.icon(
            key: const Key('copy-phrase'),
            onPressed: _copyPhrase,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        const SizedBox(height: 16),
        CofinexButton(
          key: const Key('reveal-continue'),
          label: 'I saved it',
          onPressed: _revealed ? _prepareQuiz : null,
        ),
      ],
    );
  }

  Widget _confirmPage() {
    final words = _words;
    return _page(
      title: 'Confirm phrase',
      onBack: () => setState(() => _step = _Step.reveal),
      children: [
        const Text(
          'Select the correct word for each position.',
          style: TextStyle(color: CofinexColors.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        for (var slot = 0; slot < _positions.length; slot++) ...[
          _QuizQuestion(
            position: _positions[slot],
            options: _options[slot],
            selected: _picks[_positions[slot]],
            onSelect: (word) => setState(() {
              _picks[_positions[slot]] = word;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
        ],
        InlineError(message: _error),
        const SizedBox(height: 8),
        CofinexButton(
          key: const Key('confirm-phrase'),
          label: 'Confirm',
          onPressed: _picks.length == _positions.length && words.isNotEmpty
              ? _submitQuiz
              : null,
        ),
      ],
    );
  }

  Widget _successPage() {
    return _page(
      title: 'Wallet ready',
      onBack: () {},
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.check_circle, color: CofinexColors.teal, size: 72),
        const SizedBox(height: 16),
        Text(
          'Your wallet is ready',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'The recovery phrase is encrypted with your password and stored in this device’s keystore. Sepolia testnet only.',
          style: TextStyle(color: CofinexColors.muted, height: 1.4),
        ),
        InlineError(message: _error),
        const SizedBox(height: 24),
        CofinexButton(
          key: const Key('success-done'),
          label: 'Go to my wallet',
          busy: _busy,
          onPressed: _finish,
        ),
      ],
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final level = switch (strength) {
      PasswordStrength.empty => 0.0,
      PasswordStrength.weak => 0.25,
      PasswordStrength.fair => 0.5,
      PasswordStrength.good => 0.75,
      PasswordStrength.strong => 1.0,
    };
    final color = switch (strength) {
      PasswordStrength.empty || PasswordStrength.weak => CofinexColors.danger,
      PasswordStrength.fair => CofinexColors.warning,
      PasswordStrength.good || PasswordStrength.strong => CofinexColors.teal,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: level == 0 ? 0.02 : level,
            color: color,
            backgroundColor: CofinexColors.cardHigh,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          passwordStrengthLabel(strength),
          key: const Key('password-strength'),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CofinexColors.teal),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }
}

class PhraseWordGrid extends StatelessWidget {
  const PhraseWordGrid({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < words.length; index++)
              SizedBox(
                width: width,
                child: Container(
                  key: Key('phrase-word-$index'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: CofinexColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CofinexColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: CofinexColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        words[index],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuizQuestion extends StatelessWidget {
  const _QuizQuestion({
    required this.position,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final int position;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('quiz-question-$position'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Word #${position + 1}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final word in options)
              ChoiceChip(
                key: Key('quiz-$position-$word'),
                label: Text(word),
                selected: selected == word,
                onSelected: (_) {
                  cofinexHaptic();
                  onSelect(word);
                },
              ),
          ],
        ),
      ],
    );
  }
}
