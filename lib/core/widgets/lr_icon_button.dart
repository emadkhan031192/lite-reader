import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'press_scale.dart';

/// Icon-only button: 44px touch target, 22px icon, semantic label,
/// scales to 0.96 on press.
class LrIconButton extends StatelessWidget {
  const LrIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.color,
    this.selected = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? (selected ? AppColors.accent : AppColors.ink);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: PressScale(
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: effectiveColor),
        ),
      ),
    );
  }
}
