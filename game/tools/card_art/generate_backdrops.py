#!/usr/bin/env python3
"""季节背景（16:9）：同一座神殿庭院在四季与天灾里的样子。复用 generate_art.py 的 API 调用与密钥读取。

产物：game/assets/art/bg_<id>.png（1920 宽）
用法：python game/tools/card_art/generate_backdrops.py [--only spring,winter] [--force]
"""
from __future__ import annotations

import argparse
import io
import time

from PIL import Image, ImageEnhance

from generate_art import CACHE, OUT_DIR, api_key, call_api

BASE = ("Wide cinematic panoramic matte painting, flat graphic poster style with engraved fine line texture and paper "
        "grain, muted antique palette (cream, ochre, terra cotta, olive, charcoal, gold). An ancient ruined Mediterranean "
        "classical Greek marble temple courtyard seen from inside (Doric columns, plain stone, NO Chinese or Asian "
        "architecture, NO pagodas, NO curved tiled roofs): tall classical columns and broken arches frame the LEFT and RIGHT edges "
        "symmetrically, a wide open empty stone floor in the CENTER (keep the center calm, low detail and slightly "
        "darker, it will be covered by a game board), sky visible above. No people, no text, no letters, no frame, "
        "no border. ")

SPEC = {
    "spring": "Spring dawn: soft pale green and rose sky, blossoming branches with white petals drifting between "
              "the columns, fresh moss on the stones, gentle morning light from the left.",
    "summer": "Summer noon: bright warm golden sky, strong sunlight and crisp shadows, vines heavy with leaves "
              "climbing the columns, shimmering heat haze, cicada summer feeling.",
    "autumn": "Autumn dusk: deep orange and amber sunset sky, long low sunbeams, red and golden leaves falling, "
              "warm nostalgic glow on the marble.",
    "winter": "Winter night: deep blue moonlit sky with a large pale moon and stars, snow on the column capitals and "
              "the floor edges, cold silver light, quiet and still.",
    "calamity": "Calamity storm: dark bruised purple and red sky, heavy storm clouds, distant lightning, wind tearing "
                "leaves, ominous dramatic light, cracked columns.",
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    only = {x for x in a.only.split(",") if x}
    key = api_key()
    CACHE.mkdir(parents=True, exist_ok=True)
    for sid, desc in SPEC.items():
        if only and sid not in only:
            continue
        out = OUT_DIR / f"bg_{sid}.png"
        if out.exists() and not a.force:
            print("skip", out.name)
            continue
        print("gen", out.name, flush=True)
        try:
            raw = call_api(key, BASE + desc, "16:9")
        except Exception as e:  # noqa: BLE001
            print("  !! 失败:", e)
            continue
        (CACHE / f"bg_{sid}.jpg").write_bytes(raw)
        im = Image.open(io.BytesIO(raw)).convert("RGB")
        im = ImageEnhance.Color(im).enhance(0.92)
        im = im.resize((1920, int(1920 * im.size[1] / im.size[0])), Image.LANCZOS)
        im.save(out)
        print("  ->", out.name, im.size)
        time.sleep(1.0)


if __name__ == "__main__":
    main()
