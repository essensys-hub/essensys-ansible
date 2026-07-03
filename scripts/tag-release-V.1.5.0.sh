#!/usr/bin/env bash
# Pose le tag annoté V.1.5.0 sur les SHAs figés dans essensys-memory/releases/V.1.5.0-manifest.yaml
set -euo pipefail

ROOT="${ESSENSYS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
TAG=V.1.5.0
MSG="Essensys V.1.5.0 — baseline pré audit-trail (CM5 gateway + OVH + Raspberry)"

tag_sha() {
  local repo=$1 sha=$2
  local dir="$ROOT/$repo"
  [[ -d "$dir/.git" ]] || { echo "SKIP $repo (no git)"; return 0; }
  if git -C "$dir" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "EXISTS $repo $TAG -> $(git -C "$dir" rev-parse --short "$TAG")"
    return 0
  fi
  git -C "$dir" tag -a "$TAG" "$sha" -m "$MSG"
  echo "TAGGED $repo $TAG -> $sha"
}

tag_head() {
  local repo=$1
  local dir="$ROOT/$repo"
  [[ -d "$dir/.git" ]] || { echo "SKIP $repo (no git)"; return 0; }
  if git -C "$dir" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "EXISTS $repo $TAG -> $(git -C "$dir" rev-parse --short "$TAG")"
    return 0
  fi
  git -C "$dir" tag -a "$TAG" -m "$MSG"
  echo "TAGGED $repo $TAG -> $(git -C "$dir" rev-parse --short HEAD)"
}

tag_sha essensys-server-backend bb953d0
tag_sha essensys-server-frontend 25e7649
tag_sha essensys-user-portal-backend 9525a01
tag_sha essensys-user-portal-frontend 974298a
tag_sha essensys-raspberry-gateway 1c6cab3

tag_head essensys-memory
tag_head essensys-ansible
tag_head essensys-raspberry-install

echo "=== Tags V.1.5.0 posés. Push : git push origin V.1.5.0 (par dépôt) ==="
