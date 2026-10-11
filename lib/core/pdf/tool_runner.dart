import 'dart:async';
import 'dart:isolate';

import 'pdf_tool_workers.dart';

/// Progress update from a tool worker.
class ToolUpdate {
  const ToolUpdate._({this.progress, this.outputs, this.error});

  factory ToolUpdate.progress(double value) =>
      ToolUpdate._(progress: value.clamp(0.0, 1.0));

  factory ToolUpdate.done(List<String> outputs) =>
      ToolUpdate._(progress: 1.0, outputs: outputs);

  factory ToolUpdate.error(String message) => ToolUpdate._(error: message);

  final double? progress;
  final List<String>? outputs;
  final String? error;

  bool get isDone => outputs != null;
  bool get isError => error != null;
}

/// Runs [pdfToolWorker] in a background isolate so the UI never blocks.
/// Yields progress updates, then a final done/error update.
Stream<ToolUpdate> runPdfTool(Map<String, Object?> params) {
  final controller = StreamController<ToolUpdate>();
  final receivePort = ReceivePort();
  Isolate? isolate;
  receivePort.listen((message) {
    final map = Map<String, Object?>.from(message as Map);
    if (map.containsKey('progress')) {
      controller.add(
        ToolUpdate.progress((map['progress'] as num).toDouble()),
      );
    } else if (map.containsKey('done')) {
      controller.add(
        ToolUpdate.done((map['done'] as List).cast<String>()),
      );
      controller.close();
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    } else if (map.containsKey('error')) {
      controller.add(ToolUpdate.error(map['error'] as String));
      controller.close();
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  });
  Isolate.spawn(
    pdfToolWorker,
    {...params, 'port': receivePort.sendPort},
  ).then((value) => isolate = value);
  return controller.stream;
}
