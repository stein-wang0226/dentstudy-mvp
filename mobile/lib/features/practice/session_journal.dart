import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../store.dart';
import '../../models.dart';
import 'practice_request.dart';

/// Local session metadata is separate from the event sync contract.
class SessionJournal with WidgetsBindingObserver {
  final StudyStore store;
  final PracticeRequest request;
  late Map<String, dynamic> data;
  final Stopwatch clock = Stopwatch();
  Timer? ticker;
  bool completed = false;
  bool closed = false;
  Future<void>? _finishing;
  String? error;
  SessionJournal(this.store, this.request) {
    final previous = request.draft;
    data = previous == null
        ? {
            'id': '${DateTime.now().microsecondsSinceEpoch}',
            'questionIds': request.questions.map((q) => q.id).toList(),
            'kind': request.kind,
            'label': request.label,
            'practiceMode': request.mode,
            'review': request.review,
            'exam': request.exam,
            'index': 0,
            'answers': <String, String>{},
            'grades': <String, String>{},
            'saved': <String>[],
            'eventIds': <String>[],
            'elapsedSeconds': 0,
            'startedAt': DateTime.now().toUtc().toIso8601String(),
          }
        : Map<String, dynamic>.from(previous);
    store.activeSessionId = id;
  }
  String get id => data['id'] as String;
  int get milliseconds =>
      (data['elapsedMs'] as int? ??
          (data['elapsedSeconds'] as int? ?? 0) * 1000) +
      clock.elapsedMilliseconds;
  int get seconds => milliseconds ~/ 1000;
  List<Question> get questions => request.questions;
  Set<String> get saved => Set<String>.from(data['saved'] ?? []);
  Map<String, String> get answers =>
      Map<String, String>.from(data['answers'] ?? {});
  Future<void> open() async {
    await store.saveDraft({...data});
    clock.start();
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(
        const Duration(seconds: 5), (_) => unawaited(capture({})));
  }

  Future<void> capture(Map<String, dynamic> state) async {
    if (completed || closed) return;
    final persisted = store.drafts[id] ?? data;
    final elapsedNow = milliseconds;
    clock.reset();
    data = {
      ...data,
      ...state,
      'elapsedMs': elapsedNow,
      'elapsedSeconds': elapsedNow ~/ 1000,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'saved': <String>{
        ...List<String>.from(persisted['saved'] ?? []),
        ...List<String>.from(state['saved'] ?? data['saved'] ?? [])
      }.toList(),
      'eventIds': persisted['eventIds'] ?? [],
    };
    try {
      await store.saveDraft({...data});
      error = null;
    } catch (e) {
      error = '续练记录保存失败：$e';
    }
  }

  Future<void> finish() =>
      _finishing ??= _finish().whenComplete(() => _finishing = null);
  Future<void> _finish() async {
    if (completed) return;
    await capture({});
    if (error != null) throw Exception(error);
    clock.stop();
    ticker?.cancel();
    completed = true;
    try {
      await store.finishSession(id, {
        ...data,
        'finished': true,
        'finishedAt': DateTime.now().toUtc().toIso8601String()
      });
    } catch (_) {
      completed = false;
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!completed) clock.start();
    } else {
      unawaited(capture({}));
      clock.stop();
    }
  }

  Future<void> close() async {
    try {
      if (data['finished'] == true) await finish();
      await capture({});
    } finally {
      closed = true;
      ticker?.cancel();
      clock.stop();
      WidgetsBinding.instance.removeObserver(this);
      if (store.activeSessionId == id) store.activeSessionId = null;
    }
  }
}
