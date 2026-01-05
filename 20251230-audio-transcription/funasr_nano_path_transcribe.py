import argparse
import time
from pathlib import Path

from funasr import AutoModel
import funasr.models.fun_asr_nano.model  # Ensure FunASRNano is registered.
from tqdm import tqdm


AUDIO_EXTS = {
    ".wav",
    ".mp3",
    ".flac",
    ".m4a",
    ".aac",
    ".ogg",
    ".opus",
    ".wma",
    ".aiff",
    ".aif",
    ".aifc",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe audio from a file or directory path with Fun-ASR-Nano."
    )
    parser.add_argument(
        "input_path",
        help="Audio file path or directory path to transcribe.",
    )
    parser.add_argument(
        "--output-dir",
        default="",
        help="Optional output directory for .md files.",
    )
    parser.add_argument(
        "--device",
        default="cpu",
        help="Device to run on (default: cpu).",
    )
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="When input is a directory, scan files recursively.",
    )
    return parser.parse_args()


def collect_inputs(root: Path, recursive: bool) -> list[Path]:
    if root.is_file():
        return [root]
    if not root.is_dir():
        return []
    if recursive:
        candidates = root.rglob("*")
    else:
        candidates = root.glob("*")
    return [p for p in candidates if p.is_file() and p.suffix.lower() in AUDIO_EXTS]


def build_output_path(
    src: Path, input_root: Path, output_root: Path | None
) -> Path:
    if output_root is None:
        return src.with_suffix(".md")
    if input_root.is_file():
        return output_root / f"{src.stem}.md"
    rel_parent = src.parent.relative_to(input_root)
    return output_root / rel_parent / f"{src.stem}.md"


def main() -> None:
    args = parse_args()
    input_path = Path(args.input_path).expanduser().resolve()
    output_root = (
        Path(args.output_dir).expanduser().resolve() if args.output_dir else None
    )

    inputs = collect_inputs(input_path, args.recursive)
    if not inputs:
        print(f"No audio files found under: {input_path}")
        return

    model = AutoModel(
        model="FunAudioLLM/Fun-ASR-Nano-2512",
        vad_model="fsmn-vad",
        vad_kwargs={"max_single_segment_time": 30000},
        device=args.device,
        disable_update=True,
    )

    start_time = time.monotonic()
    for src in tqdm(inputs, desc="Transcribing", unit="file"):
        out_path = build_output_path(src, input_path, output_root)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        res = model.generate(input=[str(src)], cache={}, batch_size_s=0)
        text = res[0].get("text", "")
        out_path.write_text(text + "\n", encoding="utf-8")
        tqdm.write(f"Wrote: {out_path}")
        elapsed = time.monotonic() - start_time
        tqdm.write(f"Elapsed: {elapsed:.1f}s")


if __name__ == "__main__":
    main()
