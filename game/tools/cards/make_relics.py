"""新器物的数据表 → data/relics/*.tres。用法（在 game/ 目录下）：python tools/cards/make_relics.py
效果由 core/run_state.gd / core/pulse.gd 按 id 读取（has_relic）。只覆盖本表列出的器物。"""
import os

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'relics')

FAM = {'gear': '齿轮', 'forge': '熔炉', 'star': '星辰', 'coin': '商会', 'mirror': '镜像', 'seal': '封印'}

RELICS = []
# 流派徽章：共鸣阈值 −1
for f, nm in FAM.items():
    RELICS.append(dict(id='badge_' + f, name=nm + '徽章', price=7, family=f,
                       desc='%s共鸣提前一张激活（1 / 3 / 5 张）' % nm))
RELICS += [
    dict(id='oilcan', name='油壶', price=7, family='gear', desc='齿轮牌的联动加成每张再 +1'),
    dict(id='windkey', name='发条钥匙', price=9, family='gear', desc='每次脉动，牌桌上所有牌的成熟额外 +1'),
    dict(id='tongs', name='火钳', price=6, family='forge', desc='每季开始时火候 +5'),
    dict(id='firebrick', name='耐火砖', price=8, family='forge', desc='熔炉牌都视为坚韧'),
    dict(id='orrery', name='星象仪', price=8, family='star', desc='星辰牌计算回合数时 +1'),
    dict(id='hourglass', name='沙漏', price=10, family='star', desc='四季每季多 1 回合（天灾季除外）'),
    dict(id='piggy', name='存钱罐', price=6, family='coin', desc='每回合末，每有 5 养分再 +1（最多 +3）'),
    dict(id='scales', name='天平', price=6, family='coin', desc='集市的服务与删牌都便宜 1 养分（最低 1）'),
    dict(id='twofaced', name='双面镜', price=8, family='mirror', desc='对称的牌对不再要求同类，两边都有牌就算一对'),
    dict(id='silvering', name='镀银', price=7, family='mirror', desc='镜阵每一对的总分加成再 +5%'),
    dict(id='signet', name='蜡印', price=7, family='seal', desc='封存释放时，每次封存的倍率再 +0.25'),
    dict(id='timebox', name='时光匣', price=9, family='seal', desc='提前收获时，剩余每回合都算作多封存一次'),
    dict(id='cart', name='手推车', price=7, family='', desc='每回合可以多移栽 1 次'),
    dict(id='lantern', name='提灯', price=5, family='', desc='集市多摆 1 件器物'),
    dict(id='almanac', name='历书', price=8, family='', desc='天灾季的目标 ×0.8'),
    dict(id='compass', name='罗盘', price=6, family='', desc='季末选牌时，至少一个选项来自你牌组里最多的新流派'),
]


def write(r):
    lines = [
        '[gd_resource type="Resource" script_class="RelicDef" format=3]', '',
        '[ext_resource type="Script" path="res://core/relic_def.gd" id="1"]', '',
        '[resource]', 'script = ExtResource("1")',
        'id = &"%s"' % r['id'],
        'display_name = "%s"' % r['name'],
        'desc = "%s"' % r['desc'],
        'price = %d' % r['price'],
        'family = &"%s"' % r['family'],
    ]
    with open(os.path.join(OUT, r['id'] + '.tres'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    for r in RELICS:
        write(r)
    print('wrote', len(RELICS), 'relics')
