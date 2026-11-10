# Rendition draft trash implementation plan

**Autorizacion:** el usuario aprobo disenar, aplicar en InGePlus-Dev y cablear C++.
Sin nueva aprobacion, commit, push, QML ni build. Ejecucion secuencial.

**Objetivo:** operacion `trashDraft {localId}` con Papelera y recuperacion Files v07.

**Diseno:** un solo lifecycle, el de document_nodes. No usar archived_at del
borrado definitivo logico: impediria recuperar por las ACL existentes. El RPC
actualiza row_version de la rendicion, conserva gastos y asociaciones y llama
preview/mutate_files_lifecycle_v07 atomicamente. La recuperacion v07 restaura la
legibilidad/escritura del dominio al activar el nodo; se verificara con un gasto.
Ledger privado de request_id para reintentos; ningun flag SQL controlable por cliente.

**Alternativas:** archivar raiz/gastos exigiria cambiar ACL y triggers de recovery
y distinguir gastos archivados previamente; se descarta para preservar datos y
usar una sola fuente de lifecycle. Un RPC generico de TRASH no valida las reglas
del borrador y actualmente rechaza bindings de rendiciones; se usa Files v07.

**Archivos:** migracion nueva en supabase/migrations; reporte y rollback en docs;
renditionrepository.{h,cpp}, renditionlocalstore.{h,cpp}, renditionsynccontroller.cpp,
renditionflutterbridge.cpp, renditioncontract.h y pruebas de la cola nativa.

- [x] Inspeccionar contratos, ACL y orden de bloqueos Files v07.
- [x] Crear RPC, ledger RLS sin grants y catalogo de actividad; aplicar solo Dev.
- [x] Prueba SQL con carpeta/rendicion/gasto nuevos dentro de transaccion rollback:
      CAS, propietario, idempotencia, lista Papelera, preview/recover y gastos.
- [x] Recovery funciona sin ajuste; definicion existente verificada sin cambios.
- [x] Cablear una operacion de la cola existente, request_id durable y ack local;
      conservar contenido local y permitir reaparecer tras una lista restaurada.
- [x] Ejecutar todos los .cjs y git diff --check. Sin compilar; pruebas C++ pendientes.
- [x] Documentar version aplicada, verificaciones, limpieza y reversion.

**Revisar:** respuesta perdida, replay tras recovery, permisos de otra cuenta,
CAS vencido, borrador no sincronizado, ediciones pendientes, lista remota atrasada,
cuenta cambiada y preservacion de gastos previamente archivados.
