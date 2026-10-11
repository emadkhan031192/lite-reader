import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;

import '../../../core/models/annotation.dart';
import '../../../core/theme/app_colors.dart';
import '../annotation_painter.dart';

enum _GestureMode { move, resize }

class _ActiveMove {
  _ActiveMove({
    required this.before,
    required this.mode,
    required this.startLocal,
    required this.startRectPx,
    required this.pageSize,
    required this.current,
  });

  final PdfAnnotation before;
  final _GestureMode mode;
  final Offset startLocal;
  final Rect startRectPx;
  final Size pageSize;
  PdfAnnotation current;
}

/// Interactive annotation layer for one PDF page.
///
/// The overlay fills its parent (the screen sizes it to the page rect), so
/// [localPos]/[localPoints] are in page-pixel coordinates of the overlay box.
/// The screen converts them to normalized coordinates.
class AnnotationOverlay extends StatefulWidget {
  const AnnotationOverlay({
    super.key,
    required this.page,
    required this.annotations,
    required this.selectedId,
    required this.activeTool,
    required this.onSelect,
    required this.onUpdate,
    required this.onCanvasTap,
    required this.onDrawEnd,
    required this.onRectEnd,
    this.onBackgroundTap,
    this.onGestureEnd,
    this.previewColor,
    this.previewWidthPx,
  });

  final PdfPage page;
  final List<PdfAnnotation> annotations;
  final int? selectedId;
  final AnnotationType? activeTool;
  final void Function(PdfAnnotation annotation) onSelect;
  final void Function(PdfAnnotation annotation) onUpdate;
  final Future<void> Function(Offset localPos, AnnotationType tool) onCanvasTap;
  final void Function(List<Offset> localPoints, AnnotationType tool) onDrawEnd;
  final void Function(Rect localRect, AnnotationType tool) onRectEnd;

  /// Called when the user taps empty space with no tool active.
  final VoidCallback? onBackgroundTap;

  /// Called when a move/resize gesture finishes, with the annotation as it
  /// was when the gesture started and as it ended (for undo).
  final void Function(PdfAnnotation before, PdfAnnotation after)? onGestureEnd;

  /// Style used for the in-progress stroke/rect preview.
  final Color? previewColor;
  final double? previewWidthPx;

  @override
  State<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends State<AnnotationOverlay> {
  List<Offset>? _stroke;
  _ActiveMove? _move;

  static bool _isDrawTool(AnnotationType tool) =>
      tool == AnnotationType.highlight ||
      tool == AnnotationType.underline ||
      tool == AnnotationType.strikethrough ||
      tool == AnnotationType.pen;

  PdfAnnotation? _findSelected() {
    final id = widget.selectedId;
    if (id == null) return null;
    for (final a in widget.annotations) {
      if (a.id == id) return a;
    }
    return null;
  }

  PdfAnnotation? _hitTest(Offset local, Size size) {
    for (var i = widget.annotations.length - 1; i >= 0; i--) {
      final annotation = widget.annotations[i];
      final bounds = AnnotationPainter.boundsOf(annotation, size);
      if (bounds == null) continue;
      if (annotation.type == AnnotationType.pen) {
        if (bounds.inflate(12).contains(local)) return annotation;
      } else {
        if (bounds.contains(local)) return annotation;
      }
    }
    return null;
  }

  void _onTapUp(Offset local, Size size) {
    final hit = _hitTest(local, size);
    if (hit != null) {
      widget.onSelect(hit);
      return;
    }
    final tool = widget.activeTool;
    if (tool != null) {
      widget.onCanvasTap(local, tool);
    } else {
      widget.onBackgroundTap?.call();
    }
  }

  void _onPanStart(Offset local, Size size) {
    final tool = widget.activeTool;
    if (tool != null) {
      if (_isDrawTool(tool)) {
        setState(() => _stroke = [local]);
      }
      return;
    }
    final selected = _findSelected();
    if (selected == null) return;
    final bounds = AnnotationPainter.boundsOf(selected, size);
    if (bounds == null) return;
    final handle = Rect.fromLTWH(
      bounds.right - 12,
      bounds.bottom - 12,
      24,
      24,
    );
    if (handle.contains(local)) {
      _move = _ActiveMove(
        before: selected,
        mode: _GestureMode.resize,
        startLocal: local,
        startRectPx: bounds,
        pageSize: size,
        current: selected,
      );
    } else if (bounds.contains(local)) {
      _move = _ActiveMove(
        before: selected,
        mode: _GestureMode.move,
        startLocal: local,
        startRectPx: bounds,
        pageSize: size,
        current: selected,
      );
    }
  }

  void _onPanUpdate(Offset local) {
    final stroke = _stroke;
    if (stroke != null) {
      setState(() => _stroke = [...stroke, local]);
      return;
    }
    final move = _move;
    if (move != null) {
      final updated = _applyMove(move, local);
      move.current = updated;
      widget.onUpdate(updated);
    }
  }

  void _onPanEnd() {
    final stroke = _stroke;
    _stroke = null;
    if (stroke != null) {
      final tool = widget.activeTool;
      if (tool != null && stroke.length >= 2) {
        if (tool == AnnotationType.pen) {
          widget.onDrawEnd(List<Offset>.of(stroke), tool);
        } else {
          widget.onRectEnd(_boundingRect(stroke), tool);
        }
      }
      setState(() {});
      return;
    }
    final move = _move;
    _move = null;
    if (move != null) {
      if (!_sameGeometry(move.before, move.current)) {
        widget.onGestureEnd?.call(move.before, move.current);
      }
      setState(() {});
    }
  }

  static bool _sameGeometry(PdfAnnotation a, PdfAnnotation b) {
    return _doublesEqual(a.rect, b.rect) && _pointsEqual(a.points, b.points);
  }

  static bool _doublesEqual(List<double>? a, List<double>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _pointsEqual(List<List<double>>? a, List<List<double>>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_doublesEqual(a[i], b[i])) return false;
    }
    return true;
  }

  static Rect _boundingRect(List<Offset> points) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  PdfAnnotation _applyMove(_ActiveMove move, Offset local) {
    final dx = local.dx - move.startLocal.dx;
    final dy = local.dy - move.startLocal.dy;
    final size = move.pageSize;
    final start = move.startRectPx;
    late final Rect next;
    if (move.mode == _GestureMode.move) {
      final maxLeft = max(0.0, size.width - start.width);
      final maxTop = max(0.0, size.height - start.height);
      final left = (start.left + dx).clamp(0.0, maxLeft);
      final top = (start.top + dy).clamp(0.0, maxTop);
      next = Rect.fromLTWH(left, top, start.width, start.height);
    } else {
      final maxWidth = max(24.0, size.width - start.left);
      final maxHeight = max(24.0, size.height - start.top);
      final width = (start.width + dx).clamp(24.0, maxWidth);
      final height = (start.height + dy).clamp(24.0, maxHeight);
      next = Rect.fromLTWH(start.left, start.top, width, height);
    }
    final before = move.before;
    if (before.type == AnnotationType.pen) {
      final points = before.points ?? const <List<double>>[];
      final updated = <List<double>>[];
      for (final p in points) {
        if (p.length < 2) continue;
        if (move.mode == _GestureMode.move) {
          updated.add([p[0] + dx / size.width, p[1] + dy / size.height]);
        } else {
          final sx = start.width <= 0 ? 1.0 : next.width / start.width;
          final sy = start.height <= 0 ? 1.0 : next.height / start.height;
          final px = p[0] * size.width;
          final py = p[1] * size.height;
          updated.add([
            (start.left + (px - start.left) * sx) / size.width,
            (start.top + (py - start.top) * sy) / size.height,
          ]);
        }
      }
      return before.copyWith(points: updated);
    }
    return before.copyWith(rect: [
      next.left / size.width,
      next.top / size.height,
      next.width / size.width,
      next.height / size.height,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final selected = _findSelected();
        final selectedBounds = selected == null
            ? null
            : AnnotationPainter.boundsOf(selected, size);
        final stroke = _stroke;
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            children: [
              CustomPaint(
                size: size,
                painter: AnnotationPainter(
                  annotations: widget.annotations,
                  selectedId: widget.selectedId,
                ),
              ),
              for (final annotation in widget.annotations)
                if (annotation.type == AnnotationType.signature &&
                    annotation.imagePath != null &&
                    annotation.rect != null &&
                    annotation.rect!.length == 4)
                  Positioned.fromRect(
                    rect: Rect.fromLTWH(
                      annotation.rect![0] * size.width,
                      annotation.rect![1] * size.height,
                      annotation.rect![2] * size.width,
                      annotation.rect![3] * size.height,
                    ),
                    child: Image.file(
                      File(annotation.imagePath!),
                      fit: BoxFit.fill,
                    ),
                  ),
              if (selectedBounds != null)
                Positioned(
                  left: selectedBounds.right - 12,
                  top: selectedBounds.bottom - 12,
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: ColoredBox(color: AppColors.accent),
                  ),
                ),
              if (stroke != null && stroke.length > 1)
                CustomPaint(
                  size: size,
                  painter: _StrokePreviewPainter(
                    points: stroke,
                    isRect: widget.activeTool != null &&
                        widget.activeTool != AnnotationType.pen,
                    color: widget.previewColor ??
                        AppColors.highlightColors.first,
                    width: widget.previewWidthPx ?? 14,
                  ),
                ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) =>
                      _onTapUp(details.localPosition, size),
                  onPanStart: (details) =>
                      _onPanStart(details.localPosition, size),
                  onPanUpdate: (details) =>
                      _onPanUpdate(details.localPosition),
                  onPanEnd: (_) => _onPanEnd(),
                  onPanCancel: _onPanEnd,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Preview of the stroke/rect currently being drawn.
class _StrokePreviewPainter extends CustomPainter {
  _StrokePreviewPainter({
    required this.points,
    required this.isRect,
    required this.color,
    required this.width,
  });

  final List<Offset> points;
  final bool isRect;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = isRect ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (isRect) {
      canvas.drawRect(_AnnotationOverlayState._boundingRect(points), paint);
    } else {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePreviewPainter oldDelegate) =>
      !identical(oldDelegate.points, points);
}
