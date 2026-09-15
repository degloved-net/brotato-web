#!/usr/bin/env bash
set -e

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_dir="$repo_dir/work"

read -r -e -p "gdre tools executable: " gdre
read -r -e -p "base pck: " base_pck

test ! -e "$work_dir" || exit 1

mkdir -p "$work_dir"
"$gdre" --headless --recover="$base_pck" \
  --output="$work_dir/project" --skip-checksum-check

while true; do
  read -r -e -p "dlc pck (leave blank when done): " dlc_pck
  test -n "$dlc_pck" || break
  dlc_dir="$(mktemp -d "$work_dir/dlc.XXXXXX")"
  "$gdre" --headless --recover="$dlc_pck" \
    --output="$dlc_dir" --skip-checksum-check
  if test -d "$dlc_dir/dlcs"; then
    mkdir -p "$work_dir/project/dlcs"
    cp -a "$dlc_dir/dlcs/." "$work_dir/project/dlcs/"
  fi
  if test -d "$dlc_dir/.import"; then
    mkdir -p "$work_dir/project/.import"
    cp -a "$dlc_dir/.import/." "$work_dir/project/.import/"
  fi
  find "$dlc_dir" -depth -delete
done

for patch in "$repo_dir"/patches/*.patch; do
  git -C "$work_dir/project" apply "$patch"
done
git -C "$work_dir/project" init -q
git -C "$work_dir/project" add -A
git -C "$work_dir/project" -c user.name=local -c user.email=local commit -qm base

echo "project is in $work_dir/project"
