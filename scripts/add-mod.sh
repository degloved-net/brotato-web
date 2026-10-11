#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/work/project"
source "$root/scripts/paths.sh"

if [[ ! -f "$project/project.godot" ]]; then
    echo 'missing work/project; run scripts/recover.sh first' >&2
    exit 1
fi

ask_path mod_zip 'mod zip'
if [[ ! -f "$mod_zip" ]]; then
    echo 'mod zip not found' >&2
    exit 1
fi
entries="$(unzip -Z1 "$mod_zip")"
mods=()
while IFS= read -r entry; do
    case "$entry" in
        /*|../*|*/../*|*/..)
            echo 'invalid path in mod zip' >&2
            exit 1
            ;;
        */mod_main.gd) mods+=("$entry") ;;
    esac
done <<< "$entries"
if (( ${#mods[@]} != 1 )); then
    echo 'choose a zip with one mod_main.gd' >&2
    exit 1
fi

folder="${mods[0]%/mod_main.gd}"
name="${folder#mods-unpacked/}"
if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo 'expected a mod folder or mods-unpacked/mod-folder' >&2
    exit 1
fi
target="$project/mods-unpacked/$name"
if [[ -e "$target" ]]; then
    echo "mod already exists: $name" >&2
    exit 1
fi

temp="$(mktemp -d "$root/work/mod.XXXXXX")"
trap 'rm -rf -- "$temp"' EXIT
unzip -q "$mod_zip" "$folder/*" -d "$temp"
if [[ ! -f "$temp/$folder/manifest.json" ]]; then
    echo 'mod is missing manifest.json' >&2
    exit 1
fi
mkdir -p "$project/mods-unpacked"
mv -- "$temp/$folder" "$target"
echo "added $name"
