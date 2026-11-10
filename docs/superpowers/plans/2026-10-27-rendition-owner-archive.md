# Archivar rendicion propia: diseno y plan autorizado

El usuario aprobo disenar/aplicar solo InGePlus-Dev y cablear C++ sin QML,
compilacion, commit ni push. Flujo basado en Files v07, igual que trashDraft.

Reglas: propietario activo; estados BORRADOR, OBSERVADO, APROBADO y estados
historicos REVISADO, ARCHIVADO, EXPORTADO. EN_REVISION o solicitud PENDING de
revision impiden archivar. Tambien bloqueo, borrado logico, nodo no ACTIVE,
falta de ACL documental WRITE y CAS vencido. Se conserva status y todas las versiones.

Files v07 hoy reserva ARCHIVE a administradores. Extender solo el caso .rend
propio: helpers privados identifican propietario/nodo independiente, y se
mantienen las ACL existentes. No ampliar files_archive_authority_v07 global.
Listado, contexto archivado y recovery reciben solo la excepcion de nodo propio.
El guard readonly solo permite ARCHIVE propio con guard transaccional Files.
No se habilita escribir contenido archivado ni leer archivos de terceros.

Alternativa descartada: usar archived_at de renditions rompe recovery y mezcla
el borrado logico con el Archivero. Elevar al propietario a administrador de
Files ampliaria acceso a otros tipos y se descarta.

- [x] Respaldar pg_get_functiondef y ACL de cada funcion que se reemplaza.
- [x] Crear migracion: helpers, excepciones Files acotadas, ledger privado,
      archive_my_rendition_v01(uuid,bigint,uuid), actividad y permisos.
- [x] Aplicar solo Dev; verificar firma, cuerpo, ACL y lectura/readonly/recovery.
- [x] Pruebas controladas con datos nuevos y rollback: propietario sin rol admin,
      otra cuenta, estado en revision, CAS, idempotencia, archivo, readonly y recovery.
- [x] C++: archiveRendition hacia la cola existente; marker separado de archived
      y trash, ocultar solo al ack, replay durable y reaparicion al recuperar.
- [x] CJS, diff check, revision de codigo y documentacion/reversion. Sin build.
