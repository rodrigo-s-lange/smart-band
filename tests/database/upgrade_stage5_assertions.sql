DO $$
DECLARE
    next_protocol_id bigint;
    existing_max bigint;
BEGIN
    SELECT max(protocol_id) INTO existing_max FROM interaction_requests;
    INSERT INTO interaction_requests (
        tenant_id, site_id, event_id, band_id, session_nonce, display_code,
        protocol_version, state, first_authenticated_at, expires_at
    )
    SELECT tenant_id, site_id, event_id, band_id, decode('8888888888888888', 'hex'),
           '000-001', 1, 'expired', now(), now() + interval '60 seconds'
      FROM interaction_requests
     LIMIT 1
    RETURNING protocol_id INTO next_protocol_id;

    IF next_protocol_id <= existing_max THEN
        RAISE EXCEPTION 'interaction protocol sequence did not advance: % <= %',
            next_protocol_id, existing_max;
    END IF;
    IF EXISTS (SELECT 1 FROM outbox_events WHERE stream_sequence IS NULL) THEN
        RAISE EXCEPTION 'outbox stream sequence backfill failed';
    END IF;
END;
$$;
