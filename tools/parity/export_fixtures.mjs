// 从网页原型中抽出规则代码（配置 → 行动 之间的部分），对随机生成的树记录 golden 结果，
// 供 Godot 端 tests/test_parity.gd 逐步比对。
// 用法：node tools/parity/export_fixtures.mjs shentree_prototype.html game/tests/fixtures/parity.json
import fs from 'node:fs';

const [, , htmlPath, outPath] = process.argv;
const html = fs.readFileSync(htmlPath, 'utf8');
const js = html.split('<script>')[1].split('</script>')[0];
const core = js.slice(js.indexOf('// ---------- 配置'), js.indexOf('// ---------- 行动'));
const P = new Function(core + `
;return {C, compute, targetsFor, makeNode, subtree, removeSet, k,
  setS: s => { S = s; }};`)();

function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const TYPES = ['stem', 'node', 'fork', 'tri', 'fruit', 'gold', 'flower', 'vine', 'dead'];
const WEIGHTS = [4, 2, 4, 2, 3, 1, 2, 3, 2];
const pickType = rnd => {
  let x = rnd() * WEIGHTS.reduce((a, b) => a + b, 0);
  for (let i = 0; i < TYPES.length; i++) { x -= WEIGHTS[i]; if (x < 0) return TYPES[i]; }
  return TYPES[0];
};
const parseKey = s => s.split(',').map(Number);
const outObj = out => Object.fromEntries(Object.entries(out));

const scenarios = [];
for (let sc = 0; sc < 60; sc++) {
  const rnd = mulberry32(1000 + sc);
  const season = 1 + (sc % 4);
  const S = { season, nodes: new Map(), order: 0 };
  S.nodes.set('0,0', { key: '0,0', q: 0, r: 0, type: 'seed', parents: [], children: [], facing: null, depth: 0, order: S.order++ });
  P.setS(S);
  const steps = [];
  for (let st = 0; st < 40; st++) {
    if (S.nodes.size > 4 && rnd() < 0.1) {
      const keys = [...S.nodes.keys()].filter(x => x !== '0,0');
      const kk = keys[Math.floor(rnd() * keys.length)];
      const set = P.subtree(S.nodes, kk);
      P.removeSet(S.nodes, set);
      const res = P.compute(S.nodes);
      steps.push({ op: 'prune', key: parseKey(kk), removed: set.size, total: res.total, out: outObj(res.out) });
      continue;
    }
    const type = pickType(rnd);
    const tg = P.targetsFor(type);
    if (!tg.size) continue;
    const keys = [...tg.keys()];
    const kk = keys[Math.floor(rnd() * keys.length)];
    const info = tg.get(kk);
    P.makeNode(S.nodes, type, kk, info, S.order++);
    const res = P.compute(S.nodes);
    steps.push({
      op: 'place', type, key: parseKey(kk),
      targets: keys.sort(),
      parents: info.parents.map(parseKey), facing: info.facing ?? -1,
      total: res.total, out: outObj(res.out),
    });
  }
  scenarios.push({ season, steps });
}
fs.writeFileSync(outPath, JSON.stringify(scenarios));
console.log(`wrote ${scenarios.length} scenarios, ${scenarios.reduce((a, s) => a + s.steps.length, 0)} steps -> ${outPath}`);
