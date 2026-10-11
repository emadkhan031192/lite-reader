import 'package:flutter/material.dart';

import '../../core/models/annotation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// Paints [PdfAnnotation]s whose coordinates are normalized (0..1).
///
/// The canvas size must equal the rendered page size; normalized coordinates
/// are multiplied by [size] to obtain pixel geometry. Signature annotations
/// are NOT painted here — the overlay draws them as positioned image widgets.
class AnnotationPainter extends CustomPainter {
  AnnotationPainter({required this.annotations, this.selectedId});

  final List<PdfAnnotation> annotations;
  final int? selectedId;

  /// Pixel-space bounds of [annotation] on a canvas of [size], or null when
  /// the annotation carries no geometry. Used for hit-testing, selection
  /// outlines and handles.
  static Rect? boundsOf(PdfAnnotation annotation, Size size) {
    final rect = annotation.rect;
    if (rect != null && rect.length == 4) {
      return Rect.fromLTWH(
        rect[0] * size.width,
        rect[1] * size.height,
        rect[2] * size.width,
        rect[3] * size.height,
      );
    }
    final points = annotation.points;
    if (points != null && points.isNotEmpty) {
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = double.negativeInfinity;
      var maxY = double.negativeInfinity;
      for (final p in points) {
        if (p.length < 2) continue;
        final x = p[0] * size.width;
        final y = p[1] * size.height;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
      if (minX.isFinite) {
        return Rect.fromLTRB(minX, minY, maxX, maxY);
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      _paintAnnotation(canvas, size, annotation);
    }
    final selected = selectedId;
    if (selected != null) {
      for (final annotation in annotations) {
        if (annotation.id == selected) {
          final bounds = boundsOf(annotation, size);
          if (bounds != null) {
            canvas.drawRect(
              bounds,
              Paint()
                ..color = AppColors.accent
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          }
          break;
        }
      }
    }
  }

  void _paintAnnotation(Canvas canvas, Size size, PdfAnnotation annotation) {
    switch (annotation.type) {
      case AnnotationType.highlight:
        final bounds = boundsOf(annotation, size);
        if (bounds != null) {
          canvas.drawRect(
            bounds,
            Paint()
              ..color = Color(annotation.color)
                  .withValues(alpha: annotation.opacity.clamp(0.0, 1.0)),
          );
        }
      case AnnotationType.underline:
      case AnnotationType.strikethrough:
        final bounds = boundsOf(annotation, size);
        if (bounds != null) {
          final thickness = (bounds.height * 0.14).clamp(2.0, 8.0);
          final y = annotation.type == AnnotationType.underline
              ? bounds.bottom - thickness / 2
              : bounds.top + bounds.height / 2;
          canvas.drawLine(
            Offset(bounds.left, y),
            Offset(bounds.right, y),
            Paint()
              ..color = Color(annotation.color)
              ..style = PaintingStyle.stroke
              ..strokeWidth = thickness
              ..strokeCap = StrokeCap.round,
          );
        }
      case AnnotationType.pen:
        final points = annotation.points;
        if (points != null && points.length > 1) {
          final path = Path();
          var started = false;
          for (final p in points) {
            if (p.length < 2) continue;
            final offset =
                Offset(p[0] * size.width, p[1] * size.height);
            if (!started) {
              path.moveTo(offset.dx, offset.dy);
              started = true;
            } else {
              path.lineTo(offset.dx, offset.dy);
            }
          }
          if (started) {
            canvas.drawPath(
              path,
              Paint()
                ..color = Color(annotation.color)
                ..style = PaintingStyle.stroke
                ..strokeWidth = annotation.strokeWidth.clamp(1.5, 64.0)
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round,
            );
          }
        }
      case AnnotationType.text:
        final bounds = boundsOf(annotation, size);
        if (bounds != null) {
          final painter = TextPainter(
            text: TextSpan(
              text: annotation.text ?? '',
              style: const TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
                height: 1.3,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 64,
          )..layout(maxWidth: bounds.width);
          painter.paint(canvas, bounds.topLeft);
        }
      case AnnotationType.signature:
        // Drawn as a positioned image widget by the overlay, not here.
        break;
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) {
    return !identical(oldDelegate.annotations, annotations) ||
        oldDelegate.annotations.length != annotations.length ||
        oldDelegate.selectedId != selectedId;
  }
}
