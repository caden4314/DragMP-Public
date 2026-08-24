#!/usr/bin/env python3
from __future__ import annotations
import hashlib, shutil, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
STAMP = (2026, 1, 1, 0, 0, 0)

def make(source: Path, destination: Path):
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.unlink(missing_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in sorted(p for p in source.rglob("*") if p.is_file()):
            info = zipfile.ZipInfo(path.relative_to(source).as_posix(), STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, path.read_bytes())

def main():
    shutil.rmtree(BUILD, ignore_errors=True); BUILD.mkdir()
    outputs = []
    for variant in ("without-blocker", "with-blocker"):
        client = BUILD / f"DragMP-Public-{variant}-Client.zip"
        make(ROOT / "src" / f"client-{variant}", client); outputs.append(client)
    server = BUILD / "DragMP-Public-Server.zip"
    make(ROOT / "src/server", server); outputs.append(server)
    sums=[]
    for path in outputs:
        digest=hashlib.sha256(path.read_bytes()).hexdigest(); sums.append(f"{digest}  {path.name}")
        print(f"{path.name}: {path.stat().st_size} bytes sha256={digest}")
    (BUILD / "SHA256SUMS.txt").write_text("\n".join(sums)+"\n", encoding="utf-8", newline="")

if __name__ == "__main__": main()

