import 'wallet_api.dart';

/// In-memory stand-in so widget tests do not load the native library.
class FakeWalletApi implements WalletApi {
  FakeWalletApi({this.balanceDisplay = '0', List<UnifiedAssetSnapshot>? assets})
    : assets = assets ?? _sampleUsdt;

  final String balanceDisplay;
  final List<UnifiedAssetSnapshot> assets;

  static const _sampleUsdt = <UnifiedAssetSnapshot>[
    UnifiedAssetSnapshot(
      assetId: 'tether:usdt',
      symbol: 'USDT',
      name: 'Tether USD',
      decimals: 6,
      totalBaseUnits: '3500000',
      display: '3.5',
      complete: true,
      chains: [
        ChainHoldingSnapshot(
          chainId: 'ethereum',
          label: 'Ethereum',
          address: '0x9858EfFD232B4033E47d90003D41EC34EcaEda94',
          contract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
          decimals: 6,
          baseUnits: '1500000',
          display: '1.5',
        ),
        ChainHoldingSnapshot(
          chainId: 'tron',
          label: 'TRON',
          contract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          decimals: 6,
          baseUnits: '2000000',
          display: '2',
        ),
        ChainHoldingSnapshot(
          chainId: 'solana',
          label: 'Solana',
          contract: 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
          decimals: 6,
          baseUnits: '0',
          display: '0',
        ),
      ],
    ),
  ];

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

  @override
  Future<List<UnifiedAssetSnapshot>> unifiedAssets({
    required String mnemonic,
  }) async {
    if (mnemonic.trim().isEmpty) {
      throw StateError('invalid mnemonic');
    }
    return assets;
  }
}
