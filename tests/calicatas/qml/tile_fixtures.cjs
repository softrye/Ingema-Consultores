// Pirámide XYZ de teselas de PRUEBA (z3..z17) alrededor de las calicatas del
// arnés (Lima, UTM 18S). Cada tesela es una imagen distinta: color por nivel,
// curvas sinusoidales tipo relieve, cuadrícula y bandas por x/y, para que una
// tesela ausente o fuera de lugar se note al medir píxeles. Las teselas fuera
// de la pirámide NO existen a propósito (simulan fallos del proveedor).
// Nunca contienen el color de fondo del mapa (#E9EEF2).
'use strict'
const fs = require('fs')
const path = require('path')
const zlib = require('zlib')

const CRC = (() => {
  const t = new Uint32Array(256)
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0 }
  return t
})()
function crc32(buf) { let c = 0xffffffff; for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0 }
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length)
  const td = Buffer.concat([Buffer.from(type), data])
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td))
  return Buffer.concat([len, td, crc])
}
function png(size, pixel) {
  const raw = Buffer.alloc((size * 3 + 1) * size)
  for (let y = 0; y < size; y++) {
    raw[y * (size * 3 + 1)] = 0
    for (let x = 0; x < size; x++) {
      const [r, g, b] = pixel(x, y)
      const o = y * (size * 3 + 1) + 1 + x * 3
      raw[o] = r; raw[o + 1] = g; raw[o + 2] = b
    }
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4)
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
                        chunk('IDAT', zlib.deflateSync(raw, { level: 6 })), chunk('IEND', Buffer.alloc(0))])
}
function tileOf(lat, lon, z) {
  const n = 2 ** z, r = lat * Math.PI / 180
  return { x: Math.floor((lon + 180) / 360 * n), y: Math.floor((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * n) }
}
// Escribe la pirámide en dir/{z}/{x}/{y}.png; devuelve el número de teselas.
function writePyramid(dir, opts) {
  const o = Object.assign({ lat: -12.03, lon: -76.98, minZ: 3, maxZ: 17, rx: 4, ry: 5 }, opts || {})
  let count = 0
  for (let z = o.minZ; z <= o.maxZ; z++) {
    const c = tileOf(o.lat, o.lon, z), n = 2 ** z
    const base = [[196, 214, 170], [214, 196, 160], [170, 200, 214], [204, 186, 214], [186, 214, 196]][z % 5]
    for (let x = c.x - o.rx; x <= c.x + o.rx; x++) {
      for (let y = Math.max(0, c.y - o.ry); y <= Math.min(n - 1, c.y + o.ry); y++) {
        const d = path.join(dir, String(z), String(x))
        fs.mkdirSync(d, { recursive: true })
        fs.writeFileSync(path.join(d, y + '.png'), png(256, (px, py) => {
          const gx = x * 256 + px, gy = y * 256 + py
          const relief = Math.sin(gx / 37 + Math.cos(gy / 53) * 2.1) + Math.cos(gy / 29 - gx / 71)
          const contour = Math.abs(relief * 3 % 1) < 0.07
          const grid = px === 0 || py === 0
          const k = 0.85 + 0.15 * Math.sin((x * 13 + y * 7) % 17)
          if (grid) return [90, 96, 104]
          if (contour) return [120, 92, 60]
          return [Math.round(base[0] * k), Math.round(base[1] * k), Math.round(base[2] * k)]
        }))
        count++
      }
    }
  }
  return count
}
// Decodifica un PNG de 8 bits (RGB o RGBA, sin entrelazado) como el que guarda
// grabToImage, para medir la fracción de píxeles con el fondo vacío del mapa.
function readPng(file) {
  const buf = fs.readFileSync(file)
  let p = 8, w = 0, h = 0, type = 0, depth = 0
  const idat = []
  while (p < buf.length) {
    const len = buf.readUInt32BE(p), t = buf.toString('ascii', p + 4, p + 8), d = buf.subarray(p + 8, p + 8 + len)
    if (t === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); depth = d[8]; type = d[9]; if (d[12]) throw new Error('PNG entrelazado') }
    else if (t === 'IDAT') idat.push(d)
    else if (t === 'IEND') break
    p += 12 + len
  }
  if (depth !== 8 || (type !== 2 && type !== 6)) throw new Error('PNG no soportado tipo=' + type + ' bits=' + depth)
  const bpp = type === 6 ? 4 : 3, stride = w * bpp
  const raw = zlib.inflateSync(Buffer.concat(idat)), out = Buffer.alloc(stride * h)
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1))
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? out[y * stride + i - bpp] : 0, b = y ? out[(y - 1) * stride + i] : 0
      const c = i >= bpp && y ? out[(y - 1) * stride + i - bpp] : 0
      let v = src[i]
      if (f === 1) v += a
      else if (f === 2) v += b
      else if (f === 3) v += (a + b) >> 1
      else if (f === 4) { const pp = a + b - c, pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c }
      out[y * stride + i] = v & 255
    }
  }
  return { w, h, bpp, data: out }
}
// Fracción de la zona cartográfica con el fondo exacto. Se excluyen las franjas
// con controles de vidrio superpuestos (px): arriba, abajo y a la derecha.
function emptyFraction(file, bg, insetTop, insetBottom, insetRight) {
  const img = readPng(file), [r, g, b] = bg || [0xE9, 0xEE, 0xF2]
  let n = 0, e = 0
  for (let y = (insetTop || 0) + 2; y < img.h - (insetBottom || 0); y += 6)
    for (let x = 2; x < img.w - (insetRight || 0); x += 6) {
      const i = (y * img.w + x) * img.bpp
      n++
      if (Math.abs(img.data[i] - r) < 4 && Math.abs(img.data[i + 1] - g) < 4 && Math.abs(img.data[i + 2] - b) < 4) e++
    }
  return n ? e / n : 1
}
module.exports = { writePyramid, tileOf, readPng, emptyFraction }
if (require.main === module) {
  const out = process.argv[2]
  if (!out) { console.error('uso: node tile_fixtures.cjs <dir>'); process.exit(2) }
  console.log('tiles=' + writePyramid(out))
}
