function loadSplitPck(engine, manifest) {
    const preload = engine.preloadFile;

    engine.preloadFile = async function (file, path) {
        if (file !== 'index.pck') {
            return preload.call(this, file, path);
        }

        if (!Number.isSafeInteger(manifest.size) || manifest.size <= 0 ||
            !Array.isArray(manifest.parts) || manifest.parts.length === 0) {
            throw new Error('invalid pck manifest');
        }

        const pack = new Uint8Array(manifest.size);
        const progress = document.getElementById('status-progress');
        let offset = 0;

        for (const part of manifest.parts) {
            if (!/^index\.pck\.part-\d{4}$/.test(part.file) ||
                !Number.isSafeInteger(part.size) || part.size <= 0 ||
                part.size > 20000000 || offset + part.size > pack.length) {
                throw new Error('invalid pck part');
            }

            const download = await fetch(part.file);
            if (!download.ok) {
                throw new Error(`${part.file}: http ${download.status}`);
            }
            const bytes = new Uint8Array(await download.arrayBuffer());
            if (bytes.length !== part.size) {
                throw new Error(`${part.file}: incomplete download`);
            }

            if (globalThis.crypto?.subtle) {
                const digest = await crypto.subtle.digest('SHA-256', bytes);
                const hash = Array.from(new Uint8Array(digest), byte =>
                    byte.toString(16).padStart(2, '0')).join('');
                if (hash !== part.sha256) {
                    throw new Error(`${part.file}: checksum mismatch`);
                }
            }

            pack.set(bytes, offset);
            offset += bytes.length;
            if (progress) {
                progress.max = manifest.size;
                progress.value = offset;
            }
        }

        if (offset !== pack.length) {
            throw new Error('incomplete pck manifest');
        }
        return preload.call(this, pack.buffer, path || file);
    };
}
