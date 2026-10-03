import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

/*
 * 该构建器只产出审阅版 JSON。每个正确选项均保留为讲义的独立知识要点；
 * 干扰项仅改变同一知识点中的时间、部位、病程、性质或处理方向，避免跨病种拼接。
 */
const doc = '/Users/hydrogen/Desktop/考研资料/kouwai.doc';
const output = 'review/kouwai-1200-待审阅';
const text = execFileSync('textutil', ['-convert', 'txt', '-stdout', doc], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
const lines = text.split(/\r?\n/).map(x => x.replace(/\s+/g, ' ').trim());
const sections = [
  ['绪论 病历规范与临床检查', 1, 324], ['消毒灭菌与手术基本操作', 325, 614], ['局部麻醉', 615, 884],
  ['全身麻醉与牙槽外科', 885, 1485], ['种植外科基础', 1486, 1765], ['种植骨增量与并发症', 1766, 2105],
  ['口腔颌面部感染', 2106, 2700], ['颌面部创伤急救', 2701, 3120], ['颌骨骨折', 3121, 3519],
  ['骨折愈合与固定', 3520, 3618], ['口腔颌面肿瘤总论', 3619, 3900], ['颌骨囊肿', 3901, 4140],
  ['脉管畸形与血管瘤', 4141, 4366], ['颌骨纤维性病变', 4367, 4550], ['口腔癌与颈淋巴结', 4551, 4766],
  ['唾液腺疾病', 4767, 4939], ['口底囊性病变', 4940, 5030], ['口腔黏膜与颌面软组织病变', 5031, 5150],
  ['颞下颌关节疾病', 5151, 5321], ['三叉神经痛与面神经麻痹', 5322, 5536], ['唇腭裂与阻塞性睡眠呼吸障碍', 5537, 5787],
  ['正颌外科', 5788, 6039], ['显微外科与游离组织瓣', 6040, 6400]
];
const changes = [
  ['急性', ['慢性', '亚急性', '陈旧性']], ['慢性', ['急性', '亚急性', '复发性']], ['良性', ['恶性', '交界性', '炎性']], ['恶性', ['良性', '交界性', '炎性']],
  ['上颌', ['下颌', '颧骨', '颞下颌关节']], ['下颌', ['上颌', '颧骨', '颞下颌关节']], ['单侧', ['双侧', '正中', '对侧']],
  ['局部', ['全身', '对侧', '远隔部位']], ['全身', ['局部', '单侧', '远隔部位']], ['术前', ['术后', '拆线后', '恢复期']], ['术后', ['术前', '麻醉前', '术中']],
  ['增加', ['减少', '维持不变', '消失']], ['减少', ['增加', '维持不变', '持续升高']], ['早期', ['晚期', '恢复期', '终末期']],
  ['适应证', ['禁忌证', '相对禁忌证', '非适应证']], ['禁忌证', ['适应证', '首选指征', '常规指征']], ['手术', ['保守治疗', '单纯观察', '非手术处理']],
  ['内固定', ['外固定', '不固定', '单纯观察']], ['保守治疗', ['手术治疗', '根治性治疗', '侵入性治疗']], ['阳性', ['阴性', '不典型', '无特异性']]
];
function isFact(s) {
  return s.length >= 18 && s.length <= 145 && /[\u4e00-\u9fff]/.test(s) && /[，。；：、]/.test(s)
    && !/^(第?[一二三四五六七八九十]+[、.．]|[（(]?[一二三四五六七八九十]+[）)]|\d+[.、])/.test(s)
    && !/^第[一二三四五六七八九十]+节/.test(s)
    && !/^(定义|分类|病因|治疗|临床表现|适应证|禁忌证|注意事项|手术方法|操作步骤|鉴别诊断|检查方法|诊断依据|治疗原则)$/.test(s);
}
function distractors(fact) {
  const out = [];
  const match = fact.match(/\d+(?:\.\d+)?(?=\s*(?:cm|mm|小时|h|天|周|个月|年|次|%|例|枚|指))/);
  if (match) {
    const v = Number(match[0]);
    for (const replacement of [v + 1, v + 2, v >= 2 ? v - 1 : v + 3]) out.push(fact.slice(0, match.index) + replacement + fact.slice(match.index + match[0].length));
  }
  for (const [from, alternatives] of changes) if (fact.includes(from)) for (const to of alternatives) out.push(fact.replace(from, to));
  return [...new Set(out)].filter(x => x !== fact).slice(0, 3);
}
function topicOf(fact, chapter) {
  const label = fact.match(/^(.{2,18}?)[：:]/)?.[1]?.replace(/^（\d+）/, '').trim();
  if (label && !/^(主要|一般|通常|正常|目的|方法|表现|特点)$/.test(label)) return label;
  return chapter;
}
function importance(fact) {
  return (/[0-9]/.test(fact) ? 5 : 0) + (/(诊断|鉴别|治疗|适应|禁忌|并发|骨折|麻醉|感染|肿瘤|神经|手术|检查)/.test(fact) ? 4 : 0) + (fact.length >= 40 ? 1 : 0);
}
function makeQuestion(fact, chapter, serial) {
  const wrong = distractors(fact);
  if (wrong.length < 3) return null;
  const answerIndex = (serial * 13 + 2) % 4;
  const options = wrong.slice(); options.splice(answerIndex, 0, fact);
  const answer = 'ABCD'[answerIndex];
  const stem = `关于${topicOf(fact, chapter)}，下列说法正确的是？`;
  const explanation = `讲义要点：${fact}`;
  return {
    id: `OMFS-${String(serial).padStart(4, '0')}`,
    chapter,
    knowledgePoint: topicOf(fact, chapter),
    stem,
    options,
    answer,
    answerIndex,
    explanation,
    "题干": stem,
    "选项": options,
    "正确答案": answer,
    "解析": explanation
  };
}

rmSync(output, { recursive: true, force: true }); mkdirSync(output, { recursive: true });
const pools = sections.map(([name, start, end]) => ({
  name,
  questions: lines.slice(start - 1, end).filter(isFact).map((x, i) => makeQuestion(x, name, i + 1)).filter(Boolean).sort((a, b) => importance(b.explanation) - importance(a.explanation))
}));
// 优先让所有章节都有至少 30 题；其余名额按章节可用的高价值要点补足，且不复用知识点。
for (const pool of pools) pool.take = Math.min(30, pool.questions.length);
let remaining = 1200 - pools.reduce((n, x) => n + x.take, 0);
for (const pool of pools) {
  const add = Math.min(remaining, pool.questions.length - pool.take);
  pool.take += add; remaining -= add;
}
if (remaining > 0) throw new Error(`可形成的非重复题目不足1200，尚缺${remaining}题`);
let serial = 1; const manifest = { title: '口腔颌面外科学 1200 题待审阅题库', source: 'kouwai.doc', totalQuestions: 0, chapters: [] };
for (let i = 0; i < pools.length; i++) {
  const pool = pools[i];
  const questions = pool.questions.slice(0, pool.take).map(q => ({ ...q, id: `OMFS-${String(serial++).padStart(4, '0')}` }));
  const file = `${String(i + 1).padStart(2, '0')}-${pool.name}.json`;
  writeFileSync(join(output, file), JSON.stringify({ chapter: pool.name, questions }, null, 2));
  manifest.chapters.push({ name: pool.name, file, count: questions.length }); manifest.totalQuestions += questions.length;
}
if (manifest.totalQuestions !== 1200) throw new Error(`题数错误：${manifest.totalQuestions}`);
writeFileSync(join(output, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`完成：${manifest.totalQuestions}题 / ${manifest.chapters.length}章`);
