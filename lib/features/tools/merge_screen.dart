import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/db/app_database.dart';
import '../../core/models/document.dart';
import '../../core/pdf/pdf_facade.dart';
import '../../core/services/doc_source.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/lr_icon_button.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/section_label.dart';
import 'widgets/tool_result_sheet.dart';
import 'widgets/tool_run.dart';
import 'widgets/tool_scaffold.dart';

/// Merges several PDFs into one, in the chosen order.
/// Pages are re-rendered as images: text won't be selectable in the copy.
class MergeScreen extends StatefulWidget {
  const MergeScreen({super.key, required this.initialDocumentIds});

  final List<int> initialDocumentIds;

  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends State<MergeScreen> {
  late List<int> _ids = List.of(widget.initialDocumentIds);
  bool _running = false;

  Future<void> _addDocuments() async {
    final pdfs = (await AppDatabase.instance.getAllDocuments())
        .where((d) => d.isPdf)
        .toList();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Set<int>>(
      context: context,
      builder: (sheetContext) {
        final selected = Set<int>.of(_ids);
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Add PDFs', style: AppText.body),
                const SizedBox(height: 8),
                Expanded(
                  child: pdfs.isEmpty
                      ? const Center(
                          child: Text(
                            'No PDFs in the library yet.',
                            style: AppText.bodySecondary,
                          ),
                        )
                      : ListView.builder(
                          itemCount: pdfs.length,
                          itemBuilder: (context, i) {
                            final d = pdfs[i];
                            final checked = selected.contains(d.id);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: (v) => setSheetState(() {
                                if (v == true) {
                                  selected.add(d.id!);
                                } else {
                                  selected.remove(d.id);
                                }
                              }),
                              title: Text(
                                d.displayName,
                                style: AppText.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${d.pageCount} pages',
                                style: AppText.monoSize(12),
                              ),
                              activeColor: AppColors.accent,
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: RunButton(
                    label: 'Add selected',
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(selected),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) setState(() => _ids = picked.toList());
  }

  Future<void> _run() async {
    if (_running || _ids.length < 2) return;
    setState(() => _running = true);
    try {
      final docs = await AppDatabase.instance.getAllDocuments();
      final byId = <int, LibraryDocument>{
        for (final d in docs)
          if (d.id != null) d.id!: d,
      };
      final inputs = <Map<String, Object?>>[];
      var skippedProtected = false;
      for (final id in _ids) {
        final doc = byId[id];
        if (doc == null) continue;
        late final String path;
        try {
          path = await DocSource.resolvePath(doc);
          await PdfFacade.pageCount(path);
        } on PdfPasswordException {
          skippedProtected = true;
          continue;
        } catch (_) {
          skippedProtected = true;
          continue;
        }
        inputs.add({'path': path});
      }
      if (skippedProtected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password-protected files need to be opened in the reader first.',
            ),
          ),
        );
      }
      if (inputs.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pick at least two readable PDFs to merge.'),
            ),
          );
        }
        return;
      }
      final dir = await toolOutputDir();
      final outPath =
          '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
      if (!mounted) return;
      final outputs = await runToolWithProgress(
        context,
        {
          'kind': 'merge',
          'inputs': inputs,
          'outPath': outPath,
          'dpi': 150,
          'quality': 85,
        },
        title: 'Merging…',
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
      title: 'Merge',
      children: [
        const SectionLabel('Documents'),
        const SizedBox(height: 8),
        FutureBuilder<List<LibraryDocument>>(
          future: AppDatabase.instance.getAllDocuments(),
          builder: (context, snapshot) {
            final byId = <int, LibraryDocument>{
              for (final d in snapshot.data ?? const <LibraryDocument>[])
                if (d.id != null) d.id!: d,
            };
            final docs = [
              for (final id in _ids)
                if (byId[id] != null) byId[id]!,
            ];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No PDFs chosen yet.',
                  style: AppText.bodySecondary,
                ),
              );
            }
            return ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final id = _ids.removeAt(oldIndex);
                  _ids.insert(newIndex, id);
                });
              },
              itemBuilder: (context, i) {
                final d = docs[i];
                return Container(
                  key: ValueKey(d.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.drag_handle,
                        size: 22,
                        color: AppColors.tertiary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.displayName,
                              style: AppText.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${d.pageCount} pages',
                              style: AppText.monoSize(12),
                            ),
                          ],
                        ),
                      ),
                      LrIconButton(
                        icon: Icons.close,
                        semanticLabel: 'Remove ${d.displayName}',
                        onPressed: () =>
                            setState(() => _ids.remove(d.id)),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: 'Add PDFs',
          child: PressScale(
            onTap: _addDocuments,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border.fromBorderSide(BorderSide(color: AppColors.accent)),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: const Text(
                'Add PDFs',
                style: TextStyle(
                  fontFamily: AppText.zenKaku,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const RasterNote(),
        const SizedBox(height: 16),
        RunButton(
          label: _running ? 'Working…' : 'Merge',
          onPressed: _ids.length >= 2 && !_running ? _run : null,
        ),
      ],
    );
  }
}
