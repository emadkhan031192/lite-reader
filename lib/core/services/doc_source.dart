import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document.dart';
import '../platform/saf.dart';

/// Resolves a [LibraryDocument] to a real file path for PDFium.
///
/// - App-private files are used directly.
/// - content:// URIs (SAF trees, shared files) are copied into the app cache.
///   The cache file name embeds size + modified time, so a changed source
///   file automatically misses the cache. Never assumes a real file path.
abstract final class DocSource {
  /// Returns a readable file path for [doc], copying from the content
  /// resolver when needed.
  static Future<String> resolvePath(LibraryDocument doc) async {
    final uri = doc.uri;
    if (!uri.startsWith('content://')) {
      final file = File(uri);
      if (await file.exists()) return uri;
    }
    final cacheDir = await _cacheDir();
    final key = md5.convert(uri.codeUnits).toString();
    final ext = p.extension(doc.displayName).toLowerCase();
    final name = 'doc_${doc.id ?? 'x'}_${doc.size}_${doc.modified}_$key$ext';
    final cached = File(p.join(cacheDir.path, name));
    if (await cached.exists()) return cached.path;
    await _pruneCache(cacheDir, keepName: name);
    final copied = await Saf.copyToCache(uri, name);
    if (copied == null) {
      throw StateError('Could not read ${doc.displayName}');
    }
    return copied;
  }

  static Future<Directory> _cacheDir() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, 'doc_cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Keeps at most ~100 cached copies.
  static Future<void> _pruneCache(Directory dir, {String? keepName}) async {
    final files = await dir
        .list()
        .where((e) => e is File && p.basename(e.path) != keepName)
        .cast<File>()
        .toList();
    if (files.length <= 100) return;
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final f in files.take(files.length - 100)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
