import { defineConfig } from 'vite';
export default defineConfig({ base: './', publicDir: false, build: { target: 'es2022', outDir: '../../assets/inge-ai', emptyOutDir: true, sourcemap: false } });
