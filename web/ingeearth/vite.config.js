// InGe Earth 4.0 — build de producción empaquetado dentro del APK de InGe+.
// Salida: android/assets/ingeearth (servida por WebViewAssetLoader en
// https://appassets.androidplatform.net/assets/ingeearth/index.html).
// Sin CDN: MapLibre GL JS, MapillaryJS y el control de Street View viajan en el APK.
import { defineConfig } from 'vite';
import { resolve } from 'node:path';

export default defineConfig({
  base: './',
  resolve: {
    alias: {
      // Fuente real de opengeos/maplibre-gl-streetview 0.8.0 (MIT), sin modificar.
      'maplibre-gl-streetview': resolve(__dirname, 'vendor/maplibre-gl-streetview-src/index.ts'),
    },
  },
  build: {
    outDir: resolve(__dirname, '../../android/assets/ingeearth'),
    emptyOutDir: true,
    target: 'es2020',
    sourcemap: false,
    assetsInlineLimit: 0,
    chunkSizeWarningLimit: 3000,
  },
});
