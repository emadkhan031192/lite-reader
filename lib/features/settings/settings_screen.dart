import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models/document.dart';
import '../../core/platform/saf.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/thumbnail_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/lr_icon_button.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/section_label.dart';

/// App settings: page color, reading, files, and an offline footer.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _chooseFolder(BuildContext context, WidgetRef ref) async {
    final uri = await Saf.pickDocumentTree();
    if (uri == null) return;
    await ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            chosenFolderUri: uri,
            openLocationMode: OpenLocationMode.chosen,
          ),
        );
  }

  Future<void> _clearThumbnailCache(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear thumbnail cache', style: AppText.body),
        content: const Text(
          'Cached page thumbnails will be rebuilt the next time you open a document.',
          style: AppText.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(thumbnailServiceProvider).clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thumbnail cache cleared')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final updater = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Page color'),
          const SizedBox(height: 12),
          Row(
            children: [
              _PageColorTile(
                label: 'Paper',
                color: AppColors.surface,
                selected: settings.pageColor == PageColorMode.paper,
                onTap: () => updater.update(
                  (s) => s.copyWith(pageColor: PageColorMode.paper),
                ),
              ),
              const SizedBox(width: 12),
              _PageColorTile(
                label: 'Soft grey',
                color: AppColors.softGreyPage,
                selected: settings.pageColor == PageColorMode.softGrey,
                onTap: () => updater.update(
                  (s) => s.copyWith(pageColor: PageColorMode.softGrey),
                ),
              ),
              const SizedBox(width: 12),
              _PageColorTile(
                label: 'Night',
                color: AppColors.nightPage,
                selected: settings.pageColor == PageColorMode.night,
                onTap: () => updater.update(
                  (s) => s.copyWith(pageColor: PageColorMode.night),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SwitchRow(
            label: 'Follow system',
            value: settings.followSystemTheme,
            semanticLabel: 'Follow system theme',
            onChanged: (v) => updater.update(
              (s) => s.copyWith(followSystemTheme: v),
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Reading'),
          const SizedBox(height: 12),
          const Text('Page flow', style: AppText.small),
          _OptionRow(
            label: 'Vertical scroll',
            selected: settings.pageFlow == PageFlow.vertical,
            onTap: () => updater.update(
              (s) => s.copyWith(pageFlow: PageFlow.vertical),
            ),
          ),
          _OptionRow(
            label: 'Single page',
            selected: settings.pageFlow == PageFlow.single,
            onTap: () => updater.update(
              (s) => s.copyWith(pageFlow: PageFlow.single),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Default zoom', style: AppText.small),
          _OptionRow(
            label: 'Fit width',
            selected: settings.defaultZoom == DefaultZoom.fitWidth,
            onTap: () => updater.update(
              (s) => s.copyWith(defaultZoom: DefaultZoom.fitWidth),
            ),
          ),
          _OptionRow(
            label: 'Fit page',
            selected: settings.defaultZoom == DefaultZoom.fitPage,
            onTap: () => updater.update(
              (s) => s.copyWith(defaultZoom: DefaultZoom.fitPage),
            ),
          ),
          _OptionRow(
            label: '100%',
            selected: settings.defaultZoom == DefaultZoom.hundred,
            onTap: () => updater.update(
              (s) => s.copyWith(defaultZoom: DefaultZoom.hundred),
            ),
          ),
          const SizedBox(height: 8),
          _SwitchRow(
            label: 'Remember last page',
            value: settings.rememberLastPage,
            semanticLabel: 'Remember last page',
            onChanged: (v) => updater.update(
              (s) => s.copyWith(rememberLastPage: v),
            ),
          ),
          _SwitchRow(
            label: 'Tap the edges to turn pages',
            value: settings.tapEdgesToTurnPages,
            semanticLabel: 'Tap the edges to turn pages',
            onChanged: (v) => updater.update(
              (s) => s.copyWith(tapEdgesToTurnPages: v),
            ),
          ),
          _SwitchRow(
            label: 'Volume keys turn pages',
            value: settings.volumeKeysTurnPages,
            semanticLabel: 'Volume keys turn pages',
            onChanged: (v) => updater.update(
              (s) => s.copyWith(volumeKeysTurnPages: v),
            ),
          ),
          _SwitchRow(
            label: 'Keep screen awake',
            value: settings.keepScreenAwake,
            semanticLabel: 'Keep screen awake',
            onChanged: (v) => updater.update(
              (s) => s.copyWith(keepScreenAwake: v),
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Files'),
          const SizedBox(height: 12),
          _SwitchRow(
            label: 'Show file extensions',
            value: settings.showFileExtensions,
            semanticLabel: 'Show file extensions',
            onChanged: (v) => updater.update(
              (s) => s.copyWith(showFileExtensions: v),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Open files from', style: AppText.small),
          _OptionRow(
            label: 'Last used folder',
            selected:
                settings.openLocationMode == OpenLocationMode.lastUsed,
            onTap: () => updater.update(
              (s) => s.copyWith(openLocationMode: OpenLocationMode.lastUsed),
            ),
          ),
          _OptionRow(
            label: 'Chosen one',
            selected: settings.openLocationMode == OpenLocationMode.chosen,
            onTap: () => _chooseFolder(context, ref),
          ),
          const SizedBox(height: 4),
          Semantics(
            button: true,
            label: 'Choose folder',
            child: PressScale(
              onTap: () => _chooseFolder(context, ref),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border.fromBorderSide(BorderSide(color: AppColors.accent)),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: const Text(
                  'Choose folder',
                  style: TextStyle(
                    fontFamily: AppText.zenKaku,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Manage folders', style: AppText.small),
          const _FolderList(),
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Clear thumbnail cache',
            child: PressScale(
              onTap: () => _clearThumbnailCache(context, ref),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: const Text(
                  'Clear thumbnail cache',
                  style: AppText.body,
                ),
              ),
            ),
          ),
          FutureBuilder<List<LibraryDocument>>(
            future: AppDatabase.instance.getAllDocuments(),
            builder: (context, snapshot) {
              final total = (snapshot.data ?? const <LibraryDocument>[])
                  .fold<int>(0, (sum, d) => sum + d.size);
              return Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Text(
                  'Lite Reader 1.0 · ${formatBytes(total)} · works offline',
                  style: AppText.monoSize(12, color: AppColors.tertiary),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 64x44 page-color preview with an indigo ring when selected.
class _PageColorTile extends StatelessWidget {
  const _PageColorTile({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label page color',
      selected: selected,
      child: PressScale(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                border: Border.all(
                  color:
                      selected ? AppColors.accent : AppColors.hairline,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Radio-style option row, 48px tall.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      child: PressScale(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.accent
                        : AppColors.hairline,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Center(
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppText.body)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Switch row, 48px tall.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppText.body)),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// Added SAF folders with a remove button each.
class _FolderList extends ConsumerStatefulWidget {
  const _FolderList();

  @override
  ConsumerState<_FolderList> createState() => _FolderListState();
}

class _FolderListState extends ConsumerState<_FolderList> {
  late Future<List<Map<String, Object?>>> _folders =
      AppDatabase.instance.getFolders();

  void _refresh() {
    setState(() {
      _folders = AppDatabase.instance.getFolders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _folders,
      builder: (context, snapshot) {
        final folders = snapshot.data ?? const <Map<String, Object?>>[];
        if (folders.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No folders added yet.',
              style: AppText.bodySecondary,
            ),
          );
        }
        return Column(
          children: [
            for (final folder in folders)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.rowDivider),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${folder['display_name']}',
                        style: AppText.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    LrIconButton(
                      icon: Icons.close,
                      semanticLabel:
                          'Remove folder ${folder['display_name']}',
                      onPressed: () async {
                        await AppDatabase.instance.removeFolder(
                          '${folder['tree_uri']}',
                        );
                        _refresh();
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
