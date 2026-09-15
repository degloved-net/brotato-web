#!/usr/bin/env bash
set -e

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
paths_file="$repo_dir/.build-paths"

godot=""
if test -f "$paths_file"; then
  read -r godot < "$paths_file"
fi

read -r -e -i "$godot" -p "godot executable: " godot
printf '%s\n' "$godot" > "$paths_file"
project_dir="$repo_dir/work/project"

mkdir -p "$repo_dir/build"
for name in web web-threads web-lite; do
	output_dir="$repo_dir/build/$name"
	export_dir="$project_dir"
	if test "$name" = web-lite; then
		export_dir="$(mktemp -d)"
		rsync -a --exclude .git "$project_dir/" "$export_dir/"
		find "$export_dir" -type f \( -name '*.gd' -o -name '*.tscn' -o -name '*.tres' \) -exec sed -E -i 's#res://[^"]+\.(wav|mp3|ogg)#res://lite_silence.tres#g' {} +
		find "$export_dir" -type f -name '*.gd' -exec sed -i 's/AudioStreamSample/AudioStream/g' {} +
	fi
	rm -rf "$output_dir"
	mkdir -p "$output_dir"
	"$godot" --path "$export_dir" --export "$name" "$output_dir/index.html"
	find "$output_dir" -type f \( -name '*.html' -o -name '*.js' -o -name '*.wasm' -o -name '*.pck' \) -print0 |
		xargs -0 -r -n1 gzip -9 --keep
	if test "$name" = web-lite; then
		rm -rf "$export_dir"
	fi
done

echo "web export is in $repo_dir/build/web"
echo "threaded web export is in $repo_dir/build/web-threads"
echo "lite web export is in $repo_dir/build/web-lite"
