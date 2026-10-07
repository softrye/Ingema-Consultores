// Lectura puntual del Copernicus DEM (ESA) publicado como Cloud-Optimized GeoTIFF
// en AWS Open Data (sin API de terceros, sin clave, uso comercial permitido con
// atribución). Se descarga SOLO el tile interno que contiene el punto (rango HTTP),
// se descomprime (DEFLATE) y se deshace el predictor de coma flotante (3).
//
// Alturas ortométricas EGM2008 (m.s.n.m.) de un modelo de SUPERFICIE (DSM):
// incluye vegetación/edificios. Interpolación bilineal en el punto pedido.

export const COPERNICUS_ATTRIBUTION =
  '© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved';

export const DATASETS = {
  glo30: { id: 'copernicus_glo30', label: 'Copernicus DEM GLO-30', resolution_m: 30, accuracy_m: 4,
           url: (n) => `https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/${n(10)}/${n(10)}.tif` },
  glo90: { id: 'copernicus_glo90', label: 'Copernicus DEM GLO-90', resolution_m: 90, accuracy_m: 4,
           url: (n) => `https://copernicus-dem-90m.s3.eu-central-1.amazonaws.com/${n(30)}/${n(30)}.tif` },
};

// Nombre del tile 1°×1° por su esquina SUR-OESTE (convención Copernicus).
export function tileName(lat, lon) {
  const south = Math.floor(lat), west = Math.floor(lon);
  const ns = south < 0 ? `S${String(-south).padStart(2, '0')}` : `N${String(south).padStart(2, '0')}`;
  const ew = west < 0 ? `W${String(-west).padStart(3, '0')}` : `E${String(west).padStart(3, '0')}`;
  return (arcsec) => `Copernicus_DSM_COG_${arcsec}_${ns}_00_${ew}_00_DEM`;
}

const TYPE_SIZE = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8, 16: 8 };

// IFD del primer nivel (resolución completa). `bytes` = cabecera descargada.
export function parseIfd(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const le = view.getUint16(0) === 0x4949;
  if (view.getUint16(2, le) !== 42) throw new Error('TIFF_UNSUPPORTED');
  const offset = view.getUint32(4, le);
  const count = view.getUint16(offset, le);
  const tags = {};
  for (let i = 0; i < count; i++) {
    const at = offset + 2 + i * 12;
    const tag = view.getUint16(at, le), type = view.getUint16(at + 2, le), n = view.getUint32(at + 4, le);
    const size = (TYPE_SIZE[type] || 1) * n;
    const base = size <= 4 ? at + 8 : view.getUint32(at + 8, le);
    if (base + size > bytes.byteLength) throw new Error('TIFF_HEADER_TRUNCATED');
    const values = [];
    for (let k = 0; k < n; k++) {
      const p = base + k * (TYPE_SIZE[type] || 1);
      values.push(type === 3 ? view.getUint16(p, le) : type === 4 ? view.getUint32(p, le)
        : type === 12 ? view.getFloat64(p, le) : type === 16 ? Number(view.getBigUint64(p, le)) : view.getUint8(p));
    }
    tags[tag] = values;
  }
  const geoKeys = tags[34735] || [];
  let rasterType = 1;   // 1 = PixelIsArea, 2 = PixelIsPoint (GTRasterTypeGeoKey 1025)
  for (let k = 4; k + 3 < geoKeys.length; k += 4) if (geoKeys[k] === 1025) rasterType = geoKeys[k + 3];
  return {
    littleEndian: le, width: tags[256][0], height: tags[257][0], bits: tags[258][0],
    compression: tags[259][0], predictor: (tags[317] || [1])[0], sampleFormat: (tags[339] || [1])[0],
    tileWidth: tags[322][0], tileHeight: tags[323][0], tileOffsets: tags[324], tileByteCounts: tags[325],
    scaleX: tags[33550][0], scaleY: tags[33550][1], originX: tags[33922][3], originY: tags[33922][4], rasterType,
  };
}

async function inflate(compressed) {
  const stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream('deflate'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

// Predictor 3 (coma flotante): diferencias horizontales por byte y planos de bytes.
export function decodeFloatTile(raw, tileWidth, tileHeight) {
  const rowBytes = tileWidth * 4;
  const out = new Float32Array(tileWidth * tileHeight);
  const be = new DataView(new ArrayBuffer(4));
  for (let y = 0; y < tileHeight; y++) {
    const row = raw.subarray(y * rowBytes, (y + 1) * rowBytes);
    for (let i = 1; i < rowBytes; i++) row[i] = (row[i] + row[i - 1]) & 0xff;
    for (let x = 0; x < tileWidth; x++) {
      be.setUint8(0, row[x]); be.setUint8(1, row[x + tileWidth]);
      be.setUint8(2, row[x + 2 * tileWidth]); be.setUint8(3, row[x + 3 * tileWidth]);
      out[y * tileWidth + x] = be.getFloat32(0, false);
    }
  }
  return out;
}

// Caché por instancia: varias calicatas del mismo proyecto caen en el mismo tile.
const TILE_CACHE_LIMIT = 3;
const tileCache = new Map();   // `${url}#${index}` -> Float32Array | null
const headerCache = new Map(); // url -> ifd | null
function remember(map, key, value, limit) {
  map.delete(key);
  map.set(key, value);
  while (map.size > limit) map.delete(map.keys().next().value);
}

// Altura en (lat, lon) con interpolación bilineal; null si no hay dato.
export async function sampleCopernicus(dataset, lat, lon, fetcher = fetch, timeoutMs = 12000) {
  const url = dataset.url(tileName(lat, lon));
  const get = async (start, end) => {
    const response = await fetcher(url, { headers: { Range: `bytes=${start}-${end}` }, signal: AbortSignal.timeout(timeoutMs) });
    if (response.status === 404 || response.status === 403) return null;   // océano / sin tile
    if (response.status !== 206 && response.status !== 200) throw new Error(`DEM_HTTP_${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
  };
  let ifd = headerCache.get(url);
  if (ifd === undefined) {
    const head = await get(0, 65535);
    ifd = head ? parseIfd(head) : null;
    remember(headerCache, url, ifd, 16);
  }
  if (!ifd) return null;
  if (ifd.bits !== 32 || ifd.sampleFormat !== 3 || ifd.compression !== 8 || ifd.predictor !== 3)
    throw new Error('DEM_FORMAT_UNSUPPORTED');
  const shift = ifd.rasterType === 2 ? 0 : 0.5;   // centro de píxel
  const px = (lon - ifd.originX) / ifd.scaleX - shift;
  const py = (ifd.originY - lat) / ifd.scaleY - shift;
  const x0 = Math.max(0, Math.min(ifd.width - 1, Math.floor(px))), y0 = Math.max(0, Math.min(ifd.height - 1, Math.floor(py)));
  const x1 = Math.min(ifd.width - 1, x0 + 1), y1 = Math.min(ifd.height - 1, y0 + 1);
  const across = Math.ceil(ifd.width / ifd.tileWidth);
  const value = async (x, y) => {
    const index = Math.floor(y / ifd.tileHeight) * across + Math.floor(x / ifd.tileWidth);
    const key = `${url}#${index}`;
    if (!tileCache.has(key)) {
      const start = ifd.tileOffsets[index], length = ifd.tileByteCounts[index];
      const compressed = await get(start, start + length - 1);
      remember(tileCache, key, compressed ? decodeFloatTile(await inflate(compressed), ifd.tileWidth, ifd.tileHeight) : null,
               TILE_CACHE_LIMIT);
    }
    const tile = tileCache.get(key);
    if (!tile) return NaN;
    return tile[(y % ifd.tileHeight) * ifd.tileWidth + (x % ifd.tileWidth)];
  };
  const fx = Math.min(1, Math.max(0, px - x0)), fy = Math.min(1, Math.max(0, py - y0));
  const [a, b, c, d] = [await value(x0, y0), await value(x1, y0), await value(x0, y1), await value(x1, y1)];
  const h = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  return Number.isFinite(h) && h > -500 && h < 9000 ? Math.round(h * 10) / 10 : null;
}
