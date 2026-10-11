import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/platform/device.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VolumeKeys.initialize();
  runApp(const ProviderScope(child: LiteReaderApp()));
}
