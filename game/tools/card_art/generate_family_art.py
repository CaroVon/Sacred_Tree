#!/usr/bin/env python3
"""新流派（齿轮 / 熔炉 / 星辰 / 商会 / 镜像 / 封印 / 桥牌）的美术：牌面图版、牌桌立牌、器物抠图、新地块。

沿用 generate_art.py 的接口调用、色调统一与抠图；画风保持「失落文明的古典典藏图册」，
但主角从植物换成各流派的器物，并给每个流派一个主题色点缀（其余仍是图册的哑光旧色）。

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

ACCENT = {
    "gear": ("steel blue", "#5E7381", "polished bronze"),
    "forge": ("ember red", "#B4552F", "glowing orange coals"),
    "star": ("deep indigo", "#4D5683", "pale silver starlight"),
    "coin": ("antique gold", "#A6812F", "stamped gold coins"),
    "mirror": ("cool silver grey", "#7D8C99", "polished silver glass"),
    "seal": ("plum purple", "#7A4F6E", "deep red sealing wax"),
}

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
    "forge_bellows": ("风箱", "forge", "a pair of leather blacksmith bellows with wooden handles and a bronze nozzle pointing at a small flame"),
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
    "coin_copper": ("铜币", "coin", "a neat stack of round copper coins with one large coin standing on its edge in front"),
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
    "mirror_echo": ("倒影", "mirror", "a small round bush on a stone ledge with its exact mirrored copy upside down beneath it, like a reflection in water"),
    "mirror_frame": ("镜框", "mirror", "an empty ornate rectangular mirror frame with carved corners, hanging on a column"),
    "mirror_phantom": ("幻影", "mirror", "a translucent ghostly double of a small tree standing beside a solid one, drawn in pale silver outline"),
    "mirror_kaleido": ("万花筒", "mirror", "a kaleidoscope tube and, behind it, a large perfectly symmetric six-fold kaleidoscope pattern"),
    "mirror_prism": ("棱镜", "mirror", "a solid triangular glass prism standing on a small brass base, two coloured light beams leaving it to the left and right"),
    "mirror_twin": ("双子", "mirror", "two identical classical Greek marble statues of youths standing back to back, perfectly mirrored, each holding a laurel branch"),
    "mirror_glass": ("镜面", "mirror", "a single round polished silver mirror on a small brass stand, one bright diagonal highlight across the glass"),
    # —— 封印 ——
    "seal_box": ("封印匣", "seal", "a small ornate bronze casket bound with two leather straps and closed with a large plum wax seal, faint light at the seams"),
    "seal_wax": ("蜡封", "seal", "a round blob of deep red sealing wax on a folded letter, pressed with a small tree emblem, a stick of red wax lying beside it"),
    "seal_rune": ("符文石", "seal", "an upright grey standing stone carved with simple glowing geometric lines and circles (no letters), moss at its base"),
    "seal_ward": ("护符", "seal", "a bronze protective amulet pendant on a leather cord, a round charm with a small tree emblem and a plum gem"),
    "seal_thunder": ("雷印", "seal", "a large bronze seal stamp standing upright, and above it a bright zigzag lightning bolt striking down from a dark storm cloud"),
    "seal_break": ("解印", "seal", "a wax seal cracking open with light bursting out of the crack, fragments flying"),
    "seal_hoard": ("秘藏", "seal", "an iron-bound treasure chest half buried in roots, locked with a seal, coins peeking out"),
    "seal_chain": ("锁链", "seal", "a heavy iron chain hanging from a ring and splitting into two chains, each ending in a small iron padlock"),
    # —— 桥牌 ——
    "bridge_bell": ("青铜钟", "gear", "a bronze bell hanging in a clockwork frame of cogs, stars engraved on its rim"),
    "bridge_mint": ("铸币炉", "forge", "a small furnace pouring molten gold into round coin moulds, finished coins stacked beside"),
    "bridge_starfire": ("星火", "forge", "a flame whose sparks rise and turn into silver stars in a night sky"),
    "bridge_goldgear": ("金齿轮", "coin", "a golden cog wheel whose teeth are stamped like coin edges, a coin slot in its hub"),
    "bridge_lockvine": ("锁藤", "gear", "a grapevine growing through and around bronze cog wheels, tendrils locking two gears together"),
    "bridge_spiritfruit": ("灵果", "star", "a single luminous fruit hanging from a branch under a crescent moon, glowing with silver light"),
    "bridge_mirrorforge": ("镜炉", "mirror", "a small furnace and its exact mirror image facing each other, flames reflected in a silver panel between them"),
    "bridge_sealcoin": ("封金匣", "seal", "a small brass coin box with a slot on top, a gold coin half inserted, its lid closed with a round plum wax seal"),
    # —— 诅咒 ——
    "curse_debt": ("债务", "coin", "a heavy black iron ball and chain lying on a blank torn parchment, a cracked copper coin beside it"),
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
    "silvering": ("镀银", "mirror", "a small silver flask of mirror silvering liquid with a brush beside it"),
    "signet": ("蜡印", "seal", "a bronze signet ring with a carved tree emblem, lying next to a round blob of red sealing wax"),
    "timebox": ("时光匣", "seal", "a small wooden box with a round clock face set into its front, held shut by a plum wax seal"),
    "cart": ("手推车", "", "a small wooden wheelbarrow with a sapling in a pot inside it"),
    "lantern": ("提灯", "", "a classical bronze lantern with a warm glowing flame behind glass panels"),
    "almanac": ("历书", "", "a thick closed almanac book with a moon and sun on its cover, a ribbon bookmark"),
    "compass": ("罗盘", "", "an open brass pocket compass with an eight-pointed star dial"),
}

TILES: dict[str, tuple[str, str]] = {
    "land_ore": ("矿脉", "pale grey stone ground crossed by thick bright veins of steel-blue and bronze ore, clusters of angular crystals, clearly patterned"),
    "land_lava": ("熔岩", "cracked dark-ochre crust with thin glowing ember-red lava lines between the plates, MID TONE not black"),
    "land_starwell": ("星井", "a round shallow well of deep indigo water reflecting tiny silver stars, a pale stone rim"),
    "land_goldsand": ("金沙", "evenly rippled desert sand of antique gold and cream in parallel wave lines, scattered small glinting gold nuggets"),
}

PLATE_PROMPT = """\
Vertical poster plate, flat screen-print style, for an illustrated tome of a lost
ancient civilisation.

SUBJECT: {motif}

STYLE: flat graphic poster, geometric-modernist. A few LARGE flat colour shapes with
hard edges, not a realistic drawing; no photorealism, no 3D. Fine engraved hatching as
light texture only.
CULTURE: European classical antiquity and Art Deco only (Greek, Roman, Mediterranean
temples, brass instruments). NOT East Asian: no Chinese or Japanese motifs, no dragons,
no calligraphy, no seal script, no ukiyo-e waves.
COMPOSITION: the subject is LARGE and dominant, filling two thirds of the frame height,
in the strongest contrast. Exactly ONE quiet framing shape behind it - a tall arch, a
stepped ziggurat, a broken pediment or a round medallion. Big areas of empty cream
space. A few four- and eight-pointed star sparkles of fine radiating lines.
COLOUR: matte old-print palette cream #EDE3C9, ochre #C9914A, terra #B04A2A, olive
#7B7A55, charcoal #2B2925, gold #B08A46, sage #A9A98C, plus the accent {accent} {hex}
used for the subject's key parts ({material}).
FINISH: light aged paper grain; artwork bleeds to all four edges.
STRICTLY NO text or writing of any kind (no letters, numbers, small print, captions,
signature), no border, frame or margin line, and no religious symbols such as crosses.
"""

STANDEE_PROMPT = """\
A single object cut out like a paper pop-up book standee, from an illustrated tome of
a lost ancient civilisation, flat screen-print style.

OBJECT: {motif}

STYLE: flat graphic, geometric-modernist, large simple flat colour shapes with hard
edges, a crisp charcoal outline around the whole silhouette, fine engraved hatching as
light texture. Upright, centred, compact silhouette filling about 75 percent of the
frame height, nothing touching the edges.
BACKGROUND: plain flat pure white #FFFFFF, like a studio photo of a single paper
cut-out on white; no floor line, no scene, no decoration.
CULTURE: European classical antiquity and Art Deco only (Greek, Roman, Mediterranean
temples, brass instruments). NOT East Asian: no Chinese or Japanese motifs, no dragons,
no calligraphy, no seal script, no ukiyo-e waves.
COLOUR: cream #EDE3C9, ochre #C9914A, terra #B04A2A, olive #7B7A55, charcoal #2B2925,
gold #B08A46, plus the accent {accent} {hex} ({material}).
ONE single physical object only - not a diagram, not an infographic, not a sheet of
icons, no labels, no writing of any kind.
STRICTLY NO text, letters, numbers, border or frame, and no religious symbols.
"""


# 2026-11-21 审图后待重做（MiniMax 额度用完时中断）：--redo 只重做这些（会覆盖现有图）。
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


def accent(fam: str) -> dict[str, str]:
    a = ACCENT.get(fam, ("warm gold", "#B08A46", "gilded details"))
    return {"accent": a[0], "hex": a[1], "material": a[2]}


def trim(p: str) -> str:
    return p if len(p) <= 1460 else p[:1455].rsplit(" ", 1)[0]


def jobs() -> list[tuple[str, str, str, str, int, object]]:
    """(id, 中文名, 种类, prompt, size, 抠图方式) 全部任务。"""
    out = []
    for cid, (cn, fam, motif) in CARDS.items():
        out.append((cid, cn, "cards", trim(PLATE_PROMPT.format(motif=motif, **accent(fam))), 0, None))
        out.append((f"standee_{cid}", cn, "standees", trim(STANDEE_PROMPT.format(motif=motif, **accent(fam))), 768, "soft"))
    for rid, (cn, fam, motif) in RELICS.items():
        prompt = ga.OBJECT_PROMPT.format(motif=motif + (", with small %s accents" % accent(fam)["accent"] if fam else ""))
        out.append((f"relic_cut_{rid}", cn, "relics", trim(prompt), 768, True))
    for tid, (cn, motif) in TILES.items():
        out.append((tid, cn, "tiles", trim(ga.TILE_PROMPT.format(motif=motif)), 0, None))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--kind", default="", help="cards / standees / relics / tiles（逗号分隔）")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--size", type=int, default=768)
    ap.add_argument("--redo", action="store_true", help="重做 REDO 列表里审图不合格的图（覆盖）")
    args = ap.parse_args()
    ga.OUT_DIR.mkdir(parents=True, exist_ok=True)
    ga.CACHE.mkdir(parents=True, exist_ok=True)
    only = {s for s in args.only.split(",") if s}
    if args.redo:
        only = set(REDO)
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
