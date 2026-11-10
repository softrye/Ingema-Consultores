-- InGePlus-Dev only. Read existing data under authenticated; all temp state rolls back.
-- Requires existing archived and trashed renditions with nonempty display_name.
BEGIN;
CREATE TEMP TABLE name_test_actors AS
 SELECT id FROM public.profiles WHERE status='ACTIVO';
CREATE TEMP TABLE name_test_nodes AS
 SELECT n.id,n.name,n.node_kind::text AS kind,r.display_name,r.owner_user_id,
        t.effective_lifecycle AS lifecycle
 FROM public.document_nodes n
 JOIN private.files_recovery_tree_v07() t ON t.id=n.id
 LEFT JOIN public.document_smart_bindings b ON b.node_id=n.id
   AND n.node_kind='SMART_DOCUMENT' AND b.target_type='RENDITION'
 LEFT JOIN public.renditions r ON r.id=COALESCE(b.rendition_id,b.target_id);
CREATE TEMP TABLE name_test_context_access(actor uuid,node uuid,allowed boolean);
DO $setup$
DECLARE actor record;
BEGIN
 FOR actor IN SELECT id FROM name_test_actors LOOP
  PERFORM set_config('request.jwt.claim.sub',actor.id::text,true);
  INSERT INTO name_test_context_access
  SELECT actor.id,n.id,n.lifecycle='ARCHIVED' AND n.kind IN('SMART_DOCUMENT','BINARY_DOCUMENT')
    AND (private.files_archive_authority_v07() OR private.rendition_owned_archived_file_v01(actor.id,n.id))
    AND private.files_recovery_access_v07(n.id)
  FROM name_test_nodes n;
 END LOOP;
END $setup$;
GRANT SELECT ON name_test_actors,name_test_nodes,name_test_context_access TO authenticated;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE actor record; expected record; result jsonb; item jsonb; parent uuid;
 queue uuid[]; visited uuid[]; mode text; context_count integer:=0; denied_count integer:=0;
 archive_names integer:=0; trash_names integer:=0; owner_count integer:=0;
BEGIN
 IF current_user<>'authenticated' THEN RAISE EXCEPTION 'TEST_ROLE_REQUIRED'; END IF;
 FOR actor IN SELECT id FROM name_test_actors LOOP
  PERFORM set_config('request.jwt.claim.sub',actor.id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.id,'role','authenticated')::text,true);
  FOR expected IN SELECT n.*,a.allowed FROM name_test_nodes n
   JOIN name_test_context_access a ON a.node=n.id AND a.actor=actor.id LOOP
   BEGIN
    result:=public.get_my_archived_document_context_v07(expected.id);
    IF NOT expected.allowed THEN RAISE EXCEPTION 'TEST_CONTEXT_ACCESS_LEAK'; END IF;
    IF result->>'name' IS DISTINCT FROM expected.name THEN RAISE EXCEPTION 'TEST_NODE_NAME_CHANGED'; END IF;
    IF result->>'display_name' IS DISTINCT FROM expected.display_name THEN RAISE EXCEPTION 'TEST_CONTEXT_DISPLAY_NAME'; END IF;
    context_count:=context_count+1;
    IF actor.id=expected.owner_user_id THEN owner_count:=owner_count+1; END IF;
   EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ARCHIVE_FORBIDDEN' OR expected.allowed THEN RAISE; END IF;
    denied_count:=denied_count+1;
   END;
  END LOOP;
  FOREACH mode IN ARRAY ARRAY['archive','trash'] LOOP
   queue:=ARRAY[NULL::uuid]; visited:=ARRAY[]::uuid[];
   WHILE cardinality(queue)>0 LOOP
    parent:=queue[1]; queue:=queue[2:];
    result:=CASE mode WHEN 'archive' THEN public.list_files_archive_children_v07(parent,NULL,200)
      ELSE public.list_files_trash_children_v07(parent,NULL,200) END;
    IF (result->>'has_more')::boolean THEN RAISE EXCEPTION 'TEST_FIXTURE_EXCEEDS_PAGE'; END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(result->'items') LOOP
     SELECT * INTO expected FROM name_test_nodes WHERE id=(item->>'id')::uuid;
     IF FOUND THEN
      IF item->>'name' IS DISTINCT FROM expected.name THEN RAISE EXCEPTION 'TEST_LIST_NODE_NAME_CHANGED'; END IF;
      IF item->>'display_name' IS DISTINCT FROM expected.display_name THEN
       RAISE EXCEPTION 'TEST_LIST_DISPLAY_NAME_%',mode;
      END IF;
      IF nullif(expected.display_name,'') IS NOT NULL THEN
       IF mode='archive' THEN archive_names:=archive_names+1; ELSE trash_names:=trash_names+1; END IF;
      END IF;
     ELSIF item->>'display_name' IS NOT NULL THEN RAISE EXCEPTION 'TEST_NON_RENDITION_NAME_LEAK';
     END IF;
     IF (item->>'can_browse')::boolean AND NOT (item->>'id')::uuid=ANY(visited) THEN
      queue:=array_append(queue,(item->>'id')::uuid);
      visited:=array_append(visited,(item->>'id')::uuid);
     END IF;
    END LOOP;
   END LOOP;
  END LOOP;
 END LOOP;
 IF context_count=0 OR owner_count=0 OR denied_count=0 OR archive_names=0 OR trash_names=0 THEN
  RAISE EXCEPTION 'TEST_INSUFFICIENT_COVERAGE contexts %, owners %, denied %, archive %, trash %',
   context_count,owner_count,denied_count,archive_names,trash_names;
 END IF;
 PERFORM set_config('inge.test.files_names',jsonb_build_object('role',current_user,
  'contexts',context_count,'owner_contexts',owner_count,'denied',denied_count,
  'archive_names',archive_names,'trash_names',trash_names)::text,true);
END $test$;
SELECT current_setting('inge.test.files_names')::jsonb AS test_results;
ROLLBACK;
