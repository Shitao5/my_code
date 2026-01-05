import argparse
import time
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Tuple

from funasr import AutoModel
import funasr.models.fun_asr_nano.model  # Ensure FunASRNano is registered.
from tqdm import tqdm


TimestampPair = Tuple[Optional[float], Optional[float]]
Segment = Tuple[Optional[float], Optional[float], str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe audio files with Fun-ASR-Nano and timestamps."
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Audio file paths to transcribe (e.g. /path/a.wav /path/b.mp3).",
    )
    parser.add_argument(
        "--output-dir",
        default="",
        help="Optional output directory for .md files. Defaults to each input's directory.",
    )
    parser.add_argument(
        "--device",
        default="cpu",
        help="Device to run on (default: cpu).",
    )
    parser.add_argument(
        "--segment-punct",
        default=".!?;,",
        help="Punctuation characters to segment text when only token timestamps exist.",
    )
    return parser.parse_args()


def _safe_pair(item: object) -> Optional[TimestampPair]:
    if isinstance(item, (list, tuple)) and len(item) >= 2:
        return _to_float(item[0]), _to_float(item[1])
    if isinstance(item, dict):
        if "start" in item and "end" in item:
            return _to_float(item.get("start")), _to_float(item.get("end"))
        if "timestamp" in item:
            ts = item.get("timestamp")
            if isinstance(ts, (list, tuple)) and len(ts) >= 2:
                return _to_float(ts[0]), _to_float(ts[1])
    return None


def _to_float(value: object) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _align_timestamps(text: str, timestamps: Sequence[object]) -> Optional[List[Optional[TimestampPair]]]:
    if not timestamps:
        return None
    pairs = []
    for item in timestamps:
        pair = _safe_pair(item)
        if pair is None:
            return None
        pairs.append(pair)
    if len(pairs) == len(text):
        return pairs
    non_space_indices = [i for i, ch in enumerate(text) if not ch.isspace()]
    if len(pairs) == len(non_space_indices):
        aligned: List[Optional[TimestampPair]] = [None] * len(text)
        for idx, pair in zip(non_space_indices, pairs):
            aligned[idx] = pair
        return aligned
    return None


def _segments_from_sentence_info(sentence_info: Iterable[object]) -> List[Segment]:
    segments: List[Segment] = []
    for item in sentence_info:
        if not isinstance(item, dict):
            continue
        text = str(item.get("text", "")).strip()
        if not text:
            continue
        start = _to_float(item.get("start"))
        end = _to_float(item.get("end"))
        if start is None or end is None:
            pair = _safe_pair(item)
            if pair:
                start, end = pair
        segments.append((start, end, text))
    return segments


def _segments_from_text_timestamps(
    text: str, timestamps: Sequence[object], segment_punct: str
) -> List[Segment]:
    aligned = _align_timestamps(text, timestamps)
    if not aligned:
        return []
    segments: List[Segment] = []
    seg_start = 0
    for idx, ch in enumerate(text):
        if ch in segment_punct:
            seg_text = text[seg_start : idx + 1].strip()
            if seg_text:
                seg_pairs = [p for p in aligned[seg_start : idx + 1] if p]
                start = seg_pairs[0][0] if seg_pairs else None
                end = seg_pairs[-1][1] if seg_pairs else None
                segments.append((start, end, seg_text))
            seg_start = idx + 1
    if seg_start < len(text):
        seg_text = text[seg_start:].strip()
        if seg_text:
            seg_pairs = [p for p in aligned[seg_start:] if p]
            start = seg_pairs[0][0] if seg_pairs else None
            end = seg_pairs[-1][1] if seg_pairs else None
            segments.append((start, end, seg_text))
    return segments


def _extract_segments(result: dict, segment_punct: str) -> List[Segment]:
    sentence_info = result.get("sentence_info")
    if isinstance(sentence_info, list) and sentence_info:
        segments = _segments_from_sentence_info(sentence_info)
        if segments:
            return segments
    timestamps = result.get("timestamp") or result.get("timestamps")
    text = str(result.get("text", "")).strip()
    if isinstance(timestamps, list) and text:
        segments = _segments_from_text_timestamps(text, timestamps, segment_punct)
        if segments:
            return segments
        pair = _safe_pair(timestamps[0]) if timestamps else None
        if pair:
            start = pair[0]
            end = _safe_pair(timestamps[-1])[1] if timestamps else pair[1]
            return [(start, end, text)]
    if text:
        return [(None, None, text)]
    return []


def _format_ms(value: Optional[float]) -> str:
    if value is None:
        return "--:--:--.---"
    total_ms = max(0, int(round(value)))
    hours, rem = divmod(total_ms, 3600_000)
    minutes, rem = divmod(rem, 60_000)
    seconds, ms = divmod(rem, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{ms:03d}"


def _render_markdown(segments: List[Segment]) -> str:
    lines = []
    for start, end, text in segments:
        start_str = _format_ms(start)
        end_str = _format_ms(end)
        lines.append(f"[{start_str} - {end_str}] {text}")
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else None

    model = AutoModel(
        model="FunAudioLLM/Fun-ASR-Nano-2512",
        vad_model="fsmn-vad",
        vad_kwargs={"max_single_segment_time": 30000},
        device=args.device,
        disable_update=True,
    )

    start_time = time.monotonic()
    for input_path in tqdm(args.inputs, desc="Transcribing", unit="file"):
        src = Path(input_path).expanduser().resolve()
        if not src.exists():
            tqdm.write(f"Skip missing file: {src}")
            elapsed = time.monotonic() - start_time
            tqdm.write(f"Elapsed: {elapsed:.1f}s")
            continue
        target_dir = output_dir if output_dir else src.parent
        out_path = target_dir / f"{src.stem}.md"

        res = model.generate(input=[str(src)], cache={}, batch_size_s=0)
        segments = _extract_segments(res[0], args.segment_punct)
        out_path.write_text(_render_markdown(segments), encoding="utf-8")
        tqdm.write(f"Wrote: {out_path}")
        elapsed = time.monotonic() - start_time
        tqdm.write(f"Elapsed: {elapsed:.1f}s")


if __name__ == "__main__":
    main()
