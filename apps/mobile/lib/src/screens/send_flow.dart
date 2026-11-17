import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../money.dart';
import '../theme.dart';
import '../vault/wallet_controller.dart';
import '../wallet_api.dart';

class SendFlow extends StatefulWidget {
  const SendFlow({super.key, required this.controller});

  final WalletController controller;

  @override
  State<SendFlow> createState() => _SendFlowState();
}

class _SendFlowState extends State<SendFlow> {
  final _recipient = TextEditingController();
  final _amount = TextEditingController();
  BalanceSnapshot? _balance;
  FeeQuote? _quote;
  bool _review = false;
  bool _busy = false;
  bool _quoting = false;
  String? _error;
  String? _txHash;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recipient.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final address = widget.controller.session?.address;
    if (address == null) {
      return;
    }
    try {
      final balance = await widget.controller.api.sepoliaBalance(
        address: address,
        rpcUrl: '',
      );
      if (mounted) {
        setState(() => _balance = balance);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
      }
    }
  }

  void _scheduleQuote() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _quoteNow);
  }

  Future<void> _quoteNow() async {
    final from = widget.controller.session?.address;
    final to = normalizeEvmAddress(_recipient.text);
    final amount = _amount.text.trim().isEmpty ? '0' : _amount.text.trim();
    if (from == null || to == null || ethToWei(amount) == null) {
      if (mounted) {
        setState(() => _quote = null);
      }
      return;
    }
    setState(() => _quoting = true);
    try {
      final quote = await widget.controller.api.quoteSepoliaTransfer(
        from: from,
        to: to,
        amountEth: amount,
        rpcUrl: '',
      );
      if (mounted) {
        setState(() => _quote = quote);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _quote = null;
          _error = friendlyError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _quoting = false);
      }
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        showCofinexMessage(context, 'Clipboard is empty.', error: true);
      }
      return;
    }
    _recipient.text = text;
    setState(() => _error = null);
    _scheduleQuote();
  }

  Future<void> _max() async {
    final balance = _balance;
    if (balance == null) {
      return;
    }
    await _quoteNow();
    final quote = _quote;
    if (quote == null) {
      setState(() => _error = 'Could not estimate the network fee.');
      return;
    }
    final spendable = spendableWei(balance.baseUnits, quote.maxFeeWei);
    _amount.text = weiToEth(spendable.toString());
    setState(() => _error = null);
    _scheduleQuote();
  }

  Future<void> _openReview() async {
    final to = normalizeEvmAddress(_recipient.text);
    final wei = ethToWei(_amount.text.trim());
    if (to == null) {
      setState(() => _error = 'Enter a valid Ethereum address.');
      return;
    }
    if (wei == null || wei == '0') {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    await _quoteNow();
    final balance = _balance;
    final quote = _quote;
    if (balance != null && quote != null) {
      final spendable = spendableWei(balance.baseUnits, quote.maxFeeWei);
      if (BigInt.parse(wei) > spendable) {
        setState(
          () => _error =
              'Amount plus network fee is more than your Sepolia balance.',
        );
        return;
      }
    }
    setState(() {
      _error = null;
      _review = true;
    });
  }

  Future<void> _confirm() async {
    final session = widget.controller.session;
    final to = normalizeEvmAddress(_recipient.text);
    if (session == null || to == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.controller.api.sendSepoliaEth(
        mnemonic: session.mnemonic,
        to: to,
        amountEth: _amount.text.trim(),
        rpcUrl: '',
      );
      await widget.controller.recordSend(
        hash: receipt.txHash,
        to: to,
        amountEth: _amount.text.trim(),
      );
      if (mounted) {
        setState(() => _txHash = receipt.txHash);
        showCofinexMessage(context, 'Submitted to Sepolia');
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_txHash != null) {
              Navigator.pop(context);
            } else if (_review) {
              setState(() => _review = false);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: _txHash != null
                ? _submitted()
                : _review
                ? _reviewBody()
                : _form(),
          ),
        ),
      ),
    );
  }

  List<Widget> _form() {
    final status = checkEvmAddress(_recipient.text);
    final balance = _balance;
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CofinexColors.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: CofinexColors.cardHigh,
              child: Text('Ξ', style: TextStyle(color: CofinexColors.teal)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ETH',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Text(
                    'on Sepolia',
                    style: TextStyle(color: CofinexColors.muted),
                  ),
                  Text(
                    balance == null
                        ? 'Available …'
                        : 'Available ${balance.display} ETH',
                    style: const TextStyle(color: CofinexColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Text('To', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      TextField(
        key: const Key('send-recipient'),
        controller: _recipient,
        autocorrect: false,
        onChanged: (_) {
          setState(() => _error = null);
          _scheduleQuote();
        },
        decoration: InputDecoration(
          hintText: '0x…',
          errorText: switch (status) {
            AddressStatus.empty || AddressStatus.valid => null,
            AddressStatus.invalid => 'Enter a valid Ethereum address',
            AddressStatus.badChecksum => 'Checksum does not match',
          },
          suffixIcon: IconButton(
            key: const Key('send-paste'),
            icon: const Icon(Icons.content_paste),
            onPressed: _paste,
          ),
        ),
      ),
      if (widget.controller.recentRecipients.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final recent in widget.controller.recentRecipients)
              ActionChip(
                label: Text(shortAddress(recent)),
                onPressed: () {
                  _recipient.text = recent;
                  setState(() => _error = null);
                  _scheduleQuote();
                },
              ),
          ],
        ),
      ],
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Amount',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            key: const Key('send-max'),
            onPressed: _max,
            child: const Text('Max'),
          ),
        ],
      ),
      TextField(
        key: const Key('send-amount'),
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) {
          setState(() => _error = null);
          _scheduleQuote();
        },
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        decoration: const InputDecoration(hintText: '0', suffixText: 'ETH'),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'USD price arrives later',
          style: TextStyle(color: CofinexColors.muted),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _quoting
            ? 'Estimating network fee…'
            : _quote == null
            ? 'Network fee appears after a valid address'
            : 'Estimated max fee ${_quote!.maxFeeDisplay} ETH',
        key: const Key('send-fee-preview'),
        style: const TextStyle(color: CofinexColors.muted),
      ),
      InlineError(message: _error),
      const SizedBox(height: 16),
      CofinexButton(
        key: const Key('send-next'),
        label: 'Review',
        onPressed: _openReview,
      ),
    ];
  }

  List<Widget> _reviewBody() {
    final to = normalizeEvmAddress(_recipient.text) ?? _recipient.text.trim();
    final quote = _quote;
    return [
      const Text(
        'Review',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 12),
      _line('From', 'Account 1'),
      _line('To', shortAddress(to)),
      _line('Amount', '${_amount.text.trim()} ETH'),
      _line('Network', 'Sepolia'),
      _line(
        'Estimated network fee',
        quote == null ? '—' : '${quote.maxFeeDisplay} ETH',
        valueKey: const Key('review-fee'),
      ),
      if (quote != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Up to ${quote.gasLimit} gas. Worst case from the current base fee.',
            style: const TextStyle(color: CofinexColors.muted, fontSize: 12),
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        'This broadcasts a Sepolia testnet transaction. Mainnet sends are disabled.',
        style: TextStyle(color: CofinexColors.warning, height: 1.35),
      ),
      InlineError(message: _error),
      const SizedBox(height: 16),
      CofinexButton(
        key: const Key('review-confirm'),
        label: 'Confirm send',
        busy: _busy,
        onPressed: quote == null || _quoting ? null : _confirm,
      ),
    ];
  }

  List<Widget> _submitted() {
    return [
      const Icon(Icons.check_circle, color: CofinexColors.teal, size: 64),
      const SizedBox(height: 12),
      const Text(
        'Submitted to Sepolia',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'The transaction was broadcast. It can take a moment to show in activity.',
        style: TextStyle(color: CofinexColors.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      SelectableText(_txHash ?? '', key: const Key('send-tx-hash')),
      const SizedBox(height: 16),
      CofinexButton(
        key: const Key('send-done'),
        label: 'Done',
        onPressed: () => Navigator.pop(context),
      ),
    ];
  }

  Widget _line(String label, String value, {Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: CofinexColors.muted),
            ),
          ),
          Flexible(
            child: Text(value, key: valueKey, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
