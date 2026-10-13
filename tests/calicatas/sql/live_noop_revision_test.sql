-- Prueba de servidor (DEV): un cambio live no-op NO mueve row_version.
-- Se ejecuta completa dentro de una transacción que SIEMPRE se revierte
-- (RAISE al final): crea una ficha temporal, actúa como su autor y devuelve
-- el resultado en el mensaje de error. No deja filas.
-- Ajusta v_project / v_user a un proyecto y autor con permiso de edición.
--
-- Resultado validado el 2026-10-07 tras 20261007180000_calicata_live_noop_keeps_revision:
--   start=1 | 1) live X->X rv=1 updated_at_same=t | numeric 661554->661554.00 rv=1
--   | 2) live X->Y rv=1 title=Y | live Y->Y rv=1 | full CAS save Y->Y2 rows=1 rv=2
--   | 3) autosave rows=1 rv=3 live noop rv=3 save CAS rows=1 rv=4
--   | 4) 30 rounds autosave+noop+live: last_rows=1 rv=34 | 5) stale CAS after external rows=0
-- Antes del fix: live X->X pasaba de 1 a 2 y "autosave + live no-op + save" daba
-- save CAS rows=0 (=> 40001).
do $$
declare
  v_project uuid := '7fb77795-9986-4b99-8b59-55f1266891d4';
  v_user uuid := 'bf9f0f82-10f9-4da3-bf74-cb7a3f3f755a';
  v_id uuid; v_rv bigint; v_out text := ''; v_n int; v_upd timestamptz; v_upd2 timestamptz; v_t timestamptz := now();
  v_i int;
begin
  insert into public.calicatas(project_id, code, title, easting, created_by)
  values (v_project, 'ZZ-SYNC-TEST-' || substr(gen_random_uuid()::text,1,8), 'X', 661554, v_user)
  returning id, row_version into v_id, v_rv;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  v_out := concat('start=', v_rv);
  select updated_at into v_upd from public.calicatas where id = v_id;
  perform public.apply_calicata_field_change_v02(v_project, v_id, 'CALICATA', v_id, gen_random_uuid(), 'title', 'X', v_t + interval '1 s');
  select row_version, updated_at into v_rv, v_upd2 from public.calicatas where id = v_id;
  v_out := concat(v_out, ' | 1) live X->X rv=', v_rv, ' updated_at_same=', v_upd = v_upd2);
  perform public.apply_calicata_field_change_v02(v_project, v_id, 'CALICATA', v_id, gen_random_uuid(), 'easting', '661554.00', v_t + interval '2 s');
  select row_version into v_rv from public.calicatas where id = v_id;
  v_out := concat(v_out, ' | numeric 661554->661554.00 rv=', v_rv);
  perform public.apply_calicata_field_change_v02(v_project, v_id, 'CALICATA', v_id, gen_random_uuid(), 'title', 'Y', v_t + interval '3 s');
  select row_version into v_rv from public.calicatas where id = v_id;
  v_out := concat(v_out, ' | 2) live X->Y rv=', v_rv, ' title=', (select title from public.calicatas where id = v_id));
  perform public.apply_calicata_field_change_v02(v_project, v_id, 'CALICATA', v_id, gen_random_uuid(), 'title', 'Y', v_t + interval '4 s');
  select row_version into v_rv from public.calicatas where id = v_id;
  v_out := concat(v_out, ' | live Y->Y rv=', v_rv);
  update public.calicatas set title = 'Y2' where id = v_id and row_version = v_rv returning row_version into v_rv;
  get diagnostics v_n = row_count;
  v_out := concat(v_out, ' | full CAS save Y->Y2 rows=', v_n, ' rv=', v_rv);
  update public.calicatas set title = 'Z' where id = v_id and row_version = v_rv returning row_version into v_rv;
  get diagnostics v_n = row_count;
  v_out := concat(v_out, ' | 3) autosave rows=', v_n, ' rv=', v_rv);
  perform public.apply_calicata_field_change_v02(v_project, v_id, 'CALICATA', v_id, gen_random_uuid(), 'title', 'Z', v_t + interval '5 s');
  v_out := concat(v_out, ' live noop rv=', (select row_version from public.calicatas where id = v_id));
  update public.calicatas set observations = 'save' where id = v_id and row_version = v_rv returning row_version into v_rv;
  get diagnostics v_n = row_count;
  v_out := concat(v_out, ' save CAS rows=', v_n, ' rv=', v_rv);
  for v_i in 1..30 loop
    update public.calicatas set observations = 'obs ' || v_i where id = v_id and row_version = v_rv returning row_version into v_rv;
    get diagnostics v_n = row_count; exit when v_n = 0;
    perform public.apply_calicata_field_change_v02(v_project, v_id, 'CALICATA', v_id, gen_random_uuid(), 'observations', 'obs ' || v_i, v_t + make_interval(secs => 10 + v_i * 2));
    perform public.apply_calicata_field_change_v02(v_project, v_id, 'CALICATA', v_id, gen_random_uuid(), 'title', 'T' || v_i, v_t + make_interval(secs => 11 + v_i * 2));
  end loop;
  v_out := concat(v_out, ' | 4) 30 rounds autosave+noop+live: last_rows=', v_n, ' rv=', v_rv);
  update public.calicatas set title = 'EXTERNAL' where id = v_id;
  update public.calicatas set title = 'MINE' where id = v_id and row_version = v_rv;
  get diagnostics v_n = row_count;
  v_out := concat(v_out, ' | 5) stale CAS after external rows=', v_n);
  raise exception 'TEST_RESULT %', v_out;
end $$;
