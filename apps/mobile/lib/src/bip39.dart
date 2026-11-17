import 'bip39_english.dart';

final Set<String> englishBip39 = Set<String>.unmodifiable(englishBip39Words);

bool isBip39Word(String word) {
  return englishBip39.contains(word.trim().toLowerCase());
}

List<String> splitPhrase(String raw) {
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return const [];
  }
  return trimmed.split(RegExp(r'\s+'));
}

/// Word-by-word check. Empty slots are invalid once the user tries to continue.
List<String?> phraseWordErrors(List<String> words, {required int expected}) {
  return [
    for (var index = 0; index < expected; index++)
      index >= words.length || words[index].isEmpty
          ? 'Required'
          : isBip39Word(words[index])
          ? null
          : 'Not a BIP-39 word',
  ];
}
