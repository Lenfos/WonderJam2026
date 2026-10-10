"""Generate placeholder instrument one-shots: 44100 Hz, 16-bit mono, zero leading silence.

Usage (from RythmJam/):  python tools/gen_instruments.py
Writes audio/placeholder/inst_{kick,snare,brass,bells}.wav. Stdlib only.
Melodic samples are tuned exactly to C (MusicTypes.REFERENCE_NOTE): pitch shifting is relative to C.
"""
import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
PEAK_DBFS = -3.0
FADE_SEC = 0.01       # linear fade-out at the end, avoids a click when the sample stops
ONSET_MIN = 0.2       # self-check: sample 0 must already be at least this loud (full scale = 1)

C4_HZ = 261.63
C5_HZ = 523.25

rng = random.Random(0)


def kick(t: float) -> float:
    # cos of a frequency gliding exponentially 150 -> 50 Hz: full amplitude on sample 0.
    hi, lo, glide = 150.0, 50.0, 0.06
    k = min(t, glide) / glide
    r = lo / hi
    phase = 2 * math.pi * hi * glide * (r ** k - 1) / math.log(r) + 2 * math.pi * lo * max(0.0, t - glide)
    return math.cos(phase) * math.exp(-t / 0.07)


def snare(t: float) -> float:
    tone = math.cos(2 * math.pi * 200.0 * t) * math.exp(-t / 0.03)
    noise = rng.uniform(-1, 1) * math.exp(-t / 0.04)
    return 0.4 * tone + 0.7 * noise


def brass(t: float) -> float:
    # Band-limited sawtooth (8 harmonics), cos phase so sample 0 is non-zero.
    saw = sum(math.cos(2 * math.pi * C4_HZ * h * t) / h for h in range(1, 9))
    attack = min(1.0, 0.5 + t / 0.01)            # 10 ms rise from half level: punchy, no silence
    body = 0.6 + 0.4 * math.exp(-t / 0.05)        # initial bite settling to a sustain
    return saw * attack * body


def bells(t: float) -> float:
    # Inharmonic partials, higher ones ring shorter.
    partials = ((1.0, 1.0, 0.35), (2.76, 0.5, 0.15), (5.40, 0.25, 0.06))
    return sum(a * math.cos(2 * math.pi * C5_HZ * m * t) * math.exp(-t / d) for m, a, d in partials)


INSTRUMENTS = {
    "inst_kick": (kick, 0.25),
    "inst_snare": (snare, 0.15),
    "inst_brass": (brass, 0.35),
    "inst_bells": (bells, 0.80),
}


def render(fn, length_sec: float) -> list[float]:
    n = round(length_sec * SAMPLE_RATE)
    fade = round(FADE_SEC * SAMPLE_RATE)
    samples = [fn(i / SAMPLE_RATE) for i in range(n)]
    for i in range(fade):
        samples[n - 1 - i] *= i / fade         # last sample lands exactly on 0
    peak = max(abs(s) for s in samples)
    target = 10 ** (PEAK_DBFS / 20)
    return [s / peak * target for s in samples]


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "audio" / "placeholder"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, (fn, length_sec) in INSTRUMENTS.items():
        samples = render(fn, length_sec)
        out = out_dir / f"{name}.wav"
        with wave.open(str(out), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SAMPLE_RATE)
            w.writeframes(b"".join(struct.pack("<h", round(s * 32767)) for s in samples))

        # Self-check: re-read, loud first sample, silent last sample, peak at PEAK_DBFS without clipping.
        with wave.open(str(out), "rb") as w:
            data = struct.unpack(f"<{w.getnframes()}h", w.readframes(w.getnframes()))
        first, last = data[0] / 32767, data[-1]
        peak_db = 20 * math.log10(max(abs(s) for s in data) / 32767)
        assert abs(first) >= ONSET_MIN, f"{name} starts at {first:.3f}: leading silence"
        assert last == 0, f"{name} ends at {last}: missing fade-out"
        assert abs(peak_db - PEAK_DBFS) < 0.1, f"{name} peak {peak_db:.2f} dBFS"
        print(f"{out.name}: {len(data) / SAMPLE_RATE * 1000:.0f} ms, first {first:+.3f}, peak {peak_db:.2f} dBFS")


if __name__ == "__main__":
    main()
