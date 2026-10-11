import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/document.dart';
import '../../../core/pdf/pdf_facade.dart';
import '../../../core/pdf/tool_runner.dart';
import '../../../core/services/doc_source.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';

/// Runs [params] through [runPdfTool] in a background isolate, inside a
/// modal progress dialog (not dismissible). Returns the worker output paths,
/// or null when the tool failed — a SnackBar with the error is shown first.
Future<List<String>?> runToolWithProgress(
  BuildContext context,
  Map<String, Object?> params, {
  String title = 'Working…',
}) {
  final done = Completer<List<String>?>();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ToolProgressDialog(
      title: title,
      params: params,
      onDone: (outputs) {
        Navigator.of(dialogContext).pop();
        if (!done.isCompleted) done.complete(outputs);
      },
      onError: (message) {
        Navigator.of(dialogContext).pop();
        if (!done.isCompleted) done.complete(null);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
    ),
  );
  return done.future;
}

class _ToolProgressDialog extends StatefulWidget {
  const _ToolProgressDialog({
    required this.title,
    required this.params,
    required this.onDone,
    required this.onError,
  });

  final String title;
  final Map<String, Object?> params;
  final ValueChanged<List<String>> onDone;
  final ValueChanged<String> onError;

  @override
  State<_ToolProgressDialog> createState() => _ToolProgressDialogState();
}

class _ToolProgressDialogState extends State<_ToolProgressDialog> {
  StreamSubscription<ToolUpdate>? _sub;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _sub = runPdfTool(widget.params).listen((update) {
      if (!mounted) return;
      if (update.isError) {
        widget.onError(update.error ?? 'Something went wrong.');
      } else if (update.isDone) {
        widget.onDone(update.outputs ?? const []);
      } else {
        setState(() => _progress = update.progress ?? 0);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title, style: AppText.body),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _progress,
            color: AppColors.accent,
            backgroundColor: AppColors.accentTint,
            minHeight: 4,
          ),
          const SizedBox(height: 8),
          Text(
            formatPercent(_progress),
            style: AppText.monoSize(13),
            textAlign: TextAlign.end,
          ),
        ],
      ),
    );
  }
}

/// A library document resolved to a readable file path, with its page count.
/// Throws [PdfPasswordException] (from pdfrx) for password-protected files.
class ResolvedDoc {
  const ResolvedDoc({
    required this.document,
    required this.path,
    required this.pageCount,
  });

  final LibraryDocument document;
  final String path;
  final int pageCount;
}

/// Resolves [documentId] to a real file path and page count for tool screens.
Future<ResolvedDoc> resolveDocForTool(int documentId) async {
  final doc = await AppDatabase.instance.getDocumentById(documentId);
  if (doc == null) throw StateError('Document not found');
  final path = await DocSource.resolvePath(doc);
  final pageCount = await PdfFacade.pageCount(path);
  return ResolvedDoc(document: doc, path: path, pageCount: pageCount);
}

/// App-private output folder for tool results: `docs`/LiteReader/.
Future<Directory> toolOutputDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'LiteReader'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// File-safe base name for tool outputs.
String toolBaseName(String displayName) =>
    p.basenameWithoutExtension(displayName).replaceAll(
          RegExp(r'[^A-Za-z0-9._-]+'),
          '_',
        );
