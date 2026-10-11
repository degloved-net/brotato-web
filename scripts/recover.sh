#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/work/project"
source "$root/scripts/paths.sh"

if [[ -e "$project" ]]; then
    echo 'work/project exists; move it aside first' >&2
    exit 1
fi

interactive=false
if (( $# == 0 )); then
    interactive=true
    ask_path game 'game project folder or pck'
else
    game="$1"
    shift
fi
if [[ ! -e "$game" ]]; then
    echo 'game files not found' >&2
    exit 1
fi

gdre_args=()
gdre=''
prepare_gdre() {
    if [[ -n "$gdre" ]]; then return; fi
    ask_path gdre 'gdre tools executable' "$(command -v gdre_tools || true)"
    if ! command -v "$gdre" >/dev/null 2>&1; then
        echo 'gdre tools executable not found' >&2
        exit 1
    fi
    ask_path key_file 'key file (blank if none)'
    ask_path decryptor 'decryptor script (blank if none)'
    if [[ -n "$key_file" ]]; then
        if [[ ! -f "$key_file" ]]; then
            echo 'key file not found' >&2
            exit 1
        fi
        gdre_args+=("--key=$(tr -d '\r\n' < "$key_file")")
    fi
    if [[ -n "$decryptor" ]]; then
        if [[ ! -f "$decryptor" ]]; then
            echo 'decryptor script not found' >&2
            exit 1
        fi
        gdre_args+=("--custom-decryption-script=$decryptor")
    fi
}

mkdir -p "$project"
dlc=''
trap 'if (( $? != 0 )); then rm -rf -- "$project"; fi; if [[ -n "$dlc" ]]; then rm -rf -- "$dlc"; fi' EXIT

if [[ -d "$game" ]]; then
    cp -a "$game/." "$project/"
    rm -rf "$project/.git"
else
    prepare_gdre
    "$gdre" --headless --recover="$game" --output="$project" "${gdre_args[@]}"
fi

packs=("$@")
if $interactive; then
    index=1
    while true; do
        name="dlc_$index"
        ask_path "$name" 'dlc pck (blank when done)'
        pack="${!name}"
        if [[ -z "$pack" ]]; then break; fi
        packs+=("$pack")
        index=$((index + 1))
    done
fi
for pack in "${packs[@]}"; do
    if [[ ! -f "$pack" ]]; then
        echo 'dlc pack not found' >&2
        exit 1
    fi
    prepare_gdre
    dlc="$(mktemp -d "$root/work/dlc.XXXXXX")"
    "$gdre" --headless --recover="$pack" --output="$dlc" "${gdre_args[@]}"
    for file in project.godot export_presets.cfg; do
        if [[ -f "$dlc/$file" ]]; then rm -- "$dlc/$file"; fi
    done
    rm -rf "$dlc/.git"
    cp -a "$dlc/." "$project/"
    rm -rf "$dlc"
    dlc=''
done

version="$(sed -n 's/^config_version[[:space:]]*=[[:space:]]*//p' "$project/project.godot" | tr -d '\r ')"
case "$version" in
    4) defaults=godot3 ;;
    5) defaults=godot4 ;;
    *)
        echo 'expected a godot 3 or 4 project' >&2
        exit 1
        ;;
esac

# The editor doesn't read plugin overrides from web.cfg.
sed -i '/^\[editor_plugins\]$/,/^\[.*\]$/ s/^enabled=.*/enabled=[]/' "$project/project.godot"

for file in export_presets.cfg web.cfg; do
    if [[ -f "$project/$file" ]]; then
        mv "$project/$file" "$root/work/$file.original"
    fi
done

sed -i '/^config\/project_settings_override[[:space:]]*=/d' "$project/project.godot"
if grep -q '^\[application\]$' "$project/project.godot"; then
    sed -i '/^\[application\]$/a config/project_settings_override="res://web.cfg"' "$project/project.godot"
else
    printf '\n[application]\nconfig/project_settings_override="res://web.cfg"\n' >> "$project/project.godot"
fi

git -C "$project" init -q
cat >> "$project/.git/info/exclude" <<'EOF'
.godot/editor/
.godot/exported/
.godot/shader_cache/
.godot/global_script_class_cache.cfg
.godot/uid_cache.bin
EOF
shopt -s nullglob
for patch in "$root/patches/$defaults/"*.patch "$root/patches/"*.patch; do
    echo "applying $(basename "$patch")"
    git -C "$project" apply --check "$patch"
    git -C "$project" apply "$patch"
done
git -C "$project" add -A
git -C "$project" -c user.name=local -c user.email=local commit -qm 'apply web patches'
trap - EXIT
echo "recovered $project"
