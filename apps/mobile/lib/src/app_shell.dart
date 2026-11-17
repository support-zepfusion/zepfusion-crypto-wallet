import 'package:material_ui/material_ui.dart';

import 'screens/coming_soon_screen.dart';
import 'screens/create_flow.dart';
import 'screens/home_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/restore_flow.dart';
import 'screens/send_flow.dart';
import 'screens/settings_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/welcome_screen.dart';
import 'rust_wallet_api.dart';
import 'theme.dart';
import 'vault/local_biometrics.dart';
import 'vault/vault_cipher.dart';
import 'vault/vault_store.dart';
import 'vault/wallet_controller.dart';
import 'wallet_api.dart';

class CofinexApp extends StatefulWidget {
  const CofinexApp({
    super.key,
    this.api,
    this.store,
    this.cipher,
    this.biometrics,
    this.clock,
    this.inactivityTimeout,
    this.quizPositions,
    this.quizSeed,
  });

  final WalletApi? api;
  final VaultStore? store;
  final VaultCipher? cipher;
  final BiometricGate? biometrics;
  final Clock? clock;
  final Duration? inactivityTimeout;
  final List<int>? quizPositions;
  final int? quizSeed;

  @override
  State<CofinexApp> createState() => _CofinexAppState();
}

class _CofinexAppState extends State<CofinexApp> with WidgetsBindingObserver {
  late final WalletController _controller;
  final _welcomeNav = GlobalKey<NavigatorState>();
  final _homeNav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WalletController(
      api: widget.api ?? RustWalletApi(),
      store: widget.store ?? SecureVaultStore(),
      cipher: widget.cipher ?? RustVaultCipher(),
      biometrics: widget.biometrics ?? LocalBiometricGate(),
      clock: widget.clock ?? const Clock(),
      inactivityTimeout: widget.inactivityTimeout,
    );
    _controller.boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.lockIfIdle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('app-boundary'),
      child: MaterialApp(
        title: 'Cofinex Wallet',
        debugShowCheckedModeBanner: false,
        theme: cofinexTheme(),
        home: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _controller.noteActivity(),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              return switch (_controller.stage) {
                WalletStage.booting => const Scaffold(
                  body: Center(child: Text('Opening your wallet…')),
                ),
                WalletStage.welcome => _welcome(),
                WalletStage.unlock => UnlockScreen(controller: _controller),
                WalletStage.home => _home(),
              };
            },
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    return Navigator(
      key: _welcomeNav,
      onGenerateRoute: (settings) {
        return cofinexRoute(
          WelcomeScreen(
            onEmail: () {
              _welcomeNav.currentState?.push(
                cofinexRoute(
                  const ComingSoonScreen(
                    title: 'Email sign-in is coming soon',
                    collectEmail: true,
                    body: 'Retail accounts will use email and 2-of-3 MPC, so there is no seed phrase to lose. You can type an email here. It stays on this screen and is not sent.',
                  ),
                ),
              );
            },
            onSelfCustody: () {
              _welcomeNav.currentState?.push(
                cofinexRoute(
                  CreateFlow(
                    controller: _controller,
                    quizPositions: widget.quizPositions,
                    quizSeed: widget.quizSeed,
                  ),
                ),
              );
            },
            onBusiness: () {
              _welcomeNav.currentState?.push(
                cofinexRoute(
                  const ComingSoonScreen(
                    title: 'Business wallets are coming soon',
                    body: 'Business treasury will use on-chain multisig with approval policies. That flow is not built yet.',
                  ),
                ),
              );
            },
            onRestore: () {
              _welcomeNav.currentState?.push(
                cofinexRoute(RestoreFlow(controller: _controller)),
              );
            },
          ),
        );
      },
    );
  }

  Widget _home() {
    return Navigator(
      key: _homeNav,
      onGenerateRoute: (settings) {
        return cofinexRoute(
          HomeScreen(
            controller: _controller,
            onSend: () {
              _homeNav.currentState?.push(
                cofinexRoute(SendFlow(controller: _controller)),
              );
            },
            onReceive: () {
              final address = _controller.session?.address;
              if (address == null) {
                return;
              }
              _homeNav.currentState?.push(
                cofinexRoute(ReceiveScreen(address: address)),
              );
            },
            onSettings: () {
              _homeNav.currentState?.push(
                cofinexRoute(SettingsScreen(controller: _controller)),
              );
            },
          ),
        );
      },
    );
  }
}
