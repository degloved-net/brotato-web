#!/usr/bin/env bash
set -e

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_dir="$repo_dir/work/project"
name="${1:-}"

test -n "$name" || exit 1

git -C "$project_dir" ls-files --others --exclude-standard -z |
  xargs -0 -r git -C "$project_dir" add -N --

git -C "$project_dir" diff --quiet && exit 1

number="$(find "$repo_dir/patches" -maxdepth 1 -type f -name '*.patch' | wc -l)"
number="$(printf '%04d' "$((number + 1))")"
patch="$repo_dir/patches/$number-$name.patch"

git -C "$project_dir" diff --binary > "$patch"
echo "made $patch"
