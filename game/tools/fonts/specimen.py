import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]

names = []
for sub in ("cards", "relics", "calamities"):
    for p in (ROOT / "game" / "data" / sub).glob("*.tres"):
        t = p.read_text(encoding="utf-8")
        m = re.search(r'display_name = "([^"]*)"', t)
        if m:
            names.append(m.group(1))

extra = (
    "神树牌组图鉴规则与名词春夏秋冬回合结束开始继续退出设置音量减少动效天灾器物集市主菜单返回"
    "本季累计下次脉动预计养分储备牌库弃牌可放可剪输出种字回长茎星芒环对称"
    "第年春季卡牌的效果说明类别小图版本印刷品"
)
chars = sorted(set("".join(names) + extra))

out = Path(sys.argv[1] if len(sys.argv) > 1 else "specimen.png")
im = Image.new("RGB", (40 * len(chars) + 20, 100), (246, 245, 241))
d = ImageDraw.Draw(im)
f = ImageFont.truetype(str(ROOT / "game/assets/fonts/ZCOOLXiaoWei-Regular.ttf"), 56)
for i, c in enumerate(chars):
    d.text((20 + i * 40, 20), c, font=f, fill=(27, 36, 48))
im.save(out)
print("chars", len(chars))
print("".join(chars))
