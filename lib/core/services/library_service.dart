import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../models/document.dart';
import '../platform/saf.dart';

/// MIME types tracked by the library.
const _pdfMime = 'application/pdf';
const _officeMimes = {
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

/// Sort orders for the Files tab.
enum LibrarySort { name, date, size }

/// Scans SAF folders and diffs the library by URI, size and modified time.
class LibraryService {
  LibraryService(this._db);

  final AppDatabase _db;

  /// Rescans every added folder in the background. Returns counts of
  /// added/updated/removed rows.
  Future<RescanResult> rescan() async {
    final folders = await _db.getFolders();
    final seen = <String>{};
    var added = 0;
    var updated = 0;

    for (final folder in folders) {
      final counts = await _scanTree(folder['tree_uri'] as String, seen);
      added += counts.added;
      updated += counts.updated;
    }

    // Remove tree documents that no longer exist on disk.
    var removed = 0;
    final all = await _db.getAllDocuments();
    for (final doc in all) {
      if (doc.source == 'tree' && !seen.contains(doc.uri) && doc.id != null) {
        await _db.deleteDocument(doc.id!);
        removed++;
      }
    }
    return RescanResult(added: added, updated: updated, removed: removed);
  }

  /// Registers a new SAF tree and scans it immediately.
  Future<void> addFolder(String treeUri, String displayName) async {
    await _db.addFolder(treeUri, displayName);
    await _scanTree(treeUri, <String>{});
  }

  /// Scans one SAF tree, adding [seen] URIs. Returns added/updated counts.
  Future<RescanResult> _scanTree(String treeUri, Set<String> seen) async {
    var added = 0;
    var updated = 0;
    List<SafEntry> entries;
    try {
      entries = await Saf.listTree(treeUri);
    } catch (_) {
      return const RescanResult(added: 0, updated: 0, removed: 0);
    }
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      if (entry.mimeType != _pdfMime && !_officeMimes.contains(entry.mimeType)) {
        continue;
      }
      seen.add(entry.uri);
      final existing = await _db.getDocumentByUri(entry.uri);
      if (existing == null) {
        await _db.upsertDocument(LibraryDocument(
          uri: entry.uri,
          source: 'tree',
          displayName: entry.displayName,
          mimeType: entry.mimeType,
          size: entry.size,
          modified: entry.lastModified,
        ));
        added++;
      } else if (existing.size != entry.size ||
          existing.modified != entry.lastModified ||
          existing.displayName != entry.displayName) {
        await _db.upsertDocument(existing.copyWith(
          displayName: entry.displayName,
          size: entry.size,
          modified: entry.lastModified,
        ));
        updated++;
      }
    }
    return RescanResult(added: added, updated: updated, removed: 0);
  }

  /// Registers a file opened from outside (intent, share, file picker).
  Future<LibraryDocument> registerExternal({
    required String uri,
    required String displayName,
    String mimeType = _pdfMime,
    int size = 0,
    int modified = 0,
  }) async {
    final existing = await _db.getDocumentByUri(uri);
    if (existing != null) return existing;
    final id = await _db.upsertDocument(LibraryDocument(
      uri: uri,
      source: 'external',
      displayName: displayName,
      mimeType: mimeType,
      size: size,
      modified: modified,
    ));
    final doc = await _db.getDocumentById(id);
    return doc!;
  }
}

class RescanResult {
  const RescanResult({
    required this.added,
    required this.updated,
    required this.removed,
  });

  final int added;
  final int updated;
  final int removed;

  bool get isEmpty => added == 0 && updated == 0 && removed == 0;
}

final libraryServiceProvider = Provider<LibraryService>(
  (ref) => LibraryService(AppDatabase.instance),
);
