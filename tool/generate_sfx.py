#!/usr/bin/env python3
"""Synthesises Harita's sound effects (no samples, no licences needed).

The attack sound (assets/audio/attack.mp3) and the background music are kept
as they are; this script writes:

  ability.mp3   — card used: rising whoosh into a heavy explosion
  nuke.mp3      — intro: falling whistle, then a huge atomic blast + rumble
  diamond.mp3   — diamond mine captured: bright crystal sparkle
  turn_end.mp3  — end of turn: two low war-drum hits + a short horn
  tap.mp3       — UI tap: short soft wooden click
  victory.mp3   — victory: brass fanfare (C–E–G–C) over timpani

Needs numpy and ffmpeg (libmp3lame). Usage: python3 tool/generate_sfx.py
"""

import os
import subprocess

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 44100
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be a scalar or a per-sample array."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env(t, attack, decay):
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-np.maximum(t - attack, 0) / decay)


def explosion(seconds, size=1.0):
    t = t_axis(seconds)
    noise = rng.standard_normal(len(t))
    # Bright crack that darkens into a long rumble.
    cutoff = 200 + 5000 * np.exp(-t / (0.06 * size))
    body = lowpass(noise, cutoff) * env(t, 0.004, 0.35 * size)
    rumble = lowpass(rng.standard_normal(len(t)), 90) * env(t, 0.02, 0.9 * size) * 4
    thump = np.sin(2 * np.pi * (55 * np.exp(-t / 0.25) + 30) * t) * env(t, 0.003, 0.18 * size)
    return body * 1.6 + rumble + thump * 0.9


def normalise(x, peak=0.89, rms_db=-15.0):
    """Matches the loudness of the kept attack sound (about -15 dBFS RMS)
    without letting peaks clip."""
    x = x - np.mean(x)
    fade = min(len(x), int(0.02 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    gain = min(10 ** (rms_db / 20) / rms, peak / (np.max(np.abs(x)) + 1e-9))
    return x * gain


def soft_clip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def write(name, x, rms_db=-15.0):
    x = normalise(x, rms_db=rms_db)
    pcm = (x * 32767).astype("<i2").tobytes()
    out = os.path.join(ROOT, "assets/audio", name)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1",
         "-i", "-", "-codec:a", "libmp3lame", "-b:a", "128k", out],
        input=pcm, check=True,
    )
    print(f"{name}: {len(x) / SR:.2f}s")


def brass(freq, seconds, vibrato=5.0):
    t = t_axis(seconds)
    f = freq * (1 + 0.004 * np.sin(2 * np.pi * vibrato * t) * np.minimum(t / 0.2, 1))
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = sum(np.sin(k * phase) / k ** 0.9 for k in range(1, 12))
    a = env(t, 0.04, seconds * 0.9)
    bright = lowpass(tone, 900 + 2500 * np.minimum(t / 0.08, 1) * np.exp(-t / 0.6))
    return bright * a


def drum(seconds, pitch=70):
    t = t_axis(seconds)
    f = pitch * (1 + 0.6 * np.exp(-t / 0.03))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.002, 0.25)
    skin = lowpass(rng.standard_normal(len(t)), 1800) * env(t, 0.001, 0.04)
    return tone + skin * 0.5


def place(track, clip, at):
    i = int(at * SR)
    end = min(len(track), i + len(clip))
    track[i:end] += clip[: end - i]


def ability():
    t = t_axis(1.3)
    whoosh = lowpass(rng.standard_normal(len(t)), 300 + 3000 * np.minimum(t / 0.25, 1))
    whoosh *= np.where(t < 0.25, t / 0.25, np.exp(-(t - 0.25) / 0.05)) * 0.5
    x = whoosh
    place(x, explosion(1.05, 0.8), 0.22)
    return soft_clip(x, 1.8)


def nuke():
    total = 4.2
    x = np.zeros(int(SR * total))
    # Falling whistle (pitch drops while it gets louder).
    t = t_axis(1.0)
    f = 1500 - 900 * t
    whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.15 + 0.35 * t)
    place(x, whistle, 0.0)
    boom = explosion(3.2, 2.2)
    # A second, deeper shock wave.
    t2 = t_axis(3.2)
    shock = np.sin(2 * np.pi * (38 * np.exp(-t2 / 0.6) + 22) * t2) * env(t2, 0.01, 0.9)
    place(x, boom + shock * 1.2, 1.0)
    return soft_clip(x, 2.2)


def diamond():
    x = np.zeros(int(SR * 1.1))
    notes = [1318.5, 1760.0, 2093.0, 2637.0, 3136.0]
    for i, f in enumerate(notes):
        t = t_axis(0.7)
        bell = (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t)
                + 0.2 * np.sin(2 * np.pi * f * 5.4 * t))
        place(x, bell * env(t, 0.002, 0.18), i * 0.07)
    shimmer = highpass(rng.standard_normal(len(x)), 6000) * env(t_axis(1.1), 0.01, 0.25) * 0.15
    return x + shimmer


def turn_end():
    x = np.zeros(int(SR * 1.0))
    place(x, drum(0.5, 75), 0.0)
    place(x, drum(0.5, 62), 0.16)
    place(x, brass(196.0, 0.55) * 0.6, 0.32)
    return x


def tap():
    t = t_axis(0.09)
    click = np.sin(2 * np.pi * 1100 * t) * env(t, 0.0008, 0.012)
    knock = np.sin(2 * np.pi * 320 * t) * env(t, 0.001, 0.025)
    return click * 0.6 + knock


def victory():
    x = np.zeros(int(SR * 3.4))
    c4, e4, g4, c5 = 261.6, 329.6, 392.0, 523.3
    for at, f, d in [(0.0, c4, 0.22), (0.24, e4, 0.22), (0.48, g4, 0.22),
                     (0.72, c5, 1.0), (1.85, g4, 0.25), (2.12, c5, 1.2)]:
        place(x, brass(f, d + 0.1), at)
        place(x, brass(f / 2, d + 0.1) * 0.5, at)
    for at in (0.0, 0.72, 1.85, 2.12):
        place(x, drum(0.7, 55) * 1.2, at)
    return soft_clip(x * 0.8, 1.3)


if __name__ == "__main__":
    write("ability.mp3", ability())
    write("nuke.mp3", nuke(), rms_db=-11.0)  # the big intro blast
    write("diamond.mp3", diamond())
    write("turn_end.mp3", turn_end())
    write("tap.mp3", tap())
    write("victory.mp3", victory())
