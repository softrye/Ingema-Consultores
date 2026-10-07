-- Calicatas FIELD binding must cooperate with the existing invariants trigger:
-- it increments node_version before the context trigger and requires updated_by.
-- Only the guarded FIELD transition is changed; no data rewrite or ACL changes.
BEGIN;
DO $patch$
DECLARE
  v_fn regprocedure := 'private.enforce_document_node_structural_context_v01()'::regprocedure;
  v_def text := pg_catalog.pg_get_functiondef(v_fn);
  v_old constant text := $old$AND (pg_catalog.to_jsonb(NEW) - 'structural_context')
        = (pg_catalog.to_jsonb(OLD) - 'structural_context')$old$;
  v_new constant text := $new$-- CALICATAS-FIELD-ACTOR-VERSION: metadata required by the preceding trigger.
      AND NEW.updated_by = auth.uid()
      AND NEW.node_version = OLD.node_version + 1
      AND (pg_catalog.to_jsonb(NEW) - ARRAY['structural_context', 'node_version', 'updated_by']::text[])
        = (pg_catalog.to_jsonb(OLD) - ARRAY['structural_context', 'node_version', 'updated_by']::text[])$new$;
BEGIN
  IF pg_catalog.strpos(v_def, 'CALICATAS-FIELD-ACTOR-VERSION') = 0 THEN
    IF pg_catalog.strpos(v_def, 'CALICATAS-FIELD-06-GABINETE') = 0
       OR (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, '')))
          / pg_catalog.length(v_old) <> 1 THEN
      RAISE EXCEPTION 'CALICATAS_FIELD_PATCH: guarded transition drifted';
    END IF;
    EXECUTE pg_catalog.replace(v_def, v_old, v_new);
  END IF;

  v_fn := 'public.ensure_calicata_field_folder_v01(uuid)'::regprocedure;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  IF pg_catalog.strpos(v_def, 'SET structural_context = ''FIELD''::public.document_structural_context, updated_by = v_actor_id') = 0 THEN
    IF (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def,
       'SET structural_context = ''FIELD''::public.document_structural_context', '')))
       / pg_catalog.length('SET structural_context = ''FIELD''::public.document_structural_context') <> 1 THEN
      RAISE EXCEPTION 'CALICATAS_FIELD_PATCH: RPC binding update drifted';
    END IF;
    EXECUTE pg_catalog.replace(v_def,
      'SET structural_context = ''FIELD''::public.document_structural_context',
      'SET structural_context = ''FIELD''::public.document_structural_context, updated_by = v_actor_id');
  END IF;
END;
$patch$;
NOTIFY pgrst, 'reload schema';
COMMIT;
