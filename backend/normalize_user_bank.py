"""Convert a user-supplied single-choice JSON bank into DentStudy's import schema."""
import argparse
import json
from pathlib import Path


def text(value):
    return value.strip() if isinstance(value, str) else ''


def normalize(raw_questions):
    normalized, errors, ids = [], [], set()
    for position, raw in enumerate(raw_questions, 1):
        prefix = f'题目 {position}'
        if not isinstance(raw, dict):
            errors.append(prefix + '：不是对象')
            continue
        question_id = text(raw.get('id'))
        if not question_id or question_id in ids:
            errors.append(prefix + '：ID 缺失或重复')
            continue
        ids.add(question_id)
        source = raw.get('source') if isinstance(raw.get('source'), dict) else {}
        provenance = raw.get('provenance') if isinstance(raw.get('provenance'), dict) else {}
        review = raw.get('review') if isinstance(raw.get('review'), dict) else {}
        options = raw.get('options')
        option_map = {text(option.get('id')): text(option.get('text'))
                      for option in options if isinstance(option, dict)} if isinstance(options, list) else {}
        answer = raw.get('answer')
        answer = answer[0] if isinstance(answer, list) and len(answer) == 1 else answer
        if not text(raw.get('stem')) or len(option_map) < 2 or answer not in option_map:
            errors.append(prefix + '：题干、选项或答案不完整')
            continue
        modes = raw.get('exam_modes')
        modes = [mode for mode in modes if mode in ['考研', '本科期末', '执医']] if isinstance(modes, list) else []
        if not modes:
            errors.append(prefix + '：没有可用学习模式')
            continue
        chapter = text(raw.get('chapter')) or '未分类章节'
        section = text(raw.get('section'))
        topics = [item for item in raw.get('topic_path', []) if text(item)] if isinstance(raw.get('topic_path'), list) else []
        if section and section not in topics:
            topics.insert(0, section)
        tags = [item for item in raw.get('tags', []) if text(item)] if isinstance(raw.get('tags'), list) else []
        for tag in ['用户资料', '待医学审核']:
            if tag not in tags:
                tags.append(tag)
        document = text(source.get('document')) or '用户导入资料'
        extracted_line = source.get('extracted_line')
        location = f"第 {extracted_line} 行" if isinstance(extracted_line, int) else ''
        reference = ' · '.join(item for item in [document, chapter, section, location] if item)
        chapter_id = text(raw.get('chapter_id')) or 'uncategorized'
        normalized.append({
            'id': question_id,
            'subject': '口腔修复学',
            'chapter': chapter,
            'type': raw.get('exam_type') if raw.get('exam_type') in ['A1', 'A2', 'A3', 'A4', 'B'] else 'A1',
            'stem': text(raw.get('stem')),
            'options': option_map,
            'answer': answer,
            'explanation': text(raw.get('explanation')) or '导入资料未提供详细解析。',
            'warning': '导入题库未提供独立易错提示；请结合解析、来源摘录与教材复核。',
            'reference': reference,
            'citation': {
                'publisher': None,
                'title': document,
                'edition': None,
                'chapter': chapter,
                'page': None,
                'verified': False,
                'sourceId': source.get('source_id'),
                'excerpt': source.get('excerpt'),
            },
            'tags': tags,
            'topics': topics or [chapter],
            'modes': modes,
            'school': provenance.get('school'),
            'year': provenance.get('year'),
            'paperId': f'user-prosthodontics-{chapter_id}',
            'paperName': f'口腔修复学 · {chapter}（用户导入）',
            'durationMinutes': 60,
            'order': raw.get('number') if type(raw.get('number')) is int and raw['number'] > 0 else position,
            'points': 1,
            'isDemo': False,
            'reviewStatus': 'approved' if review.get('medical_reviewed') is True else 'draft',
            'sourceType': 'user_material',
            'license': '用户提供资料；仅供本地学习使用，发布前需核实授权与医学审核。',
            'sourceUrl': None,
            'reviewer': review.get('reviewer'),
            'reviewedAt': review.get('reviewed_at'),
            'importMetadata': {
                'originalType': raw.get('type'),
                'examType': raw.get('exam_type'),
                'questionStyle': raw.get('question_style'),
                'difficulty': raw.get('difficulty'),
                'section': section,
                'provenance': provenance,
                'review': review,
            },
        })
    return normalized, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    raw = json.loads(args.source.read_text(encoding='utf-8'))
    if not isinstance(raw, list):
        raise SystemExit('源文件顶层必须为题目数组')
    questions, errors = normalize(raw)
    if errors:
        print('\n'.join(errors[:50]))
        raise SystemExit(f'转换失败：{len(errors)} 道题不符合导入条件')
    args.output.write_text(json.dumps({'version': 1, 'name': '口腔修复学用户导入题库',
                                       'isDemo': False, 'questions': questions}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'转换完成：{len(questions)} 道题')


if __name__ == '__main__':
    main()
