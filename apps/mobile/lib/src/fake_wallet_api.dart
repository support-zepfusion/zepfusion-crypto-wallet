import 'money.dart';
import 'wallet_api.dart';

/// In-memory stand-in so widget tests do not load the native library.
class FakeWalletApi implements WalletApi {
  FakeWalletApi({
    this.balanceDisplay = '1.5',
    this.balanceBaseUnits = '1500000000000000000',
    this.feeDisplay = '0.000063',
    this.feeWei = '63000000000000',
    this.phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident',
    this.address = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94',
  });

  final String balanceDisplay;
  final String balanceBaseUnits;
  final String feeDisplay;
  final String feeWei;
  final String phrase;
  final String address;

  int balanceCalls = 0;
  SendReceipt? lastSend;

  @override
  Future<WalletSnapshot> createTestWallet() async {
    return WalletSnapshot(mnemonic: phrase, sepoliaAddress: address);
  }

  @override
  Future<WalletSnapshot> importTestWallet(String mnemonic) async {
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    if (words.length != 12 && words.length != 24) {
      throw StateError('invalid mnemonic');
    }
    return WalletSnapshot(sepoliaAddress: address);
  }

  @override
  Future<BalanceSnapshot> sepoliaBalance({
    required String address,
    required String rpcUrl,
  }) async {
    if (checkEvmAddress(address) != AddressStatus.valid) {
      throw StateError('address is invalid');
    }
    balanceCalls += 1;
    return BalanceSnapshot(
      symbol: 'ETH',
      baseUnits: balanceBaseUnits,
      display: balanceDisplay,
    );
  }

  @override
  Future<FeeQuote> quoteSepoliaTransfer({
    required String from,
    required String to,
    required String amountEth,
    required String rpcUrl,
  }) async {
    if (checkEvmAddress(from) != AddressStatus.valid ||
        checkEvmAddress(to) != AddressStatus.valid) {
      throw StateError('address is invalid');
    }
    if (ethToWei(amountEth) == null) {
      throw StateError('amount is invalid');
    }
    return FeeQuote(
      gasLimit: '21000',
      maxFeePerGasWei: '3000000000',
      maxPriorityFeePerGasWei: '1000000000',
      maxFeeWei: feeWei,
      maxFeeDisplay: feeDisplay,
    );
  }

  @override
  Future<SendReceipt> sendSepoliaEth({
    required String mnemonic,
    required String to,
    required String amountEth,
    required String rpcUrl,
  }) async {
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    if (words.length != 12 && words.length != 24) {
      throw StateError('invalid mnemonic');
    }
    if (checkEvmAddress(to) != AddressStatus.valid) {
      throw StateError('address is invalid');
    }
    final wei = ethToWei(amountEth);
    if (wei == null || wei == '0') {
      throw StateError('amount is invalid');
    }
    final receipt = SendReceipt(txHash: '0x${'ab' * 32}');
    lastSend = receipt;
    return receipt;
  }
}
