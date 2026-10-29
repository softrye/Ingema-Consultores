# Rendiciones: paridad funcional Web → Android (P0, 2026-10-14)

Referencia: `E1PT04m0/ingeplus` (`apps/android`, `packages/test-vectors`,
`packages/contracts`). Sin UI nueva (Visual Zero): todo es accesible por los
comandos JSON de `RenditionFlutterBridge::submit` (QML: `renditionFlutterBridge`).

Commits: `43047fa` (dominio), `d0e42fc` (IA apagada), `03e91e6` (pruebas).

## Comandos nuevos del bridge

| Comando | Argumentos | Efecto |
|---|---|---|
| `saveFinancial` | `localId`, `kind` (`funding_set`/`exchange_set`), `values`, `expectedRowVersion` | Intención durable en el outbox (request_id + CAS) |
| `exchangeQuote` | `renditionId` | GET `<INGEPLUS_WEB_API_ORIGIN>/api/renditions/exchange-rate` con la sesión del usuario |
| `coreAnalyze` | — | Devuelve `AI_DISABLED` (IA de Rendiciones apagada) |

`present` y `ownerExport` usan ahora el permiso efectivo (`can_edit_content`) y
los suplementos congelados de la versión.

## RPC usadas por el cliente (deben existir en InGePlus-Dev)

`list_renditions_effective_v06`, `get_rendition_effective_v06`,
`present_my_rendition_v02`, `set_rendition_funding_v01`,
`set_rendition_exchange_rate_v02`, `get_rendition_funding_v01`,
`get_rendition_exchange_rate_v02`, más las ya existentes de borrador, gastos y
adjuntos. No se modificaron migraciones ni RLS. El despliegue remoto no está
verificado (PENDING_REMOTE_E2E).

## Cotización automática

Requiere el origen de la API Web autenticada: variable de entorno o definición
de compilación `INGEPLUS_WEB_API_ORIGIN` (https, o http solo en loopback). Sin
él, `exchangeQuote` responde `QUOTE_ORIGIN_NOT_CONFIGURED` y se conserva el tipo
guardado (BLOCKED hasta configurar). El tipo de cambio manual funciona.

## IA de Rendiciones

Apagada por defecto: `INGE_RENDITIONS_AI_ENABLED=0` (C++) y
`--dart-define=INGE_RENDITIONS_AI=false` (Dart). `RenditionAssistantPort`
(`src/cpp/renditionassistantport.h`) es la interfaz futura para InGe IA: no
está conectada, no hay Gemini ni claves.

## Pruebas de host (escritorio, no Android)

```
cmake -S tests/renditions -B <dir-corto> -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=C:/Qt/6.9.3/mingw_64
cmake --build <dir-corto>
ctest --test-dir <dir-corto> --output-on-failure
```

Usar un directorio de build de ruta corta (límite de rutas de Windows).
Dart: `cd flutter/inge_earth && flutter test`.

## Verificación en Android (pendiente, la realiza el usuario)

1. Qt Creator → kit Android arm64-v8a → CMake → Build → instalar.
2. `adb logcat -c`, iniciar la app y revisar errores QML, crash o ANR.
3. Sesión Dev: abrir Rendiciones, crear borrador, gasto, fondo PEN/USD, tipo
   manual, presentar, y comprobar `syncState` SYNCED y el mismo UUID remoto.
4. Probar sin red: la intención queda en el outbox y se reintenta con el mismo
   request_id al volver la conexión.
