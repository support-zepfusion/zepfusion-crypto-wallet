import 'package:cofinex_wallet/main.dart';
import 'package:cofinex_wallet/src/fake_wallet_api.dart';
import 'package:cofinex_wallet/src/vault/vault_cipher.dart';
import 'package:cofinex_wallet/src/vault/vault_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_vault_cipher.dart';

const phrase =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';
const address = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({FakeWalletApi api, MemoryVaultStore store, TestVaultCipher cipher})>
  pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    MemoryVaultStore? store,
    Duration? inactivityTimeout,
    List<int>? quizPositions,
    BiometricGate? biometrics,
    FakeWalletApi? api,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = (
      api: api ?? FakeWalletApi(),
      store: store ?? MemoryVaultStore(),
      cipher: TestVaultCipher(),
    );
    await tester.pumpWidget(
      CofinexApp(
        api: harness.api,
        store: harness.store,
        cipher: harness.cipher,
        biometrics: biometrics ?? const UnavailableBiometricGate(),
        inactivityTimeout: inactivityTimeout,
        quizPositions: quizPositions,
        quizSeed: 7,
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('onboarding offers email, self-custody, business, and restore', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Cofinex Wallet'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(find.textContaining('2-of-3 MPC'), findsOneWidget);

    await tapKey(tester, 'continue-with-email');
    expect(find.text('Email sign-in is coming soon'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('email-field')),
      'ada@example.com',
    );
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.textContaining('not sent'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'other-ways');
    expect(find.text('Self-custody wallet'), findsOneWidget);
    expect(find.text('Business wallet'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Restore existing wallet'),
      200,
    );
    expect(find.text('Restore existing wallet'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);

    await tapKey(tester, 'setup-business');
    expect(find.text('Business wallets are coming soon'), findsOneWidget);
    expect(find.textContaining('multisig'), findsOneWidget);
  });

  testWidgets('self-custody confirms the phrase and opens the home screen', (
    tester,
  ) async {
    await pumpApp(tester, quizPositions: const [0, 4, 11]);
    await tapKey(tester, 'other-ways');
    await tapKey(tester, 'setup-self-custody');

    await tester.enterText(
      find.byKey(const Key('password-field')),
      'Wallet123',
    );
    await tester.enterText(
      find.byKey(const Key('password-confirm-field')),
      'Wallet123',
    );
    await tester.pump();
    expect(find.text('Fair'), findsOneWidget);
    await tapKey(tester, 'terms-checkbox');
    await tapKey(tester, 'password-continue');
    expect(find.text('Secure your wallet'), findsOneWidget);

    await tapKey(tester, 'secure-continue');
    expect(find.text('abandon'), findsNothing);
    await tapKey(tester, 'reveal-phrase');
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('accident'), findsOneWidget);
    await tapKey(tester, 'reveal-continue');

    final wrong = find
        .descendant(
          of: find.byKey(const Key('quiz-question-0')),
          matching: find.byWidgetPredicate((widget) {
            return widget is ChoiceChip &&
                widget.label is Text &&
                (widget.label as Text).data != 'abandon';
          }),
        )
        .first;
    await tester.ensureVisible(wrong);
    await tester.tap(wrong);
    await tester.pumpAndSettle();
    await tapKey(tester, 'quiz-4-above');
    await tapKey(tester, 'quiz-11-accident');
    await tapKey(tester, 'confirm-phrase');
    expect(find.byKey(const Key('inline-error')), findsOneWidget);
    expect(find.byKey(const Key('home-balance')), findsNothing);

    await tapKey(tester, 'quiz-0-abandon');
    await tapKey(tester, 'quiz-4-above');
    await tapKey(tester, 'quiz-11-accident');
    await tapKey(tester, 'confirm-phrase');
    expect(find.text('Your wallet is ready'), findsOneWidget);
    await tapKey(tester, 'success-done');

    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('Account 1'), findsOneWidget);
    expect(find.textContaining('0x9858'), findsWidgets);
    expect(
      tester.widget<InkWell>(find.byKey(const Key('action-swap'))).onTap,
      isNull,
    );
    expect(find.text('Soon'), findsWidgets);
  });

  testWidgets('restore rejects an unknown word and accepts twelve words', (
    tester,
  ) async {
    final harness = await pumpApp(tester);
    await tapKey(tester, 'other-ways');
    await tester.scrollUntilVisible(find.byKey(const Key('setup-restore')), 200);
    await tapKey(tester, 'setup-restore');

    await tester.enterText(
      find.byKey(const Key('restore-phrase')),
      'abandon notaword',
    );
    await tester.pump();
    expect(find.text('Not a BIP-39 word'), findsOneWidget);
    await tapKey(tester, 'restore-continue');
    expect(find.byKey(const Key('home-balance')), findsNothing);

    await tester.enterText(find.byKey(const Key('restore-phrase')), phrase);
    await tester.pumpAndSettle();
    await tapKey(tester, 'restore-continue');
    await tester.enterText(
      find.byKey(const Key('restore-password')),
      'Wallet123',
    );
    await tester.enterText(
      find.byKey(const Key('restore-password-confirm')),
      'Wallet123',
    );
    await tapKey(tester, 'restore-terms');
    await tapKey(tester, 'restore-finish');

    expect(find.text('1.5'), findsOneWidget);
    expect(harness.store.values[VaultKeys.payload], isNotNull);
    expect(
      harness.store.values[VaultKeys.payload]!.contains('abandon'),
      isFalse,
    );
  });

  testWidgets('unlock rejects a bad password and opens the home screen', (
    tester,
  ) async {
    final store = MemoryVaultStore();
    final cipher = TestVaultCipher();
    store.values[VaultKeys.payload] = await cipher.seal(phrase, 'Wallet123');
    store.values[VaultKeys.address] = address;
    await pumpApp(tester, store: store);

    expect(find.byKey(const Key('unlock-password')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('unlock-password')), 'nope');
    await tapKey(tester, 'unlock-submit');
    expect(find.byKey(const Key('inline-error')), findsOneWidget);
    expect(find.textContaining('incorrect password'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('unlock-password')),
      'Wallet123',
    );
    await tapKey(tester, 'unlock-submit');
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('Sepolia'), findsWidgets);

    await tapKey(tester, 'network-selector');
    expect(find.text('Mainnet disabled'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('Coming soon'), findsWidgets);
    await tester.tap(find.text('Sepolia').last);
    await tester.pumpAndSettle();

    await tapKey(tester, 'token-eth');
    expect(find.byKey(const Key('token-eth-chains')), findsOneWidget);
    expect(find.textContaining('Sepolia · 1.5 ETH'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('No activity yet'), findsOneWidget);
  });

  testWidgets('home sends Sepolia ETH and lists it in activity', (
    tester,
  ) async {
    final store = MemoryVaultStore();
    final cipher = TestVaultCipher();
    final api = FakeWalletApi();
    store.values[VaultKeys.payload] = await cipher.seal(phrase, 'Wallet123');
    store.values[VaultKeys.address] = address;
    await pumpApp(tester, store: store, api: api);
    await tester.enterText(
      find.byKey(const Key('unlock-password')),
      'Wallet123',
    );
    await tapKey(tester, 'unlock-submit');

    final before = api.balanceCalls;
    await tester.fling(
      find.byKey(const Key('token-list')),
      const Offset(0, 400),
      1200,
    );
    await tester.pumpAndSettle();
    expect(api.balanceCalls, greaterThan(before));

    await tapKey(tester, 'action-receive');
    expect(find.byKey(const Key('receive-warning')), findsOneWidget);
    expect(find.text(address), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('receive-copy')));
    await tester.tap(find.byKey(const Key('receive-copy')));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapKey(tester, 'action-send');
    await tester.enterText(
      find.byKey(const Key('send-recipient')),
      '0x9858effd232b4033e47d90003d41ec34ecaeda94',
    );
    await tester.enterText(find.byKey(const Key('send-amount')), '0.1');
    await tester.pumpAndSettle();
    await tapKey(tester, 'send-next');
    expect(find.textContaining('0.000063 ETH'), findsWidgets);
    await tapKey(tester, 'review-confirm');
    expect(find.text('Submitted to Sepolia'), findsWidgets);
    expect(api.lastSend, isNotNull);
    await tapKey(tester, 'send-done');

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Sent 0.1 ETH'), findsOneWidget);

    await tapKey(tester, 'settings-button');
    await tapKey(tester, 'reset-wallet');
    await tapKey(tester, 'reset-confirm');
    expect(find.text('Continue with email'), findsOneWidget);
    expect(store.values, isEmpty);
  });

  testWidgets('auto-lock returns to the unlock screen', (tester) async {
    final store = MemoryVaultStore();
    final cipher = TestVaultCipher();
    store.values[VaultKeys.payload] = await cipher.seal(phrase, 'Wallet123');
    store.values[VaultKeys.address] = address;
    await pumpApp(
      tester,
      store: store,
      inactivityTimeout: const Duration(seconds: 1),
    );
    await tester.enterText(
      find.byKey(const Key('unlock-password')),
      'Wallet123',
    );
    await tester.tap(find.byKey(const Key('unlock-submit')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('home-balance')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('unlock-password')), findsOneWidget);
  });

  testWidgets('a small phone lays out welcome without overflow', (tester) async {
    await pumpApp(tester, size: const Size(320, 640));
    expect(find.text('Continue with email'), findsOneWidget);
    await tapKey(tester, 'other-ways');
    await tester.scrollUntilVisible(find.text('Restore existing wallet'), 200);
    expect(find.text('Self-custody wallet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a large phone lays out the home screen', (tester) async {
    final store = MemoryVaultStore();
    final cipher = TestVaultCipher();
    store.values[VaultKeys.payload] = await cipher.seal(phrase, 'Wallet123');
    store.values[VaultKeys.address] = address;
    await pumpApp(tester, size: const Size(800, 1200), store: store);
    await tester.enterText(
      find.byKey(const Key('unlock-password')),
      'Wallet123',
    );
    await tapKey(tester, 'unlock-submit');
    expect(find.text('1.5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
