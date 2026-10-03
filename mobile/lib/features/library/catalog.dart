import '../../models.dart';

/// A catalogue is a view of the loaded bank, never another copy of its content.
class QuestionCatalog {
  static const minimumQuestions = 50;
  final List<Question> all;
  final String mode;
  late final List<Question> _inMode =
      all.where((q) => q.modes.contains(mode)).toList();
  late final Map<String, List<Question>> _materials = _groupMaterials();
  Map<String, List<Question>> _groupMaterials() {
    final groups = <String, List<Question>>{};
    for (final q in _inMode) {
      if (q.data['isDemo'] == false)
        groups.putIfAbsent(q.subject, () => []).add(q);
    }
    return groups;
  }

  QuestionCatalog(List<Question> questions, this.mode)
      : all = {for (final q in questions) q.id: q}.values.toList();
  List<Question> get inMode => _inMode;
  List<String> get subjects => {
        ...all.map((q) => q.subject),
      }.toList();
  List<Question> material(String subject) => _materials[subject] ?? [];
  bool available(String subject) =>
      material(subject).length >= minimumQuestions;
  List<Question> get learnable => inMode
      .where((q) => q.data['isDemo'] == false && available(q.subject))
      .toList();
  String get countLabel => '本机 ${all.length} 题 · $mode可练 ${learnable.length} 题';
  static String sourceLabel(Question q) {
    if (q.data['isDemo'] == true) return '演示题';
    if (q.data['sourceType'] == 'past_paper')
      return q.data['citation']?['verified'] == true ? '真题' : '真题来源待核验';
    if (q.data['sourceType'] == 'user_material') return '资料整理题';
    return '来源待核验';
  }

  static String statusSummary(List<Question> questions) =>
      '${questions.map(sourceLabel).toSet().join(' / ')} · ${questions.map(reviewLabel).toSet().join(' / ')}';

  static String reviewLabel(Question q) =>
      q.data['reviewStatus'] == 'approved' &&
              q.data['citation']?['verified'] == true &&
              q.data['reviewer'] != null &&
              q.data['reviewedAt'] != null
          ? '已审核'
          : '待审核';
}
