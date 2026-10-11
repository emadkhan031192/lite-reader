import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;
import 'package:share_plus/share_plus.dart';

import '../../core/db/app_database.dart';
import '../../core/models/annotation.dart';
import '../../core/models/document.dart';
import '../../core/pdf/pdf_facade.dart';
import '../../core/platform/device.dart';
import '../../core/services/doc_source.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/lr_icon_button.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/section_label.dart';
import '../annotate/annotation_painter.dart';
import '../outline/outline_sheet.dart';
import 'providers.dart';
import 'widgets/password_dialog.dart';
import 'widgets/ruler_scrubber.dart';
import 'widgets/search_panel.dart';

/// The core reading screen: full-bleed PDF on a desk, tap-to-toggle chrome,
/// edge tap zones, ruler scrubber, search, bookmarks and annotation overlays.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.documentId,
    required this.initialPage,
  });

  final int documentId;
  final int initialPage;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  static const double _kTopBarHeight = 56.0;
  static const double _kProgressHeight = 2.0;
  static const double _kBottomChromeHeight = 136.0;
  static const double _kEdgeZoneWidth = 56.0;
  static const double _kSearchPanelHeight = 68.0;

  LibraryDocument? _doc;
  String? _filePath;
  String? _password;
  int _pageCount = 0;
  int _currentPage = 1;
  bool _ready = false;
  String? _error;
  bool _chromeVisible = true;
  bool _searchOpen = false;
  int _annotationVersion = 0;

  final PdfViewerController _controller = PdfViewerController();
  PdfTextSearcher? _searcher;
  double? _fitZoom;
  double? _coverZoom;
  double? _restoredZoom;
  final Debouncer _progressDebouncer =
      Debouncer(delay: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    _controller.addListener(_onViewerMatrixChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onViewerMatrixChanged);
    VolumeKeys.onVolumeKey = null;
    unawaited(VolumeKeys.setActive(false));
    unawaited(Device.setKeepAwake(false));
    _saveProgress();
    _progressDebouncer.dispose();
    _searcher?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _saveProgress();
  }

  bool _isNight(SettingsState settings) =>
      settings.pageColor == PageColorMode.night ||
      (settings.followSystemTheme &&
          MediaQuery.platformBrightnessOf(context) == Brightness.dark);

  // ---------- setup ----------

  Future<void> _init() async {
    final db = AppDatabase.instance;
    final doc = await db.getDocumentById(widget.documentId);
    if (!mounted) return;
    if (doc == null) {
      setState(() => _error = 'This file is no longer in the library.');
      return;
    }

    late final String path;
    try {
      path = await DocSource.resolvePath(doc);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open this file.');
      return;
    }

    // Password loop: keep asking until the file opens or the user cancels.
    String? password = ref.read(docPasswordProvider(widget.documentId));
    late final int pageCount;
    while (true) {
      try {
        pageCount = await PdfFacade.pageCount(path, password: password);
        break;
      } on PdfPasswordException {
        if (!mounted) return;
        final entered = await showPasswordDialog(context);
        if (!mounted) return;
        if (entered == null || entered.isEmpty) {
          context.pop();
          return;
        }
        password = entered;
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = 'Could not read this PDF.');
        return;
      }
    }
    if (!mounted) return;
    ref.read(docPasswordProvider(widget.documentId).notifier).set(password);

    final settings = ref.read(settingsProvider);
    var startPage = widget.initialPage.clamp(1, pageCount);
    double? savedZoom;
    if (settings.rememberLastPage) {
      final progress = await db.getProgress(widget.documentId);
      if (!mounted) return;
      if (progress != null) {
        startPage = (progress['page'] as num).toInt().clamp(1, pageCount);
        savedZoom = (progress['zoom'] as num?)?.toDouble();
      }
    }
    unawaited(db.touchLastOpened(widget.documentId));
    if (doc.pageCount != pageCount) {
      unawaited(db.updatePageCount(widget.documentId, pageCount));
    }
    await Device.setKeepAwake(settings.keepScreenAwake);
    if (settings.volumeKeysTurnPages) {
      await VolumeKeys.setActive(true);
      VolumeKeys.onVolumeKey = _onVolumeKey;
    }
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _filePath = path;
      _password = password;
      _pageCount = pageCount;
      _currentPage = startPage;
      _restoredZoom = savedZoom;
      _ready = true;
    });
  }

  void _onVolumeKey(String direction) {
    if (!mounted || !_ready) return;
    if (direction == 'up') {
      _prevPage();
    } else {
      _nextPage();
    }
  }

  // ---------- viewer callbacks ----------

  void _onPageChanged(int? pageNumber) {
    if (!mounted || pageNumber == null) return;
    setState(() => _currentPage = pageNumber);
    _scheduleProgressSave();
  }

  void _onViewerMatrixChanged() {
    // Fires on scroll and zoom; the debouncer keeps writes cheap.
    _scheduleProgressSave();
  }

  void _paintSearchMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  List<Widget> _buildPageOverlays(
      BuildContext context, Rect pageRect, PdfPage page) {
    final pageNumber = page.pageNumber;
    final bookmarked = ref
        .read(bookmarkPagesProvider(widget.documentId))
        .contains(pageNumber);
    final overlays = <Widget>[];
    if (bookmarked) {
      overlays.add(
        Positioned(
          key: ValueKey('ribbon-$pageNumber'),
          left: pageRect.right - 26,
          top: pageRect.top - 2,
          child: const CustomPaint(
            size: Size(18, 30),
            painter: _BookmarkRibbonPainter(),
          ),
        ),
      );
    }
    overlays.add(
      Positioned.fromRect(
        key: ValueKey('ann-$pageNumber-v$_annotationVersion'),
        rect: pageRect,
        child: _PageAnnotationLayer(
          documentId: widget.documentId,
          pageNumber: pageNumber,
        ),
      ),
    );
    return overlays;
  }

  // ---------- navigation ----------

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _prevPage() {
    if (_controller.isReady && _currentPage > 1) {
      unawaited(_controller.goToPage(
        pageNumber: _currentPage - 1,
        anchor: PdfPageAnchor.top,
        duration: const Duration(milliseconds: 200),
      ));
    }
  }

  void _nextPage() {
    if (_controller.isReady && _currentPage < _pageCount) {
      unawaited(_controller.goToPage(
        pageNumber: _currentPage + 1,
        anchor: PdfPageAnchor.top,
        duration: const Duration(milliseconds: 200),
      ));
    }
  }

  void _onDoubleTap(Offset localPosition, double topInset) {
    if (!_controller.isReady) return;
    final viewerPosition = localPosition + Offset(0, topInset);
    if (_controller.currentZoom < 1.4) {
      unawaited(_controller.setZoom(viewerPosition, 2.5));
    } else if (_coverZoom != null) {
      unawaited(_controller.setZoom(viewerPosition, _coverZoom!));
    }
  }

  // ---------- progress ----------

  void _scheduleProgressSave() => _progressDebouncer.call(_saveProgress);

  void _saveProgress() {
    if (!_ready || _doc == null) return;
    final zoom = _controller.isReady
        ? _controller.currentZoom
        : (_restoredZoom ?? 1.0);
    unawaited(
      AppDatabase.instance.saveProgress(
        widget.documentId,
        _currentPage,
        zoom,
      ),
    );
  }

  // ---------- actions ----------

  Future<void> _toggleBookmark() async {
    await ref
        .read(bookmarkPagesProvider(widget.documentId).notifier)
        .toggle(_currentPage);
    if (_controller.isReady) _controller.invalidate();
  }

  void _toggleNight() {
    final settings = ref.read(settingsProvider);
    final night = _isNight(settings);
    unawaited(ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            pageColor:
                night ? PageColorMode.paper : PageColorMode.night,
            // Turning night off must win over "follow system".
            followSystemTheme: night ? false : s.followSystemTheme,
          ),
        ));
  }

  void _openAnnotate() {
    context
        .push(
            '/annotate?documentId=${widget.documentId}&page=$_currentPage')
        .then((_) {
      if (!mounted) return;
      // Annotations may have changed: rebuild the overlay layers.
      setState(() => _annotationVersion++);
      if (_controller.isReady) _controller.invalidate();
    });
  }

  void _openOutlineSheet() {
    final path = _filePath;
    if (path == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OutlineSheet(
        documentId: widget.documentId,
        filePath: path,
        password: _password,
        pageCount: _pageCount,
        currentPage: _currentPage,
        onGoToPage: (page) => _controller.goToPage(
          pageNumber: page,
          anchor: PdfPageAnchor.top,
        ),
      ),
    );
  }

  void _openDisplaySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DisplaySheet(
        fitZoom: _fitZoom,
        coverZoom: _coverZoom,
        onApplyZoom: (zoom) async {
          if (_controller.isReady) {
            await _controller.setZoom(
                _controller.centerPosition, zoom);
          }
        },
      ),
    );
  }

  void _onMoreSelected(String value) {
    switch (value) {
      case 'share':
        _shareFile();
      case 'details':
        _showFileDetails();
    }
  }

  Future<void> _shareFile() async {
    final path = _filePath;
    final doc = _doc;
    if (path == null || doc == null || !mounted) return;
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: doc.displayName),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share this file.')),
      );
    }
  }

  void _showFileDetails() {
    final doc = _doc;
    if (doc == null) return;
    final modified =
        DateTime.fromMillisecondsSinceEpoch(doc.modified);
    final pages = doc.pageCount > 0 ? doc.pageCount : _pageCount;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.hairline),
        ),
        title: const Text('File details', style: AppText.body),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.displayName, style: AppText.body),
            const SizedBox(height: 8),
            Text(
              '${formatBytes(doc.size)} · $pages pages · '
              '${formatShortDate(modified)}',
              style: AppText.monoSize(13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final bookmarks = ref.watch(bookmarkPagesProvider(widget.documentId));

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.desk,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: AppText.bodySecondary),
                  const SizedBox(height: 16),
                  LrIconButton(
                    icon: Icons.arrow_back,
                    semanticLabel: 'Back',
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_ready || _doc == null || _filePath == null) {
      return const Scaffold(
        backgroundColor: AppColors.desk,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    final night = _isNight(settings);
    final deskColor = night
        ? AppColors.nightBackground
        : settings.pageColor == PageColorMode.softGrey
            ? AppColors.softGreyPage
            : AppColors.desk;

    Widget viewerArea = PdfViewer.file(
      _filePath!,
      key: ValueKey('reader-${settings.pageFlow.name}'),
      passwordProvider: createSimplePasswordProvider(_password),
      firstAttemptByEmptyPassword: _password == null,
      controller: _controller,
      initialPageNumber: _currentPage,
      params: PdfViewerParams(
        backgroundColor: Colors.transparent,
        margin: 8,
        sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
          maxScale: 5.0,
          calculateInitialZoom:
              (document, controller, fitZoom, coverZoom) {
            _fitZoom = fitZoom;
            _coverZoom = coverZoom;
            final saved = _restoredZoom;
            if (saved != null && saved > 0) return saved;
            return switch (settings.defaultZoom) {
              DefaultZoom.fitWidth => coverZoom,
              DefaultZoom.fitPage => fitZoom,
              DefaultZoom.hundred => 1.0,
            };
          },
        ),
        pageOverlaysBuilder: _buildPageOverlays,
        pagePaintCallbacks: [_paintSearchMatches],
        onPageChanged: _onPageChanged,
        onViewerReady: (document, controller) {
          _searcher?.dispose();
          _searcher = PdfTextSearcher(_controller);
        },
        panEnabled: true,
        scaleEnabled: true,
        scrollPhysics: settings.pageFlow == PageFlow.single
            ? const NeverScrollableScrollPhysics()
            : null,
        matchTextColor: const Color(0xFFFFD60A),
        activeMatchTextColor: const Color(0xFF2A4D8F),
      ),
    );
    if (night) {
      viewerArea = ColorFiltered(
        colorFilter:
            const ColorFilter.matrix(AppColors.nightInvertMatrix),
        child: viewerArea,
      );
    }

    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final topInset = _chromeVisible
        ? safeTop +
            _kTopBarHeight +
            _kProgressHeight +
            (_searchOpen ? _kSearchPanelHeight : 0)
        : 0.0;
    final bottomInset =
        _chromeVisible ? safeBottom + _kBottomChromeHeight : 0.0;
    final edgeWidth =
        settings.tapEdgesToTurnPages ? _kEdgeZoneWidth : 0.0;

    return Scaffold(
      backgroundColor: deskColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: deskColor, child: viewerArea),
          ),
          // Center tap zone: toggles the chrome. Kept clear of the
          // edge zones so a tap never does two things at once.
          Positioned(
            left: edgeWidth,
            right: edgeWidth,
            top: topInset,
            bottom: bottomInset,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleChrome,
              onDoubleTapDown: (d) =>
                  _onDoubleTap(d.localPosition, topInset),
              child: const SizedBox.expand(),
            ),
          ),
          if (settings.tapEdgesToTurnPages) ...[
            Positioned(
              left: 0,
              top: topInset,
              bottom: bottomInset,
              width: _kEdgeZoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _prevPage,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              right: 0,
              top: topInset,
              bottom: bottomInset,
              width: _kEdgeZoneWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _nextPage,
                child: const SizedBox.expand(),
              ),
            ),
          ],
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopChrome(settings, night),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomChrome(settings, night, bookmarks),
          ),
        ],
      ),
    );
  }

  Widget _buildTopChrome(SettingsState settings, bool night) {
    final barColor = night ? AppColors.nightBackground : AppColors.surface;
    final iconColor = night ? AppColors.nightText : null;
    return SafeArea(
      bottom: false,
      child: AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !_chromeVisible,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _kProgressHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _pageCount <= 0
                        ? 0
                        : (_currentPage / _pageCount).clamp(0.0, 1.0),
                    child: const ColoredBox(color: AppColors.accent),
                  ),
                ),
              ),
              Container(
                height: _kTopBarHeight,
                color: barColor,
                child: Row(
                  children: [
                    LrIconButton(
                      icon: Icons.arrow_back,
                      semanticLabel: 'Back',
                      color: iconColor,
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        _doc!.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            night ? AppText.nightBody : AppText.body,
                      ),
                    ),
                    Text(
                      formatPageIndicator(_currentPage, _pageCount),
                      style: AppText.monoSize(13,
                          color: night
                              ? AppColors.nightText
                              : AppColors.secondaryText),
                    ),
                    const SizedBox(width: 4),
                    LrIconButton(
                      icon: Icons.search_outlined,
                      semanticLabel: 'Search in document',
                      color: iconColor,
                      onPressed: _searcher == null
                          ? null
                          : () => setState(() {
                                _searchOpen = true;
                                _chromeVisible = true;
                              }),
                    ),
                    Semantics(
                      label: 'More options',
                      button: true,
                      child: PopupMenuButton<String>(
                        tooltip: 'More options',
                        icon: Icon(
                          Icons.more_vert,
                          size: 22,
                          color: iconColor ?? AppColors.ink,
                        ),
                        onSelected: _onMoreSelected,
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'share',
                            child: Text('Share file'),
                          ),
                          PopupMenuItem(
                            value: 'details',
                            child: Text('File details'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_searchOpen && _searcher != null)
                SizedBox(
                  height: _kSearchPanelHeight,
                  child: ReaderSearchPanel(
                    searcher: _searcher!,
                    onClose: () =>
                        setState(() => _searchOpen = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomChrome(
      SettingsState settings, bool night, List<int> bookmarks) {
    final barColor = night ? AppColors.nightBackground : AppColors.surface;
    final bookmarked = bookmarks.contains(_currentPage);
    return SafeArea(
      top: false,
      child: AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !_chromeVisible,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 56,
                child: RulerScrubber(
                  pageCount: _pageCount,
                  currentPage: _currentPage,
                  onPageSelected: (page) => _controller.goToPage(
                    pageNumber: page,
                    anchor: PdfPageAnchor.top,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius:
                        const BorderRadius.all(Radius.circular(20)),
                    border: const Border.fromBorderSide(
                        BorderSide(color: AppColors.hairline)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _pillItem(
                        icon: Icons.list_outlined,
                        semantic: 'Table of contents',
                        night: night,
                        onPressed: _openOutlineSheet,
                      ),
                      _pillItem(
                        icon: bookmarked
                            ? Icons.bookmark
                            : Icons.bookmark_outlined,
                        semantic: 'Bookmark this page',
                        night: night,
                        selected: bookmarked,
                        onPressed: _toggleBookmark,
                      ),
                      _pillItem(
                        icon: Icons.text_fields_outlined,
                        semantic: 'Page color and zoom',
                        night: night,
                        onPressed: _openDisplaySheet,
                      ),
                      _pillItem(
                        icon: night
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        semantic: 'Night mode',
                        night: night,
                        selected: night,
                        onPressed: _toggleNight,
                      ),
                      _pillItem(
                        icon: Icons.edit_outlined,
                        semantic: 'Annotate',
                        night: night,
                        onPressed: _openAnnotate,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Icon-only pill button: 44px touch target, 22px icon.
  Widget _pillItem({
    required IconData icon,
    required String semantic,
    required bool night,
    bool selected = false,
    VoidCallback? onPressed,
  }) {
    final iconColor = selected
        ? AppColors.accent
        : (night ? AppColors.nightText : AppColors.ink);
    return Expanded(
      child: Semantics(
        button: true,
        label: semantic,
        child: PressScale(
          onTap: onPressed,
          child: SizedBox(
            height: 44,
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// Page color + zoom sheet behind the "Aa" toolbar button.
/// Both apply immediately.
class _DisplaySheet extends ConsumerWidget {
  const _DisplaySheet({
    required this.onApplyZoom,
    this.fitZoom,
    this.coverZoom,
  });

  final double? fitZoom;
  final double? coverZoom;
  final Future<void> Function(double zoom) onApplyZoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final night = settings.pageColor == PageColorMode.night;
    return Container(
      decoration: BoxDecoration(
        color: night ? AppColors.nightBackground : AppColors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Page color'),
              const SizedBox(height: 12),
              Row(
                children: [
                  _colorOption(
                    ref,
                    'Paper',
                    AppColors.surface,
                    PageColorMode.paper,
                    settings.pageColor,
                    night,
                  ),
                  const SizedBox(width: 12),
                  _colorOption(
                    ref,
                    'Soft grey',
                    AppColors.softGreyPage,
                    PageColorMode.softGrey,
                    settings.pageColor,
                    night,
                  ),
                  const SizedBox(width: 12),
                  _colorOption(
                    ref,
                    'Night',
                    AppColors.nightPage,
                    PageColorMode.night,
                    settings.pageColor,
                    night,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionLabel('Zoom'),
              const SizedBox(height: 4),
              _zoomRow(
                ref,
                'Fit width',
                DefaultZoom.fitWidth,
                coverZoom,
                settings,
              ),
              _zoomRow(
                ref,
                'Fit page',
                DefaultZoom.fitPage,
                fitZoom,
                settings,
              ),
              _zoomRow(
                ref,
                '100%',
                DefaultZoom.hundred,
                1.0,
                settings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorOption(
    WidgetRef ref,
    String label,
    Color preview,
    PageColorMode mode,
    PageColorMode selected,
    bool night,
  ) {
    final isSelected = mode == selected;
    return Expanded(
      child: PressScale(
        onTap: () => unawaited(ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(pageColor: mode))),
        child: Semantics(
          button: true,
          label: '$label page color',
          selected: isSelected,
          child: Column(
            children: [
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: preview,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.hairline,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppText.monoSize(11,
                    color: night
                        ? AppColors.nightText
                        : AppColors.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zoomRow(
    WidgetRef ref,
    String label,
    DefaultZoom mode,
    double? zoom,
    SettingsState settings,
  ) {
    final isSelected = settings.defaultZoom == mode;
    return PressScale(
      onTap: zoom == null
          ? null
          : () async {
              await onApplyZoom(zoom);
              await ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(defaultZoom: mode));
            },
      child: Semantics(
        button: true,
        label: '$label zoom',
        selected: isSelected,
        child: Container(
          height: 48,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.rowDivider),
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: AppText.body.copyWith(
                  color: zoom == null
                      ? AppColors.tertiary
                      : AppColors.ink,
                ),
              ),
              const Spacer(),
              if (isSelected)
                const Icon(
                  Icons.check,
                  size: 22,
                  color: AppColors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small indigo bookmark ribbon drawn in a page's top corner.
class _BookmarkRibbonPainter extends CustomPainter {
  const _BookmarkRibbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - 7)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Read-only annotation overlay for one page.
///
/// Loads the page's annotations once from SQLite and paints them with the
/// shared [AnnotationPainter] (normalized coordinates); signature images
/// are stacked as positioned [Image.file] widgets.
class _PageAnnotationLayer extends StatefulWidget {
  const _PageAnnotationLayer({
    required this.documentId,
    required this.pageNumber,
  });

  final int documentId;
  final int pageNumber;

  @override
  State<_PageAnnotationLayer> createState() => _PageAnnotationLayerState();
}

class _PageAnnotationLayerState extends State<_PageAnnotationLayer> {
  List<PdfAnnotation>? _annotations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppDatabase.instance
        .getAnnotations(widget.documentId, widget.pageNumber);
    if (!mounted) return;
    setState(() => _annotations = list);
  }

  @override
  Widget build(BuildContext context) {
    final annotations = _annotations;
    if (annotations == null || annotations.isEmpty) {
      return const SizedBox.shrink();
    }
    final shapes = annotations
        .where((a) =>
            a.type != AnnotationType.signature || a.imagePath == null)
        .toList();
    final signatures = annotations
        .where((a) =>
            a.type == AnnotationType.signature &&
            a.imagePath != null &&
            a.rect != null)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size =
            Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: AnnotationPainter(annotations: shapes),
              ),
            ),
            for (final s in signatures)
              Positioned(
                left: s.rect![0] * size.width,
                top: s.rect![1] * size.height,
                width: s.rect![2] * size.width,
                height: s.rect![3] * size.height,
                child: Image.file(
                  File(s.imagePath!),
                  fit: BoxFit.fill,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox.shrink(),
                ),
              ),
          ],
        );
      },
    );
  }
}
