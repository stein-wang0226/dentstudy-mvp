"""Split a supplied, year-verified oral practitioner bank without rewriting questions."""
import argparse
import json
import sys
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from bank import validate


def split_bank(bank):
    errors = validate(bank)
    if errors:
        raise ValueError('\n'.join(errors))
    groups, paper_years = {}, {}
    for q in bank['questions']:
        year = q.get('year')
        provenance = q.get('examProvenance')
        if not isinstance(provenance, dict):
            raise ValueError(f"{q['id']}: 缺少 examProvenance 来源与年份记录")
        if (q['modes'] != ['执医'] or provenance.get('examName') != '口腔执业医师'
                or q['isDemo'] is not False):
            raise ValueError(f"{q['id']}: 仅接受非演示的口腔执业医师试题")
        if q['sourceType'] not in ('past_paper', 'recalled_paper'):
            raise ValueError(f"{q['id']}: 资料整理题或模拟题不能改标为历年试题")
        if type(year) is not int or not 1999 <= year <= date.today().year:
            raise ValueError(f"{q['id']}: 考试年份无效")
        if provenance.get('yearVerified') is not True:
            raise ValueError(f"{q['id']}: 考试年份尚未核验；不能用文档上传年份代替")
        source_url = q.get('sourceUrl')
        source = urlparse(source_url if isinstance(source_url, str) else '')
        if source.scheme not in ('https', 'http') or not source.netloc:
            raise ValueError(f"{q['id']}: 缺少可追溯的 sourceUrl")
        if q['sourceType'] == 'past_paper' and provenance.get('sourceVerified') is not True:
            raise ValueError(f"{q['id']}: 真题来源尚未核验")
        if q['paperId'] in paper_years and paper_years[q['paperId']] != year:
            raise ValueError(f"{q['id']}: 同一 paperId 的考试年份不一致")
        paper_years[q['paperId']] = year
        groups.setdefault(year, []).append(q)
    return {
        year: {
            'version': bank.get('version', 1),
            'name': f'{year} 年口腔执业医师试题',
            'isDemo': False,
            'sourceNote': '由用户提供并核验年份的资料拆分；来源类型、答案、解析和审核状态逐题保留。',
            'questions': sorted(qs, key=lambda q: (q['paperId'], q['order'])),
        }
        for year, qs in sorted(groups.items(), reverse=True)
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        banks = split_bank(json.loads(args.source.read_text(encoding='utf-8-sig')))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
    outputs = {
        args.output / f'oral_practitioner_{year}.json':
            json.dumps(bank, ensure_ascii=False, indent=2) + '\n'
        for year, bank in banks.items()
    }
    # Check all targets before writing; never replace an existing different bank.
    for path, content in outputs.items():
        if path.exists() and path.read_text(encoding='utf-8') != content:
            raise SystemExit(f'目标文件已有不同内容，请选择新的输出目录：{path}')
    args.output.mkdir(parents=True, exist_ok=True)
    for path, content in outputs.items():
        path.write_text(content, encoding='utf-8')
    print(f"已按 {len(banks)} 个年份输出 {sum(len(b['questions']) for b in banks.values())} 道题；未修改运行题库。")


if __name__ == '__main__':
    main()
