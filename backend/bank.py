"""Validate and import curated JSON banks; no scraped or invented official papers."""
import argparse
import json
import os
import tempfile
from pathlib import Path

SUBJECTS = ['口腔解剖生理学', '口腔组织病理学', '牙体牙髓病学', '牙周病学', '口腔黏膜病学', '口腔颌面外科学', '口腔修复学', '口腔正畸学']
TYPES = ['A1', 'A2', 'A3', 'A4', 'B', '简答题', '案例分析']


def validate(bank, production=False):
    errors, ids, groups, papers = [], set(), {}, {}
    if not isinstance(bank, dict) or not isinstance(bank.get('questions'), list):
        return ['顶层必须含 questions 数组']
    if not bank['questions']:
        return ['题库不能为空']
    for i, q in enumerate(bank['questions']):
        prefix = f'题目 {i + 1}'
        if not isinstance(q, dict):
            errors.append(prefix + ': 必须是对象')
            continue
        missing = [k for k in ['id','subject','chapter','type','stem','options','answer','explanation','warning','reference','citation','tags','topics','modes','paperId','paperName','durationMinutes','order','points','isDemo','reviewStatus','sourceType','license'] if k not in q]
        if missing:
            errors.append(prefix + ': 缺少 ' + ', '.join(missing))
            continue
        if not isinstance(q['id'], str) or not q['id'] or q['id'] in ids:
            errors.append(prefix + ': ID 为空、格式不正确或重复')
            continue
        ids.add(q['id'])
        if q['subject'] not in SUBJECTS or q['type'] not in TYPES:
            errors.append(prefix + ': 无效科目或题型')
        for key in ['chapter','stem','explanation','warning','reference','paperId','paperName','license']:
            if not isinstance(q[key], str) or not q[key].strip():
                errors.append(prefix + ': ' + key + ' 必须是非空字符串')
        for key in ['tags','topics','modes']:
            if not isinstance(q[key], list) or not all(isinstance(x,str) for x in q[key]):
                errors.append(prefix + ': ' + key + ' 必须是字符串数组')
        if not isinstance(q['modes'], list) or not q['modes'] or any(m not in ['考研','本科期末','执医'] for m in q['modes']):
            errors.append(prefix + ': 无效学习模式')
        for key in ['durationMinutes','order','points']:
            if type(q[key]) is not int or q[key] <= 0:
                errors.append(prefix + ': ' + key + ' 必须是正整数')
        opts = q['options']
        if not isinstance(opts, dict) or not all(isinstance(k,str) and isinstance(v,str) for k,v in opts.items()):
            errors.append(prefix + ': options 必须为字符串映射')
        elif q['type'] not in ['简答题','案例分析']:
            if len(opts)<2 or q['answer'] not in opts:
                errors.append(prefix + ': 客观题至少两个选项，答案须属于选项')
        elif q['answer'] is not None or not q.get('rubric'):
            errors.append(prefix + ': 主观题 answer 应为 null，且必须提供 rubric')
        if q['type'] in ['A3','A4','B']:
            if not q.get('groupId') or not q.get('sharedStem'):
                errors.append(prefix + ': 共用题型必须提供 groupId/sharedStem')
            else:
                identity=(q['type'],q['sharedStem'],q['options'] if q['type']=='B' else None,q['paperId'])
                if q['groupId'] in groups and groups[q['groupId']] != identity:
                    errors.append(prefix + ': 同组题干、类型、试卷或 B 型选项不一致')
                groups[q['groupId']]=identity
        if isinstance(q['paperId'], str):
            identity=(q['paperName'],q['durationMinutes'])
            if q['paperId'] in papers and papers[q['paperId']] != identity:
                errors.append(prefix + ': 同一试卷的名称或时长不一致')
            papers[q['paperId']]=identity
        if production:
            citation=q['citation']
            if q['isDemo'] is not False or q['reviewStatus']!='approved':
                errors.append(prefix + ': 正式库不得包含演示题或未审核题')
            if not isinstance(citation,dict) or citation.get('verified') is not True or not all(citation.get(k) for k in ['publisher','title','edition','chapter','page']):
                errors.append(prefix + ': 正式库必须核实教材书名、出版社、版次、章节、页码')
            if not q.get('reviewer') or not q.get('reviewedAt') or not q.get('sourceUrl'):
                errors.append(prefix + ': 正式库需提供审核人与来源记录')
            if q['sourceType']=='past_paper' and (not q.get('school') or type(q.get('year')) is not int):
                errors.append(prefix + ': 院校真题必须含学校与年份')
    return errors


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['validate','import'])
    parser.add_argument('file',type=Path)
    parser.add_argument('--production',action='store_true')
    parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'mobile/assets/questions.json')
    args=parser.parse_args()
    bank=json.loads(args.file.read_text())
    errors=validate(bank,args.production)
    if errors:
        for error in errors: print(error)
        raise SystemExit(1)
    if args.action=='import':
        # Question IDs are immutable content versions, so old attempts stay interpretable.
        if args.output.exists():
            old=json.loads(args.output.read_text())
            existing={q['id']:q for q in old['questions']}
            for q in bank['questions']:
                if q['id'] in existing and existing[q['id']]!=q:
                    raise SystemExit(f"题目 {q['id']} 已存在且内容不同，请分配新版本 ID")
                existing[q['id']]=q
            bank['questions']=list(existing.values())
        args.output.parent.mkdir(parents=True,exist_ok=True)
        fd,path=tempfile.mkstemp(dir=args.output.parent)
        with os.fdopen(fd,'w') as output: json.dump(bank,output,ensure_ascii=False,indent=2)
        os.replace(path,args.output)
    print(f"校验通过：{len(bank['questions'])} 道题，{'正式审核模式' if args.production else '开发模式'}")


if __name__=='__main__': main()
