import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/section_label.dart';
import 'widgets/doc_picker_field.dart';
import 'widgets/tool_result_sheet.dart';
import 'widgets/tool_run.dart';
import 'widgets/tool_scaffold.dart';

/// Re-renders a PDF at a lower DPI to make a smaller copy.
/// The original file is never changed.
class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key, required this.documentId});

  final int documentId;

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  late int _docId = widget.documentId;
  Future<ResolvedDoc?>? _docFuture;
  double _dpi = 110;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    if (_docId != 0) _docFuture = _load(_docId);
  }

  Future<ResolvedDoc?> _load(int id) async {
    try {
      return await resolveDocForTool(id);
    } on PdfPasswordException {
      return null;
    } catch (_) {
      return null;
    }
  }

  void _selectDoc(int id) {
    setState(() {
      _docId = id;
      _docFuture = _load(id);
    });
  }

  Future<void> _run() async {
    if (_running || _docId == 0) return;
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
      final before = resolved.document.size;
      final dir = await toolOutputDir();
      if (!mounted) return;
      final base = toolBaseName(resolved.document.displayName);
      final outPath = '${dir.path}/${base}_compressed.pdf';
      final outputs = await runToolWithProgress(
        context,
        {
          'kind': 'compress',
          'inPath': resolved.path,
          'outPath': outPath,
          'dpi': _dpi.round(),
          'quality': 70,
        },
        title: 'Compressing…',
      );
      if (!mounted) return;
      if (outputs != null && outputs.isNotEmpty) {
        var after = 0;
        try {
          after = await File(outputs.first).length();
        } catch (_) {
          // Size stays 0; the sheet still lists the file.
        }
        if (!mounted) return;
        await showToolResultSheet(
          context,
          paths: outputs,
          note:
              'Before ${formatBytes(before)} → after ${formatBytes(after)}',
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      title: 'Compress',
      children: [
        DocPickerField(
          documentId: _docId == 0 ? null : _docId,
          onChanged: _selectDoc,
        ),
        const SizedBox(height: 8),
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
            if (resolved == null) {
              return const Text(
                'This file is password-protected. Open it in the reader first.',
                style: AppText.bodySecondary,
              );
            }
            return Text(
              'Original: ${formatBytes(resolved.document.size)}',
              style: AppText.monoSize(13),
            );
          },
        ),
        const SizedBox(height: 16),
        const SectionLabel('Quality'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _dpi,
                min: 72,
                max: 200,
                divisions: 8,
                label: '${_dpi.round()} DPI',
                activeColor: AppColors.accent,
                inactiveColor: AppColors.hairline,
                onChanged: (v) => setState(() => _dpi = v),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                '${_dpi.round()} DPI',
                style: AppText.monoSize(13, color: AppColors.ink),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const Text(
          'Lower DPI means a smaller file and softer pages.',
          style: TextStyle(
            fontFamily: AppText.zenKaku,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.tertiary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        const RasterNote(),
        const SizedBox(height: 16),
        RunButton(
          label: _running ? 'Working…' : 'Compress',
          onPressed: _docId != 0 && !_running ? _run : null,
        ),
      ],
    );
  }
}
