import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../wallet_api.dart';
import 'vault_cipher.dart';
import 'vault_store.dart';

class Clock {
  const Clock();

  DateTime now() => DateTime.now();
}

enum WalletStage { booting, welcome, unlock, home }

class UnlockedWallet {
  UnlockedWallet({required this.mnemonic, required this.address});

  final String mnemonic;
  final String address;
}

class LocalActivity {
  const LocalActivity({
    required this.hash,
    required this.to,
    required this.amountEth,
    required this.at,
  });

  final String hash;
  final String to;
  final String amountEth;
  final DateTime at;
}

class WalletController extends ChangeNotifier {
  WalletController({
    required this.api,
    required this.store,
    required this.cipher,
    required this.biometrics,
    this.clock = const Clock(),
    this.inactivityTimeout,
  });

  final WalletApi api;
  final VaultStore store;
  final VaultCipher cipher;
  final BiometricGate biometrics;
  final Clock clock;

  /// `null` disables the inactivity timer. Production uses 60 seconds.
  final Duration? inactivityTimeout;

  WalletStage stage = WalletStage.booting;
  UnlockedWallet? session;
  String? addressHint;
  bool biometricEnabled = false;
  List<String> recentRecipients = [];
  List<LocalActivity> activity = [];
  String? bootError;

  DateTime? _lastActivity;
  Timer? _lockTimer;

  Future<void> boot() async {
    try {
      final payload = await store.read(VaultKeys.payload);
      addressHint = await store.read(VaultKeys.address);
      biometricEnabled = (await store.read(VaultKeys.biometric)) == '1';
      recentRecipients = _decodeRecent(await store.read(VaultKeys.recent));
      activity = _decodeActivity(await store.read(VaultKeys.activity));
      stage = payload == null ? WalletStage.welcome : WalletStage.unlock;
    } catch (error) {
      bootError = error.toString();
      stage = WalletStage.welcome;
    }
    notifyListeners();
  }

  Future<void> saveNewWallet({
    required String mnemonic,
    required String password,
    required String address,
  }) async {
    final payload = await cipher.seal(mnemonic, password);
    await store.write(VaultKeys.payload, payload);
    await store.write(VaultKeys.address, address);
    addressHint = address;
    session = UnlockedWallet(mnemonic: mnemonic, address: address);
    stage = WalletStage.home;
    _touch();
    notifyListeners();
  }

  Future<void> unlockWithPassword(String password) async {
    final payload = await store.read(VaultKeys.payload);
    if (payload == null) {
      throw StateError('No wallet is stored on this device.');
    }
    final mnemonic = await cipher.open(payload, password);
    await _openSession(mnemonic);
  }

  Future<bool> unlockWithBiometric() async {
    if (!biometricEnabled) {
      return false;
    }
    final ok = await biometrics.authenticate('Unlock Cofinex Wallet');
    if (!ok) {
      return false;
    }
    final payload = await store.read(VaultKeys.payload);
    final key = await store.read(VaultKeys.wrapping);
    if (payload == null || key == null) {
      throw StateError('Biometric unlock is not set up on this device.');
    }
    final mnemonic = await cipher.openWithWrappingKey(payload, key);
    await _openSession(mnemonic);
    return true;
  }

  Future<String> revealMnemonic(String password) async {
    final payload = await store.read(VaultKeys.payload);
    if (payload == null) {
      throw StateError('No wallet is stored on this device.');
    }
    return cipher.open(payload, password);
  }

  Future<void> setBiometricEnabled(bool enabled, {String? password}) async {
    if (!enabled) {
      await store.delete(VaultKeys.wrapping);
      await store.write(VaultKeys.biometric, '0');
      biometricEnabled = false;
      notifyListeners();
      return;
    }
    final available = await biometrics.canAuthenticate();
    if (!available) {
      throw StateError('Biometrics are not available on this device.');
    }
    if (password == null || password.isEmpty) {
      throw StateError('Enter your password to turn on biometric unlock.');
    }
    final payload = await store.read(VaultKeys.payload);
    if (payload == null) {
      throw StateError('No wallet is stored on this device.');
    }
    final key = await cipher.wrappingKey(payload, password);
    final confirmed = await biometrics.authenticate(
      'Confirm biometrics for Cofinex Wallet',
    );
    if (!confirmed) {
      throw StateError('Biometric confirmation was cancelled.');
    }
    await store.write(VaultKeys.wrapping, key);
    await store.write(VaultKeys.biometric, '1');
    biometricEnabled = true;
    notifyListeners();
  }

  Future<void> rememberRecipient(String address) async {
    recentRecipients.remove(address);
    recentRecipients.insert(0, address);
    if (recentRecipients.length > 8) {
      recentRecipients = recentRecipients.sublist(0, 8);
    }
    await store.write(VaultKeys.recent, jsonEncode(recentRecipients));
    notifyListeners();
  }

  Future<void> recordSend({
    required String hash,
    required String to,
    required String amountEth,
  }) async {
    activity.insert(
      0,
      LocalActivity(
        hash: hash,
        to: to,
        amountEth: amountEth,
        at: clock.now().toUtc(),
      ),
    );
    if (activity.length > 20) {
      activity = activity.sublist(0, 20);
    }
    await store.write(
      VaultKeys.activity,
      jsonEncode([
        for (final item in activity)
          {
            'hash': item.hash,
            'to': item.to,
            'amountEth': item.amountEth,
            'at': item.at.toIso8601String(),
          },
      ]),
    );
    await rememberRecipient(to);
  }

  void noteActivity() {
    if (session == null) {
      return;
    }
    _touch();
  }

  void lockIfIdle() {
    final timeout = inactivityTimeout;
    final last = _lastActivity;
    if (timeout == null || last == null || session == null) {
      return;
    }
    if (!clock.now().isBefore(last.add(timeout))) {
      lock();
    }
  }

  void lock() {
    _lockTimer?.cancel();
    _lockTimer = null;
    if (session == null) {
      return;
    }
    session = null;
    stage = WalletStage.unlock;
    notifyListeners();
  }

  Future<void> reset() async {
    _lockTimer?.cancel();
    _lockTimer = null;
    session = null;
    addressHint = null;
    biometricEnabled = false;
    recentRecipients = [];
    activity = [];
    await store.deleteAll();
    stage = WalletStage.welcome;
    notifyListeners();
  }

  Future<void> _openSession(String mnemonic) async {
    final imported = await api.importTestWallet(mnemonic);
    session = UnlockedWallet(
      mnemonic: mnemonic,
      address: imported.sepoliaAddress,
    );
    addressHint = imported.sepoliaAddress;
    await store.write(VaultKeys.address, imported.sepoliaAddress);
    stage = WalletStage.home;
    _touch();
    notifyListeners();
  }

  void _touch() {
    _lastActivity = clock.now();
    _lockTimer?.cancel();
    final timeout = inactivityTimeout;
    if (timeout == null || session == null) {
      return;
    }
    _lockTimer = Timer(timeout, lock);
  }

  List<String> _decodeRecent(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return [for (final item in decoded) item.toString()];
    } catch (_) {
      return [];
    }
  }

  List<LocalActivity> _decodeActivity(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return [
        for (final item in decoded)
          if (item is Map)
            LocalActivity(
              hash: '${item['hash'] ?? ''}',
              to: '${item['to'] ?? ''}',
              amountEth: '${item['amountEth'] ?? ''}',
              at:
                  DateTime.tryParse('${item['at']}')?.toUtc() ??
                  DateTime.now().toUtc(),
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }
}
