#!/usr/bin/env bash
set -Eeuo pipefail
root="${DRAGMP_PUBLIC_BUILDER_ROOT:-/srv/dragmp-public-builder}"; source_dir="$root/source"; state="$root/released-revision"
repository="${DRAGMP_PUBLIC_REPOSITORY:-caden4314/DragMP-Public}"; branch="${DRAGMP_PUBLIC_REF:-main}"
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
code="$(curl -sS -o /dev/null -w '%{http_code}' -H "$auth" -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/${repository}/releases/tags/${tag}")"
[[ "$code" != 200 ]] || { echo "Release $tag already exists; bump VERSION." >&2; exit 1; }
python3 "$source_dir/scripts/package.py"
payload="$(python3 - "$tag" "$revision" <<'PY'
import json,sys
print(json.dumps({'tag_name':sys.argv[1], 'target_commitish':sys.argv[2], 'name':f'DragMP Public {sys.argv[1]}', 'prerelease':True, 'generate_release_notes':True}))
PY
)"
release="$(curl -fsS -X POST -H "$auth" -H 'Accept: application/vnd.github+json' -H 'Content-Type: application/json' "https://api.github.com/repos/${repository}/releases" -d "$payload")"
release_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$release")"
for asset in DragMP-Public-without-blocker-Client.zip DragMP-Public-with-blocker-Client.zip DragMP-Public-Server.zip SHA256SUMS.txt; do curl -fsS -X POST -H "$auth" -H 'Content-Type: application/octet-stream' "https://uploads.github.com/repos/${repository}/releases/${release_id}/assets?name=${asset}" --data-binary "@$source_dir/build/$asset" >/dev/null; done
printf '%s\n' "$revision" >"$state.tmp"; mv "$state.tmp" "$state"; echo "[DragMP Public Builder] published $tag"

