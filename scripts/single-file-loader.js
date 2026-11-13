function decodeEmbeddedBytes(encoded) {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}

function loadEmbeddedFile(file) {
    const asset = embeddedFiles[file];
    if (!asset) {
        return Promise.reject(new Error(`missing file: ${file}`));
    }
    if (typeof DecompressionStream === 'undefined') {
        return Promise.reject(new Error('update your browser to open this file'));
    }

    let chunk = 0;
    const compressed = new ReadableStream({
        pull(controller) {
            if (chunk === asset.chunks) {
                controller.close();
                return;
            }
            const node = document.getElementById(`embedded-${file}-${chunk++}`);
            if (!node) {
                controller.error(new Error(`missing data: ${file}`));
                return;
            }
            const bytes = decodeEmbeddedBytes(node.textContent);
            node.remove();
            controller.enqueue(bytes);
        },
    });
    return Promise.resolve(new Response(compressed.pipeThrough(new DecompressionStream('gzip')), {
        headers: { 'content-type': asset.type, 'content-length': String(asset.size) },
    }));
}
