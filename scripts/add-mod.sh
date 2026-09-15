#!/usr/bin/env bash
set -e

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_dir="$repo_dir/work/project"

read -r -e -p "mod zip: " mod_zip

mod_path="$(unzip -Z1 "$mod_zip" | sed -n '/mod_main.gd$/p' | head -n 1)"
mod_name="$(printf '%s\n' "$mod_path" | sed -n 's#^mods-unpacked/\([^/]*\)/mod_main.gd$#\1#p;s#^\([^/]*\)/mod_main.gd$#\1#p')"
test -n "$mod_name"
target_dir="$project_dir/mods-unpacked/$mod_name"

test ! -e "$target_dir"
mkdir -p "$project_dir/mods-unpacked"
case "$mod_path" in
  mods-unpacked/*) unzip -q "$mod_zip" -d "$project_dir" ;;
  *) unzip -q "$mod_zip" -d "$project_dir/mods-unpacked" ;;
esac

echo "added $mod_name"
