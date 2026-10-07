# Descarga InGeDrive y exportación sin apertura automática — 05/10/2026

## Causas confirmadas

El archivo de la captura es document_version_id 47b6d06f-081c-42c5-b9b0-db4dc7e0a4cd, nodo 054dc145-8ed0-47d8-9ace-5b39375a35ba. Supabase confirma SUBIDO, bucket privado project-files y tamaño 215099 bytes. No existe un bucket IngePlus en este proyecto.

NothingDocuments resolvía el destino correcto mediante get_binary_document_access_v01, pero pasaba sólo storage_path a CloudDocs::downloadJson. Ese método construía la URL con el bucket global heredado IngePlus: se descartaba el bucket devuelto por el servidor. No era un fallo de la carpeta exports ni motivo para hacer público Storage o crear otro bucket.

CalicatasEditorPage::_finishExcelExport llamaba expresamente a openLastExport(false). Por separado, exportStateToXlsx copiaba el libro a MediaStore Downloads automáticamente. La exportación aún ejecutaba esos pasos del flujo local anterior.

## Cambios de fuente

- CloudDocs::downloadExact recibe bucket, storage_path, tamaño y callback de esa descarga. Valida project-files y la ruta canónica antes de usar la sesión del usuario para el GET. No cambia el bucket global ni prueba otro destino si falla.
- downloadObject es el único transporte de descarga compartido con el wrapper legado. Limita el tiempo de red, exige HTTP 2xx, verifica la longitud esperada y escribe mediante QSaveFile. Un fallo conserva cualquier copia anterior. Una respuesta de una sesión o cuenta anterior no escribe archivos.
- NothingDocuments usa downloadExact y un callback ligado al epoch de cuenta. Sólo tras guardar correctamente se materializa el manifiesto del espejo. Un fallo al guardar ese manifiesto se informa, sin anunciar LOCAL_AVAILABLE.
- Descargar por menú no abre el archivo. Abrir/compartir desde InGeDrive sigue siendo una acción explícita y puede descargar la versión actual antes de invocar el visor.
- _finishExcelExport no invoca ningún visor, termina con la acción Cerrar e indica consultar InGeDrive. Muestra el estado real SYNCED/ERROR/CONFLICT/PENDING_SYNC, sin presentar una cola aceptada como una subida confirmada.
- exportStateToXlsx conserva la copia privada y la cola durable para subir a exports, pero deja de copiar automáticamente el Excel de Calicatas a Descargas públicas. No se borraron descargas anteriores. Otros exportadores conservan su comportamiento.

## Validación realizada

1. Los nuevos tests fallaron primero por la llamada automática a openLastExport y por usar downloadJson sin bucket.
2. tests/calicatas/export-drive-only.cjs ejecuta la función QML real para estados pendiente, sincronizado y error; prueba ausencia de visor, cola sin red, mensaje de sincronización y ausencia de copia pública automática.
3. tests/documents/download-exact-static.cjs comprueba el recorrido bucket/path exactos, JWT de sesión, epoch, tamaño, guardado atómico y límite de red.
4. Las 27 suites JavaScript de tests/calicatas y tests/documents pasan. La aceptación R13 anterior, que exigía autoabrir, se actualizó al comportamiento solicitado.
5. qmlformat Qt 6.9.3 analizó CalicatasEditorPage sin errores, sin reformatear el fuente.
6. En Supabase se ejecutó BEGIN/ROLLBACK con rol authenticated y el usuario uploaded_by de la versión. get_binary_document_access_v01(..., NULL) devolvió la versión actual, project-files y su ruta/tamaño. SELECT sujeto a RLS sobre storage.objects confirmó object_readable=true. No se cambió Storage, sus políticas ni la ficha del usuario.
7. git diff --check sobre los seis fuentes modificados no reportó errores de espacios.

No se ejecutaron build, instalación, ADB ni logcat: Fabián compila. La comprobación SQL confirma objeto/ACL, no sustituye una descarga HTTP real desde Android. La prueba antigua de tests/inge-core/beta21_calicatas.cjs ya documentada en la fase anterior continúa fuera de esta validación.

## Prueba requerida en el APK nuevo

1. Compilar e instalar los fuentes actuales del árbol de trabajo.
2. Exportar una calicata: debe permanecer en InGe+, sin Excel/selector y sin una nueva copia pública en Descargas.
3. Esperar sincronización; localizar la carpeta exports junto al JSON editable en InGeDrive.
4. Descargar el XLSX desde InGeDrive. La URL autenticada debe utilizar project-files. Puede probarse también el archivo de la captura, sin volver a exportarlo.
5. Abrirlo mediante un toque explícito en InGeDrive; comprobar también menú Descargar sin visor, reutilización de copia actual, actualización a una nueva versión y uso de la copia sin red.
6. Si se cambia de cuenta durante una descarga, ninguna respuesta de la cuenta anterior debe materializarse en la nueva.

Se conservaron los cambios de trabajo existentes. Las rutas legacy no se migraron cambiando su bucket global ni se crearon implementaciones alternativas.
