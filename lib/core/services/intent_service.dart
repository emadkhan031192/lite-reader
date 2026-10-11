import '../db/app_database.dart';
import '../platform/device.dart';
import 'doc_source.dart';
import 'library_service.dart';

/// Handles "Open with" / share intents (cold and warm start).
///
/// Registers the incoming file in the library, then asks the UI to open it.
class IntentService {
  IntentService._();

  static final IntentService instance = IntentService._();

  bool _attached = false;

  void attach({
    required void Function(int documentId) onOpenDocument,
    required void Function(String message) onError,
  }) {
    if (_attached) return;
    _attached = true;
    Future<void> handle(IncomingFile file) async {
      try {
        final db = AppDatabase.instance;
        final service = LibraryService(db);
        final displayName =
            file.displayName ?? file.uri.split('/').last.ifEmpty('document.pdf');
        final doc = await service.registerExternal(
          uri: file.uri,
          displayName: displayName,
          mimeType: file.mimeType,
        );
        // Warm the cached copy so the reader opens instantly.
        try {
          await DocSource.resolvePath(doc);
        } catch (_) {}
        onOpenDocument(doc.id!);
      } catch (_) {
        onError('Could not open that file.');
      }
    }

    Intents.listen(handle);
    Intents.getInitialFile().then((file) {
      if (file != null) handle(file);
    });
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
