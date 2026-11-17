import '../rust/api/vault.dart' as rust;
import '../rust_bridge.dart';

/// Seals a recovery phrase with a password-derived key.
///
/// Production uses PBKDF2-HMAC-SHA256 (600,000 iterations) and AES-256-GCM in
/// Rust. Widget tests supply their own implementation and do not load the
/// native library.
abstract class VaultCipher {
  Future<String> seal(String mnemonic, String password);

  Future<String> open(String payload, String password);

  Future<String> wrappingKey(String payload, String password);

  Future<String> openWithWrappingKey(String payload, String wrappingKey);
}

class RustVaultCipher implements VaultCipher {
  @override
  Future<String> open(String payload, String password) async {
    await ensureRustLib();
    return rust.openMnemonic(payload: payload, password: password);
  }

  @override
  Future<String> openWithWrappingKey(String payload, String wrappingKey) async {
    await ensureRustLib();
    return rust.openWithWrappingKey(payload: payload, wrappingKey: wrappingKey);
  }

  @override
  Future<String> seal(String mnemonic, String password) async {
    await ensureRustLib();
    return rust.sealMnemonic(mnemonic: mnemonic, password: password);
  }

  @override
  Future<String> wrappingKey(String payload, String password) async {
    await ensureRustLib();
    return rust.wrappingKey(payload: payload, password: password);
  }
}

/// App-level biometric gate. The wrapping key itself stays in secure storage.
abstract class BiometricGate {
  Future<bool> canAuthenticate();

  Future<bool> authenticate(String reason);
}

class UnavailableBiometricGate implements BiometricGate {
  const UnavailableBiometricGate();

  @override
  Future<bool> authenticate(String reason) async => false;

  @override
  Future<bool> canAuthenticate() async => false;
}
