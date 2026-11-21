"""检查标题字体里有没有「实心方块」式的坏字形（比如 ZCOOL XiaoWei 的「回」）。

用法: python game/tools/fonts/check_glyphs.py [字体路径]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
FONT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "game/assets/fonts/ZCOOLXiaoWei-Regular.ttf"

SIZE = 64


def solid_rect(ch: str, font: ImageFont.FreeTypeFont) -> bool:
    """字形是不是一块填死的方块。"""
    im = Image.new("L", (SIZE * 2, SIZE * 2), 0)
    ImageDraw.Draw(im).text((SIZE // 2, SIZE // 2), ch, font=font, fill=255)
    bbox = im.getbbox()
    if not bbox:
        return False
    im = im.crop(bbox)
    w, h = im.size
    if w < SIZE * 0.45 or h < SIZE * 0.45:
        return False  # 太小的字形不算方块
    px = im.load()
    filled = 0
    total = w * h
    for y in range(h):
        for x in range(w):
            if px[x, y] > 128:
                filled += 1
    ratio = filled / total
    # 实心方块：填充率极高，而且宽高比接近 1
    return ratio > 0.78 and 0.75 < w / h < 1.33


def main() -> None:
    font = ImageFont.truetype(str(FONT), SIZE)
    # 游戏里可能用到的全部汉字
    chars = set()
    for pat in ("game/**/*.gd", "game/**/*.tres", "game/**/*.tscn", "*.html", "*.md"):
        for p in ROOT.glob(pat):
            chars |= set(p.read_text(encoding="utf-8", errors="ignore"))
    chars = sorted(c for c in chars if ord(c) > 0x2E80)
    bad = [c for c in chars if solid_rect(c, font)]
    print(f"字体: {FONT.name}")
    print(f"检查 {len(chars)} 个汉字，疑似实心方块 {len(bad)} 个")
    if bad:
        print("坏字: " + "".join(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
