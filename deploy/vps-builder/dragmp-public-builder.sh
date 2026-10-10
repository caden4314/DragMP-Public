#!/usr/bin/env bash
set -Eeuo pipefail
root="${DRAGMP_PUBLIC_BUILDER_ROOT:-/srv/dragmp-public-builder}"; source_dir="$root/source"; state="$root/released-revision"
repository="${DRAGMP_PUBLIC_REPOSITORY:-caden4314/DragMP-Public}"; branch="${DRAGMP_PUBLIC_REF:-main}"
for required_command in git curl python3 mktemp flock; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "[DragMP Builder] Missing required command: $required_command" >&2
    exit 127
  fi
done
mkdir -p "$root"; exec 9>"$root/builder.lock"; flock -n 9 || exit 0
askpass="$(mktemp "$root/.askpass.XXXXXX")"; trap 'rm -f -- "$askpass"' EXIT
cat >"$askpass" <<'EOF'
#!/usr/bin/env bash
case "$1" in *Username*) echo x-access-token;; *Password*) echo "${SR_BUILDER_GITHUB_TOKEN:?}";; esac
EOF
chmod 0700 "$askpass"; export GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0
remote="https://github.com/${repository}.git"
if [[ -d "$source_dir/.git" ]]; then git -C "$source_dir" remote set-url origin "$remote"; git -C "$source_dir" fetch --prune origin "$branch"; else rm -rf "$source_dir"; git clone --branch "$branch" "$remote" "$source_dir"; fi
revision="$(git -C "$source_dir" rev-parse "origin/$branch")"
[[ "$revision" != "$(cat "$state" 2>/dev/null || true)" ]] || { echo '[DragMP Public Builder] current'; exit 0; }
git -C "$source_dir" reset --hard "$revision"; git -C "$source_dir" clean -ffd
version="$(tr -d '[:space:]' <"$source_dir/VERSION")"; tag="v$version"; auth="Authorization: Bearer ${SR_BUILDER_GITHUB_TOKEN}"

asset_names=(DragMP-Public-without-blocker-Client.zip DragMP-Public-with-blocker-Client.zip DragMP-Public-Server.zip SHA256SUMS.txt)
release_response="$(mktemp "$root/.release-response.XXXXXX")"
trap 'rm -f -- "$askpass" "$release_response"' EXIT

verify_release_assets() {
  local response_file="$1"
  python3 - "$source_dir/build" "$response_file" "${asset_names[@]}" <<'PY'
import hashlib, json, pathlib, sys
build_dir = pathlib.Path(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as stream:
    release = json.load(stream)
assets = {asset.get("name"): asset for asset in release.get("assets", [])}
for name in sys.argv[3:]:
    item = assets.get(name)
    if not item or item.get("state") != "uploaded":
        raise SystemExit("missing or incomplete released asset: " + name)
    digest = "sha256:" + hashlib.sha256((build_dir / name).read_bytes()).hexdigest()
    if item.get("digest") != digest:
        raise SystemExit("published asset digest mismatch: " + name)
print("[DragMP Builder] Verified published artifact SHA-256 digests.")
PY
}

# Package before checking whether an existing tag already has valid assets.
python3 "$source_dir/scripts/package.py"
code="$(curl -sS -o "$release_response" -w '%{http_code}' \
  -H "$auth" -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/${repository}/releases/tags/${tag}")" || {
    echo '[DragMP Builder] GitHub release lookup failed.' >&2
    exit 1
  }
case "$code" in
  200)
    verify_release_assets "$release_response"
    printf '%s\n' "$revision" > "$state.tmp"
    mv "$state.tmp" "$state"
    echo "[DragMP Builder] $tag already published and verified; synchronized local state."
    exit 0
    ;;
  404) ;;
  *)
    echo "[DragMP Builder] Release lookup failed with HTTP $code; not publishing." >&2
    exit 1
    ;;
esac

payload="$(python3 - "$tag" "$revision" <<'PY'
import json,sys
print(json.dumps({'tag_name':sys.argv[1], 'target_commitish':sys.argv[2], 'name':f'DragMP Public {sys.argv[1]}', 'prerelease':True, 'generate_release_notes':True}))
PY
)"
release="$(curl -fsS -X POST -H "$auth" -H 'Accept: application/vnd.github+json' -H 'Content-Type: application/json' "https://api.github.com/repos/${repository}/releases" -d "$payload")"
release_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$release")"
for asset in DragMP-Public-without-blocker-Client.zip DragMP-Public-with-blocker-Client.zip DragMP-Public-Server.zip SHA256SUMS.txt; do curl -fsS -X POST -H "$auth" -H 'Content-Type: application/octet-stream' "https://uploads.github.com/repos/${repository}/releases/${release_id}/assets?name=${asset}" --data-binary "@$source_dir/build/$asset" >/dev/null; done
curl -fsS -o "$release_response" -H "$auth" \
  -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/${repository}/releases/${release_id}" \
  || { echo '[DragMP Builder] Failed to verify uploaded release.' >&2; exit 1; }
verify_release_assets "$release_response"
printf '%s\n' "$revision" >"$state.tmp"; mv "$state.tmp" "$state"; echo "[DragMP Public Builder] published $tag"

