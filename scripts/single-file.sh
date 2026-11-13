#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail
export LC_ALL=C
shopt -s nullglob

root="$(cd "$(dirname "$0")/.." && pwd)"
chunk_size=786432
if (( $# )); then
    echo 'run without arguments' >&2
    exit 1
fi
for tool in gzip base64 sha256sum jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing tool: $tool" >&2
        exit 1
    fi
done

temporary=''
trap 'if [[ -n "$temporary" ]]; then rm -rf -- "$temporary"; fi' EXIT

fail() {
    echo "$*" >&2
    exit 1
}

require_once() {
    if ! awk -v needle="$2" '
        { line = $0; while ((pos = index(line, needle))) {
            count++; line = substr(line, pos + length(needle))
        } }
        END { exit count != 1 }
    ' "$1"; then
        fail "unsupported loader: $1"
    fi
}

presets=(web)
if [[ -d "$root/build/web-lite" ]]; then presets+=(web-lite); fi

for name in "${presets[@]}"; do
    folder="$root/build/$name"
    [[ -s "$folder/index.html" ]] || fail "missing build: $name; run scripts/build.sh"
    temporary="$(mktemp -d "$root/build/.single-file-$name.XXXXXX")"
    cp -- "$folder/index.html" "$temporary/shell.html"

    config="$(sed -nE 's/^[[:space:]]*const GODOT_CONFIG = (\{.*\});$/\1/p' "$temporary/shell.html")"
    if [[ -z "$config" ]] || ! jq -e 'type == "object" and
            ((.gdnativeLibs // []) | length == 0) and
            ((.gdextensionLibs // []) | length == 0) and
            ((.serviceWorker // "") == "")' <<< "$config" >/dev/null ||
            [[ -e "$folder/index.worker.js" || -e "$folder/index.side.wasm" ]] ||
            grep -Eq 'const GODOT_THREADS_ENABLED = true;' "$temporary/shell.html"; then
        fail "unsupported export: $name; turn off threads, extensions and pwa"
    fi

    manifest="$(sed -nE 's/^loadSplitPck\(engine, (\{.*\})\);$/\1/p' "$temporary/shell.html")"
    awk '
        /^function loadSplitPck\(engine, manifest\) \{$/ { dropping = 1; blocks++ }
        /^loadSplitPck\(engine, \{.*\}\);$/ {
            if (!dropping) exit 1
            dropping = 0; calls++; next
        }
        !dropping { print }
        END { if (dropping || blocks > 1 || blocks != calls) exit 1 }
    ' "$temporary/shell.html" > "$temporary/clean.html" || fail "bad pack loader: $name"

    require_once "$folder/index.js" 'fetch(file).then(function (response) {'
    require_once "$folder/index.js" 'function _godot_js_pwa_cb(p_update_cb){if("serviceWorker"in navigator){'
    sed \
        -e 's/fetch(file)\.then(function (response) {/loadEmbeddedFile(file).then(function (response) {/' \
        -e 's#function _godot_js_pwa_cb(p_update_cb){if("serviceWorker"in navigator){#function _godot_js_pwa_cb(p_update_cb){if(/^https?:$/.test(location.protocol)\&\&"serviceWorker"in navigator){#' \
        -e 's#</[sS][cC][rR][iI][pP][tT]#<\\/script#g' \
        "$folder/index.js" > "$temporary/engine.js"

    worklets=("$folder/"index.*.worklet.js)
    (( ${#worklets[@]} )) || fail "missing audio loader: $name"
    printf 'const embeddedWorklets = {\n' > "$temporary/worklets.js"
    for worklet in "${worklets[@]}"; do
        file="$(basename "$worklet")"
        [[ "$file" =~ ^index(\.[a-zA-Z0-9_-]+)+\.worklet\.js$ ]] || fail "bad audio filename: $file"
        suffix="${file#index}"
        needle='return `${loadPath}'"$suffix"'`;'
        require_once "$temporary/engine.js" "$needle"
        awk -v needle="$needle" -v replacement="return embeddedWorklets['$file'];" '
            {
                pos = index($0, needle)
                if (pos) $0 = substr($0, 1, pos - 1) replacement substr($0, pos + length(needle))
                print
            }
        ' "$temporary/engine.js" > "$temporary/patched.js"
        mv -- "$temporary/patched.js" "$temporary/engine.js"
        {
            printf "    '%s': 'data:text/javascript;base64," "$file"
            base64 -w 0 "$worklet"
            printf "',\n"
        } >> "$temporary/worklets.js"
    done
    printf '};\n' >> "$temporary/worklets.js"

    for image in "$folder/"index*.png; do
        file="$(basename "$image")"
        [[ "$file" =~ ^index(\.[a-zA-Z0-9_-]+)*\.png$ ]] || fail "bad image filename: $file"
        { printf 'data:image/png;base64,'; base64 -w 0 "$image"; printf '\n'; } > "$temporary/image"
        add_icon=0
        if [[ "$file" == index.png ]] && ! grep -Eqi "<link[^>]*rel=['\"](shortcut[[:space:]]+)?icon['\"]" "$temporary/clean.html"; then
            add_icon=1
        fi
        awk -v image_file="$temporary/image" -v name="$file" -v add_icon="$add_icon" '
            function replace(text, needle, addition, result, pos) {
                while ((pos = index(text, needle))) {
                    result = result substr(text, 1, pos - 1) addition
                    text = substr(text, pos + length(needle))
                }
                return result text
            }
            BEGIN { getline image < image_file }
            {
                $0 = replace($0, name, image)
                if (add_icon && index($0, "</head>")) {
                    $0 = replace($0, "</head>", "<link rel=\"icon\" href=\"" image "\">\n</head>")
                }
                print
            }
        ' "$temporary/clean.html" > "$temporary/images.html"
        mv -- "$temporary/images.html" "$temporary/clean.html"
    done

    awk -v before="$temporary/before.html" -v after="$temporary/after.html" '
        {
            if (match($0, /<script[^>]*src=["\047]index[.]js["\047][^>]*><\/script>/)) {
                found++
                print substr($0, 1, RSTART - 1) > before
                print substr($0, RSTART + RLENGTH) > after
            } else {
                print > (found ? after : before)
            }
        }
        END { if (found != 1) exit 1 }
    ' "$temporary/clean.html" || fail "need one engine script: $name"

    output="$temporary/index.html"
    cat -- "$temporary/before.html" > "$output"
    files='{}'
    for asset in index.wasm index.pck; do
        size="$(jq -er --arg asset "$asset" '.fileSizes[$asset] | select(type == "number" and . > 0 and . == floor and . <= 9007199254740991)' <<< "$config")" ||
            fail "bad file size: $folder/$asset"
        paths=()
        sizes=()
        hashes=()
        if [[ -f "$folder/$asset" ]]; then
            paths+=("$folder/$asset")
            sizes+=("$size")
            hashes+=('')
        elif [[ "$asset" == index.pck && -n "$manifest" ]]; then
            jq -e --argjson size "$size" '
                .size == $size and (.parts | type == "array" and length > 0) and
                all(.parts[]; (.file | type == "string") and
                    (.size | type == "number" and . > 0 and . <= 20000000 and . == floor) and
                    (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))) and
                ([.parts[].size] | add == $size)
            ' <<< "$manifest" >/dev/null || fail "bad pack parts: $name"
            jq -r '.parts[] | [.file, .size, .sha256] | @tsv' <<< "$manifest" > "$temporary/parts"
            part_index=0
            while IFS=$'\t' read -r file part_size hash; do
                printf -v expected 'index.pck.part-%04d' "$part_index"
                [[ "$file" == "$expected" ]] || fail "bad pack filename: $file"
                paths+=("$folder/$file")
                sizes+=("$part_size")
                hashes+=("$hash")
                part_index=$((part_index + 1))
            done < "$temporary/parts"
        else
            fail "missing file: $folder/$asset"
        fi

        for i in "${!paths[@]}"; do
            [[ -f "${paths[i]}" && "$(stat -c %s "${paths[i]}")" == "${sizes[i]}" ]] ||
                fail "missing file or wrong size: ${paths[i]}"
            if [[ -n "${hashes[i]}" ]]; then
                hash="$(sha256sum -- "${paths[i]}")"
                [[ "${hash%% *}" == "${hashes[i]}" ]] || fail "bad checksum: ${paths[i]}"
            fi
        done

        cat -- "${paths[@]}" | gzip -n -9 > "$temporary/asset.gz"
        compressed_size="$(stat -c %s "$temporary/asset.gz")"
        chunks=$(((compressed_size + chunk_size - 1) / chunk_size))
        for ((i = 0; i < chunks; i++)); do
            printf '<script type="application/octet-stream" id="embedded-%s-%s">' "$asset" "$i" >> "$output"
            dd if="$temporary/asset.gz" bs="$chunk_size" skip="$i" count=1 status=none | base64 -w 0 >> "$output"
            printf '</script>\n' >> "$output"
        done
        type='application/octet-stream'
        if [[ "$asset" == index.wasm ]]; then type='application/wasm'; fi
        files="$(jq -c --arg asset "$asset" --arg type "$type" --argjson size "$size" --argjson chunks "$chunks" \
            '.[$asset] = {size: $size, chunks: $chunks, type: $type}' <<< "$files")"
    done

    {
        printf '<script>const embeddedFiles = %s;</script>\n<script>\n' "$files"
        cat -- "$root/scripts/single-file-loader.js" "$temporary/worklets.js" "$temporary/engine.js"
        printf '\n</script>\n'
        cat -- "$temporary/after.html"
    } >> "$output"
    chmod 644 "$output"
    mv -- "$output" "$root/build/$name.html"
    echo "made $root/build/$name.html"
    rm -rf -- "$temporary"
    temporary=''
done
