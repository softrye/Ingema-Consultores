-- PRESTATE / ROLLBACK: NO EJECUTADO.
-- Target exclusivo: InGePlus-Dev / aalmeaqhhlhzwwzsbbxz.
-- Antes de 20261027145502 no existian ni el RPC ni el ledger:
-- to_regprocedure('public.trash_my_rendition_draft_v01(uuid,bigint,uuid)') = NULL
-- to_regclass('private.rendition_draft_trash_requests_v01') = NULL
-- No se reemplazo ninguna funcion existente. Files v07 queda intacto.
--
-- Para revertir, aplicar este SQL como NUEVA migracion solo con autorizacion.
-- Retira la nueva API sin eliminar receipts, auditoria ni rendiciones/nodos.
-- Los nodos ya enviados a Papelera siguen recuperables mediante Files v07.
-- El cliente con trashDraft recibira RPC no disponible hasta redesplegarla.
BEGIN;
REVOKE ALL ON FUNCTION public.trash_my_rendition_draft_v01(uuid,bigint,uuid) FROM authenticated;
DROP FUNCTION public.trash_my_rendition_draft_v01(uuid,bigint,uuid);
NOTIFY pgrst, 'reload schema';
COMMIT;
