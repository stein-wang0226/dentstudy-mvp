import copy
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from import_prosthodontics_postgraduate_bank import convert, merge


def source(question_id, kind='original'):
    question = {
        'id': question_id,
        'chapter': '第一章 绪论',
        'section': '第一节 概述',
        'type': 'single_choice',
        'question': f'测试题 {question_id}',
        'options': ['A. 甲', 'B. 乙', 'C. 丙', 'D. 丁'],
        'answer': 'A',
        'explanation': '测试解析。',
        'knowledge_point': '测试考点',
        'source': {'type': kind},
    }
    if kind == 'real_exam':
        question.update({
            'type': 'term_explain',
            'question': '测试名词解释',
            'answer': 'test term',
            'options': None,
            'source': {
                'type': 'real_exam', 'school': '测试院校', 'year': 2009,
                'url': 'https://example.test/source', 'note': '考生回忆版',
            },
        })
    return question


class ProsthodonticsImportTests(unittest.TestCase):
    def test_converts_preserves_chapters_and_distinguishes_provenance(self):
        payload = {'meta': {'total_questions': 2}, 'chapters': [{
            'index': 1, 'name': '第一章 绪论',
            'questions': [source('CH1-001'), source('CH1-002', 'real_exam')],
        }]}
        before = copy.deepcopy(payload)
        questions = convert(payload)
        self.assertEqual(payload, before)
        self.assertEqual([q['id'] for q in questions], ['PROS-CH1-001', 'PROS-CH1-002'])
        self.assertEqual(questions[0]['subject'], '口腔修复学')
        self.assertEqual(questions[0]['chapter'], '第一章 绪论')
        self.assertEqual(questions[0]['sourceType'], 'user_material')
        self.assertEqual(questions[1]['type'], '简答题')
        self.assertIsNone(questions[1]['answer'])
        self.assertEqual(questions[1]['sourceType'], 'recalled_paper')
        self.assertEqual(questions[1]['year'], 2009)

    def test_merge_is_idempotent_and_never_rewrites_existing_questions(self):
        payload = {'meta': {'total_questions': 1}, 'chapters': [{
            'index': 1, 'name': '第一章 绪论', 'questions': [source('CH1-001')],
        }]}
        imported = convert(payload)
        base = {'name': '原题库', 'questions': [{'id': 'CH1-001', 'stem': '旧题'}]}
        once, added = merge(base, imported)
        twice, repeated = merge(once, imported)
        self.assertEqual(added, 1)
        self.assertEqual(repeated, 0)
        self.assertEqual(once, twice)
        self.assertEqual(base['questions'], [{'id': 'CH1-001', 'stem': '旧题'}])


if __name__ == '__main__':
    unittest.main()
