# MAP V2 — configuración de Google Maps Platform

MAP V2 no contiene claves reales en QML, JavaScript ni archivos versionados.
Sin configuración, la subapp abre su superficie Cesium y muestra claramente
`Google Maps Platform no configurado`; no intenta ocultar el problema con otro
proveedor visual.

## APIs requeridas

- **Map Tiles API**: Photorealistic 3D Tiles y sesiones 2D Satellite,
  Roadmap y Terrain.
- **Places API**: evolución de búsqueda/Autocomplete.
- **Maps JavaScript API**: integración Places del workspace web.

La base actual usa Map Tiles API. La búsqueda local ya resuelve coordenadas,
proyectos y puntos persistentes; Places/Autocomplete queda preparada para la
siguiente integración y no se simula cuando la API no está disponible.

## Configuración externa

`MapWorkspaceController::configurationPath` indica el archivo privado que la
instalación debe provisionar fuera del repositorio. Su contenido es:

```json
{
  "googleMapsApiKey": "REEMPLAZAR_FUERA_DEL_REPOSITORIO",
  "androidPackage": "com.ingema.ingeplus",
  "androidCertSha1": "SHA1_SIN_DOS_PUNTOS",
  "language": "es-PE",
  "region": "PE",
  "cesiumBaseUrl": "https://cesium.com/downloads/cesiumjs/releases/1.143/Build/Cesium/"
}
```

Para ejecución de desarrollo también se aceptan estas variables de entorno:

- `INGE_GOOGLE_MAPS_API_KEY`
- `INGE_ANDROID_PACKAGE`
- `INGE_ANDROID_CERT_SHA1`
- `INGE_CESIUM_BASE_URL`

No se imprime ninguno de esos valores. No se debe crear un archivo real de
configuración dentro de este repositorio.

## Restricciones obligatorias

Usar una clave separada para el cliente Android y restringirla a:

1. paquete `com.ingema.ingeplus`;
2. SHA-1 del certificado Debug durante validación y del certificado Release
   únicamente cuando corresponda;
3. Map Tiles API, Places API y Maps JavaScript API según la clave utilizada.

Las llamadas directas del workspace adjuntan `X-Android-Package` y
`X-Android-Cert` cuando ambos valores están configurados. Antes de producción
se debe verificar en Google Cloud que identificadores Android incorrectos sean
rechazados. Si un endpoint no admite esa restricción, debe colocarse detrás de
un proxy autenticado; nunca se debe usar una clave irrestricta.

## Attribution

- Photorealistic 3D Tiles usa `showCreditsOnScreen` de Cesium.
- Google 2D muestra `Google Maps` y consulta el endpoint `viewport` para
  actualizar el copyright requerido para la región visible.
- La interfaz nunca debe cubrir ni eliminar los créditos de Google o Cesium.

No se permite precargar, extraer ni almacenar tiles de Google para uso offline.
