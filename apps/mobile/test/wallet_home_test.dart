import 'package:cofinex_wallet/main.dart';
import 'package:cofinex_wallet/src/fake_wallet_api.dart';
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

    expect(find.textContaining('Sepolia testnet only'), findsOneWidget);
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
}
