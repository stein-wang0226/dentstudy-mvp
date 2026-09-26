const intervals = [1, 2, 4, 7, 14];
const subjects = [
  '口腔解剖生理学',
  '口腔组织病理学',
  '牙体牙髓病学',
  '牙周病学',
  '口腔黏膜病学',
  '口腔颌面外科学',
  '口腔修复学',
  '口腔正畸学'
];
String dayOf(DateTime time) => time
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);

class Question {
  final Map<String, dynamic> data;
  Question(this.data);
  String get id => data['id'];
  String get stem => data['stem'];
  String get subject => data['subject'];
  String get chapter => data['chapter'];
  String get type => data['type'];
  String? get answer => data['answer'];
  String get explanation => data['explanation'];
  String get reference => data['reference'];
  String get warning => data['warning'];
  String get sharedStem => data['sharedStem'] ?? '';
  String? get groupId => data['groupId'];
  List<String> get tags => List<String>.from(data['tags']);
  List<String> get modes => List<String>.from(data['modes']);
  Map<String, String> get options => Map<String, String>.from(data['options']);
}

class Progress {
  int stage = -1;
  String? due, lastDay, grade;
  bool wrong = false, favorite = false;
  String note = '';
}

class LearningState {
  final Map<String, Progress> states = {};
  final List<Map<String, dynamic>> attempts = [];
  LearningState(List<Map<String, dynamic>> events, List<Question> bank) {
    final questions = {for (final q in bank) q.id: q};
    final sorted = [...events]..sort((a, b) {
        final c = DateTime.parse(a['at']).compareTo(DateTime.parse(b['at']));
        return c == 0 ? (a['id'] as String).compareTo(b['id']) : c;
      });
    for (final e in sorted) {
      final q = questions[e['questionId']];
      if (q == null) continue;
      final s = states.putIfAbsent(q.id, Progress.new);
      final v = e['value'];
      switch (e['kind']) {
        case 'favorite':
          s.favorite = v as bool;
          break;
        case 'note':
          s.note = v as String;
          break;
        case 'removeWrong':
          s.wrong = false;
          break;
        case 'review':
          final bool? correct =
              q.answer == null ? null : v['answer'] == q.answer;
          final String grade = correct == false ? 'wrong' : v['grade'];
          final day = dayOf(DateTime.parse(e['at']));
          if (grade == 'wrong') {
            s.stage = 0;
            s.wrong = true;
          } else if (grade == 'guessed') {
            s.stage = (s.stage - 1).clamp(0, 4).toInt();
          } else if (s.lastDay != day &&
              (s.due == null || day.compareTo(s.due!) >= 0)) {
            s.stage = (s.stage + 1).clamp(0, 4).toInt();
          }
          s.stage = s.stage.clamp(0, 4).toInt();
          final next = DateTime.parse('${day}T00:00:00Z')
              .add(Duration(days: intervals[s.stage]))
              .toIso8601String()
              .substring(0, 10);
          if ((grade != 'mastered' || s.lastDay != day) &&
              (grade != 'mastered' ||
                  s.due == null ||
                  s.due!.compareTo(day) <= 0)) {
            s.due = next;
          }
          s.due ??= next;
          s.lastDay = day;
          s.grade = grade;
          attempts.add({
            'id': e['id'],
            'questionId': q.id,
            'at': e['at'],
            'correct': correct,
            'grade': grade,
            'mode': v['mode'] ?? 'practice'
          });
          break;
      }
    }
  }
  List<Question> due(List<Question> bank, DateTime now) {
    final day = dayOf(now);
    return bank
        .where((q) =>
            states[q.id]?.due != null && states[q.id]!.due!.compareTo(day) <= 0)
        .toList()
      ..sort((a, b) {
        final sa = states[a.id]!, sb = states[b.id]!;
        final c = (sa.grade == 'wrong' ? 0 : 1)
            .compareTo(sb.grade == 'wrong' ? 0 : 1);
        return c != 0 ? c : sa.due!.compareTo(sb.due!);
      });
  }
}
