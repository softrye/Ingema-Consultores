# Acciones del preview de estratos

- Pulsación prolongada 380 ms, igual al Dock; feedback de presión inmediato y háptico global existente. Desplazar cancela el gesto. El toque normal continúa abriendo el editor.
- Ambos previews (normal y ampliado) abren un menú compacto Borrar/Mover. Borrar usa la confirmación y las reglas existentes, incluida la conservación de al menos un estrato. Confirmar comprueba identidad y datos vigentes para evitar borrar otro estrato por un cambio remoto.
- Mover ofrece subir/bajar entre vecinos y confirma el nuevo límite. Los extremos deshabilitan la dirección imposible. Hasta debe estar completo en ambos estratos afectados; un tercer estrato pendiente no impide mover un par completo.

## Compatibilidad con la web

Revisado ingeplus-main (2).zip, src/components/calicatas/CalicataDetailPanel.tsx:2364–2452. Sí existe requestMoveStratum/applyStratumMove: mantiene los UUID/posiciones, intercambia contenido de campo y laboratorio y cambia el contacto según los espesores. Android replica esa semántica: no permuta las filas remotas ni sequence_number. Conserva metadatos técnicos de cada posición y traslada intervalos de muestra por su desplazamiento relativo.

La implementación anterior Android movía UUIDs completos y terminaba en «No hay RPC autorizado para mover UUIDs». Se reemplaza el recorrido de las acciones por swapStratumSlotsLikeWeb. ListModel actualiza solo las dos posiciones, sin clear/append global que recreara todos los delegados. No se eliminan datos durante el movimiento.

## Servidor y verificación

InGePlus-Dev (aalmeaqhhlhzwwzsbbxz) se consultó únicamente con SELECT de metadatos: RPC de añadir/actualizar/borrar, constraints y triggers. No existe reordenación de UUIDs. La semántica web permite usar las operaciones existentes; no se crea migración ni se escribe en Supabase. No se accede al proyecto de producción.

`node tests/calicatas/profile_hold_move.cjs` pasa: material/lab/espesores, ida/vuelta, UUID de estrato/muestra/lab estable, tercer estrato incompleto, ausencia de clear global e identidad tras inserción concurrente. `node tests/calicatas/pending_selectors_patterns.cjs` pasa la regresión de clasificación. qmllint de CalicataProfile.qml y CalicataFormPage.qml sale 0 con avisos de imports/tipos al analizar desde fuente.

Sin compilar, instalar, ADB ni suites completas. Pendiente en dispositivo: hold frente a tap/scroll, cancelar y confirmar borrar, mover en ambos sentidos, reapertura, sincronización real y edición concurrente web/Android. No se afirma validación de servidor extremo a extremo.

CalicataProfile.qml tenía cambios previos del placeholder «sin Hasta» y bands; se conservan e incluyen en el commit para mantener la vista existente.
