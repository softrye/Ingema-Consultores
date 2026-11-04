-- InGePlus-Dev ONLY. Existing bindings only. No writes or permission changes.
-- Run in an authorized SQL connection; any attempted data write is rejected.
begin read only;
do $$
begin
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',(select id from public.profiles where role::text='ADMINISTRADOR_GENERAL'
           and status::text='ACTIVO' limit 1),
    'role','authenticated')::text,true);
end $$;
set local role authenticated;

select current_setting('transaction_read_only') as read_only,to_jsonb(r) as rpc_response
from public.ensure_calicata_smart_document_v01('c5a8cece-b1a6-4f29-988e-826be10a6c82') r;
-- c+00+11: every original client condition currently passes.

select current_setting('transaction_read_only') as read_only,to_jsonb(r) as rpc_response
from public.ensure_calicata_smart_document_v01('fbd8ec81-3f0b-4c8d-9998-99b2002c33bc') r;
-- Existing root document: parent_node_id is explicit JSON null. All other
-- fields pass; this was rejected by parentNodeId.isEmpty() in Android.
rollback;
