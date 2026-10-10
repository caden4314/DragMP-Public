#!/usr/bin/env python3
"""Fail closed when GitHub release artifacts differ from local deterministic packages."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


def verify(build_dir: Path, release_path: Path, required: list[str]) -> None:
    with release_path.open(encoding="utf-8") as stream:
        release = json.load(stream)
    if not isinstance(release, dict):
        raise ValueError("invalid release metadata")
    if release.get("draft") is True:
        raise ValueError("release is still a draft")
    assets = {
        asset.get("name"): asset
        for asset in release.get("assets", [])
        if isinstance(asset, dict)
    }
    if not required:
        raise ValueError("no expected assets specified")
    for name in required:
        if name != Path(name).name or not name or name.startswith("."):
            raise ValueError("unsafe asset name")
        asset = assets.get(name)
        if not asset or asset.get("state") != "uploaded":
            raise ValueError(f"missing or incomplete released asset: {name}")
        artifact = build_dir / name
        if not artifact.is_file() or artifact.stat().st_size == 0:
            raise ValueError(f"missing or empty local asset: {name}")
        digest = "sha256:" + hashlib.sha256(artifact.read_bytes()).hexdigest()
        if asset.get("digest") != digest:
            raise ValueError(f"published asset checksum mismatch: {name}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit("usage: verify_release_assets.py BUILD_DIR RELEASE_JSON ASSET...")
    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:])
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"[DragMP Builder] Release verification failed: {exc}")
    print("[DragMP Builder] Published release SHA-256 verification passed.")
