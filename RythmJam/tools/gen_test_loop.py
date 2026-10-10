"""Generate a placeholder click loop: 44100 Hz, 16-bit mono, exactly N beats.

Usage (from RythmJam/):  python tools/gen_test_loop.py [bpm] [beats]
Writes audio/placeholder/test_loop_<bpm>.wav. Stdlib only.
"""
import math
import struct
import sys
import wave
from fractions import Fraction
from pathlib import Path

SAMPLE_RATE = 44100
BEATS_PER_BAR = 4
THUMP_SEC = 0.08      # every beat: low sine with a pitch drop
THUMP_HZ = (160.0, 60.0)
ACCENT_SEC = 0.05     # bar starts: extra high blip on top
ACCENT_HZ = 1200.0
AMPLITUDE = 0.8


def beat_sample(beat: int, bpm: Fraction) -> int:
    """First sample of `beat`, computed from the exact rational time: no accumulated drift."""
    return round(beat * 60 * SAMPLE_RATE / bpm)


def thump(t: float) -> float:
    if t >= THUMP_SEC:
        return 0.0
    k = t / THUMP_SEC
    lo, hi = THUMP_HZ[1], THUMP_HZ[0]
    # Phase of a frequency gliding exponentially from hi to lo over THUMP_SEC.
    r = lo / hi
    phase = 2 * math.pi * hi * THUMP_SEC * (r ** k - 1) / math.log(r)
    return math.sin(phase) * (1 - k) ** 2


def accent(t: float) -> float:
    if t >= ACCENT_SEC:
        return 0.0
    return 0.6 * math.sin(2 * math.pi * ACCENT_HZ * t) * (1 - t / ACCENT_SEC) ** 3


def main() -> None:
    bpm = Fraction(sys.argv[1]) if len(sys.argv) > 1 else Fraction(120)
    beats = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    exact_total = beats * 60 * SAMPLE_RATE / bpm
    total = beat_sample(beats, bpm)
    if exact_total != total:
        print(f"warning: loop is {float(exact_total)} samples, rounded to {total}"
              f" ({abs(float(exact_total) - total) / SAMPLE_RATE * 1000:.4f} ms off)")

    samples = [0.0] * total
    for b in range(beats):
        start = beat_sample(b, bpm)
        end = min(total, start + round(THUMP_SEC * SAMPLE_RATE))
        for i in range(start, end):
            t = (i - start) / SAMPLE_RATE
            samples[i] += thump(t) + (accent(t) if b % BEATS_PER_BAR == 0 else 0.0)

    peak = max(abs(s) for s in samples) or 1.0
    frames = b"".join(struct.pack("<h", round(s / peak * AMPLITUDE * 32767)) for s in samples)

    name = f"test_loop_{bpm.numerator if bpm.denominator == 1 else float(bpm)}.wav"
    out = Path(__file__).resolve().parent.parent / "audio" / "placeholder" / name
    out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(frames)

    # Self-check: re-read the file and verify length and beat-aligned onsets.
    with wave.open(str(out), "rb") as w:
        assert w.getnframes() == total, (w.getnframes(), total)
        assert w.getframerate() == SAMPLE_RATE and w.getsampwidth() == 2 and w.getnchannels() == 1
    assert samples[-1] == 0.0, "click tail reaches the loop end: wrap would not be seamless"
    print(f"{out.name}: {total} samples = {total / SAMPLE_RATE:.6f} s, {beats} beats @ {float(bpm)} BPM")


if __name__ == "__main__":
    main()
