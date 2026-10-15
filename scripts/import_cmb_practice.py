"""Reproducibly import an explicitly curated subset of CMB, never as past papers.

Input is a pinned byte-range of the upstream ZIP (the start of the train entry).
Only complete JSON records are decoded; the trailing partial record is ignored.
The entire downloaded range must match its frozen SHA-256 before selection.
"""
import argparse
import copy
import hashlib
import json
import re
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from bank import SUBJECTS, validate

REVISION = '6c8ece46097dae736c6805dd3b831e1a38c08971'
ZIP_BLOB = 'c05ff2040d8257408aee77a774d41f29727401bf'
PREFIX_SHA256 = '1f23527ce1bfb50942c8c59d9095a4071ae056e006c9c4ec26f16c340a053633'
SOURCE_URL = f'https://github.com/FreedomIntelligence/CMB/tree/{REVISION}'
EXPLANATION_SOURCE = 'DentStudy AI 辅助补充解析，待专业医学审核'
SUBJECT_MAP = {'修复': '口腔修复学', '牙体': '牙体牙髓病学', '牙周': '牙周病学',
               '口外': '口腔颌面外科学', '黏膜': '口腔黏膜病学',
               '解剖': '口腔解剖生理学', '病理': '口腔组织病理学'}


def read_records(path):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != PREFIX_SHA256:
        raise ValueError('上游数据片段校验失败；拒绝从不同版本或不完整下载导入')
    header = struct.unpack_from('<4s5H3I2H', raw)
    name_len, extra_len = header[-2:]
    if (header[0] != b'PK\x03\x04' or header[3] != 8 or
            raw[30:30 + name_len] != b'CMB/CMB-Exam/CMB-train/CMB-train-merge.json'):
        raise ValueError('不是已固定版本的 CMB 训练集条目')
    text = zlib.decompressobj(-15).decompress(raw[30 + name_len + extra_len:])
    text = text.decode('utf-8', errors='ignore')  # only a trailing partial codepoint
    decoder, records, offset = json.JSONDecoder(), [], 1
    while offset < len(text):
        while offset < len(text) and (text[offset].isspace() or text[offset] == ','):
            offset += 1
        try:
            record, offset = decoder.raw_decode(text, offset)
        except ValueError:
            break  # incomplete last record is never imported
        records.append(record)
    return records


def fingerprint(stem):
    return re.sub(r'[\W_]+', '', re.sub(r'^\d+[-－]', '', stem), flags=re.UNICODE)


def convert(record, annotation):
    index, subject, chapter, kind, expected, explanation = annotation
    if (record.get('exam_type'), record.get('exam_class'), record.get('exam_subject')) != (
            '医师考试', '执业医师', '口腔执业医师'):
        raise ValueError(f'{index}: 非口腔执业医师来源')
    options = record.get('option', {})
    if (record.get('question_type') != '单项选择题' or expected != record.get('answer')
            or expected not in options or len(expected) != 1 or len(options) < 4
            or not all(isinstance(v, str) and v.strip() for v in options.values())):
        raise ValueError(f'{index}: 选项或原答案不匹配')
    if subject not in SUBJECT_MAP or kind not in ['A1', 'A2'] or len(explanation) < 30:
        raise ValueError(f'{index}: 分科或补充解析不完整')
    stem = record.get('question', '')
    if not stem or re.search(r'[\x00-\x1f\ufffd]', stem):
        raise ValueError(f'{index}: 题干含损坏字符')
    name = SUBJECT_MAP[subject]
    original_hash = hashlib.sha256(json.dumps(record, ensure_ascii=False,
        sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return {
        'id': f'cmb-train-{index:06d}-v1', 'subject': name, 'chapter': chapter,
        'type': kind, 'stem': stem, 'options': copy.deepcopy(options),
        'answer': expected, 'explanation': explanation,
        'warning': '开放数据练习题，非历年真题；解析为 AI 辅助整理，尚未通过专业医学审核。',
        'topics': [chapter], 'tags': ['CMB', '执医补充练习'], 'modes': ['执医'],
        'school': None, 'year': None, 'paperId': f'cmb-practice-{SUBJECTS.index(name)}-v1',
        'paperName': f'CMB · {name}补充练习（非真题）', 'durationMinutes': 90,
        'order': index + 1, 'points': 1,
        'reference': f'CMB / FreedomIntelligence · CMB-Exam 训练集 · 原始第 {index + 1} 条。'
                     f'原分类：口腔执业医师。题干、选项与答案按原数据保留；学科与章节由 DentStudy 整理。',
        'citation': {'publisher': 'FreedomIntelligence', 'title': 'CMB',
                     'edition': REVISION, 'chapter': 'CMB-Exam/CMB-train',
                     'page': None, 'verified': False},
        'reviewStatus': 'draft', 'isDemo': False, 'sourceType': 'open_dataset',
        'license': 'Apache-2.0（CMB 发布方标注）；本站分科与补充解析变更已说明',
        'sourceUrl': SOURCE_URL, 'explanationSource': EXPLANATION_SOURCE,
        'datasetProvenance': {'dataset': 'CMB', 'split': 'train',
            'revision': REVISION, 'archiveGitBlob': ZIP_BLOB, 'rowIndex': index,
            'originalRecordSha256': original_hash, 'licenseId': 'Apache-2.0',
            'licenseUrl': f'https://github.com/FreedomIntelligence/CMB/blob/{REVISION}/LICENSE',
            'datasetCardUrl': 'https://huggingface.co/datasets/FreedomIntelligence/CMB',
            'changes': ['增加学科、章节与单选题型映射', '增加 AI 辅助补充解析及来源记录'],
            'yearVerified': False},
        'rubric': None,
    }


def build(records, annotations, existing):
    merged = copy.deepcopy(existing)
    old = {q['id']: q for q in existing['questions']}
    stems = {fingerprint(q['stem']) for q in existing['questions']}
    selected, skipped, indices = [], [], set()
    for annotation in annotations:
        index = annotation[0]
        if type(index) is not int or index < 0 or index >= len(records) or index in indices:
            raise ValueError(f'重复或无效源行号：{index}')
        indices.add(index)
        q = convert(records[index], annotation)
        if q['id'] in old:
            if q != old[q['id']]:
                raise ValueError(f"{q['id']}: 已有内容不同，禁止覆盖")
            selected.append(q)  # idempotent re-export
            continue
        key = fingerprint(q['stem'])
        if key in stems:
            skipped.append({'rowIndex': index, 'reason': '与既有或本批题干重复'})
            continue
        stems.add(key)
        selected.append(q)
        merged['questions'].append(q)
    merged['name'] = '齿间综合题库（资料整理题与开放数据练习题）'
    merged['sourceNote'] = '保留原题库，追加 CMB 分科练习；来源、使用许可及待审核状态逐题标注。'
    errors = validate(merged)
    if errors:
        raise ValueError('\n'.join(errors))
    return merged, selected, skipped


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_prefix', type=Path)
    parser.add_argument('--annotations', type=Path, default=ROOT / 'data/curation/cmb_practice_annotations.json')
    parser.add_argument('--bank', type=Path, default=ROOT / 'mobile/assets/all_questions.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'question-bank/open-practice')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    records = read_records(args.source_prefix)
    original = json.loads(args.bank.read_text())
    annotations = json.loads(args.annotations.read_text())
    merged, selected, skipped = build(records, annotations, original)
    counts = Counter(q['subject'] for q in selected)
    report = {'sourceRevision': REVISION, 'prefixSha256': PREFIX_SHA256,
        'selected': len(selected), 'counts': dict(counts), 'skipped': skipped,
        'before': len(original['questions']), 'after': len(merged['questions']),
        'oldQuestionsUnchanged': all(q in merged['questions'] for q in original['questions'])}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not args.apply:
        return
    outputs = {args.bank: merged}
    for name in counts:
        outputs[args.output / f'{name}.json'] = {'version': 1, 'name': f'CMB · {name}执医补充练习',
            'isDemo': False, 'sourceNote': '开放数据练习题，非历年真题；AI 辅助补充解析待审核。',
            'questions': [q for q in selected if q['subject'] == name]}
    # Validate all outputs before writing. Existing subject exports cannot be overwritten.
    for path, content in outputs.items():
        if path != args.bank and path.exists() and json.loads(path.read_text()) != content:
            raise ValueError(f'分科文件已有不同内容：{path}')
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(content, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
