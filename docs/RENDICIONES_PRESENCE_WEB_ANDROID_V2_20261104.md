# Rendiciones Android — presencia y foco Realtime (04-11-2026)

## Alcance y estado
- Integración sobre las clases y controles **ya existentes**, sin crear otro cliente Supabase.
- Código editado en Android; **sin compilar, instalar ni probar en dispositivo**, por solicitud explícita.
- Worktree inicial con numerosas modificaciones ajenas: se editaron sólo fragmentos puntuales; no se hizo commit.
- No se tocaron `qml/Mobile/pages/*`, el Dock, el esquema ni las credenciales.

## Web revisada: límite de paridad
Referencia indicada: `C:\Users\PC-02\Downloads\ingeplus-main (1).zip`.
Extraídos a carpeta temporal sólo archivos de búsqueda de presencia/realtime; fuente principal:
`ingeplus-main/src/components/renditions/RenditionLivePresence.tsx`.
El código entregado usa:
- Canal privado: `rendition:<renditionId>`.
- `channel.track({ userId, name, routeIds: [renditionId] })`.
- `broadcast` evento `invalidate` (sin datos de usuario en el aviso).
- Render de avatar **con iniciales**, no foto; **no** envía `field`, `avatarUrl` ni `color`.
**El ZIP no contiene el contrato v2 de foco/fotografía solicitado para Rendiciones.**
No se han inventado nombres de eventos, identificadores de campo ni un protocolo web inexistente en esa versión.

## Android: implementación y reaprovechamiento
- `src/cpp/supabaserealtimechannel.{h,cpp}`: canal autentificado existente, reconexión, leave; control configurable `fieldSettleMs` (180 ms por defecto, **150 ms para Rendiciones**), limpieza del campo al ir a segundo plano o cambiar de documento.
- `src/cpp/presenceidentity.{h,cpp}` (existentes, sin modificar): color FNV-1a a partir del ID real del usuario, referencia privada `storage://avatars/<uid>/…`, URL firmada solicitada por cada receptor, descarga a caché privada y fallback a iniciales. Nunca enviar token/URL firmada por el canal.
- `qml/Mobile/renditions/RenditionsApp.qml`: vínculo del canal con detalle, editor de cabecera, editor de gasto y recepción administrativa; foco limpio en segundo plano, hoja de nueva rendición o cierre. Reusa broadcast `invalidate` y lógica de recarga diferida.
- `qml/Mobile/renditions/RCard.qml`: conecta foco del control hijo al identificador visual de presencia.
- `qml/Mobile/renditions/RenditionDetail.qml`: avatares existentes y halo de encabezado mientras alguien edita datos de la rendición.
- `qml/Mobile/renditions/RenditionExpenses.qml` (ya integrado): halo por `Gasto N`.
- `qml/Mobile/renditions/RenditionFinancial.qml`: halo para `Financiamiento` y `Tipo de cambio` cuando se enfoca un control de su tarjeta.
- `qml/Mobile/renditions/RenditionDocuments.qml`: halo en documentos asociados a un gasto que otra persona está editando.
- `qml/Mobile/renditions/RenditionReceived.qml`: se une al mismo canal, lista compañeros y avatares en vista de recepción, sin publicar un foco ficticio al solo leer.
- `qml/Mobile/components/PresenceAvatars.qml` y `FieldPresenceHighlight.qml` preexistentes; no duplicados.
- CMake ya enumera los servicios y los dos QML; **no se agregaron QRC/qmldir ni nuevos tipos**.

## Qué comprobar al compilar el usuario
1. Instalar Android y entrar con **cuenta A**; abrir una rendición ya sincronizada con `remoteId`.
2. Entrar con **cuenta B** en la **web** sobre el mismo `renditionId`. Validar que cada sesión vea a la otra. Con el ZIP web revisado se esperan **iniciales**, no fotos ni halo en esa web.
3. Entrar con **cuenta B en otro Android** con esta implementación. Comprobar la foto de perfil cuando haya `storage://avatars` accesible, o inicial si no.
4. Desde A abrir «Editar rendición», enfocarse en nombre; B debe iluminar «Datos de la rendición». Pasar a otro campo y cerrar editor: limpiar halo.
5. Desde A abrir un gasto, enfocar su formulario; B debe iluminar la tarjeta correspondiente en Gastos y Documentos.
6. Desde A ir a Finanzas y enfocar los campos de importe o tipo de cambio; B debe ver el halo correcto, color y etiqueta.
7. Desde recepción administrativa, comprobar avatares sin edición falsa. Desde una cuenta sin acceso, el canal privado debe rechazar la unión.
8. Cambiar de rendición, mandar Android a segundo plano, matar app y volver: no deben quedar participantes/focos fantasmas; al regresar debe reconectar.
9. Probar modo claro/oscuro, teclado abierto, red interrumpida y reconexión; al recibir `invalidate`, se vuelven a pedir datos autorizados, sin confiar en metadatos de presencia para editar valores.

## Riesgos / pendientes explícitos
- **Paridad v2 web no certificable:** el ZIP no implementa fotos ni foco para Rendiciones. Para cumplir el requisito bidireccional hay que aportar la fuente de esa v2 web o incorporarle el mismo contrato.
- `field` es actualmente una **etiqueta de sector** en Android (`Gasto N`, `Financiamiento`, `Tipo de cambio`, `Datos de la rendición`). No hay IDs de campo/sector compartidos en la web del ZIP; las numeraciones podrían diferir entre sesiones con orden de gastos distinto.
- No se verificaron las políticas de acceso Realtime/Storage ni la firma de avatares contra backend real.
- No se compiló ni inspeccionó logcat; no se afirma aprobación funcional o visual.

## Verificación estática
```powershell
node tests/renditions/presence_v2_android_static.cjs
git diff --check -- src/cpp/supabaserealtimechannel.cpp src/cpp/supabaserealtimechannel.h qml/Mobile/renditions
```
La primera prueba verifica la presencia de conexiones, contratos y recursos en fuentes; **no sustituye** prueba de runtime Qt/Supabase.
