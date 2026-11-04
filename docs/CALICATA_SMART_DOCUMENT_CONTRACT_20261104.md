# Smart Document de Calicata: padre nulo valido en la raiz del espacio

Fecha: 2026-11-04. Rama: codex/fusionbridge-native.
Unico servidor consultado: InGePlus-Dev / aalmeaqhhlhzwwzsbbxz.

## Evidencia y limite de la reproduccion

El RPC llamado antes del rechazo es `ensure_calicata_smart_document_v01`.
Se invoco con rol authenticated, perfil administrador activo y
`transaction_read_only=on`. Solo se ejercio su rama de vinculo existente:
consulta la vinculacion y devuelve `IDEMPOTENT_REPLAY`. No se crearon ni
actualizaron nodos, fichas, permisos o migraciones.

Respuesta real actual de **c+00+11**, proyecto PROYECTO_HUARMEY:

```json
{
  "document_node_id": "1272e209-cd62-4ffc-9bb4-8413e3a3a1ac",
  "space_id": "53a2e43c-0ccd-4e76-8f16-940ca1e86ee0",
  "parent_node_id": "f212e604-4a7a-4bc0-a04c-9748e78e933a",
  "project_id": "7fb77795-9986-4b99-8b59-55f1266891d4",
  "target_id": "c5a8cece-b1a6-4f29-988e-826be10a6c82",
  "target_type": "CALICATA",
  "name": "c+00+11.calicata",
  "lifecycle": "ACTIVE",
  "node_version": 1,
  "result_code": "IDEMPOTENT_REPLAY"
}
```

Esta respuesta cumple **todas** las condiciones originales: los tres UUID de
enrutamiento no estan vacios, proyecto y destino coinciden, tipo CALICATA,
nombre no vacio, version >= 1, lifecycle y result_code admitidos. No demuestra
por si sola que el rechazo observado anteriormente en el telefono fuera el
mismo defecto; esa respuesta fallida no fue capturada.

Se contrastaron las respuestas reales de las siete calicatas con vinculacion
existente en ese proyecto. Seis pasan el validador anterior. Una falla
exactamente en **parent_node_id**: `QA IA laptop 2026-10-15`, cuya respuesta es:

```json
{
  "document_node_id": "417a298d-3ad7-42ab-8ba7-599d55128e85",
  "space_id": "53a2e43c-0ccd-4e76-8f16-940ca1e86ee0",
  "parent_node_id": null,
  "project_id": "7fb77795-9986-4b99-8b59-55f1266891d4",
  "target_id": "fbd8ec81-3f0b-4c8d-9998-99b2002c33bc",
  "target_type": "CALICATA",
  "name": "QA IA laptop 2026-10-15.calicata",
  "lifecycle": "ACTIVE",
  "node_version": 1,
  "result_code": "IDEMPOTENT_REPLAY"
}
```

El esquema permite `document_nodes.parent_id IS NULL`. Existe un Smart
Document activo en esa ubicacion raiz. La rama de repeticion del RPC devuelve
el padre real del nodo mediante `private.smart_materialization_result_v01`;
no reubica documentos existentes a 06_GABINETE. El cliente convertia null a
cadena vacia y rechazaba esa ubicacion legitima con `parentNodeId.isEmpty()`.
No se observaron result_code EXISTING/UPDATED, versiones 0, nombres vacios,
otros formatos de columna ni lifecycle PURGED en estas respuestas.

## Correccion

En `calicatacloudservice.cpp`, bloque de materializacion:

- Se acepta un padre UUID valido o **null explicito** para la raiz.
- Una columna ausente, cadena vacia o UUID malformado sigue siendo invalida.
- Proyecto, destino y tipo siguen siendo obligatorios y deben coincidir.
- Se mantienen los controles de nombre, version, lifecycle y result_code.
- Se conserva el null en el resultado local, sin inventar una carpeta padre.
- El log `INGE_CALICATA_SMART_DOCUMENT_INVALID` identifica cada campo fallido
  y forma/cantidad de filas. No imprime respuestas, valores de campos, nombres,
  identificadores personales, credenciales ni URLs firmadas.
- Se entrega `SMART_DOCUMENT_INVALID_CONTRACT` / `CAL-SMART-CONTRACT` como
  referencia del rechazo; el borrador sigue conservandose.

No se modifico el RPC ni se aplico migracion: las respuestas comprobadas son
coherentes con el esquema y el control incorrecto estaba en Android.

## Pruebas y verificacion

- `node --test tests/calicatas/smart_document_contract.cjs`: cinco pruebas.
  Antes de corregir, la respuesta real con padre null era rechazada; despues
  pasa. Se comprueba que padre ausente/vacio/malformado e identidades o estados
  incoherentes siguen siendo rechazados y que el diagnostico no expone valores.
  Las pruebas ejecutan los predicados booleanos extraidos del C++ con
  adaptadores de valores Qt; no sustituyen una compilacion/prueba nativa.
- `node tests/calicatas/drive-save-coordination.cjs`: pasa.
- `node tests/calicatas/form_logic_static.cjs`: seis comprobaciones pasan.
- Fixtures de las respuestas reales: `tests/calicatas/fixtures/smart_document_rpc_dev_20261104.json`.
- Reproduccion SQL sin escritura: `tests/calicatas/sql/smart_document_contract_readonly.sql`.

Cuando el usuario compile: abrir PROYECTO_HUARMEY > c+00+11 y sincronizar.
Confirmar que no aparece el aviso y que el borrador queda sincronizado. Abrir
tambien la ficha de prueba situada en la raiz y repetir; debe conservar su
ubicacion real. Si vuelve el rechazo, registrar solo la linea
`INGE_CALICATA_SMART_DOCUMENT_INVALID fields=... shape=... rows=...` para
identificar el campo concreto de esa respuesta.

[No se pudo reproducir el rechazo anterior de c+00+11: su respuesta actual es valida.]
[No se compilo ni se instalo la app; sincronizacion y regresion en dispositivo pendientes del usuario.]

Los cambios previos sin commit de otros trabajos se preservaron. El commit
de esta fase contiene unicamente el cambio del validador y estos documentos/pruebas.
