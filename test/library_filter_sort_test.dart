import 'package:flutter_test/flutter_test.dart';
import 'package:litereader/core/models/document.dart';
import 'package:litereader/core/services/library_service.dart';
import 'package:litereader/features/library/providers.dart';

LibraryDocument _doc(
  String name, {
  String mime = 'application/pdf',
  int size = 100,
  int modified = 10,
  bool starred = false,
}) =>
    LibraryDocument(
      uri: 'test://$name',
      source: 'app',
      displayName: name,
      mimeType: mime,
      size: size,
      modified: modified,
      starred: starred,
    );

const _officeMime =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

void main() {
  group('sortDocuments', () {
    test('by name, case-insensitive ascending', () {
      final docs = [_doc('b.pdf'), _doc('A.pdf'), _doc('c.pdf')];
      final sorted = sortDocuments(docs, LibrarySort.name);
      expect(
        sorted.map((d) => d.displayName),
        ['A.pdf', 'b.pdf', 'c.pdf'],
      );
    });

    test('by size, largest first', () {
      final docs = [_doc('a.pdf', size: 10), _doc('b.pdf', size: 50)];
      final sorted = sortDocuments(docs, LibrarySort.size);
      expect(sorted.map((d) => d.displayName), ['b.pdf', 'a.pdf']);
    });

    test('by date, newest first', () {
      final docs = [_doc('a.pdf', modified: 5), _doc('b.pdf', modified: 9)];
      final sorted = sortDocuments(docs, LibrarySort.date);
      expect(sorted.map((d) => d.displayName), ['b.pdf', 'a.pdf']);
    });

    test('does not mutate the input list', () {
      final docs = [_doc('b.pdf'), _doc('a.pdf')];
      sortDocuments(docs, LibrarySort.name);
      expect(docs.map((d) => d.displayName), ['b.pdf', 'a.pdf']);
    });
  });

  group('filterDocuments', () {
    final docs = [
      _doc('report.pdf'),
      _doc('notes.docx', mime: _officeMime),
      _doc('starred.pdf', starred: true),
    ];

    test('all tab keeps everything', () {
      expect(filterDocuments(docs, LibraryTab.all, ''), hasLength(3));
    });

    test('pdf tab hides office files', () {
      final filtered = filterDocuments(docs, LibraryTab.pdf, '');
      expect(filtered.map((d) => d.displayName),
          containsAll(['report.pdf', 'starred.pdf']));
      expect(
        filtered.map((d) => d.displayName),
        isNot(contains('notes.docx')),
      );
    });

    test('office tab shows only office files', () {
      final filtered = filterDocuments(docs, LibraryTab.office, '');
      expect(
        filtered.map((d) => d.displayName),
        ['notes.docx'],
      );
    });

    test('starred tab shows only starred', () {
      final filtered = filterDocuments(docs, LibraryTab.starred, '');
      expect(
        filtered.map((d) => d.displayName),
        ['starred.pdf'],
      );
    });

    test('query matches names case-insensitively', () {
      final filtered = filterDocuments(docs, LibraryTab.all, 'REPORT');
      expect(
        filtered.map((d) => d.displayName),
        ['report.pdf'],
      );
    });
  });
}
