import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Lite Reader type scale. Quiet and precise: thin hairlines, small exact type.
abstract final class AppText {
  static const String zenKaku = 'ZenKaku';
  static const String dmMono = 'DMMono';

  static const TextStyle title = TextStyle(
    fontFamily: zenKaku,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.2,
    letterSpacing: -0.01,
  );

  static const TextStyle body = TextStyle(
    fontFamily: zenKaku,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
    height: 1.45,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: zenKaku,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.secondaryText,
    height: 1.45,
  );

  static const TextStyle small = TextStyle(
    fontFamily: zenKaku,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.secondaryText,
    height: 1.4,
  );

  /// Section labels: 11px, uppercase, 0.14em tracking, tertiary.
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: zenKaku,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.tertiary,
    letterSpacing: 0.14 * 11,
    height: 1.3,
  );

  /// All numbers (page counts, sizes, dates) use DM Mono with tabular figures.
  static const TextStyle mono = TextStyle(
    fontFamily: dmMono,
    fontWeight: FontWeight.w400,
    color: AppColors.secondaryText,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle monoSize(double size, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: dmMono,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? AppColors.secondaryText,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static const TextStyle nightTitle = TextStyle(
    fontFamily: zenKaku,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.nightText,
    height: 1.2,
    letterSpacing: -0.01,
  );

  static const TextStyle nightBody = TextStyle(
    fontFamily: zenKaku,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.nightText,
    height: 1.45,
  );
}
