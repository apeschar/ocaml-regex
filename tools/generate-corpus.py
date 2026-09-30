#!/usr/bin/env python3
"""Generate a standalone, deterministic regex benchmark corpus (no downloads)."""
import hashlib
import json
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1] / "corpus"
SEED = 1729
randomizer = random.Random(SEED)
ROOT.mkdir(exist_ok=True)

# Names describe generic regex operations, not application modules or vendors.
PATTERNS = [
    ["literal_marker", "Re", "", "document", r"session-verification"],
    ["caseless_literal", "Re", "`CASELESS", "document", r"javascript enabled"],
    ["word_boundary", "Re", "", "document", r"\brequest_token\b"],
    ["signature_alternation", "Re", "`CASELESS", "document", r"assets\.example\.org|/static/assets/|data-component|client\.ready"],
    ["attribute_capture", "Re", "", "document", r'''data-record-id\s*=\s*["']([0-9]+)["']'''],
    ["assignment_capture", "Re", "", "document", r"\b(?:let|const)\s+recordId\s*=\s*([0-9]+)\s*;"],
    ["multiline_log_capture", "Re", "`MULTILINE", "log", r"^(INFO|WARN|ERROR)\s+([0-9]{4}-[0-9]{2}-[0-9]{2})\s+(.+)$"],
    ["numeric_identifier", "Re", "", "token", r"\A(?:[0-9]{8}|[0-9]{12,14})\z"],
    ["path_capture", "Re", "`CASELESS", "path", r"^(/(?:[a-z]{2}/)?items/([^/?#]+))/?$"],
    ["path_component", "Re", "`CASELESS", "path", r"/items/"],
    ["anchored_heading", "Re", "`CASELESS", "heading", r"^\s*Please wait[.!]?\s*$"],
    ["byte_marker", "Re", "", "bytes", r"\x00record:[0-9]+"],
    ["atomic_group", "Pcre", "", "token", r"\A(?>[a-z]+)[0-9]+\z"],
]
records = []


def emit(category, name, data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    digest = hashlib.sha256(data).hexdigest()
    (ROOT / digest).write_bytes(data)
    records.append({"category": category, "name": name, "sha256": digest, "bytes": len(data)})


words = ["alpha", "beta", "gamma", "delta", "sample", "document", "paragraph", "message", "value", "content"]
for size in [4096, 65536, 1048576]:
    for case in range(8):
        line = "<p>" + " ".join(randomizer.choice(words) for _ in range(64)) + "</p>\n"
        padding = (line * (size // len(line) + 1))[:size]
        marker = (
            '<section class="session-verification">JavaScript Enabled request_token</section>'
            '<script src="https://assets.example.org/app.js"></script>'
            f'<div data-record-id="{1000 + case}"></div>'
            f'<script>const recordId = {1000 + case};</script>'
        )
        # Half positive, with early/middle/late hits; half negative.
        if case < 4:
            offset = [0, size // 2, size, size // 3][case]
            padding = padding[:offset] + marker + padding[offset:]
        emit("document", f"document-{size}-{case}", "<!doctype html><html><body>" + padding + "</body></html>")

for size in [4096, 65536]:
    for case in range(8):
        level = ["INFO", "WARN", "ERROR", "DEBUG"][case % 4]
        line = f"{level} 2026-01-02 record={1000 + case} message=generic-event\n"
        emit("log", f"log-{size}-{case}", (line * (size // len(line) + 1))[:size])

paths = ["/", "/items/", "/catalog/sample", "/items/sample?x=1", "/items/sample#section"]
paths += [f"/{prefix}items/record-{i}{suffix}" for prefix in ["", "en/", "fr/", "nested/extra/"]
          for suffix in ["", "/"] for i in range(8)]
paths += ["/ITEMS/UPPERCASE", "/items/with-hyphen"]
for i, path in enumerate(paths):
    emit("path", f"path-{i:03}", path)

for i, token in enumerate(["12345678", "123456789012", "12345678901234", "123", "123456789012345", "abc123", "alpha9", "alpha", "12345678x", "", "0"]):
    emit("token", f"token-{i:02}", token)
for i, heading in enumerate(["Please wait", " please wait! ", "PLEASE WAIT.", "Ready", "Please wait for input", "", "\nPlease wait\n"]):
    emit("heading", f"heading-{i:02}", heading)
for i in range(8):
    # Arbitrary byte strings, including NUL and non-UTF8 bytes. No word-boundary
    # patterns are applied here, so ASCII vs Latin-1 classes cannot bias parity.
    data = bytes(randomizer.randrange(256) for _ in range(32768))
    if i % 2 == 0:
        data += b"\x00record:12345"
    emit("bytes", f"bytes-{i:02}", data)

(ROOT / "patterns.tsv").write_text("".join("\t".join(row) + "\n" for row in PATTERNS))
(ROOT / "payloads.tsv").write_text("".join(f'{r["category"]}\t{r["name"]}\t{r["sha256"]}\n' for r in records))
(ROOT / "manifest.json").write_text(json.dumps({"format": 1, "generator": "tools/generate-corpus.py", "seed": SEED, "patterns": PATTERNS, "payloads": records}, indent=2) + "\n")
print(f"Generated {len(PATTERNS)} patterns, {len(records)} payloads, {sum(r['bytes'] for r in records):,} bytes")
