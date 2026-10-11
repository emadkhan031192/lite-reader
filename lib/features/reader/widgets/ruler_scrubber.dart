import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Ruler-style page scrubber: 56px tall, baseline hairline with ticks,
/// an indigo handle at the current progress, and a page-number bubble
/// while dragging. Dragging anywhere on the bar scrubs; releasing jumps.
class RulerScrubber extends StatefulWidget {
  const RulerScrubber({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.onPageSelected,
  });

  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  @override
  State<RulerScrubber> createState() => _RulerScrubberState();
}

class _RulerScrubberState extends State<RulerScrubber> {
  bool _dragging = false;
  int _dragPage = 1;

  int get _pageCount => widget.pageCount <= 0 ? 1 : widget.pageCount;

  double _progressFor(int page) =>
      _pageCount <= 1 ? 0.0 : (page - 1) / (_pageCount - 1);

  int _pageForDx(double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    return (1 + t * (_pageCount - 1)).round().clamp(1, _pageCount);
  }

  void _beginDrag(double dx, double width) {
    setState(() {
      _dragging = true;
      _dragPage = _pageForDx(dx, width);
    });
  }

  void _updateDrag(double dx, double width) {
    final page = _pageForDx(dx, width);
    if (page != _dragPage) setState(() => _dragPage = page);
  }

  void _endDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onPageSelected(_dragPage);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final shownPage = _dragging ? _dragPage : widget.currentPage;
        final bubbleT = _progressFor(shownPage).clamp(0.07, 0.93);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragDown: (d) => _beginDrag(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) =>
              _updateDrag(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _endDrag(),
          onHorizontalDragCancel: () =>
              setState(() => _dragging = false),
          child: SizedBox(
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RulerPainter(
                      pageCount: _pageCount,
                      progress: _progressFor(
                        widget.currentPage.clamp(1, _pageCount),
                      ),
                    ),
                  ),
                ),
                if (_dragging)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment(bubbleT * 2 - 1, -1),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: const BorderRadius.all(Radius.circular(12)),
                            border: Border.all(
                                color: AppColors.hairline),
                          ),
                          child: Text(
                            '$shownPage',
                            style: AppText.monoSize(12,
                                color: AppColors.ink,
                                weight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Baseline hairline, ticks (one per page up to 100 segments, then bucketed;
/// medium every 5, tall every 10), and the indigo handle circle.
class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.pageCount, required this.progress});

  final int pageCount;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const baselineY = 44.0;
    final hairlinePaint = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    final tickPaint = Paint()
      ..color = AppColors.tertiary
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      const Offset(0, baselineY),
      Offset(size.width, baselineY),
      hairlinePaint,
    );

    final segments = pageCount <= 100 ? pageCount : 100;
    for (var i = 0; i < segments; i++) {
      final x = segments == 1
          ? size.width / 2
          : size.width * i / (segments - 1);
      final double tickHeight;
      if (i % 10 == 0) {
        tickHeight = 14;
      } else if (i % 5 == 0) {
        tickHeight = 10;
      } else {
        tickHeight = 6;
      }
      canvas.drawLine(
        Offset(x, baselineY - tickHeight),
        Offset(x, baselineY),
        tickHeight > 6 ? tickPaint : hairlinePaint,
      );
    }

    final handleX = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(handleX, baselineY),
      9,
      Paint()..color = AppColors.accent,
    );
    canvas.drawCircle(
      Offset(handleX, baselineY),
      3.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.pageCount != pageCount ||
      oldDelegate.progress != progress;
}
