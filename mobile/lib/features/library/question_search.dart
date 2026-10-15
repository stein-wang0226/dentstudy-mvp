import '../../models.dart';

/// Built once per bank snapshot. Query changes do not rebuild the text index.
class QuestionSearchIndex {
  final List<_SearchEntry> _entries;
  QuestionSearchIndex(List<Question> questions)
      : _entries = questions.map(_SearchEntry.new).toList();

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll('𬌗', '咬合')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  static List<String> terms(String query) =>
      normalize(query).split(' ').where((s) => s.isNotEmpty).toList();

  List<Question> search(String query, {String? subject, String? chapter}) {
    final tokens = terms(query);
    if (tokens.isEmpty) return [];
    final results = <({Question question, int score, int order})>[];
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final q = entry.question;
      if ((subject != null && q.subject != subject) ||
          (chapter != null && q.chapter != chapter) ||
          !tokens.every(entry.text.contains)) continue;
      final score = tokens.fold<int>(
          0,
          (sum, token) =>
              sum +
              (entry.stem.contains(token) ? 3 : 0) +
              (entry.context.contains(token) ? 1 : 0));
      results.add((question: q, score: score, order: i));
    }
    results.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score == 0 ? a.order.compareTo(b.order) : score;
    });
    return results.map((r) => r.question).toList();
  }
}

class _SearchEntry {
  final Question question;
  late final String stem =
      QuestionSearchIndex.normalize('${question.sharedStem} ${question.stem}');
  late final String context = QuestionSearchIndex.normalize(
      '${question.subject} ${question.chapter} ${question.tags.join(' ')} '
      '${question.data['topics'] ?? ''} ${question.id} '
      '${question.data['year'] ?? ''} ${question.data['paperName'] ?? ''}');
  late final String text =
      '$stem $context ${QuestionSearchIndex.normalize('${question.options.values.join(' ')} ${question.explanation}')}';
  _SearchEntry(this.question);
}
