import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/press_scale.dart';

/// Result of the signature pad: the captured PNG, the typed/drawn name and
/// whether the user wants a "Signed <date>" caption.
class SignatureResult {
  const SignatureResult({
    required this.bytes,
    required this.name,
    required this.includeDate,
  });

  final Uint8List bytes;
  final String name;
  final bool includeDate;
}

/// Shows the signature dialog (Draw / Type tabs). Returns null on cancel.
Future<SignatureResult?> showSignaturePad(BuildContext context) {
  return showDialog<SignatureResult>(
    context: context,
    builder: (context) => const _SignaturePadDialog(),
  );
}

class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog();

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final GlobalKey _repaintKey = GlobalKey();
  int _tab = 0; // 0 = draw, 1 = type
  final List<List<Offset>> _strokes = [];
  List<Offset> _current = [];
  String _name = '';
  bool _includeDate = true;

  bool get _hasContent => _tab == 0
      ? _strokes.any((s) => s.isNotEmpty) || _current.isNotEmpty
      : _name.trim().isNotEmpty;

  Future<Uint8List?> _capture() async {
    final boundaryContext = _repaintKey.currentContext;
    if (boundaryContext == null) return null;
    final boundary =
        boundaryContext.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _save() async {
    final bytes = await _capture();
    if (!mounted || bytes == null) return;
    Navigator.of(context).pop(
      SignatureResult(bytes: bytes, name: _name.trim(), includeDate: _includeDate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: const BorderSide(color: AppColors.hairline, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Signature',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            _SegmentedTabs(
              tab: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = min(300.0, constraints.maxWidth);
                return Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: width,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.hairline,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(7)),
                      child: _tab == 0
                          ? _buildDrawCanvas(width)
                          : _buildTypeCanvas(width),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _includeDate,
                  activeColor: AppColors.accent,
                  onChanged: (v) => setState(() => _includeDate = v ?? true),
                ),
                Expanded(
                  child: Text(
                    'Add "Signed ${formatSignedDate(DateTime.now())}"',
                    style: AppText.small,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    semanticsLabel: 'Cancel',
                    style: TextStyle(
                      fontFamily: AppText.zenKaku,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _hasContent ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.hairline,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  child: const Text(
                    'Save signature',
                    semanticsLabel: 'Save signature',
                    style: TextStyle(
                      fontFamily: AppText.zenKaku,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawCanvas(double width) {
    return GestureDetector(
      onPanStart: (details) =>
          setState(() => _current = [details.localPosition]),
      onPanUpdate: (details) =>
          setState(() => _current = [..._current, details.localPosition]),
      onPanEnd: (_) => setState(() {
        if (_current.isNotEmpty) {
          _strokes.add(_current);
          _current = [];
        }
      }),
      onPanCancel: () => setState(() {
        if (_current.isNotEmpty) {
          _strokes.add(_current);
          _current = [];
        }
      }),
      child: RepaintBoundary(
        key: _repaintKey,
        child: CustomPaint(
          size: Size(width, 160),
          painter: _SignatureDrawPainter(
            strokes: [..._strokes, if (_current.isNotEmpty) _current],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeCanvas(double width) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Type your name',
              isDense: true,
            ),
            style: const TextStyle(
              fontFamily: AppText.zenKaku,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
            onChanged: (v) => setState(() => _name = v),
          ),
        ),
        Expanded(
          child: RepaintBoundary(
            key: _repaintKey,
            child: SizedBox(
              width: width,
              child: Center(
                child: Text(
                  _name.trim().isEmpty ? 'Your name' : _name.trim(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppText.zenKaku,
                    fontSize: 28,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: _name.trim().isEmpty
                        ? AppColors.tertiary
                        : AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.tab, required this.onSelect});

  final int tab;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Signature input mode',
      child: Row(
        children: [
          _tabButton(0, 'Draw'),
          const SizedBox(width: 8),
          _tabButton(1, 'Type'),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label) {
    final active = tab == index;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        selected: active,
        child: PressScale(
          onTap: () => onSelect(index),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.accentTint : Colors.transparent,
              borderRadius: BorderRadius.all(Radius.circular(8)),
              border: Border.all(
                color: active ? AppColors.accent : AppColors.hairline,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.accent : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignatureDrawPainter extends CustomPainter {
  _SignatureDrawPainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, stroke, paint);
      } else {
        final path = Path()
          ..moveTo(stroke.first.dx, stroke.first.dy);
        for (var i = 1; i < stroke.length; i++) {
          path.lineTo(stroke[i].dx, stroke[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignatureDrawPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes);
}
