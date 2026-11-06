# Pulsación prolongada en preview de estratos

Objetivo: gesto de 380 ms del Dock, menú Borrar/Mover y toque normal para editar. Sin compilar ni ADB.

- [x] CalicataProfile emite held sin convertirlo en tap; cancelar al arrastrar y reutilizar feedback háptico global.
- [x] Menú compacto con Borrar (confirmación existente) y Mover (subir/bajar, confirmar intercambio).
- [x] Reproducir CalicataDetailPanel.tsx:2364–2452 del ZIP web: intercambiar materiales/laboratorio y espesores entre vecinos manteniendo los UUID en sus posiciones. No reordenar UUIDs ni añadir RPC.
- [x] Identidad estable al confirmar acciones, verificar datos concurrentes y no inventar intervalos incompletos.
- [x] Pruebas puntuales, qmllint, documentación y commit.

Supabase Dev se consultó solo en lectura: no hay RPC de reordenación de UUIDs. La web no lo necesita: intercambia contenido, no sequence_number. No se modifica servidor.

Implementación y verificación estática terminadas; compilación y uso real pendientes del usuario.
