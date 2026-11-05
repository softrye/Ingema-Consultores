# Calicatas: patrón de laboratorio y popup de estrato

## Cambios
- Símbolo/patrón del estrato: solo lectura, sin flecha ni acción para abrir Laboratorio. Se conserva la vista de color y tramas.
- Popup de estrato: ancho máximo 560 dp y alto preferido 82 % del espacio libre, con límite de 760 dp; usa el mismo cálculo IME, Flickable y animaciones existentes. Origen pasa antes de profundidad, color y clasificación; moverlo no escribe ni borra datos.
- SUCS se sugiere desde los ensayos y solo se adopta explícitamente en Laboratorio. Una sugerencia doble escribe primary_sucs/is_composite/secondary_sucs en una operación, sin estados intermedios. Conserva valores ocultos al adoptar una clasificación simple.
- IP = LL − LP; línea A: IP = 0.73(LL − 20). F = pasa Nº 200: <5 % limpio, 5–12 % doble, >12 % grueso con finos. 50 % separa fino de grueso. La zona CL-ML produce el símbolo doble correspondiente, no dos alternativas simples.
- Cu = D60/D10; Cc = D30²/(D10·D60). Bien graduado: Cu ≥4 en grava o ≥6 en arena y 1≤Cc≤3. Dp se interpola en escala semilogarítmica solo entre porcentajes medidos de tamices con abertura conocida (4.75, 2, 0.425 y 0.075 mm). No se interpreta el campo «Máx. (%)» como un diámetro, ni se extrapolan extremos. Si D10/D30/D60 faltan quedan alternativas pendientes: por ejemplo F>10 % requiere una fracción menor que Nº200 para D10.
- La proyección conserva las capas SVG existentes (una por código), los campos y el contrato de sincronización. Los suelos finos requieren confirmar naturaleza orgánica; no se inventa ese ensayo. CL-ML describe la zona de suelos inorgánicos y la adopción sigue a cargo del técnico.

## Fuente
FHWA NHI-05-037, capítulo 4, tabla 4-13 y notas 3–7: https://www.fhwa.dot.gov/engineering/geotech/pubs/05037/04c.cfm . La línea A ya existía en CalicataRules.aLinePlasticity. Las sugerencias SUCS ahora amplían el motor Web anterior: el fixture antiguo de paridad numérica SUCS necesita actualizarse a esta regla; no se afirma igualdad con esos resultados antiguos.

## Validación
- Prueba puntual: `node tests/calicatas/sucs_calculated_symbols.cjs`: interpolación sin extrapolación, Cu/Cc, límites 5/12/50, línea A, clasificación doble, adopción y dos capas de patrón.
- `qmllint -I C:/Qt/6.9.3/mingw_64/qml -I qml/Mobile qml/Mobile/pages/CalicataFormPage.qml`: salida 0 con avisos de análisis desde fuente.
- Sin compilar, instalar, ADB ni suites completas. Pendiente probar teclado, tamaños, gesto y Natural → Antrópico → Natural en la app compilada por el usuario.
- Los dos archivos de producción ya tenían modificaciones extensas sin commit antes de este encargo; se conservan. No se modifica Earth, Login, exportadores ni persistencia.

El commit incluye el estado previo necesario de los dos archivos de Calicatas (rediseño pendiente que ya estaba en el workspace), junto a estas correcciones; las copias previas se conservaron fuera del repo. El rediseño anterior no se atribuye a este encargo.
