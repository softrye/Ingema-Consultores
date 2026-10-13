// resolve-calicata-elevation: cota del terreno (evidencias geoespaciales + validación
// Gemini estructurada). Lógica en handler.mjs (probada con Node), lectura del DEM en
// copernicus.mjs. Secretos: GEMINI_API_KEY (existente) y, opcional,
// GOOGLE_MAPS_ELEVATION_API_KEY (clave de servidor restringida a Elevation API).
import { createHandler } from './handler.mjs';

Deno.serve(createHandler({ env: (name: string) => Deno.env.get(name) }));
