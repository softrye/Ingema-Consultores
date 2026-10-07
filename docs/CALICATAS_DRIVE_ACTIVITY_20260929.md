# Calicatas: NAME_CONFLICT y actividad 42501

## Diagnostico

Backend autorizado: InGePlus-Dev, aalmeaqhhlhzwwzsbbxz. Sin build ni ADB.

1. `saveJsonToDrive` envia `<codigo>.calicata.json` a la reserva binaria.
   `private.reserve_binary_upload_core_v01` separa `.json` y trata de insertar
   `document_nodes.name = <codigo>.calicata`. Ese nombre ya corresponde al
   Smart Document. El indice `document_nodes_active_sibling_name_v01_uq` ignora
   la extension y provoca unique_violation, traducida a NAME_CONFLICT.
   No hace falta una carrera para reproducirlo.
2. El comando `calicatas.sync` llama doSave y saveDriveJson en paralelo. Al
   terminar doSave, publishCalicata crea ademas otro snapshot con hash, en la
   raiz. Su INGE_DRIVE_EXPORT synced corresponde a esa segunda publicacion,
   no demuestra que la copia JSON en 06_GABINETE haya terminado.
3. `drive_json_node_id` solo se conserva localmente despues de finalize y el
   intento usa un UUID nuevo cada vez. Perder la respuesta/identidad induce
   otro CREATE_DOCUMENT. Falta identidad persistente del JSON por calicata.
4. Autosave de datos no exporta ese JSON por si solo; hay otro timer JSON de
   20 s. doSave no espera el autosave y los callbacks dan prioridad al autosave
   cuando ambos usan el mismo instanceId: pueden consumir la respuesta manual.
5. flushActivity intenta INSERT directo en activity_logs. authenticated solo
   tiene SELECT y una policy SELECT; 42501 es el rechazo correcto. Ademas,
   UPDATE_CALICATA no es el evento canonico CALICATA_UPDATED. El trigger
   audit_calicata_change_v01 ya registra creacion/cambios/estado. Hay registros
   reales del backend para estas operaciones. No procede abrir INSERT/RLS.

Se conserva todo dato y cambio previo del usuario. Se corregiran solamente
CalicataCloudService, el coordinador QML de guardado y las RPC necesarias.
Los fuentes afectados ya tenian cambios previos extensos; se conserva su
contenido al integrar esta correccion. No se modifica la cola de Rendiciones.

Prueba SQL de reproduccion: tests/calicatas/drive-conflict-before.sql.

## Resolucion final

1. NAME_CONFLICT: la identidad JSON la fija el servidor
   (`reserve_my_calicata_json_v01`, binding privado por calicata). Nombre del
   nodo: `ficha-<codigo sin puntos>-<8 hex del id>`; archivo fisico `.json`.
   No queda ningun punto antes de `.json`, asi que nunca se reduce a
   `<codigo>.calicata` (Smart Document). Ambos viven en `06_GABINETE` (FIELD).
   Guardados siguientes versionan el MISMO nodo (node/content version leidos en
   el servidor); contenido identico devuelve IDEMPOTENT_REPLAY.
2. Actividad: el cliente ya no reenvia eventos de ciclo de vida
   (`audit_calicata_change_v01` los registra); solo exportaciones via
   `record_my_calicata_export_v02`. activity_logs sigue sin INSERT directo.
3. Guardado: un solo flujo `calicatas.sync` -> doSave -> syncDocument
   (fila + `ensure_calicata_field_folder_v01` + Smart Document) -> JSON. Solo el
   JSON lanzado por ese Guardar lo cierra; un autoguardado JSON en curso deja el
   del Guardar en cola. `publishCalicata` solo corre en la exportacion Excel.
4. Abrir desde InGeDrive reconoce `ficha-...-xxxxxxxx(.json)` (y el nombre
   previo `calicata-<uuid>`), descarga y abre con `applyPickedFile`.
5. La migracion 20260929201351 se aplico en InGePlus-Dev mediante el complemento.
   `tests/calicatas/drive-conflict-before.sql` pasa a ser la regresion final.
