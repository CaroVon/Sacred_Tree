#!/usr/bin/env python3
"""新美学方向的插画生成：失落文明的古典典藏图册。

方向（与旧的「木刻剪影」完全不同）：
  纵向海报式构图 / 几何拱门与神庙碎片 / 平面色块 / 雕版细线 /
  哑光旧色（奶油白、赭金、焦橙、土红、橄榄、炭灰）/ 星芒符号 / 纸张颗粒

产物：game/assets/art/<id>.png（彩色，直接用于卡面插画区）
用法：
    python game/tools/card_art/generate_art.py                 # 生成全部缺失的
    python game/tools/card_art/generate_art.py --only tree,oak
    python game/tools/card_art/generate_art.py --force
"""
from __future__ import annotations

import argparse
import io
import json
import time
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / "game"
OUT_DIR = GAME / "assets" / "art"
CACHE = Path.home() / "AppData" / "Local" / "Temp" / "opencode" / "artgen"
API = "https://api.minimaxi.com/v1/image_generation"

# ---------------------------------------------------------------- 调色板
CREAM = "#EDE3C9"
OCHRE = "#C9914A"
TERRA = "#B04A2A"
OLIVE = "#7B7A55"
CHARCOAL = "#2B2925"
GOLD = "#B08A46"
SAGE = "#A9A98C"

PALETTE_BLOCK = """
COLOUR (only these flat colours):
cream #EDE3C9  ochre #C9914A  terra #B04A2A  olive #7B7A55
charcoal #2B2925  gold #B08A46  sage #A9A98C
"""

# ---------------------------------------------------------------- 母题表
# id -> (中文名, 画幅, 母题描述, 构图补充)
SPEC: dict[str, tuple[str, str, str, str]] = {
    # —— 标题插画 ——
    "tree": (
        "神树", "3:4",
        "a slender pale silver-white tree in full silhouette, its branches spreading "
        "symmetrically like a candelabra, standing in front of a great flat golden sun "
        "disc; below, the roots spread out into the shape of a classical temple portal "
        "with columns",
        "Use a tall pointed arch behind the tree. Add four-pointed star sparkles.",
    ),
    # —— 传导 ——
    "stem": (
        "茎", "3:4",
        "a single slender pale stem rising straight from a carved stone base, two tiny "
        "buds opening at the very top, the stem drawn as one confident vertical line",
        "Use a tall narrow arch behind. One eight-pointed star at the top.",
    ),
    "node": (
        "节", "3:4",
        "a straight pale stem with one swollen round knuckle in the middle, the knuckle "
        "grown around a fluted column drum",
        "Use a crescent moon behind. Two four-pointed sparkles.",
    ),
    "oak": (
        "古木", "3:4",
        "an ancient tree drawn as flat shapes: a thick twisted trunk of flat olive and "
        "charcoal forms grown through a broken fluted stone column, roots gripping a "
        "cracked step, the canopy one solid mass of sage and olive shapes",
        "The background field is dark charcoal. Put a pale stone arch behind. Add "
        "eight-pointed star sparkles in the dark sky.",
    ),
    "burl": (
        "树瘤", "3:4",
        "a round burl knot drawn as flat concentric rings of ochre and charcoal like a "
        "stone medallion, a short stub of trunk pushing out of its side",
        "Use a tall arch behind. Four-pointed sparkles around the rings.",
    ),
    # —— 分枝 ——
    "fork": (
        "分叉", "3:4",
        "a pale stem that divides once into exactly two symmetrical branches, the "
        "division springing from the top of a stepped ziggurat",
        "Use a stepped ziggurat as the framing device. Two eight-pointed stars.",
    ),
    "side": (
        "侧枝", "3:4",
        "a pale upright stem with one shorter branch leaving its middle toward the left, "
        "standing before a broken classical pediment",
        "Use a broken pediment as the framing device. One four-pointed sparkle.",
    ),
    "tri": (
        "三叉", "3:4",
        "a pale stem dividing into exactly three symmetrical upward branches, like a "
        "trident, in front of a large crescent moon",
        "Use a crescent moon as the framing device. Two eight-pointed stars.",
    ),
    "palm": (
        "掌叉", "3:4",
        "a pale stem dividing into three branches that spread backwards to the sides "
        "like an open hand, standing in a tall pointed archway",
        "Use a tall pointed arch as the framing device. Three four-pointed sparkles.",
    ),
    "curl": (
        "回旋枝", "3:4",
        "one branch curling into a tight spiral scroll, the spiral drawn as one clean "
        "sweeping curve of olive and gold, set inside a round medallion",
        "Use a round medallion as the framing device. Four-pointed sparkles.",
    ),
    # —— 末端 ——
    "berry": (
        "浆果", "3:4",
        "a branch of berries drawn as flat shapes: round terra-red berries clustered on "
        "a slim dark stem among a few simple olive leaf shapes, set inside a large "
        "ochre circle on a cream field",
        "Use the large ochre circle as the framing device. One eight-pointed star.",
    ),
    "fruit": (
        "果", "3:4",
        "one plump round fruit of terra red on a short stem, set in a stone niche with "
        "a small arched top",
        "Use a tall arched niche as the framing device. Four-pointed sparkles.",
    ),
    "pod": (
        "种荚", "3:4",
        "a long slender seed pod split open showing round seeds inside, lying against "
        "a broken column shaft",
        "Use a broken column as the framing device. One eight-pointed star.",
    ),
    "gold": (
        "金果", "3:4",
        "one round fruit of matte gold crowned with three triangular points, resting in "
        "the niche of a fluted column capital",
        "Use a tall narrow arch as the framing device. Four-pointed sparkles.",
    ),
    # —— 相邻 ——
    "flower": (
        "花", "3:4",
        "one five petal flower of terra red drawn as flat geometric petals around a gold "
        "centre, on a straight stem",
        "Use a round medallion as the framing device. Four-pointed sparkles.",
    ),
    "nectar": (
        "蜜花", "3:4",
        "one pale flower with five sage petals and a gold centre, a small geometric bee "
        "resting on it",
        "Use an arched niche as the framing device. Four-pointed sparkles.",
    ),
    "moss": (
        "苔", "3:4",
        "a patch of moss of olive and sage flat shapes growing over a cracked stone step, "
        "tiny fronds rising",
        "Use a low stepped platform as the framing device. No arch.",
    ),
    # —— 嫁接 ——
    "vine": (
        "藤", "3:4",
        "a long spiralling stem coiling in a helix around a broken classical column, "
        "carrying a few heart-shaped olive leaves",
        "The vine's spiral is the main shape. Use a stepped stone platform as the "
        "framing device.",
    ),
    "twinvine": (
        "连理藤", "3:4",
        "two vines wrapping each other in a double helix, one olive and one gold, "
        "rising between two broken columns",
        "Use two tall arches behind. Four-pointed sparkles.",
    ),
    # —— 时间 ——
    "shoot": (
        "新芽", "3:4",
        "a young shoot with two small leaves unfurling, rising out of a crack in a "
        "stone step, one olive and one sage",
        "Use a tall narrow arch behind. Two four-pointed sparkles.",
    ),
    "bud": (
        "花苞", "3:4",
        "a closed pointed flower bud of terra red on a straight stem, rising from a "
        "cracked classical bust",
        "Vertical composition with lots of cream empty space. Use a narrow arch.",
    ),
    "heartwood": (
        "心材", "3:4",
        "the cross section of a tree, concentric growth rings of ochre and charcoal "
        "inside a rough bark circle, one radial crack",
        "Use a round medallion as the framing device. No arch.",
    ),
    # —— 修剪 ——
    "leaf": (
        "落叶", "3:4",
        "several separate leaves of ochre and terra drifting down through empty air, "
        "scattered asymmetrically at different heights, one large leaf in the foreground",
        "Asymmetric scattered composition, no frame at all, only floating leaves and "
        "small four-pointed sparkles.",
    ),
    "dead": (
        "枯枝", "3:4",
        "a bare broken twig with a jagged snapped end, drawn as thin charcoal lines, "
        "leaning against a broken column",
        "Use a broken pediment as the framing device. Very empty.",
    ),
    "rot": (
        "朽木", "3:4",
        "a rotting fallen log of flat olive and charcoal shapes with cracks and pale "
        "fungus discs, lying on a stepped platform",
        "Use a low stepped platform as the framing device. No arch.",
    ),
    # —— 器物（方形图标）——
    "basket": (
        "竹篮", "1:1",
        "a woven basket drawn as flat interlaced ochre and gold bands, seen from the "
        "front, with a handle arching over the top",
        "The basket fills the frame. One eight-pointed star at the top corner.",
    ),
    "beehive": (
        "蜂箱", "1:1",
        "a stacked beehive of flat gold and ochre boxes with a dark arched entrance "
        "slot and a small flight of geometric bees",
        "The hive fills the frame. Four-pointed sparkles.",
    ),
    "chime": (
        "风铃", "1:1",
        "a hanging wind chime: a thin gold bell, a small disc and one dangling leaf "
        "shape, suspended from a short chain",
        "The chime hangs in the centre. Four-pointed sparkles around it.",
    ),
    "compost": (
        "堆肥桶", "1:1",
        "a wooden compost barrel drawn as flat ochre planks with two dark hoops, "
        "a heap of olive leaves spilling from the top",
        "The barrel fills the frame.",
    ),
    "dew": (
        "露水瓶", "1:1",
        "a slim tall glass bottle drawn in pale cream and light sage with one large "
        "drop of water inside, standing on a small pale stone, bright and airy with "
        "wide empty cream space around it",
        "The bottle stands in the centre, small, with wide empty cream margins. "
        "Four-pointed sparkles.",
    ),
    "knife": (
        "嫁接刀", "1:1",
        "a grafting knife drawn as a flat charcoal blade with a gold bolster and an "
        "ochre wooden handle, lying diagonally",
        "The knife fills the frame diagonally.",
    ),
    "root": (
        "古树根", "1:1",
        "an ancient gnarled tree root drawn as flat charcoal and olive shapes arching "
        "over a cracked stone",
        "The root fills the frame.",
    ),
    "ruler": (
        "年轮尺", "1:1",
        "a flat measuring rule of pale cream with dark tick marks and a gold edge, "
        "lying diagonally across the frame",
        "The ruler fills the frame diagonally.",
    ),
    "seedbag": (
        "种子袋", "1:1",
        "a small cloth sack of flat cream and ochre, its mouth open with round seeds "
        "spilling out onto the ground",
        "The sack fills the frame.",
    ),
    "shears": (
        "修枝剪", "1:1",
        "a pair of pruning shears drawn as flat charcoal blades and gold handles, "
        "slightly open",
        "The shears fill the frame.",
    ),
    # —— 天灾（方形图标）——
    "drought": (
        "干旱", "1:1",
        "dry cracked earth drawn as flat terra and ochre polygons split by deep "
        "angular cracks, a withered leaf in one crack",
        "The cracked ground fills the frame.",
    ),
    "lightning": (
        "雷击", "1:1",
        "a single jagged lightning bolt of matte gold striking down onto a small "
        "charcoal broken branch",
        "The bolt fills the frame vertically.",
    ),
    "pests": (
        "虫害", "1:1",
        "a branch of flat olive leaves riddled with small round holes, three flat "
        "geometric beetles crawling on it",
        "The branch fills the frame.",
    ),
}


def build_prompt(motif: str, extra: str) -> str:
    p = f"""\
Vertical poster plate, flat screen-print style, for an illustrated botanical tome of a
lost ancient civilisation.

SUBJECT: {motif}

STYLE: flat graphic poster, geometric-modernist. Simplify the subject into a few LARGE
flat colour shapes with hard edges - not a realistic drawing. No individual leaves, no
bark texture, no realistic shading, no photorealism, no 3D. Fine engraved hatching only
as light texture.

COMPOSITION: the subject fills the frame, may be cropped at the edges. Architecture is
fused with the plant: roots become arches, stems become columns, vines wrap capitals.
Exactly ONE large framing shape behind the subject - one of: tall arch, stepped
ziggurat, broken pediment, round medallion, crescent moon. Never repeat circles. Big
areas of empty cream space. Four- and eight-pointed star sparkles of fine radiating
lines.
THE PLANT IS THE HERO: the plant itself must be LARGE and dominant, filling at least
two thirds of the frame height, in the strongest contrast on the plate. The
architecture behind is a quiet simple backdrop that never competes with the subject.
{extra}
{PALETTE_BLOCK}
FINISH: light aged paper grain; artwork bleeds to all four edges.
STRICTLY NO text, letters, numbers, captions, signature, border, frame, page edge or
margin line.
"""
    # 接口上限 1500 字符，留点余量
    if len(p) > 1460:
        p = p[:1455].rsplit(" ", 1)[0]
    return p


# ---------------------------------------------------------------- 地块与背景
# 地块是「一块石板/土面」的方形贴图，Godot 里再裁成六边形。
TILES: dict[str, tuple[str, str]] = {
    "land_plain": (
        "平地", "a floor of large pale cream stone flagstones, each flat slab separated by "
        "thin dark joint lines, faint fine engraved hatch marks on the slab faces, a "
        "few small ochre pebbles, quiet and orderly"),
    "land_fertile": (
        "沃土", "warm brown soil of mid-tone ochre and olive, scattered with small pale "
        "sage sprouts and fine pale root lines running through it, a few golden seed "
        "husks, MID TONE and clearly lighter than black"),
    "land_rock": (
        "岩石", "pale grey-ochre stone slabs at sharp angles, warm light grey stone with "
        "thin dark cracks between the slabs, fine hatch marks on the faces, a few small "
        "chips, LIGHT overall not dark"),
    "land_spring": (
        "泉眼", "a still pool of muted sage and pale cream water, concentric ripple "
        "rings spreading from the middle, a pale stone rim, the softest ground"),
}

TILE_PROMPT = """\
A square tile of terrain seen straight from above, flat screen-print style, for an
illustrated tome of a lost ancient civilisation.

TERRAIN: {motif}

STYLE: flat graphic, geometric-modernist. Clear readable structure: large simple flat
colour shapes with hard edges and thin dark joint lines, fine engraved hatching as
light texture. No photorealism, no 3D, no perspective, no shadows. The whole square is
the terrain itself, edge to edge.
COLOUR (only these flat colours):
cream #EDE3C9  ochre #C9914A  terra #B04A2A  olive #7B7A55
charcoal #2B2925  gold #B08A46  sage #A9A98C
FINISH: light aged paper grain. STRICTLY NO text, letters, numbers, captions,
signature, border, frame, page edge or margin line.
"""

BG_PROMPT = """\
A wide horizontal backdrop of an impossible ancient courtyard, flat screen-print
style, for an illustrated botanical tome of a lost ancient civilisation.

SCENE: a vast empty temple hall of pale cream marble, a row of tall fluted columns
receding, arches and a stepped platform in the distance, a dark starry sky of
charcoal above with a few four-pointed and eight-pointed star sparkles, a great
golden disc low in the sky. The centre of the picture is empty floor.

STYLE: flat graphic, geometric-modernist, large simple flat colour shapes with hard
edges, fine engraved hatching as light texture. No photorealism, no 3D, no people.
COLOUR (only these flat colours):
cream #EDE3C9  ochre #C9914A  terra #B04A2A  olive #7B7A55
charcoal #2B2925  gold #B08A46  sage #A9A98C
FINISH: light aged paper grain. STRICTLY NO text, letters, numbers, captions,
signature, border, frame, page edge or margin line.
"""


# ---------------------------------------------------------------- 3D 牌桌与器物（阶段 2）
OBJECT_PROMPT = """\
A single museum artefact of a lost ancient civilisation, drawn in flat screen-print
style for an illustrated tome.

OBJECT: {motif}

STYLE: flat graphic, geometric-modernist, large simple flat colour shapes with hard
edges, crisp dark outline around the whole object, fine engraved hatching as light
texture. The object stands upright, seen slightly from the front, centred, filling
about 70 percent of the frame height.
BACKGROUND: completely plain, flat, empty, uniform pale cream #F2EBD8 - no scene, no
floor, no shadow, no arch, no stars, no decoration at all around the object.
COLOUR (only these flat colours):
cream #EDE3C9  ochre #C9914A  terra #B04A2A  olive #7B7A55
charcoal #2B2925  gold #B08A46  sage #A9A98C
STRICTLY NO text, letters, numbers, captions, signature, border or frame.
"""

RELIC_OBJECTS: dict[str, tuple[str, str]] = {
    "knife": ("嫁接刀", "a small curved grafting knife with a polished ochre wooden handle wrapped in a gold band, the charcoal blade engraved with a vine pattern, standing on its tip in a little stone stand"),
    "root": ("古树根", "a gnarled ancient tree root knot, twisted charcoal and olive strands coiled into a compact sculptural knot, set on a small fluted column drum"),
    "beehive": ("蜂箱", "a classical skep beehive of stacked ochre and gold rings shaped like a small domed temple, a dark arched doorway at its base, two tiny bees"),
    "seedbag": ("种子袋", "a small plump seed sack of terra-red and ochre striped cloth with a dark charcoal outline, tied at the neck with a gold cord, a few ochre seeds spilling at its foot, a single olive sprout leaf tucked in the knot"),
    "basket": ("竹篮", "a round woven bamboo basket in ochre and gold weave with a tall arched handle, a few sage leaves inside"),
    "chime": ("风铃", "a bronze wind chime: a small gold bell-shaped canopy with five slender hanging tubes of different lengths and a leaf-shaped striker"),
    "compost": ("堆肥桶", "a squat terracotta urn with two loop handles, filled to the brim with dark soil and fallen olive leaves, a geometric band painted around its belly"),
    "dew": ("露水瓶", "a slender glass amphora-shaped flask with a gold stopper, a single large dew drop of pale sage blue inside, fine highlight lines on the glass"),
    "ruler": ("年轮尺", "a flat round wooden disc cut from a tree trunk showing concentric growth rings in ochre and charcoal, standing upright on a small stone easel, with gold measuring ticks around its rim"),
    "shears": ("修枝剪", "a pair of classical pruning shears with charcoal blades and curved ochre handles, standing upright, slightly open"),
}

TABLE_PROMPT = """\
A square seamless texture of a carved stone altar surface seen straight from above,
flat screen-print style, for an illustrated tome of a lost ancient civilisation.

SURFACE: one large slab of pale warm travertine, very subtle large flat tonal patches
of cream and light ochre, a few fine hairline cracks, faint engraved concentric
geometric rings and a delicate meander band, all very low contrast so that game
pieces placed on top stay readable.

STYLE: flat graphic, no perspective, no shadows, no objects on it, edge to edge.
COLOUR: mostly cream #EDE3C9 and #E4DCC4 with touches of ochre #C9914A and sage #A9A98C.
FINISH: light aged paper grain. STRICTLY NO text, letters, numbers, border or frame.
"""

CARD_BACK_PROMPT = """\
The back of a sacred playing card from a lost ancient civilisation, flat screen-print
style, perfectly symmetric vertical design.

DESIGN: a deep charcoal #2B2925 field; in the centre a great gold sun disc with fine
radiating lines, in front of it a stylised symmetric sacred tree whose roots become a
small stepped temple; geometric gold meander band and thin double gold lines framing
the whole card; four small eight-pointed stars in the corners.

STYLE: flat graphic, geometric-modernist, hard edges, fine engraved hatching.
COLOUR: charcoal #2B2925, gold #B08A46, ochre #C9914A, a little cream #EDE3C9.
FINISH: light aged paper grain. STRICTLY NO text, letters or numbers.
"""

BG_HD_PROMPT = BG_PROMPT.replace(
    "The centre of the picture is empty floor.",
    "The centre and lower half of the picture is a wide empty marble floor seen from a "
    "low viewpoint, the columns on both sides lead the eye to the centre. Soft warm light.")


def cutout(im: Image.Image, tol: int = 34, feather: float = 1.4) -> Image.Image:
    """把纯色底抠成透明：从四边泛洪找出与边缘连通、颜色接近底色的像素。"""
    import numpy as np
    from collections import deque
    from PIL import ImageFilter

    rgb = np.asarray(im.convert("RGB"), dtype=np.int16)
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    close = np.abs(rgb - bg).sum(axis=2) < tol * 3
    seen = np.zeros((h, w), dtype=bool)
    q: deque = deque()
    for x in range(w):
        for y in (0, h - 1):
            if close[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if close[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and close[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    alpha = Image.fromarray(np.where(seen, 0, 255).astype("uint8"), "L")
    # 去掉一圈残边再羽化
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(feather))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 20 else 0).getbbox()
    if bbox:
        pad = 8
        bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(w, bbox[2] + pad), min(h, bbox[3] + pad))
        out = out.crop(bbox)
    return out


def extra_items() -> dict[str, tuple[str, str, str, int, bool]]:
    """id -> (中文名, 画幅, 提示词, 输出宽度, 是否抠图)"""
    items: dict[str, tuple[str, str, str, int, bool]] = {
        "table_top": ("台面", "1:1", TABLE_PROMPT, 1024, False),
        "card_back": ("牌背", "3:4", CARD_BACK_PROMPT, 768, False),
        "board_bg": ("神庙（高清）", "16:9", BG_HD_PROMPT, 1280, False),
    }
    for rid, (cn, motif) in RELIC_OBJECTS.items():
        items[f"relic_cut_{rid}"] = (cn, "1:1", OBJECT_PROMPT.format(motif=motif), 768, True)
    return items


# ---------------------------------------------------------------- 牌桌上的拟态立牌（纸雕立体书风格）
# 纯白底生成，再用区域生长抠图（模型不肯给纯绿幕，会给带渐变的灰绿底，和叶子撞色）。
STANDEE_PROMPT = """\
A single botanical element cut out like a paper pop-up book standee, from an
illustrated tome of a lost ancient civilisation, flat screen-print style.

ELEMENT: {motif}

STYLE: flat graphic, geometric-modernist, large simple flat colour shapes with hard
edges, a crisp charcoal outline around the whole silhouette, fine engraved hatching as
light texture. Upright, centred, compact silhouette filling about 75 percent of the
frame height, nothing touching the edges.
BACKGROUND: plain flat pure white #FFFFFF, like a studio photo of a single paper
cut-out on white; no floor line, no scene, no decoration.
COLOUR of the element (only these): cream #EDE3C9  ochre #C9914A  terra #B04A2A
olive #7B7A55  charcoal #2B2925  gold #B08A46  sage #A9A98C
STRICTLY NO text, letters, numbers, border or frame.
"""

STANDEES: dict[str, tuple[str, str]] = {
    "seed": ("树心", "the sacred heart of a tree: a short thick gnarled charcoal trunk stump with a gold sun disc set into its front and strong roots spreading at its base"),
    "stem": ("茎", "a single slender straight olive stem with two small leaves and a tiny bud at the top"),
    "node": ("节", "a short straight olive stem segment with one swollen round knuckle in the middle and a small leaf at the knuckle"),
    "oak": ("古木", "a tiny ancient gnarled oak tree with a thick twisted charcoal trunk and a compact round olive and sage canopy"),
    "burl": ("树瘤", "a short thick branch segment with one big round burl knot showing ochre and charcoal concentric rings"),
    "curl": ("回旋枝", "a slender branch curling into a tight spiral scroll tendril with two small leaves"),
    "fork": ("分叉", "a Y-shaped forked twig splitting into two equal branches with small olive leaves at both tips"),
    "palm": ("掌叉", "a twig splitting into three spreading branches like an open hand with small olive leaves at the tips"),
    "side": ("侧枝", "a straight twig with one side branch sprouting to the left, small olive leaves"),
    "tri": ("三叉", "a twig splitting into three upright branches like a trident, small olive leaves"),
    "berry": ("浆果", "a small cluster of round terra-red berries on a short twig with two olive leaves"),
    "fruit": ("果", "a single ripe round terra-red fruit hanging from a short twig with two olive leaves"),
    "gold": ("金果", "a single gleaming golden fruit with a small crown-shaped top on a short twig with olive leaves, fine radiating sparkle lines around it"),
    "pod": ("种荚", "a long curved olive seed pod split open showing a row of ochre seeds"),
    "flower": ("花", "a single open flower with large terra and ochre petals on a short olive stem with two leaves"),
    "moss": ("苔", "a low soft rounded cushion of olive and sage moss with a few tiny stalks"),
    "nectar": ("蜜花", "a single open flower with cream and gold petals and a glistening ochre nectar drop in its centre, a tiny bee beside it"),
    "vine": ("藤", "a twisting climbing gold-olive vine with curly tendrils and small leaves, coiled in an S shape"),
    "twinvine": ("连理藤", "two vines intertwined into one braided rope, small gold leaves along it"),
    "bud": ("花苞", "a single closed terra and ochre flower bud on a short olive stem, tightly wrapped sepals"),
    "heartwood": ("心材", "a short upright log segment whose cut top shows deep terra-brown growth rings around a glowing gold core"),
    "shoot": ("新芽", "a tiny fresh sprout with two bright olive seed leaves rising from a small pinch of charcoal soil"),
    "dead": ("枯枝", "a bare grey leafless dead twig, dry and slightly bent"),
    "leaf": ("落叶", "a single autumn leaf in ochre and terra, curled slightly, standing on its stem"),
    "rot": ("朽木", "a short crumbling rotten log segment, grey-brown, with two small ochre mushrooms growing on it"),
}


def cutout_soft(im: Image.Image, step: float = 7.0, total: float = 60.0, feather: float = 1.2) -> Image.Image:
    """渐变底也能抠：从四边做区域生长——相邻像素变化很小、且离边缘底色不远，就算底。"""
    import numpy as np
    from collections import deque
    from PIL import ImageFilter

    blur = np.asarray(im.convert("RGB").filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float32)
    h, w, _ = blur.shape
    border = np.concatenate([blur[0], blur[-1], blur[:, 0], blur[:, -1]])
    far = np.abs(blur - np.median(border, axis=0)).sum(axis=2)
    seen = np.zeros((h, w), dtype=bool)
    q: deque = deque()
    for x in range(w):
        for y in (0, h - 1):
            seen[y, x] = True
            q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        c = blur[y, x]
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                if np.abs(blur[ny, nx] - c).sum() < step and far[ny, nx] < total * 3:
                    seen[ny, nx] = True
                    q.append((ny, nx))
    alpha = Image.fromarray(np.where(seen, 0, 255).astype("uint8"), "L")
    alpha = alpha.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(feather))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 20 else 0).getbbox()
    if bbox:
        pad = 6
        out = out.crop((max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(w, bbox[2] + pad), min(h, bbox[3] + pad)))
    return out


def cutout_green(im: Image.Image, feather: float = 1.2) -> Image.Image:
    """绿幕抠图 + 去绿边。"""
    import numpy as np
    from PIL import ImageFilter

    rgb = np.asarray(im.convert("RGB"), dtype=np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # 绿得明显（g 比 r、b 都高出很多）就是底色
    green = (g - np.maximum(r, b)) > 38
    alpha = Image.fromarray(np.where(green, 0, 255).astype("uint8"), "L")
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(feather))
    # 去绿边：把绿色压到红蓝的均值附近
    g2 = np.minimum(g, (r + b) * 0.5 + 18)
    rgb2 = np.stack([r, g2, b], axis=-1).clip(0, 255).astype("uint8")
    out = Image.fromarray(rgb2, "RGB").convert("RGBA")
    out.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 20 else 0).getbbox()
    if bbox:
        w, h = out.size
        pad = 6
        out = out.crop((max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(w, bbox[2] + pad), min(h, bbox[3] + pad)))
    return out


# ---------------------------------------------------------------- API
def api_key() -> str:
    p = Path.home() / ".local" / "share" / "opencode" / "auth.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    for name in ("minimax-cn", "minimax", "minimax-cn-coding-plan", "minimax-coding-plan"):
        if name in d and d[name].get("key"):
            return d[name]["key"]
    raise SystemExit("找不到 minimax API key")


def call_api(key: str, prompt: str, aspect: str = "3:4", model: str = "image-01") -> bytes:
    body = json.dumps({
        "model": model,
        "prompt": prompt,
        "aspect_ratio": aspect,
        "response_format": "url",
        "n": 1,
        "prompt_optimizer": False,
    }).encode("utf-8")
    req = urllib.request.Request(
        API, data=body, method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        r = json.loads(resp.read().decode("utf-8"))
    st = r.get("base_resp", {})
    if st.get("status_code") != 0:
        raise RuntimeError(f"API 错误 {st.get('status_code')}: {st.get('status_msg')}")
    urls = (r.get("data") or {}).get("image_urls") or []
    if not urls:
        raise RuntimeError(f"没有返回图片: {r}")
    with urllib.request.urlopen(urls[0], timeout=300) as resp:
        return resp.read()


# ---------------------------------------------------------------- 后处理
def harmonize(raw: bytes, size: int = 768) -> Image.Image:
    """轻微向调色板靠拢 + 统一纸底暖调，保留原有质感。"""
    from PIL import ImageEnhance

    im = Image.open(io.BytesIO(raw)).convert("RGB")
    im = ImageEnhance.Color(im).enhance(0.88)
    im = ImageEnhance.Brightness(im).enhance(1.03)
    im = ImageEnhance.Contrast(im).enhance(0.97)
    im = im.resize((size, int(size * im.size[1] / im.size[0])), Image.LANCZOS)
    return im


def strip_borders(im: Image.Image, margin: float = 0.055, bottom: float = 0.05) -> Image.Image:
    """裁掉模型爱加的画框线、页边和底部的假文字条。"""
    w, h = im.size
    m = int(w * margin)
    b = int(h * bottom)
    px = im.load()

    def edge_uniform(y: int, x0: int, x1: int) -> bool:
        c0 = px[x0, y]
        c1 = px[x1, y]
        return sum(abs(c0[i] - c1[i]) for i in range(3)) < 40

    extra = 0
    if edge_uniform(0, m, w - m) and edge_uniform(h - 1, m, w - m):
        extra = int(w * 0.02)
    return im.crop((m + extra, m, w - m - extra, h - b - extra))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--model", default="image-01")
    ap.add_argument("--sleep", type=float, default=1.0)
    ap.add_argument("--size", type=int, default=768)
    ap.add_argument("--standees", action="store_true", help="生成牌桌上的拟态立牌（25 张，白底区域生长抠图）")
    ap.add_argument("--extra", action="store_true", help="生成 3D 牌桌资产（台面/牌背/高清背景/器物抠图）")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    only = {s for s in args.only.split(",") if s}

    key = api_key()
    failed: list[str] = []

    def run(cid: str, cn: str, prompt: str, aspect: str, size: int = 0, cut=False) -> None:
        out = OUT_DIR / f"{cid}.png"
        jpg = CACHE / f"{cid}.jpg"
        if out.exists() and not args.force:
            print(f"[skip] {cid}")
            return
        print(f"[gen ] {cid} ({cn}) ...", flush=True)
        try:
            raw = call_api(key, prompt, aspect, args.model)
        except Exception as e:  # noqa: BLE001
            print(f"  !! 失败: {e}")
            failed.append(cid)
            return
        jpg.write_bytes(raw)
        time.sleep(args.sleep)
        img = harmonize(raw, size or args.size)
        if cut == "soft":
            img = cutout_soft(img)
        elif cut == "green":
            img = cutout_green(img)
        elif cut:
            img = cutout(img)
        else:
            img = strip_borders(img)
        img.save(out)
        print(f"  -> {out.name} {img.size}")

    # --standees / --extra 只生成那一批，不碰原有的牌面与地块（配合 --force 时尤其要紧）
    batch = args.standees or args.extra
    for cid, (cn, aspect, motif, extra) in SPEC.items():
        if (only and cid not in only) or (not only and batch):
            continue
        run(cid, cn, build_prompt(motif, extra), aspect)

    for cid, (cn, motif) in TILES.items():
        if (only and cid not in only) or (not only and batch):
            continue
        run(cid, cn, TILE_PROMPT.format(motif=motif), "1:1")

    # 牌桌上的拟态立牌：--standees 或 --only standee_<id>
    for sid, (cn, motif) in STANDEES.items():
        cid = f"standee_{sid}"
        if (only and cid not in only) or (not only and not args.standees):
            continue
        run(cid, cn, STANDEE_PROMPT.format(motif=motif), "3:4", 768, "soft")

    # 阶段 2 的 3D 牌桌资产：只在 --extra 或 --only 点名时生成（board_bg 用高清版覆盖旧图）
    for cid, (cn, aspect, prompt, size, cut) in extra_items().items():
        if (only and cid not in only) or (not only and not args.extra):
            continue
        run(cid, cn, prompt, aspect, size, cut)

    if failed:
        print("失败: " + ", ".join(failed))


if __name__ == "__main__":
    raise SystemExit(main())
