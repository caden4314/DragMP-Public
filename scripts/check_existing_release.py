#!/usr/bin/env python3
"""Verify local deterministic DragMP release artifacts against any existing tag."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parents[1]
repo = os.environ.get("GITHUB_REPOSITORY", "")
version = (root / "VERSION").read_text(encoding="utf-8").strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+[-.][0-9A-Za-z.-]+", version):
    raise SystemExit("Invalid DragMP version")
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
    raise SystemExit("Invalid repository identity")
tag = "v" + version
url = "https://api.github.com/repos/" + repo + "/releases/tags/" + tag
headers = {"Accept": "application/vnd.github+json", "User-Agent": "Scenic-Route-Builder-CI"}
token = os.environ.get("GITHUB_TOKEN", "")
if token:
    headers["Authorization"] = "Bearer " + token
try:
    with urlopen(Request(url, headers=headers), timeout=25) as response:
        release = json.load(response)
except HTTPError as exc:
    if exc.code == 404:
        print("Version", tag, "has no release yet; local packaging passed.")
        raise SystemExit(0)
    raise SystemExit("GitHub release lookup failed with HTTP " + str(exc.code)) from None
except (URLError, TimeoutError):
    raise SystemExit("GitHub release lookup failed: network unavailable") from None

if release.get("draft"):
    raise SystemExit("Release exists but is a draft")
assets = {a.get("name"): a for a in release.get("assets", [])}
files = sorted((root / "build").glob("*"))
if not files or not any(x.suffix == ".zip" for x in files) or not any(x.name == "SHA256SUMS.txt" for x in files):
    raise SystemExit("Expected release artifacts missing")
for file in files:
    if not file.is_file():
        raise SystemExit("Unexpected non-file artifact")
    item = assets.get(file.name)
    digest = "sha256:" + hashlib.sha256(file.read_bytes()).hexdigest()
    if item is None or item.get("state") != "uploaded" or item.get("digest") != digest:
        raise SystemExit("Published release differs from local deterministic output: " + file.name)
print("Verified existing GitHub release", tag, "matches", len(files), "local artifacts")
