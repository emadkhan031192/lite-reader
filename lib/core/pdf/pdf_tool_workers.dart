import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' hide PdfDocument, PdfException;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// Background-isolate workers for every PDF tool.
///
/// The original file is never modified: each tool renders pages to images
/// with PDFium and composes a brand-new PDF with the `pdf` package. Text in
/// the output is therefore rasterized and non-selectable — the UI says so
/// plainly wherever a tool runs.
///
/// Message shape (all values isolate-transferable):
/// ```dart
/// {
///   'kind': 'export' | 'merge' | 'split' | 'reorder' | 'compress' | 'images',
///   'port': SendPort,
///   ...kind-specific params...
/// }
/// ```
/// Progress: `{'progress': 0.0..1.0}`. Completion: `{'done': [outPaths]}`.
/// Failure: `{'error': message}`.
Future<void> pdfToolWorker(Map<String, Object?> message) async {
  final port = message['port'] as SendPort;
  void progress(int done, int total) =>
      port.send({'progress': total == 0 ? 1.0 : done / total});

  try {
    final kind = message['kind'] as String;
    final List<String> outputs;
    switch (kind) {
      case 'export':
        outputs = [await _exportAnnotated(message, progress)];
      case 'merge':
        outputs = [await _merge(message, progress)];
      case 'split':
        outputs = await _split(message, progress);
      case 'reorder':
        outputs = [await _reorder(message, progress)];
      case 'compress':
        outputs = [await _compress(message, progress)];
      case 'images':
        outputs = [await _imagesToPdf(message, progress)];
      default:
        throw ArgumentError('Unknown tool kind: $kind');
    }
    port.send({'done': outputs});
  } catch (e) {
    port.send({'error': _friendlyError(e)});
  }
}

String _friendlyError(Object e) {
  if (e is PdfPasswordException) {
    return 'Wrong password or the file needs one.';
  }
  return e.toString().replaceFirst('Exception: ', '');
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Future<PdfDocument> _openDoc(String path, String? password) {
  return PdfDocument.openFile(
    path,
    passwordProvider: createSimplePasswordProvider(password),
    firstAttemptByEmptyPassword: password == null,
  );
}

/// Rendered page as a mutable [img.Image] plus its size in PDF points.
class _PageImage {
  _PageImage(this.image, this.widthPt, this.heightPt);

  final img.Image image;
  final double widthPt;
  final double heightPt;
}

Future<_PageImage> _renderPage(
  PdfDocument doc,
  int pageNumber, {
  required int dpi,
}) async {
  final page = doc.pages[pageNumber - 1];
  final widthPx = (page.width * dpi / 72).round().clamp(16, 8000);
  final rendered = await page.render(
    width: widthPx,
    backgroundColor: 0xFFFFFFFF,
  );
  if (rendered == null) {
    throw PdfException('Could not render page $pageNumber');
  }
  final image = img.Image.fromBytes(
    width: rendered.width,
    height: rendered.height,
    bytes: rendered.pixels.buffer,
    order: img.ChannelOrder.bgra,
  );
  return _PageImage(image, page.width, page.height);
}

/// Draws stored annotations onto a rendered page image.
/// Annotation coordinates are normalized (0..1 of the page).
void _drawAnnotations(
  img.Image canvas,
  List<Map<String, Object?>> annotations,
) {
  final w = canvas.width.toDouble();
  final h = canvas.height.toDouble();
  for (final a in annotations) {
    final type = a['type'] as String? ?? 'highlight';
    final argb = (a['color'] as num?)?.toInt() ?? 0xFFFFD60A;
    final opacity = (a['opacity'] as num?)?.toDouble() ?? 0.55;
    final strokePt = (a['stroke_width'] as num?)?.toDouble() ?? 14;
    final pageWidthPt = (a['_pageWidthPt'] as num?)?.toDouble() ?? w;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final fill = img.ColorRgba8(r, g, b, (opacity * 255).round().clamp(0, 255));
    final solid = img.ColorRgba8(r, g, b, 255);

    // rect_json holds normalized [x, y, w, h].
    final rectRaw = a['rect_json'] as String?;
    List<double>? rect;
    if (rectRaw != null) {
      rect = (jsonDecode(rectRaw) as List)
          .map((e) => (e as num).toDouble())
          .toList();
    }
    var x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    if (rect != null && rect.length == 4) {
      x1 = (rect[0] * w).round();
      y1 = (rect[1] * h).round();
      x2 = ((rect[0] + rect[2]) * w).round();
      y2 = ((rect[1] + rect[3]) * h).round();
    }
    // strokeWidth is in PDF points; scale points -> px.
    final thickness =
        (strokePt * w / pageWidthPt).round().clamp(1, 64);

    switch (type) {
      case 'highlight':
        if (rect != null) {
          img.fillRect(
            canvas,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            color: fill,
          );
        }
      case 'underline':
      case 'strikethrough':
        if (rect != null) {
          final y = type == 'underline'
              ? y2 - thickness ~/ 2
              : (y1 + y2) ~/ 2;
          img.drawLine(
            canvas,
            x1: x1,
            y1: y,
            x2: x2,
            y2: y,
            color: solid,
            thickness: thickness,
          );
        }
      case 'pen':
        final pointsRaw = a['points_json'] as String?;
        if (pointsRaw != null) {
          final pts = (jsonDecode(pointsRaw) as List)
              .map((p) => [
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  ])
              .toList();
          for (var i = 0; i + 1 < pts.length; i++) {
            img.drawLine(
              canvas,
              x1: (pts[i][0] * w).round(),
              y1: (pts[i][1] * h).round(),
              x2: (pts[i + 1][0] * w).round(),
              y2: (pts[i + 1][1] * h).round(),
              color: solid,
              thickness: thickness,
            );
          }
        }
      case 'text':
        if (rect != null) {
          final text = a['text'] as String? ?? '';
          final font = (y2 - y1) < 28
              ? img.arial14
              : (y2 - y1) < 56
                  ? img.arial24
                  : img.arial48;
          img.drawString(
            canvas,
            text,
            font: font,
            x: x1,
            y: y1,
            color: solid,
          );
        }
      case 'signature':
        final sigPath = a['image_path'] as String?;
        if (rect != null && sigPath != null) {
          try {
            final sig = img.decodeImage(
              File(sigPath).readAsBytesSync(),
            );
            if (sig != null) {
              final resized = img.copyResize(
                sig,
                width: (x2 - x1).clamp(1, 4000),
                height: (y2 - y1).clamp(1, 4000),
              );
              img.compositeImage(
                canvas,
                resized,
                dstX: x1,
                dstY: y1,
              );
            }
          } catch (_) {
            // A missing signature file must not fail the whole export.
          }
        }
    }
  }
}

Future<void> _composeAndSave(
  List<_PageImage> pages,
  String outPath, {
  required int quality,
}) async {
  final doc = pw.Document();
  for (final p in pages) {
    final jpg = Uint8List.fromList(img.encodeJpg(p.image, quality: quality));
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(p.widthPt, p.heightPt, marginAll: 0),
        build: (_) => pw.Image(
          pw.MemoryImage(jpg),
          fit: pw.BoxFit.fill,
          width: p.widthPt,
          height: p.heightPt,
        ),
      ),
    );
  }
  final bytes = await doc.save();
  await File(outPath).writeAsBytes(bytes, flush: true);
}

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

Future<String> _exportAnnotated(
  Map<String, Object?> m,
  void Function(int, int) progress,
) async {
  final inPath = m['inPath'] as String;
  final outPath = m['outPath'] as String;
  final password = m['password'] as String?;
  final dpi = (m['dpi'] as num?)?.toInt() ?? 150;
  final quality = (m['quality'] as num?)?.toInt() ?? 85;
  final annotations =
      (m['annotations'] as List?)?.cast<Map<String, Object?>>() ?? const [];

  final doc = await _openDoc(inPath, password);
  try {
    final pages = <_PageImage>[];
    final total = doc.pages.length;
    for (var n = 1; n <= total; n++) {
      final rendered = await _renderPage(doc, n, dpi: dpi);
      final forPage = annotations
          .where((a) => (a['page'] as num?)?.toInt() == n)
          .map((a) => {...a, '_pageWidthPt': rendered.widthPt})
          .toList();
      _drawAnnotations(rendered.image, forPage);
      pages.add(rendered);
      progress(n, total);
    }
    await _composeAndSave(pages, outPath, quality: quality);
    return outPath;
  } finally {
    await doc.dispose();
  }
}

Future<String> _merge(
  Map<String, Object?> m,
  void Function(int, int) progress,
) async {
  final inputs = (m['inputs'] as List).cast<Map<String, Object?>>();
  final outPath = m['outPath'] as String;
  final dpi = (m['dpi'] as num?)?.toInt() ?? 150;
  final quality = (m['quality'] as num?)?.toInt() ?? 85;

  // Count pages first so progress is accurate.
  var total = 0;
  final counts = <int>[];
  for (final input in inputs) {
    final doc = await _openDoc(
      input['path'] as String,
      input['password'] as String?,
    );
    counts.add(doc.pages.length);
    total += doc.pages.length;
    await doc.dispose();
  }

  final pages = <_PageImage>[];
  var done = 0;
  for (var k = 0; k < inputs.length; k++) {
    final doc = await _openDoc(
      inputs[k]['path'] as String,
      inputs[k]['password'] as String?,
    );
    try {
      for (var n = 1; n <= counts[k]; n++) {
        pages.add(await _renderPage(doc, n, dpi: dpi));
        progress(++done, total);
      }
    } finally {
      await doc.dispose();
    }
  }
  await _composeAndSave(pages, outPath, quality: quality);
  return outPath;
}

Future<List<String>> _split(
  Map<String, Object?> m,
  void Function(int, int) progress,
) async {
  final inPath = m['inPath'] as String;
  final outDir = m['outDir'] as String;
  final baseName = m['baseName'] as String;
  final password = m['password'] as String?;
  final dpi = (m['dpi'] as num?)?.toInt() ?? 150;
  final quality = (m['quality'] as num?)?.toInt() ?? 85;
  final ranges = (m['ranges'] as List)
      .map((r) => [(r[0] as num).toInt(), (r[1] as num).toInt()])
      .toList();

  final outputs = <String>[];
  final doc = await _openDoc(inPath, password);
  try {
    var done = 0;
    final total = ranges.fold<int>(0, (p, r) => p + (r[1] - r[0] + 1));
    for (var k = 0; k < ranges.length; k++) {
      final pages = <_PageImage>[];
      for (var n = ranges[k][0]; n <= ranges[k][1]; n++) {
        pages.add(await _renderPage(doc, n, dpi: dpi));
        progress(++done, total);
      }
      final outPath = '$outDir/${baseName}_part${k + 1}.pdf';
      await _composeAndSave(pages, outPath, quality: quality);
      outputs.add(outPath);
    }
    return outputs;
  } finally {
    await doc.dispose();
  }
}

Future<String> _reorder(
  Map<String, Object?> m,
  void Function(int, int) progress,
) async {
  final inPath = m['inPath'] as String;
  final outPath = m['outPath'] as String;
  final password = m['password'] as String?;
  final dpi = (m['dpi'] as num?)?.toInt() ?? 150;
  final quality = (m['quality'] as num?)?.toInt() ?? 85;
  final order = (m['order'] as List).map((e) => (e as num).toInt()).toList();

  final doc = await _openDoc(inPath, password);
  try {
    final pages = <_PageImage>[];
    for (var k = 0; k < order.length; k++) {
      pages.add(await _renderPage(doc, order[k], dpi: dpi));
      progress(k + 1, order.length);
    }
    await _composeAndSave(pages, outPath, quality: quality);
    return outPath;
  } finally {
    await doc.dispose();
  }
}

Future<String> _compress(
  Map<String, Object?> m,
  void Function(int, int) progress,
) async {
  final inPath = m['inPath'] as String;
  final outPath = m['outPath'] as String;
  final password = m['password'] as String?;
  final dpi = (m['dpi'] as num?)?.toInt() ?? 110;
  final quality = (m['quality'] as num?)?.toInt() ?? 70;

  final doc = await _openDoc(inPath, password);
  try {
    final pages = <_PageImage>[];
    final total = doc.pages.length;
    for (var n = 1; n <= total; n++) {
      pages.add(await _renderPage(doc, n, dpi: dpi));
      progress(n, total);
    }
    await _composeAndSave(pages, outPath, quality: quality);
    return outPath;
  } finally {
    await doc.dispose();
  }
}

Future<String> _imagesToPdf(
  Map<String, Object?> m,
  void Function(int, int) progress,
) async {
  final images = (m['images'] as List).cast<String>();
  final outPath = m['outPath'] as String;
  final pageSize = m['pageSize'] as String? ?? 'fit';
  final quality = (m['quality'] as num?)?.toInt() ?? 85;

  final doc = pw.Document();
  for (var k = 0; k < images.length; k++) {
    final bytes = await File(images[k]).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw PdfException('Could not read image ${k + 1}');
    if (image.width > 2400 || image.height > 2400) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? 2400 : null,
        height: image.height > image.width ? 2400 : null,
      );
    }
    final jpg = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    final PdfPageFormat format;
    if (pageSize == 'a4') {
      format = PdfPageFormat.a4;
    } else {
      format = PdfPageFormat(
        image.width * 72 / 150,
        image.height * 72 / 150,
        marginAll: 0,
      );
    }
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.contain),
        ),
      ),
    );
    progress(k + 1, images.length);
  }
  final bytes = await doc.save();
  await File(outPath).writeAsBytes(bytes, flush: true);
  return outPath;
}
