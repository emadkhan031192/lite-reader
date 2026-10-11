import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/intent_service.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

/// Lite Reader root widget.
class LiteReaderApp extends ConsumerStatefulWidget {
  const LiteReaderApp({super.key});

  @override
  ConsumerState<LiteReaderApp> createState() => _LiteReaderAppState();
}

class _LiteReaderAppState extends ConsumerState<LiteReaderApp> {
  @override
  void initState() {
    super.initState();
    // Handle "Open with" / share intents after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      IntentService.instance.attach(
        onOpenDocument: (documentId) {
          ref.read(routerProvider).go('/reader?documentId=$documentId');
        },
        onError: (message) {
          final context = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Lite Reader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
