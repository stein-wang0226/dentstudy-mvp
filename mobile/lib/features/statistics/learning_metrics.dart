import '../../models.dart';

class LearningMetrics {
  final LearningState learning;
  final List<Question> questions;
  final DateTime now;
  LearningMetrics(this.learning, this.questions, {DateTime? now})
      : now = now ?? DateTime.now();
  List<Map<String, dynamic>> attemptsFor(List<Question> scope) {
    final ids = scope.map((q) => q.id).toSet();
    return learning.attempts
        .where((a) => ids.contains(a['questionId']))
        .toList();
  }

  double? accuracy(List<Question> scope) {
    final a = attemptsFor(scope).where((a) => a['correct'] != null).toList();
    return a.isEmpty
        ? null
        : a.where((a) => a['correct'] == true).length / a.length;
  }

  static String percent(double? value) =>
      value == null ? '暂无作答' : '${(value * 100).round()}%';
  int learned(List<Question> scope) =>
      scope.where((q) => learning.states[q.id]?.lastDay != null).length;
  int wrong(List<Question> scope) =>
      scope.where((q) => learning.states[q.id]?.wrong == true).length;

  /// The event log is the source of truth.  These helpers deliberately only
  /// derive a view of it, so the existing review schedule and sync payload do
  /// not need a new field just to support a more useful mistake notebook.
  int wrongAttempts(Question question) => learning.attempts
      .where((a) =>
          a['questionId'] == question.id &&
          (a['correct'] == false || a['grade'] == 'wrong'))
      .length;

  String? latestGrade(Question question) {
    final attempts = learning.attempts
        .where((a) => a['questionId'] == question.id)
        .toList()
      ..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
    return attempts.isEmpty ? null : attempts.last['grade'] as String?;
  }

  /// A wrong-question mark is intentionally not removed automatically: it is
  /// the learner's record.  A later "mastered" grade lets the UI offer a
  /// reversible archive action without touching that history.
  bool isRecoveredMistake(Question question) =>
      learning.states[question.id]?.wrong == true &&
      latestGrade(question) == 'mastered';

  bool isWrongToday(Question question) {
    final state = learning.states[question.id];
    if (state?.wrong != true || state?.lastDay != dayOf(now)) return false;
    final attempts = learning.attempts
        .where((a) => a['questionId'] == question.id)
        .toList()
      ..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
    final latest = attempts.isEmpty ? null : attempts.last;
    return latest?['correct'] == false || latest?['grade'] == 'wrong';
  }

  bool isRepeatedMistake(Question question) => wrongAttempts(question) >= 2;

  List<Question> activeMistakes(List<Question> scope) {
    final result = scope
        .where((q) =>
            learning.states[q.id]?.wrong == true && !isRecoveredMistake(q))
        .toList();
    result.sort((a, b) {
      final tierA = isWrongToday(a)
          ? 0
          : isRepeatedMistake(a)
              ? 1
              : 2;
      final tierB = isWrongToday(b)
          ? 0
          : isRepeatedMistake(b)
              ? 1
              : 2;
      if (tierA != tierB) return tierA.compareTo(tierB);
      return (learning.states[b.id]?.lastDay ?? '')
          .compareTo(learning.states[a.id]?.lastDay ?? '');
    });
    return result;
  }

  int unresolvedWrong(List<Question> scope) => activeMistakes(scope).length;

  int due(List<Question> scope) => learning.due(scope, now).length;
  String lastDay(List<Question> scope) {
    final days = scope
        .map((q) => learning.states[q.id]?.lastDay)
        .whereType<String>()
        .toList()
      ..sort();
    return days.isEmpty ? '尚未学习' : days.last;
  }

  /// A conservative status: a chapter cannot look "stable" after only a few
  /// lucky answers, and an unresolved wrong answer always takes precedence.
  String masteryLabel(List<Question> scope) {
    final learnedCount = learned(scope);
    if (learnedCount == 0) return '尚未开始';
    final rate = accuracy(scope);
    if (unresolvedWrong(scope) > 0 || (rate != null && rate < .7)) {
      return '需巩固';
    }
    if (learnedCount < (scope.length * .7).ceil() ||
        (rate != null && rate < .8)) return '学习中';
    if (due(scope) > 0) return '待复习';
    return '较稳定';
  }

  String masteryDetail(List<Question> scope) =>
      '${masteryLabel(scope)} · 已学 ${learned(scope)} / ${scope.length} · 正确率 ${percent(accuracy(scope))}';

  int get streak {
    final days =
        learning.attempts.map((a) => dayOf(DateTime.parse(a['at']))).toSet();
    var date = DateTime.parse(dayOf(now));
    if (!days.contains(dayOf(now)))
      date = date.subtract(const Duration(days: 1));
    var count = 0;
    while (days.contains(date.toIso8601String().substring(0, 10))) {
      count++;
      date = date.subtract(const Duration(days: 1));
    }
    return count;
  }

  List<List<Question>> get weakChapters {
    final groups = <String, List<Question>>{};
    for (final q in questions) {
      groups.putIfAbsent('${q.subject}\u0000${q.chapter}', () => []).add(q);
    }
    return groups.values
        .where((qs) => accuracy(qs) != null && accuracy(qs)! < .8)
        .toList()
      ..sort((a, b) => accuracy(a)!.compareTo(accuracy(b)!));
  }
}
