import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Quiet search field used on the Files tab and in the reader.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.autofocus = false,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: semanticLabel ?? hintText,
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          style: AppText.body,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppText.bodySecondary,
            prefixIcon: const Icon(
              Icons.search,
              size: 22,
              color: AppColors.tertiary,
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
