#!/usr/bin/env python3
"""Generate an auditable periodontology bank from a supplied DOCX.

The generator creates draft A1 items from explicit source statements. It keeps
the source excerpt and paragraph number on every item so a dental educator can
review or revise the question before publication.
"""
from __future__ import annotations

import argparse
import json
import random
import re
from collections import OrderedDict
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET

NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
CHAPTER_RE = re.compile(r"^第[一二三四五六七八九十百]+章\s*")
HEADING_RE = re.compile(
    r"^(?:第[一二三四五六七八九十百]+章|第[一二三四五六七八九十百]+节|"
    r"[一二三四五六七八九十]+、|（[一二三四五六七八九十]+）|\d+[.、])"
)
NUMBER_RE = re.compile(r"(?<![A-Za-z])([0-9]+(?:\.[0-9]+)?)(\s*(?:mm|cm|%|层|年|月|天|岁|颗|种|次|小时|分钟)?)")
ALIAS_RE = re.compile(r"^(.{2,40}?)(?:（[^）]+）)?又称([^，。；]+)")
LIST_RE = re.compile(r"^(.{2,40}?)(?:包括|分为|分成)([^。；]+)")
LOCATION_RE = re.compile(r"^(.{2,40}?)(?:位于|附着于|分布于|延伸至|终止于)([^。；]+)")
DEFINITION_RE = re.compile(r"^(.{2,40}?)(?:是|称为)([^。；]+)")

SWAPS = (
    ("冠方", "根方"), ("根方", "冠方"), ("上颌", "下颌"), ("下颌", "上颌"),
    ("颊侧", "舌侧"), ("舌侧", "颊侧"), ("前牙", "后牙"), ("后牙", "前牙"),
    ("近中", "远中"), ("远中", "近中"), ("角化", "非角化"), ("非角化", "角化"),
    ("增加", "减少"), ("减少", "增加"), ("有", "无"), ("无", "有"),
    ("可", "不可"), ("不可", "可"),
)


def paragraphs(path: Path) -> list[tuple[int, str]]:
    with ZipFile(path) as archive:
        root = ET.fromstring(archive.read("word/document.xml"))
    result = []
    for number, node in enumerate(root.findall(".//w:body/w:p", NS), 1):
        text = "".join(t.text or "" for t in node.findall(".//w:t", NS)).strip()
        if text:
            result.append((number, re.sub(r"\s+", " ", text).strip()))
    return result


def facts(source: list[tuple[int, str]]) -> list[tuple[str, str, int]]:
    chapter = "未分章"
    result = []
    for line, paragraph in source:
        if CHAPTER_RE.match(paragraph) and len(paragraph) < 40:
            chapter = paragraph
            continue
        if len(paragraph) < 24 or len(paragraph) > 360 or HEADING_RE.match(paragraph):
            continue
        for piece in re.split(r"(?<=[。！？；])", paragraph):
            piece = piece.strip("；。 ")
            if 24 <= len(piece) <= 220 and not HEADING_RE.match(piece):
                result.append((chapter, piece, line))
    seen = set()
    unique = []
    for item in result:
        key = (item[0], item[1])
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique


def wrong_variants(text: str, pools: dict[str, list[str]], count: int = 4, kind: str = "general") -> list[str]:
    variants = []
    match = NUMBER_RE.search(text)
    if match:
        value = float(match.group(1))
        deltas = (1, -1, 2) if value >= 1 else (0.01, -0.01, 0.1)
        for delta in deltas:
            changed_value = value + delta
            if changed_value <= 0:
                continue
            if value.is_integer():
                changed = str(int(changed_value))
            else:
                changed = f"{changed_value:.2f}".rstrip("0").rstrip(".")
            variants.append(text[: match.start(1)] + changed + text[match.end(1):])
    for old, new in SWAPS:
        if old in text:
            variants.append(text.replace(old, new, 1))
            break
    if "是" in text:
        variants.append(text.replace("是", "不是", 1))
    if "可" in text:
        variants.append(text.replace("可", "不可", 1))
    if "有" in text:
        variants.append(text.replace("有", "无", 1))
    pool_key = {
        "definition": "definitions",
        "location": "locations",
        "list": "lists",
        "alias": "aliases",
    }.get(kind, "general")
    for value in pools.get(pool_key, []) + pools.get("general", []):
        if value not in text:
            variants.append(value)
            if len(variants) >= count:
                break
    variants.append("资料未作此表述，不能据此判断。")
    out = []
    for value in variants:
        if value != text and value not in out:
            out.append(value)
        if len(out) == count:
            break
    while len(out) < count:
        out.append("与资料所述条件不符。")
    return out


def choose_facts(items: list[tuple[str, str, int]], count: int) -> list[tuple[str, str, int]]:
    by_chapter: OrderedDict[str, list[tuple[str, str, int]]] = OrderedDict()
    for item in items:
        by_chapter.setdefault(item[0], []).append(item)
    total = sum(len(v) for v in by_chapter.values())
    quotas = {k: max(1, round(count * len(v) / total)) for k, v in by_chapter.items()}
    while sum(quotas.values()) > count:
        key = max(quotas, key=lambda k: quotas[k])
        if quotas[key] > 1:
            quotas[key] -= 1
        else:
            break
    while sum(quotas.values()) < count:
        key = max(by_chapter, key=lambda k: len(by_chapter[k]) - quotas[k])
        if quotas[key] >= len(by_chapter[key]):
            break
        quotas[key] += 1
    selected = []
    for chapter, values in by_chapter.items():
        selected.extend(values[: quotas[chapter]])
    return selected[:count]


def build_item(index: int, chapter: str, fact: str, line: int, pools: dict[str, list[str]], rng: random.Random) -> dict:
    alias = ALIAS_RE.search(fact)
    listing = LIST_RE.search(fact)
    location = LOCATION_RE.search(fact)
    definition = DEFINITION_RE.search(fact)
    if alias:
        entity, answer = alias.group(1).strip(), alias.group(2).strip()
        display_entity = entity.split("：")[-1].strip()
        stem = f"{display_entity}又称？"
        candidates = [x for x in pools.get("aliases", []) if x != answer]
        options = [answer] + candidates[:4]
        while len(options) < 5:
            options.append("资料未提及的名称")
        explanation = f"{entity}又称{answer}。原文同时说明：{fact}。"
        topic = display_entity
    elif listing:
        entity, answer = listing.group(1).strip(), listing.group(2).strip()
        display_entity = entity.split("：")[-1].strip()
        stem = f"{display_entity}包括哪些分类或组成？"
        options = [answer] + wrong_variants(answer, pools, 4, "list")
        explanation = f"{entity}{'包括' if '包括' in fact else '分为'}{answer}。"
        topic = display_entity
    elif location:
        entity, answer = location.group(1).strip(), location.group(2).strip()
        display_entity = entity.split("：")[-1].strip()
        stem = f"{display_entity}的相关位置或分布是？"
        options = [answer] + wrong_variants(answer, pools, 4, "location")
        explanation = f"{entity}{'位于' if '位于' in fact else '的相关部位为'}{answer}。"
        topic = display_entity
    elif definition:
        entity, answer = definition.group(1).strip(), definition.group(2).strip()
        display_entity = entity.split("：")[-1].strip()
        stem = f"关于{display_entity}的定义或主要特点，哪项正确？"
        options = [answer] + wrong_variants(answer, pools, 4, "definition")
        explanation = f"{entity}{'是' if '是' in fact else '称为'}{answer}。"
        topic = display_entity
    else:
        lead = fact.split("：", 1)[-1]
        lead = re.split(r"[，,。；]", lead, 1)[0].strip()[:40]
        stem = f"关于“{lead}”的表述，哪项正确？"
        options = [fact] + wrong_variants(fact, pools, 4, "general")
        explanation = f"正确表述为：{fact}。"
        topic = lead or "牙周病学"
    options = list(dict.fromkeys(options))[:5]
    while len(options) < 5:
        options.append("资料未给出该说法。")
    rng.shuffle(options)
    letters = ["A", "B", "C", "D", "E"]
    answer_letter = letters[options.index(answer if alias else (answer if listing or location or definition else fact))]
    tags = ["资料改编", "考点单选", "用户资料", "待医学审核"]
    if "★" in fact or any(k in fact for k in ("定义", "分类", "诊断", "治疗", "探诊", "附着")):
        tags.append("高频考点")
    if any(k in fact for k in ("仅", "不", "无", "最", "约", "区别", "易")):
        tags.append("易混淆")
    return {
        "id": f"DS-PERIO-{index:05d}-v2",
        "subject": "牙周病学",
        "chapter": chapter,
        "type": "A1",
        "stem": stem,
        "options": dict(zip(letters, options)),
        "answer": answer_letter,
        "explanation": explanation,
        "warning": "题目由学习资料整理，正式用于考研前应由专业教师核对题干、选项和教材版本。",
        "topics": [topic],
        "tags": tags,
        "modes": ["考研"],
        "school": None,
        "year": None,
        "paperId": "periodontology-yazhou-draft-v2",
        "paperName": "牙周病学考研资料章节题库（优化整理稿）",
        "durationMinutes": 180,
        "order": index,
        "points": 1,
        "reference": f"yazhou.docx · {chapter} · 原文段 {line}",
        "citation": {
            "publisher": None,
            "title": "yazhou.docx",
            "edition": None,
            "chapter": chapter,
            "page": None,
            "verified": False,
            "sourceId": f"YAZHOU-{line:04d}",
            "excerpt": fact,
        },
        "reviewStatus": "draft",
        "isDemo": False,
        "sourceType": "user_material",
        "license": "用户提供资料，待专业审核",
        "rubric": None,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--count", type=int, default=1200)
    args = parser.parse_args()
    source_facts = facts(paragraphs(args.source))
    if len(source_facts) < args.count:
        raise SystemExit(f"可整理事实仅 {len(source_facts)} 条，少于目标 {args.count} 条")
    selected = choose_facts(source_facts, args.count)
    aliases = []
    definitions = []
    locations = []
    lists = []
    general = []
    for _, text, _ in source_facts:
        match = ALIAS_RE.search(text)
        if match:
            aliases.append(match.group(2).strip())
        match = DEFINITION_RE.search(text)
        if match:
            definitions.append(match.group(2).strip())
        match = LOCATION_RE.search(text)
        if match:
            locations.append(match.group(2).strip())
        match = LIST_RE.search(text)
        if match:
            lists.append(match.group(2).strip())
        if not any((ALIAS_RE.search(text), DEFINITION_RE.search(text), LOCATION_RE.search(text), LIST_RE.search(text))):
            general.append(text)
    pools = {
        "aliases": list(dict.fromkeys(aliases)),
        "definitions": list(dict.fromkeys(definitions)),
        "locations": list(dict.fromkeys(locations)),
        "lists": list(dict.fromkeys(lists)),
        "general": list(dict.fromkeys(general)),
    }
    rng = random.Random(20260928)
    questions = [build_item(i, chapter, text, line, pools, rng) for i, (chapter, text, line) in enumerate(selected, 1)]
    bank = {
        "version": 1,
        "name": "牙周病学考研资料独立题库（优化整理稿）",
        "isDemo": False,
        "sourceDocument": args.source.name,
        "sourceNote": "依据用户提供的 yazhou.docx 自动整理；题目保留原文摘录，均为待专业审核的资料整理稿。",
        "questions": questions,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(bank, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"generated {len(questions)} questions from {len(source_facts)} source facts")


if __name__ == "__main__":
    main()
