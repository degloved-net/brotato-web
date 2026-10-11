#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if (( $# )); then
    echo 'run without arguments to split all four builds' >&2
    exit 1
fi

if [[ ! -s "$root/scripts/pck-loader.js" || ! -r "$root/scripts/pck-loader.js" ]]; then
    echo 'missing scripts/pck-loader.js' >&2
    exit 1
fi

for name in web web-threads web-lite web-lite-threads; do
    folder="$root/build/$name"
    if [[ ! -s "$folder/index.html" ]]; then
        echo "missing build: $name; run scripts/build.sh first" >&2
        exit 1
    fi
    if [[ ! -s "$folder/index.pck" ]]; then
        if [[ -s "$folder/index.pck.part-0000" ]] && grep -q 'loadSplitPck(engine, {' "$folder/index.html"; then
            continue
        fi
        echo "missing pack: $name; run scripts/build.sh first" >&2
        exit 1
    fi
    if ! grep -Eq "src=['\"]index\.js['\"]" "$folder/index.html" ||
       ! grep -Eq '(const|var|let) engine = new Engine\(' "$folder/index.html"; then
        echo "use the default godot html page: $name" >&2
        exit 1
    fi
done

html=''
trap 'if [[ -n "$html" ]]; then rm -f -- "$html"; fi' EXIT

for name in web web-threads web-lite web-lite-threads; do
    folder="$root/build/$name"
    if [[ ! -s "$folder/index.pck" ]]; then
        echo "already split: $name"
        continue
    fi

    rm -f -- "$folder/"index.pck.part-*
    split -b 20000000 -d -a 4 "$folder/index.pck" "$folder/index.pck.part-"
    manifest="$(
        printf '{"size":%s,"parts":[' "$(stat -c %s "$folder/index.pck")"
        separator=''
        for part in "$folder/"index.pck.part-*; do
            hash="$(sha256sum "$part")"
            printf '%s{"file":"%s","size":%s,"sha256":"%s"}' \
                "$separator" "$(basename "$part")" "$(stat -c %s "$part")" "${hash%% *}"
            separator=','
        done
        printf ']}'
    )"

    html="$(mktemp "$folder/index.html.XXXXXX")"
    awk -v loader="$root/scripts/pck-loader.js" -v manifest="$manifest" '
        { print }
        /engine = new Engine\(/ {
            while ((getline line < loader) > 0) print line
            close(loader)
            print "loadSplitPck(engine, " manifest ");"
        }
    ' "$folder/index.html" > "$html"
    chmod --reference="$folder/index.html" "$html"
    mv -- "$html" "$folder/index.html"
    html=''
    rm -- "$folder/index.pck"
    echo "split pack: $name"
done
