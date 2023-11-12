import { resolve, join } from 'node:path';
import { existsSync } from 'node:fs';
import { readFile, writeFile, cp, mkdir, rm } from 'node:fs/promises';
import { defineConfig } from 'vite';
import mkcert from 'vite-plugin-mkcert';

import pkg from './package.json';
const PLUGIN_NAME = pkg.name;

const getIndexCode = (port: number) => (
  `await import('https://localhost:${port}/@vite/client');
  export * from 'https://localhost:${port}/src/index.ts';`
);

let port: number;
const outDir = resolve(__dirname, 'dist');
const pluginsDir = resolve(__dirname, pkg.config.loaderPath, 'plugins', PLUGIN_NAME);

async function emptyDir(path: string) {
  if (existsSync(path)) {
    await rm(path, { recursive: true });
  }
  await mkdir(path, { recursive: true });
}

export default defineConfig({
  build: {
    minify: 'esbuild',
    rollupOptions: {
      output: {
        format: 'esm',
        entryFileNames: 'index.js',
        manualChunks: undefined,
      },
	  treeshake: true,
    },
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: PLUGIN_NAME,
      fileName: 'index',
	  formats: [ 'es' ],
    },
  },
  server: {
    https: true,
    // port: 3000
  },
  publicDir: false,
  plugins: [
    mkcert(),
    {
      name: 'll-serve',
      apply: 'serve',
      enforce: 'post',
      configureServer(server) {
        server.httpServer!.once('listening', async () => {
          // @ts-ignore
          port = server.httpServer.address()['port'];
          await emptyDir(pluginsDir);
          await writeFile(join(pluginsDir, 'index.js'), getIndexCode(port));
        });
      },
      transform: (code, id) => {
        if (/\.(ts|tsx|js|jsx)$/i.test(id)) return;
        return code.replace(/\/src\//g, `https://localhost:${port}/src/`)
      },
    },
    {
      name: 'll-build',
      apply: 'build',
      enforce: 'post',
      async closeBundle() {
        const indexJs = join(outDir, 'index.js');
        const jsCode = (await readFile(indexJs, 'utf-8'))
        await writeFile(indexJs, jsCode);

        // Copy output
        await emptyDir(pluginsDir);
        await cp(outDir, pluginsDir, {
          recursive: true,
        });
      }
    }
  ]
});
