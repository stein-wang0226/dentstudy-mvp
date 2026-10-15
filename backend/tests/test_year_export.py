import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from split_exam_year_banks import split_bank


def fixture(n, year):
    return {
        'id': f'fixture-{n}', 'subject': '口腔修复学', 'chapter': '测试章节',
        'type': 'A1', 'stem': f'软件测试题 {n}',
        'options': dict(zip('ABCDE', ['甲', '乙', '丙', '丁', '戊'])),
        'answer': 'E', 'explanation': '软件测试解析', 'warning': '非学习题目',
        'reference': '测试来源', 'citation': {'verified': False},
        'tags': [], 'topics': [], 'modes': ['执医'], 'year': year,
        'paperId': f'test-{year}', 'paperName': f'{year} 测试卷',
        'durationMinutes': 60, 'order': n, 'points': 1,
        'isDemo': False, 'reviewStatus': 'draft', 'sourceType': 'past_paper',
        'license': '软件测试数据', 'sourceUrl': 'https://example.invalid/source',
        'examProvenance': {'examName': '口腔执业医师', 'yearVerified': True,
                           'sourceVerified': True},
    }


class YearExportTests(unittest.TestCase):
    def test_split_preserves_questions_answers_ids_and_five_options(self):
        bank = {'questions': [fixture(1, 2024), fixture(2, 2023), fixture(3, 2024)]}
        original = copy.deepcopy(bank)
        result = split_bank(bank)
        self.assertEqual(list(result), [2024, 2023])
        self.assertEqual(result[2024]['questions'], [bank['questions'][0], bank['questions'][2]])
        self.assertEqual(result[2024]['questions'][0]['options']['E'], '戊')
        self.assertEqual(bank, original)

    def test_rejects_unknown_year_and_other_examination_types(self):
        for key, value in [('yearVerified', False), ('examName', '口腔执业助理医师')]:
            q = fixture(1, 2024)
            q['examProvenance'][key] = value
            with self.assertRaises(ValueError):
                split_bank({'questions': [q]})
        for key, value in [('sourceType', 'user_material'), ('year', True), ('year', 2099),
                           ('answer', 'F'), ('explanation', '')]:
            q = fixture(1, 2024)
            q[key] = value
            with self.assertRaises(ValueError):
                split_bank({'questions': [q]})


if __name__ == '__main__':
    unittest.main()
