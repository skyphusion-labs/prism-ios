#!/usr/bin/env python3
"""Regenerate App/BundledLegalText.swift from repo LICENSE + NOTICE."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
license = (ROOT / "LICENSE").read_text(encoding="utf-8")
notice_path = ROOT / "NOTICE"
notice = notice_path.read_text(encoding="utf-8") if notice_path.exists() else ""

n = 5
while ("#" * n + '"""') in license or ('"""' + "#" * n) in license:
  n += 1
open_d = "#" * n + '"""'
close_d = '"""' + "#" * n

out = ROOT / "App" / "BundledLegalText.swift"
out.write_text(
  "// Generated from repo LICENSE + NOTICE for offline AGPL display.\n"
  "// Regenerate: python3 scripts/embed-legal.py\n\n"
  "enum BundledLegalText {\n"
  f"  static let licenseAGPL3: String = {open_d}\n"
  f"{license}"
  f"{close_d}\n\n"
  f"  static let notice: String = {open_d}\n"
  f"{notice}"
  f"{close_d}\n"
  "}\n",
  encoding="utf-8",
)
print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size} bytes)")
