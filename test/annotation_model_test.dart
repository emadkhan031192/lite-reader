import 'package:flutter_test/flutter_test.dart';
import 'package:litereader/core/models/annotation.dart';

void main() {
  test('toMap/fromMap round-trip keeps rect, points and note', () {
    const annotation = PdfAnnotation(
      id: 7,
      documentId: 3,
      page: 2,
      type: AnnotationType.pen,
      color: 0xFFFFD60A,
      opacity: 0.8,
      strokeWidth: 10,
      rect: [0.1, 0.2, 0.3, 0.4],
      points: [
        [0.1, 0.2],
        [0.3, 0.4],
      ],
      note: 'remember this',
    );
    final restored = PdfAnnotation.fromMap(annotation.toMap());
    expect(restored.id, 7);
    expect(restored.documentId, 3);
    expect(restored.page, 2);
    expect(restored.type, AnnotationType.pen);
    expect(restored.color, 0xFFFFD60A);
    expect(restored.opacity, 0.8);
    expect(restored.strokeWidth, 10);
    expect(restored.rect, [0.1, 0.2, 0.3, 0.4]);
    expect(
      restored.points,
      [
        [0.1, 0.2],
        [0.3, 0.4],
      ],
    );
    expect(restored.note, 'remember this');
  });

  test('defaults: opacity 0.55, empty optionals', () {
    const annotation = PdfAnnotation(
      documentId: 1,
      page: 1,
      type: AnnotationType.highlight,
      color: 0xFFFFD60A,
    );
    expect(annotation.opacity, 0.55);
    expect(annotation.strokeWidth, 14);
    expect(annotation.rect, isNull);
    expect(annotation.points, isNull);
    expect(annotation.text, isNull);
    expect(annotation.imagePath, isNull);
    expect(annotation.note, isNull);
  });

  test('fromMap fills defaults when keys are missing', () {
    final restored = PdfAnnotation.fromMap({
      'document_id': 1,
      'page': 1,
      'type': 'highlight',
      'color': 0xFFFFD60A,
    });
    expect(restored.opacity, 0.55);
    expect(restored.strokeWidth, 14);
    expect(restored.rect, isNull);
    expect(restored.points, isNull);
  });

  test('unknown type falls back to highlight', () {
    final restored = PdfAnnotation.fromMap({
      'document_id': 1,
      'page': 1,
      'type': 'nope',
      'color': 0xFFFFD60A,
    });
    expect(restored.type, AnnotationType.highlight);
  });
}
