import 'package:flutter/services.dart';

/// A file handed to Lite Reader via an "Open with" / share intent.
class IncomingFile {
  const IncomingFile({
    required this.uri,
    required this.mimeType,
    this.displayName,
  });

  final String uri;
  final String mimeType;
  final String? displayName;

  factory IncomingFile.fromMap(Map<Object?, Object?> map) => IncomingFile(
        uri: map['uri'] as String,
        mimeType: map['mimeType'] as String? ?? 'application/pdf',
        displayName: map['displayName'] as String?,
      );
}

/// Intent handling for ACTION_VIEW (content:// and file://) and ACTION_SEND.
/// Covers both cold start (getInitialFile) and warm start (onSharedFile).
class Intents {
  Intents._();

  static const MethodChannel _channel = MethodChannel('litereader/intent');
  static void Function(IncomingFile)? _onShared;

  static void listen(void Function(IncomingFile) onShared) {
    _onShared = onShared;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedFile' && _onShared != null) {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        _onShared!(IncomingFile.fromMap(args));
      }
    });
  }

  /// Returns the file from the launching intent, if any. Consumed once.
  static Future<IncomingFile?> getInitialFile() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getInitialFile',
    );
    if (map == null) return null;
    return IncomingFile.fromMap(map);
  }
}

/// Volume keys turn pages while the reader is active.
class VolumeKeys {
  VolumeKeys._();

  static const MethodChannel _channel = MethodChannel('litereader/volume');
  static void Function(String direction)? onVolumeKey;

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeKey') {
        onVolumeKey?.call(call.arguments as String);
      }
    });
  }

  /// Tells the native side whether volume keys should turn pages.
  static Future<void> setActive(bool active) =>
      _channel.invokeMethod('setActive', {'active': active});
}

/// Device-level helpers: keep screen awake, camera permission.
class Device {
  Device._();

  static const MethodChannel _channel = MethodChannel('litereader/device');

  static Future<void> setKeepAwake(bool keepAwake) =>
      _channel.invokeMethod('setKeepAwake', {'keepAwake': keepAwake});

  static Future<bool> isCameraGranted() async {
    final granted = await _channel.invokeMethod<bool>('isCameraGranted');
    return granted ?? false;
  }

  /// Shows the system camera permission prompt. Call only after showing
  /// the in-app explanation.
  static Future<bool> requestCamera() async {
    final granted = await _channel.invokeMethod<bool>('requestCamera');
    return granted ?? false;
  }
}
