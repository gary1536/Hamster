#!/usr/bin/env python3
"""嘸蝦米聯想詞庫：從 rime-essay（essay.txt，繁體詞頻）產生鍵盤用的聯想補詞資源。

輸出格式（UTF-8，一行一個字）：
    首字<TAB>接續1<TAB>接續2 ...
接續 = 以該字開頭的 2–4 字詞去掉首字（1–3 字），依 essay 權重由高到低，最多 TOP_N 個。
鍵盤在使用者自己的聯想不足時，用這份補上。

用法：
    python3 BoshiamyAssocBuild.py [essay.txt] [輸出檔]
預設讀 .tmp/SharedSupport/essay.txt（InputSchemaBuild.sh 產生），
輸出到 Packages/HamsterKeyboardKit/Sources/Resources/boshiamy_assoc.txt。
"""
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

TOP_N = 12
MIN_WEIGHT = 50  # 太罕見的詞不收，縮小檔案

root = Path(__file__).resolve().parent
src = Path(sys.argv[1]) if len(sys.argv) > 1 else root / ".tmp/SharedSupport/essay.txt"
dst = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "Packages/HamsterKeyboardKit/Sources/Resources/boshiamy_assoc.txt"


def is_han(ch: str) -> bool:
    return ch == "〇" or unicodedata.name(ch, "").startswith("CJK UNIFIED IDEOGRAPH")


entries = []
for line in src.read_text(encoding="utf-8").splitlines():
    parts = line.split("\t")
    if len(parts) < 2:
        continue
    word, weight = parts[0], parts[1]
    if not 2 <= len(word) <= 4 or not all(is_han(c) for c in word):
        continue
    try:
        w = int(weight)
    except ValueError:
        continue
    if w < MIN_WEIGHT:
        continue
    entries.append((word, w))

# essay 是 OpenCC 標準繁體（爲、啓），轉成台灣用字（為、啟）。有 .deps/bin/opencc 才轉。
opencc = root / ".deps/bin/opencc"
config = root / ".deps/share/opencc/t2tw.json"
if opencc.exists() and config.exists():
    import subprocess

    out = subprocess.run(
        [str(opencc), "-c", str(config)],
        input="\n".join(w for w, _ in entries),
        capture_output=True, text=True, check=True,
    ).stdout.split("\n")
    converted = [o for o in out if o != ""]
    if len(converted) == len(entries):
        entries = [(c, w) for c, (_, w) in zip(converted, entries) if len(c) == len(_)]
        print(f"converted with t2tw: {len(entries)} words")
    else:
        print("WARNING: opencc output size mismatch, keep original", file=sys.stderr)
else:
    print("WARNING: .deps/bin/opencc not found, keep OpenCC standard forms", file=sys.stderr)

# 同一個詞轉換後可能重複，權重相加
merged = defaultdict(int)
for word, w in entries:
    merged[word] += w

groups = defaultdict(list)
for word, w in merged.items():
    groups[word[0]].append((w, word[1:]))

lines = []
for lead in sorted(groups):
    conts = [c for _, c in sorted(groups[lead], key=lambda x: -x[0])[:TOP_N]]
    lines.append("\t".join([lead] + conts))

dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"{dst}: {len(lines)} lead chars, {dst.stat().st_size} bytes")
