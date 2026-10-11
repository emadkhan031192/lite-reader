import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/press_scale.dart';
import '../providers.dart';

/// Text tabs for the Files screen: All / PDF / Office / Starred.
/// Each tab shows its label plus a DM Mono count; the active tab
/// has a 2px indigo underline spanning the full tab width.
class LibraryTabs extends StatelessWidget {
  const LibraryTabs({
    super.key,
    required this.active,
    required this.counts,
    required this.onChanged,
  });

  final LibraryTab active;
  final Map<LibraryTab, int> counts;
  final ValueChanged<LibraryTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [for (final tab in LibraryTab.values) _buildTab(tab)],
    );
  }

  Widget _buildTab(LibraryTab tab) {
    final isActive = tab == active;
    final count = counts[tab] ?? 0;
    final labelStyle = isActive
        ? AppText.body.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          )
        : AppText.body.copyWith(color: AppColors.tertiary);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: '${tab.label}, $count files',
        child: PressScale(
          onTap: () => onChanged(tab),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isActive ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(tab.label, style: labelStyle),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppText.monoSize(
                    12,
                    color: isActive ? AppColors.accent : AppColors.tertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
