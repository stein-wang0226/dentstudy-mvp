import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from import_cmb_practice import build, convert, fingerprint, read_records


def record():
    return {'exam_type': '医师考试', 'exam_class': '执业医师',
            'exam_subject': '口腔执业医师', 'question': '测试题干',
            'question_type': '单项选择题', 'answer': 'E',
            'option': dict(zip('ABCDE', ['甲', '乙', '丙', '丁', '戊']))}


def note(index=0):
    return [index, '修复', '测试章节', 'A1', 'E',
            '这是用于软件测试的补充解析，不是真实医学题目，不代表任何考试答案或专业医学审核结果。']


class CmbImportTests(unittest.TestCase):
    def test_rejects_changed_or_incomplete_source_download(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'invalid.bin'
            path.write_bytes(b'not-the-pinned-source')
            with self.assertRaises(ValueError):
                read_records(path)

    def test_preserves_source_and_marks_provenance(self):
        raw = record()
        before = copy.deepcopy(raw)
        q = convert(raw, note())
        self.assertEqual(raw, before)
        self.assertEqual(q['options'], raw['option'])
        self.assertEqual(q['stem'], raw['question'])
        self.assertEqual(q['answer'], 'E')
        self.assertIsNone(q['year'])
        self.assertEqual(q['sourceType'], 'open_dataset')
        self.assertEqual(q['reviewStatus'], 'draft')
        self.assertFalse(q['citation']['verified'])
        self.assertEqual(q['modes'], ['执医'])
        self.assertIn('AI', q['explanationSource'])

    def test_rejects_wrong_track_answer_and_broken_content(self):
        for key, value in [('exam_subject', '口腔执业助理医师'),
                           ('exam_class', '中级职称'), ('answer', 'A'),
                           ('question_type', '多项选择题'), ('question', '坏\x1f字')]:
            raw = record()
            raw[key] = value
            with self.assertRaises(ValueError):
                convert(raw, note())

    def test_merge_is_idempotent_and_old_records_are_immutable(self):
        raw = record()
        base = {'name': '旧库', 'questions': []}
        once, added, _ = build([raw], [note()], base)
        twice, again, _ = build([raw], [note()], once)
        self.assertEqual(once, twice)
        self.assertEqual(added, again)
        self.assertEqual(base['questions'], [])
        changed = note()
        changed[-1] += '此改写不得覆盖原有内容。'
        with self.assertRaises(ValueError):
            build([raw], [changed], once)
        with self.assertRaises(ValueError):
            build([raw], [note(), note()], base)

    def test_duplicate_stems_are_not_imported_twice(self):
        self.assertEqual(fingerprint('1-测试题？'), fingerprint('测试题'))
        once, _, _ = build([record()], [note()], {'questions': []})
        raw = record()
        raw['question'] = '测试题干？'
        merged, selected, skipped = build([record(), raw], [note(1)], once)
        self.assertEqual(merged, once)
        self.assertFalse(selected)
        self.assertEqual(len(skipped), 1)

    def test_runtime_bank_is_empty_after_content_withdrawal(self):
        bank = json.loads((ROOT / 'mobile/assets/all_questions.json').read_text())
        self.assertEqual(bank['questions'], [])


if __name__ == '__main__':
    unittest.main()
