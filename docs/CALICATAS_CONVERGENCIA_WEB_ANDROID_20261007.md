# Calicatas: convergencia Web ↔ Android (2026-10-07)

Fuente de verdad: `E1PT04m0/ingeplus-web`, rama `feature/calicatas-cloud-media-04a`
(archivo de la rama del 2026-09-25). Android se adaptó al contrato Web; Web no se tocó.

## 01 Encabezado
- Proyecto = `projects.name` (snapshot `project.name`). Es una sola fuente para la ficha, el rótulo de fotos, el Excel AG4 y el PDF.
- Se retiraron del formulario «Nombre del proyecto» editable, «Nombre corto del proyecto» y «Nombre corto (interno)».
- `project_full_name`, `project_short_name` y `title` se conservan en el documento.
  - El nombre antiguo solo se muestra y exporta si la ficha aún no tiene proyecto.
- «Título de la ficha / testificación» = `description` (como Web). El código sigue aparte.

## 02 Estrato ↔ Laboratorio ↔ SUCS/AASHTO
- Port exacto de `soilClassification.ts` y `laboratoryContract.ts`:
  - `reviewLaboratorySample`, `classifyAashto` (IG con topes), `recommendSucs` (Nº 4), `validateCalicataLaboratoryForm`, `formatSucsProjection`, `resolveCalicataSucsPattern`.
  - Verificado contra el motor Web real: 5000 casos aleatorios, 0 diferencias.
  - 500 casos se guardan en `tests/calicatas/fixtures/web_lab_golden_04a.json`.
- Sin NP ni D10/D30/D60 en la clasificación. Un grueso limpio queda como conjunto (GW/GP/SW/SP solo como candidatos).
- WL/LP son enteros, como Web. Un decimal antiguo queda pendiente (`LAB_LIMITS`) y nunca se redondea.
- La autoridad es el laboratorio:
  - Campos: `extra.primary_sucs`, `is_composite`, `secondary_sucs`, `lab_confirmed_aashto` (= `calicata_lab_results`).
  - Fichas antiguas: `lab_confirmed_sucs` se migra una vez y queda como espejo.
- Laboratorio replica la tabla Web:
  - «Clasificación sugerida»: chips AASHTO + hasta 4 SUCS y «+N».
  - Adoptar exige un toque.
  - Selectores SUCS principal / compuesta / segundo SUCS / AASHTO.
- Estrato muestra SUCS, AASHTO y patrón en solo lectura («Pendiente de laboratorio»). Tocar abre Laboratorio.
- Se retiraron:
  - los selectores SUCS/AASHTO del Estrato;
  - el selector de tramas MTC/RA;
  - el motor `classifyLaboratory`.
- Teselas `SUCS/web/*.svg` y `SUCS/web/export/*.svg`, idénticas byte a byte a `sucsSymbols.ts`.
- Exportación = `exportModel`:
  - laboratorio primero, valor anterior del estrato solo si el laboratorio está vacío;
  - rótulo «SP-SM»;
  - trama compuesta E:G | H:I a 17 px.

## 03 Fotos
- «Descargar versión anotada»: copia exacta del derivado ya guardado (`foto%1_path`), sin repintar.
  - Android 10+: MediaStore `Pictures/InGePlus`.
  - Android 9: carpeta pública + escaneo de medios.
  - El original no cambia.
- «Descargar original» igual que Web.

## 05 Sincronización / row_version (DEV, verificado con transacción revertida)
- Cambio live a un valor nuevo → `row_version` igual.
- Cambio live al mismo valor → sin UPDATE y `row_version` igual.
- Escritura de fila completa o estructural → +1.
- Autosave → live no-op → guardado: sin 40001.
- Escritor externo: se detecta (CAS 0 filas).
- Laboratorio: solo `upsert_my_calicata_lab_result_v02`. Se eliminaron las llamadas a RPC inexistentes:
  - `upsert_my_calicata_lab_result_v03`;
  - `set_my_calicata_lab_extension_v01`;
  - `set_my_calicata_stratum_field_classification_v01`.
- Migraciones Android-only no aplicadas → `supabase/superseded/`.

## 06 Estados
- Web 04a no usa `transition_calicata_review_v07`. Ofrece `get_my_calicata_status_actions_v01` y luego aplica un CAS de `status`; Android hace lo mismo.
- Restaurar una ficha sincronizada → OBSERVADO, la única transición que el servidor permite.

## Pruebas
- `node tests/calicatas/web_lab_parity_static.cjs` (nueva) y el resto de `tests/calicatas`.
- Sin compilación, APK ni ADB (regla del equipo).
  - E2E Android↔Web: **NOT_RUN**.
