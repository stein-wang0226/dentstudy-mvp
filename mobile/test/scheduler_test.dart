import 'package:flutter_test/flutter_test.dart';
import 'package:dentstudy/models.dart';

void main() {
  final bank = [
    Question({'id': 'q1', 'answer': 'A'})
  ];
  Map<String, dynamic> event(int id, String day,
          {String grade = 'mastered', String answer = 'A'}) =>
      {
        'id': 'event-${id.toString().padLeft(20, '0')}',
        'questionId': 'q1',
        'at': '${day}T04:00:00Z',
        'kind': 'review',
        'value': {'answer': answer, 'grade': grade}
      };
  test('1, 2, 4, 7, 14 day staircase and cap', () {
    final days = [
      '2026-01-01',
      '2026-01-02',
      '2026-01-04',
      '2026-01-08',
      '2026-01-15',
      '2026-01-29'
    ];
    final due = [
      '2026-01-02',
      '2026-01-04',
      '2026-01-08',
      '2026-01-15',
      '2026-01-29',
      '2026-02-12'
    ];
    for (var i = 0; i < days.length; i++) {
      final state =
          LearningState(List.generate(i + 1, (j) => event(j, days[j])), bank);
      expect(state.states['q1']!.due, due[i]);
    }
  });
  test('same-day mastery never skips stages', () {
    final state =
        LearningState(List.generate(6, (i) => event(i, '2026-01-01')), bank);
    expect(state.states['q1']!.stage, 0);
    expect(state.states['q1']!.due, '2026-01-02');
  });
  test('actual incorrect answer overrides self-report', () {
    final state = LearningState([event(1, '2026-01-01', answer: 'B')], bank);
    expect(state.states['q1']!.grade, 'wrong');
    expect(state.states['q1']!.wrong, true);
  });
  test('early repetition does not postpone due day', () {
    final state = LearningState([
      event(1, '2026-01-01'),
      event(2, '2026-01-02'),
      event(3, '2026-01-03')
    ], bank);
    expect(state.states['q1']!.due, '2026-01-04');
  });
  test('business day uses UTC+8', () {
    expect(dayOf(DateTime.parse('2026-01-01T16:00:00Z')), '2026-01-02');
  });
  test('batch events still use the unchanged staircase reducer', () {
    final events = [
      event(1, '2026-01-01', grade: 'wrong', answer: 'B'),
      event(2, '2026-01-02', grade: 'mastered'),
    ];
    final state = LearningState(events, bank);
    expect(state.attempts.length, 2);
    expect(state.states['q1']!.stage, 1);
    expect(state.states['q1']!.due, '2026-01-04');
  });
}
