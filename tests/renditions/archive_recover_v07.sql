-- Dev only. All new fixtures, grants, membership, audit and receipts roll back.
-- No existing user/profile, rendition, node or permission row is modified.
BEGIN;
DO $test$
DECLARE creator uuid; actor uuid; origin record; folder record; created record; expense record;
 result record; replay record; snapshot record; other_rend record;
 node uuid; other_node uuid; member_id uuid; assignment_id uuid;
 request uuid:=gen_random_uuid(); expected bigint; node_ver bigint; plan jsonb;
 versions_before jsonb; cat text; pay text; support text; stage integer;
BEGIN
 SELECT p.id INTO actor FROM public.profiles p WHERE p.status='ACTIVO'
   AND NOT private.files_archive_authority_v07(p.id) ORDER BY p.id LIMIT 1;
 IF actor IS NULL THEN RAISE EXCEPTION 'TEST_NONADMIN_PROFILE_REQUIRED'; END IF;
 SELECT r.owner_user_id INTO creator FROM public.renditions r JOIN public.profiles p ON p.id=r.owner_user_id
 WHERE r.archived_at IS NULL AND p.status='ACTIVO' AND private.files_archive_authority_v07(p.id)
 ORDER BY r.created_at DESC LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',creator::text,true);
 SELECT b.space_id,b.project_id,n.parent_id INTO origin FROM public.document_smart_bindings b
 JOIN public.document_nodes n ON n.id=b.node_id JOIN public.renditions r ON r.id=b.rendition_id
 WHERE r.owner_user_id=creator AND r.archived_at IS NULL AND n.lifecycle='ACTIVE'
 AND NOT EXISTS(SELECT 1 FROM public.project_members m WHERE m.project_id=b.project_id AND m.profile_id=actor)
 AND private.files_acl_can_access_v01(creator,b.space_id,n.parent_id,'WRITE')
 ORDER BY r.created_at DESC LIMIT 1;
 IF origin.parent_id IS NULL THEN RAISE EXCEPTION 'TEST_PROJECT_WITHOUT_MEMBER_REQUIRED'; END IF;
 SELECT * INTO folder FROM public.create_document_folder_v01(origin.space_id,origin.parent_id,'CODEX_ARCHIVE_TEST_'||request::text);
 IF folder.success IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FOLDER_FAILED: %',folder.error_code; END IF;
 INSERT INTO public.project_members(project_id,profile_id,assignment_source,assigned_by,approved_by)
 VALUES(origin.project_id,actor,'FIXTURE_LOCAL',creator,creator) RETURNING id INTO member_id;
 INSERT INTO private.document_access_assignments(space_id,node_id,principal_profile_id,access_level,source_kind,source_key,assigned_by)
 VALUES(origin.space_id,folder.node_id,actor,'WRITE','CODEX_TEST',request::text,creator) RETURNING id INTO assignment_id;
 SELECT * INTO created FROM public.create_my_rendition_draft_v03(gen_random_uuid(),date '2026-10-01',date '2026-10-31',
   ARRAY[origin.project_id],origin.project_id,folder.node_id,'CODEX_ARCHIVE_TEST_'||request::text);
 SELECT code INTO cat FROM public.rendition_expense_categories WHERE is_active AND deactivated_at IS NULL ORDER BY display_order LIMIT 1;
 SELECT code INTO pay FROM public.rendition_payment_methods WHERE is_active AND deactivated_at IS NULL ORDER BY display_order LIMIT 1;
 SELECT code INTO support FROM public.rendition_support_types WHERE is_active AND deactivated_at IS NULL ORDER BY display_order LIMIT 1;
 SELECT * INTO expense FROM public.create_my_rendition_expense_v02(gen_random_uuid(),created.rendition_id,created.row_version,
   origin.project_id,date '2026-10-27',cat,'CODEX_ARCHIVE_TEST',pay,support,'PEN',1.00,
   NULL,'Prueba SQL',NULL,'Prueba SQL','Prueba SQL');
 -- Only a newly created fixture changes owner; never modify a real profile/role.
 UPDATE public.renditions SET owner_user_id=actor WHERE id=created.rendition_id;
 SELECT b.node_id INTO node FROM public.document_smart_bindings b WHERE b.rendition_id=created.rendition_id;
 SELECT * INTO other_rend FROM public.create_my_rendition_draft_v03(gen_random_uuid(),date '2026-10-01',date '2026-10-31',
   ARRAY[origin.project_id],origin.project_id,folder.node_id,'CODEX_ARCHIVE_OTHER_'||request::text);
 SELECT b.node_id INTO other_node FROM public.document_smart_bindings b WHERE b.rendition_id=other_rend.rendition_id;
 PERFORM public.archive_my_rendition_v01(other_rend.rendition_id,other_rend.row_version,gen_random_uuid());
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 IF private.files_archive_authority_v07() THEN RAISE EXCEPTION 'TEST_ACTOR_MUST_NOT_BE_ADMIN'; END IF;
 IF private.files_lifecycle_root_allowed_v07(folder.node_id,'ARCHIVE') THEN RAISE EXCEPTION 'TEST_FOLDER_AUTHORITY_LEAK'; END IF;
 BEGIN
   PERFORM public.archive_my_rendition_v01(other_rend.rendition_id,other_rend.row_version,gen_random_uuid());
   RAISE EXCEPTION 'TEST_OWNER_NOT_ENFORCED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RENDITION_NOT_FOUND_OR_FORBIDDEN' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.list_files_archive_children_v07(NULL,NULL,200)->'items') x
   WHERE x->>'id'=other_node::text) THEN RAISE EXCEPTION 'TEST_ARCHIVE_VISIBILITY_LEAK'; END IF;

 -- BORRADOR, then APROBADO with a real immutable submitted version.
 FOR stage IN 1..2 LOOP
   IF stage=2 THEN
     PERFORM set_config('request.jwt.claim.sub',creator::text,true);
     SELECT r.row_version INTO expected FROM public.renditions r WHERE r.id=created.rendition_id;
     SELECT * INTO snapshot FROM private.freeze_rendition_for_admin_v04(created.rendition_id,expected,gen_random_uuid());
     PERFORM set_config('request.jwt.claim.sub',actor::text,true);
     BEGIN
       PERFORM public.archive_my_rendition_v01(created.rendition_id,snapshot.row_version,gen_random_uuid());
       RAISE EXCEPTION 'TEST_REVIEW_ARCHIVE_NOT_BLOCKED';
     EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RENDITION_ARCHIVE_REVIEW_PENDING' THEN RAISE; END IF; END;
     PERFORM set_config('request.jwt.claim.sub',creator::text,true);
     PERFORM public.transition_rendition_review_v03(created.rendition_id,snapshot.row_version,'APROBADO','Prueba SQL controlada');
     PERFORM set_config('request.jwt.claim.sub',actor::text,true);
   END IF;
   SELECT r.row_version INTO expected FROM public.renditions r WHERE r.id=created.rendition_id;
   SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]') INTO versions_before
     FROM public.rendition_versions v WHERE v.rendition_id=created.rendition_id;
   request:=gen_random_uuid();
   BEGIN
     PERFORM public.archive_my_rendition_v01(created.rendition_id,-1,request);
     RAISE EXCEPTION 'TEST_CAS_NOT_ENFORCED';
   EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RENDITION_VERSION_CONFLICT' THEN RAISE; END IF; END;
   SELECT * INTO result FROM public.archive_my_rendition_v01(created.rendition_id,expected,request);
   SELECT * INTO replay FROM public.archive_my_rendition_v01(created.rendition_id,expected,request);
   IF result.lifecycle<>'ARCHIVED' OR replay.result_code<>'IDEMPOTENT_REPLAY'
     OR replay.row_version<>result.row_version THEN RAISE EXCEPTION 'TEST_ARCHIVE_REPLAY'; END IF;
   BEGIN
     PERFORM public.archive_my_rendition_v01(created.rendition_id,-1,request);
     RAISE EXCEPTION 'TEST_PAYLOAD_NOT_ENFORCED';
   EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'RENDITION_IDEMPOTENCY_CONFLICT' THEN RAISE; END IF; END;
   IF EXISTS(SELECT 1 FROM public.list_renditions_effective_v06(100,NULL,NULL) x WHERE x->>'id'=created.rendition_id::text)
     THEN RAISE EXCEPTION 'TEST_ARCHIVE_STILL_ACTIVE'; END IF;
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.list_files_archive_children_v07(NULL,NULL,200)->'items') x
     WHERE x->>'id'=node::text AND (x->>'can_reactivate')::boolean AND (x->>'can_browse')::boolean=false)
     THEN RAISE EXCEPTION 'TEST_OWNER_ARCHIVE_MISSING_OR_BROWSED_AS_FOLDER'; END IF;
   IF public.get_my_archived_document_context_v07(node)->>'target_id' IS DISTINCT FROM created.rendition_id::text
     THEN RAISE EXCEPTION 'TEST_ARCHIVE_CONTEXT'; END IF;
   IF EXISTS(SELECT 1 FROM public.get_rendition_effective_v06(created.rendition_id) x WHERE (x->>'can_edit_content')::boolean)
     THEN RAISE EXCEPTION 'TEST_ARCHIVE_WRITABLE'; END IF;
   BEGIN
     UPDATE public.rendition_expenses SET concept=concept||'_ILLEGAL' WHERE id=expense.expense_id;
     RAISE EXCEPTION 'TEST_READONLY_NOT_ENFORCED';
   EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'ARCHIVE_READ_ONLY' THEN RAISE; END IF; END;
   SELECT n.node_version INTO node_ver FROM public.document_nodes n WHERE n.id=node;
   plan:=public.preview_files_recovery_v07(node,node_ver,NULL,NULL);
   IF plan->>'token' IS NULL THEN RAISE EXCEPTION 'TEST_RECOVERY_PREVIEW'; END IF;
   IF (public.mutate_files_recovery_v07(node,node_ver,gen_random_uuid(),plan->>'token',NULL,NULL)->>'success')::boolean IS DISTINCT FROM true
     THEN RAISE EXCEPTION 'TEST_RECOVERY_FAILED'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.list_renditions_effective_v06(100,NULL,NULL) x WHERE x->>'id'=created.rendition_id::text)
     THEN RAISE EXCEPTION 'TEST_RECOVERED_RENDITION_MISSING'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.list_my_rendition_expenses_v01(created.rendition_id) x WHERE x.id=expense.expense_id AND x.concept='CODEX_ARCHIVE_TEST')
     THEN RAISE EXCEPTION 'TEST_RECOVERED_EXPENSE_MISSING'; END IF;
   IF versions_before IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]') FROM public.rendition_versions v WHERE v.rendition_id=created.rendition_id)
     THEN RAISE EXCEPTION 'TEST_VERSION_HISTORY_CHANGED'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.renditions r WHERE r.id=created.rendition_id AND r.status=CASE WHEN stage=1 THEN 'BORRADOR' ELSE 'APROBADO' END AND r.archived_at IS NULL)
     THEN RAISE EXCEPTION 'TEST_BUSINESS_STATE_CHANGED'; END IF;
   PERFORM public.archive_my_rendition_v01(created.rendition_id,expected,request);
   IF NOT EXISTS(SELECT 1 FROM public.document_nodes n WHERE n.id=node AND n.lifecycle='ACTIVE')
     THEN RAISE EXCEPTION 'TEST_REPLAY_REARCHIVED'; END IF;
 END LOOP;
 PERFORM set_config('codex.archive_test_result',jsonb_build_object('passed',true,'nonadmin_owner',actor,
   'rendition_id',created.rendition_id,'other_rendition_id',other_rend.rendition_id,'node_id',node,'other_node_id',other_node,
   'folder_id',folder.node_id,'expense_id',expense.expense_id,'membership_id',member_id,'assignment_id',assignment_id,
   'checks',ARRAY['nonadmin owner','owner isolation','no folder archive escalation','EN_REVISION rejection','CAS',
    'idempotence','payload conflict','archive list','readonly','Files recover','expense preserved','immutable version preserved','state preserved','replay after recovery'],
   'cleanup','ROLLBACK all new fixtures and temporary grants')::text,true);
END;
$test$;
SELECT current_setting('codex.archive_test_result')::jsonb AS controlled_archive_test;
ROLLBACK;
