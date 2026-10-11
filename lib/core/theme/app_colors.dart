import 'package:flutter/material.dart';

/// Lite Reader design tokens. Do not invent new colors — use these.
abstract final class AppColors {
  // Light
  static const Color background = Color(0xFFF4F5F3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF1A1C20);
  static const Color secondaryText = Color(0xFF5B5F68);
  static const Color tertiary = Color(0xFF70747D);
  static const Color hairline = Color(0xFFDCDDD8);
  static const Color rowDivider = Color(0xFFE3E4DF);
  static const Color accent = Color(0xFF2A4D8F);
  static const Color accentTint = Color(0xFFE6ECF7);

  // Reader desk (light)
  static const Color desk = Color(0xFFE6E7E3);
  // Soft grey page option
  static const Color softGreyPage = Color(0xFFE4E5E1);

  // Night
  static const Color nightBackground = Color(0xFF0D0F12);
  static const Color nightPage = Color(0xFF1B1E24);
  static const Color nightText = Color(0xFFD4D7DD);

  /// The five annotation highlight colors, in dock order.
  static const List<Color> highlightColors = [
    Color(0xFFFFD60A),
    Color(0xFF8FDDB0),
    Color(0xFF9DBDF2),
    Color(0xFFF2A9BE),
    Color(0xFFCDB6EE),
  ];

  /// Soft night inversion matrix for PDF pages: inverts without pure black.
  /// Maps white -> ~#1B1E24 and black -> ~#D4D7DD.
  static const List<double> nightInvertMatrix = [
    -0.725, 0, 0, 0, 211.9, //
    0, -0.725, 0, 0, 211.9, //
    0, 0, -0.725, 0, 211.9, //
    0, 0, 0, 1, 0, //
  ];
}
