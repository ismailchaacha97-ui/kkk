#!/usr/bin/env python3
"""
Studio-Grade YouTube Short Renderer: "The Atomic Secret Inside Every Painting"
1080x1920 @ 30fps vertical cinema with:
- Auto-trimmed full-bleed hand-inked gouache graphic-novel artwork
- Subpixel smooth camera choreography + bespoke per-scene visual FX
- Waveform-aligned editorial kinetic captions & archival chapter HUD stamps
- Original procedural stereo soundtrack + sound design with sidechain voice ducking
"""

import math
import os
import subprocess
import numpy as np
import scipy.io.wavfile as wavfile
import scipy.signal as signal
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import imageio_ffmpeg

W, H = 1080, 1920
FPS = 30
SR = 44100

ROOT = "/home/user/kkk"
CACHE = os.path.join(ROOT, ".cache")
FONT_DIR = os.path.join(CACHE, "fonts")
AUDIO_IN_DIR = os.path.join(CACHE, "audio")
WORK_DIR = os.path.join(CACHE, "render_work")
SCENE_DIR = os.path.join(ROOT, "shorts", "scenes")
OUT_MP4 = os.path.join(ROOT, "shorts", "atomic_art_secret_short.mp4")

os.makedirs(WORK_DIR, exist_ok=True)
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

# Color Palette (Graphic Novel Chiaroscuro + Isotope Emerald)
GOLD = (245, 184, 65)
EMERALD = (92, 235, 142)
CORAL_RED = (242, 100, 87)
IVORY = (248, 245, 238)
MUTED_SLATE = (182, 196, 214)
DARK_GLASS = (10, 16, 26, 208)

# 10 Story Beats with curated phrase chunks, highlighted keywords, camera direction & HUD stamps
SCENES = [
    {
        "id": 1,
        "img": "scene_01_hook.jpg",
        "tag": ("CASE FILE // 01", "ART FORENSICS", EMERALD),
        "cam": {"z0": 1.03, "z1": 1.15, "x0": 0.50, "x1": 0.52, "y0": 0.46, "y1": 0.42},
        "vfx": "laser_scan",
        "pause_after": 0.14,
        "phrases": [
            ("Every painting made", {}),
            ("before 1945", {"1945": GOLD}),
            ("hides a secret", {"secret": EMERALD}),
            ("no art forger on Earth", {"forger": GOLD}),
            ("can fake.", {"fake.": CORAL_RED}),
        ],
    },
    {
        "id": 2,
        "img": "scene_02_forger.jpg",
        "tag": ("PRE-1945 ERA", "THE PERFECT FORGERY", GOLD),
        "cam": {"z0": 1.13, "z1": 1.04, "x0": 0.54, "x1": 0.47, "y0": 0.48, "y1": 0.50},
        "vfx": "candle_flicker",
        "pause_after": 0.12,
        "phrases": [
            ("For centuries, master forgers", {"master": GOLD, "forgers": GOLD}),
            ("fooled the world's top museums", {"fooled": CORAL_RED}),
            ("by scraping antique canvases clean", {"antique": GOLD}),
            ("and painting right over them.", {}),
        ],
    },
    {
        "id": 3,
        "img": "scene_03_loupe.jpg",
        "tag": ("COUNTERFEIT METHOD", "ARTIFICIAL CRAQUELURE", GOLD),
        "cam": {"z0": 1.17, "z1": 1.03, "x0": 0.46, "x1": 0.50, "y0": 0.50, "y1": 0.48},
        "vfx": "loupe_glint",
        "pause_after": 0.26,  # Dramatic breath right before July 16, 1945!
        "phrases": [
            ("They even baked fresh oil paint", {"baked": GOLD}),
            ("in ovens to fake", {}),
            ("300-year-old cracks.", {"300-year-old": GOLD}),
            ("To the naked eye,", {}),
            ("the illusion was flawless.", {"flawless.": EMERALD}),
        ],
    },
    {
        "id": 4,
        "img": "scene_04_trinity.jpg",
        "tag": ("JULY 16, 1945", "TRINITY TEST // NEW MEXICO", GOLD),
        "cam": {"z0": 1.15, "z1": 1.03, "x0": 0.52, "x1": 0.50, "y0": 0.55, "y1": 0.46},
        "vfx": "trinity_flash",
        "pause_after": 0.14,
        "phrases": [
            ("Until July 16, 1945,", {"July": GOLD, "16,": GOLD, "1945,": GOLD}),
            ("when the first atomic test", {"atomic": CORAL_RED}),
            ("lit up the New Mexico desert.", {"New": GOLD, "Mexico": GOLD}),
        ],
    },
    {
        "id": 5,
        "img": "scene_05_fallout.jpg",
        "tag": ("GLOBAL FALLOUT", "ISOTOPE // CESIUM-137", EMERALD),
        "cam": {"z0": 1.04, "z1": 1.14, "x0": 0.50, "x1": 0.50, "y0": 0.56, "y1": 0.42},
        "vfx": "isotope_drift",
        "pause_after": 0.12,
        "phrases": [
            ("That blast scattered", {}),
            ("brand-new man-made isotopes,", {"man-made": EMERALD, "isotopes,": EMERALD}),
            ("like Cesium-137,", {"Cesium-137,": EMERALD}),
            ("across the entire planet's", {}),
            ("atmosphere.", {"atmosphere.": GOLD}),
        ],
    },
    {
        "id": 6,
        "img": "scene_06_flax.jpg",
        "tag": ("BIO-CHAIN VECTOR", "FLAX TO LINSEED OIL", EMERALD),
        # Story-driven top-to-bottom camera tilt from sky/flax down to linseed oil & brushes!
        "cam": {"z0": 1.12, "z1": 1.12, "x0": 0.50, "x1": 0.50, "y0": 0.34, "y1": 0.66},
        "vfx": "flax_pollen",
        "pause_after": 0.14,
        "phrases": [
            ("Those microscopic particles", {"microscopic": EMERALD}),
            ("drifted onto flax fields,", {"flax": GOLD}),
            ("soaked into the seeds", {}),
            ("pressed for linseed oil,", {"linseed": GOLD, "oil,": GOLD}),
            ("and mixed straight into", {}),
            ("every artist's paint.", {"paint.": EMERALD}),
        ],
    },
    {
        "id": 7,
        "img": "scene_07_microscope.jpg",
        "tag": ("MICRO-SAMPLING", "SAMPLE MASS // UNDER 0.1 MG", EMERALD),
        "cam": {"z0": 1.03, "z1": 1.16, "x0": 0.50, "x1": 0.49, "y0": 0.50, "y1": 0.56},
        "vfx": "forensic_reticle",
        "pause_after": 0.12,
        "phrases": [
            ("Today, forensic scientists", {"forensic": EMERALD}),
            ("only need a speck of pigment", {"speck": GOLD}),
            ("smaller than an eyelash.", {"eyelash.": EMERALD}),
        ],
    },
    {
        "id": 8,
        "img": "scene_08_detector.jpg",
        "tag": ("GAMMA SPECTROMETRY", "662 keV SPIKE DETECTED", EMERALD),
        "cam": {"z0": 1.04, "z1": 1.14, "x0": 0.48, "x1": 0.55, "y0": 0.48, "y1": 0.49},
        "vfx": "oscilloscope_pulse",
        "pause_after": 0.16,
        "phrases": [
            ("If their detector catches", {}),
            ("even a whisper of post-war fallout,", {"fallout,": EMERALD}),
            ("that supposed 17th-century", {"17th-century": GOLD}),
            ("masterpiece is exposed", {"exposed": CORAL_RED}),
            ("as a modern fake.", {"modern": CORAL_RED, "fake.": CORAL_RED}),
        ],
    },
    {
        "id": 9,
        "img": "scene_09_shipwreck.jpg",
        "tag": ("LOW-BACKGROUND STEEL", "PRE-1945 SUNKEN WRECKS", GOLD),
        "cam": {"z0": 1.04, "z1": 1.14, "x0": 0.50, "x1": 0.53, "y0": 0.54, "y1": 0.47},
        "vfx": "underwater_sparks",
        "pause_after": 0.15,
        "phrases": [
            ("Wildest of all?", {"Wildest": GOLD}),
            ("Labs actually salvage steel", {"salvage": GOLD, "steel": GOLD}),
            ("from pre-1945 sunken shipwrecks", {"pre-1945": EMERALD, "shipwrecks": GOLD}),
            ("just to build radiation shields", {"radiation": EMERALD}),
            ("clean enough to run the test.", {}),
        ],
    },
    {
        "id": 10,
        "img": "scene_10_signature.jpg",
        "tag": ("THE ATOMIC WATERMARK", "HISTORY SIGNED IN ATOMS", EMERALD),
        "cam": {"z0": 1.03, "z1": 1.16, "x0": 0.50, "x1": 0.50, "y0": 0.48, "y1": 0.53},
        "vfx": "atomic_signature",
        "pause_after": 0.06,  # Seamless handoff into Frame 0 loop!
        "phrases": [
            ("The moment humanity", {}),
            ("split the atom,", {"split": GOLD, "atom,": EMERALD}),
            ("we accidentally signed", {"signed": GOLD}),
            ("every canvas on Earth.", {"every": EMERALD, "canvas": EMERALD}),
            ("And that is why...", {"why...": GOLD}),
        ],
    },
]


def count_syllables(word: str) -> float:
    w = "".join(ch for ch in word.lower() if ch.isalpha() or ch.isdigit())
    if not w:
        return 1.0
    if w.isdigit():
        return max(2.0, len(w) * 1.1)
    vowels = "aeiouy"
    count = 0
    prev_v = False
    for ch in w:
        is_v = ch in vowels
        if is_v and not prev_v:
            count += 1
        prev_v = is_v
    if w.endswith("e") and count > 1:
        count -= 0.5
    return max(1.0, float(count))


def phrase_weight(text: str) -> float:
    words = text.split()
    syl = sum(count_syllables(w) for w in words)
    punct_bonus = 0.35 if any(text.endswith(p) for p in [",", ".", "?", "..."]) else 0.0
    return syl + punct_bonus


def tighten_pauses(arr: np.ndarray, sr: int, thresh=0.008, max_pause_s=0.14, keep_pause_s=0.075) -> np.ndarray:
    idx = np.where(np.abs(arr) > thresh)[0]
    if len(idx) == 0:
        return arr
    pad = int(0.025 * sr)
    s0 = max(0, idx[0] - pad)
    e0 = min(len(arr), idx[-1] + pad)
    arr = arr[s0:e0]

    hop = int(0.01 * sr)
    n_hops = len(arr) // hop
    silent = np.zeros(n_hops, dtype=bool)
    for k in range(n_hops):
        seg = arr[k * hop : (k + 1) * hop]
        if np.sqrt(np.mean(seg**2)) < thresh:
            silent[k] = True

    out_chunks = []
    k = 0
    max_hops = int(max_pause_s / 0.01)
    keep_hops = max(2, int(keep_pause_s / 0.01))
    while k < n_hops:
        if not silent[k]:
            out_chunks.append(arr[k * hop : (k + 1) * hop])
            k += 1
        else:
            j = k
            while j < n_hops and silent[j]:
                j += 1
            run = j - k
            if run > max_hops:
                half = keep_hops // 2
                a = arr[k * hop : (k + half) * hop]
                b = arr[(j - half) * hop : j * hop]
                out_chunks.append(a)
                out_chunks.append(b)
            else:
                out_chunks.append(arr[k * hop : j * hop])
            k = j
    if n_hops * hop < len(arr):
        out_chunks.append(arr[n_hops * hop :])
    res = np.concatenate(out_chunks)
    # 12ms micro fade-in/out to prevent clicks
    fade = min(int(0.012 * sr), len(res) // 4)
    if fade > 0:
        res[:fade] *= np.linspace(0.0, 1.0, fade, dtype=np.float32)
        res[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
    return res


def align_phrases_to_waveform(audio: np.ndarray, sr: int, phrases: list):
    """
    Aligns curated phrase cards to actual energy valleys around expected syllable ratios
    so captions snap cleanly to natural speech phrasing.
    """
    dur = len(audio) / sr
    n = len(phrases)
    if n == 1:
        return [(0.0, dur, phrases[0][0], phrases[0][1])]

    weights = np.array([phrase_weight(p[0]) for p in phrases], dtype=np.float64)
    cum = np.cumsum(weights) / np.sum(weights)

    # Compute smoothed 10ms RMS envelope
    hop = int(0.01 * sr)
    n_hops = max(1, len(audio) // hop)
    rms = np.array(
        [np.sqrt(np.mean(audio[k * hop : (k + 1) * hop] ** 2) + 1e-9) for k in range(n_hops)]
    )
    # Smooth slightly (30ms)
    kernel = np.ones(3) / 3.0
    rms_smooth = np.convolve(rms, kernel, mode="same")

    boundaries = [0.0]
    for i in range(n - 1):
        target_t = cum[i] * dur
        # Search +-0.22s window around target_t for the lowest energy valley (natural word boundary)
        win_lo = max(boundaries[-1] + 0.22, target_t - 0.22)
        win_hi = min(dur - 0.22 * (n - 1 - i), target_t + 0.22)
        if win_hi <= win_lo:
            boundaries.append(target_t)
            continue
        k_lo = max(0, int(win_lo / 0.01))
        k_hi = min(n_hops - 1, int(win_hi / 0.01))
        if k_hi > k_lo:
            # Penalize distance from target_t gently so we pick a nearby speech dip
            ks = np.arange(k_lo, k_hi + 1)
            ts = ks * 0.01
            dist_penalty = 0.35 * ((ts - target_t) / 0.22) ** 2
            norm_rms = rms_smooth[k_lo : k_hi + 1] / (np.max(rms_smooth) + 1e-6)
            best_k = ks[int(np.argmin(norm_rms + dist_penalty))]
            boundaries.append(float(best_k * 0.01))
        else:
            boundaries.append(target_t)
    boundaries.append(dur)

    aligned = []
    for i in range(n):
        aligned.append((boundaries[i], boundaries[i + 1], phrases[i][0], phrases[i][1]))
    return aligned


def prepare_narration_and_timeline():
    """Processes all 10 voice clips, computes exact frame boundaries, and builds master VO track."""
    vo_segments = []
    timeline = []
    cursor_s = 0.10  # 3-frame crisp visual pre-roll

    # Lead silence
    vo_segments.append(np.zeros(int(cursor_s * SR), dtype=np.float32))

    for sc in SCENES:
        cid = sc["id"]
        mp3_path = os.path.join(AUDIO_IN_DIR, f"clip_{cid:02d}.mp3")
        raw_wav = os.path.join(WORK_DIR, f"raw_{cid:02d}.wav")
        tight_wav = os.path.join(WORK_DIR, f"tight_{cid:02d}.wav")
        proc_wav = os.path.join(WORK_DIR, f"proc_{cid:02d}.wav")

        subprocess.run(
            [FFMPEG, "-y", "-i", mp3_path, "-ar", str(SR), "-ac", "1", raw_wav],
            check=True,
            capture_output=True,
        )
        _, raw_i16 = wavfile.read(raw_wav)
        arr = raw_i16.astype(np.float32) / 32768.0
        tight = tighten_pauses(arr, SR)
        wavfile.write(tight_wav, SR, np.clip(tight * 32767, -32768, 32767).astype(np.int16))

        # Broadcast voice polish + gentle 1.18x documentary pacing (100% natural pitch)
        af = (
            "atempo=1.18,"
            "highpass=f=80,"
            "equalizer=f=220:t=q:w=1.2:g=1.5,"
            "equalizer=f=3600:t=q:w=1.4:g=2.2,"
            "acompressor=threshold=-19dB:ratio=2.6:attack=8:release=110:makeup=2.5dB,"
            "alimiter=limit=0.90"
        )
        subprocess.run(
            [FFMPEG, "-y", "-i", tight_wav, "-filter:a", af, "-ar", str(SR), "-ac", "1", proc_wav],
            check=True,
            capture_output=True,
        )
        _, proc_i16 = wavfile.read(proc_wav)
        proc = proc_i16.astype(np.float32) / 32768.0

        clip_dur = len(proc) / SR
        pause_after = sc["pause_after"]
        scene_start = 0.0 if cid == 1 else cursor_s
        speech_start = cursor_s
        scene_end = speech_start + clip_dur + pause_after

        aligned_phrases = align_phrases_to_waveform(proc, SR, sc["phrases"])
        abs_phrases = [
            (speech_start + p0, speech_start + p1, txt, hl)
            for (p0, p1, txt, hl) in aligned_phrases
        ]

        timeline.append(
            {
                **sc,
                "start_s": scene_start,
                "speech_start_s": speech_start,
                "end_s": scene_end,
                "dur_s": scene_end - scene_start,
                "abs_phrases": abs_phrases,
            }
        )

        vo_segments.append(proc)
        vo_segments.append(np.zeros(int(pause_after * SR), dtype=np.float32))
        cursor_s = scene_end

    vo_mono = np.concatenate(vo_segments)
    # Snap total length to exact multiple of 1/FPS so video & audio end on identical sample/frame!
    total_frames = int(round((len(vo_mono) / SR) * FPS))
    target_samples = int(round((total_frames / FPS) * SR))
    if len(vo_mono) < target_samples:
        vo_mono = np.pad(vo_mono, (0, target_samples - len(vo_mono)))
    else:
        vo_mono = vo_mono[:target_samples]
    timeline[-1]["end_s"] = total_frames / FPS
    timeline[-1]["dur_s"] = timeline[-1]["end_s"] - timeline[-1]["start_s"]

    return vo_mono, timeline, total_frames


def build_cinematic_soundtrack(vo_mono: np.ndarray, timeline: list) -> np.ndarray:
    """
    Synthesizes an original stereo documentary score + sound effects tailored to the 10 scenes,
    sidechain-ducked cleanly beneath the narrator's voice.
    """
    n_samples = len(vo_mono)
    t = np.arange(n_samples, dtype=np.float64) / SR
    left = np.zeros(n_samples, dtype=np.float64)
    right = np.zeros(n_samples, dtype=np.float64)

    def add_stereo(sig, start_s, pan=0.0, gain=1.0):
        i0 = max(0, int(start_s * SR))
        i1 = min(n_samples, i0 + len(sig))
        if i1 <= i0:
            return
        seg = sig[: i1 - i0] * gain
        gl = math.cos((pan + 1.0) * math.pi / 4.0)
        gr = math.sin((pan + 1.0) * math.pi / 4.0)
        left[i0:i1] += seg * gl
        right[i0:i1] += seg * gr

    def warm_pad(freqs, dur_s, attack=0.6, release=0.8, bright=900.0):
        ns = int(dur_s * SR)
        lt = np.arange(ns, dtype=np.float64) / SR
        out_l = np.zeros(ns, dtype=np.float64)
        out_r = np.zeros(ns, dtype=np.float64)
        for idx_f, f in enumerate(freqs):
            # Rich warm detuned saw/triangle hybrid
            detune = 1.0035 if idx_f % 2 == 0 else 0.9965
            vib = 1.0 + 0.0012 * np.sin(2 * np.pi * 4.2 * lt + idx_f)
            ph1 = 2 * np.pi * f * vib * lt
            ph2 = 2 * np.pi * (f * detune) * lt + 0.7
            w1 = 0.65 * np.sin(ph1) + 0.22 * np.sin(2 * ph1) + 0.10 * np.sin(3 * ph1)
            w2 = 0.65 * np.sin(ph2) + 0.22 * np.sin(2 * ph2) + 0.10 * np.sin(3 * ph2)
            out_l += w1 / len(freqs)
            out_r += w2 / len(freqs)
        sos = signal.butter(2, bright / (SR / 2), btype="low", output="sos")
        out_l = signal.sosfilt(sos, out_l)
        out_r = signal.sosfilt(sos, out_r)
        env = np.ones(ns, dtype=np.float64)
        na = min(ns // 2, int(attack * SR))
        nr = min(ns // 2, int(release * SR))
        if na > 0:
            env[:na] = np.linspace(0.0, 1.0, na) ** 1.5
        if nr > 0:
            env[-nr:] = np.linspace(1.0, 0.0, nr) ** 1.5
        return out_l * env, out_r * env

    s4_start = timeline[3]["speech_start_s"]  # July 16, 1945!
    s5_start = timeline[4]["start_s"]
    s7_start = timeline[6]["start_s"]
    s8_start = timeline[7]["start_s"]
    s9_start = timeline[8]["start_s"]
    s10_start = timeline[9]["start_s"]
    total_dur = n_samples / SR

    # 1. Act I Mystery Bowed Drone (0 -> s4_start - 0.18s): D2 (73.42), A2 (110.0), F3 (174.61)
    act1_dur = max(1.0, s4_start - 0.18)
    p_l, p_r = warm_pad([73.42, 110.00, 146.83, 174.61], act1_dur, attack=0.25, release=0.35, bright=650.0)
    left[: len(p_l)] += p_l * 0.24
    right[: len(p_r)] += p_r * 0.24

    # Gallery antique pocket-watch tick every 0.48s during Act I (stops dead right before Trinity!)
    tick_t = 0.35
    tick_idx = 0
    while tick_t < s4_start - 0.40:
        nt = int(0.045 * SR)
        lt = np.arange(nt) / SR
        freq = 2150.0 if tick_idx % 2 == 0 else 1680.0
        click = np.sin(2 * np.pi * freq * lt) * np.exp(-lt * 140.0)
        body = np.sin(2 * np.pi * 420.0 * lt) * np.exp(-lt * 85.0) * 0.4
        add_stereo(click + body, tick_t, pan=-0.25 if tick_idx % 2 == 0 else 0.25, gain=0.085)
        tick_t += 0.48
        tick_idx += 1

    # Subtle forensic laser hum in Scene 01
    n_las = int(min(3.5, timeline[0]["dur_s"]) * SR)
    lt_las = np.arange(n_las) / SR
    las = np.sin(2 * np.pi * (196.0 + 18.0 * np.sin(2 * np.pi * 0.6 * lt_las)) * lt_las)
    las *= np.sin(np.pi * lt_las / (n_las / SR)) ** 1.2
    add_stereo(las, 0.2, pan=0.15, gain=0.04)

    # 2. Act II: July 16, 1945 Trinity Sub-Drop + Shockwave Rumble!
    boom_dur = 3.6
    nb = int(boom_dur * SR)
    lt_b = np.arange(nb) / SR
    # Exponential pitch sweep 98Hz -> 31Hz
    inst_f = 31.0 + 67.0 * np.exp(-lt_b * 4.5)
    phase_b = 2 * np.pi * np.cumsum(inst_f) / SR
    sub_boom = np.tanh(1.6 * np.sin(phase_b)) * np.exp(-lt_b * 1.15)
    # Filtered desert rumble noise
    rng = np.random.default_rng(1945)
    noise = rng.standard_normal(nb)
    sos_rumble = signal.butter(3, 180.0 / (SR / 2), btype="low", output="sos")
    rumble = signal.sosfilt(sos_rumble, noise) * np.exp(-lt_b * 1.4) * 1.8
    env_b = np.minimum(1.0, lt_b / 0.018)
    add_stereo((sub_boom * 0.34 + rumble * 0.22) * env_b, s4_start - 0.03, pan=0.0, gain=1.0)

    # 3. Act III & IV Chord Progression (s4_start + 0.4 -> end)
    # Chords: Bbmaj7 -> Gm9 -> Dm9 -> A7sus4 -> Dm (seamless loop back to D2!)
    chords = [
        (s4_start + 0.3, s5_start, [58.27, 116.54, 174.61, 220.00], 780.0),      # Bbmaj7 awe
        (s5_start, timeline[5]["start_s"], [73.42, 146.83, 220.00, 261.63, 329.63], 1050.0),  # Dm9 fallout
        (timeline[5]["start_s"], s7_start, [65.41, 130.81, 196.00, 246.94, 293.66], 980.0),   # Cmaj7/G pastoral flax
        (s7_start, s9_start, [55.00, 110.00, 164.81, 220.00, 246.94], 860.0),    # Am9 forensic tension
        (s9_start, s10_start, [49.00, 98.00, 146.83, 220.00, 293.66], 720.0),    # Gm9 deep ocean steel
        (s10_start, total_dur, [73.42, 110.00, 146.83, 220.00, 329.63], 950.0),  # Dm9 resolving to D2 loop!
    ]
    for c0, c1, freqs, cutoff in chords:
        dur_c = max(0.5, (c1 - c0) + 0.45)  # slight overlap crossfade
        pl, pr = warm_pad(freqs, dur_c, attack=0.45, release=0.55, bright=cutoff)
        i0 = max(0, int(c0 * SR))
        i1 = min(n_samples, i0 + len(pl))
        left[i0:i1] += pl[: i1 - i0] * 0.25
        right[i0:i1] += pr[: i1 - i0] * 0.25

    # Shimmering crystalline isotope notes in Scene 05
    sparkle_notes = [587.33, 659.25, 880.0, 1046.50, 880.0, 659.25]
    for idx_n, fn in enumerate(sparkle_notes):
        nt = s5_start + 0.45 + idx_n * 0.85
        if nt < timeline[4]["end_s"] - 0.3:
            ns_bell = int(0.9 * SR)
            lt_bell = np.arange(ns_bell) / SR
            bell = (np.sin(2 * np.pi * fn * lt_bell) + 0.3 * np.sin(2 * np.pi * fn * 2.0 * lt_bell)) * np.exp(-lt_bell * 4.5)
            bell[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
            add_stereo(bell, nt, pan=(-0.4 + 0.16 * idx_n), gain=0.045)

    # Geiger clicks + clean emerald oscilloscope ping on Scene 08!
    for gc in [0.18, 0.31, 0.39, 0.58, 0.72, 0.79, 0.95]:
        nc = int(0.012 * SR)
        lt_c = np.arange(nc) / SR
        geiger = np.sin(2 * np.pi * 3400.0 * lt_c) * np.exp(-lt_c * 350.0)
        add_stereo(geiger, s8_start + gc, pan=-0.2, gain=0.09)
    # Signature oscilloscope spike ping (E6 = 1318.5Hz)
    np_ping = int(1.1 * SR)
    lt_p = np.arange(np_ping) / SR
    ping = np.sin(2 * np.pi * 1318.5 * lt_p) * np.exp(-lt_p * 4.2)
    ping[: int(0.008 * SR)] *= np.linspace(0, 1, int(0.008 * SR))
    add_stereo(ping, s8_start + 1.05, pan=0.22, gain=0.075)

    # Deep underwater sonar ping on Scene 09 (Shipwreck)
    for sp_delay, sp_gain in [(0.35, 0.085), (1.15, 0.032)]:
        ns_son = int(1.0 * SR)
        lt_s = np.arange(ns_son) / SR
        sonar = np.sin(2 * np.pi * 587.33 * lt_s) * np.exp(-lt_s * 3.8)
        sonar[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
        add_stereo(sonar, s9_start + sp_delay, pan=-0.15 if sp_delay < 0.5 else 0.30, gain=sp_gain)

    # Subtle soft cinema air-whoosh transitions on scene cuts
    for idx_sc in range(1, len(timeline)):
        cut_s = timeline[idx_sc]["start_s"]
        if idx_sc == 3:
            continue  # Trinity already has sub-boom
        nw = int(0.34 * SR)
        lt_w = np.arange(nw) / SR
        wn = rng.standard_normal(nw)
        sos_w = signal.butter(2, [180.0 / (SR / 2), 1100.0 / (SR / 2)], btype="band", output="sos")
        whoosh = signal.sosfilt(sos_w, wn) * (np.sin(np.pi * lt_w / 0.34) ** 2.0)
        add_stereo(whoosh, cut_s - 0.17, pan=0.0, gain=0.065)

    # Sidechain ducking envelope driven by VO energy
    vo_abs = np.abs(vo_mono.astype(np.float64))
    # Smooth envelope with fast attack (25ms), smooth release (260ms)
    win = int(0.04 * SR)
    vo_env = np.convolve(vo_abs, np.ones(win) / win, mode="same")
    duck = 1.0 - 0.52 * np.clip(vo_env / 0.08, 0.0, 1.0)
    # Extra smooth ducking curve
    smooth_win = int(0.12 * SR)
    duck = np.convolve(duck, np.ones(smooth_win) / smooth_win, mode="same")

    mix_l = vo_mono * 0.92 + left * duck
    mix_r = vo_mono * 0.92 + right * duck

    # Master soft-knee limiter to -1.0 dBFS (0.891)
    peak = max(1e-6, np.max(np.abs(mix_l)), np.max(np.abs(mix_r)))
    if peak > 0.89:
        mix_l = np.tanh(mix_l * 0.95) * 0.89
        mix_r = np.tanh(mix_r * 0.95) * 0.89

    stereo = np.stack([mix_l, mix_r], axis=1)
    return np.clip(stereo * 32767.0, -32768, 32767).astype(np.int16)


def auto_crop_fullbleed(img_path: str) -> Image.Image:
    """Removes any outer cream paper frame so every illustration is full-bleed edge-to-edge."""
    im = Image.open(img_path).convert("RGB")
    arr = np.array(im)
    h, w, _ = arr.shape
    gray = arr.mean(axis=2)

    top = 0
    for r in range(int(h * 0.08)):
        if np.percentile(gray[r, int(w * 0.15) : int(w * 0.85)], 75) > 190:
            top = r + 1
        elif top > 0:
            break
    bot = h
    for r in range(h - 1, int(h * 0.92), -1):
        if np.percentile(gray[r, int(w * 0.15) : int(w * 0.85)], 75) > 190:
            bot = r
        elif bot < h:
            break
    left = 0
    for c in range(int(w * 0.08)):
        if np.percentile(gray[int(h * 0.15) : int(h * 0.85), c], 75) > 190:
            left = c + 1
        elif left > 0:
            break
    right = w
    for c in range(w - 1, int(w * 0.92), -1):
        if np.percentile(gray[int(h * 0.15) : int(h * 0.85), c], 75) > 190:
            right = c
        elif right < w:
            break

    box = (
        left + (9 if left > 0 else 2),
        top + (9 if top > 0 else 2),
        right - (9 if right < w else 2),
        bot - (9 if bot < h else 2),
    )
    cropped = im.crop(box)
    # Pre-upscale to high-res working canvas (1350x2400) with LANCZOS for crisp subpixel camera pans!
    cw, ch = cropped.size
    target_ratio = W / H
    cur_ratio = cw / ch
    if cur_ratio > target_ratio:
        # slightly wider than 9:16
        new_h = 2400
        new_w = int(round(new_h * cur_ratio))
    else:
        new_w = 1350
        new_h = int(round(new_w / cur_ratio))
    return cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)


def smoothstep(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def build_vignette_alpha() -> Image.Image:
    """Precomputes an L-mode alpha mask for subtle cinema vignette + readability gradients."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx = (xx - W * 0.5) / (W * 0.5)
    ny = (yy - H * 0.46) / (H * 0.54)
    r2 = nx * nx + ny * ny
    vig = np.clip(1.0 - 0.30 * (r2 ** 1.35), 0.52, 1.0)
    top_grad = np.clip(0.76 + 0.24 * (yy / 280.0), 0.76, 1.0)
    bot_grad = np.clip(1.0 - 0.34 * np.clip((yy - 1180.0) / 740.0, 0.0, 1.0), 0.66, 1.0)
    darkness = 1.0 - (vig * top_grad * bot_grad)
    alpha_u8 = np.clip(darkness * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(alpha_u8, mode="L")


def render_camera_frame(hi_img: Image.Image, u: float, cam: dict, shake_px=(0.0, 0.0)) -> Image.Image:
    s = smoothstep(u)
    iw, ih = hi_img.size
    zoom = cam["z0"] + (cam["z1"] - cam["z0"]) * s
    cx = (cam["x0"] + (cam["x1"] - cam["x0"]) * s) * iw + shake_px[0]
    cy = (cam["y0"] + (cam["y1"] - cam["y0"]) * s) * ih + shake_px[1]

    base_w = min(iw, ih * (W / H))
    base_h = base_w * (H / W)
    crop_w = base_w / zoom
    crop_h = base_h / zoom

    x0 = max(0.0, min(iw - crop_w, cx - crop_w * 0.5))
    y0 = max(0.0, min(ih - crop_h, cy - crop_h * 0.5))
    x1 = x0 + crop_w
    y1 = y0 + crop_h

    return hi_img.transform(
        (W, H),
        Image.Transform.EXTENT,
        (x0, y0, x1, y1),
        resample=Image.Resampling.BILINEAR,
    )


def apply_scene_vfx(d: ImageDraw.ImageDraw, vfx_name: str, local_t: float, dur_s: float, particles: np.ndarray) -> None:
    """Draws bespoke subtle cinematic visual motion directly in RGBA mode onto the RGB frame."""
    if vfx_name == "laser_scan":
        scan_y = int(H * (0.31 + 0.16 * math.sin(local_t * 1.35)))
        for dy, alpha in [(-10, 14), (-5, 28), (0, 62), (5, 28), (10, 14)]:
            d.line([(340, scan_y + dy), (980, scan_y + dy - 22)], fill=(92, 235, 142, alpha), width=3)
        for p in particles[:18]:
            px = int((p[0] * W + local_t * 18.0 * p[2]) % W)
            py = int((p[1] * H * 0.65 - local_t * 14.0 * p[3]) % (H * 0.65))
            if 320 < px < 960 and 120 < py < 1100:
                a = int(55 + 45 * math.sin(local_t * 3.0 + p[4]))
                d.ellipse((px - 2, py - 2, px + 2, py + 2), fill=(255, 218, 145, max(0, a)))

    elif vfx_name == "candle_flicker":
        pulse = 0.5 + 0.5 * math.sin(local_t * 11.0) * math.cos(local_t * 6.3)
        alpha = int(14 + 18 * pulse)
        cx, cy = 195, 1080
        for rad, mul in [(280, 0.35), (180, 0.65), (95, 1.0)]:
            d.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=(255, 168, 62, int(alpha * mul)))

    elif vfx_name == "loupe_glint":
        prog = local_t / max(0.1, dur_s)
        gx = int(260 + 460 * prog)
        gy = int(780 + 120 * prog)
        d.ellipse((gx - 90, gy - 90, gx + 90, gy + 90), fill=(255, 240, 200, 22))

    elif vfx_name == "trinity_flash":
        if local_t < 0.42:
            flash_a = int(235 * math.exp(-local_t * 9.5))
            d.rectangle((0, 0, W, H), fill=(255, 242, 205, max(0, min(255, flash_a))))
        for p in particles[:24]:
            px = int((p[0] * W + math.sin(local_t * 2.5 + p[4]) * 26) % W)
            py = int(H * 0.78 - ((local_t * 110 * (0.6 + p[2]) + p[1] * 700) % 900))
            d.ellipse((px - 2, py - 2, px + 2, py + 2), fill=(255, 196, 92, 95))

    elif vfx_name == "isotope_drift":
        for p in particles[:36]:
            px = int((p[0] * W + local_t * 36.0 * (0.5 + p[2])) % W)
            py = int((p[1] * H * 0.72 + math.sin(local_t * 1.8 + p[4]) * 28.0) % (H * 0.75))
            r = 2 if p[2] < 0.5 else 3
            glow_a = int(90 + 75 * math.sin(local_t * 4.0 + p[4]))
            d.ellipse((px - r - 3, py - r - 3, px + r + 3, py + r + 3), fill=(92, 235, 142, max(0, glow_a // 3)))
            d.ellipse((px - r, py - r, px + r, py + r), fill=(175, 255, 205, max(0, glow_a)))

    elif vfx_name == "flax_pollen":
        for p in particles[:26]:
            px = int((p[0] * W + math.sin(local_t * 1.6 + p[4]) * 30.0) % W)
            py = int((p[1] * H * 0.65 + local_t * 45.0 * (0.5 + p[3])) % (H * 0.72))
            a = int(85 + 60 * math.sin(local_t * 3.2 + p[4]))
            d.ellipse((px - 3, py - 3, px + 3, py + 3), fill=(115, 248, 162, max(0, a)))

    elif vfx_name == "forensic_reticle":
        rx, ry = 486, 1148
        rad = int(78 - 14 * smoothstep(min(1.0, local_t / 0.8)))
        col = (92, 235, 142, 185)
        d.ellipse((rx - rad, ry - rad, rx + rad, ry + rad), outline=col, width=2)
        for dx1, dy1, dx2, dy2 in [
            (-rad - 16, 0, -rad + 8, 0),
            (rad - 8, 0, rad + 16, 0),
            (0, -rad - 16, 0, -rad + 8),
            (0, rad - 8, 0, rad + 16),
        ]:
            d.line([(rx + dx1, ry + dy1), (rx + dx2, ry + dy2)], fill=col, width=2)

    elif vfx_name == "oscilloscope_pulse":
        if local_t > 0.85:
            pulse = math.exp(-((local_t - 1.15) ** 2) / 0.18) + 0.35 * (0.5 + 0.5 * math.sin(local_t * 7.0))
            ga = int(min(70, 48 * pulse))
            gx, gy = 770, 960
            d.ellipse((gx - 190, gy - 190, gx + 190, gy + 190), fill=(80, 245, 140, ga))

    elif vfx_name == "underwater_sparks":
        for idx_p, p in enumerate(particles[:28]):
            if idx_p < 14:
                ang = p[4]
                spd = 80.0 + 130.0 * p[2]
                age = (local_t * 1.6 + p[0]) % 1.0
                sx = int(795 + math.cos(ang) * spd * age)
                sy = int(990 + math.sin(ang) * spd * age + 90.0 * age * age)
                sa = int(210 * (1.0 - age))
                if 0 <= sx < W and 0 <= sy < H:
                    d.ellipse((sx - 2, sy - 2, sx + 2, sy + 2), fill=(255, 205, 90, sa))
            else:
                bx = int(260 + p[0] * 420 + math.sin(local_t * 2.2 + p[4]) * 14)
                by = int(1250 - ((local_t * 75.0 * (0.6 + p[3]) + p[1] * 800) % 950))
                d.ellipse((bx - 4, by - 4, bx + 4, by + 4), outline=(170, 225, 245, 75), width=1)

    elif vfx_name == "atomic_signature":
        pulse = 0.5 + 0.5 * math.sin(local_t * 4.5)
        ax, ay = 655, 1285
        d.ellipse((ax - 155, ay - 155, ax + 155, ay + 155), fill=(85, 240, 145, int(20 + 22 * pulse)))


def draw_hud_and_captions(
    d: ImageDraw.ImageDraw,
    sc: dict,
    t_abs: float,
    total_dur: float,
    font_caption: ImageFont.FreeTypeFont,
    font_tag_top: ImageFont.FreeTypeFont,
    font_tag_main: ImageFont.FreeTypeFont,
) -> None:
    """Renders minimalist archival chapter stamp, top progress bar, and clean editorial captions in-place."""
    # 1. Sleek 5px progress bar at very top edge
    prog_w = int(W * (t_abs / max(0.01, total_dur)))
    d.rectangle((0, 0, W, 5), fill=(255, 255, 255, 38))
    d.rectangle((0, 0, prog_w, 5), fill=(*sc["tag"][2], 235))

    # 2. Top-left Archival Chapter Stamp (inside safe zone: x=62, y=142)
    local_t = t_abs - sc["start_s"]
    tag_enter = smoothstep(min(1.0, local_t / 0.24))
    tag_exit = smoothstep(min(1.0, (sc["end_s"] - t_abs) / 0.18))
    tag_alpha_mul = tag_enter * tag_exit

    if tag_alpha_mul > 0.02:
        kicker, title, accent = sc["tag"]
        slide_x = int(-24 * (1.0 - tag_enter))
        bx = 62 + slide_x
        by = 142
        bb1 = d.textbbox((0, 0), kicker, font=font_tag_top)
        bb2 = d.textbbox((0, 0), title, font=font_tag_main)
        box_w = max(bb1[2] - bb1[0], bb2[2] - bb2[0]) + 48
        box_h = 88

        d.rounded_rectangle(
            (bx, by, bx + box_w, by + box_h),
            radius=14,
            fill=(10, 16, 26, int(204 * tag_alpha_mul)),
            outline=(255, 255, 255, int(40 * tag_alpha_mul)),
            width=1,
        )
        d.rounded_rectangle(
            (bx + 12, by + 14, bx + 18, by + box_h - 14),
            radius=3,
            fill=(*accent, int(245 * tag_alpha_mul)),
        )
        d.text(
            (bx + 30, by + 13),
            kicker,
            font=font_tag_top,
            fill=(*MUTED_SLATE, int(230 * tag_alpha_mul)),
        )
        d.text(
            (bx + 30, by + 39),
            title,
            font=font_tag_main,
            fill=(*IVORY, int(250 * tag_alpha_mul)),
        )

    # 3. Editorial Phrase Card (Safe Zone: centered at x=505, y=1425)
    active_phrase = None
    for p0, p1, txt, hl in sc["abs_phrases"]:
        if p0 - 0.03 <= t_abs <= p1 + 0.05:
            active_phrase = (p0, p1, txt, hl)
            if t_abs <= p1:
                break

    if active_phrase is not None:
        p0, p1, txt, hl_map = active_phrase
        p_in = smoothstep(min(1.0, max(0.0, (t_abs - p0 + 0.03) / 0.11)))
        p_out = smoothstep(min(1.0, max(0.0, (p1 + 0.05 - t_abs) / 0.09)))
        alpha_f = p_in * p_out
        y_offset = int(12 * (1.0 - p_in))

        words = txt.split()
        if len(txt) <= 21 or len(words) <= 3:
            lines = [words]
        else:
            best_split = len(words) // 2
            best_diff = 999
            for sp in range(1, len(words)):
                diff = abs(len(" ".join(words[:sp])) - len(" ".join(words[sp:])))
                if diff < best_diff:
                    best_diff = diff
                    best_split = sp
            lines = [words[:best_split], words[best_split:]]

        space_w = d.textlength(" ", font=font_caption)
        line_widths = [
            sum(d.textlength(w, font=font_caption) for w in lw_words) + space_w * max(0, len(lw_words) - 1)
            for lw_words in lines
        ]

        max_lw = max(line_widths)
        line_h = 66
        total_th = len(lines) * line_h
        center_x = 505
        center_y = 1425 + y_offset

        pad_x, pad_y = 34, 22
        pill_x0 = int(center_x - max_lw * 0.5 - pad_x)
        pill_y0 = int(center_y - total_th * 0.5 - pad_y)
        pill_x1 = int(center_x + max_lw * 0.5 + pad_x)
        pill_y1 = int(center_y + total_th * 0.5 + pad_y)

        d.rounded_rectangle(
            (pill_x0, pill_y0, pill_x1, pill_y1),
            radius=22,
            fill=(8, 13, 22, int(212 * alpha_f)),
            outline=(255, 255, 255, int(42 * alpha_f)),
            width=2,
        )

        for li, lw_words in enumerate(lines):
            cur_x = center_x - line_widths[li] * 0.5
            cur_y = center_y - total_th * 0.5 + li * line_h - 4
            for w_str in lw_words:
                col = hl_map.get(w_str, IVORY)
                d.text(
                    (cur_x + 2, cur_y + 3),
                    w_str,
                    font=font_caption,
                    fill=(0, 0, 0, int(215 * alpha_f)),
                )
                d.text(
                    (cur_x, cur_y),
                    w_str,
                    font=font_caption,
                    fill=(*col, int(255 * alpha_f)),
                )
                cur_x += d.textlength(w_str, font=font_caption) + space_w


def main():
    print("1/4 Preparing voiceover timing & waveform phrase alignment...", flush=True)
    vo_mono, timeline, total_frames = prepare_narration_and_timeline()
    total_dur = total_frames / FPS
    print(f"    Total duration: {total_dur:.2f}s ({total_frames} frames @ {FPS}fps)", flush=True)
    for sc in timeline:
        print(f"    Scene {sc['id']:02d}: {sc['start_s']:5.2f}s -> {sc['end_s']:5.2f}s ({sc['dur_s']:.2f}s) | {sc['tag'][1]}", flush=True)

    print("2/4 Synthesizing original procedural score & foley mix...", flush=True)
    master_stereo = build_cinematic_soundtrack(vo_mono, timeline)
    master_wav = os.path.join(WORK_DIR, "master_mix.wav")
    wavfile.write(master_wav, SR, master_stereo)

    print("3/4 Loading & border-trimming 10 high-resolution graphic-novel scenes...", flush=True)
    hi_scenes = {}
    for sc in timeline:
        p = os.path.join(SCENE_DIR, sc["img"])
        hi_scenes[sc["id"]] = auto_crop_fullbleed(p)

    font_caption = ImageFont.truetype(os.path.join(FONT_DIR, "montserrat-latin-800-normal.woff"), 50)
    font_tag_top = ImageFont.truetype(os.path.join(FONT_DIR, "space-grotesk-latin-700-normal.woff"), 20)
    font_tag_main = ImageFont.truetype(os.path.join(FONT_DIR, "bebas-neue-latin-400-normal.woff"), 35)

    vig_alpha = build_vignette_alpha()
    black_img = Image.new("RGB", (W, H), (0, 0, 0))
    f0_loop = render_camera_frame(hi_scenes[1], 0.0, timeline[0]["cam"])

    rng = np.random.default_rng(42)
    particles = rng.random((40, 5))
    particles[:, 4] *= 2.0 * math.pi

    print("4/4 Rendering 1080x1920 @ 30fps cinema frames directly to H.264 + AAC MP4...", flush=True)
    os.makedirs(os.path.dirname(OUT_MP4), exist_ok=True)
    ffmpeg_log_path = os.path.join(WORK_DIR, "ffmpeg_encode.log")
    ffmpeg_cmd = [
        FFMPEG,
        "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-s", f"{W}x{H}",
        "-pix_fmt", "rgb24",
        "-r", str(FPS),
        "-i", "-",
        "-i", master_wav,
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "21",
        "-pix_fmt", "yuv420p",
        "-profile:v", "high",
        "-c:a", "aac",
        "-b:a", "192k",
        "-movflags", "+faststart",
        "-shortest",
        OUT_MP4,
    ]
    with open(ffmpeg_log_path, "w") as ff_err:
        proc = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE, stderr=ff_err)

        sc_idx = 0
        for f_idx in range(total_frames):
            t_abs = f_idx / FPS
            while sc_idx < len(timeline) - 1 and t_abs >= timeline[sc_idx]["end_s"]:
                sc_idx += 1
            sc = timeline[sc_idx]
            local_t = max(0.0, t_abs - sc["start_s"])
            u = local_t / max(0.01, sc["dur_s"])

            shake = (0.0, 0.0)
            if sc["id"] == 4 and local_t < 0.75:
                amp = 22.0 * math.exp(-local_t * 5.2)
                shake = (amp * math.sin(local_t * 58.0), amp * math.cos(local_t * 47.0))

            frame = render_camera_frame(hi_scenes[sc["id"]], u, sc["cam"], shake_px=shake)

            if sc["id"] == 10 and (total_frames - f_idx) <= 6:
                blend_a = (6 - (total_frames - f_idx) + 1) / 8.0 * 0.45
                frame = Image.blend(frame, f0_loop, blend_a)

            # Fast C-level vignette mask composite
            frame.paste(black_img, (0, 0), vig_alpha)

            # Draw bespoke scene VFX + crisp HUD + captions directly in RGBA mode
            d = ImageDraw.Draw(frame, "RGBA")
            apply_scene_vfx(d, sc["vfx"], local_t, sc["dur_s"], particles)
            draw_hud_and_captions(
                d, sc, t_abs, total_dur, font_caption, font_tag_top, font_tag_main
            )

            proc.stdin.write(frame.tobytes())

            if (f_idx + 1) % 300 == 0 or f_idx == total_frames - 1:
                print(f"    Rendered {f_idx + 1}/{total_frames} frames ({100.0 * (f_idx + 1) / total_frames:.0f}%)", flush=True)

        proc.stdin.close()
        ret = proc.wait()

    if ret != 0:
        with open(ffmpeg_log_path) as f_log:
            err_tail = f_log.read()[-1500:]
        raise RuntimeError(f"FFmpeg failed with code {ret}:\n{err_tail}")

    size_mb = os.path.getsize(OUT_MP4) / (1024 * 1024)
    print(f"SUCCESS! Wrote {OUT_MP4} ({size_mb:.2f} MB)", flush=True)


if __name__ == "__main__":
    main()
