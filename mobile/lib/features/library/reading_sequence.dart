import '../../models.dart';

/// Chapter reading and filtered-result reading share navigation, not study events.
class ReadingSequence {
  final List<Question> questions;
  final bool byChapter;
  ReadingSequence(List<Question> source, {this.byChapter = false})
      : questions = byChapter ? _group(source) : List.of(source);

  static List<Question> _group(List<Question> source) {
    final groups = <String, List<Question>>{};
    for (final q in source) {
      groups.putIfAbsent('${q.subject}\u0000${q.chapter}', () => []).add(q);
    }
    return groups.values.expand((qs) => qs).toList();
  }

  bool sameChapter(Question a, Question b) =>
      a.subject == b.subject && a.chapter == b.chapter;
  bool endsChapter(int index) =>
      index + 1 == questions.length ||
      !sameChapter(questions[index], questions[index + 1]);
  int chapterCount(int index) =>
      questions.where((q) => sameChapter(q, questions[index])).length;
  int chapterPosition(int index) => questions
      .take(index + 1)
      .where((q) => sameChapter(q, questions[index]))
      .length;
  int startIndex({String? questionId, String? chapter}) {
    final found = questions.indexWhere((q) => questionId != null
        ? q.id == questionId
        : chapter != null && q.chapter == chapter);
    return found < 0 ? 0 : found;
  }
}
