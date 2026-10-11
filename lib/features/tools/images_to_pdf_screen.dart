import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/lr_icon_button.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/section_label.dart';
import 'widgets/tool_result_sheet.dart';
import 'widgets/tool_run.dart';
import 'widgets/tool_scaffold.dart';

/// Builds a PDF from picked images: add, order, page size, create.
class ImagesToPdfScreen extends StatefulWidget {
  const ImagesToPdfScreen({super.key, this.initialImages = const []});

  final List<String> initialImages;

  @override
  State<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends State<ImagesToPdfScreen> {
  late List<String> _images = List.of(widget.initialImages);
  String _pageSize = 'fit';
  bool _running = false;

  Future<void> _addImages() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final paths = files
        .map((f) => f.path)
        .whereType<String>()
        .where((path) => !_images.contains(path))
        .toList();
    if (paths.isEmpty || !mounted) return;
    setState(() => _images.addAll(paths));
  }

  Future<void> _run() async {
    if (_running || _images.isEmpty) return;
    setState(() => _running = true);
    try {
      final dir = await toolOutputDir();
      final outPath =
          '${dir.path}/images_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputs = await runToolWithProgress(
        context,
        {
          'kind': 'images',
          'images': _images,
          'outPath': outPath,
          'pageSize': _pageSize,
          'quality': 85,
        },
        title: 'Creating PDF…',
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
      title: 'Images to PDF',
      children: [
        const SectionLabel('Images'),
        const SizedBox(height: 8),
        if (_images.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No images yet. Add some to begin.',
              style: AppText.bodySecondary,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _images.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final path = _images.removeAt(oldIndex);
                _images.insert(newIndex, path);
              });
            },
            itemBuilder: (context, i) {
              final path = _images[i];
              return Container(
                key: ValueKey(path),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
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
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(4)),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: AppColors.background,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.basename(path),
                        style: AppText.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    LrIconButton(
                      icon: Icons.close,
                      semanticLabel: 'Remove image',
                      onPressed: () =>
                          setState(() => _images.removeAt(i)),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: 'Add images',
          child: PressScale(
            onTap: _addImages,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border.fromBorderSide(BorderSide(color: AppColors.accent)),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: const Text(
                'Add images',
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
        const SectionLabel('Page size'),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'fit', label: Text('Fit image')),
            ButtonSegment(value: 'a4', label: Text('A4')),
          ],
          selected: {_pageSize},
          onSelectionChanged: (s) => setState(() => _pageSize = s.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.accentTint,
            selectedForegroundColor: AppColors.accent,
          ),
        ),
        const SizedBox(height: 16),
        RunButton(
          label: _running ? 'Working…' : 'Create PDF',
          onPressed: _images.isNotEmpty && !_running ? _run : null,
        ),
      ],
    );
  }
}
