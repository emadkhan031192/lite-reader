import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/section_label.dart';
import 'widgets/tool_tile.dart';

/// Tools hub. Everything runs on the phone; nothing is uploaded.
///
/// There is deliberately no Lock/password-protect tile: research confirmed
/// no permissively-licensed Dart library can write AES-encrypted PDFs, so
/// the tile is hidden by design rather than shipping something fake.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Everything runs on your phone. Nothing is uploaded.',
            style: AppText.bodySecondary,
          ),
          const SizedBox(height: 16),
          const SectionLabel('Organize'),
          ToolTile(
            icon: Icons.merge_type,
            title: 'Merge',
            subtitle: 'Combine PDFs into one',
            onTap: () => context.push('/tools/merge'),
          ),
          ToolTile(
            icon: Icons.call_split,
            title: 'Split',
            subtitle: 'At a page or by range',
            onTap: () => context.push('/tools/split'),
          ),
          ToolTile(
            icon: Icons.reorder,
            title: 'Reorder pages',
            subtitle: 'Drag to reorder',
            onTap: () => context.push('/tools/reorder'),
          ),
          ToolTile(
            icon: Icons.compress,
            title: 'Compress',
            subtitle: 'Smaller file, lower DPI',
            onTap: () => context.push('/tools/compress'),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Create'),
          ToolTile(
            icon: Icons.document_scanner,
            title: 'Scan to PDF',
            subtitle: 'Camera or gallery',
            onTap: () => context.push('/tools/scan'),
          ),
          ToolTile(
            icon: Icons.image_outlined,
            title: 'Images to PDF',
            subtitle: 'Pick, order, page size',
            onTap: () => context.push('/tools/images'),
          ),
          ToolTile(
            icon: Icons.draw,
            title: 'Sign',
            subtitle: 'Place your signature',
            onTap: () => context.push('/tools/sign'),
          ),
        ],
      ),
    );
  }
}
