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
  int due(List<Question> scope) => learning.due(scope, now).length;
  String lastDay(List<Question> scope) {
    final days = scope
        .map((q) => learning.states[q.id]?.lastDay)
        .whereType<String>()
        .toList()
      ..sort();
    return days.isEmpty ? '尚未学习' : days.last;
  }

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
