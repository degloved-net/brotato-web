#!/usr/bin/env bash

ask_path() {
    local name="$1" label="$2" fallback="${3:-}" answer
    local saved="$root/work/paths/$name"

    if [[ -f "$saved" ]]; then
        IFS= read -r fallback < "$saved"
    fi
    if [[ -t 0 ]]; then
        read -r -e -i "$fallback" -p "$label: " answer
    else
        printf '%s [%s]: ' "$label" "$fallback" >&2
        IFS= read -r answer
    fi
    answer="${answer:-$fallback}"
    if [[ "$answer" == '-' ]]; then answer=''; fi
    if [[ "$answer" == '~/'* ]]; then answer="$HOME/${answer:2}"; fi
    if [[ -n "$answer" && -e "$answer" ]]; then
        answer="$(realpath "$answer")"
    fi

    printf -v "$name" '%s' "$answer"
    mkdir -p "$root/work/paths"
    (umask 077; printf '%s\n' "$answer" > "$saved")
}
