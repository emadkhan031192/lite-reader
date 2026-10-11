import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;
import 'package:share_plus/share_plus.dart';

import '../../core/db/app_database.dart';
import '../../core/models/annotation.dart';
import '../../core/models/document.dart';
import '../../core/pdf/pdf_facade.dart';
import '../../core/pdf/tool_runner.dart';
import '../../core/platform/saf.dart';
import '../../core/services/doc_source.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/lr_icon_button.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/section_label.dart';
import 'annotation_painter.dart';
import 'providers.dart';
import 'widgets/annotation_overlay.dart';
import 'widgets/annotation_popover.dart';
import 'widgets/signature_pad.dart';
import 'widgets/tool_dock.dart';

/// Annotate & sign screen: a fixed fit-width page with an interactive
/// annotation overlay, a six-tool dock and export of an annotated copy.
///
/// Route: `/annotate?documentId=&page=`.
class AnnotateScreen extends ConsumerStatefulWidget {
  const AnnotateScreen({
    super.key,
    required this.documentId,
    required this.initialPage,
  });

  final int documentId;
  final int initialPage;

  @override
  ConsumerState<AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends ConsumerState<AnnotateScreen> {
  late final PdfViewerController _viewerController;
  LibraryDocument? _doc;
  String? _pdfPath;
  int _pageCount = 0;
  int _currentPage = 1;
  String? _password;
  bool _loading = true;
  String? _error;
  bool _passwordAsked = false;

  @override
  void initState() {
    super.initState();
    _viewerController = PdfViewerController();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc =
          await AppDatabase.instance.getDocumentById(widget.documentId);
      if (!mounted) return;
      if (doc == null) {
        setState(() {
          _loading = false;
          _error = 'Document not found.';
        });
        return;
      }
      final path = await DocSource.resolvePath(doc);
      final count = await PdfFacade.pageCount(path, password: _password);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _pdfPath = path;
        _pageCount = count;
        _currentPage = widget.initialPage.clamp(1, count);
        _loading = false;
        _error = null;
      });
    } on PdfPasswordException {
      if (!mounted) return;
      if (!_passwordAsked) {
        _passwordAsked = true;
        final password = await _askPassword();
        if (!mounted) return;
        if (password != null && password.isNotEmpty) {
          _password = password;
          _passwordAsked = false;
          _load();
          return;
        }
      }
      setState(() {
        _loading = false;
        _error = 'This file needs a password.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open the file.';
      });
    }
  }

  Future<String?> _askPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          'Password required',
          style: TextStyle(
            fontFamily: AppText.zenKaku,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        content: Semantics(
          label: 'Password',
          textField: true,
          child: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Password'),
            onSubmitted: (_) =>
                Navigator.of(context).pop(controller.text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              semanticsLabel: 'Cancel',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            child: const Text(
              'Unlock',
              semanticsLabel: 'Unlock',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Page navigation
  // -------------------------------------------------------------------------

  void _goToPage(int page) {
    final next = page.clamp(1, _pageCount);
    if (next == _currentPage) return;
    setState(() => _currentPage = next);
    ref.read(selectedAnnotationProvider.notifier).select(null);
    unawaited(_viewerController.goToPage(pageNumber: next));
  }

  // -------------------------------------------------------------------------
  // Annotation creation
  // -------------------------------------------------------------------------

  Future<void> _addAnnotation(PdfAnnotation annotation) async {
    final created = await ref
        .read(annotateControllerProvider(widget.documentId).notifier)
        .pushAdd(annotation);
    if (!mounted) return;
    ref.read(selectedAnnotationProvider.notifier).select(created.id);
  }

  Future<void> _handleCanvasTap(
    Offset pos,
    AnnotationType tool,
    int pageNumber,
    Size size,
  ) async {
    final nx = (pos.dx / size.width).clamp(0.0, 1.0);
    final ny = (pos.dy / size.height).clamp(0.0, 1.0);
    if (tool == AnnotationType.text) {
      final text = await _askText();
      if (!mounted || text == null || text.trim().isEmpty) return;
      const w = 0.5;
      const h = 0.07;
      await _addAnnotation(PdfAnnotation(
        documentId: widget.documentId,
        page: pageNumber,
        type: AnnotationType.text,
        color: AppColors.ink.toARGB32(),
        opacity: 1.0,
        strokeWidth: 14,
        rect: [
          (nx - w / 2).clamp(0.0, 1.0 - w),
          ny.clamp(0.0, 1.0 - h),
          w,
          h,
        ],
        text: text.trim(),
      ));
    } else if (tool == AnnotationType.signature) {
      await _placeSignature(nx, ny, pageNumber);
    }
    // Highlight, underline, strikethrough and pen need a drag; ignore taps.
  }

  Future<void> _handleRectEnd(
    Rect rect,
    AnnotationType tool,
    int pageNumber,
    Size size,
  ) async {
    final style = ref.read(annotateStyleProvider);
    final nx = (rect.left / size.width).clamp(0.0, 1.0);
    var ny = (rect.top / size.height).clamp(0.0, 1.0);
    var nw = rect.width / size.width;
    var nh = rect.height / size.height;
    if (tool == AnnotationType.underline ||
        tool == AnnotationType.strikethrough) {
      if (nw * size.width < 12) return;
      final minH = 10 / size.height;
      if (nh < minH) {
        final center = ny + nh / 2;
        ny = (center - minH / 2).clamp(0.0, max(0.0, 1.0 - minH));
        nh = minH;
      }
    } else {
      // Highlight: ignore accidental taps.
      if (nw * size.width < 8 || nh * size.height < 8) return;
    }
    if (nx + nw > 1) nw = 1 - nx;
    if (ny + nh > 1) nh = 1 - ny;
    await _addAnnotation(PdfAnnotation(
      documentId: widget.documentId,
      page: pageNumber,
      type: tool,
      color: style.color.toARGB32(),
      opacity: style.opacity,
      strokeWidth: style.widthPx,
      rect: [nx, ny, nw, nh],
    ));
  }

  Future<void> _handleDrawEnd(
    List<Offset> points,
    AnnotationType tool,
    int pageNumber,
    Size size,
  ) async {
    if (points.length < 2) return;
    final style = ref.read(annotateStyleProvider);
    await _addAnnotation(PdfAnnotation(
      documentId: widget.documentId,
      page: pageNumber,
      type: tool,
      color: style.color.toARGB32(),
      opacity: 1.0,
      strokeWidth: style.widthPx,
      points: [
        for (final o in points)
          [
            (o.dx / size.width).clamp(0.0, 1.0),
            (o.dy / size.height).clamp(0.0, 1.0),
          ],
      ],
    ));
  }

  Future<void> _placeSignature(double nx, double ny, int pageNumber) async {
    final result = await showSignaturePad(context);
    if (!mounted || result == null) return;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'LiteReader', 'signatures'));
    await dir.create(recursive: true);
    final path = p.join(
      dir.path,
      'sig_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await File(path).writeAsBytes(result.bytes, flush: true);
    if (!mounted) return;
    await AppDatabase.instance.saveSignature(
      result.name.isEmpty ? 'Signature' : result.name,
      path,
    );
    final style = ref.read(annotateStyleProvider);
    const w = 0.42;
    const h = 0.14;
    final x = (nx - w / 2).clamp(0.0, 1.0 - w);
    final y = ny.clamp(0.0, 1.0 - h);
    await _addAnnotation(PdfAnnotation(
      documentId: widget.documentId,
      page: pageNumber,
      type: AnnotationType.signature,
      color: style.color.toARGB32(),
      opacity: 1.0,
      strokeWidth: style.widthPx,
      rect: [x, y, w, h],
      imagePath: path,
    ));
    if (result.includeDate) {
      await _addAnnotation(PdfAnnotation(
        documentId: widget.documentId,
        page: pageNumber,
        type: AnnotationType.text,
        color: AppColors.ink.toARGB32(),
        opacity: 1.0,
        strokeWidth: 14,
        rect: [x, (y + h + 0.01).clamp(0.0, 1.0 - 0.05), w, 0.05],
        text: 'Signed ${formatSignedDate(DateTime.now())}',
      ));
    }
  }

  // -------------------------------------------------------------------------
  // Selection actions
  // -------------------------------------------------------------------------

  Future<void> _deleteAnnotation(PdfAnnotation annotation) async {
    await ref
        .read(annotateControllerProvider(widget.documentId).notifier)
        .pushRemove(annotation);
    if (!mounted) return;
    ref.read(selectedAnnotationProvider.notifier).select(null);
  }

  Future<void> _recolorAnnotation(PdfAnnotation annotation, int color) {
    return ref
        .read(annotateControllerProvider(widget.documentId).notifier)
        .pushUpdate(annotation, annotation.copyWith(color: color));
  }

  Future<void> _editNote(PdfAnnotation annotation) async {
    final text = await _askText(
      title: 'Note',
      hint: 'Add a note',
      initial: annotation.note,
    );
    if (!mounted || text == null) return;
    final note = text.trim();
    final updated = PdfAnnotation(
      id: annotation.id,
      documentId: annotation.documentId,
      page: annotation.page,
      type: annotation.type,
      color: annotation.color,
      opacity: annotation.opacity,
      strokeWidth: annotation.strokeWidth,
      rect: annotation.rect,
      points: annotation.points,
      text: annotation.text,
      imagePath: annotation.imagePath,
      note: note.isEmpty ? null : note,
    );
    await ref
        .read(annotateControllerProvider(widget.documentId).notifier)
        .pushUpdate(annotation, updated);
  }

  Future<String?> _askText({
    String title = 'Text',
    String hint = 'Annotation text',
    String? initial,
  }) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: AppText.zenKaku,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        content: Semantics(
          label: 'Annotation text',
          textField: true,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              semanticsLabel: 'Cancel',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            child: const Text(
              'Save',
              semanticsLabel: 'Save',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Style sheet
  // -------------------------------------------------------------------------

  Future<void> _openStyleSheet() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Consumer(
            builder: (context, ref, _) {
              final style = ref.watch(annotateStyleProvider);
              final notifier = ref.read(annotateStyleProvider.notifier);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Annotation style'),
                  const SizedBox(height: 16),
                  _sliderRow(
                    label: 'Width',
                    valueText: '${style.widthPx.round()} px',
                    value: style.widthPx,
                    min: 4,
                    max: 40,
                    onChanged: notifier.setWidth,
                  ),
                  _sliderRow(
                    label: 'Opacity',
                    valueText: '${(style.opacity * 100).round()}%',
                    value: style.opacity,
                    min: 0.1,
                    max: 1.0,
                    onChanged: notifier.setOpacity,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: AppText.small),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: AppColors.accent,
              inactiveColor: AppColors.hairline,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: AppText.monoSize(13),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  Future<void> _exportFlow() async {
    if (_pdfPath == null || _doc == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Save a copy with annotations',
          style: TextStyle(
            fontFamily: AppText.zenKaku,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        content: const Text(
          'Exports a new PDF with your annotations drawn onto each page. '
          'Text becomes non-selectable in the copy. '
          'The original file is never changed.',
          style: AppText.small,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              semanticsLabel: 'Cancel',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            child: const Text(
              'Export',
              semanticsLabel: 'Export',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final docsDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docsDir.path, 'LiteReader'));
    await outDir.create(recursive: true);
    final base = p.basenameWithoutExtension(_doc!.displayName);
    final outPath = p.join(outDir.path, '${base}_annotated.pdf');
    final annotations =
        await AppDatabase.instance.getAllAnnotations(widget.documentId);
    if (!mounted) return;

    final progress = ValueNotifier<double>(0);
    String? donePath;
    String? errorMessage;
    final subscription = runPdfTool(<String, Object?>{
      'kind': 'export',
      'inPath': _pdfPath!,
      'outPath': outPath,
      'password': _password,
      'dpi': 150,
      'quality': 85,
      'annotations': annotations.map((a) => a.toMap()).toList(),
    }).listen((update) {
      if (update.isDone) {
        donePath = update.outputs!.first;
        progress.value = 1;
      } else if (update.isError) {
        errorMessage = update.error;
      } else {
        progress.value = update.progress ?? 0;
      }
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (dialogContext, value, _) {
          if (donePath != null || errorMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            });
          }
          return AlertDialog(
            title: const Text(
              'Exporting…',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: value,
                  color: AppColors.accent,
                  backgroundColor: AppColors.hairline,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatPercent(value),
                    style: AppText.monoSize(13),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    await subscription.cancel();
    progress.dispose();
    if (!mounted) return;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $errorMessage')),
      );
      return;
    }
    if (donePath != null) {
      await _showExportResult(donePath!);
    }
  }

  Future<void> _showExportResult(String path) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new, size: 22),
              title: const Text('Open', style: AppText.body),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _openExported(path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share, size: 22),
              title: const Text('Share', style: AppText.body),
              onTap: () {
                Navigator.of(sheetContext).pop();
                SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(path)],
                    text:
                        'Annotated copy of ${_doc?.displayName ?? 'document'}',
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, size: 22),
              title: const Text('Save to…', style: AppText.body),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _saveExportedToTree(path);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExported(String path) async {
    final file = File(path);
    final id = await AppDatabase.instance.upsertDocument(
      LibraryDocument(
        uri: path,
        source: 'app',
        displayName: p.basename(path),
        mimeType: 'application/pdf',
        size: file.lengthSync(),
        modified: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    context.push('/reader?documentId=$id&page=1');
  }

  Future<void> _saveExportedToTree(String path) async {
    final treeUri = await Saf.pickDocumentTree();
    if (!mounted || treeUri == null) return;
    final uri = await Saf.createInTree(
      treeUri: treeUri,
      displayName: p.basename(path),
      mimeType: 'application/pdf',
      sourcePath: path,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          uri == null ? 'Could not save the file.' : 'Saved.',
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Page overlays
  // -------------------------------------------------------------------------

  List<Widget> _buildOverlays(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
  ) {
    if (page.pageNumber != _currentPage) return const [];
    return [
      Consumer(
        builder: (context, ref, _) {
          final annotations = ref
                  .watch(
                    pageAnnotationsProvider(
                      (docId: widget.documentId, page: page.pageNumber),
                    ),
                  )
                  .value ??
              const <PdfAnnotation>[];
          final selectedId = ref.watch(selectedAnnotationProvider);
          final tool = ref.watch(annotateToolProvider);
          final style = ref.watch(annotateStyleProvider);
          PdfAnnotation? selected;
          for (final annotation in annotations) {
            if (annotation.id == selectedId) {
              selected = annotation;
              break;
            }
          }
          final selectedBounds = selected == null
              ? null
              : AnnotationPainter.boundsOf(selected, pageRect.size);
          return SizedBox(
            width: pageRect.width,
            height: pageRect.height,
            child: Stack(
              children: [
                AnnotationOverlay(
                  page: page,
                  annotations: annotations,
                  selectedId: selectedId,
                  activeTool: tool,
                  previewColor: style.color,
                  previewWidthPx: style.widthPx,
                  onSelect: (annotation) => ref
                      .read(selectedAnnotationProvider.notifier)
                      .select(annotation.id),
                  onBackgroundTap: () => ref
                      .read(selectedAnnotationProvider.notifier)
                      .select(null),
                  onUpdate: (annotation) => ref
                      .read(
                        pageAnnotationsProvider(
                          (docId: widget.documentId, page: page.pageNumber),
                        ).notifier,
                      )
                      .updateLocal(annotation),
                  onGestureEnd: (before, after) => ref
                      .read(
                        annotateControllerProvider(widget.documentId).notifier,
                      )
                      .pushUpdate(before, after),
                  onCanvasTap: (pos, t) =>
                      _handleCanvasTap(pos, t, page.pageNumber, pageRect.size),
                  onDrawEnd: (points, t) =>
                      _handleDrawEnd(points, t, page.pageNumber, pageRect.size),
                  onRectEnd: (rect, t) =>
                      _handleRectEnd(rect, t, page.pageNumber, pageRect.size),
                ),
                if (selected != null && selectedBounds != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    top: _popoverTop(selectedBounds, pageRect.height),
                    child: AnnotationPopover(
                      annotation: selected,
                      onDelete: () => _deleteAnnotation(selected!),
                      onColor: (color) =>
                          _recolorAnnotation(selected!, color),
                      onAddNote: () => _editNote(selected!),
                      onClose: () => ref
                          .read(selectedAnnotationProvider.notifier)
                          .select(null),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ];
  }

  double _popoverTop(Rect bounds, double pageHeight) {
    const estimatedHeight = 116.0;
    var top = bounds.top - estimatedHeight - 8;
    if (top < 8) top = bounds.bottom + 8;
    return top.clamp(8.0, max(8.0, pageHeight - estimatedHeight - 8));
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  Widget _buildTopBar() {
    ref.watch(annotateControllerProvider(widget.documentId));
    final notifier =
        ref.read(annotateControllerProvider(widget.documentId).notifier);
    final canUndo = notifier.canUndo;
    final canRedo = notifier.canRedo;
    return Container(
      color: AppColors.surface,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            LrIconButton(
              icon: Icons.undo,
              semanticLabel: 'Undo',
              color: canUndo ? null : AppColors.tertiary,
              onPressed: canUndo ? () => notifier.undo() : null,
            ),
            LrIconButton(
              icon: Icons.redo,
              semanticLabel: 'Redo',
              color: canRedo ? null : AppColors.tertiary,
              onPressed: canRedo ? () => notifier.redo() : null,
            ),
            const Expanded(
              child: Text(
                'Annotate',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title,
              ),
            ),
            LrIconButton(
              icon: Icons.ios_share,
              semanticLabel: 'Save a copy with annotations',
              onPressed: _exportFlow,
            ),
            Semantics(
              button: true,
              label: 'Done',
              child: TextButton(
                onPressed: () => context.pop(),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontFamily: AppText.zenKaku,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    return Stack(
      children: [
        if (_pdfPath != null)
          PdfViewer.file(
            _pdfPath!,
            passwordProvider: createSimplePasswordProvider(_password),
            firstAttemptByEmptyPassword: _password == null,
            controller: _viewerController,
            initialPageNumber: _currentPage,
            params: PdfViewerParams(
              backgroundColor: Colors.transparent,
              margin: 8,
              sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
                maxScale: 5.0,
                calculateInitialZoom:
                    (document, controller, fitZoom, coverZoom) => coverZoom,
              ),
              panEnabled: false,
              scaleEnabled: false,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              pageOverlaysBuilder: _buildOverlays,
            ),
          ),
        Positioned(
          left: 8,
          top: 0,
          bottom: 0,
          child: Center(child: _buildChevron(next: false)),
        ),
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(child: _buildChevron(next: true)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.fromBorderSide(BorderSide(color: AppColors.hairline, width: 1)),
              ),
              child: Text(
                formatPageIndicator(_currentPage, _pageCount),
                style: AppText.monoSize(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChevron({required bool next}) {
    final enabled = next ? _currentPage < _pageCount : _currentPage > 1;
    return Semantics(
      button: true,
      label: next ? 'Next page' : 'Previous page',
      child: PressScale(
        onTap:
            enabled ? () => _goToPage(_currentPage + (next ? 1 : -1)) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: AppColors.hairline, width: 1)),
            ),
            child: Icon(
              next ? Icons.chevron_right : Icons.chevron_left,
              size: 22,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadout() {
    final tool = ref.watch(annotateToolProvider);
    final style = ref.watch(annotateStyleProvider);
    return Semantics(
      button: true,
      label: 'Annotation style settings',
      child: GestureDetector(
        onTap: _openStyleSheet,
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.hairline, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  annotateStyleReadout(tool, style),
                  style: AppText.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.tune,
                size: 18,
                color: AppColors.tertiary,
                semanticLabel: 'Style settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.desk,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }
    if (_error != null || _doc == null || _pdfPath == null) {
      return Scaffold(
        backgroundColor: AppColors.desk,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error ?? 'Could not open the file.',
                    style: AppText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    child: const Text(
                      'Go back',
                      semanticsLabel: 'Go back',
                      style: TextStyle(
                        fontFamily: AppText.zenKaku,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.desk,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildViewer()),
          _buildReadout(),
          const SafeArea(
            top: false,
            child: ToolDock(),
          ),
        ],
      ),
    );
  }
}
