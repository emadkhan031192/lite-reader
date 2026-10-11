import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/device.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/section_label.dart';
import 'widgets/tool_scaffold.dart';

/// Scans pages with the camera (or picks from the gallery), then hands the
/// images to Images to PDF. The camera permission is only requested here,
/// after an in-app explanation.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<String> _scans = const [];
  bool _busy = false;

  Future<void> _startScan() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Camera', style: AppText.body),
        content: const Text(
          'Lite Reader uses the camera only to scan documents. '
          'Scans stay on your phone.',
          style: AppText.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      var granted = await Device.isCameraGranted();
      if (!granted) granted = await Device.requestCamera();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is needed to scan.'),
          ),
        );
        return;
      }
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 100,
        scannerSource: ScannerSource.cameraAndGallery,
      );
      if (!mounted) return;
      if (pictures != null && pictures.isNotEmpty) {
        setState(() => _scans = pictures);
      }
    } on CunningDocumentScannerException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolScaffold(
      title: 'Scan to PDF',
      children: [
        if (_scans.isEmpty)
          SizedBox(
            height: 360,
            child: EmptyState(
              message: 'Scan pages with the camera',
              buttonLabel: _busy ? 'Starting…' : 'Start scan',
              buttonSemanticLabel: 'Start scan',
              onButtonPressed: _busy ? () {} : _startScan,
            ),
          )
        else ...[
          const SectionLabel('Scans'),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _scans.length,
            itemBuilder: (context, i) => ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              child: Image.file(
                File(_scans[i]),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: AppColors.background),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Scan more',
                  child: PressScale(
                    onTap: _busy ? null : _startScan,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border.fromBorderSide(BorderSide(color: AppColors.accent)),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: const Text(
                        'Scan more',
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
                child: Semantics(
                  button: true,
                  label: 'Create PDF',
                  child: PressScale(
                    onTap: () =>
                        context.push('/tools/images', extra: _scans),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: const Text(
                        'Create PDF',
                        style: TextStyle(
                          fontFamily: AppText.zenKaku,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
