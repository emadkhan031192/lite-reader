import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/pdf/pdf_facade.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'widgets/doc_picker_field.dart';
import 'widgets/tool_result_sheet.dart';
import 'widgets/tool_run.dart';
import 'widgets/tool_scaffold.dart';

/// Reorders pages by dragging thumbnails into the new order.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key, required this.documentId});

  final int documentId;

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  late int _docId = widget.documentId;
  Future<ResolvedDoc?>? _docFuture;
  List<int>? _order;
  final _thumbs = <int, Uint8List>{};
  bool _running = false;

  @override
  void initState() {
    super.initState();
    if (_docId != 0) _docFuture = _load(_docId);
  }

  Future<ResolvedDoc?> _load(int id) async {
    try {
      final resolved = await resolveDocForTool(id);
      if (mounted) {
        setState(() {
          _order = List<int>.generate(
            resolved.pageCount,
            (i) => i + 1,
          );
        });
      }
      return resolved;
    } on PdfPasswordException {
      return null;
    } catch (_) {
      return null;
    }
  }

  void _selectDoc(int id) {
    setState(() {
      _docId = id;
      _order = null;
      _thumbs.clear();
      _docFuture = _load(id);
    });
  }

  Future<void> _run() async {
    final order = _order;
    if (_running || _docId == 0 || order == null) return;
    final resolved = await _docFuture;
    if (!mounted) return;
    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password-protected files need to be opened in the reader first.',
          ),
        ),
      );
      return;
    }
    setState(() => _running = true);
    try {
      final dir = await toolOutputDir();
      if (!mounted) return;
      final base = toolBaseName(resolved.document.displayName);
      final outPath = '${dir.path}/${base}_reordered.pdf';
      final outputs = await runToolWithProgress(
        context,
        {
          'kind': 'reorder',
          'inPath': resolved.path,
          'outPath': outPath,
          'dpi': 150,
          'quality': 85,
          'order': order,
        },
        title: 'Reordering…',
      );
      if (!mounted) return;
      if (outputs != null) await showToolResultSheet(context, paths: outputs);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      title: 'Reorder pages',
      children: [
        DocPickerField(
          documentId: _docId == 0 ? null : _docId,
          onChanged: _selectDoc,
        ),
        const SizedBox(height: 16),
        FutureBuilder<ResolvedDoc?>(
          future: _docFuture,
          builder: (context, snapshot) {
            if (_docId == 0) {
              return const Text(
                'Choose a document to begin.',
                style: AppText.bodySecondary,
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final resolved = snapshot.data;
            final order = _order;
            if (resolved == null || order == null) {
              return const Text(
                'This file is password-protected. Open it in the reader first.',
                style: AppText.bodySecondary,
              );
            }
            return ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: order.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                                    final page = order.removeAt(oldIndex);
                  order.insert(newIndex, page);
                });
              },
              itemBuilder: (context, i) {
                final page = order[i];
                return _PageRow(
                  key: ValueKey(page),
                  page: page,
                  path: resolved.path,
                  cache: _thumbs,
                );
              },
            );
          },
        ),
        const SizedBox(height: 16),
        const RasterNote(),
        const SizedBox(height: 16),
        RunButton(
          label: _running ? 'Working…' : 'Reorder',
          onPressed: _docId != 0 && _order != null && !_running ? _run : null,
        ),
      ],
    );
  }
}

/// One page row: lazily rendered thumbnail (cached in memory) + mono page
/// number + drag handle.
class _PageRow extends StatefulWidget {
  const _PageRow({
    super.key,
    required this.page,
    required this.path,
    required this.cache,
  });

  final int page;
  final String path;
  final Map<int, Uint8List> cache;

  @override
  State<_PageRow> createState() => _PageRowState();
}

class _PageRowState extends State<_PageRow> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.cache[widget.page];
    if (_bytes == null) {
      PdfFacade.renderPagePng(widget.path, widget.page, widthPx: 120).then(
        (bytes) {
          widget.cache[widget.page] = bytes;
          if (mounted) setState(() => _bytes = bytes);
        },
      ).catchError((Object _) {
        // A single failed thumbnail must not break the list.
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 88,
            child: _bytes == null
                ? const ColoredBox(color: AppColors.background)
                : Image.memory(_bytes!, fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${widget.page}',
              style: AppText.monoSize(15, color: AppColors.ink),
            ),
          ),
          const Icon(
            Icons.drag_handle,
            size: 22,
            color: AppColors.tertiary,
          ),
        ],
      ),
    );
  }
}
