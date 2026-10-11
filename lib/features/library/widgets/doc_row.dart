import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/document.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/lr_icon_button.dart';
import '../../../core/widgets/press_scale.dart';
import 'doc_thumbnail.dart';

/// One library row: mini thumbnail, name, a DM Mono meta line,
/// a 64px progress hairline, and a star toggle.
class DocRow extends ConsumerWidget {
  const DocRow({
    super.key,
    required this.doc,
    required this.progress,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleStar,
  });

  final LibraryDocument doc;
  final double progress;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showExtensions = ref.watch(settingsProvider).showFileExtensions;
    return Semantics(
      button: true,
      label: doc.displayName,
      child: PressScale(
        onTap: onTap,
        child: GestureDetector(
          onLongPress: onLongPress,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 64,
            color: selected ? AppColors.accentTint : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                DocThumbnail(
                  key: ValueKey('row-${doc.id}'),
                  doc: doc,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name(doc.displayName, showExtensions),
                        style: AppText.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      _metaLine(),
                      if (doc.isPdf && progress > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: 64,
                            height: 2,
                            child: Stack(
                              children: [
                                const ColoredBox(color: AppColors.rowDivider),
                                FractionallySizedBox(
                                  widthFactor: progress.clamp(0.0, 1.0),
                                  alignment: Alignment.centerLeft,
                                  child: const ColoredBox(
                                    color: AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                LrIconButton(
                  icon: doc.starred ? Icons.star : Icons.star_border,
                  semanticLabel: doc.starred ? 'Unstar' : 'Star',
                  selected: doc.starred,
                  onPressed: onToggleStar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaLine() {
    final date = formatShortDate(
      DateTime.fromMillisecondsSinceEpoch(doc.modified),
    );
    final String meta;
    if (doc.isPdf) {
      meta = doc.pageCount > 0
          ? '${formatBytes(doc.size)} · ${doc.pageCount} pages · $date'
          : '${formatBytes(doc.size)} · $date';
    } else {
      final ext = p.extension(doc.displayName);
      final tag = ext.isNotEmpty ? ext.substring(1).toUpperCase() : 'FILE';
      meta = '$tag · ${formatBytes(doc.size)} · $date';
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: meta, style: AppText.monoSize(12)),
          if (!doc.isPdf)
            const TextSpan(
              text: ' · Opens in another app',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.tertiary,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _name(String name, bool showExtensions) {
    if (showExtensions) return name;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
