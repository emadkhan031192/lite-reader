import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../features/annotate/annotate_screen.dart';
import '../features/library/library_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tools/compress_screen.dart';
import '../features/tools/images_to_pdf_screen.dart';
import '../features/tools/merge_screen.dart';
import '../features/tools/reorder_screen.dart';
import '../features/tools/scan_screen.dart';
import '../features/tools/sign_screen.dart';
import '../features/tools/split_screen.dart';
import '../features/tools/tools_screen.dart';

/// Bottom navigation shell: Files, Tools, Settings.
class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.hairline, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: navigationShell.currentIndex,
          onTap: _go,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder),
              label: 'Files',
              tooltip: 'Files',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.build_outlined),
              activeIcon: Icon(Icons.build),
              label: 'Tools',
              tooltip: 'Tools',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
              tooltip: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/files',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _ShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/files',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tools',
                builder: (context, state) => const ToolsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) {
          final documentId =
              int.tryParse(state.uri.queryParameters['documentId'] ?? '') ?? 0;
          final page =
              int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 1;
          return ReaderScreen(documentId: documentId, initialPage: page);
        },
      ),
      GoRoute(
        path: '/annotate',
        builder: (context, state) {
          final documentId =
              int.tryParse(state.uri.queryParameters['documentId'] ?? '') ?? 0;
          final page =
              int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 1;
          return AnnotateScreen(documentId: documentId, initialPage: page);
        },
      ),
      GoRoute(
        path: '/tools/merge',
        builder: (context, state) => MergeScreen(
          initialDocumentIds:
              (state.extra as List?)?.map((e) => (e as num).toInt()).toList() ??
                  const [],
        ),
      ),
      GoRoute(
        path: '/tools/split',
        builder: (context, state) => SplitScreen(
          documentId:
              int.tryParse(state.uri.queryParameters['documentId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/tools/reorder',
        builder: (context, state) => ReorderScreen(
          documentId:
              int.tryParse(state.uri.queryParameters['documentId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/tools/compress',
        builder: (context, state) => CompressScreen(
          documentId:
              int.tryParse(state.uri.queryParameters['documentId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/tools/images',
        builder: (context, state) => ImagesToPdfScreen(
          initialImages:
              (state.extra as List?)?.whereType<String>().toList() ?? const [],
        ),
      ),
      GoRoute(
        path: '/tools/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/tools/sign',
        builder: (context, state) => SignScreen(
          documentId:
              int.tryParse(state.uri.queryParameters['documentId'] ?? '') ?? 0,
        ),
      ),
    ],
  );
});
