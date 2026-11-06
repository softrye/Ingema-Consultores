# Calicatas: selectores y patrones — plan de implementación

> Ejecución secuencial en esta sesión con la habilidad executing-plans; sin subagentes ni compilación.

**Objetivo:** ejecutar los dos pendientes de docs/PENDIENTES_CALICATAS.md.
**Arquitectura:** reutilizar optionPickerPopup/GenChoiceRow y la proyección SUCS existente; ningún motor nuevo, cambio de almacenamiento o equivalencia AASHTO→SUCS.
**Tecnología:** Qt 6.9.3, QML/JavaScript. El usuario compila.

- [x] Reducir el selector compartido a contenido limitado a seis filas, scroll para listas largas, opción actual visible y aplicación con un toque. X/Atrás cancelan sin guardar; evitar callback doble.
- [x] Revisar adopción/proyección/serialización de dos códigos SUCS; diferenciar visualmente SUCS de AASHTO y mostrar si falta el segundo SUCS. No inventar otra trama para AASHTO.
- [x] Verificar con qmllint y pruebas puntuales de proyección/adopción; conservar valores ocultos y JSON. No suites completas, CMake, build, instalación ni ADB.
- [x] Documentar lo implementado y la validación móvil pendiente; un commit final de esta fase.

Revisión: listas cortas/largas, opción vacía/actual, doble toque/cancelación, clasificación GP+A-1-a frente a GP+GM y compuesto incompleto. Riesgos a comprobar por el usuario: IME, pantalla pequeña, modo oscuro y Realtime real.

Resultado: código y pruebas puntuales preparados; los pendientes se conservan como validación de dispositivo en el documento original. No se marca terminada la regresión real.
