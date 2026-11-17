import 'wallet_api.dart';

/// In-memory stand-in so widget tests do not load the native library.
class FakeWalletApi implements WalletApi {
  FakeWalletApi({this.balanceDisplay = '0'});

  final String balanceDisplay;

  @override
  Future<WalletSnapshot> createTestWallet() async {
    return const WalletSnapshot(
      mnemonic: 'test phrase shown only by the fake api',
      sepoliaAddress: '0x9858EfFD232B4033E47d90003D41EC34EcaEda94',
    );
  }

  @override
  Future<WalletSnapshot> importTestWallet(String mnemonic) async {
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    if (words.length < 12) {
      throw StateError('invalid mnemonic');
    }
    return const WalletSnapshot(
      sepoliaAddress: '0x9858EfFD232B4033E47d90003D41EC34EcaEda94',
    );
  }

  @override
  Future<BalanceSnapshot> sepoliaBalance({
    required String address,
    required String rpcUrl,
  }) async {
    if (!address.startsWith('0x') || address.length != 42) {
      throw StateError('address is invalid');
    }
    if (rpcUrl.trim().isEmpty) {
      throw StateError(
        'Sepolia RPC URL is not configured. Set COFINEX_SEPOLIA_RPC_URL or pass a URL.',
      );
    }
    return BalanceSnapshot(
      symbol: 'ETH',
      baseUnits: '0',
      display: balanceDisplay,
    );
  }
}
