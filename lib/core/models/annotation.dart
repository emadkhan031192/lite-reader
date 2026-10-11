import 'dart:convert';

/// Annotation tools available in the dock.
enum AnnotationType {
  highlight,
  underline,
  strikethrough,
  pen,
  text,
  signature,
}

/// An annotation stored in SQLite, per file and per page, using normalized
/// coordinates (0..1 relative to the page width/height) so it survives
/// re-renders at any DPI.
class PdfAnnotation {
  const PdfAnnotation({
    this.id,
    required this.documentId,
    required this.page,
    required this.type,
    required this.color,
    this.opacity = 0.55,
    this.strokeWidth = 14,
    this.rect,
    this.points,
    this.text,
    this.imagePath,
    this.note,
  });

  final int? id;
  final int documentId;
  /// 1-based page number.
  final int page;
  final AnnotationType type;
  /// ARGB color value.
  final int color;
  final double opacity;
  /// Stroke width in px at 1x scale.
  final double strokeWidth;
  /// Normalized rect [x, y, w, h] for highlight/underline/strikethrough/
  /// text/signature.
  final List<double>? rect;
  /// Normalized points [[x, y], ...] for pen strokes.
  final List<List<double>>? points;
  /// Text annotation content.
  final String? text;
  /// Signature image file path (app-private).
  final String? imagePath;
  /// Optional note attached to the annotation.
  final String? note;

  PdfAnnotation copyWith({
    int? id,
    int? documentId,
    int? page,
    AnnotationType? type,
    int? color,
    double? opacity,
    double? strokeWidth,
    List<double>? rect,
    List<List<double>>? points,
    String? text,
    String? imagePath,
    String? note,
  }) {
    return PdfAnnotation(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      page: page ?? this.page,
      type: type ?? this.type,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      rect: rect ?? this.rect,
      points: points ?? this.points,
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'document_id': documentId,
        'page': page,
        'type': type.name,
        'color': color,
        'opacity': opacity,
        'stroke_width': strokeWidth,
        'rect_json': rect == null ? null : jsonEncode(rect),
        'points_json': points == null ? null : jsonEncode(points),
        'text': text,
        'image_path': imagePath,
        'note': note,
      };

  factory PdfAnnotation.fromMap(Map<String, Object?> map) {
    List<double>? rect;
    final rectJson = map['rect_json'] as String?;
    if (rectJson != null) {
      rect = (jsonDecode(rectJson) as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }
    List<List<double>>? points;
    final pointsJson = map['points_json'] as String?;
    if (pointsJson != null) {
      points = (jsonDecode(pointsJson) as List)
          .map((p) =>
              (p as List).map((e) => (e as num).toDouble()).toList())
          .toList();
    }
    return PdfAnnotation(
      id: map['id'] as int?,
      documentId: (map['document_id'] as num).toInt(),
      page: (map['page'] as num).toInt(),
      type: AnnotationType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => AnnotationType.highlight,
      ),
      color: (map['color'] as num).toInt(),
      opacity: (map['opacity'] as num?)?.toDouble() ?? 0.55,
      strokeWidth: (map['stroke_width'] as num?)?.toDouble() ?? 14,
      rect: rect,
      points: points,
      text: map['text'] as String?,
      imagePath: map['image_path'] as String?,
      note: map['note'] as String?,
    );
  }
}
