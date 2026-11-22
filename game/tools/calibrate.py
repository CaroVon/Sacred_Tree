"""数值校准：并行跑每个主流派的规划者 bot，汇总通关率与每季得分。

用法（在仓库根目录）：
  python game/tools/calibrate.py real 60          # 按当前目标跑，报告每个流派的通关率
  python game/tools/calibrate.py free 60          # 忽略目标跑满三年，按分位数建议目标
  python game/tools/calibrate.py free 60 --q 0.3  # 建议目标取全部流派合并后的第 30 百分位
  python game/tools/calibrate.py real 150 --no-legendary   # 卡池里去掉传说牌（量化传说的贡献）

输出里的“建议目标”可以直接贴进 core/rules.gd 的 TARGETS（已按梯度约束后处理）。
"""
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GODOT = os.path.join(ROOT, 'tools', 'godot', 'Godot_v4.7.2-stable_win64_console.exe')
FAMILIES = ['wood', 'gear', 'forge', 'star', 'coin', 'mirror', 'seal']
SEASONS = ['春', '夏', '秋', '冬', '天灾']
# 2026-11-22 用户决定：全阶段目标都参与校准（第 1 年不再固定），并强化梯度。
FIXED = {}
# 梯度约束：季内每季 ≥ 上一季 ×SEASON_STEP；天灾季 ≥ 冬季；每年春 ≥ 上一年春 ×YEAR_STEP。
# （春季树心输出回落到 ×1，天然比上一年天灾低，所以跨年按春对春比较。）
SEASON_STEP = 2.5
YEAR_STEP = 8.0


def enforce_gradient(t):
    """梯度约束（从后往前）：以后期分位数为锚，压低早期目标，保证陡峭。t: {(年, 季): 目标}。"""
    for y in (3, 2, 1):
        if y < 3:
            t[(y, 1)] = min(t[(y, 1)], t[(y + 1, 1)] / YEAR_STEP)
        t[(y, 4)] = min(t[(y, 4)], t[(y, 5)])
        for s in (3, 2, 1):
            t[(y, s)] = min(t[(y, s)], t[(y, s + 1)] / SEASON_STEP)
        if y < 3:
            t[(y, 1)] = min(t[(y, 1)], t[(y + 1, 1)] / YEAR_STEP)
    for k in t:
        t[k] = nice(t[k])
    return t


def nice_up(v):
    """向上取两位有效数字。"""
    if v < 100:
        return int(v)
    s = len(str(int(v))) - 2
    q = 10 ** s
    return int(-(-int(v) // q) * q)


NOLEGEND = '--no-legendary' in sys.argv
NOPICK = '--no-pick' in sys.argv


def run(family, mode, runs, seed0):
    cmd = [GODOT, '--headless', '--path', os.path.join(ROOT, 'game'), '-s', 'tools/balance_sim.gd', '--',
           str(runs), 'planner', mode, str(seed0), family, 'raw'] + (['nolegend'] if NOLEGEND else []) + (['nopick'] if NOPICK else [])
    out = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=3600).stdout
    raw, ends = [], []
    for line in out.splitlines():
        p = line.split(',')
        if p[0] == 'RAW':
            raw.append((int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5])))
        elif p[0] == 'END':
            ends.append((int(p[1]), int(p[2]), int(p[3]), int(p[4])))
    return family, raw, ends


def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return 0
    return xs[min(len(xs) - 1, max(0, int(q * (len(xs) - 1))))]


def nice(v):
    """取两位有效数字，方便读。"""
    if v < 100:
        return int(v)
    s = len(str(int(v))) - 2
    return int(round(v / 10 ** s) * 10 ** s)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'real'
    runs = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    q = float(sys.argv[sys.argv.index('--q') + 1]) if '--q' in sys.argv else 0.3
    fams = FAMILIES
    if '--only' in sys.argv:
        fams = sys.argv[sys.argv.index('--only') + 1].split(',')
    with ThreadPoolExecutor(max_workers=len(fams)) as ex:
        results = list(ex.map(lambda f: run(f, mode, runs, 1), fams))
    if mode == 'real':
        print('流派     通关率   止步分布（年-季: 局数）')
        rates = {}
        for f, raw, ends in results:
            won = sum(e[1] for e in ends)
            rates[f] = won / max(1, len(ends))
            stops = {}
            for e in ends:
                if not e[1]:
                    k = '%d-%s' % (e[2], SEASONS[e[3] - 1])
                    stops[k] = stops.get(k, 0) + 1
            top = sorted(stops.items(), key=lambda kv: -kv[1])[:4]
            print('%-8s %5.1f%%   %s' % (f, 100 * rates[f], '  '.join('%s:%d' % kv for kv in top)))
        vals = list(rates.values())
        print('平均 %.1f%%，最高-最低 %.1f 个百分点' % (100 * sum(vals) / len(vals), 100 * (max(vals) - min(vals))))
        return
    # free：每季合并所有流派的得分，取分位数作为建议目标
    by_stage = {}
    per_fam = {}
    for f, raw, ends in results:
        for seed, y, s, score, _ in raw:
            by_stage.setdefault((y, s), []).append(score)
            per_fam.setdefault((f, y, s), []).append(score)
    print('季节        ' + '  '.join('%-9s' % f for f in fams) + '  建议目标(q=%.2f)' % q)
    targets = {}
    for y in (1, 2, 3):
        for s in range(1, 6):
            key = (y, s)
            if key not in by_stage:
                continue
            targets[key] = FIXED.get(key, nice(pct(by_stage[key], q)))
    enforce_gradient(targets)
    for y in (1, 2, 3):
        for s in range(1, 6):
            key = (y, s)
            meds = '  '.join('%-9d' % pct(per_fam.get((f, y, s), [0]), 0.5) for f in fams)
            print('%d年%-4s     %s  %d' % (y, SEASONS[s - 1], meds, targets[key]))
    print('\nTARGETS := [')
    for y in (1, 2, 3):
        print('\t[%s],' % ', '.join(str(targets.get((y, s), 0)) for s in range(1, 6)))
    print(']')


if __name__ == '__main__':
    main()
