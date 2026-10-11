import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// De-risks the tools architecture: pdfrx must render inside a background
/// isolate (used by Merge/Split/Compress/Export).
///
/// `flutter test` does not run the pdfium_dart build hook, so PDFium is only
/// available when PDFIUM_SO points at a libpdfium.so (the sandbox downloads
/// the same bblanchon/pdfium-binaries build the hook uses). Without it the
/// tests self-skip; they never fail CI.
String? _pdfiumSo() {
  final env = Platform.environment['PDFIUM_SO'];
  if (env != null && File(env).existsSync()) return env;
  const fallback = '/home/hatch/tmp/pdfium/lib/libpdfium.so';
  if (File(fallback).existsSync()) return fallback;
  return null;
}

Future<String> _makePdf() async {
  final doc = pw.Document();
  for (var i = 1; i <= 2; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (c) => pw.Center(
          child:
              pw.Text('Hello page $i', style: const pw.TextStyle(fontSize: 40)),
        ),
      ),
    );
  }
  final path =
      '${Directory.systemTemp.path}/probe_${DateTime.now().microsecondsSinceEpoch}.pdf';
  await File(path).writeAsBytes(await doc.save());
  return path;
}

/// Returns false (after marking the test skipped) when PDFium is unavailable.
/// `markTestSkipped` alone does not stop the test body, so callers must
/// return early on false.
Future<bool> _ensurePdfium() async {
  final so = _pdfiumSo();
  if (so == null) {
    markTestSkipped('PDFium not provisioned for flutter test (no PDFIUM_SO)');
    return false;
  }
  Pdfrx.pdfiumModulePath = so;
  return true;
}

void main() {
  test('pdfrx opens and renders in the main isolate', () async {
    if (!await _ensurePdfium()) return;
    final path = await _makePdf();
    final doc = await PdfDocument.openFile(path);
    expect(doc.pages.length, 2);
    final page = doc.pages[0];
    expect(page.width, greaterThan(0));
    expect(page.height, greaterThan(0));
    final img = await page.render(width: 200, height: 282);
    expect(img, isNotNull);
    expect(img!.pixels.length, img.width * img.height * 4);
    await doc.dispose();
  });

  test('pdfrx renders inside Isolate.run', () async {
    if (!await _ensurePdfium()) return;
    final path = await _makePdf();
    final so = _pdfiumSo()!;
    final result = await Isolate.run(() async {
      Pdfrx.pdfiumModulePath = so;
      final doc = await PdfDocument.openFile(path);
      final img = await doc.pages[1].render(width: 200, height: 282);
      final info =
          '${doc.pages.length}:${img?.width}x${img?.height}:${img?.pixels.length}';
      await doc.dispose();
      return info;
    });
    expect(result, '2:200x282:${200 * 282 * 4}');
  });

}
