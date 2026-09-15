## brotato web port

you need [gdre tools](https://github.com/GDRETools/gdsdecomp/releases/tag/v2.6.4) and [godot 3.6.1](https://github.com/godotengine/godot/releases/tag/3.6.1-stable) with the html5 export templates installed.

`recover.sh` asks for gdre tools, `Brotato.pck`, and any dlc packs. it puts the recovered project in `work/project`

`build.sh` asks for godot. it makes `build/web` and `build/web-threads`.

`build/web` singlethreaded so it doesnt need headers

`build/web-lite` no music or sound effects

`build/web-threads` uses threads for better performance. it must be served with these headers on every response

```
cross-origin-opener-policy: same-origin
cross-origin-embedder-policy: require-corp
```

## mods

point the script to your mod zip

```bash
scripts/add-mod.sh
scripts/build.sh
```

`add-mod.sh` unpacks the mod into `work/project/mods-unpacked`, and after, it's bundled into the web builds. some mods might be unsupported by this version of brotato (this is the latest) and may require modification

## changes

run `scripts/recover.sh`, make changes in `work/project`, then run

```bash
scripts/add-patch.sh <patch name>
```

to add the patch
