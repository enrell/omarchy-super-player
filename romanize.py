#!/usr/bin/env python3
"""Romanize lyrics to Latin script. Reads text on stdin, writes it on stdout.

One output line per input line, so the caller can map lines back by index.

Tools, best first:
  1. pykakasi  — Japanese readings with word tokens joined by spaces. It is a
     pure Python package; the plugin looks for it in ~/.local/share/romanize
     (see README: `uv pip install --target ~/.local/share/romanize pykakasi`).
  2. kakasi    — two passes: `-w` segments words (kanji left alone), then the
     remaining kanji tokens are converted in one batch. Ships in Arch's extra
     repo, so it may be installed system wide or under ~/.local.
  3. uconv     — ICU transliteration for everything else (kana, Hangul,
     Cyrillic, Greek, ...). ICU turns kanji into pinyin, which is wrong for
     Japanese, so Japanese text only gets its kana transliterated.

With --tool the chosen tool is printed instead (used by the widget settings).
"""
import os
import re
import shutil
import subprocess
import sys

KANA = re.compile(r"[\u3040-\u30ff\u30fc]")
KANJI = re.compile(r"[\u4e00-\u9fff\u3005\u3006]")
JAPANESE = re.compile(r"[\u3040-\u30ff\u4e00-\u9fff\u3005\u3006]")
PYKAKASI_PATH = os.path.expanduser("~/.local/share/romanize")


def load_pykakasi():
    try:
        import pykakasi
    except ImportError:
        if not os.path.isdir(PYKAKASI_PATH):
            return None
        sys.path.append(PYKAKASI_PATH)
        try:
            import pykakasi
        except ImportError:
            return None
    return pykakasi.kakasi()


def pick_tool():
    if load_pykakasi() is not None:
        return "pykakasi"
    if shutil.which("kakasi"):
        return "kakasi"
    if shutil.which("uconv"):
        return "uconv"
    return "none"


def kakasi(text, *flags):
    result = subprocess.run(
        ["kakasi", "-i", "utf8", "-o", "utf8", *flags],
        input=text, capture_output=True, text=True,
    )
    return result.stdout


def romanize_with_pykakasi(kakasi_obj, line):
    return " ".join(token["hepburn"] for token in kakasi_obj.convert(line)).strip()


def romanize_with_kakasi(text):
    # Pass 1: word segmentation, kana converted, kanji kept.
    segmented = kakasi(text, "-w", "-Ja", "-Ha", "-Ka", "-Ea")
    lines = [line.split() for line in segmented.split("\n")]

    # Pass 2: convert every distinct kanji token in a single kakasi call.
    tokens = sorted({token for line in lines for token in line if KANJI.search(token)})
    readings = {}
    if tokens:
        converted = kakasi("\n".join(tokens), "-Ja", "-Ha", "-Ka", "-Ea").split("\n")
        for token, reading in zip(tokens, converted):
            readings[token] = reading.strip().replace("^", " ")

    return "\n".join(
        " ".join(readings.get(token, token) for token in line).replace("^", " ")
        for line in lines
    )


def romanize_with_uconv(text):
    chain = "Katakana-Hiragana; Hiragana-Latin" if KANA.search(text) else "Any-Latin"
    result = subprocess.run(
        ["uconv", "-x", chain], input=text, capture_output=True, text=True,
    )
    return result.stdout


def romanize(text, tool=None):
    tool = tool or pick_tool()
    if tool == "none":
        return text

    if tool == "pykakasi":
        converter = load_pykakasi()
        out = []
        for line in text.split("\n"):
            if JAPANESE.search(line):
                out.append(romanize_with_pykakasi(converter, line))
            else:
                out.append(line)
        return "\n".join(out)

    if tool == "kakasi" and JAPANESE.search(text):
        return romanize_with_kakasi(text)

    return romanize_with_uconv(text)


if __name__ == "__main__":
    if "--tool" in sys.argv:
        print(pick_tool())
    else:
        sys.stdout.write(romanize(sys.stdin.read()))
