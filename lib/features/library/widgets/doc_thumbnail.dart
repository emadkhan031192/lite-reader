import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/document.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/theme/app_colors.dart';

/// Page-1 thumbnail for a library document, rendered once and cached on
/// disk by [ThumbnailService]. [size] is the width; the height follows
/// the ~1.3 page aspect ratio. Shows a quiet placeholder until (or when)
/// no thumbnail is available.
class DocThumbnail extends ConsumerStatefulWidget {
  const DocThumbnail({super.key, required this.doc, required this.size});

  final LibraryDocument doc;
  final double size;

  @override
  ConsumerState<DocThumbnail> createState() => _DocThumbnailState();
}

class _DocThumbnailState extends ConsumerState<DocThumbnail> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DocThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      _path = null;
      _load();
    }
  }

  Future<void> _load() async {
    final path =
        await ref.read(thumbnailServiceProvider).ensureThumbnail(widget.doc);
    if (!mounted) return;
    setState(() => _path = path);
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.size * 1.3;
    final path = _path;
    if (path != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        child: Image.file(
          File(path),
          width: widget.size,
          height: height,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: widget.size,
      height: height,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Icon(
        widget.doc.isPdf
            ? Icons.picture_as_pdf_outlined
            : Icons.description_outlined,
        size: 20,
        color: AppColors.tertiary,
      ),
    );
  }
}
