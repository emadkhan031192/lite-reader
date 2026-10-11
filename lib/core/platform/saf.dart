import 'package:flutter/services.dart';

/// A file discovered inside a SAF document tree.
class SafEntry {
  const SafEntry({
    required this.uri,
    required this.displayName,
    required this.mimeType,
    required this.size,
    required this.lastModified,
    required this.isDirectory,
  });

  final String uri;
  final String displayName;
  final String mimeType;
  final int size;
  final int lastModified;
  final bool isDirectory;

  factory SafEntry.fromMap(Map<Object?, Object?> map) => SafEntry(
        uri: map['uri'] as String,
        displayName: map['displayName'] as String? ?? '',
        mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
        size: (map['size'] as num?)?.toInt() ?? 0,
        lastModified: (map['lastModified'] as num?)?.toInt() ?? 0,
        isDirectory: map['isDirectory'] as bool? ?? false,
      );
}

/// Storage Access Framework bridge. Never assumes a real file path:
/// content:// URIs are read through streams or cached copies.
class Saf {
  Saf._();

  static const MethodChannel _channel = MethodChannel('litereader/saf');

  /// Opens ACTION_OPEN_DOCUMENT_TREE and returns the persisted tree URI,
  /// or null when the user cancels.
  static Future<String?> pickDocumentTree() async {
    return _channel.invokeMethod<String>('pickDocumentTree');
  }

  /// Recursively lists files under a persisted tree URI.
  static Future<List<SafEntry>> listTree(String treeUri) async {
    final result =
        await _channel.invokeMethod<List<Object?>>('listTree', {'treeUri': treeUri});
    return (result ?? const [])
        .map((e) => SafEntry.fromMap(e as Map<Object?, Object?>))
        .toList();
  }

  /// Copies a content:// URI into the app cache and returns the file path.
  static Future<String?> copyToCache(String uri, String fileName) async {
    return _channel.invokeMethod<String>(
      'copyToCache',
      {'uri': uri, 'fileName': fileName},
    );
  }

  /// Creates a document inside a tree and writes [sourcePath] into it.
  /// Returns the new document URI, or null on failure.
  static Future<String?> createInTree({
    required String treeUri,
    required String displayName,
    required String mimeType,
    required String sourcePath,
  }) async {
    return _channel.invokeMethod<String>('createInTree', {
      'treeUri': treeUri,
      'displayName': displayName,
      'mimeType': mimeType,
      'sourcePath': sourcePath,
    });
  }

  /// Opens a URI with the system "Open with" chooser (used for Office files).
  /// Returns false when no app can open it.
  static Future<bool> openWith(String uri, String mimeType) async {
    final ok = await _channel.invokeMethod<bool>(
      'openWith',
      {'uri': uri, 'mimeType': mimeType},
    );
    return ok ?? false;
  }
}
