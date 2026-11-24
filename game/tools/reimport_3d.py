"""把 3D 牌桌用到的贴图改成生成 mipmap（缩小时不闪烁、不起锯齿），然后需要用 Godot --import 重新导入。

用法（仓库根目录）：
  python game/tools/reimport_3d.py
  tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --import
"""
import glob
import os
import re

ART = os.path.join(os.path.dirname(__file__), '..', 'assets', 'art')
PATTERNS = ['*.png']  # 牌面插画也平铺在 3D 地块上

changed = 0
for pat in PATTERNS:
    for png in glob.glob(os.path.join(ART, pat)):
        imp = png + '.import'
        if not os.path.exists(imp):
            continue
        s = open(imp, encoding='utf-8').read()
        t = re.sub(r'^mipmaps/generate=false', 'mipmaps/generate=true', s, flags=re.M)
        if t != s:
            open(imp, 'w', encoding='utf-8', newline='').write(t)
            changed += 1
print('updated', changed, 'import files')
