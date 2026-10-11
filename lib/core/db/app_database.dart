import 'package:sqflite/sqflite.dart';

import '../models/annotation.dart';
import '../models/document.dart';

/// SQLite storage for the library, bookmarks, annotations, progress and
/// saved signatures. Everything stays on the phone.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _name = 'litereader.db';
  static const _version = 1;

  Database? _db;

  Future<Database> get database async {
    final db = _db;
    if (db != null) return db;
    return _db = await _open();
  }

  /// Opens an in-memory database. Used by tests.
  Future<Database> openForTest() => openDatabase(
        inMemoryDatabasePath,
        version: _version,
        onCreate: _create,
      );

  Future<Database> _open() async {
    final path = '${await getDatabasesPath()}/$_name';
    return openDatabase(
      path,
      version: _version,
      onCreate: _create,
    );
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tree_uri TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE documents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uri TEXT NOT NULL UNIQUE,
        source TEXT NOT NULL,
        display_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL,
        modified INTEGER NOT NULL,
        page_count INTEGER NOT NULL DEFAULT 0,
        thumbnail_path TEXT,
        starred INTEGER NOT NULL DEFAULT 0,
        last_opened INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE progress(
        document_id INTEGER PRIMARY KEY,
        page INTEGER NOT NULL,
        zoom REAL NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE bookmarks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        page INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(document_id, page)
      )
    ''');
    await db.execute('''
      CREATE TABLE annotations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        page INTEGER NOT NULL,
        type TEXT NOT NULL,
        color INTEGER NOT NULL,
        opacity REAL NOT NULL,
        stroke_width REAL NOT NULL,
        rect_json TEXT,
        points_json TEXT,
        text TEXT,
        image_path TEXT,
        note TEXT,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE signatures(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        image_path TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_documents_last_opened ON documents(last_opened)');
    await db.execute(
        'CREATE INDEX idx_annotations_doc_page ON annotations(document_id, page)');
    await db.execute(
        'CREATE INDEX idx_bookmarks_doc ON bookmarks(document_id)');
  }

  // ---------- folders ----------

  Future<List<Map<String, Object?>>> getFolders() async {
    final db = await database;
    return db.query('folders', orderBy: 'added_at ASC');
  }

  Future<void> addFolder(String treeUri, String displayName) async {
    final db = await database;
    await db.insert(
      'folders',
      {
        'tree_uri': treeUri,
        'display_name': displayName,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Removes a folder and every document discovered through it (bookmarks,
  /// progress and annotations cascade). Files on the device are untouched.
  Future<void> removeFolder(String treeUri) async {
    final db = await database;
    final rows = await db.query(
      'folders',
      columns: ['id'],
      where: 'tree_uri = ?',
      whereArgs: [treeUri],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final id = rows.first['id'] as int;
      await db.delete('documents', where: 'folder_id = ?', whereArgs: [id]);
    }
    await db.delete('folders', where: 'tree_uri = ?', whereArgs: [treeUri]);
  }

  // ---------- documents ----------

  Future<int> upsertDocument(LibraryDocument doc) async {
    final db = await database;
    return db.insert(
      'documents',
      doc.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDocument(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('documents', where: 'id = ?', whereArgs: [id]);
      await txn.delete('progress', where: 'document_id = ?', whereArgs: [id]);
      await txn.delete('bookmarks', where: 'document_id = ?', whereArgs: [id]);
      await txn
          .delete('annotations', where: 'document_id = ?', whereArgs: [id]);
    });
  }

  Future<List<LibraryDocument>> getAllDocuments() async {
    final db = await database;
    final rows = await db.query('documents');
    return rows.map(LibraryDocument.fromMap).toList();
  }

  Future<LibraryDocument?> getDocumentByUri(String uri) async {
    final db = await database;
    final rows =
        await db.query('documents', where: 'uri = ?', whereArgs: [uri]);
    if (rows.isEmpty) return null;
    return LibraryDocument.fromMap(rows.first);
  }

  Future<LibraryDocument?> getDocumentById(int id) async {
    final db = await database;
    final rows = await db.query('documents', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return LibraryDocument.fromMap(rows.first);
  }

  Future<void> setStarred(int id, bool starred) async {
    final db = await database;
    await db.update(
      'documents',
      {'starred': starred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touchLastOpened(int id) async {
    final db = await database;
    await db.update(
      'documents',
      {'last_opened': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePageCount(int id, int pageCount) async {
    final db = await database;
    await db.update(
      'documents',
      {'page_count': pageCount},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThumbnail(int id, String path) async {
    final db = await database;
    await db.update(
      'documents',
      {'thumbnail_path': path},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- progress ----------

  Future<void> saveProgress(int documentId, int page, double zoom) async {
    final db = await database;
    await db.insert(
      'progress',
      {
        'document_id': documentId,
        'page': page,
        'zoom': zoom,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getProgress(int documentId) async {
    final db = await database;
    final rows = await db.query(
      'progress',
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ---------- bookmarks ----------

  Future<List<int>> getBookmarkPages(int documentId) async {
    final db = await database;
    final rows = await db.query(
      'bookmarks',
      columns: ['page'],
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'page ASC',
    );
    return rows.map((r) => (r['page'] as num).toInt()).toList();
  }

  Future<bool> isBookmarked(int documentId, int page) async {
    final db = await database;
    final rows = await db.query(
      'bookmarks',
      columns: ['id'],
      where: 'document_id = ? AND page = ?',
      whereArgs: [documentId, page],
    );
    return rows.isNotEmpty;
  }

  Future<void> toggleBookmark(int documentId, int page) async {
    final db = await database;
    final marked = await isBookmarked(documentId, page);
    if (marked) {
      await db.delete(
        'bookmarks',
        where: 'document_id = ? AND page = ?',
        whereArgs: [documentId, page],
      );
    } else {
      await db.insert('bookmarks', {
        'document_id': documentId,
        'page': page,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  // ---------- annotations ----------

  Future<int> insertAnnotation(PdfAnnotation annotation) async {
    final db = await database;
    final map = annotation.toMap()
      ..['created_at'] = DateTime.now().millisecondsSinceEpoch;
    return db.insert('annotations', map);
  }

  Future<void> updateAnnotation(PdfAnnotation annotation) async {
    final db = await database;
    await db.update(
      'annotations',
      annotation.toMap(),
      where: 'id = ?',
      whereArgs: [annotation.id],
    );
  }

  Future<void> deleteAnnotation(int id) async {
    final db = await database;
    await db.delete('annotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PdfAnnotation>> getAnnotations(int documentId, int page) async {
    final db = await database;
    final rows = await db.query(
      'annotations',
      where: 'document_id = ? AND page = ?',
      whereArgs: [documentId, page],
      orderBy: 'id ASC',
    );
    return rows.map(PdfAnnotation.fromMap).toList();
  }

  Future<List<PdfAnnotation>> getAllAnnotations(int documentId) async {
    final db = await database;
    final rows = await db.query(
      'annotations',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'page ASC, id ASC',
    );
    return rows.map(PdfAnnotation.fromMap).toList();
  }

  // ---------- signatures ----------

  Future<int> saveSignature(String name, String imagePath) async {
    final db = await database;
    return db.insert('signatures', {
      'name': name,
      'image_path': imagePath,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> getSignatures() async {
    final db = await database;
    return db.query('signatures', orderBy: 'created_at DESC');
  }

  Future<void> deleteSignature(int id) async {
    final db = await database;
    await db.delete('signatures', where: 'id = ?', whereArgs: [id]);
  }
}
