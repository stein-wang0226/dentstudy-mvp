import '../../models.dart';

/// Exam year is provenance, not the upload/publication year of a document.
class ExamYearCatalog {
  final List<Question> questions;
  ExamYearCatalog(Iterable<Question> all, String mode)
      : questions = {
          for (final q in all)
            if (q.modes.contains(mode) && isHistorical(q)) q.id: q
        }.values.toList();

  static bool isHistorical(Question q) =>
      q.data['isDemo'] == false &&
      const ['past_paper', 'recalled_paper'].contains(q.data['sourceType']);

  static Map getProvenance(Question q) => q.data['examProvenance'] is Map
      ? q.data['examProvenance'] as Map
      : const {};

  static int? verifiedYear(Question q) {
    final year = q.data['year'];
    if (!isHistorical(q) ||
        year is! int ||
        year < 1999 ||
        year > DateTime.now().year ||
        getProvenance(q)['yearVerified'] != true) return null;
    return year;
  }

  static bool verifiedPaper(Question q) =>
      q.data['sourceType'] == 'past_paper' &&
      verifiedYear(q) != null &&
      getProvenance(q)['sourceVerified'] == true &&
      (q.data['sourceUrl'] is String &&
          (q.data['sourceUrl'] as String).trim().isNotEmpty);

  static String? yearLabel(Question q) {
    if (!isHistorical(q)) return null;
    final year = verifiedYear(q);
    if (year == null) return '考试年份待核验';
    return '$year 年 · ${q.data['sourceType'] == 'recalled_paper' ? '回忆题' : verifiedPaper(q) ? '真题' : '试题来源待核验'}';
  }

  List<int> get years =>
      questions.map(verifiedYear).whereType<int>().toSet().toList()
        ..sort((a, b) => b.compareTo(a));

  int get pendingCount =>
      questions.where((q) => verifiedYear(q) == null).length;

  List<Question> forYear(int year) =>
      questions.where((q) => verifiedYear(q) == year).toList()
        ..sort((a, b) {
          final paper = (a.data['paperId'] as String? ?? '')
              .compareTo(b.data['paperId'] as String? ?? '');
          return paper != 0
              ? paper
              : (a.data['order'] as int? ?? 0)
                  .compareTo(b.data['order'] as int? ?? 0);
        });
}
