import 'dart:io';

import 'rust/api/wallet.dart' as rust;
import 'rust_bridge.dart';
import 'sepolia_rpc.dart';
import 'wallet_api.dart';

/// Live adapter over the Rust core.
class RustWalletApi implements WalletApi {
  String _rpcUrl(String field) {
    final mobile = Platform.isAndroid || Platform.isIOS;
    return resolveSepoliaRpcUrl(
      field,
      environmentUrl: mobile
          ? null
          : Platform.environment['COFINEX_SEPOLIA_RPC_URL'],
      allowEnvironment: !mobile,
    );
  }

  @override
  Future<WalletSnapshot> createTestWallet() async {
    await ensureRustLib();
    final created = await rust.createTestWallet();
    return WalletSnapshot(
      mnemonic: created.mnemonic,
      sepoliaAddress: created.sepoliaAddress,
    );
  }

  @override
  Future<WalletSnapshot> importTestWallet(String mnemonic) async {
    await ensureRustLib();
    final imported = await rust.importTestWallet(mnemonic: mnemonic);
    return WalletSnapshot(sepoliaAddress: imported.sepoliaAddress);
  }

  @override
  Future<BalanceSnapshot> sepoliaBalance({
    required String address,
    required String rpcUrl,
  }) async {
    await ensureRustLib();
    final balance = await rust.sepoliaBalance(
      address: address,
      rpcUrl: _rpcUrl(rpcUrl),
    );
    return BalanceSnapshot(
      symbol: balance.symbol,
      baseUnits: balance.baseUnits,
      display: balance.display,
    );
  }

  @override
  Future<FeeQuote> quoteSepoliaTransfer({
    required String from,
    required String to,
    required String amountEth,
    required String rpcUrl,
  }) async {
    await ensureRustLib();
    final quote = await rust.quoteSepoliaTransfer(
      from: from,
      to: to,
      amountEth: amountEth,
      rpcUrl: _rpcUrl(rpcUrl),
    );
    return FeeQuote(
      gasLimit: quote.gasLimit,
      maxFeePerGasWei: quote.maxFeePerGasWei,
      maxPriorityFeePerGasWei: quote.maxPriorityFeePerGasWei,
      maxFeeWei: quote.maxFeeWei,
      maxFeeDisplay: quote.maxFeeDisplay,
    );
  }

  @override
  Future<SendReceipt> sendSepoliaEth({
    required String mnemonic,
    required String to,
    required String amountEth,
    required String rpcUrl,
  }) async {
    await ensureRustLib();
    final receipt = await rust.sendSepoliaEth(
      mnemonic: mnemonic,
      to: to,
      amountEth: amountEth,
      rpcUrl: _rpcUrl(rpcUrl),
    );
    return SendReceipt(txHash: receipt.txHash);
  }
}
