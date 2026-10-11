# Lite Reader ProGuard / R8 rules.
#
# NOTE: no INTERNET permission is declared anywhere in this app. Keep it that
# way — "works offline" is a headline feature.

# Flutter embedding.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.afzal.litereader.** { *; }

# pdfrx / PDFium are loaded through Dart FFI; R8 must not strip the plugin
# registrant or the FFI plugin glue.
-keep class com.espresso3389.** { *; }
-dontwarn com.espresso3389.**

# ML Kit (cunning_document_scanner) ships optional script modules that R8
# cannot see; silence the warnings instead of failing the build.
-dontwarn com.google.mlkit.**

# Play Core splitcompat/splitinstall classes are referenced by the Flutter
# embedding but never used (no deferred components); silence R8.
-dontwarn com.google.android.play.core.**

# share_plus / file_picker: keep the platform channel handlers reachable.
-keep class androidx.** { *; }
