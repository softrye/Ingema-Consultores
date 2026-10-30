-- Controlled Dev-only regression. All fixture rows and audit rows roll back.
-- Does not trash/recover/delete any preexisting rendition or document.
BEGIN;
DO $test$
DECLARE
 actor uuid;
 other_actor uuid;
 origin record;
 folder record;
 created record;
 expense record;
 trashed record;
 replay record;
 node uuid;
 node_ver bigint;
 request uuid := gen_random_uuid();
 plan jsonb;
 recovered jsonb;
 cat text;
 pay text;
 support text;
BEGIN
 SELECT r.owner_user_id INTO actor FROM public.renditions r
 JOIN public.profiles p ON p.id=r.owner_user_id AND p.status='ACTIVO'
 JOIN public.document_smart_bindings b ON b.rendition_id=r.id
 JOIN public.document_nodes n ON n.id=b.node_id AND n.lifecycle='ACTIVE'
 WHERE r.archived_at IS NULL AND r.status='BORRADOR' AND NOT r.is_blocked
 ORDER BY r.created_at DESC LIMIT 1;
 IF actor IS NULL THEN RAISE EXCEPTION 'TEST_ACTIVE_OWNER_MISSING'; END IF;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 SELECT b.space_id,b.project_id,n.parent_id INTO origin
 FROM public.document_smart_bindings b JOIN public.document_nodes n ON n.id=b.node_id
 JOIN public.renditions r ON r.id=b.rendition_id
 WHERE r.owner_user_id=actor AND r.archived_at IS NULL AND n.lifecycle='ACTIVE'
 AND private.files_acl_can_access_v01(actor,b.space_id,n.parent_id,'WRITE')
 ORDER BY r.created_at DESC LIMIT 1;
 IF origin.parent_id IS NULL THEN RAISE EXCEPTION 'TEST_WRITABLE_PARENT_MISSING'; END IF;
 SELECT * INTO folder FROM public.create_document_folder_v01(origin.space_id,origin.parent_id,
   'CODEX_TRASH_TEST_'||request::text);
 IF folder.success IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FOLDER_FAILED: %',folder.error_code; END IF;
 SELECT * INTO created FROM public.create_my_rendition_draft_v03(gen_random_uuid(),
   date '2026-10-01',date '2026-10-31',ARRAY[origin.project_id],origin.project_id,
   folder.node_id,'CODEX_TRASH_TEST_'||request::text);
 SELECT code INTO cat FROM public.rendition_expense_categories WHERE is_active AND deactivated_at IS NULL ORDER BY display_order LIMIT 1;
 SELECT code INTO pay FROM public.rendition_payment_methods WHERE is_active AND deactivated_at IS NULL AND code='CASH';
 SELECT code INTO support FROM public.rendition_support_types WHERE is_active AND deactivated_at IS NULL AND code='NONE';
 IF pay IS NULL THEN SELECT code INTO pay FROM public.rendition_payment_methods WHERE is_active AND deactivated_at IS NULL ORDER BY display_order LIMIT 1; END IF;
 IF support IS NULL THEN SELECT code INTO support FROM public.rendition_support_types WHERE is_active AND deactivated_at IS NULL ORDER BY display_order LIMIT 1; END IF;
 SELECT * INTO expense FROM public.create_my_rendition_expense_v02(gen_random_uuid(),created.rendition_id,
   created.row_version,origin.project_id,date '2026-10-27',cat,'CODEX_TRASH_TEST',pay,support,'PEN',1.00,
   NULL,'Prueba controlada',NULL,'Prueba controlada','Prueba controlada');
 SELECT b.node_id INTO node FROM public.document_smart_bindings b WHERE b.rendition_id=created.rendition_id;
 SELECT p.id INTO other_actor FROM public.profiles p WHERE p.status='ACTIVO' AND p.id<>actor ORDER BY p.id LIMIT 1;
 IF other_actor IS NULL THEN RAISE EXCEPTION 'TEST_OTHER_ACTIVE_PROFILE_MISSING'; END IF;
 PERFORM set_config('request.jwt.claim.sub',other_actor::text,true);
 BEGIN
   PERFORM public.trash_my_rendition_draft_v01(created.rendition_id,expense.rendition_row_version,gen_random_uuid());
   RAISE EXCEPTION 'TEST_OWNER_NOT_ENFORCED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RENDITION_NOT_FOUND_OR_FORBIDDEN' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 BEGIN
   PERFORM public.trash_my_rendition_draft_v01(created.rendition_id,-1,request);
   RAISE EXCEPTION 'TEST_CAS_NOT_ENFORCED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RENDITION_VERSION_CONFLICT' THEN RAISE; END IF; END;
 SELECT * INTO trashed FROM public.trash_my_rendition_draft_v01(created.rendition_id,expense.rendition_row_version,request);
 SELECT * INTO replay FROM public.trash_my_rendition_draft_v01(created.rendition_id,expense.rendition_row_version,request);
 IF trashed.lifecycle<>'TRASHED' OR replay.result_code<>'IDEMPOTENT_REPLAY'
   OR replay.row_version<>trashed.row_version THEN RAISE EXCEPTION 'TEST_TRASH_REPLAY'; END IF;
 BEGIN
   PERFORM public.trash_my_rendition_draft_v01(created.rendition_id,-1,request);
   RAISE EXCEPTION 'TEST_REQUEST_PAYLOAD_NOT_ENFORCED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RENDITION_IDEMPOTENCY_CONFLICT' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM public.list_renditions_effective_v06(100,NULL,NULL) x WHERE x->>'id'=created.rendition_id::text)
   THEN RAISE EXCEPTION 'TEST_TRASH_STILL_IN_RENDITIONS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.list_files_global_trash_v04(NULL,200)->'items') x
   WHERE x->>'id'=node::text) THEN RAISE EXCEPTION 'TEST_MISSING_GLOBAL_TRASH'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.list_files_trash_children_v07(NULL,NULL,200)->'items') x
   WHERE x->>'id'=node::text AND (x->>'can_restore')::boolean)
   THEN RAISE EXCEPTION 'TEST_MISSING_MOBILE_TRASH'; END IF;
 SELECT n.node_version INTO node_ver FROM public.document_nodes n WHERE n.id=node;
 plan := public.preview_files_recovery_v07(node,node_ver,NULL,NULL);
 IF plan->>'token' IS NULL THEN RAISE EXCEPTION 'TEST_RECOVERY_PLAN: %',plan; END IF;
 recovered := public.mutate_files_recovery_v07(node,node_ver,gen_random_uuid(),plan->>'token',NULL,NULL);
 IF (recovered->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_RECOVERY_FAILED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.list_renditions_effective_v06(100,NULL,NULL) x WHERE x->>'id'=created.rendition_id::text)
   THEN RAISE EXCEPTION 'TEST_RECOVERED_RENDITION_MISSING'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.list_my_rendition_expenses_v01(created.rendition_id) x WHERE x.id=expense.expense_id)
   THEN RAISE EXCEPTION 'TEST_RECOVERED_EXPENSE_MISSING'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.renditions r WHERE r.id=created.rendition_id AND r.archived_at IS NULL)
   OR NOT EXISTS(SELECT 1 FROM public.document_nodes n WHERE n.id=node AND n.lifecycle='ACTIVE')
   THEN RAISE EXCEPTION 'TEST_RECOVERED_STATE'; END IF;
 PERFORM public.trash_my_rendition_draft_v01(created.rendition_id,expense.rendition_row_version,request);
 IF NOT EXISTS(SELECT 1 FROM public.document_nodes n WHERE n.id=node AND n.lifecycle='ACTIVE')
   THEN RAISE EXCEPTION 'TEST_REPLAY_RETRASHED_RECOVERED_NODE'; END IF;
 PERFORM set_config('codex.trash_test_result',jsonb_build_object('passed',true,
   'rendition_id',created.rendition_id,'node_id',node,'folder_id',folder.node_id,'expense_id',expense.expense_id,
   'checks',ARRAY['owner','CAS','trash','request_id replay','request payload conflict','global trash','mobile trash can_restore',
   'Files preview','Files recover','rendition visible','expense preserved'],
   'cleanup','ROLLBACK: all fixture rows removed')::text,true);
END;
$test$;
SELECT current_setting('codex.trash_test_result')::jsonb AS controlled_test;
ROLLBACK;
