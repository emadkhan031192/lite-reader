import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/section_label.dart';
import 'widgets/doc_picker_field.dart';
import 'widgets/tool_result_sheet.dart';
import 'widgets/tool_run.dart';
import 'widgets/tool_scaffold.dart';

/// Parses "1-5, 6-10" (1-based inclusive page ranges) against [pageCount].
/// Returns an empty list when the text is invalid in any way.
List<List<int>> parseRanges(String text, int pageCount) {
  final ranges = <List<int>>[];
  for (final part in text.split(',')) {
    final match =
        RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$').firstMatch(part);
    if (match == null) return [];
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    if (start < 1 || end > pageCount || start > end) return [];
    ranges.add([start, end]);
  }
  return ranges;
}

/// Splits a PDF at a page or by page ranges. Each range becomes its own file.
class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key, required this.documentId});

  final int documentId;

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  late int _docId = widget.documentId;
  Future<ResolvedDoc?>? _docFuture;
  bool _byRange = false;
  bool _running = false;
  final _pageController = TextEditingController();
  final _rangesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_docId != 0) _docFuture = _load(_docId);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _rangesController.dispose();
    super.dispose();
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
    final pageCount = resolved.pageCount;
    final List<List<int>> ranges;
    if (_byRange) {
      ranges = parseRanges(_rangesController.text, pageCount);
      if (ranges.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter valid ranges like "1-5, 6-10".'),
          ),
        );
        return;
      }
    } else {
      final at = int.tryParse(_pageController.text.trim()) ?? 0;
      if (at < 1 || at >= pageCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enter a page between 1 and ${pageCount - 1}.'),
          ),
        );
        return;
      }
      ranges = [
        [1, at],
        [at + 1, pageCount],
      ];
    }
    setState(() => _running = true);
    try {
      final dir = await toolOutputDir();
      final base = toolBaseName(resolved.document.displayName);
      final outputs = await runToolWithProgress(
        context,
        {
          'kind': 'split',
          'inPath': resolved.path,
          'outDir': dir.path,
          'baseName': base,
          'dpi': 150,
          'quality': 85,
          'ranges': ranges,
        },
        title: 'Splitting…',
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
      title: 'Split',
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
              '${resolved.pageCount} pages',
              style: AppText.monoSize(13),
            );
          },
        ),
        const SizedBox(height: 16),
        const SectionLabel('Mode'),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('At page')),
            ButtonSegment(value: true, label: Text('By range')),
          ],
          selected: {_byRange},
          onSelectionChanged: (s) => setState(() => _byRange = s.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.accentTint,
            selectedForegroundColor: AppColors.accent,
          ),
        ),
        const SizedBox(height: 12),
        if (!_byRange)
          TextField(
            controller: _pageController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Split after page',
              hintText: 'e.g. 5',
              border: OutlineInputBorder(),
            ),
          )
        else
          TextField(
            controller: _rangesController,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Ranges',
              hintText: '1-5, 6-10',
              border: OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 16),
        const RasterNote(),
        const SizedBox(height: 16),
        RunButton(
          label: _running ? 'Working…' : 'Split',
          onPressed: _docId != 0 && !_running ? _run : null,
        ),
      ],
    );
  }
}
