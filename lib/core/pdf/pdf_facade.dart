import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// Flattened outline entry for the Contents tab.
class OutlineEntry {
  const OutlineEntry({
    required this.title,
    required this.pageNumber,
    required this.depth,
  });

  final String title;
  /// 1-based page number.
  final int pageNumber;
  final int depth;
}

/// Page dimensions in PDF points (1/72 inch).
class PdfPageSize {
  const PdfPageSize(this.width, this.height);

  final double width;
  final double height;
}

/// Verified pdfrx (PDFium) operations used across the app.
///
/// All functions open the document, do the work, and dispose it, so they are
/// safe to call from the UI isolate or from inside a background isolate
/// worker (each isolate opens its own document).
///
/// Throws [PdfPasswordException] when the file needs a password or the
/// password is wrong.
abstract final class PdfFacade {
  static Future<int> pageCount(String path, {String? password}) async {
    final doc = await _open(path, password: password);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  static Future<List<PdfPageSize>> pageSizes(
    String path, {
    String? password,
  }) async {
    final doc = await _open(path, password: password);
    try {
      return [
        for (final p in doc.pages) PdfPageSize(p.width, p.height),
      ];
    } finally {
      await doc.dispose();
    }
  }

  static Future<List<OutlineEntry>> outline(
    String path, {
    String? password,
  }) async {
    final doc = await _open(path, password: password);
    try {
      final nodes = await doc.loadOutline();
      final out = <OutlineEntry>[];
      void walk(List<PdfOutlineNode> children, int depth) {
        for (final node in children) {
          final page = node.dest?.pageNumber ?? 0;
          out.add(OutlineEntry(
            title: node.title,
            pageNumber: page < 1 ? 1 : page,
            depth: depth,
          ));
          walk(node.children, depth + 1);
        }
      }

      walk(nodes, 0);
      return out;
    } finally {
      await doc.dispose();
    }
  }

  /// Renders [pageNumber] (1-based) to PNG bytes at [widthPx] wide.
  /// Uses the pure-Dart `image` package for encoding so it also works
  /// inside background isolates (no dart:ui needed).
  static Future<Uint8List> renderPagePng(
    String path,
    int pageNumber, {
    required int widthPx,
    String? password,
    int backgroundColor = 0xFFFFFFFF,
  }) async {
    final doc = await _open(path, password: password);
    try {
      final page = doc.pages[pageNumber - 1];
      final scale = widthPx / page.width;
      final heightPx = (page.height * scale).round().clamp(1, 20000);
      final rendered = await page.render(
        width: widthPx,
        height: heightPx,
        backgroundColor: backgroundColor,
      );
      if (rendered == null) {
        throw PdfException('Could not render page $pageNumber');
      }
      final decoded = img.Image.fromBytes(
        width: rendered.width,
        height: rendered.height,
        bytes: rendered.pixels.buffer,
        order: img.ChannelOrder.bgra,
      );
      return Uint8List.fromList(img.encodePng(decoded));
    } finally {
      await doc.dispose();
    }
  }

  /// Renders [pageNumber] (1-based) to raw BGRA pixels at [widthPx] wide.
  /// Lower overhead than [renderPagePng] for tool pipelines that draw
  /// annotations before encoding.
  static Future<RenderedPage> renderPageRaw(
    String path,
    int pageNumber, {
    required int widthPx,
    String? password,
    int backgroundColor = 0xFFFFFFFF,
  }) async {
    final doc = await _open(path, password: password);
    try {
      final page = doc.pages[pageNumber - 1];
      final size = PdfPageSize(page.width, page.height);
      final scale = widthPx / page.width;
      final heightPx = (page.height * scale).round().clamp(1, 20000);
      final rendered = await page.render(
        width: widthPx,
        height: heightPx,
        backgroundColor: backgroundColor,
      );
      if (rendered == null) {
        throw PdfException('Could not render page $pageNumber');
      }
      return RenderedPage(
        pageSize: size,
        widthPx: rendered.width,
        heightPx: rendered.height,
        bgra: rendered.pixels,
      );
    } finally {
      await doc.dispose();
    }
  }

  static Future<PdfDocument> _open(String path, {String? password}) {
    return PdfDocument.openFile(
      path,
      passwordProvider: createSimplePasswordProvider(password),
      firstAttemptByEmptyPassword: password == null,
    );
  }
}

/// A rendered page: raw BGRA pixels plus the source page size in points.
class RenderedPage {
  const RenderedPage({
    required this.pageSize,
    required this.widthPx,
    required this.heightPx,
    required this.bgra,
  });

  final PdfPageSize pageSize;
  final int widthPx;
  final int heightPx;
  final Uint8List bgra;
}
