BEGIN;
-- One SQL statement / MVCC snapshot. Existing table RLS and lab authorization
-- remain authoritative; no new write privilege or SECURITY DEFINER is needed.
CREATE OR REPLACE FUNCTION public.get_my_calicata_snapshot_v01(p_project_id uuid,p_calicata_id uuid)
RETURNS TABLE(calicata jsonb,project jsonb,strata jsonb,samples jsonb,labs jsonb)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
 SELECT to_jsonb(c),jsonb_build_object('id',p.id,'code',p.code,'name',p.name),
   coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.sequence_number)
     FROM public.calicata_strata s WHERE s.calicata_id=c.id),'[]'::jsonb),
   coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.created_at,s.id)
     FROM public.calicata_samples s WHERE s.calicata_id=c.id),'[]'::jsonb),
   coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.stratum_id)
     FROM public.get_my_calicata_lab_results_v01(c.project_id,c.id) l),'[]'::jsonb)
 FROM public.calicatas c JOIN public.projects p ON p.id=c.project_id
 WHERE auth.uid() IS NOT NULL AND c.id=p_calicata_id AND c.project_id=p_project_id;
$fn$;
REVOKE ALL ON FUNCTION public.get_my_calicata_snapshot_v01(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_my_calicata_snapshot_v01(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
