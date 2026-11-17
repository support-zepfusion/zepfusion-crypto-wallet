import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys for the on-device vault. The payload is ciphertext, never the phrase.
class VaultKeys {
  static const payload = 'cofinex.vault.payload';
  static const address = 'cofinex.vault.address';
  static const biometric = 'cofinex.vault.biometric';
  static const wrapping = 'cofinex.vault.wrapping';
  static const recent = 'cofinex.vault.recent';
  static const activity = 'cofinex.vault.activity';

  static const all = <String>[
    payload,
    address,
    biometric,
    wrapping,
    recent,
    activity,
  ];
}

abstract class VaultStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<void> deleteAll();
}

class MemoryVaultStore implements VaultStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    values.clear();
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

/// Android Keystore-backed storage. `resetOnError` stays off so a keystore
/// glitch cannot delete the sealed phrase.
class SecureVaultStore implements VaultStore {
  SecureVaultStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() async {
    for (final key in VaultKeys.all) {
      await _storage.delete(key: key);
    }
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}
