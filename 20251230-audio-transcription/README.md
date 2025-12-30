# 录音转写（Fun-ASR-Nano）

这个文件夹包含一个基于 FunASR 的命令行脚本，用于批量转写音频文件，并将结果输出为同名的 `.md` 文件。

## 文件说明

- `funasr_nano_cli_transcribe.py`：命令行转写脚本（支持多个输入文件、进度条、运行时长输出）

## 使用前提

确保已安装 FunASR 与必要依赖，并完成 Fun-ASR-Nano 模型的首次下载。

如果之前在 `/home/shitao5/rproject/20251230-funasr` 中已成功运行脚本，则无需重复安装。

## 使用方法

### 基本用法（多个文件）

```bash
python3.13 funasr_nano_cli_transcribe.py /path/to/a.mp3 /path/to/b.wav
```

输出文件会与输入文件同目录、同名（仅后缀改为 `.md`），例如：

- `/path/to/a.md`
- `/path/to/b.md`

### 指定输出目录

```bash
python3.13 funasr_nano_cli_transcribe.py /path/to/a.mp3 /path/to/b.wav --output-dir /path/to/output
```

### 指定设备（默认 cpu）

```bash
python3.13 funasr_nano_cli_transcribe.py /path/to/a.mp3 --device cpu
```

## 运行示例

```bash
cd /home/shitao5/rproject/my_code/20251230-audio-transcription
python3.13 funasr_nano_cli_transcribe.py /home/shitao5/test/16k16bit.mp3
```

运行过程中会显示进度条，并在每个文件处理完成后输出已运行时长。
