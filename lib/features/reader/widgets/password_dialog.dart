import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/press_scale.dart';

/// Small password prompt for password-protected PDFs.
///
/// Returns the entered password, or null when the user cancels.
Future<String?> showPasswordDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.hairline),
        ),
        title: const Text('Password required', style: AppText.body),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This PDF is password protected.',
              style: AppText.small,
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'PDF password',
              textField: true,
              child: TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                style: AppText.body,
                decoration: const InputDecoration(
                  hintText: 'Password',
                  hintStyle: AppText.small,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (_) =>
                    Navigator.of(dialogContext).pop(controller.text),
              ),
            ),
          ],
        ),
        actions: [
          PressScale(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text('Cancel', style: AppText.bodySecondary),
            ),
          ),
          PressScale(
            onTap: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: const Text(
                'Unlock',
                style: TextStyle(
                  fontFamily: AppText.zenKaku,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
