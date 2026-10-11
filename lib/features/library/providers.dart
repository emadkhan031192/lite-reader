import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/db/app_database.dart';
import '../../core/models/document.dart';
import '../../core/pdf/pdf_facade.dart';
import '../../core/platform/saf.dart';
import '../../core/services/doc_source.dart';
import '../../core/services/library_service.dart';

/// Tabs on the Files screen.
enum LibraryTab {
  all('All'),
  pdf('PDF'),
  office('Office'),
  starred('Starred');

  const LibraryTab(this.label);

  final String label;
}

/// Sorts a document list. Pure — safe to unit test.
List<LibraryDocument> sortDocuments(
  List<LibraryDocument> docs,
  LibrarySort sort,
) {
  final sorted = List<LibraryDocument>.of(docs);
  switch (sort) {
    case LibrarySort.name:
      sorted.sort(
        (a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()),
      );
    case LibrarySort.date:
      sorted.sort((a, b) => b.modified.compareTo(a.modified));
    case LibrarySort.size:
      sorted.sort((a, b) => b.size.compareTo(a.size));
  }
  return sorted;
}

/// Filters by tab and search query (case-insensitive name match).
/// Pure — safe to unit test.
List<LibraryDocument> filterDocuments(
  List<LibraryDocument> docs,
  LibraryTab tab,
  String query,
) {
  final q = query.trim().toLowerCase();
  return docs.where((doc) {
    switch (tab) {
      case LibraryTab.all:
        break;
      case LibraryTab.pdf:
        if (!doc.isPdf) return false;
      case LibraryTab.office:
        if (doc.isPdf) return false;
      case LibraryTab.starred:
        if (!doc.starred) return false;
    }
    if (q.isNotEmpty && !doc.displayName.toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }).toList();
}

/// The library document list, backed by SQLite.
class LibraryDocs extends AsyncNotifier<List<LibraryDocument>> {
  @override
  Future<List<LibraryDocument>> build() async {
    final docs = await AppDatabase.instance.getAllDocuments();
    // Fill in unknown page counts without blocking the first frame.
    unawaited(_fillPageCounts(docs));
    return docs;
  }

  /// Reads page counts for PDFs that don't have one yet (skips
  /// password-protected files — the reader asks for the password later).
  Future<void> _fillPageCounts(List<LibraryDocument> docs) async {
    var changed = false;
    for (final doc in docs) {
      final id = doc.id;
      if (id == null || !doc.isPdf || doc.pageCount > 0) continue;
      try {
        final path = await DocSource.resolvePath(doc);
        final count = await PdfFacade.pageCount(path);
        await AppDatabase.instance.updatePageCount(id, count);
        changed = true;
      } on PdfPasswordException {
        // Password-protected: page count stays unknown for now.
      } catch (_) {
        // Unreadable file: leave the page count unknown.
      }
      if (!ref.mounted) return;
    }
    if (changed && ref.mounted) {
      state = AsyncValue.data(await AppDatabase.instance.getAllDocuments());
    }
  }

  /// Rescans the added SAF folders and reloads the list.
  /// Returns the rescan diff so the caller can decide about a snackbar.
  Future<RescanResult> refresh() async {
    final result = await ref.read(libraryServiceProvider).rescan();
    final docs = await AppDatabase.instance.getAllDocuments();
    state = AsyncValue.data(docs);
    unawaited(_fillPageCounts(docs));
    return result;
  }

  /// Optimistic star toggle.
  Future<void> toggleStar(int id) async {
    final docs = state.value;
    if (docs == null) return;
    LibraryDocument? target;
    for (final d in docs) {
      if (d.id == id) {
        target = d;
        break;
      }
    }
    if (target == null) return;
    final next = !target.starred;
    state = AsyncValue.data(
      [for (final d in docs) d.id == id ? d.copyWith(starred: next) : d],
    );
    await AppDatabase.instance.setStarred(id, next);
  }

  /// Deletes documents (and their progress/bookmarks/annotations rows).
  Future<void> removeDocuments(List<int> ids) async {
    for (final id in ids) {
      await AppDatabase.instance.deleteDocument(id);
    }
    ref.read(selectionProvider.notifier).clear();
    state = await AsyncValue.guard(
      () => AppDatabase.instance.getAllDocuments(),
    );
  }

  /// Lets the user pick a folder via SAF, registers it, then rescans.
  /// Does nothing when the user cancels the picker.
  Future<void> addFolder() async {
    final treeUri = await Saf.pickDocumentTree();
    if (treeUri == null) return;
    await ref
        .read(libraryServiceProvider)
        .addFolder(treeUri, _folderLabel(treeUri));
    await refresh();
  }

  String _folderLabel(String treeUri) {
    try {
      final decoded = Uri.decodeComponent(treeUri.split('/').last);
      final label = decoded.split(':').last.trim();
      if (label.isNotEmpty) return label;
    } catch (_) {}
    return 'Folder';
  }
}

final libraryDocsProvider =
    AsyncNotifierProvider<LibraryDocs, List<LibraryDocument>>(LibraryDocs.new);

class LibraryTabController extends Notifier<LibraryTab> {
  @override
  LibraryTab build() => LibraryTab.all;

  void set(LibraryTab tab) {
    if (state != tab) state = tab;
  }
}

final libraryTabProvider =
    NotifierProvider<LibraryTabController, LibraryTab>(
  LibraryTabController.new,
);

class LibrarySortController extends Notifier<LibrarySort> {
  @override
  LibrarySort build() => LibrarySort.name;

  void set(LibrarySort sort) {
    if (state != sort) state = sort;
  }
}

final librarySortProvider =
    NotifierProvider<LibrarySortController, LibrarySort>(
  LibrarySortController.new,
);

class LibraryQueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) {
    if (state != query) state = query;
  }
}

final libraryQueryProvider =
    NotifierProvider<LibraryQueryController, String>(
  LibraryQueryController.new,
);

/// The set of selected document ids (selection mode).
class Selection extends Notifier<Set<int>> {
  @override
  Set<int> build() => <int>{};

  void toggle(int id) {
    final next = Set<int>.of(state);
    if (!next.remove(id)) {
      next.add(id);
    }
    state = next;
  }

  void clear() {
    if (state.isNotEmpty) state = <int>{};
  }

  void selectAll(List<int> ids) {
    state = Set<int>.of(ids);
  }
}

final selectionProvider = NotifierProvider<Selection, Set<int>>(Selection.new);

/// Reading progress for one document: saved page / page count,
/// clamped to 0..1. 0 when the page or the page count is unknown.
final docProgressProvider = FutureProvider.family<double, int>(
  (ref, docId) async {
    final docs = await ref.watch(libraryDocsProvider.future);
    LibraryDocument? doc;
    for (final d in docs) {
      if (d.id == docId) {
        doc = d;
        break;
      }
    }
    if (doc == null || doc.pageCount <= 0) return 0;
    final saved = await AppDatabase.instance.getProgress(docId);
    final page = (saved?['page'] as num?)?.toInt() ?? 0;
    if (page <= 0) return 0;
    return (page / doc.pageCount).clamp(0.0, 1.0);
  },
);
