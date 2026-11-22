#!/usr/bin/env python3
"""新流派（齿轮 / 熔炉 / 星辰 / 商会 / 镜像 / 封印 / 桥牌）的美术：牌面图版、牌桌立牌、器物抠图、新地块。

沿用 generate_art.py 的接口调用、色调统一与抠图。每个流派一套独立画风（见 STYLE）：
齿轮=维多利亚工程铜版画，熔炉=巴洛克火光油画，星辰=星图集金线，商会=金箔新艺术，
镜像=超现实主义，封印=铅条彩色玻璃。古木系、地块和通用器物仍是原来的复古几何丝网风。

用法（在仓库根目录）：
    python game/tools/card_art/generate_family_art.py                    # 生成全部缺失的
    python game/tools/card_art/generate_family_art.py --kind cards       # 只生成牌面（cards/standees/relics/tiles）
    python game/tools/card_art/generate_family_art.py --only gear_cog,standee_gear_cog
    python game/tools/card_art/generate_family_art.py --jobs 3           # 并行请求数
"""
from __future__ import annotations

import argparse
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_art as ga  # noqa: E402

# id -> (中文名, 流派, 母题)
CARDS: dict[str, tuple[str, str, str]] = {
    # —— 齿轮 ——
    "gear_cog": ("齿轮", "gear", "one huge bronze cog wheel with square teeth filling most of the plate, a small tree emblem cut into its hub, standing on a short fluted column"),
    "gear_link": ("联动齿轮", "gear", "three interlocking bronze cog wheels of different sizes meshing together in a diagonal chain, their teeth engaged"),
    "gear_hub": ("枢纽", "gear", "a large bronze mechanical hub: one big central cog wheel with five smaller bronze cogs meshing around its rim, all mounted on a stone wall plate, clockwork style"),
    "gear_rivet": ("铆钉", "gear", "one big round-headed iron rivet standing upright, with a steel-blue riveted plate behind it"),
    "gear_diff": ("差速器", "gear", "a bevel gear differential: one vertical cog driving two cogs that turn left and right, splitting like a branching stem"),
    "gear_shaft": ("传动轴", "gear", "a tall steel drive shaft standing upright like a column, bronze collars along it and a large bronze cog at the top and bottom"),
    "gear_escape": ("擒纵", "gear", "a brass clock escapement: one large toothed wheel with an anchor-shaped lever resting on its teeth and a pendulum hanging below"),
    "gear_core": ("机芯", "gear", "an open round brass pocket-watch movement seen from the front, several meshing cogs inside and a red jewel at the centre"),
    "gear_spring": ("发条", "gear", "a tightly wound flat steel mainspring coil with a bronze winding key standing in its centre"),
    # —— 熔炉 ——
    "forge_coal": ("炭", "forge", "a heap of black faceted coal lumps with glowing ember cracks, small flames licking from the top"),
    "forge_furnace": ("熔炉", "forge", "a domed stone smelting furnace like a small Roman temple, plain columns, its arched mouth glowing bright orange, a chimney with sparks"),
    "forge_ember": ("余烬", "forge", "a single glowing ember drifting upward above a bed of grey ash, trailing a thin curl of smoke"),
    "forge_altar": ("祭坛", "forge", "a stepped stone altar with a shallow bronze fire bowl on top, tall flames rising, offerings of twigs at its foot"),
    "forge_kindle": ("火种", "forge", "a small forked dry twig standing upright, a little flame burning at each of its two tips"),
    "forge_anvil": ("铁砧", "forge", "a heavy black iron anvil on a stone block, a glowing red-hot bar on it and a hammer leaning against it"),
    "forge_ash": ("灰烬", "forge", "a tall urn overflowing with pale grey ash, faint glowing specks inside, a single burnt leaf on top"),
    "forge_phoenix": ("凤凰羽", "forge", "one single long feather of a European heraldic firebird, shaped like a quill and burning at its tip, ember red, orange and gold, standing upright in a bronze holder"),
    "forge_bellows": ("风箱", "forge", "a pair of leather blacksmith bellows (no person) with wooden handles and a bronze nozzle, blowing into a small glowing fire"),
    # —— 星辰 ——
    "star_sand": ("星砂", "star", "an hourglass whose falling sand is made of tiny silver stars, set on a carved pedestal"),
    "star_moon": ("满月", "star", "a large pale full moon disc with flat silver patches, set on top of a slender classical column"),
    "star_tide": ("潮汐", "star", "a single tall classical Greek wave scroll pattern rising like a column under a crescent moon, Mediterranean meander style"),
    "star_meteor": ("流星", "star", "a glowing round stone meteor with a long silver flaming tail, diving diagonally"),
    "star_chart": ("星图", "star", "a round brass celestial globe on a stand, engraved with constellation dots joined by fine lines"),
    "star_dial": ("日晷", "star", "a stone sundial on a column, its bronze gnomon casting a long shadow across engraved hour lines"),
    "star_comet": ("彗尾", "star", "a comet with a very long sweeping tail that curves down the whole plate like a branch"),
    "star_astrolabe": ("星盘", "star", "a bronze astrolabe with nested rings and a pointer, three arms reaching out in different directions"),
    # —— 商会 ——
    "coin_copper": ("铜币", "coin", "a tall neat stack of round copper coins with one large coin standing on its edge in front, on a plain gold mosaic ground"),
    "coin_bank": ("银行", "coin", "a classical bank facade with columns and a pediment, a large gold coin set into the pediment"),
    "coin_vault": ("金库", "coin", "a heavy round steel vault door with a spoked wheel handle, slightly open, gold coins visible inside"),
    "coin_contract": ("契约", "coin", "a rolled blank parchment scroll tied with a ribbon and a round red wax seal, a feather quill crossed over it"),
    "coin_bond": ("债券", "coin", "a neat stack of three ornate paper certificates tied with a gold ribbon, a gold coin resting on top"),
    "coin_caravan": ("驼队", "coin", "a camel loaded with bundles and striped saddle bags, walking under a crescent moon, two more camels behind in silhouette"),
    "coin_pawn": ("当铺", "coin", "three gold balls hanging from a curled wrought-iron wall bracket, the classic pawnbroker sign"),
    "coin_ledger": ("账本", "coin", "a thick open ledger book with neat columns of marks, a balance scale standing on it"),
    "coin_horn": ("丰饶角", "coin", "a golden cornucopia horn lying on its side, overflowing with gold coins, grapes and apples"),
    # —— 镜像 ——
    "mirror_silver": ("银镜", "mirror", "a tall oval silver hand mirror with an ornate frame, its glass reflecting a tiny sacred tree"),
    "mirror_echo": ("倒影", "mirror", "a large round topiary bush filling the middle of the frame, standing on a still lake with its exact mirrored copy upside down beneath it"),
    "mirror_frame": ("镜框", "mirror", "an empty ornate rectangular mirror frame with carved corners, hanging on a column"),
    "mirror_phantom": ("幻影", "mirror", "a translucent ghostly double of a small tree standing beside a solid one, drawn in pale silver outline"),
    "mirror_kaleido": ("万花筒", "mirror", "a kaleidoscope tube and, behind it, a large perfectly symmetric six-fold kaleidoscope pattern"),
    "mirror_prism": ("棱镜", "mirror", "a solid triangular glass prism standing on a small brass base, two coloured light beams leaving it to the left and right"),
    "mirror_twin": ("双子", "mirror", "two identical classical Greek marble statues of youths standing back to back, perfectly mirrored, each holding a laurel branch"),
    "mirror_glass": ("镜面", "mirror", "a large round standing silver mirror on a brass stand, filling most of the frame, its glass reflecting a second sky with clouds"),
    # —— 封印 ——
    "seal_box": ("封印匣", "seal", "a small ornate bronze casket bound with two leather straps and closed with a large plum wax seal, faint light at the seams"),
    "seal_wax": ("蜡封", "seal", "a round blob of deep red sealing wax on a folded letter, pressed with a small tree emblem, a stick of red wax lying beside it"),
    "seal_rune": ("符文石", "seal", "an upright grey standing stone carved with simple glowing geometric lines and circles (no letters), moss at its base"),
    "seal_ward": ("护符", "seal", "a bronze protective amulet pendant on a leather cord, a round charm with a small tree emblem and a plum gem"),
    "seal_thunder": ("雷印", "seal", "a European brass hand stamp with a turned wooden handle standing upright, and above it a bright zigzag lightning bolt striking down from a dark storm cloud"),
    "seal_break": ("解印", "seal", "a wax seal cracking open with light bursting out of the crack, fragments flying"),
    "seal_hoard": ("秘藏", "seal", "an iron-bound treasure chest half buried in roots, locked with a seal, coins peeking out"),
    "seal_chain": ("锁链", "seal", "a heavy iron chain hanging from a ring and splitting into two chains, each ending in a small iron padlock"),
    # —— 桥牌 ——
    "bridge_bell": ("青铜钟", "gear", "a bronze bell hanging in a clockwork frame of cogs, stars engraved on its rim"),
    "bridge_mint": ("铸币炉", "forge", "a small furnace pouring molten gold into round coin moulds, finished coins stacked beside"),
    "bridge_starfire": ("星火", "forge", "a single campfire flame (no person) whose sparks rise and turn into silver stars in the night sky above it"),
    "bridge_goldgear": ("金齿轮", "coin", "a large golden cog wheel whose rim is milled like a coin edge, a gold coin set into its hub"),
    "bridge_lockvine": ("锁藤", "gear", "a grapevine growing through and around bronze cog wheels, tendrils locking two gears together"),
    "bridge_spiritfruit": ("灵果", "star", "a single luminous fruit hanging from a branch under a crescent moon, glowing with silver light"),
    "bridge_mirrorforge": ("镜炉", "mirror", "a small furnace and its exact mirror image facing each other, flames reflected in a silver panel between them"),
    "bridge_sealcoin": ("封金匣", "coin", "a small iron-bound oak strongbox with a heavy padlock, a stack of gold coins on its lid"),
    # —— 传说（规则改写）——
    "gear_perpetual": ("永动机", "gear", "a perpetual motion machine: a large wheel with hinged weighted arms around its rim, mounted on a brass stand, a ring of small cogs around its axle"),
    "star_retro": ("逆行", "star", "a planet drawn with a looping retrograde path that curls back on itself across the night sky, a small arrow-shaped comet following the loop"),
    "coin_partner": ("合伙契约", "coin", "two hands in ornate gold-embroidered sleeves clasping in a handshake above a single gold coin"),
    "mirror_myriad": ("万象镜", "mirror", "a tall arch-shaped mirror standing on a plain, reflecting a whole field of many identical small trees that do not exist in front of it"),
    # —— 诅咒 ——
    "curse_debt": ("债务", "coin", "a large heavy black iron ball and chain filling the lower half of the frame, lying on a torn blank parchment, a cracked copper coin beside it"),
}

# 新器物：id -> (中文名, 流派, 器物描述)
RELICS: dict[str, tuple[str, str, str]] = {
    "badge_gear": ("齿轮徽章", "gear", "a plain round bronze medal embossed with a cog wheel, hanging from a steel-blue ribbon"),
    "badge_forge": ("熔炉徽章", "forge", "a round bronze badge medal embossed with a flame, hanging from an ember-red ribbon"),
    "badge_star": ("星辰徽章", "star", "a round silver badge medal embossed with an eight-pointed star, hanging from an indigo ribbon"),
    "badge_coin": ("商会徽章", "coin", "a plain round gold medal embossed with a stack of coins, hanging from a gold ribbon"),
    "badge_mirror": ("镜像徽章", "mirror", "a plain round silver medal embossed with two mirrored crescent shapes (no letters around the rim), hanging from a grey ribbon"),
    "badge_seal": ("封印徽章", "seal", "a plain round bronze medal embossed with a small padlock, hanging from a plum ribbon"),
    "oilcan": ("油壶", "gear", "a small brass oil can with a long thin spout and a thumb pump"),
    "windkey": ("发条钥匙", "gear", "a large ornate bronze winding key with a butterfly-shaped handle"),
    "tongs": ("火钳", "forge", "a pair of long blacksmith tongs holding a glowing coal"),
    "firebrick": ("耐火砖", "forge", "a stack of three ochre fire bricks, the top one glowing at the edges"),
    "orrery": ("星象仪", "star", "a small brass orrery with planets on curved arms around a central sun sphere"),
    "hourglass": ("沙漏", "star", "an ornate hourglass with turned wooden posts and silver sand"),
    "piggy": ("存钱罐", "coin", "a round ceramic piggy bank painted with gold coins, a coin slot on its back"),
    "scales": ("天平", "coin", "a balanced brass scale with two hanging pans"),
    "twofaced": ("双面镜", "mirror", "a round double-sided silver mirror held in a brass ring on a swivel stand, shown slightly turned"),
    "silvering": ("镀银", "mirror", "a small faceted cut-glass bottle filled with shining liquid silver, a silver stopper on top"),
    "signet": ("蜡印", "seal", "a large bronze signet ring seen from the front, its flat face carved with a small tree emblem"),
    "timebox": ("时光匣", "seal", "a small wooden box with a round clock face set into its front, held shut by a plum wax seal"),
    "cart": ("手推车", "", "a small wooden wheelbarrow with a sapling in a pot inside it"),
    "lantern": ("提灯", "", "a classical bronze lantern with a warm glowing flame behind glass panels"),
    "almanac": ("历书", "", "a thick closed almanac book with a moon and sun on its cover, a ribbon bookmark"),
    "compass": ("罗盘", "", "an open brass pocket compass with an eight-pointed star dial"),
}

TILES: dict[str, tuple[str, str]] = {
    "land_ore": ("矿脉", "a dense flat surface of dark grey rock covered edge to edge with clusters of angular faceted steel-blue crystals and bronze metal nuggets, sharp geometric facets; no clouds, no water, no rivers, no trees, no landscape"),
    "land_lava": ("熔岩", "cracked dark-ochre crust with thin glowing ember-red lava lines between the plates, MID TONE not black"),
    "land_starwell": ("星井", "a round shallow well of deep indigo water reflecting tiny silver stars, a pale stone rim"),
    "land_goldsand": ("金沙", "evenly rippled desert sand of antique gold and cream in parallel wave lines, scattered small glinting gold nuggets"),
}

# 每个流派一套独立画风（古木系仍是 generate_art.py 的复古几何丝网风）。
#   plate: 牌面图版的画法；obj: 立牌 / 器物（白底抠图）的画法；colour: 色板。
STYLE = {
    "gear": {
        "plate": "a hand-coloured Victorian British copperplate engraving of a machine part, as in an "
                 "1850s London engineering magazine: dense, precise black-ink line work and cross-hatching, "
                 "the metal fully shaded and tinted with rich steel blue and polished brass, a soft "
                 "parchment-toned background with a few faint compass arcs. The engraving fills the whole "
                 "picture edge to edge - no plate border, no caption, no annotations, no characters.",
        "obj": "a 19th-century copperplate engraving: precise black-ink line work and cross-hatching, "
               "hand-tinted with steel blue and brass washes",
        "colour": "warm off-white paper, black ink, steel blue #5E7381, brass #B08A46, a touch of copper",
    },
    "forge": {
        "plate": "a dramatic Baroque oil painting lit only by firelight, strong chiaroscuro: a near-black "
                 "smoky background, the subject blazing with intense orange and gold light, glowing "
                 "sparks and embers, visible loose brushstrokes, like an 18th-century painting of an iron forge.",
        "obj": "a Baroque oil painting with strong firelight: rich brushstrokes, deep shadows on one side "
               "and hot orange-gold glowing highlights on the other",
        "colour": "soot black, deep umber, ember red #B4552F, molten orange, gold highlights",
    },
    "star": {
        "plate": "a page from a 17th-century European celestial atlas: a deep midnight-indigo ground, the "
                 "subject drawn in fine luminous gold-leaf line art with delicate engraved shading, tiny "
                 "silver star dots scattered across the sky joined by thin constellation lines, flat and elegant.",
        "obj": "fine gold-leaf line art with delicate engraved shading on deep indigo and silver, like a "
               "figure cut from a 17th-century celestial atlas",
        "colour": "midnight indigo #2A3160, deep blue #4D5683, gold leaf, pale silver, a little pearl white",
    },
    "coin": {
        "plate": "a Vienna Secession gilded painting in the manner of 1900s Vienna: the subject set against "
                 "a flat shimmering gold-leaf ground patterned with small squares, rectangles and dots like "
                 "a mosaic, thin Art Nouveau whiplash lines, luxurious and rich; no clouds, no waves.",
        "obj": "a gilded Vienna Secession style with gold-leaf surfaces and small mosaic squares",
        "colour": "gold leaf #C9A23F, antique gold #A6812F, deep emerald green, black, warm ivory",
    },
    "mirror": {
        "plate": "a calm 1930s surrealist painting: perfectly smooth matte brushwork with no visible strokes, "
                 "crisp clean edges, uncanny stillness and exact symmetry, a pale blue sky with soft white "
                 "clouds and a low horizon, long soft shadows.",
        "obj": "a smooth 1930s surrealist painting style: matte, no visible brushstrokes, crisp clean "
               "edges, soft cool light",
        "colour": "pale sky blue, cloud white, cool silver grey #7D8C99, soft slate, a touch of pale gold",
    },
    "seal": {
        "plate": "a leaded stained-glass window panel: the whole image built from pieces of glowing "
                 "translucent coloured glass separated by thick black lead lines, light shining through, "
                 "jewel tones, slight texture and bubbles in the glass. Purely decorative and secular - "
                 "no saints, no figures in robes, no halos.",
        "obj": "leaded stained glass: glowing translucent jewel-coloured glass pieces joined by thick "
               "black lead lines",
        "colour": "plum purple #7A4F6E, deep wine red, amber, midnight blue, a little emerald",
    },
}

CULTURE = ("CULTURE: European / Western traditions only. NOT East Asian: no Chinese or Japanese motifs, "
           "no dragons, no calligraphy, no Chinese characters, no seal script, no ukiyo-e waves, no ink-wash clouds, no swirling auspicious clouds, no pagoda roofs.")

PLATE_PROMPT = """\
A PICTURE ONLY - an illustration, never a page of text, a document, a chart or a sheet with writing.
Vertical illustrated plate for a fantasy card game.

SUBJECT: {motif}

STYLE: {plate}
{culture}
COMPOSITION: the subject is LARGE and dominant, filling about two thirds of the frame
height, clearly readable even at small size; the background is simple and uncluttered.
COLOUR: {colour}
FINISH: artwork bleeds to all four edges.
STRICTLY NO text or writing of any kind (no letters, numbers, small print, captions,
signature), no border, frame or margin line, and no religious symbols such as crosses.
"""

STANDEE_PROMPT = (
    "Illustration of {motif}, a single object shown whole and upright, painted as {obj}, "
    "isolated on a plain pure white background, centred, crisp dark outline, European style, "
    "colours: {colour}."
)

OBJECT_PROMPT = (
    "Illustration of {motif}, a single object shown whole and upright, painted as {obj}, "
    "isolated on a plain flat pale cream background, centred, crisp dark outline, European style, "
    "colours: {colour}."
)


def style(fam: str) -> dict[str, str]:
    st = STYLE[fam]
    return {"plate": st["plate"], "obj": st["obj"], "colour": st["colour"], "culture": CULTURE}


# 立牌单独的画面（奶油色纸张会被抠图抠掉，改用深色物件）
STANDEE_MOTIF = {
    "star_meteor": "a gold metal brooch shaped like a shooting star with a long tapering tail",
    "star_comet": "a bright golden comet head with one long straight silver tail of fine lines, no creatures, no swirls",
    "bridge_mirrorforge": "a small black iron furnace with a bright flame in its mouth, standing on a polished silver base that reflects it",
    "mirror_glass": "a round hand mirror with a thick dark ornate silver frame and handle, its glass showing a deep blue night reflection",
    "coin_contract": "a thick dark brown leather-bound ledger book standing upright, brass corner plates, "
                     "a red wax seal on its strap and a dark feather quill tucked in",
}


# 2026-11-21 审图后待重做（MiniMax 额度用完时中断）：--redo 只重做这些（会覆盖现有图）。
# 立牌单独的画面（奶油色纸张会被抠图抠掉，改用深色物件）
STANDEE_MOTIF = {
    "coin_contract": "a thick dark brown leather-bound ledger book standing upright, brass corner plates, a red wax seal on its strap and a dark feather quill tucked in",
}

# 地块单独的短提示词（图册风的长提示词总被画成东方山水）
TILE_OVERRIDE = {
    "land_ore": ("Seamless square floor texture seen from directly above: large irregular flagstones in warm "
                 "grey and cream, with bold zigzag veins of shiny steel-blue and bronze metal ore and clusters of "
                 "angular blue crystals clearly visible across the whole square, high contrast, flat graphic print style; no landscape, no mountains, no plants, no sky, no water, "
                 "no writing."),
}

REDO = [
    # 图版：带汉字 / 东方风格 / 跑题 / 十字架
    "gear_hub", "coin_contract", "coin_horn", "mirror_twin", "seal_box", "seal_wax", "seal_ward",
    "seal_thunder", "bridge_sealcoin", "curse_debt",
    # 立牌（已删除的坏图会先用流派徽记占位）
    "standee_gear_rivet", "standee_coin_contract", "standee_mirror_echo", "standee_mirror_twin",
    "standee_mirror_glass", "standee_seal_wax", "standee_seal_rune", "standee_seal_chain", "standee_bridge_sealcoin",
    # 器物与地块
    "relic_cut_badge_gear", "relic_cut_badge_coin", "relic_cut_badge_mirror", "relic_cut_badge_seal",
    "relic_cut_twofaced", "relic_cut_signet", "relic_cut_timebox", "land_ore", "land_goldsand",
]


def trim(p: str) -> str:
    return p if len(p) <= 1460 else p[:1455].rsplit(" ", 1)[0]


def jobs() -> list[tuple[str, str, str, str, int, object]]:
    """(id, 中文名, 种类, prompt, size, 抠图方式) 全部任务。"""
    out = []
    for cid, (cn, fam, motif) in CARDS.items():
        out.append((cid, cn, "cards", trim(PLATE_PROMPT.format(motif=motif, **style(fam))), 0, None))
        sm = STANDEE_MOTIF.get(cid, motif)
        out.append((f"standee_{cid}", cn, "standees", trim(STANDEE_PROMPT.format(motif=sm, **style(fam))), 768, "soft"))
    for rid, (cn, fam, motif) in RELICS.items():
        if fam:
            prompt = OBJECT_PROMPT.format(motif=motif, **style(fam))
        else:  # 通用器物沿用古木图册风
            prompt = ga.OBJECT_PROMPT.format(motif=motif)
        out.append((f"relic_cut_{rid}", cn, "relics", trim(prompt), 768, True))
    for tid, (cn, motif) in TILES.items():
        prompt = TILE_OVERRIDE.get(tid) or (ga.TILE_PROMPT.format(motif=motif) + CULTURE + " No writing anywhere.")
        out.append((tid, cn, "tiles", trim(prompt), 0, None))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--kind", default="", help="cards / standees / relics / tiles（逗号分隔）")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--size", type=int, default=768)
    ap.add_argument("--redo", action="store_true", help="重做 REDO 列表里审图不合格的图（覆盖）")
    ap.add_argument("--all", action="store_true", help="按新画风重做全部牌面 / 立牌 / 流派器物（覆盖，不含地块和通用器物）")
    ap.add_argument("--preview", default="", help="输出到这个目录而不是游戏素材目录（试画风用）")
    args = ap.parse_args()
    if args.preview:
        ga.OUT_DIR = Path(args.preview)
        args.force = True
    ga.OUT_DIR.mkdir(parents=True, exist_ok=True)
    ga.CACHE.mkdir(parents=True, exist_ok=True)
    only = {s for s in args.only.split(",") if s}
    if args.redo:
        only = set(REDO)
        args.force = True
    if args.all:
        only = {j[0] for j in jobs() if j[2] in ("cards", "standees") or (j[2] == "relics" and RELICS[j[0][10:]][1])}
        args.force = True
    kinds = {s for s in args.kind.split(",") if s}
    key = ga.api_key()
    todo = []
    for j in jobs():
        cid, _, kind = j[0], j[1], j[2]
        if only and cid not in only:
            continue
        if kinds and kind not in kinds:
            continue
        if (ga.OUT_DIR / f"{cid}.png").exists() and not args.force:
            continue
        todo.append(j)
    print(f"共 {len(todo)} 张待生成", flush=True)
    failed: list[str] = []

    def run(j) -> None:
        cid, cn, kind, prompt, size, cut = j
        aspect = "1:1" if kind in ("relics", "tiles") else "3:4"
        for attempt in range(3):
            try:
                raw = ga.call_api(key, prompt, aspect)
                break
            except Exception as e:  # noqa: BLE001
                print(f"  !! {cid} 第 {attempt + 1} 次失败: {e}", flush=True)
                time.sleep(5 * (attempt + 1))
        else:
            failed.append(cid)
            return
        (ga.CACHE / f"{cid}.jpg").write_bytes(raw)
        img = ga.harmonize(raw, size or args.size)
        if cut == "soft":
            img = ga.cutout_soft(img)
        elif cut:
            img = ga.cutout(img)
        else:
            img = ga.strip_borders(img)
        img.save(ga.OUT_DIR / f"{cid}.png")
        print(f"[done] {cid} ({cn}) {img.size}", flush=True)

    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        list(ex.map(run, todo))
    if failed:
        print("失败: " + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
