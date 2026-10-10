"""Generate a short, sharp metronome click: 44100 Hz, 16-bit mono, zero leading silence.

Usage (from RythmJam/):  python tools/gen_click.py
Writes audio/placeholder/click.wav. Stdlib only.
Leading silence would add fake latency to every click, so the attack starts on sample 0.
"""
import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
LENGTH_SEC = 0.03
DECAY_SEC = 0.004     # exponential decay time constant
TONE_HZ = 2000.0      # clearly above the test loop's 1200 Hz bar blip
NOISE_MIX = 0.3       # a bit of noise makes the attack sharper
AMPLITUDE = 0.9
ONSET_MIN = 0.3       # self-check: sample 0 must already be at least this loud (full scale = 1)


def main() -> None:
    rng = random.Random(0)
    samples = []
    for i in range(round(LENGTH_SEC * SAMPLE_RATE)):
        t = i / SAMPLE_RATE
        # cos, not sin: full amplitude on sample 0, no ramp-up.
        tone = math.cos(2 * math.pi * TONE_HZ * t)
        samples.append(((1 - NOISE_MIX) * tone + NOISE_MIX * rng.uniform(-1, 1)) * math.exp(-t / DECAY_SEC))

    peak = max(abs(s) for s in samples)
    frames = b"".join(struct.pack("<h", round(s / peak * AMPLITUDE * 32767)) for s in samples)

    out = Path(__file__).resolve().parent.parent / "audio" / "placeholder" / "click.wav"
    out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(frames)

    # Self-check: re-read the file, the very first sample must be loud (zero leading silence).
    with wave.open(str(out), "rb") as w:
        first = struct.unpack("<h", w.readframes(1))[0] / 32767
    assert abs(first) >= ONSET_MIN, f"click starts at {first:.3f}: leading silence"
    print(f"{out.name}: {len(samples)} samples = {len(samples) / SAMPLE_RATE * 1000:.1f} ms, first sample {first:+.3f}")


if __name__ == "__main__":
    main()
