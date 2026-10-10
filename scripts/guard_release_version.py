#!/usr/bin/env python3
"""Require a new immutable version whenever a DragMP distribution input changes."""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


def must_advance(changed_paths: list[str], previous: str, current: str) -> bool:
    """Return true when source changes reuse the same published version."""
    return any(path.startswith("src/") for path in changed_paths) and previous == current


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True, stderr=subprocess.DEVNULL).strip()


def main() -> int:
    base = os.environ.get("GITHUB_BASE_SHA") or os.environ.get("GITHUB_EVENT_BEFORE") or ""
    if not re.fullmatch(r"[0-9a-f]{40}", base) or base == "0" * 40:
        print("No comparison revision in this event; version-advance check not applicable.")
        return 0
    current = Path("VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-.][0-9A-Za-z.-]+)?", current):
        raise SystemExit("Invalid release VERSION value")
    try:
        previous = git("show", base + ":VERSION")
        paths = git("diff", "--name-only", base, "HEAD", "--", "src").splitlines()
    except subprocess.CalledProcessError:
        raise SystemExit("Could not inspect comparison revision; refusing unvalidated version reuse")
    if must_advance(paths, previous, current):
        raise SystemExit("Distribution sources changed without advancing immutable VERSION")
    print("Distribution version change policy passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
