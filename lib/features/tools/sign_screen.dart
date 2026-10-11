import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;

import '../../core/db/app_database.dart';
import '../../core/models/annotation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/section_label.dart';
import 'widgets/doc_picker_field.dart';
import 'widgets/tool_result_sheet.dart';
import 'widgets/tool_run.dart';
import 'widgets/tool_scaffold.dart';

/// Places a saved signature on a page, or exports a copy with all
/// annotations baked in. New signatures are drawn in Annotate.
class SignScreen extends StatefulWidget {
  const SignScreen({super.key, required this.documentId});

  final int documentId;

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  late int _docId = widget.documentId;
  Future<List<Map<String, Object?>>>? _signaturesFuture;
  String? _selectedSignaturePath;
  final _pageController = TextEditingController(text: '1');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _signaturesFuture = AppDatabase.instance.getSignatures();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectDoc(int id) => setState(() => _docId = id);

  Future<void> _placeSignature() async {
    final signaturePath = _selectedSignaturePath;
    if (_busy || _docId == 0 || signaturePath == null) return;
    final page = int.tryParse(_pageController.text.trim()) ?? 0;
    setState(() => _busy = true);
    try {
      late final ResolvedDoc resolved;
      try {
        resolved = await resolveDocForTool(_docId);
      } on PdfPasswordException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Password-protected files need to be opened in the reader first.',
              ),
            ),
          );
        }
        return;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the document.')),
          );
        }
        return;
      }
      if (page < 1 || page > resolved.pageCount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Enter a page between 1 and ${resolved.pageCount}.'),
            ),
          );
        }
        return;
      }
      await AppDatabase.instance.insertAnnotation(
        PdfAnnotation(
          documentId: _docId,
          page: page,
          type: AnnotationType.signature,
          color: 0xFF1A1C20,
          rect: const [0.29, 0.44, 0.42, 0.12],
          imagePath: signaturePath,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signature placed on page $page.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCopy() async {
    if (_busy || _docId == 0) return;
    setState(() => _busy = true);
    try {
      late final ResolvedDoc resolved;
      try {
        resolved = await resolveDocForTool(_docId);
      } on PdfPasswordException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Password-protected files need to be opened in the reader first.',
              ),
            ),
          );
        }
        return;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the document.')),
          );
        }
        return;
      }
      final annotations =
          await AppDatabase.instance.getAllAnnotations(_docId);
      final dir = await toolOutputDir();
      final base = toolBaseName(resolved.document.displayName);
      final outPath = '${dir.path}/${base}_signed.pdf';
      if (!mounted) return;
      final outputs = await runToolWithProgress(
        context,
        {
          'kind': 'export',
          'inPath': resolved.path,
          'outPath': outPath,
          'dpi': 150,
          'quality': 85,
          'annotations': annotations.map((a) => a.toMap()).toList(),
        },
        title: 'Saving a copy…',
      );
      if (!mounted) return;
      if (outputs != null) await showToolResultSheet(context, paths: outputs);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      title: 'Sign',
      children: [
        DocPickerField(
          documentId: _docId == 0 ? null : _docId,
          onChanged: _selectDoc,
        ),
        const SizedBox(height: 16),
        const SectionLabel('Signature'),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, Object?>>>(
          future: _signaturesFuture,
          builder: (context, snapshot) {
            final signatures = snapshot.data ?? const [];
            return SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: signatures.length + 1,
                itemBuilder: (context, i) {
                  if (i == signatures.length) return _newSignatureTile();
                  final sig = signatures[i];
                  final path = sig['image_path'] as String?;
                  if (path == null) return const SizedBox.shrink();
                  final selected = _selectedSignaturePath == path;
                  return Semantics(
                    button: true,
                    label:
                        'Use signature ${sig['name'] ?? ''}',
                    selected: selected,
                    child: PressScale(
                      onTap: () => setState(
                        () => _selectedSignaturePath = path,
                      ),
                      child: Container(
                        width: 104,
                        height: 56,
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(
                            color: selected
                                ? AppColors.accent
                                : AppColors.hairline,
                            width: selected ? 2 : 1,
                          ),
                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(
                            color: AppColors.background,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const SectionLabel('Page'),
        const SizedBox(height: 12),
        TextField(
          controller: _pageController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Page number',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        RunButton(
          label: _busy ? 'Working…' : 'Place signature',
          onPressed:
              _docId != 0 && _selectedSignaturePath != null && !_busy
                  ? _placeSignature
                  : null,
        ),
        const SizedBox(height: 16),
        const RasterNote(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Open in Annotate',
                child: PressScale(
                  onTap: _docId == 0
                      ? null
                      : () => context.push(
                            '/annotate?documentId=$_docId&page=1',
                          ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      border: Border.fromBorderSide(BorderSide(color: AppColors.accent)),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: const Text(
                      'Open in Annotate',
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
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RunButton(
                label: 'Save a copy',
                onPressed:
                    _docId != 0 && !_busy ? _saveCopy : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _newSignatureTile() {
    return Semantics(
      button: true,
      label: 'New signature',
      child: PressScale(
        onTap: () {
          if (_docId == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Choose a document first.'),
              ),
            );
            return;
          }
          context.push('/annotate?documentId=$_docId&page=1');
        },
        child: Container(
          width: 104,
          height: 56,
          margin: const EdgeInsets.only(right: 8),
          decoration: const BoxDecoration(
            border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 22, color: AppColors.accent),
              SizedBox(height: 2),
              Text('New', style: AppText.small),
            ],
          ),
        ),
      ),
    );
  }
}
