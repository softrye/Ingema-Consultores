BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"d043f2a5-5210-4cf1-ac62-6f22b6487e73","role":"authenticated"}',true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE c public.calicatas%ROWTYPE; s public.calicata_strata%ROWTYPE;
  snap record; r record; sample public.calicata_samples%ROWTYPE; lab public.calicata_lab_results%ROWTYPE;
  before_version bigint; v bigint; n integer;
BEGIN
  SELECT * INTO STRICT snap FROM public.get_my_calicata_snapshot_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4');
  SELECT * INTO STRICT c FROM public.calicatas WHERE id=(snap.calicata->>'id')::uuid;
  before_version:=c.row_version;
  IF jsonb_array_length(snap.strata)<>3 OR jsonb_array_length(snap.samples)<>2 THEN
    RAISE EXCEPTION 'real fixture changed: inspect before testing';
  END IF;
  UPDATE public.calicatas SET observations=coalesce(c.observations,'')||' [transactional Android test]'
    WHERE id=c.id AND project_id=c.project_id AND row_version=before_version RETURNING row_version INTO v;
  IF v IS DISTINCT FROM before_version+1 THEN RAISE EXCEPTION 'root CAS failed'; END IF;
  -- Competing save using the same baseline must fail, never silently overwrite.
  UPDATE public.calicatas SET observations='must not be written' WHERE id=c.id AND row_version=before_version;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>0 THEN RAISE EXCEPTION 'stale root accepted'; END IF;
  FOR s IN SELECT * FROM public.calicata_strata WHERE calicata_id=c.id ORDER BY sequence_number LOOP
    SELECT * INTO STRICT r FROM public.update_my_calicata_stratum_v03(c.project_id,c.id,s.id,v,
      s.to_depth_m,s.description,s.moisture_condition,s.consistency_compaction,s.excavability,s.color,s.sample_type,s.observations);
    IF r.calicata_row_version<>v+1 THEN RAISE EXCEPTION 'stratum revision mismatch'; END IF;
    v:=r.calicata_row_version;
  END LOOP;
  FOR sample IN SELECT * FROM public.calicata_samples WHERE calicata_id=c.id LOOP
    SELECT * INTO STRICT r FROM public.update_my_calicata_sample_v01(c.project_id,c.id,sample.stratum_id,
      sample.id,v,sample.sample_code,sample.sample_type,sample.from_depth_m,sample.to_depth_m);
    IF r.calicata_row_version<>v+1 THEN RAISE EXCEPTION 'sample revision mismatch'; END IF;
    v:=r.calicata_row_version;
  END LOOP;
  FOR lab IN SELECT * FROM public.get_my_calicata_lab_results_v01(c.project_id,c.id) LOOP
    SELECT * INTO STRICT r FROM public.upsert_my_calicata_lab_result_v02(c.project_id,c.id,lab.stratum_id,v,
      lab.sieve_max_pct,lab.sieve_no4_pct,lab.sieve_2mm_pct,lab.sieve_04mm_pct,lab.sieve_008mm_pct,
      lab.liquid_limit,lab.plastic_limit,lab.natural_moisture_pct,lab.primary_sucs,lab.is_composite,
      lab.secondary_sucs,lab.aashto,lab.laboratory_source,lab.test_date);
    IF r.calicata_row_version<>v+1 THEN RAISE EXCEPTION 'lab revision mismatch'; END IF;
    v:=r.calicata_row_version;
  END LOOP;
  SELECT * INTO STRICT snap FROM public.get_my_calicata_snapshot_v01(c.project_id,c.id);
  IF (snap.calicata->>'row_version')::bigint<>v OR
     snap.calicata->>'observations' IS DISTINCT FROM coalesce(c.observations,'')||' [transactional Android test]' THEN
    RAISE EXCEPTION 'Web readback differs';
  END IF;
  PERFORM set_config('test.roundtrip',jsonb_build_object('before',before_version,'after_in_transaction',v,
    'root_write','PASS','stale_rejected','PASS','strata','PASS','samples','PASS','lab','PASS','web_readback','PASS','rollback',true)::text,true);
END;
$test$;
SELECT current_setting('test.roundtrip') AS result;
ROLLBACK;
