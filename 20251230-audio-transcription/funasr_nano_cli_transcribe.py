import argparse
import time
from pathlib import Path

from funasr import AutoModel
import funasr.models.fun_asr_nano.model  # Ensure FunASRNano is registered.
from tqdm import tqdm


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe one or more audio files with Fun-ASR-Nano."
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
    return parser.parse_args()


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
        text = res[0].get("text", "")
        out_path.write_text(text + "\n", encoding="utf-8")
        tqdm.write(f"Wrote: {out_path}")
        elapsed = time.monotonic() - start_time
        tqdm.write(f"Elapsed: {elapsed:.1f}s")


if __name__ == "__main__":
    main()
