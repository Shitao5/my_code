# EPUB to DOCX Translator (Ollama)

Translate an English EPUB to a Chinese Word document using a local Ollama model
while keeping images at the same positions.

## Requirements

- Python 3.9+
- Ollama running locally with the `qwen3` model installed

Install dependencies:

```bash
pip install -r requirements.txt
```

The translator shows a progress bar per EPUB section.

## Usage

```bash
python translate_epub_to_docx.py \
  --input "The AI-Driven Leader.epub" \
  --output-dir "out" \
  --model qwen3:8b
```

To run with your `hunyuan-mt-abliterated` model pulled from the community
registry, pass the fully qualified name (note the `huihui_ai` namespace):

```bash
python translate_epub_to_docx.py \
  --input "The AI-Driven Leader.epub" \
  --output-dir "out" \
  --model huihui_ai/hunyuan-mt-abliterated:latest
```

Optional flags:

- `--url` Ollama base URL (default: `http://localhost:11434`)
- `--max-chars` max characters per translation chunk (default: 1500)
- `--retry` retry count for Ollama calls (default: 2)

## Workflow

1. Translate EPUB into multiple `.docx` files under `out/`.
2. Merge the translated `.docx` files into a single document.

## Merge translated DOCX files

Merge all `.docx` files in a directory into a single Word document while
preserving styles, sizes, colors, and images. The script will:

- Replace `</translation>` tags.
- Collapse consecutive manual line breaks or empty paragraphs into a single
  paragraph break.
- Set all fonts to `宋体`.
- Resize images to 14 cm width (height auto-scaled) and center them.

```bash
python merge_docx.py -i out -o merged.docx
```

Optional flags:

- `-i/--input-dir` directory containing `.docx` files (default: `out`)
- `-o/--output` output filename (default: `merged.docx`)

Notes:

- Files are merged in filename sort order (e.g., `section_01_of_24.docx`).
- Image resizing only affects inline images in the body (not headers/footers).
