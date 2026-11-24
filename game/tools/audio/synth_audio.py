#!/usr/bin/env python3
"""程序合成神树的音乐、环境音与音效（numpy + scipy，无外部服务）。

产物（单声道 16-bit WAV，Godot 导入时压缩）：
  game/assets/music/<id>.wav      每季 / 天灾 / 集市 / 主题的无缝循环
  game/assets/ambience/<id>.wav   风、鸟、虫、雨、火、冬风的无缝循环
  game/assets/sfx/<id>.wav        计分演出的新音效
用法（仓库根目录）：
  python game/tools/audio/synth_audio.py             # 全部
  python game/tools/audio/synth_audio.py music       # 只做音乐（ambience / sfx 同理）
  python game/tools/audio/synth_audio.py music spring
"""
from __future__ import annotations

import sys
import wave
import zlib
from pathlib import Path

import numpy as np
from scipy import signal

SR = 32000
GAME = Path(__file__).resolve().parents[2]
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- 基础
def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def midi_hz(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


def env_adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([np.linspace(0, 1, max(1, a_n)), np.linspace(1, s, max(1, d_n)), np.full(s_n, s),
                        np.linspace(s, 0, max(1, r_n))])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def lowpass(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    b, a = signal.butter(order, min(0.99, hz / (SR / 2)), "low")
    return signal.lfilter(b, a, x)


def highpass(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    b, a = signal.butter(order, [lo / (SR / 2), min(0.99, hi / (SR / 2))], "band")
    return signal.lfilter(b, a, x)


_ir_cache: dict = {}


def reverb(x: np.ndarray, size: float = 2.5, wet: float = 0.3, bright: float = 5000) -> np.ndarray:
    key = (size, bright)
    if key not in _ir_cache:
        n = int(size * SR)
        r = np.random.default_rng(11)
        ir = r.standard_normal(n) * np.exp(-np.linspace(0, 7, n))
        ir = lowpass(ir, bright)
        ir[: int(0.012 * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        _ir_cache[key] = ir
    wetsig = signal.fftconvolve(x, _ir_cache[key])[: len(x)]
    return x * (1 - wet) + wetsig * wet * 0.9


def place(buf: np.ndarray, snd: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = int(at * SR) % len(buf)
    end = i + len(snd)
    if end <= len(buf):
        buf[i:end] += snd * gain
    else:  # 绕回开头：保证循环无缝
        k = len(buf) - i
        buf[i:] += snd[:k] * gain
        buf[: end - len(buf)] += snd[k:] * gain


# ---------------------------------------------------------------- 乐器
def pluck(hz: float, dur: float, bright: float = 0.5, damp: float = 0.996) -> np.ndarray:
    """Karplus-Strong 拨弦（竖琴 / 琴 / 鲁特琴）。"""
    n = int(dur * SR)
    p = max(2, int(SR / hz))
    buf = rng.uniform(-1, 1, p)
    buf = lowpass(buf, 800 + 6000 * bright, 1)
    out = np.empty(n)
    idx = 0
    for i in range(n):
        v = buf[idx]
        nxt = buf[(idx + 1) % p]
        buf[idx] = damp * 0.5 * (v + nxt)
        out[i] = v
        idx = (idx + 1) % p
    out *= env_adsr(n, 0.002, 0.05, 1.0, min(0.3, dur * 0.3))
    return out * 0.6


def pluck_fast(hz: float, dur: float, bright: float = 0.5, decay: float = 2.5) -> np.ndarray:
    """加法合成的拨弦（比 KS 快，用于密集琶音）。"""
    t = t_axis(dur)
    x = np.zeros_like(t)
    for k in range(1, 8):
        x += (bright ** (k - 1)) / k * np.sin(2 * np.pi * hz * k * t) * np.exp(-t * decay * (1 + 0.6 * k))
    x *= env_adsr(len(t), 0.003, 0.0, 1.0, 0.05)
    return x * 0.5


def flute(hz: float, dur: float) -> np.ndarray:
    t = t_axis(dur)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.4, 0, 1)
    ph = 2 * np.pi * np.cumsum(hz * vib) / SR
    x = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    breath = bandpass(rng.standard_normal(len(t)), hz * 0.8, hz * 3) * 0.05
    return (x + breath) * env_adsr(len(t), 0.08, 0.1, 0.8, 0.25) * 0.35


def pad(hz: float, dur: float, warm: float = 1500) -> np.ndarray:
    t = t_axis(dur)
    x = np.zeros_like(t)
    for det in (-0.006, 0.0, 0.007):
        f = hz * (1 + det)
        ph = 2 * np.pi * f * t + rng.uniform(0, 6.28)
        x += signal.sawtooth(ph) * 0.33
    x = lowpass(x, warm, 2)
    return x * env_adsr(len(t), dur * 0.3, 0.1, 0.9, dur * 0.35) * 0.22


def bell(hz: float, dur: float, ratio: float = 3.5, index: float = 2.0) -> np.ndarray:
    """FM 钟 / 钢片琴。"""
    t = t_axis(dur)
    e = np.exp(-t * 3.0)
    x = np.sin(2 * np.pi * hz * t + index * e * np.sin(2 * np.pi * hz * ratio * t))
    return x * e * env_adsr(len(t), 0.002, 0, 1, 0.05) * 0.35


def marimba(hz: float, dur: float) -> np.ndarray:
    t = t_axis(dur)
    x = np.sin(2 * np.pi * hz * t) * np.exp(-t * 6) + 0.3 * np.sin(2 * np.pi * hz * 4 * t) * np.exp(-t * 18)
    return x * env_adsr(len(t), 0.002, 0, 1, 0.03) * 0.5


def drone(hz: float, dur: float) -> np.ndarray:
    t = t_axis(dur)
    x = np.sin(2 * np.pi * hz * t) + 0.5 * np.sin(2 * np.pi * hz * 2.003 * t) + 0.25 * np.sin(2 * np.pi * hz * 3 * t)
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.07 * t)
    return x * 0.12


def taiko(dur: float = 1.2, pitch: float = 70) -> np.ndarray:
    t = t_axis(dur)
    f = pitch * (1 + 1.5 * np.exp(-t * 30))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 5)
    x += lowpass(rng.standard_normal(len(t)), 1200) * np.exp(-t * 40) * 0.5
    return x * 0.8


def tremolo_strings(hz: float, dur: float) -> np.ndarray:
    x = pad(hz, dur, 2200)
    t = t_axis(dur)
    return x * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * t)) * 1.3


# ---------------------------------------------------------------- 作曲
PENTA = [0, 2, 4, 7, 9]


def scale_notes(root: int, mode: list[int], lo: int, hi: int) -> list[int]:
    return [root + o * 12 + s for o in range(-3, 5) for s in mode if lo <= root + o * 12 + s <= hi]


def melody(notes: list[int], beats: int, rr: np.random.Generator, rest: float = 0.25) -> list[tuple[float, int, float]]:
    """随机游走的五声旋律：(拍, midi, 时值拍数)。"""
    out = []
    i = len(notes) // 2
    b = 0.0
    while b < beats:
        dur = rr.choice([1.0, 1.0, 2.0, 0.5, 0.5, 1.5, 3.0])
        if rr.random() > rest:
            i = int(np.clip(i + rr.choice([-2, -1, -1, 0, 1, 1, 2]), 0, len(notes) - 1))
            out.append((b, notes[i], dur))
        b += dur
    return out


def finish(buf: np.ndarray, rev: float, wet: float, gain_db: float = -3.0) -> np.ndarray:
    # 循环混响：把整段接两遍做混响，取第二遍，尾巴自然绕回开头
    two = np.concatenate([buf, buf])
    two = reverb(two, rev, wet)
    y = two[len(buf):]
    y = highpass(y, 40, 1)
    peak = np.max(np.abs(y)) + 1e-9
    return y / peak * (10 ** (gain_db / 20))


def compose(name: str) -> np.ndarray:
    rr = np.random.default_rng(zlib.crc32(name.encode()))
    if name == "spring":
        bpm, root, prog, bars = 84, 62, [0, -3, 5, 7], 16
    elif name == "summer":
        bpm, root, prog, bars = 90, 65, [0, 5, -2, 7], 16
    elif name == "autumn":
        bpm, root, prog, bars = 76, 57, [0, -4, 5, -2], 16
    elif name == "winter":
        bpm, root, prog, bars = 66, 64, [0, -3, -7, -5], 12
    elif name == "calamity":
        bpm, root, prog, bars = 100, 50, [0, 1, 0, -2], 16
    elif name == "market":
        bpm, root, prog, bars = 96, 60, [0, 5, 7, 5], 16
    else:  # theme
        bpm, root, prog, bars = 72, 62, [0, 7, 9, 5], 16
    beat = 60.0 / bpm
    beats = bars * 4
    L = beats * beat
    buf = np.zeros(int(L * SR))
    bar_of_chord = bars // len(prog)
    mel_notes = scale_notes(root, PENTA, root + 7, root + 26)
    for ci, off in enumerate(prog):
        t0 = ci * bar_of_chord * 4 * beat
        clen = bar_of_chord * 4 * beat
        chord = [root - 12 + off, root - 5 + off, root + off + (3 if name in ("autumn", "calamity", "winter") else 4)]
        # 底：长音铺底 / 低音持续
        if name == "calamity":
            place(buf, drone(midi_hz(root - 24 + off), clen + 1.5), t0, 1.2)
            for c in chord[1:]:
                place(buf, tremolo_strings(midi_hz(c), clen + 1.0), t0, 0.7)
        else:
            for c in chord:
                place(buf, pad(midi_hz(c), clen + 2.0, 900 if name == "winter" else 1500), t0, 0.55)
            place(buf, drone(midi_hz(root - 24 + off), clen + 1.0), t0, 0.5)
        # 中：琶音
        arp = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[1] + 24]
        step = beat / (2 if name in ("summer", "market", "spring") else 1)
        n = int(clen / step)
        for k in range(n):
            if name == "winter" and k % 2:
                continue
            m = arp[k % len(arp)]
            at = t0 + k * step
            if name == "summer":
                place(buf, marimba(midi_hz(m), 0.7), at, 0.35)
            elif name == "winter":
                place(buf, bell(midi_hz(m + 12), 2.0, 3.01, 1.2), at, 0.22)
            elif name == "calamity":
                if k % 4 == 0:
                    place(buf, taiko(1.2, 55 if k % 8 == 0 else 72), at, 0.9)
            else:
                place(buf, pluck_fast(midi_hz(m), 1.6, 0.45, 2.2), at, 0.3)
    # 上：旋律（主题 / 春 / 秋 / 集市）
    lead = {"theme": "pluck", "spring": "flute", "autumn": "flute", "market": "pluck", "summer": "flute",
            "winter": "bell", "calamity": None}[name]
    if lead:
        for b, m, d in melody(mel_notes, beats, rr, 0.35 if name != "theme" else 0.2):
            at = b * beat
            if lead == "flute":
                place(buf, flute(midi_hz(m), d * beat * 0.95), at, 0.55)
            elif lead == "bell":
                place(buf, bell(midi_hz(m + 12), 3.0, 3.5, 1.5), at, 0.25)
            else:
                place(buf, pluck(midi_hz(m), 2.2, 0.6), at, 0.7)
    return finish(buf, 3.0 if name == "winter" else 2.4, 0.35 if name != "calamity" else 0.25, -4.0)


# ---------------------------------------------------------------- 环境音（30 秒循环）
def loopify(x: np.ndarray, fade: float = 2.0) -> np.ndarray:
    n = int(fade * SR)
    head, body = x[:n], x[n:]
    w = np.linspace(0, 1, n)
    body[-n:] = body[-n:] * (1 - w) + head * w
    return body


def ambience(name: str) -> np.ndarray:
    dur = 32.0
    t = t_axis(dur)
    noise = rng.standard_normal(len(t))
    if name == "wind":
        lfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.06 * t) * np.sin(2 * np.pi * 0.023 * t + 1)
        x = bandpass(noise, 200, 900) * (0.3 + 0.7 * lfo)
    elif name == "winter_wind":
        lfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t + 2)
        x = bandpass(noise, 500, 2200, 3) * (0.25 + 0.75 * lfo) + bandpass(noise, 150, 400) * 0.4
    elif name == "rain":
        x = highpass(noise, 1500) * 0.35 + bandpass(noise, 300, 1200) * 0.2
        for _ in range(500):
            place(x, bell(rng.uniform(2500, 5000), 0.05, 1.5, 0.5) * rng.uniform(0.1, 0.4), rng.uniform(0, dur))
    elif name == "fire":
        x = lowpass(noise, 500) * 0.4
        for _ in range(900):
            c = highpass(rng.standard_normal(int(rng.uniform(0.002, 0.012) * SR)), 1500)
            place(x, c * rng.uniform(0.2, 1.0), rng.uniform(0, dur))
    elif name == "birds":
        x = bandpass(noise, 200, 700) * 0.15
        for _ in range(40):
            at = rng.uniform(0, dur)
            base = rng.uniform(2200, 4200)
            for k in range(rng.integers(2, 6)):
                n = int(rng.uniform(0.05, 0.12) * SR)
                tt = np.arange(n) / SR
                f = base * (1 + rng.uniform(-0.3, 0.3) * tt / tt[-1])
                chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / tt[-1])
                place(x, chirp * 0.25, at + k * rng.uniform(0.08, 0.16))
    elif name == "crickets":
        x = bandpass(noise, 200, 700) * 0.1
        pulse = (np.sin(2 * np.pi * 28 * t) > 0.3).astype(float)
        gate = (np.sin(2 * np.pi * 0.9 * t) > -0.2).astype(float)
        x = x + np.sin(2 * np.pi * 4300 * t) * lowpass(pulse * gate, 300) * 0.12
    else:
        x = noise * 0.0
    x = reverb(x, 1.5, 0.25)
    x = loopify(x)
    return x / (np.max(np.abs(x)) + 1e-9) * 0.5


# ---------------------------------------------------------------- 音效
def sfx(name: str) -> np.ndarray:
    if name == "slam":  # 倍率重击：低音轰 + 裂响
        x = taiko(1.6, 48) * 1.2
        crack = highpass(rng.standard_normal(int(0.15 * SR)), 2000) * np.exp(-np.linspace(0, 12, int(0.15 * SR)))
        place(x, crack * 0.6, 0.0)
        return reverb(x, 2.0, 0.3)
    if name == "boom":  # 大档冲击：更重、带长尾
        x = taiko(2.4, 38) * 1.4
        t = t_axis(2.4)
        x += np.sin(2 * np.pi * 55 * t) * np.exp(-t * 1.5) * 0.5
        return reverb(x, 3.0, 0.4)
    if name == "pattern":  # 牌型：明亮的钟声琶音
        x = np.zeros(int(1.6 * SR))
        for k, m in enumerate([76, 81, 88]):
            place(x, bell(midi_hz(m), 1.4, 3.5, 1.8), k * 0.06, 0.6)
        return reverb(x, 2.0, 0.35)
    if name == "chord":  # 共鸣升层：温暖的大三和弦
        x = np.zeros(int(2.4 * SR))
        for k, m in enumerate([62, 66, 69, 74]):
            place(x, pluck_fast(midi_hz(m), 2.2, 0.55, 1.4), k * 0.07, 0.8)
            place(x, pad(midi_hz(m - 12), 2.2, 1800), 0.0, 0.5)
        return reverb(x, 2.5, 0.4)
    if name == "overkill":  # 超额：上行钟声瀑布
        x = np.zeros(int(2.2 * SR))
        for k, m in enumerate([72, 76, 79, 84, 88, 91, 96]):
            place(x, bell(midi_hz(m), 1.5, 3.5, 2.2), k * 0.05, 0.5)
        return reverb(x, 2.5, 0.4)
    if name == "goal":  # 达标：钟 + 拨弦和弦
        x = np.zeros(int(2.6 * SR))
        for k, m in enumerate([67, 71, 74, 79]):
            place(x, pluck_fast(midi_hz(m), 2.4, 0.6, 1.2), k * 0.08, 0.8)
        place(x, bell(midi_hz(91), 2.4, 3.5, 1.5), 0.32, 0.6)
        return reverb(x, 3.0, 0.4)
    if name == "flow":  # 流动的一滴（按深度升调播放）
        t = t_axis(0.25)
        f = 900 * (1 + 0.6 * np.exp(-t * 40))
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 18)
        return reverb(x * 0.5, 1.0, 0.2)
    if name == "draw":  # 抽牌：纸张摩擦
        n = int(0.18 * SR)
        x = bandpass(rng.standard_normal(n), 1500, 7000) * np.sin(np.linspace(0, np.pi, n)) ** 2
        return x * 0.5
    if name == "reward":  # 得牌 / 器物：闪光
        x = np.zeros(int(1.4 * SR))
        for k in range(8):
            place(x, bell(midi_hz(84 + PENTA[k % 5] + 12 * (k // 5)), 0.8, 2.0, 1.0), k * 0.035, 0.35)
        return reverb(x, 2.0, 0.4)
    if name == "banner":  # 横幅：柔和的锣
        t = t_axis(3.0)
        x = sum(np.sin(2 * np.pi * 110 * r * t) * np.exp(-t * (0.8 + r * 0.4)) / r for r in (1, 2.41, 3.77, 5.1))
        return reverb(x * 0.4, 3.0, 0.35)
    if name == "season":  # 季节开场：钟 + 长音
        x = np.zeros(int(3.0 * SR))
        place(x, bell(midi_hz(74), 2.8, 2.0, 1.0), 0.0, 0.7)
        place(x, pad(midi_hz(62), 2.8, 1500), 0.0, 0.8)
        return reverb(x, 3.0, 0.4)
    if name == "shatter":  # 天灾毁牌：木头断裂
        n = int(0.5 * SR)
        x = highpass(rng.standard_normal(n), 800) * np.exp(-np.linspace(0, 10, n))
        x += taiko(0.5, 120)[:n] * 0.5
        return reverb(x, 1.5, 0.25)
    raise KeyError(name)


SFX = ["slam", "boom", "pattern", "chord", "overkill", "goal", "flow", "draw", "reward", "banner", "season", "shatter"]
MUSIC = ["theme", "spring", "summer", "autumn", "winter", "calamity", "market"]
AMB = ["wind", "winter_wind", "rain", "fire", "birds", "crickets"]


def save(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pk = np.max(np.abs(x)) + 1e-9
    if pk > 0.99:
        x = x / pk * 0.99
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", path.relative_to(GAME), f"{len(x) / SR:.1f}s")


def main() -> None:
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    only = sys.argv[2:]
    if what in ("all", "sfx"):
        for n in (only or SFX):
            save(GAME / "assets" / "sfx" / f"{n}.wav", sfx(n))
    if what in ("all", "ambience"):
        for n in (only or AMB):
            save(GAME / "assets" / "ambience" / f"{n}.wav", ambience(n))
    if what in ("all", "music"):
        for n in (only or MUSIC):
            save(GAME / "assets" / "music" / f"{n}.wav", compose(n))


if __name__ == "__main__":
    main()
