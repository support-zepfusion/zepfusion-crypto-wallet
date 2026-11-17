import 'dart:convert';

import 'package:cofinex_wallet/src/vault/vault_cipher.dart';
import 'package:crypto/crypto.dart';

/// Test double. It checks the password, but it is not the production KDF.
/// Production sealing is PBKDF2 + AES-GCM in Rust and is covered by cargo tests.
class TestVaultCipher implements VaultCipher {
  @override
  Future<String> open(String payload, String password) async {
    final map = _read(payload);
    if (map['mac'] != _mac(password)) {
      throw StateError('incorrect password');
    }
    return utf8.decode(base64Decode(map['secret']! as String));
  }

  @override
  Future<String> openWithWrappingKey(String payload, String wrappingKey) async {
    final map = _read(payload);
    if (map['wrap'] != wrappingKey) {
      throw StateError('incorrect password');
    }
    return utf8.decode(base64Decode(map['secret']! as String));
  }

  @override
  Future<String> seal(String mnemonic, String password) async {
    return jsonEncode({
      'test': true,
      'mac': _mac(password),
      'wrap': _wrap(password),
      'secret': base64Encode(utf8.encode(mnemonic)),
    });
  }

  @override
  Future<String> wrappingKey(String payload, String password) async {
    await open(payload, password);
    return _read(payload)['wrap']! as String;
  }

  Map<String, dynamic> _read(String payload) =>
      jsonDecode(payload) as Map<String, dynamic>;

  String _mac(String password) =>
      sha256.convert(utf8.encode('v1|$password')).toString();

  String _wrap(String password) =>
      sha256.convert(utf8.encode('wrap|$password')).toString();
}

class ScriptedBiometricGate implements BiometricGate {
  ScriptedBiometricGate({this.available = true, this.accept = true});

  bool available;
  bool accept;

  @override
  Future<bool> authenticate(String reason) async => accept;

  @override
  Future<bool> canAuthenticate() async => available;
}
