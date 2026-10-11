import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/app_database.dart';
import '../../core/models/document.dart';
import '../../core/platform/saf.dart';
import '../../core/services/doc_source.dart';
import '../../core/services/library_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/debouncer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/lr_icon_button.dart';
import '../../core/widgets/search_field.dart';
import '../../core/widgets/section_label.dart';
import 'providers.dart';
import 'widgets/doc_row.dart';
import 'widgets/library_tabs.dart';
import 'widgets/recent_card.dart';
import 'widgets/selection_bar.dart';

/// The Files tab: title, search, text tabs, recent cards, all files,
/// and a selection mode for share / merge / remove.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer();
  bool _initialRescanDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialRescan());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  /// One background rescan after the first frame; guarded against repeats.
  Future<void> _initialRescan() async {
    if (_initialRescanDone || !mounted) return;
    _initialRescanDone = true;
    await _refresh(showSnackBar: true);
  }

  Future<void> _refresh({required bool showSnackBar}) async {
    RescanResult result;
    try {
      result = await ref.read(libraryDocsProvider.notifier).refresh();
    } catch (_) {
      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not refresh the library.')),
        );
      }
      return;
    }
    if (mounted && showSnackBar && !result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final docsValue = ref.watch(libraryDocsProvider);
    final tab = ref.watch(libraryTabProvider);
    final sort = ref.watch(librarySortProvider);
    final query = ref.watch(libraryQueryProvider);
    final selection = ref.watch(selectionProvider);
    final selecting = selection.isNotEmpty;

    final allDocs = docsValue.value ?? const <LibraryDocument>[];
    final filtered = sortDocuments(filterDocuments(allDocs, tab, query), sort);
    final recent = filtered.where((d) => d.lastOpened > 0).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    final recentTop = recent.take(3).toList();

    final counts = <LibraryTab, int>{
      LibraryTab.all: allDocs.length,
      LibraryTab.pdf: allDocs.where((d) => d.isPdf).length,
      LibraryTab.office: allDocs.where((d) => !d.isPdf).length,
      LibraryTab.starred: allDocs.where((d) => d.starred).length,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar:
          selecting ? _buildSelectionBar(selection, allDocs) : _buildAppBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchField(
              controller: _searchController,
              hintText: 'Search documents',
              semanticLabel: 'Search documents',
              onChanged: (value) => _debouncer(
                () => ref.read(libraryQueryProvider.notifier).set(value),
              ),
            ),
          ),
          LibraryTabs(
            active: tab,
            counts: counts,
            onChanged: (t) => ref.read(libraryTabProvider.notifier).set(t),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _buildBody(docsValue, allDocs, filtered, recentTop),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: const Text('Documents', style: AppText.title),
      actions: [
        LrIconButton(
          icon: Icons.sort,
          semanticLabel: 'Sort',
          onPressed: _showSortSheet,
        ),
        LrIconButton(
          icon: Icons.create_new_folder_outlined,
          semanticLabel: 'Add folder',
          onPressed: () => ref.read(libraryDocsProvider.notifier).addFolder(),
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

  PreferredSizeWidget _buildSelectionBar(
    Set<int> selection,
    List<LibraryDocument> allDocs,
  ) {
    final pdfIds = <int>[];
    for (final doc in allDocs) {
      if (doc.id != null && selection.contains(doc.id) && doc.isPdf) {
        pdfIds.add(doc.id!);
      }
    }
    return SelectionBar(
      count: selection.length,
      onShare: _shareSelected,
      onMerge: pdfIds.length >= 2 ? _mergeSelected : null,
      onRemove: _confirmRemove,
      onClear: () => ref.read(selectionProvider.notifier).clear(),
    );
  }

  Widget _buildBody(
    AsyncValue<List<LibraryDocument>> docsValue,
    List<LibraryDocument> allDocs,
    List<LibraryDocument> filtered,
    List<LibraryDocument> recent,
  ) {
    if (docsValue.isLoading && allDocs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (docsValue.hasError && allDocs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Could not load the library.',
            style: AppText.bodySecondary,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (allDocs.isEmpty) {
      return EmptyState(
        message: 'No documents yet',
        buttonLabel: 'Add a folder',
        onButtonPressed: () =>
            ref.read(libraryDocsProvider.notifier).addFolder(),
      );
    }
    if (filtered.isEmpty) {
      return const Center(
        child: Text('No documents match.', style: AppText.bodySecondary),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _refresh(showSnackBar: true),
      child: CustomScrollView(
        slivers: [
          if (recent.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SectionLabel('Recent'),
              ),
            ),
            SliverToBoxAdapter(child: _recentRow(recent)),
          ],
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SectionLabel('All files'),
            ),
          ),
          SliverList.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final doc = filtered[index];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _docRow(doc),
                  if (index < filtered.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.rowDivider,
                      indent: 68,
                    ),
                ],
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _recentRow(List<LibraryDocument> recent) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final doc = recent[index];
          return Consumer(
            builder: (context, ref, _) {
              final progress = doc.id == null
                  ? 0.0
                  : ref.watch(docProgressProvider(doc.id!)).value ?? 0.0;
              return RecentCard(
                doc: doc,
                progress: progress,
                onTap: () => _onTapDoc(doc),
              );
            },
          );
        },
      ),
    );
  }

  Widget _docRow(LibraryDocument doc) {
    return Consumer(
      builder: (context, ref, _) {
        final selection = ref.watch(selectionProvider);
        final progress = doc.id == null
            ? 0.0
            : ref.watch(docProgressProvider(doc.id!)).value ?? 0.0;
        return DocRow(
          key: ValueKey(doc.id),
          doc: doc,
          progress: progress,
          selected: selection.contains(doc.id),
          onTap: () => _onTapDoc(doc),
          onLongPress: () => _onLongPressDoc(doc),
          onToggleStar: () {
            final id = doc.id;
            if (id != null) {
              ref.read(libraryDocsProvider.notifier).toggleStar(id);
            }
          },
        );
      },
    );
  }

  void _onLongPressDoc(LibraryDocument doc) {
    final id = doc.id;
    if (id == null) return;
    ref.read(selectionProvider.notifier).toggle(id);
  }

  Future<void> _onTapDoc(LibraryDocument doc) async {
    final id = doc.id;
    if (id == null) return;
    if (ref.read(selectionProvider).isNotEmpty) {
      ref.read(selectionProvider.notifier).toggle(id);
      return;
    }
    if (doc.isPdf) {
      await AppDatabase.instance.touchLastOpened(id);
      ref.invalidate(libraryDocsProvider);
      if (!mounted) return;
      context.go('/reader?documentId=$id');
    } else {
      final opened = await Saf.openWith(doc.uri, doc.mimeType);
      if (!mounted) return;
      if (opened) {
        await AppDatabase.instance.touchLastOpened(id);
        ref.invalidate(libraryDocsProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app found to open this file.')),
        );
      }
    }
  }

  Future<void> _shareSelected() async {
    final ids = ref.read(selectionProvider).toList();
    final allDocs =
        ref.read(libraryDocsProvider).value ?? const <LibraryDocument>[];
    final files = <XFile>[];
    for (final id in ids) {
      LibraryDocument? doc;
      for (final d in allDocs) {
        if (d.id == id) {
          doc = d;
          break;
        }
      }
      if (doc == null) continue;
      try {
        final path = await DocSource.resolvePath(doc);
        files.add(XFile(path, name: doc.displayName));
      } catch (_) {
        // Skip files that can no longer be read.
      }
    }
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not prepare files for sharing.')),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: files, text: 'Shared from Lite Reader'),
    );
    ref.read(selectionProvider.notifier).clear();
  }

  void _mergeSelected() {
    final selection = ref.read(selectionProvider);
    final allDocs =
        ref.read(libraryDocsProvider).value ?? const <LibraryDocument>[];
    final pdfIds = <int>[];
    for (final doc in allDocs) {
      if (doc.id != null && selection.contains(doc.id) && doc.isPdf) {
        pdfIds.add(doc.id!);
      }
    }
    if (pdfIds.length < 2) return;
    ref.read(selectionProvider.notifier).clear();
    context.push('/tools/merge', extra: pdfIds);
  }

  Future<void> _confirmRemove() async {
    final count = ref.read(selectionProvider).length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Remove ${count == 1 ? 'file' : 'files'}?',
          style: AppText.body.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove $count ${count == 1 ? 'file' : 'files'} from the library? '
          'The originals stay on your device.',
          style: AppText.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: AppText.body.copyWith(color: AppColors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Remove',
              style: AppText.body.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(libraryDocsProvider.notifier)
          .removeDocuments(ref.read(selectionProvider).toList());
    }
  }

  void _showSortSheet() {
    final current = ref.read(librarySortProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Sort by',
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            RadioGroup<LibrarySort>(
              groupValue: current,
              onChanged: (value) {
                if (value != null) {
                  ref.read(librarySortProvider.notifier).set(value);
                }
                Navigator.of(sheetContext).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in LibrarySort.values)
                    RadioListTile<LibrarySort>(
                      title: Text(_sortLabel(option), style: AppText.body),
                      value: option,
                      activeColor: AppColors.accent,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _sortLabel(LibrarySort sort) {
    switch (sort) {
      case LibrarySort.name:
        return 'Name';
      case LibrarySort.date:
        return 'Date';
      case LibrarySort.size:
        return 'Size';
    }
  }
}
