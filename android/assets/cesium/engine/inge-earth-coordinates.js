(() => {
  'use strict';

  const WGS84_A = 6378137.0;
  const WGS84_ECC_SQUARED = 0.00669437999014;
  const K0 = 0.9996;

  const zoneFor = (longitude) => Math.min(60, Math.max(1, Math.floor((longitude + 180) / 6) + 1));
  const hemisphereFor = (latitude) => latitude >= 0 ? 'N' : 'S';
  const definition = (zone, hemisphere) => `+proj=utm +zone=${zone}${hemisphere === 'S' ? ' +south' : ''} +datum=WGS84 +units=m +no_defs`;

  const toUtmFallback = (latitude, longitude) => {
    const zone = zoneFor(longitude);
    const latitudeRadians = latitude * Math.PI / 180;
    const longitudeRadians = longitude * Math.PI / 180;
    const centralLongitude = ((zone - 1) * 6 - 180 + 3) * Math.PI / 180;
    const eccPrimeSquared = WGS84_ECC_SQUARED / (1 - WGS84_ECC_SQUARED);
    const n = WGS84_A / Math.sqrt(1 - WGS84_ECC_SQUARED * Math.sin(latitudeRadians) ** 2);
    const t = Math.tan(latitudeRadians) ** 2;
    const c = eccPrimeSquared * Math.cos(latitudeRadians) ** 2;
    const a = Math.cos(latitudeRadians) * (longitudeRadians - centralLongitude);
    const m = WGS84_A * ((1 - WGS84_ECC_SQUARED / 4 - 3 * WGS84_ECC_SQUARED ** 2 / 64 - 5 * WGS84_ECC_SQUARED ** 3 / 256) * latitudeRadians
      - (3 * WGS84_ECC_SQUARED / 8 + 3 * WGS84_ECC_SQUARED ** 2 / 32 + 45 * WGS84_ECC_SQUARED ** 3 / 1024) * Math.sin(2 * latitudeRadians)
      + (15 * WGS84_ECC_SQUARED ** 2 / 256 + 45 * WGS84_ECC_SQUARED ** 3 / 1024) * Math.sin(4 * latitudeRadians)
      - (35 * WGS84_ECC_SQUARED ** 3 / 3072) * Math.sin(6 * latitudeRadians));
    const easting = K0 * n * (a + (1 - t + c) * a ** 3 / 6
      + (5 - 18 * t + t ** 2 + 72 * c - 58 * eccPrimeSquared) * a ** 5 / 120) + 500000;
    let northing = K0 * (m + n * Math.tan(latitudeRadians) * (a ** 2 / 2
      + (5 - t + 9 * c + 4 * c ** 2) * a ** 4 / 24
      + (61 - 58 * t + t ** 2 + 600 * c - 330 * eccPrimeSquared) * a ** 6 / 720));
    if (latitude < 0)
      northing += 10000000;
    return { zone, hemisphere: hemisphereFor(latitude), easting, northing };
  };

  const toUtm = (latitude, longitude) => {
    const zone = zoneFor(longitude);
    const hemisphere = hemisphereFor(latitude);
    if (typeof window.proj4 === 'function') {
      const result = window.proj4('EPSG:4326', definition(zone, hemisphere), [longitude, latitude]);
      return { zone, hemisphere, easting: result[0], northing: result[1] };
    }
    return toUtmFallback(latitude, longitude);
  };

  const fromUtmFallback = (zone, hemisphere, easting, northing) => {
    const x = easting - 500000;
    let y = northing;
    if (hemisphere === 'S')
      y -= 10000000;
    const eccPrimeSquared = WGS84_ECC_SQUARED / (1 - WGS84_ECC_SQUARED);
    const m = y / K0;
    const mu = m / (WGS84_A * (1 - WGS84_ECC_SQUARED / 4 - 3 * WGS84_ECC_SQUARED ** 2 / 64 - 5 * WGS84_ECC_SQUARED ** 3 / 256));
    const e1 = (1 - Math.sqrt(1 - WGS84_ECC_SQUARED)) / (1 + Math.sqrt(1 - WGS84_ECC_SQUARED));
    const phi1 = mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * Math.sin(2 * mu)
      + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * Math.sin(4 * mu)
      + (151 * e1 ** 3 / 96) * Math.sin(6 * mu) + (1097 * e1 ** 4 / 512) * Math.sin(8 * mu);
    const n1 = WGS84_A / Math.sqrt(1 - WGS84_ECC_SQUARED * Math.sin(phi1) ** 2);
    const t1 = Math.tan(phi1) ** 2;
    const c1 = eccPrimeSquared * Math.cos(phi1) ** 2;
    const r1 = WGS84_A * (1 - WGS84_ECC_SQUARED) / (1 - WGS84_ECC_SQUARED * Math.sin(phi1) ** 2) ** 1.5;
    const d = x / (n1 * K0);
    const latitude = phi1 - (n1 * Math.tan(phi1) / r1) * (d ** 2 / 2
      - (5 + 3 * t1 + 10 * c1 - 4 * c1 ** 2 - 9 * eccPrimeSquared) * d ** 4 / 24
      + (61 + 90 * t1 + 298 * c1 + 45 * t1 ** 2 - 252 * eccPrimeSquared - 3 * c1 ** 2) * d ** 6 / 720);
    const centralLongitude = ((zone - 1) * 6 - 180 + 3) * Math.PI / 180;
    const longitude = centralLongitude + (d - (1 + 2 * t1 + c1) * d ** 3 / 6
      + (5 - 2 * c1 + 28 * t1 - 3 * c1 ** 2 + 8 * eccPrimeSquared + 24 * t1 ** 2) * d ** 5 / 120) / Math.cos(phi1);
    return { latitude: latitude * 180 / Math.PI, longitude: longitude * 180 / Math.PI, height: 0 };
  };

  const fromUtm = (zone, hemisphere, easting, northing) => {
    if (typeof window.proj4 === 'function') {
      const result = window.proj4(definition(zone, hemisphere), 'EPSG:4326', [easting, northing]);
      return { latitude: result[1], longitude: result[0], height: 0 };
    }
    return fromUtmFallback(zone, hemisphere, easting, northing);
  };

  const parse = (text) => {
    const value = String(text || '').trim().replace(/[°]/g, '');
    let match = value.match(/^UTM\s+(\d{1,2})\s*([NS])\s+([\d.]+)\s+([\d.]+)$/i);
    if (match) {
      const zone = Number(match[1]);
      const hemisphere = match[2].toUpperCase();
      const easting = Number(match[3]);
      const northing = Number(match[4]);
      if (zone >= 1 && zone <= 60 && easting >= 100000 && easting <= 900000 && northing >= 0 && northing <= 10000000)
        return fromUtm(zone, hemisphere, easting, northing);
      return null;
    }
    const parts = value.replace(/\s*,\s*/g, ' ').split(/\s+/).filter(Boolean).map(Number);
    if (parts.length >= 2 && parts.length <= 3 && parts.every(Number.isFinite)
        && parts[0] >= -90 && parts[0] <= 90 && parts[1] >= -180 && parts[1] <= 180)
      return { latitude: parts[0], longitude: parts[1], height: parts[2] || 0 };
    return null;
  };

  const formatUtm = (coordinate) => {
    const result = toUtm(coordinate.latitude, coordinate.longitude);
    return `UTM ${result.zone}${result.hemisphere} ${Math.round(result.easting)} E ${Math.round(result.northing)} N`;
  };

  window.InGeEarthCoordinates = { toUtm, fromUtm, parse, formatUtm };
})();
