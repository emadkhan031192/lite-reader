import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/annotation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/press_scale.dart';
import '../providers.dart';

/// Bottom tool dock: the six annotation tools. Tapping the active tool again
/// returns to select/move mode. Each button is 56px tall with a 22px icon.
class ToolDock extends ConsumerWidget {
  const ToolDock({super.key});

  static const List<(AnnotationType, IconData, String)> _tools = [
    (AnnotationType.highlight, Icons.highlight, 'Highlight'),
    (AnnotationType.underline, Icons.format_underline, 'Underline'),
    (AnnotationType.strikethrough, Icons.strikethrough_s, 'Strikethrough'),
    (AnnotationType.pen, Icons.brush, 'Pen'),
    (AnnotationType.text, Icons.text_fields, 'Text'),
    (AnnotationType.signature, Icons.gesture, 'Signature'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(annotateToolProvider);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (final (type, icon, label) in _tools)
            Expanded(
              child: _ToolButton(
                icon: icon,
                label: label,
                active: active == type,
                onTap: () => ref
                    .read(annotateToolProvider.notifier)
                    .set(active == type ? null : type),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      selected: active,
      child: PressScale(
        onTap: onTap,
        child: Container(
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.accentTint : Colors.transparent,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: active ? AppColors.accent : AppColors.secondaryText,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: AppText.zenKaku,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: active ? AppColors.accent : AppColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
