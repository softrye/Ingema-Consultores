DO $patch$
DECLARE source text; needle text := '    RETURN QUERY SELECT v_attachment.id, v_attachment.storage_bucket,';
BEGIN
SELECT pg_get_functiondef('public.reserve_rendition_attachment_v01(uuid,uuid,uuid,text,text,bigint,text,text)'::regprocedure) INTO source;
IF position('RENDITION_ATTACHMENT_RENEWAL_V01' in source)>0 THEN RETURN; END IF;
IF position(needle in source)=0 THEN RAISE EXCEPTION 'Reservation contract changed'; END IF;
source := replace(source, needle, $insert$
    -- RENDITION_ATTACHMENT_RENEWAL_V01: renew the original identity and object.
    IF v_attachment.status = 'RESERVED'
       AND v_attachment.reservation_expires_at <= v_now + interval '1 minute' THEN
      PERFORM 1 FROM public.renditions AS owned
        WHERE owned.id = p_rendition_id AND owned.owner_user_id = v_actor
          AND owned.archived_at IS NULL AND owned.status = 'BORRADOR'
          AND owned.current_version_id IS NULL FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='RENDITION_NOT_EDITABLE'; END IF;
      IF NOT EXISTS (SELECT 1 FROM public.rendition_expenses AS expense
        WHERE expense.id=p_expense_id AND expense.rendition_id=p_rendition_id
          AND expense.archived_at IS NULL) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='RENDITION_EXPENSE_NOT_FOUND_OR_FORBIDDEN';
      END IF;
      UPDATE public.rendition_expense_attachments AS attachment
        SET reservation_expires_at = pg_catalog.clock_timestamp() + interval '15 minutes'
        WHERE attachment.id=v_attachment.id AND attachment.actor_user_id=v_actor
          AND attachment.status='RESERVED';
      SELECT attachment.* INTO v_attachment
        FROM public.rendition_expense_attachments AS attachment WHERE attachment.id=v_attachment.id;
    END IF;
    RETURN QUERY SELECT v_attachment.id, v_attachment.storage_bucket,$insert$);
EXECUTE source;
END $patch$;
