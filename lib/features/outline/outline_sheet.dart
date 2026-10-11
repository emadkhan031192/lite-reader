import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pdf/pdf_facade.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/lr_icon_button.dart';
import '../reader/providers.dart';

/// Bottom sheet behind the reader's "Contents" button.
///
/// Three tabs — Contents (from the PDF outline), Bookmarks (with a count),
/// and Pages (a thumbnail grid) — plus a "Go to page" row at the bottom.
class OutlineSheet extends ConsumerStatefulWidget {
  const OutlineSheet({
    super.key,
    required this.documentId,
    required this.filePath,
    this.password,
    required this.pageCount,
    required this.currentPage,
    required this.onGoToPage,
  });

  final int documentId;
  final String filePath;
  final String? password;
  final int pageCount;
  final int currentPage;
  final Future<void> Function(int page) onGoToPage;

  @override
  ConsumerState<OutlineSheet> createState() => _OutlineSheetState();
}

class _OutlineSheetState extends ConsumerState<OutlineSheet> {
  final _thumbCache = <int, Uint8List>{};
  final _goController = TextEditingController();

  @override
  void dispose() {
    _goController.dispose();
    super.dispose();
  }

  Future<void> _go(int page) async {
    final target = page.clamp(1, widget.pageCount);
    final go = widget.onGoToPage;
    Navigator.of(context).pop();
    await go(target);
  }

  void _submitGo() {
    final page = int.tryParse(_goController.text.trim());
    if (page == null) return;
    _goController.clear();
    unawaited(_go(page));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final night = settings.pageColor == PageColorMode.night;
    final bookmarkCount =
        ref.watch(bookmarkPagesProvider(widget.documentId)).length;
    final bg = night ? AppColors.nightBackground : AppColors.surface;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
                TabBar(
                  labelColor: AppColors.accent,
                  unselectedLabelColor: AppColors.secondaryText,
                  indicatorColor: AppColors.accent,
                  indicatorWeight: 2,
                  labelStyle: AppText.body,
                  unselectedLabelStyle: AppText.body,
                  tabs: [
                    const Tab(text: 'Contents'),
                    Tab(text: 'Bookmarks ($bookmarkCount)'),
                    const Tab(text: 'Pages'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ContentsTab(
                        filePath: widget.filePath,
                        password: widget.password,
                        currentPage: widget.currentPage,
                        scrollController: scrollController,
                        night: night,
                        onGo: _go,
                      ),
                      _BookmarksTab(
                        documentId: widget.documentId,
                        scrollController: scrollController,
                        night: night,
                        onGo: _go,
                      ),
                      _PagesTab(
                        filePath: widget.filePath,
                        password: widget.password,
                        pageCount: widget.pageCount,
                        currentPage: widget.currentPage,
                        scrollController: scrollController,
                        cache: _thumbCache,
                        night: night,
                        onGo: _go,
                      ),
                    ],
                  ),
                ),
                _goToPageRow(night),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _goToPageRow(bool night) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 10, 8, 10 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 44,
            child: Semantics(
              label: 'Go to page',
              textField: true,
              child: TextField(
                controller: _goController,
                keyboardType: TextInputType.number,
                style: AppText.monoSize(
                  14,
                  color:
                      night ? AppColors.nightText : AppColors.ink,
                ),
                decoration: const InputDecoration(
                  hintText: 'Page',
                  hintStyle: AppText.small,
                  border: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: AppColors.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: AppColors.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: AppColors.accent),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10),
                ),
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _submitGo(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'of ${widget.pageCount}',
            style: AppText.monoSize(13),
          ),
          const Spacer(),
          TextButton(
            onPressed: _submitGo,
            child: const Text(
              'Go',
              style: TextStyle(
                fontFamily: AppText.zenKaku,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contents tab: the PDF outline with dotted leaders and mono page numbers.
/// The current section (last entry at or before the current page) is indigo
/// and bold. Sub-entries are indented by depth.
class _ContentsTab extends StatefulWidget {
  const _ContentsTab({
    required this.filePath,
    this.password,
    required this.currentPage,
    required this.scrollController,
    required this.night,
    required this.onGo,
  });

  final String filePath;
  final String? password;
  final int currentPage;
  final ScrollController scrollController;
  final bool night;
  final Future<void> Function(int page) onGo;

  @override
  State<_ContentsTab> createState() => _ContentsTabState();
}

class _ContentsTabState extends State<_ContentsTab> {
  late final Future<List<OutlineEntry>> _outline =
      PdfFacade.outline(widget.filePath, password: widget.password);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OutlineEntry>>(
      future: _outline,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child:
                CircularProgressIndicator(color: AppColors.accent),
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not load the outline.',
                style: AppText.bodySecondary,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final entries = snapshot.data ?? const <OutlineEntry>[];
        if (entries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This PDF has no outline — try the Pages tab.',
                style: AppText.bodySecondary,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        var currentIndex = -1;
        for (var i = 0; i < entries.length; i++) {
          if (entries[i].pageNumber <= widget.currentPage) {
            currentIndex = i;
          }
        }
        return ListView.builder(
          controller: widget.scrollController,
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final entry = entries[i];
            final isCurrent = i == currentIndex;
            final titleStyle = isCurrent
                ? AppText.body.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  )
                : (widget.night ? AppText.nightBody : AppText.body);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(widget.onGo(entry.pageNumber)),
              child: Container(
                padding: EdgeInsets.only(
                  left: 16 + entry.depth * 16.0,
                  right: 16,
                  top: 11,
                  bottom: 11,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: SizedBox(
                        height: 12,
                        child: CustomPaint(
                          painter: _DottedLeaderPainter(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.pageNumber}',
                      style: AppText.monoSize(13),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Row of 2px tertiary dots used as the leader between an outline title
/// and its page number.
class _DottedLeaderPainter extends CustomPainter {
  const _DottedLeaderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.tertiary
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    final y = size.height / 2;
    for (var x = 4.0; x < size.width - 2; x += 8) {
      canvas.drawCircle(Offset(x, y), 1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bookmarks tab: bookmarked pages with a remove button each.
class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab({
    required this.documentId,
    required this.scrollController,
    required this.night,
    required this.onGo,
  });

  final int documentId;
  final ScrollController scrollController;
  final bool night;
  final Future<void> Function(int page) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(bookmarkPagesProvider(documentId));
    if (pages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No bookmarks yet. Tap the bookmark button in the reader to add one.',
            style: AppText.bodySecondary,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: pages.length,
      itemBuilder: (context, i) {
        final page = pages[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(onGo(page)),
          child: Container(
            padding:
                const EdgeInsets.only(left: 16, right: 4, top: 6, bottom: 6),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.rowDivider),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Page $page',
                    style: AppText.monoSize(
                      14,
                      color: night ? AppColors.nightText : AppColors.ink,
                    ),
                  ),
                ),
                LrIconButton(
                  icon: Icons.bookmark_remove_outlined,
                  semanticLabel: 'Remove bookmark for page $page',
                  onPressed: () => unawaited(ref
                      .read(bookmarkPagesProvider(documentId).notifier)
                      .toggle(page)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pages tab: a 3-column thumbnail grid. Thumbnails render on demand at
/// 160px wide and are cached in memory for the life of the sheet.
class _PagesTab extends StatelessWidget {
  const _PagesTab({
    required this.filePath,
    this.password,
    required this.pageCount,
    required this.currentPage,
    required this.scrollController,
    required this.cache,
    required this.night,
    required this.onGo,
  });

  final String filePath;
  final String? password;
  final int pageCount;
  final int currentPage;
  final ScrollController scrollController;
  final Map<int, Uint8List> cache;
  final bool night;
  final Future<void> Function(int page) onGo;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: pageCount,
      itemBuilder: (context, i) {
        final page = i + 1;
        return _PageThumb(
          page: page,
          filePath: filePath,
          password: password,
          isCurrent: page == currentPage,
          cache: cache,
          night: night,
          onTap: () => unawaited(onGo(page)),
        );
      },
    );
  }
}

class _PageThumb extends StatefulWidget {
  const _PageThumb({
    required this.page,
    required this.filePath,
    this.password,
    required this.isCurrent,
    required this.cache,
    required this.night,
    required this.onTap,
  });

  final int page;
  final String filePath;
  final String? password;
  final bool isCurrent;
  final Map<int, Uint8List> cache;
  final bool night;
  final VoidCallback onTap;

  @override
  State<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<_PageThumb> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.cache[widget.page];
    if (_bytes == null) _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await PdfFacade.renderPagePng(
        widget.filePath,
        widget.page,
        widthPx: 160,
        password: widget.password,
      );
      if (!mounted) return;
      widget.cache[widget.page] = bytes;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Semantics(
        button: true,
        label: 'Go to page ${widget.page}',
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                  border: Border.all(
                    color: widget.isCurrent
                        ? AppColors.accent
                        : AppColors.hairline,
                    width: widget.isCurrent ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _bytes != null
                    ? Image.memory(
                        _bytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : _failed
                        ? const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 22,
                              color: AppColors.tertiary,
                            ),
                          )
                        : const ColoredBox(
                            color: AppColors.rowDivider,
                          ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.page}',
              style: AppText.monoSize(
                11,
                color: widget.isCurrent
                    ? AppColors.accent
                    : (widget.night
                        ? AppColors.nightText
                        : AppColors.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
