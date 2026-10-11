import 'package:flutter_test/flutter_test.dart';
import 'package:litereader/core/db/app_database.dart';
import 'package:litereader/core/models/annotation.dart';
import 'package:litereader/core/models/document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LibraryDocument _doc(String tag) => LibraryDocument(
      uri: 'test://$tag-${DateTime.now().microsecondsSinceEpoch}.pdf',
      source: 'app',
      displayName: '$tag.pdf',
      mimeType: 'application/pdf',
      size: 1234,
      modified: 0,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Verifies the schema builds; app methods use the file-backed database.
    final probe = await AppDatabase.instance.openForTest();
    final tables = await probe.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((t) => t['name'] as String).toSet();
    expect(
      names,
      containsAll({
        'folders',
        'documents',
        'progress',
        'bookmarks',
        'annotations',
        'signatures',
      }),
    );
    await probe.close();
  });

  test('insert and get document', () async {
    final db = AppDatabase.instance;
    final id = await db.upsertDocument(_doc('insert'));
    final got = await db.getDocumentById(id);
    expect(got, isNotNull);
    expect(got!.displayName, 'insert.pdf');
    expect(got.isPdf, isTrue);
    expect(got.size, 1234);
  });

  test('saveProgress / getProgress round-trip', () async {
    final db = AppDatabase.instance;
    final id = await db.upsertDocument(_doc('progress'));
    await db.saveProgress(id, 12, 1.5);
    final progress = await db.getProgress(id);
    expect(progress, isNotNull);
    expect(progress!['page'], 12);
    expect(progress['zoom'], 1.5);
  });

  test('toggleBookmark adds and removes', () async {
    final db = AppDatabase.instance;
    final id = await db.upsertDocument(_doc('bookmark'));
    expect(await db.isBookmarked(id, 3), isFalse);
    await db.toggleBookmark(id, 3);
    expect(await db.isBookmarked(id, 3), isTrue);
    expect(await db.getBookmarkPages(id), [3]);
    await db.toggleBookmark(id, 3);
    expect(await db.isBookmarked(id, 3), isFalse);
  });

  test('insertAnnotation / getAnnotations round-trip', () async {
    final db = AppDatabase.instance;
    final id = await db.upsertDocument(_doc('annotation'));
    final annotationId = await db.insertAnnotation(
      PdfAnnotation(
        documentId: id,
        page: 1,
        type: AnnotationType.highlight,
        color: 0xFFFFD60A,
        rect: const [0.0, 0.0, 1.0, 0.1],
      ),
    );
    expect(annotationId, greaterThan(0));
    final page = await db.getAnnotations(id, 1);
    expect(page, hasLength(1));
    expect(page.first.rect, [0.0, 0.0, 1.0, 0.1]);
    expect(page.first.opacity, 0.55);
    final all = await db.getAllAnnotations(id);
    expect(all, hasLength(1));
    expect(await db.getAnnotations(id, 2), isEmpty);
  });

  test('saveSignature / getSignatures', () async {
    final db = AppDatabase.instance;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await db.saveSignature('sig-$stamp', '/tmp/sig-$stamp.png');
    final signatures = await db.getSignatures();
    expect(
      signatures.any((s) => s['name'] == 'sig-$stamp'),
      isTrue,
    );
  });
}
