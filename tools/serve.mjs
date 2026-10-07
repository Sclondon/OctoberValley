// Serves the web build (build/) on http://127.0.0.1:<port>/ for trying it in a browser.
//
//     node tools/serve.mjs [port]

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(fileURLToPath(new URL('.', import.meta.url)), '..', 'build');
const port = Number(process.argv[2] ?? 8791);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png', '.pck': 'application/octet-stream' };

createServer(async (request, response) => {
    const path = normalize(decodeURIComponent(new URL(request.url, 'http://x').pathname)).replace(/^[\\/]+/, '') || 'index.html';
    try {
        const data = await readFile(join(root, path));
        response.writeHead(200, { 'Content-Type': types[extname(path)] ?? 'application/octet-stream' });
        response.end(data);
    } catch {
        response.writeHead(404);
        response.end('not found');
    }
}).listen(port, '127.0.0.1', () => console.log(`October Valley web build on http://127.0.0.1:${port}/`));
