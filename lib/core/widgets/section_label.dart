import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 11px uppercase label with 0.14em tracking, tertiary color,
/// followed by a 1px hairline.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text.toUpperCase(), style: AppText.sectionLabel),
        ),
        const SizedBox(
          height: 1,
          child: ColoredBox(color: AppColors.hairline),
        ),
      ],
    );
  }
}
