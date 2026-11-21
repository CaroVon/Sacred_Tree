"""新流派牌的数据表 → data/cards/*.tres。

用法（在 game/ 目录下）：python tools/cards/make_cards.py
只生成/覆盖本表里列出的牌，不动原有的木系牌。数值在阶段 E 统一校准，改这里再重跑即可。

字段与 core/card_def.gd 一一对应；没写的字段用 CardDef 的默认值。
Effect：NONE 0 / ADD 1 / ADD_DEPTH 2 / MUL 3 / SUB_CLAMP 4 / GRAFT 5
Category：CONDUCT 0 / BRANCH 1 / END 2 / AURA 3 / GRAFT 4 / TIME 5 / PRUNE 6
"""
import os

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'cards')

NONE, ADD, ADD_DEPTH, MUL, SUB, GRAFT = range(6)
CONDUCT, BRANCH, END, AURA, GRAFTC, TIME, PRUNE = range(7)

CARDS = [
    # ---------------- 齿轮：联动 / 集群 ----------------
    dict(id='gear_cog', name='齿轮', family=['gear'], kw=['conduct', 'link'], rarity=0, price=3,
         category=CONDUCT, ports=[0], effect=ADD, value=2, adj_family_add=3,
         desc='+{value}；每个相邻的齿轮牌再 +{adj_family_add}'),
    dict(id='gear_link', name='联动齿轮', family=['gear'], kw=['conduct', 'link'], rarity=1, price=6,
         category=CONDUCT, ports=[0], effect=MUL, value=1, adj_family_mul=1.5,
         desc='×(1 + {adj_family_mul}×相邻齿轮牌数)'),
    dict(id='gear_hub', name='枢纽', family=['gear'], kw=['link'], rarity=2, price=7,
         category=GRAFTC, ports=[], effect=GRAFT, value=2, graft_sum=True, graft_family='gear',
         graft_count_mul=True,
         desc='放在挨着 2 张以上齿轮牌的空格，把它们接起来：流出 = 它们的流出之和 ×{value} × 张数'),
    dict(id='gear_rivet', name='铆钉', family=['gear'], kw=['conduct'], rarity=0, price=2,
         category=CONDUCT, ports=[0], effect=ADD, value=1, innate_tough=True,
         desc='+1；天生坚韧（不枯萎，天灾伤不到）'),
    dict(id='gear_diff', name='差速器', family=['gear'], kw=['link'], rarity=0, price=4,
         category=BRANCH, ports=[-1, 1], effect=NONE, value=0, adj_family_add=1,
         desc='向左右分枝；每个相邻的齿轮牌 +{adj_family_add}'),
    dict(id='gear_shaft', name='传动轴', family=['gear'], kw=['conduct'], rarity=1, price=5,
         category=CONDUCT, ports=[0], effect=ADD, value=0, copy_max_neighbor=True,
         desc='流入取“父牌”和“相邻已结算的牌”中最高的流出'),
    dict(id='gear_escape', name='擒纵', family=['gear'], kw=['tip'], rarity=1, price=4,
         category=AURA, ports=[], effect=NONE, value=0, aura_tip_mul=1.0,
         desc='末端，不加值；相邻其他末梢的收获 ×{tip_mul}'),
    dict(id='gear_core', name='机芯', family=['gear'], kw=['tip', 'link'], rarity=2, price=6,
         category=END, ports=[], effect=MUL, value=1, family_count_mul=1.5,
         desc='末端；×(1 + {family_count_mul}×牌桌上的齿轮牌数)'),
    dict(id='gear_spring', name='发条', family=['gear'], kw=['tip', 'timing'], rarity=1, price=4,
         category=END, ports=[], effect=MUL, value=1, mature_step=1.0, mature_cap=6.0,
         desc='末端 ×{value}；每次脉动后倍率 +{mature_step}，最多 ×{mature_max}'),

    # ---------------- 熔炉：燃料（任何牌离开牌桌 = 火候 +1） ----------------
    dict(id='forge_coal', name='炭', family=['forge'], kw=['conduct', 'fuel'], rarity=0, price=2,
         category=CONDUCT, ports=[0], effect=ADD, value=3, heat_on_burn=4,
         desc='+{value}；燃烧（离开牌桌）时火候额外 +{heat_on_burn}'),
    dict(id='forge_furnace', name='熔炉', family=['forge'], kw=['conduct', 'fuel'], rarity=1, price=7,
         category=CONDUCT, ports=[0], effect=MUL, value=1, heat_mul=0.8, innate_tough=True,
         desc='×(1 + {heat_mul}×火候)；天生耐火（不枯萎，天灾伤不到）。火候整局累积'),
    dict(id='forge_ember', name='余烬', family=['forge'], kw=['tip', 'fuel'], rarity=1, price=4,
         category=END, ports=[], effect=ADD, value=6, burn_total_mult=1.0,
         desc='+{value}，末端；燃烧时，下次脉动总分 ×2（可叠加）'),
    dict(id='forge_altar', name='祭坛', family=['forge'], kw=['tip', 'fuel'], rarity=1, price=4,
         category=AURA, ports=[], effect=NONE, value=0, burn_adjacent=True,
         desc='末端；每次脉动后烧掉相邻收获最低的末梢（回到弃牌堆，坚韧的除外）'),
    dict(id='forge_kindle', name='火种', family=['forge'], kw=['fuel'], rarity=0, price=3,
         category=BRANCH, ports=[-1, 1], effect=ADD, value=1, heat_on_burn=3,
         desc='+{value}，向左右分枝；燃烧时火候额外 +{heat_on_burn}'),
    dict(id='forge_anvil', name='铁砧', family=['forge'], kw=['conduct', 'timing'], rarity=0, price=3,
         category=CONDUCT, ports=[0], effect=MUL, value=2, mature_step=-0.25, mature_cap=1.0,
         desc='×2；每次脉动后倍率 −0.25，最低 ×1（冷了就烧掉它）'),
    dict(id='forge_ash', name='灰烬', family=['forge'], kw=['tip', 'fuel'], rarity=1, price=4,
         category=END, ports=[], effect=ADD, value=0, burned_add=3,
         desc='末端；+{burned_add}×本局累计燃烧的牌数'),
    dict(id='forge_phoenix', name='凤凰羽', family=['forge'], kw=['tip', 'fuel'], rarity=2, price=6,
         category=END, ports=[], effect=MUL, value=4, heat_on_burn=5,
         desc='末端 ×{value}；燃烧时火候额外 +{heat_on_burn}'),
    dict(id='forge_bellows', name='风箱', family=['forge'], kw=['tip', 'fuel'], rarity=0, price=3,
         category=AURA, ports=[], effect=NONE, value=0, pulse_heat=3,
         desc='末端，不加值；每次脉动火候 +{pulse_heat}'),

    # ---------------- 星辰：时机 ----------------
    dict(id='star_sand', name='星砂', family=['star'], kw=['conduct', 'timing'], rarity=0, price=3,
         category=CONDUCT, ports=[0], effect=ADD, value=0, turn_add=4,
         desc='+{turn_add}×当前回合数'),
    dict(id='star_moon', name='满月', family=['star'], kw=['tip', 'timing'], rarity=1, price=5,
         category=END, ports=[], effect=MUL, value=1, turn_mul=True,
         desc='末端；×当前回合数（第 5 回合 ×5）'),
    dict(id='star_tide', name='潮汐', family=['star'], kw=['conduct', 'timing'], rarity=0, price=4,
         category=CONDUCT, ports=[0], effect=MUL, value=1, odd_turn_mul=3,
         desc='奇数回合 ×{odd_turn_mul}，偶数回合不变'),
    dict(id='star_meteor', name='流星', family=['star'], kw=['tip', 'timing'], rarity=1, price=4,
         category=END, ports=[], effect=ADD, value=2, last_turn_mult=6,
         desc='+{value}，末端；每季最后一回合 ×{last_turn_mult}'),
    dict(id='star_chart', name='星图', family=['star'], kw=['timing'], rarity=2, price=7,
         category=AURA, ports=[], effect=NONE, value=0, star_total_mult=0.1,
         desc='末端；整树总分 ×(1 + {star_total_mult}×牌桌上的星辰牌数)，多张星图叠乘'),
    dict(id='star_dial', name='日晷', family=['star'], kw=['conduct', 'timing'], rarity=0, price=4,
         category=CONDUCT, ports=[0], effect=MUL, value=1, season_mul=True,
         desc='×季节序号（春 1、夏 2、秋 3、冬与天灾 4）'),
    dict(id='star_comet', name='彗尾', family=['star'], kw=['tip'], rarity=1, price=4,
         category=END, ports=[], effect=ADD, value=3, depth_bonus=3,
         desc='+3，末端；计算长茎时深度 +3'),
    dict(id='star_astrolabe', name='星盘', family=['star'], kw=['timing'], rarity=0, price=3,
         category=BRANCH, ports=[-1, 0, 1], effect=SUB, value=1,
         desc='−1，向前与左右三个方向分枝；星辰牌排成直线 3 张以上成「连星」，流出 ×2'),

    # ---------------- 商会：养分 ----------------
    dict(id='coin_copper', name='铜币', family=['coin'], kw=['tip', 'sap'], rarity=0, price=3,
         category=END, ports=[], effect=ADD, value=3, pulse_sap=2,
         desc='+{value}，末端；每次脉动得 {pulse_sap} 养分'),
    dict(id='coin_bank', name='银行', family=['coin'], kw=['conduct', 'sap'], rarity=1, price=5,
         category=CONDUCT, ports=[0], effect=ADD, value=0, sap_add=3,
         desc='+{sap_add}×当前养分'),
    dict(id='coin_vault', name='金库', family=['coin'], kw=['tip', 'sap'], rarity=2, price=6,
         category=END, ports=[], effect=MUL, value=1, sap_mul=0.3,
         desc='末端；×(1 + {sap_mul}×养分)'),
    dict(id='coin_contract', name='契约', family=['coin'], kw=['conduct', 'sap'], rarity=1, price=5,
         category=CONDUCT, ports=[0], effect=MUL, value=5, pulse_cost=2,
         desc='×{value}；每次脉动花 {pulse_cost} 养分，养分不够时流出 0'),
    dict(id='coin_bond', name='债券', family=['coin'], kw=['sap'], rarity=1, price=4,
         category=AURA, ports=[], effect=NONE, value=0, interest=0.1,
         desc='末端；每回合末养分 +10%（每张最多 +5）'),
    dict(id='coin_caravan', name='驼队', family=['coin'], kw=['sap'], rarity=0, price=3,
         category=BRANCH, ports=[-1, 0, 1], effect=NONE, value=0, play_cost=3,
         desc='向三个方向分枝且不减值；放下时花 3 养分'),
    dict(id='coin_pawn', name='当铺', family=['coin'], kw=['tip', 'sap'], rarity=1, price=4,
         category=END, ports=[], effect=MUL, value=2, prune_out_sap=0.5,
         desc='×2，末端；被剪掉时额外得到它流出一半的养分'),
    dict(id='coin_ledger', name='账本', family=['coin'], kw=['conduct', 'sap'], rarity=1, price=4,
         category=CONDUCT, ports=[0], effect=ADD, value=0, spent_add=0.5,
         desc='+{spent_add}×本局在集市累计花费的养分'),
    dict(id='coin_horn', name='丰饶角', family=['coin'], kw=['tip'], rarity=2, price=7,
         category=END, ports=[], effect=MUL, value=1, relic_mul=True,
         desc='末端；×(器物数 + 1)'),

    # ---------------- 镜像：对称位置 ----------------
    dict(id='mirror_silver', name='银镜', family=['mirror'], kw=['conduct', 'mirror'], rarity=1, price=6,
         category=CONDUCT, ports=[0], effect=ADD, value=0, mirror_copy=5,
         desc='流出至少是点对称位置那张牌流出的 {mirror_copy} 倍（对面先放的才算）'),
    dict(id='mirror_echo', name='倒影', family=['mirror'], kw=['tip', 'mirror'], rarity=1, price=4,
         category=END, ports=[], effect=ADD, value=3, mirror_tip=True,
         desc='+{value}，末端；收获至少等于对称位置末梢的收获'),
    dict(id='mirror_frame', name='镜框', family=['mirror'], kw=['conduct', 'mirror'], rarity=0, price=3,
         category=CONDUCT, ports=[0], effect=ADD, value=3, mirror_same_mult=4,
         desc='+{value}；对称位置也是镜框时 ×{mirror_same_mult}'),
    dict(id='mirror_phantom', name='幻影', family=['mirror'], kw=['mirror'], rarity=1, price=4,
         category=END, ports=[], effect=ADD, value=6, wild=True,
         desc='+{value}，末端；共鸣计数时还算作离下一阈值最近的另一个流派'),
    dict(id='mirror_kaleido', name='万花筒', family=['mirror'], kw=['tip', 'mirror'], rarity=1, price=5,
         category=END, ports=[], effect=ADD, value=0, pair_add=16,
         desc='末端；牌桌上每有一对对称的同类牌 +{pair_add}'),
    dict(id='mirror_prism', name='棱镜', family=['mirror'], kw=['mirror'], rarity=0, price=3,
         category=BRANCH, ports=[-2, 2], effect=ADD, value=1,
         desc='+{value}，向左右后方两个方向分枝，方便摆出对称的形状'),
    dict(id='mirror_twin', name='双子', family=['mirror'], kw=['mirror'], rarity=1, price=4,
         category=BRANCH, ports=[-1, 1], effect=ADD, value=2, mirror_same_mult=3,
         desc='+{value}，向左右分枝；对称位置也是双子时 ×{mirror_same_mult}'),
    dict(id='mirror_glass', name='镜面', family=['mirror'], kw=['tip', 'mirror'], rarity=0, price=2,
         category=END, ports=[], effect=ADD, value=6,
         desc='+{value}，末端；便宜的对称材料'),

    # ---------------- 封印：封存 ----------------
    dict(id='seal_box', name='封印匣', family=['seal'], kw=['store'], rarity=1, price=6,
         category=AURA, ports=[], effect=NONE, value=0, seal_adjacent=True, seal_rate=1.2,
         desc='末端；相邻末梢的收获存进匣里（当回合不计分）。季末或提前收获时释放：存量 ×(1 + {seal_rate}×封存次数)'),
    dict(id='seal_wax', name='蜡封', family=['seal'], kw=['tip', 'store'], rarity=0, price=3,
         category=END, ports=[], effect=ADD, value=4, seal_self=True, seal_rate=1.2,
         desc='+{value}，末端；自己的收获封存，季末释放 ×(1 + {seal_rate}×封存次数)'),
    dict(id='seal_rune', name='符文石', family=['seal'], kw=['conduct', 'store'], rarity=0, price=3,
         category=CONDUCT, ports=[0], effect=ADD, value=3, release_adj_bonus=0.5,
         desc='+{value}；相邻封印牌释放时，每次封存的倍率再 +{release_adj_bonus}'),
    dict(id='seal_ward', name='护符', family=['seal'], kw=['store'], rarity=1, price=4,
         category=AURA, ports=[], effect=ADD, value=2, aura_tough=True,
         desc='+{value}，末端；相邻的牌视为坚韧（不枯萎，天灾伤不到）'),
    dict(id='seal_thunder', name='雷印', family=['seal'], kw=['tip', 'timing'], rarity=1, price=4,
         category=END, ports=[], effect=MUL, value=2, calamity_mult=3,
         desc='×{value}，末端；天灾季再 ×{calamity_mult}'),
    dict(id='seal_break', name='解印', family=['seal'], kw=['conduct', 'store'], rarity=2, price=5,
         category=CONDUCT, ports=[0], effect=ADD, value=1, release_on_prune=2,
         desc='+1；被剪掉时立即释放牌桌上全部封存，再 ×2'),
    dict(id='seal_hoard', name='秘藏', family=['seal'], kw=['tip', 'store'], rarity=1, price=6,
         category=END, ports=[], effect=MUL, value=3, seal_self=True, seal_rate=1.0,
         desc='×{value}，末端；自己的收获封存，季末释放 ×(1 + {seal_rate}×封存次数)'),
    dict(id='seal_chain', name='锁链', family=['seal'], kw=['store'], rarity=0, price=3,
         category=BRANCH, ports=[-1, 1], effect=NONE, value=0, seal_feed=3,
         desc='向左右分枝；每次脉动给相邻封印牌的存量 +{seal_feed}'),

    # ---------------- 双流派桥牌（同时算进两个流派的共鸣） ----------------
    dict(id='bridge_bell', name='青铜钟', family=['gear', 'star'], kw=['link', 'timing'], rarity=1, price=5,
         category=CONDUCT, ports=[0], effect=ADD, value=1, adj_family_add=1, last_turn_mult=3,
         desc='+1；每个相邻的齿轮或星辰牌 +1；每季最后一回合 ×3'),
    dict(id='bridge_mint', name='铸币炉', family=['forge', 'coin'], kw=['fuel', 'sap'], rarity=1, price=5,
         category=AURA, ports=[], effect=NONE, value=0, sap_on_burn=1,
         desc='末端；牌桌上每燃烧一张牌，得 1 养分'),
    dict(id='bridge_starfire', name='星火', family=['forge', 'star'], kw=['fuel', 'timing'], rarity=1, price=4,
         category=CONDUCT, ports=[0], effect=ADD, value=2, heat_on_burn_turn=True,
         desc='+2；燃烧时火候额外 + 当前回合数'),
    dict(id='bridge_goldgear', name='金齿轮', family=['gear', 'coin'], kw=['link', 'sap'], rarity=1, price=5,
         category=CONDUCT, ports=[0], effect=ADD, value=2, adj_family_add=2, pulse_sap=1,
         desc='+2；每个相邻的齿轮或商会牌 +2；每次脉动得 1 养分'),
    dict(id='bridge_lockvine', name='锁藤', family=['wood', 'gear'], kw=['link'], rarity=2, price=6,
         category=GRAFTC, ports=[], effect=GRAFT, value=0,
         desc='同藤：放在挨着 2 个以上末梢的空格，养分相乘；同时算作齿轮牌'),
    dict(id='bridge_spiritfruit', name='灵果', family=['wood', 'star'], kw=['tip', 'timing'], rarity=2, price=6,
         category=END, ports=[], effect=MUL, value=2, mature_step=0.5, mature_cap=2.0, last_turn_mult=2,
         desc='×2，末端；每次脉动倍率 +0.5（最多 ×4）；每季最后一回合再 ×2'),
    dict(id='bridge_mirrorforge', name='镜炉', family=['mirror', 'forge'], kw=['fuel', 'mirror'], rarity=2, price=6,
         category=CONDUCT, ports=[0], effect=MUL, value=1, heat_mul=0.1, mirror_same_mult=2,
         desc='×(1 + 0.1×火候)；对称位置也是镜炉时再 ×2'),
    dict(id='bridge_sealcoin', name='封金匣', family=['seal', 'coin'], kw=['store', 'sap'], rarity=1, price=4,
         category=END, ports=[], effect=ADD, value=2, seal_self=True, pulse_sap=1,
         desc='+2，末端；自己的收获封存，季末释放；每次脉动得 1 养分'),
]

COLOR = {'wood': 'gold', 'gear': 'steel', 'forge': 'ember', 'star': 'astral', 'coin': 'coin', 'mirror': 'mirror', 'seal': 'seal'}

SIMPLE = ['adj_family_add', 'adj_family_mul', 'family_count_mul', 'heat_mul', 'burned_add', 'aura_tip_mul',
          'pulse_sap', 'pulse_heat', 'heat_on_burn', 'burn_total_mult', 'mature_step', 'mature_cap',
          'min_depth', 'aura', 'aura_conduct', 'prune_value', 'graft_min', 'ripen_age', 'ripe_value',
          'turn_add', 'odd_turn_mul', 'last_turn_mult', 'star_total_mult', 'depth_bonus',
          'sap_add', 'sap_mul', 'pulse_cost', 'interest', 'play_cost', 'prune_out_sap', 'spent_add',
          'mirror_copy', 'mirror_same_mult', 'pair_add', 'seal_rate', 'release_adj_bonus', 'calamity_mult',
          'release_on_prune', 'seal_feed', 'sap_on_burn']
BOOLS = ['copy_max_neighbor', 'graft_count_mul', 'burn_adjacent', 'innate_tough', 'graft_sum', 'exhaust_on_prune',
         'turn_mul', 'season_mul', 'relic_mul', 'mirror_tip', 'wild', 'seal_adjacent', 'seal_self', 'aura_tough',
         'heat_on_burn_turn']


def fmt(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, float):
        return repr(v)
    return str(v)


def sn_array(xs):
    return 'Array[StringName]([%s])' % ', '.join('&"%s"' % x for x in xs)


def num(v):
    if isinstance(v, bool):
        return str(v)
    v = float(v)
    return str(int(v)) if v == int(v) else ('%.2f' % v).rstrip('0').rstrip('.')


def fill_desc(c):
    """描述里的 {字段} 替换成当前数值，调数值时描述自动跟着变。"""
    vals = {k: num(v) for k, v in c.items() if isinstance(v, (int, float))}
    vals.setdefault('seal_rate', num(0.5))
    vals['tip_mul'] = num(1 + float(c.get('aura_tip_mul', 0)))
    vals['mature_max'] = num(float(c.get('value', 0)) + float(c.get('mature_cap', 0)))
    return c['desc'].format(**vals)


def write(c):
    lines = [
        '[gd_resource type="Resource" script_class="CardDef" format=3]', '',
        '[ext_resource type="Script" path="res://core/card_def.gd" id="1"]', '',
        '[resource]', 'script = ExtResource("1")',
        'id = &"%s"' % c['id'],
        'display_name = "%s"' % c['name'],
        'category = %d' % c['category'],
        'ports = PackedInt32Array(%s)' % ', '.join(str(p) for p in c['ports']),
        'effect = %d' % c['effect'],
        'value = %s' % float(c['value']),
        'color_key = &"%s"' % COLOR[c['family'][0]],
        'price = %d' % c['price'],
        'rarity = %d' % c['rarity'],
        'family = %s' % sn_array(c['family']),
        'keywords = %s' % sn_array(c['kw']),
        'desc = "%s"' % fill_desc(c),
    ]
    for k in SIMPLE:
        if k in c:
            lines.append('%s = %s' % (k, fmt(c[k])))
    for k in BOOLS:
        if c.get(k):
            lines.append('%s = true' % k)
    if c.get('graft_family'):
        lines.append('graft_family = &"%s"' % c['graft_family'])
    path = os.path.join(OUT, c['id'] + '.tres')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    for c in CARDS:
        write(c)
    print('wrote', len(CARDS), 'cards')
