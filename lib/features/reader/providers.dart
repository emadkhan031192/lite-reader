import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';

/// Session-only password for a password-protected PDF.
///
/// Scoped per document id. Never persisted to disk — the user re-enters it
/// on the next cold open.
class DocPassword extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? password) => state = password;

  void clear() => state = null;
}

final docPasswordProvider =
    NotifierProvider.family<DocPassword, String?, int>(
  (docId) => DocPassword(),
);

/// Bookmarked page numbers (1-based, ascending) for one document.
class BookmarkPages extends Notifier<List<int>> {
  BookmarkPages(this._documentId);

  final int _documentId;

  @override
  List<int> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    final pages =
        await AppDatabase.instance.getBookmarkPages(_documentId);
    state = pages;
  }

  /// Toggles the bookmark for [page], persists it, and refreshes the list.
  Future<void> toggle(int page) async {
    await AppDatabase.instance.toggleBookmark(_documentId, page);
    final pages =
        await AppDatabase.instance.getBookmarkPages(_documentId);
    state = pages;
  }

  bool isBookmarked(int page) => state.contains(page);
}

final bookmarkPagesProvider =
    NotifierProvider.family<BookmarkPages, List<int>, int>(
  (docId) => BookmarkPages(docId),
);
