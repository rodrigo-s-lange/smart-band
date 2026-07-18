SELECT smartband_reserve_credit('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1');
SELECT smartband_dispatch_actuation(
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1',
    'ffffffff-ffff-ffff-ffff-fffffffffff1'
);
SELECT smartband_record_actuation_ack(
    'ffffffff-ffff-ffff-ffff-fffffffffff1', 'not_executed'
);

DO $$
DECLARE
    v_interaction_state text;
    v_transaction_state text;
BEGIN
    SELECT state INTO v_interaction_state
      FROM interaction_requests
     WHERE interaction_id = 'cccccccc-cccc-cccc-cccc-ccccccccccc1';
    SELECT status INTO v_transaction_state
      FROM transaction_intents
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';

    IF v_interaction_state <> 'actuation_failed'
       OR v_transaction_state <> 'actuation_failed' THEN
        RAISE EXCEPTION
            'fixture did not reach actuation_failed: interaction %, transaction %',
            v_interaction_state, v_transaction_state;
    END IF;

    BEGIN
        INSERT INTO interaction_requests (
            tenant_id, site_id, event_id, band_id, session_nonce, display_code,
            protocol_version, state, first_authenticated_at, expires_at,
            protocol_id
        ) VALUES (
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222',
            '33333333-3333-3333-3333-333333333333',
            '66666666-6666-6666-6666-666666666661',
            decode('2122232425262728', 'hex'), 'P9N-5RY', 1, 'queued',
            now(), now() + interval '60 seconds', 103
        );
        RAISE EXCEPTION
            'actuation_failed did not block a second active interaction';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    BEGIN
        PERFORM smartband_record_authenticated_sighting(
            '77777777-7777-7777-7777-777777777771',
            '66666666-6666-6666-6666-666666666661',
            decode('3132333435363738', 'hex'),
            'Q2R-6TZ', 1::smallint, 60::smallint, -45::smallint, now(), now()
        );
        RAISE EXCEPTION
            'authenticated ingestion accepted a second active interaction';
    EXCEPTION WHEN unique_violation THEN
        IF SQLERRM <> 'band already has an active interaction' THEN
            RAISE EXCEPTION 'unexpected ingestion error: %', SQLERRM;
        END IF;
    END;
END;
$$;
