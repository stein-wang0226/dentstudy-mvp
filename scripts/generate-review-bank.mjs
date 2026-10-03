import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// 仅用于审阅：不接入应用、不修改远程仓库，也不覆盖既有题库。
const source = '/Users/hydrogen/Desktop/考研资料/kouwai.doc';
const target = 'review/kouwai-1200-json';
const lines = execFileSync('textutil', ['-convert', 'txt', '-stdout', source], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 })
  .split(/\r?\n/).map(x => x.replace(/\s+/g, ' ').trim());
const ranges = [
  ['绪论 病历规范与临床检查',1,324],['消毒灭菌与手术基本操作',325,614],['局部麻醉',615,884],['牙及牙槽外科',885,1485],['种植外科基础',1486,1765],['种植骨增量与并发症',1766,2105],['口腔颌面部感染',2106,2700],['颌面部创伤急救',2701,3120],['颌骨骨折',3121,3519],['骨折愈合与固定',3520,3618],['口腔颌面肿瘤总论',3619,3900],['颌骨囊肿',3901,4140],['脉管畸形与血管瘤',4141,4366],['颌骨纤维性病变',4367,4550],['口腔癌与颈淋巴结',4551,4766],['唾液腺疾病',4767,4939],['口底囊性病变',4940,5030],['口腔黏膜与颌面软组织病变',5031,5150],['颞下颌关节疾病',5151,5321],['三叉神经痛与面神经麻痹',5322,5536],['唇腭裂',5537,5693],['阻塞性睡眠呼吸障碍',5694,5787],['正颌外科',5788,6039],['显微外科与游离组织瓣',6040,6400]
];
const replacements = [
  ['正常',['异常','病理性','不正常']], ['上颌',['下颌','颧骨','颈部']], ['下颌',['上颌','颧骨','颈部']],
  ['急性',['慢性','复发性','陈旧性']], ['慢性',['急性','亚急性','复发性']], ['良性',['恶性','交界性','非肿瘤性']],
  ['恶性',['良性','交界性','非肿瘤性']], ['增加',['减少','不变','消失']], ['减少',['增加','不变','持续']],
  ['早期',['晚期','终末期','恢复期']], ['术后',['术前','麻醉前','拆线后']], ['术前',['术后','麻醉后','拆线后']],
  ['适应证',['禁忌证','相对禁忌证','非适应证']], ['禁忌证',['适应证','常规指征','首选指征']],
  ['局部',['全身','远隔','非局部']], ['全身',['局部','单一器官','非全身']], ['单侧',['双侧','中线','对侧']],
  ['内固定',['外固定','不固定','单纯观察']], ['手术',['保守','观察','非手术']], ['保守',['手术','侵入性','根治性']]
];
function useful(s) {
  return s.length >= 18 && s.length <= 145 && /[\u4e00-\u9fff]/.test(s) && /[，。；：、]/.test(s)
    && !/^(第?[一二三四五六七八九十]+[、.．]|[（(]?[一二三四五六七八九十]+[）)]|\d+[.、])/.test(s)
    && !/^(定义|分类|病因|治疗|临床表现|适应证|禁忌证|注意事项|手术方法|操作步骤|鉴别诊断|检查方法|诊断依据|治疗原则)$/.test(s)
    && !/^第[一二三四五六七八九十]+节/.test(s);
}
function falseVariants(fact) {
  const out = [];
  const number = fact.match(/\d+(?:\.\d+)?(?=\s*(?:cm|mm|小时|h|天|周|个月|年|次|%|例|枚|指))/);
  if (number) {
    const value = Number(number[0]);
    for (const n of [value + 1, value + 2, value ? Math.max(0.1, value / 2) : 1]) out.push(fact.slice(0, number.index) + n + fact.slice(number.index + number[0].length));
  }
  for (const [from, choices] of replacements) {
    if (!fact.includes(from)) continue;
    for (const to of choices) out.push(fact.replace(from, to));
  }
  return [...new Set(out)].filter(x => x !== fact).slice(0, 3);
}
function question(fact, chapter, id) {
  const distractors = falseVariants(fact);
  if (distractors.length < 3) return null;
  const answerIndex = (id * 11 + 1) % 4;
  const options = distractors.slice(0, 3); options.splice(answerIndex, 0, fact);
  return {
    id: `KOWAI-${String(id).padStart(4, '0')}`,
    chapter,
    stem: `关于“${chapter}”的相关知识，下列描述正确的是：`,
    options,
    answer: 'ABCD'[answerIndex],
    answerIndex,
    explanation: `依据讲义原文：${fact}`
  };
}
rmSync(target, { recursive: true, force: true }); mkdirSync(target, { recursive: true });
let id = 1; const manifest = { title: '口腔颌面外科学 1200 题审阅稿', source: 'kouwai.doc', totalQuestions: 0, chapters: [] };
const pools = [];
for (let i = 0; i < ranges.length; i++) {
  const [name, begin, end] = ranges[i];
  const candidates = lines.slice(begin - 1, end).filter(useful).map(x => question(x, name, id)).filter(Boolean);
  if (candidates.length < 15) throw new Error(`${name} 可形成的严谨变式不足 15 题：${candidates.length}`);
  pools.push({ name, candidates, take: Math.min(50, candidates.length) });
}
let remaining = 1200 - pools.reduce((sum, x) => sum + x.take, 0);
for (const pool of pools) {
  const extra = Math.min(remaining, pool.candidates.length - pool.take);
  pool.take += extra; remaining -= extra;
}
if (remaining > 0) throw new Error(`严谨变式总量不足 1200，尚缺 ${remaining} 题`);
for (let i = 0; i < pools.length; i++) {
  const { name, candidates, take } = pools[i];
  const questions = candidates.slice(0, take).map(q => ({ ...q, id: `KOWAI-${String(id++).padStart(4, '0')}` }));
  const file = `${String(i + 1).padStart(2, '0')}-${name}.json`;
  writeFileSync(join(target, file), JSON.stringify({ chapter: name, questions }, null, 2));
  manifest.chapters.push({ name, file, count: questions.length }); manifest.totalQuestions += questions.length;
}
if (manifest.totalQuestions !== 1200) throw new Error(`预期 1200 题，实际 ${manifest.totalQuestions} 题`);
writeFileSync(join(target, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`审阅题库已生成：${manifest.totalQuestions} 题，${manifest.chapters.length} 章。`);
