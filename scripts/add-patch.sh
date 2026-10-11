#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/work/project"
name="${1:-}"
if [[ -z "$name" ]]; then
    read -r -p 'patch name: ' name
fi

if [[ ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo 'use lowercase letters, numbers, and dashes' >&2
    exit 1
fi

if [[ ! -d "$project/.git" ]] || ! git -C "$project" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo 'missing patch history in work/project' >&2
    exit 1
fi

last="$(find "$root/patches" -name '*.patch' -printf '%f\n' | sort | tail -n 1)"
number="${last%%-*}"
number="$((10#${number:-0000} + 1))"
patch="$root/patches/$(printf '%04d' "$number")-$name.patch"

git -C "$project" add -A
if git -C "$project" diff --cached --quiet; then
    echo 'nothing to save'
    exit 1
fi

git -C "$project" diff --cached --binary HEAD > "$patch"
git -C "$project" -c user.name=local -c user.email=local commit -qm "$name"
echo "saved $patch"
