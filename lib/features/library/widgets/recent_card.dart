import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/document.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/press_scale.dart';
import 'doc_thumbnail.dart';

/// A recent-file card: page thumbnail, a thin 2px progress line under it,
/// and the file name on one line.
class RecentCard extends ConsumerWidget {
  const RecentCard({
    super.key,
    required this.doc,
    required this.progress,
    required this.onTap,
  });

  final LibraryDocument doc;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showExtensions = ref.watch(settingsProvider).showFileExtensions;
    return Semantics(
      button: true,
      label: 'Open ${doc.displayName}',
      child: PressScale(
        onTap: onTap,
        child: SizedBox(
          width: 124,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DocThumbnail(
                key: ValueKey('recent-${doc.id}'),
                doc: doc,
                size: 112,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 112,
                height: 2,
                child: Stack(
                  children: [
                    const ColoredBox(color: AppColors.rowDivider),
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: const ColoredBox(color: AppColors.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: Text(
                  _name(doc.displayName, showExtensions),
                  style: AppText.small.copyWith(color: AppColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _name(String name, bool showExtensions) {
    if (showExtensions) return name;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
