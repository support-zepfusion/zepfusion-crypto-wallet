import 'package:cofinex_wallet/src/bip39.dart';
import 'package:cofinex_wallet/src/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('password meter requires length and a mix of characters', () {
    expect(scorePassword(''), PasswordStrength.empty);
    expect(scorePassword('short'), PasswordStrength.weak);
    expect(scorePassword('aaaaaaaa'), PasswordStrength.weak);
    expect(passwordIsAcceptable('Wallet123'), isTrue);
    expect(scorePassword('Wallet123'), PasswordStrength.fair);
    expect(scorePassword('Wallet-pass-123'), PasswordStrength.strong);
  });

  test('wei conversion matches the integer ETH rules', () {
    expect(ethToWei('1.5'), '1500000000000000000');
    expect(ethToWei('0'), '0');
    expect(ethToWei('.001'), '1000000000000000');
    expect(ethToWei('1.0000000000000000001'), isNull);
    expect(weiToEth('1500000000000000000'), '1.5');
    expect(weiToEth('63000000000000'), '0.000063');
    expect(
      spendableWei('1500000000000000000', '63000000000000').toString(),
      '1499937000000000000',
    );
  });

  test('EIP-55 accepts the BIP-44 vector and rejects a bad checksum', () {
    expect(
      toEip55('9858effd232b4033e47d90003d41ec34ecaeda94'),
      '0x9858EfFD232B4033E47d90003D41EC34EcaEda94',
    );
    expect(
      checkEvmAddress('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
      AddressStatus.valid,
    );
    expect(
      checkEvmAddress('0x9858effd232b4033e47d90003d41ec34ecaeda94'),
      AddressStatus.valid,
    );
    expect(
      checkEvmAddress('0x9858EfFD232B4033E47d90003D41EC34EcaEda95'),
      AddressStatus.badChecksum,
    );
    expect(checkEvmAddress('not-an-address'), AddressStatus.invalid);
    expect(
      shortAddress('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
      '0x9858…da94',
    );
  });

  test('BIP-39 validation flags unknown words', () {
    expect(isBip39Word('abandon'), isTrue);
    expect(isBip39Word('notaword'), isFalse);
    final errors = phraseWordErrors(['abandon', 'notaword'], expected: 2);
    expect(errors[0], isNull);
    expect(errors[1], 'Not a BIP-39 word');
  });

  test('idle expiry uses the injected clock', () {
    final start = DateTime.utc(2026, 11, 17, 12);
    expect(
      idleExpired(
        lastActivity: start,
        now: start.add(const Duration(seconds: 59)),
        timeout: const Duration(seconds: 60),
      ),
      isFalse,
    );
    expect(
      idleExpired(
        lastActivity: start,
        now: start.add(const Duration(seconds: 60)),
        timeout: const Duration(seconds: 60),
      ),
      isTrue,
    );
  });
}
