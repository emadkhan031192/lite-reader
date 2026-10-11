import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../models/document.dart';
import '../pdf/pdf_facade.dart';
import 'doc_source.dart';

/// On-disk thumbnail cache (~120px wide PNGs). Capped in size; oldest
/// entries are pruned first.
class ThumbnailService {
  ThumbnailService(this._db);

  final AppDatabase _db;

  static const maxFiles = 300;
  static const maxBytes = 12 * 1024 * 1024;

  Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'thumbnails'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _nameFor(LibraryDocument doc) => 'thumb_${doc.id}.png';

  /// Returns the cached thumbnail path, generating it on first use.
  /// Returns null for non-PDFs or when rendering fails.
  Future<String?> ensureThumbnail(LibraryDocument doc) async {
    if (!doc.isPdf || doc.id == null) return null;
    final dir = await _dir();
    final file = File(p.join(dir.path, _nameFor(doc)));
    if (await file.exists()) return file.path;
    try {
      final path = await DocSource.resolvePath(doc);
      final png = await PdfFacade.renderPagePng(
        path,
        1,
        widthPx: 120,
      );
      await file.writeAsBytes(png, flush: true);
      await _db.updateThumbnail(doc.id!, file.path);
      await _prune(dir);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Clears the whole thumbnail cache (Settings action).
  Future<void> clear() async {
    final dir = await _dir();
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    }
    final db = await _db.database;
    await db.update('documents', {'thumbnail_path': null});
  }

  Future<void> _prune(Directory dir) async {
    final files = <File>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        files.add(e);
        total += await e.length();
      }
    }
    if (files.length <= maxFiles && total <= maxBytes) return;
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    for (final f in files) {
      if (files.length <= maxFiles && total <= maxBytes) break;
      try {
        total -= await f.length();
        await f.delete();
      } catch (_) {}
    }
  }
}

final thumbnailServiceProvider = Provider<ThumbnailService>(
  (ref) => ThumbnailService(AppDatabase.instance),
);
