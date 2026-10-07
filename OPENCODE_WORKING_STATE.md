# Checkpoint 2026-08-26 Rendiciones P0 Sync
UI Flutter Rendiciones usable.
LocalStore JSON + outbox presentes.
RenditionRepository V02 y RenditionSyncController presentes.
Codex no pudo validar sync contra servidor por falta de sesion Android autenticada.
Fase de inmutabilidad ya agrego assertDraftStatus a mutaciones LocalStore.
Hallazgo usuario: Mobile guarda borradores/presentaciones localmente pero no aparecen en Web/servidor.
Objetivo: reparar bidireccionalidad real sin cambiar contratos backend.
