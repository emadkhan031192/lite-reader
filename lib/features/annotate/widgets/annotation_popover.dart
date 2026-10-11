import 'package:flutter/material.dart';

import '../../../core/models/annotation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/lr_icon_button.dart';
import '../../../core/widgets/press_scale.dart';

/// Floating card shown above the selected annotation: five color dots,
/// an "Add note" action and delete. Quiet surface with a 1px hairline
/// border — no shadow.
class AnnotationPopover extends StatelessWidget {
  const AnnotationPopover({
    super.key,
    required this.annotation,
    required this.onDelete,
    required this.onColor,
    required this.onAddNote,
    required this.onClose,
  });

  final PdfAnnotation annotation;
  final VoidCallback onDelete;
  final ValueChanged<int> onColor;
  final VoidCallback onAddNote;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(10)),
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final color in AppColors.highlightColors)
                _ColorDot(
                  color: color,
                  selected: annotation.color == color.toARGB32(),
                  onTap: () => onColor(color.toARGB32()),
                ),
              const Spacer(),
              LrIconButton(
                icon: Icons.delete_outline,
                semanticLabel: 'Delete annotation',
                onPressed: onDelete,
                color: AppColors.secondaryText,
              ),
            ],
          ),
          if (annotation.note != null && annotation.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text(
                annotation.note!,
                style: AppText.small,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            children: [
              TextButton(
                onPressed: onAddNote,
                child: Text(
                  annotation.note == null || annotation.note!.isEmpty
                      ? 'Add note'
                      : 'Edit note',
                  semanticsLabel: 'Add note',
                  style: const TextStyle(
                    fontFamily: AppText.zenKaku,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onClose,
                child: const Text(
                  'Close',
                  semanticsLabel: 'Close',
                  style: TextStyle(
                    fontFamily: AppText.zenKaku,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Annotation color',
      selected: selected,
      child: PressScale(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.hairline,
                width: selected ? 2 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
