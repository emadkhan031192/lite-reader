import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/lr_icon_button.dart';

/// Replaces the AppBar while rows are selected: a close button,
/// a "`count` selected" title, and Share / Merge / Remove actions.
/// Pass [onMerge] as null to disable merging (fewer than 2 PDFs selected).
class SelectionBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onShare,
    required this.onMerge,
    required this.onRemove,
    required this.onClear,
  });

  final int count;
  final VoidCallback onShare;
  final VoidCallback? onMerge;
  final VoidCallback onRemove;
  final VoidCallback onClear;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: LrIconButton(
        icon: Icons.close,
        semanticLabel: 'Clear selection',
        onPressed: onClear,
      ),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$count',
              style: AppText.monoSize(
                15,
                color: AppColors.ink,
                weight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: ' selected',
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      actions: [
        LrIconButton(
          icon: Icons.share_outlined,
          semanticLabel: 'Share selected',
          onPressed: onShare,
        ),
        Opacity(
          opacity: onMerge == null ? 0.35 : 1.0,
          child: LrIconButton(
            icon: Icons.merge_type,
            semanticLabel: 'Merge selected',
            onPressed: onMerge,
          ),
        ),
        LrIconButton(
          icon: Icons.delete_outline,
          semanticLabel: 'Remove selected',
          onPressed: onRemove,
        ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: SizedBox(
          height: 1,
          child: ColoredBox(color: AppColors.hairline),
        ),
      ),
    );
  }
}
