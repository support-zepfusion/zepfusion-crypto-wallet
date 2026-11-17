import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/keccak.dart';

/// Password quality shown while a self-custody password is created.
enum PasswordStrength { empty, weak, fair, good, strong }

PasswordStrength scorePassword(String value) {
  if (value.isEmpty) {
    return PasswordStrength.empty;
  }
  if (value.length < 8) {
    return PasswordStrength.weak;
  }
  final lower = value.contains(RegExp(r'[a-z]'));
  final upper = value.contains(RegExp(r'[A-Z]'));
  final digit = value.contains(RegExp(r'[0-9]'));
  final symbol = value.contains(RegExp(r'[^A-Za-z0-9]'));
  final classes = [lower, upper, digit, symbol].where((item) => item).length;
  if (value.length >= 12 && classes >= 3) {
    return PasswordStrength.strong;
  }
  if (value.length >= 10 && classes >= 3) {
    return PasswordStrength.good;
  }
  if (classes >= 2) {
    return PasswordStrength.fair;
  }
  return PasswordStrength.weak;
}

bool passwordIsAcceptable(String value) {
  final strength = scorePassword(value);
  return strength == PasswordStrength.fair ||
      strength == PasswordStrength.good ||
      strength == PasswordStrength.strong;
}

String passwordStrengthLabel(PasswordStrength strength) {
  return switch (strength) {
    PasswordStrength.empty => 'Enter a password',
    PasswordStrength.weak => 'Weak',
    PasswordStrength.fair => 'Fair',
    PasswordStrength.good => 'Good',
    PasswordStrength.strong => 'Strong',
  };
}

/// `0x` plus 4 characters on each side, for the account chip.
String shortAddress(String address) {
  if (address.length < 12) {
    return address;
  }
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}

Uint8List keccak256(List<int> bytes) {
  return KeccakDigest(256).process(Uint8List.fromList(bytes));
}

/// EIP-55 checksum text for a 40-character lowercase hex body.
String toEip55(String lowercaseBody) {
  final hash = keccak256(utf8.encode(lowercaseBody));
  final out = StringBuffer('0x');
  for (var index = 0; index < lowercaseBody.length; index++) {
    final character = lowercaseBody[index];
    final nibble = (hash[index ~/ 2] >> (index.isEven ? 4 : 0)) & 0x0f;
    final letter = RegExp(r'[a-f]').hasMatch(character);
    out.write(letter && nibble >= 8 ? character.toUpperCase() : character);
  }
  return out.toString();
}

/// Empty, structurally valid, or checksum-invalid.
enum AddressStatus { empty, invalid, badChecksum, valid }

AddressStatus checkEvmAddress(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return AddressStatus.empty;
  }
  final lowerPrefix = text.startsWith('0x') || text.startsWith('0X');
  if (!lowerPrefix) {
    return AddressStatus.invalid;
  }
  final body = text.substring(2);
  if (body.length != 40 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(body)) {
    return AddressStatus.invalid;
  }
  final lowercase = body.toLowerCase();
  final mixed = body != lowercase && body != body.toUpperCase();
  if (!mixed) {
    return AddressStatus.valid;
  }
  return toEip55(lowercase).substring(2) == body
      ? AddressStatus.valid
      : AddressStatus.badChecksum;
}

String? normalizeEvmAddress(String input) {
  if (checkEvmAddress(input) != AddressStatus.valid) {
    return null;
  }
  return toEip55(input.trim().substring(2).toLowerCase());
}

/// Decimal ETH to a wei integer string. Rejects signs, exponents, and >18 places.
String? ethToWei(String amount) {
  final trimmed = amount.trim();
  if (trimmed.isEmpty || trimmed.startsWith('+') || trimmed.startsWith('-')) {
    return null;
  }
  final split = trimmed.split('.');
  if (split.length > 2) {
    return null;
  }
  final whole = split[0].isEmpty ? '0' : split[0];
  final frac = split.length == 2 ? split[1] : '';
  if (frac.length > 18) {
    return null;
  }
  if (!RegExp(r'^[0-9]+$').hasMatch(whole) ||
      (frac.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(frac))) {
    return null;
  }
  final combined = '$whole${frac.padRight(18, '0')}'.replaceFirst(
    RegExp(r'^0+'),
    '',
  );
  if (combined.isEmpty) {
    return '0';
  }
  if (combined.length > 39) {
    return null;
  }
  try {
    BigInt.parse(combined);
  } on FormatException {
    return null;
  }
  return combined;
}

/// Wei integer to a trimmed ETH decimal. No floating point.
String weiToEth(String wei) {
  if (!RegExp(r'^[0-9]+$').hasMatch(wei)) {
    return '0';
  }
  final digits = wei.replaceFirst(RegExp(r'^0+'), '');
  if (digits.isEmpty) {
    return '0';
  }
  if (digits.length <= 18) {
    final padded = digits.padLeft(18, '0');
    final whole = '0';
    var frac = padded;
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    return frac.isEmpty ? whole : '$whole.$frac';
  }
  final split = digits.length - 18;
  var frac = digits.substring(split);
  frac = frac.replaceFirst(RegExp(r'0+$'), '');
  final whole = digits.substring(0, split);
  return frac.isEmpty ? whole : '$whole.$frac';
}

BigInt spendableWei(String balanceWei, String feeWei) {
  final balance = BigInt.parse(balanceWei);
  final fee = BigInt.parse(feeWei);
  final left = balance - fee;
  return left.isNegative ? BigInt.zero : left;
}

bool idleExpired({
  required DateTime lastActivity,
  required DateTime now,
  required Duration timeout,
}) {
  return !now.isBefore(lastActivity.add(timeout));
}

String friendlyError(Object error) {
  var text = error.toString().trim();
  for (final prefix in const ['Exception: ', 'Bad state: ', 'StateError: ']) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length);
    }
  }
  return text;
}
