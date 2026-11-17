import 'package:cofinex_wallet/main.dart';
import 'package:cofinex_wallet/src/fake_wallet_api.dart';
import 'package:cofinex_wallet/src/wallet_api.dart';
import 'package:cofinex_wallet/src/wallet_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, FakeWalletApi api) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CofinexApp(home: WalletHome(api: api)));
  }

  testWidgets('create shows the Sepolia address and the test phrase', (tester) async {
    await pumpHome(tester, FakeWalletApi());

    expect(find.textContaining('Signing stays on Sepolia'), findsOneWidget);
    expect(find.text('Create test wallet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-wallet')));
    await tester.pumpAndSettle();

    expect(
      find.text('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
      findsOneWidget,
    );
    expect(find.text('test phrase shown only by the fake api'), findsOneWidget);
    expect(find.textContaining('Do not reuse it on mainnet'), findsOneWidget);
  });

  testWidgets('balance refresh reports the fake balance and an empty URL error', (
    tester,
  ) async {
    await pumpHome(tester, FakeWalletApi(balanceDisplay: '1.5'));
    await tester.tap(find.byKey(const Key('create-wallet')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refresh-balance')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sepolia RPC URL is not configured'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('rpc-field')),
      'https://ethereum-sepolia-rpc.publicnode.com',
    );
    await tester.tap(find.byKey(const Key('refresh-balance')));
    await tester.pumpAndSettle();

    expect(find.text('1.5 ETH'), findsOneWidget);
    expect(find.text('0 wei'), findsOneWidget);
  });

  testWidgets('import rejects a short phrase and accepts twelve words', (tester) async {
    await pumpHome(tester, FakeWalletApi());

    await tester.enterText(find.byKey(const Key('mnemonic-field')), 'too short');
    await tester.tap(find.byKey(const Key('import-wallet')));
    await tester.pumpAndSettle();
    expect(find.textContaining('invalid mnemonic'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('mnemonic-field')),
      'one two three four five six seven eight nine ten eleven twelve',
    );
    await tester.tap(find.byKey(const Key('import-wallet')));
    await tester.pumpAndSettle();

    expect(
      find.text('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('mnemonic')), findsNothing);
  });

  testWidgets('unified USDT shows a total, chain chips, and the breakdown', (
    tester,
  ) async {
    await pumpHome(tester, FakeWalletApi());
    await tester.tap(find.byKey(const Key('create-wallet')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refresh-unified')));
    await tester.pumpAndSettle();

    expect(find.text('Tether USD'), findsOneWidget);
    expect(find.text('3.5 USDT'), findsOneWidget);
    expect(find.byKey(const Key('chip-USDT-ethereum')), findsOneWidget);
    expect(find.byKey(const Key('chip-USDT-tron')), findsOneWidget);
    expect(find.byKey(const Key('chip-USDT-solana')), findsOneWidget);

    await tester.tap(find.byKey(const Key('expand-USDT')));
    await tester.pumpAndSettle();

    expect(find.text('1.5 USDT\n1500000 base units'), findsOneWidget);
    expect(find.text('2 USDT\n2000000 base units'), findsOneWidget);
    expect(find.text('0 USDT\n0 base units'), findsOneWidget);
  });

  testWidgets('a chain that cannot be read marks the total incomplete', (
    tester,
  ) async {
    const partial = UnifiedAssetSnapshot(
      assetId: 'tether:usdt',
      symbol: 'USDT',
      name: 'Tether USD',
      decimals: 6,
      totalBaseUnits: '1500000',
      display: '1.5',
      complete: false,
      chains: [
        ChainHoldingSnapshot(
          chainId: 'ethereum',
          label: 'Ethereum',
          decimals: 6,
          baseUnits: '1500000',
          display: '1.5',
        ),
        ChainHoldingSnapshot(
          chainId: 'solana',
          label: 'Solana',
          decimals: 6,
          error: 'solana does not implement fungible_balance yet',
        ),
      ],
    );
    await pumpHome(tester, FakeWalletApi(assets: const [partial]));
    await tester.tap(find.byKey(const Key('create-wallet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-unified')));
    await tester.pumpAndSettle();

    expect(find.textContaining('incomplete'), findsOneWidget);
    await tester.tap(find.byKey(const Key('expand-USDT')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not implement fungible_balance'),
      findsOneWidget,
    );
  });
}
