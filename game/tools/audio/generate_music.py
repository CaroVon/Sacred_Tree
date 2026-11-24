#!/usr/bin/env python3
"""用 MiniMax 音乐生成接口做背景音乐（纯音乐）。密钥读取方式与 generate_art.py 完全一致（复用它的 api_key）。

产物：game/assets/music/<id>.mp3
用法（仓库根目录）：
    python game/tools/audio/generate_music.py                # 生成全部缺失的
    python game/tools/audio/generate_music.py --only theme
    python game/tools/audio/generate_music.py --force
    python game/tools/audio/generate_music.py --probe        # 只试一下接口与可用模型
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "card_art"))
from generate_art import api_key  # noqa: E402

GAME = HERE.parents[1]
OUT = GAME / "assets" / "music"
API = "https://api.minimaxi.com/v1/music_generation"
MODELS = ["music-2.6", "music-2.5", "music-2.0", "music-3.0"]

STYLE = ("instrumental only, no vocals, no singing. Calm, meditative ambient chamber music for a contemplative "
         "card game about tending a sacred tree in an ancient ruined temple. Warm, intimate, slightly melancholic, "
         "timeless. Loopable, steady tempo, no sudden endings, soft dynamics.")

# id -> 描述
SPEC: dict[str, str] = {
    "theme": "Main theme. Solo plucked harp and guzheng-like zither over soft string pad, a gentle memorable melody, "
             "sense of wonder and sacred quiet, like dawn light in a marble colonnade.",
    "spring": "Spring. Light fingerpicked lute, wooden flute melody, birdsong-like ornaments, fresh and hopeful, "
              "moderate tempo 84 bpm.",
    "summer": "Summer noon. Warm marimba and kalimba ostinato with low cello drone, lazy and bright, "
              "shimmering heat, 90 bpm.",
    "autumn": "Autumn dusk. Nylon guitar and oboe, falling arpeggios, nostalgic golden-hour mood, 76 bpm.",
    "winter": "Winter moonlight. Sparse celesta and soft piano, long reverb, cold and still, music box feeling, 66 bpm.",
    "calamity": "Calamity season. Low taiko pulses, tense tremolo strings, dark drones, ominous but restrained, "
                "storm approaching, 100 bpm.",
    "market": "Night market among temple ruins. Gentle hand percussion, dulcimer and pizzicato strings, "
              "curious and cozy, 96 bpm.",
}


def call(key: str, model: str, prompt: str) -> dict:
    body = {
        "model": model,
        "prompt": prompt,
        "is_instrumental": True,
        "audio_setting": {"sample_rate": 44100, "bitrate": 128000, "format": "mp3"},
        "output_format": "hex",
    }
    req = urllib.request.Request(API, data=json.dumps(body).encode("utf-8"),
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        return json.loads(resp.read().decode("utf-8"))


def extract(d: dict) -> bytes | None:
    data = d.get("data") or {}
    audio = data.get("audio")
    if not audio:
        return None
    if audio.startswith("http"):
        with urllib.request.urlopen(audio, timeout=300) as r:
            return r.read()
    return bytes.fromhex(audio)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--model", default="")
    a = ap.parse_args()
    key = api_key()
    OUT.mkdir(parents=True, exist_ok=True)
    models = [a.model] if a.model else MODELS
    if a.probe:
        for m in models:
            try:
                d = call(key, m, STYLE + " Short test, 20 seconds.")
                print(m, "->", d.get("base_resp"), "audio" if extract(d) else "no audio")
            except urllib.error.HTTPError as e:
                print(m, "HTTP", e.code, e.read()[:300])
            except Exception as e:  # noqa: BLE001
                print(m, "ERR", e)
        return
    ids = [x for x in a.only.split(",") if x] or list(SPEC)
    for i in ids:
        dst = OUT / f"{i}.mp3"
        if dst.exists() and not a.force:
            print("skip", i)
            continue
        for m in models:
            try:
                d = call(key, m, STYLE + " " + SPEC[i])
            except urllib.error.HTTPError as e:
                print(i, m, "HTTP", e.code, e.read()[:200])
                continue
            raw = extract(d)
            if raw:
                dst.write_bytes(raw)
                print("ok", i, m, len(raw) // 1024, "KB")
                break
            print(i, m, "no audio", d.get("base_resp"))


if __name__ == "__main__":
    main()
