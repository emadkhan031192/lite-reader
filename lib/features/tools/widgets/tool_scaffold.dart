import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/press_scale.dart';

/// Shared scaffold for tool screens: AppBar with back + title and a
/// scrolling list with 16px padding.
class ToolScaffold extends StatelessWidget {
  const ToolScaffold({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        actions: action == null ? null : [action!],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}

/// Honest note shown under rasterizing tools: pages are re-rendered as
/// images, so text won't be selectable in the copy.
class RasterNote extends StatelessWidget {
  const RasterNote({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      "Pages are re-rendered as images, so text won't be selectable in the copy.",
      style: TextStyle(
        fontFamily: AppText.zenKaku,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.tertiary,
        height: 1.4,
      ),
    );
  }
}

/// Full-width primary action button for tool screens.
class RunButton extends StatelessWidget {
  const RunButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return Semantics(
      button: true,
      label: label,
      enabled: active,
      child: PressScale(
        onTap: active ? onPressed : null,
        child: Opacity(
          opacity: active ? 1.0 : 0.4,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppText.zenKaku,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
