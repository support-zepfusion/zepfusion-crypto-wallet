import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

class ManifestException {
  ManifestException(this.message, {required this.fileName});

  final String? fileName;
  final String message;

  @override
  String toString() {
    if (fileName != null) {
      return 'Failed to parse package manifest at $fileName: $message';
    } else {
      return 'Failed to parse package manifest: $message';
    }
  }
}

class CrateInfo {
  CrateInfo({required this.packageName, required this.libName});

  final String packageName;

  /// File stem of the built library. Cargo's default replaces `-` with `_`,
  /// and `[lib] name` overrides that. The `.so` is `lib$libName.so`.
  final String libName;

  static CrateInfo parseManifest(String manifest, {final String? fileName}) {
    final toml = TomlDocument.parse(manifest);
    final root = toml.toMap();
    final package = root['package'];
    if (package == null) {
      throw ManifestException('Missing package section', fileName: fileName);
    }
    final name = package['name'];
    if (name is! String || name.isEmpty) {
      throw ManifestException('Missing package name', fileName: fileName);
    }
    final lib = root['lib'];
    final explicit = lib is Map ? lib['name'] : null;
    final libName = explicit is String && explicit.isNotEmpty
        ? explicit
        : name.replaceAll('-', '_');
    return CrateInfo(packageName: name, libName: libName);
  }

  static CrateInfo load(String manifestDir) {
    final manifestFile = File(path.join(manifestDir, 'Cargo.toml'));
    final manifest = manifestFile.readAsStringSync();
    return parseManifest(manifest, fileName: manifestFile.path);
  }
}
