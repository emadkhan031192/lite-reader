import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/document.dart';
import '../../../core/pdf/pdf_facade.dart';
import '../../../core/platform/saf.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/press_scale.dart';

/// Bottom sheet shown after a tool finishes: lists each output file with
/// its name and mono size, plus Open / Share / Save to… actions.
/// An optional [note] (e.g. before/after sizes) is shown under the title.
Future<void> showToolResultSheet(
  BuildContext context, {
  required List<String> paths,
  String? note,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => _ToolResultSheet(paths: paths, note: note),
  );
}

class _ResultFile {
  const _ResultFile({
    required this.path,
    required this.size,
    required this.pageCount,
  });

  final String path;
  final int size;
  final int pageCount;
}

class _ToolResultSheet extends StatefulWidget {
  const _ToolResultSheet({super.key, required this.paths, this.note});

  final List<String> paths;
  final String? note;

  @override
  State<_ToolResultSheet> createState() => _ToolResultSheetState();
}

class _ToolResultSheetState extends State<_ToolResultSheet> {
  late final Future<List<_ResultFile>> _files = _load();

  Future<List<_ResultFile>> _load() async {
    final out = <_ResultFile>[];
    for (final path in widget.paths) {
      var size = 0;
      var pages = 0;
      try {
        size = await File(path).length();
      } catch (_) {
        // Missing file: report 0 B rather than failing the sheet.
      }
      try {
        pages = await PdfFacade.pageCount(path);
      } catch (_) {
        // Unreadable file: page count stays 0.
      }
      out.add(_ResultFile(path: path, size: size, pageCount: pages));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Done',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            if (widget.note != null) ...[
              const SizedBox(height: 4),
              Text(widget.note!, style: AppText.monoSize(12)),
            ],
            const SizedBox(height: 8),
            Flexible(
              child: FutureBuilder<List<_ResultFile>>(
                future: _files,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final files = snapshot.data!;
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (context, i) => _row(context, files[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _ResultFile file) {
    final name = p.basename(file.path);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: AppText.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${formatBytes(file.size)} · ${file.pageCount} pages',
            style: AppText.monoSize(12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _action('Open', () => _open(context, file)),
              _action('Share', () => _share(file)),
              _action('Save to…', () => _saveTo(context, file)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.only(right: 8),
          decoration: const BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppText.zenKaku,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, _ResultFile file) async {
    final id = await AppDatabase.instance.upsertDocument(
      LibraryDocument(
        uri: file.path,
        source: 'app',
        displayName: p.basename(file.path),
        mimeType: 'application/pdf',
        size: file.size,
        modified: DateTime.now().millisecondsSinceEpoch,
        pageCount: file.pageCount,
      ),
    );
    if (context.mounted) context.go('/reader?documentId=$id');
  }

  Future<void> _share(_ResultFile file) {
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: p.basename(file.path),
      ),
    );
  }

  Future<void> _saveTo(BuildContext context, _ResultFile file) async {
    final container = ProviderScope.containerOf(context);
    final settings = container.read(settingsProvider);
    var treeUri = settings.chosenFolderUri ?? settings.lastUsedFolderUri;
    treeUri ??= await Saf.pickDocumentTree();
    if (treeUri == null) return;
    final uri = await Saf.createInTree(
      treeUri: treeUri,
      displayName: p.basename(file.path),
      mimeType: 'application/pdf',
      sourcePath: file.path,
    );
    await container.read(settingsProvider.notifier).noteFolderUsed(treeUri);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null ? 'Could not save the file.' : 'Saved',
          ),
        ),
      );
    }
  }
}
