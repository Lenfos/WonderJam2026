"""Turn a downloaded track into a seamless backing loop of exactly <beats> beats.

Usage (from RythmJam/):  python tools/make_loop.py <in.wav> <out.wav> <bpm> <beats>
Keeps the first <beats> beats (the track must start on a downbeat) and mixes everything after
them (reverb/delay tail) back over the start, as heard when the loop wraps. 16-bit WAV, stdlib only.
Then: loop mode Forward in the output's .import, NewsData.backing_beats = <beats>.
"""
import array
import sys
import wave
from fractions import Fraction


def main() -> None:
    src, dst, bpm, beats = sys.argv[1], sys.argv[2], Fraction(sys.argv[3]), int(sys.argv[4])
    with wave.open(src, "rb") as w:
        rate, channels = w.getframerate(), w.getnchannels()
        assert w.getsampwidth() == 2, "16-bit WAV only"
        data = array.array("h", w.readframes(w.getnframes()))
    del data[len(data) - len(data) % channels:]  # drop a truncated last frame
    loop = round(beats * 60 * rate / bpm) * channels  # samples, all channels interleaved
    assert len(data) >= loop, f"track is {len(data) // channels} frames, loop needs {loop // channels}"

    mixed = list(data[:loop])
    for i in range(loop, len(data)):
        mixed[i % loop] += data[i]
    gain = min(1.0, 32767 / max(abs(s) for s in mixed))  # scale down rather than clip
    out = array.array("h", (round(s * gain) for s in mixed))
    with wave.open(dst, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())

    # Self-check: re-read, exact loop length, nothing dropped by the fold (sum of samples kept).
    with wave.open(dst, "rb") as w:
        frames = w.getnframes()
        reread = array.array("h", w.readframes(frames))
    assert frames * channels == loop, (frames, loop // channels)
    assert abs(sum(reread) - sum(data) * gain) <= len(reread), "tail fold lost samples"
    print(f"{dst}: {frames} frames = {frames / rate:.6f} s, {beats} beats @ {float(bpm)} BPM,"
          f" tail folded {(len(data) - loop) // channels / rate:.3f} s, gain {gain:.3f}")


if __name__ == "__main__":
    main()
