import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models/annotation.dart';

/// Key for per-page annotation state.
typedef PageKey = ({int docId, int page});

/// Human label for a dock tool; null means select/move mode.
String annotateToolLabel(AnnotationType? tool) => switch (tool) {
      AnnotationType.highlight => 'Highlight',
      AnnotationType.underline => 'Underline',
      AnnotationType.strikethrough => 'Strikethrough',
      AnnotationType.pen => 'Pen',
      AnnotationType.text => 'Text',
      AnnotationType.signature => 'Signature',
      null => 'Select',
    };

/// Readout line under the dock, e.g. "Highlight Width 14 px · Opacity 55%".
String annotateStyleReadout(AnnotationType? tool, AnnotateStyleState style) {
  if (tool == null) return 'Select · tap an annotation to edit it';
  return '${annotateToolLabel(tool)} Width ${style.widthPx.round()} px · '
      'Opacity ${(style.opacity * 100).round()}%';
}

// ---------------------------------------------------------------------------
// Active tool (null = select/move mode)
// ---------------------------------------------------------------------------

final annotateToolProvider =
    NotifierProvider<AnnotateTool, AnnotationType?>(AnnotateTool.new);

class AnnotateTool extends Notifier<AnnotationType?> {
  @override
  AnnotationType? build() => null;

  void set(AnnotationType? tool) => state = tool;
}

// ---------------------------------------------------------------------------
// Style: color, width, opacity
// ---------------------------------------------------------------------------

class AnnotateStyleState {
  const AnnotateStyleState({
    required this.color,
    required this.widthPx,
    required this.opacity,
  });

  final Color color;
  final double widthPx;
  final double opacity;

  AnnotateStyleState copyWith({
    Color? color,
    double? widthPx,
    double? opacity,
  }) {
    return AnnotateStyleState(
      color: color ?? this.color,
      widthPx: widthPx ?? this.widthPx,
      opacity: opacity ?? this.opacity,
    );
  }
}

final annotateStyleProvider =
    NotifierProvider<AnnotateStyle, AnnotateStyleState>(AnnotateStyle.new);

class AnnotateStyle extends Notifier<AnnotateStyleState> {
  @override
  AnnotateStyleState build() => const AnnotateStyleState(
        color: Color(0xFFFFD60A),
        widthPx: 14,
        opacity: 0.55,
      );

  void setColor(Color color) => state = state.copyWith(color: color);

  void setWidth(double widthPx) =>
      state = state.copyWith(widthPx: widthPx.clamp(4.0, 40.0));

  void setOpacity(double opacity) =>
      state = state.copyWith(opacity: opacity.clamp(0.1, 1.0));
}

// ---------------------------------------------------------------------------
// Selected annotation id (null = none)
// ---------------------------------------------------------------------------

final selectedAnnotationProvider =
    NotifierProvider<SelectedAnnotation, int?>(SelectedAnnotation.new);

class SelectedAnnotation extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}

// ---------------------------------------------------------------------------
// Per-page annotations (SQLite-backed)
// ---------------------------------------------------------------------------

final pageAnnotationsProvider = AsyncNotifierProvider.family<
    PageAnnotations, List<PdfAnnotation>, PageKey>(
  (arg) => PageAnnotations(arg),
);

class PageAnnotations extends AsyncNotifier<List<PdfAnnotation>> {
  PageAnnotations(this._key);

  final PageKey _key;

  @override
  Future<List<PdfAnnotation>> build() =>
      AppDatabase.instance.getAnnotations(_key.docId, _key.page);

  /// Inserts into SQLite and appends to state. Returns the annotation with
  /// its database id.
  Future<PdfAnnotation> add(PdfAnnotation annotation) async {
    final id = await AppDatabase.instance.insertAnnotation(annotation);
    final withId = annotation.copyWith(id: id);
    final current = state.value ?? const <PdfAnnotation>[];
    state = AsyncData([...current, withId]);
    return withId;
  }

  /// Persists and replaces the annotation in state.
  Future<void> updateAnn(PdfAnnotation annotation) async {
    await AppDatabase.instance.updateAnnotation(annotation);
    updateLocal(annotation);
  }

  /// Replaces the annotation in state only (live gesture updates).
  void updateLocal(PdfAnnotation annotation) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final a in current)
        if (a.id == annotation.id) annotation else a,
    ]);
  }

  Future<void> removeAnn(int id) async {
    await AppDatabase.instance.deleteAnnotation(id);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.where((a) => a.id != id).toList());
  }
}

// ---------------------------------------------------------------------------
// Undo/redo controller (family by document id)
// ---------------------------------------------------------------------------

enum _OpKind { add, remove, update }

class _Op {
  const _Op({required this.kind, this.before, this.after});

  final _OpKind kind;
  final PdfAnnotation? before;
  final PdfAnnotation? after;
}

/// Undo/redo stacks per document. The exposed int state is a generation
/// counter bumped on every stack change so the UI rebuilds; [canUndo] and
/// [canRedo] are read alongside it. All database writes go through here.
final annotateControllerProvider =
    NotifierProvider.family<AnnotateController, int, int>(
  (docId) => AnnotateController(docId),
);

class AnnotateController extends Notifier<int> {
  AnnotateController(this._docId);

  final int _docId;
  final List<_Op> _undo = [];
  final List<_Op> _redo = [];

  @override
  int build() => 0;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _bump() => state++;

  PageAnnotations _page(int page) =>
      ref.read(pageAnnotationsProvider((docId: _docId, page: page)).notifier);

  Future<PdfAnnotation> pushAdd(PdfAnnotation annotation) async {
    final withId = await _page(annotation.page).add(annotation);
    _undo.add(_Op(kind: _OpKind.add, after: withId));
    _redo.clear();
    _bump();
    return withId;
  }

  Future<void> pushRemove(PdfAnnotation annotation) async {
    final id = annotation.id;
    if (id == null) return;
    await _page(annotation.page).removeAnn(id);
    _undo.add(_Op(kind: _OpKind.remove, before: annotation));
    _redo.clear();
    _bump();
  }

  Future<void> pushUpdate(PdfAnnotation before, PdfAnnotation after) async {
    await _page(after.page).updateAnn(after);
    _undo.add(_Op(kind: _OpKind.update, before: before, after: after));
    _redo.clear();
    _bump();
  }

  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final op = _undo.removeLast();
    switch (op.kind) {
      case _OpKind.add:
        final after = op.after!;
        await _page(after.page).removeAnn(after.id!);
        _redo.add(op);
      case _OpKind.remove:
        // Re-inserting assigns a new id; track it so redo removes the
        // right row.
        final before = op.before!;
        final readded = await _page(before.page).add(before.copyWith(id: null));
        _redo.add(_Op(kind: _OpKind.remove, before: readded));
      case _OpKind.update:
        final before = op.before!;
        await _page(before.page).updateAnn(before);
        _redo.add(op);
    }
    _bump();
  }

  Future<void> redo() async {
    if (_redo.isEmpty) return;
    final op = _redo.removeLast();
    switch (op.kind) {
      case _OpKind.add:
        final after = op.after!;
        final readded = await _page(after.page).add(after.copyWith(id: null));
        _undo.add(_Op(kind: _OpKind.add, after: readded));
      case _OpKind.remove:
        final before = op.before!;
        await _page(before.page).removeAnn(before.id!);
        _undo.add(op);
      case _OpKind.update:
        final after = op.after!;
        await _page(after.page).updateAnn(after);
        _undo.add(op);
    }
    _bump();
  }
}
