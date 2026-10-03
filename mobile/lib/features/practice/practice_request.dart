import '../../models.dart';

class PracticeRequest {
  final List<Question> questions;
  final String mode, kind, label;
  final bool review, exam;
  final Map<String, dynamic>? draft;
  const PracticeRequest(this.questions,
      {this.mode = 'deep',
      this.kind = 'custom',
      this.label = '自定义练习',
      this.review = false,
      this.exam = false,
      this.draft});
}

typedef StartPractice = Future<void> Function(PracticeRequest request);
