DO $$
DECLARE
    v_result text;
    v_next_status text;
    v_count bigint;
    v_state text;
    v_tx_status text;
    v_claim_status text;
    v_gateway_sequence integer[];
    v_nonce_count bigint;
    v_confirmation_deadline timestamptz;
    base_time timestamptz := clock_timestamp();
BEGIN
    DELETE FROM outbox_events;
    DELETE FROM interaction_sightings
     WHERE interaction_id IN (
        'cccccccc-cccc-cccc-cccc-ccccccccccc1',
        'cccccccc-cccc-cccc-cccc-ccccccccccc2'
     );
    UPDATE interaction_requests
       SET state = 'claimed', expires_at = base_time + interval '60 seconds'
     WHERE interaction_id IN (
        'cccccccc-cccc-cccc-cccc-ccccccccccc1',
        'cccccccc-cccc-cccc-cccc-ccccccccccc2'
     );
    UPDATE interaction_claims
       SET status = 'active', attempt_count = 1,
           lease_expires_at = base_time + interval '10 seconds'
     WHERE claim_id IN (
        'dddddddd-dddd-dddd-dddd-ddddddddddd1',
        'dddddddd-dddd-dddd-dddd-ddddddddddd2'
     );
    UPDATE transaction_intents
       SET status = 'claimed', confirmation_expires_at = NULL, updated_at = base_time
     WHERE transaction_id IN (
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2'
     );

    INSERT INTO interaction_sightings (
        interaction_id, gateway_id, tenant_id, site_id, rssi,
        received_at, gateway_observed_at
    ) VALUES
        ('cccccccc-cccc-cccc-cccc-ccccccccccc2',
         '77777777-7777-7777-7777-777777777772',
         '11111111-1111-1111-1111-111111111111',
         '22222222-2222-2222-2222-222222222222', -40, base_time, base_time),
        ('cccccccc-cccc-cccc-cccc-ccccccccccc2',
         '77777777-7777-7777-7777-777777777771',
         '11111111-1111-1111-1111-111111111111',
         '22222222-2222-2222-2222-222222222222', -70, base_time, base_time);

    SELECT result INTO v_result
      FROM smartband_start_radio_dispatch(
          decode('00000000000000e2', 'hex'),
          '13131313-1313-4313-8313-131313131311',
          decode('0102030405060708', 'hex'), 7, decode('deadbeef', 'hex'), base_time
      );
    IF v_result <> 'started' THEN
        RAISE EXCEPTION 'dispatch did not start: %', v_result;
    END IF;

    UPDATE radio_dispatch_attempts
       SET worker_id = '14141414-1414-4414-8414-141414141414',
           work_lease_expires_at = dispatch_deadline
     WHERE dispatch_id = '13131313-1313-4313-8313-131313131311';
    SELECT result, next_status INTO v_result, v_next_status
      FROM smartband_finish_radio_dispatch(
          '13131313-1313-4313-8313-131313131311',
          'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2', 1::smallint,
          decode('0102030405060708', 'hex'),
          '14141414-1414-4414-8414-141414141414',
          'failed', 'connect_failed', base_time + interval '1 second',
          '13131313-1313-4313-8313-131313131312',
          decode('1112131415161718', 'hex')
      );
    IF v_result <> 'accepted' OR v_next_status <> 'pending' THEN
        RAISE EXCEPTION 'first retry failed: %, %', v_result, v_next_status;
    END IF;

    UPDATE radio_dispatch_attempts
       SET worker_id = '14141414-1414-4414-8414-141414141414',
           work_lease_expires_at = dispatch_deadline
     WHERE dispatch_id = '13131313-1313-4313-8313-131313131312';
    SELECT result, next_status INTO v_result, v_next_status
      FROM smartband_finish_radio_dispatch(
          '13131313-1313-4313-8313-131313131312',
          'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2', 2::smallint,
          decode('1112131415161718', 'hex'),
          '14141414-1414-4414-8414-141414141414',
          'failed', 'write_not_confirmed', base_time + interval '2 seconds',
          '13131313-1313-4313-8313-131313131313',
          decode('2122232425262728', 'hex')
      );
    IF v_result <> 'accepted' OR v_next_status <> 'pending' THEN
        RAISE EXCEPTION 'second retry failed: %, %', v_result, v_next_status;
    END IF;

    UPDATE radio_dispatch_attempts
       SET worker_id = '14141414-1414-4414-8414-141414141414',
           work_lease_expires_at = dispatch_deadline
     WHERE dispatch_id = '13131313-1313-4313-8313-131313131313';
    SELECT result, next_status INTO v_result, v_next_status
      FROM smartband_finish_radio_dispatch(
          '13131313-1313-4313-8313-131313131313',
          'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2', 3::smallint,
          decode('2122232425262728', 'hex'),
          '14141414-1414-4414-8414-141414141414',
          'failed', 'gateway_offline', base_time + interval '3 seconds',
          '13131313-1313-4313-8313-131313131314',
          decode('3132333435363738', 'hex')
      );
    IF v_result <> 'accepted' OR v_next_status <> 'exhausted' THEN
        RAISE EXCEPTION 'third retry did not exhaust: %, %', v_result, v_next_status;
    END IF;

    SELECT array_agg(g.protocol_id ORDER BY d.attempt),
           count(DISTINCT encode(d.challenge_nonce, 'hex'))
      INTO v_gateway_sequence, v_nonce_count
      FROM radio_dispatch_attempts d
      JOIN gateways g ON g.gateway_id = d.radio_gateway_id
     WHERE d.transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2';
    IF v_gateway_sequence <> ARRAY[2,1,2] OR v_nonce_count <> 3 THEN
        RAISE EXCEPTION 'radio preference/reuse/nonce invariant failed: %, %',
            v_gateway_sequence, v_nonce_count;
    END IF;

    SELECT i.state, t.status, c.status
      INTO v_state, v_tx_status, v_claim_status
      FROM interaction_requests i
      JOIN transaction_intents t USING (interaction_id)
      JOIN interaction_claims c ON c.claim_id = t.claim_id
     WHERE t.transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2';
    IF v_state <> 'expired' OR v_tx_status <> 'cancelled' OR v_claim_status <> 'expired' THEN
        RAISE EXCEPTION 'terminal states wrong: %, %, %', v_state, v_tx_status, v_claim_status;
    END IF;
    SELECT count(*) INTO v_count
      FROM credit_reservations r FULL JOIN ledger_entries l
        ON l.transaction_id = r.transaction_id
     WHERE r.transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2'
        OR l.transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'radio exhaustion touched reservation or ledger';
    END IF;
    SELECT count(*) INTO v_count FROM outbox_events
     WHERE event_type = 'radio.dispatch_failed';
    IF v_count <> 3 OR NOT EXISTS (
        SELECT 1 FROM outbox_events
         WHERE event_type = 'interaction.expired'
           AND payload #>> '{payload,reason}' = 'radio_attempts_exhausted'
    ) THEN
        RAISE EXCEPTION 'radio exhaustion events incomplete';
    END IF;

    SELECT result INTO v_result
      FROM smartband_finish_radio_dispatch(
          '13131313-1313-4313-8313-131313131311',
          'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2', 1::smallint,
          decode('0102030405060708', 'hex'),
          '14141414-1414-4414-8414-141414141414',
          'delivered', NULL, base_time + interval '4 seconds',
          '13131313-1313-4313-8313-131313131315',
          decode('4142434445464748', 'hex')
      );
    IF v_result <> 'stale' THEN
        RAISE EXCEPTION 'late result advanced state: %', v_result;
    END IF;
    SELECT result INTO v_result
      FROM smartband_finish_radio_dispatch(
          '13131313-1313-4313-8313-131313131313',
          'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2', 3::smallint,
          decode('2122232425262728', 'hex'),
          '14141414-1414-4414-8414-141414141414',
          'failed', 'gateway_offline', base_time + interval '4 seconds',
          '13131313-1313-4313-8313-131313131316',
          decode('5152535455565758', 'hex')
      );
    IF v_result <> 'duplicate' THEN
        RAISE EXCEPTION 'duplicate result not classified: %', v_result;
    END IF;

    -- Only a stale sighting exists, so no I/O-capable attempt may be created.
    INSERT INTO interaction_sightings (
        interaction_id, gateway_id, tenant_id, site_id, rssi,
        received_at, gateway_observed_at
    ) VALUES (
        'cccccccc-cccc-cccc-cccc-ccccccccccc1',
        '77777777-7777-7777-7777-777777777772',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        -30, base_time - interval '11 seconds', base_time
    );
    SELECT result, status INTO v_result, v_state
      FROM smartband_start_radio_dispatch(
          decode('00000000000000e1', 'hex'),
          '15151515-1515-4515-8515-151515151511',
          decode('6162636465666768', 'hex'), 9, decode('cafe', 'hex'), base_time
      );
    IF v_result <> 'started' OR v_state <> 'waiting_for_radio' THEN
        RAISE EXCEPTION 'stale radio was selected: %, %', v_result, v_state;
    END IF;
    PERFORM smartband_promote_waiting_radio(base_time + interval '1 second');
    IF EXISTS (
        SELECT 1 FROM radio_dispatch_attempts
         WHERE dispatch_id = '15151515-1515-4515-8515-151515151511'
           AND status <> 'waiting_for_radio'
    ) THEN
        RAISE EXCEPTION 'waiting dispatch performed stale selection';
    END IF;

    INSERT INTO interaction_sightings (
        interaction_id, gateway_id, tenant_id, site_id, rssi,
        received_at, gateway_observed_at
    ) VALUES (
        'cccccccc-cccc-cccc-cccc-ccccccccccc1',
        '77777777-7777-7777-7777-777777777771',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        -50, base_time + interval '2 seconds', base_time + interval '2 seconds'
    );
    PERFORM smartband_promote_waiting_radio(base_time + interval '2 seconds');
    UPDATE radio_dispatch_attempts
       SET worker_id = '16161616-1616-4616-8616-161616161616',
           work_lease_expires_at = dispatch_deadline
     WHERE dispatch_id = '15151515-1515-4515-8515-151515151511';
    SELECT result INTO v_result
      FROM smartband_finish_radio_dispatch(
          '15151515-1515-4515-8515-151515151511',
          'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1', 1::smallint,
          decode('6162636465666768', 'hex'),
          '16161616-1616-4616-8616-161616161616',
          'delivered', NULL, base_time + interval '3 seconds',
          '15151515-1515-4515-8515-151515151512',
          decode('7172737475767778', 'hex')
      );
    SELECT status, confirmation_expires_at INTO v_tx_status, v_confirmation_deadline
      FROM transaction_intents
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    IF v_result <> 'accepted' OR v_tx_status <> 'awaiting_band_confirmation'
       OR v_confirmation_deadline <> base_time + interval '13 seconds' THEN
        RAISE EXCEPTION 'delivered transition failed: %, %, %',
            v_result, v_tx_status, v_confirmation_deadline;
    END IF;

    -- Expiring the persisted no-radio window consumes exactly one attempt.
    DELETE FROM radio_dispatch_result_audit
     WHERE dispatch_id IN (
        SELECT dispatch_id FROM radio_dispatch_attempts
         WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1'
     );
    DELETE FROM radio_dispatch_attempts
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    DELETE FROM interaction_sightings
     WHERE interaction_id = 'cccccccc-cccc-cccc-cccc-ccccccccccc1';
    UPDATE interaction_requests SET state = 'claimed'
     WHERE interaction_id = 'cccccccc-cccc-cccc-cccc-ccccccccccc1';
    UPDATE interaction_claims
       SET status = 'active', attempt_count = 1,
           lease_expires_at = base_time + interval '30 seconds'
     WHERE claim_id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1';
    UPDATE transaction_intents
       SET status = 'claimed', confirmation_expires_at = NULL, updated_at = base_time
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    PERFORM smartband_start_radio_dispatch(
        decode('00000000000000e1', 'hex'),
        '20202020-2020-4020-8020-202020202021',
        decode('8182838485868788', 'hex'), 9, decode('cafe', 'hex'),
        base_time + interval '20 seconds'
    );
    SELECT result, next_status INTO v_result, v_next_status
      FROM smartband_finish_radio_dispatch(
          '20202020-2020-4020-8020-202020202021',
          'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1', 1::smallint,
          decode('8182838485868788', 'hex'), NULL,
          'failed', 'no_radio_gateway', base_time + interval '30 seconds',
          '20202020-2020-4020-8020-202020202022',
          decode('9192939495969798', 'hex')
      );
    IF v_result <> 'accepted' OR v_next_status <> 'waiting_for_radio'
       OR NOT EXISTS (
           SELECT 1 FROM radio_dispatch_attempts
            WHERE dispatch_id = '20202020-2020-4020-8020-202020202021'
              AND status = 'failed' AND failure_kind = 'no_radio_gateway'
       ) THEN
        RAISE EXCEPTION 'waiting_for_radio expiration failed: %, %',
            v_result, v_next_status;
    END IF;

    -- With one eligible gateway, retry is allowed to reuse that same radio.
    DELETE FROM radio_dispatch_result_audit
     WHERE dispatch_id IN (
        SELECT dispatch_id FROM radio_dispatch_attempts
         WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1'
     );
    DELETE FROM radio_dispatch_attempts
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    UPDATE interaction_claims
       SET attempt_count = 1, lease_expires_at = base_time + interval '50 seconds'
     WHERE claim_id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1';
    INSERT INTO interaction_sightings (
        interaction_id, gateway_id, tenant_id, site_id, rssi,
        received_at, gateway_observed_at
    ) VALUES (
        'cccccccc-cccc-cccc-cccc-ccccccccccc1',
        '77777777-7777-7777-7777-777777777771',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        -45, base_time + interval '40 seconds', base_time + interval '40 seconds'
    );
    PERFORM smartband_start_radio_dispatch(
        decode('00000000000000e1', 'hex'),
        '21212121-2121-4121-8121-212121212121',
        decode('a1a2a3a4a5a6a7a8', 'hex'), 9, decode('babe', 'hex'),
        base_time + interval '40 seconds'
    );
    UPDATE radio_dispatch_attempts
       SET worker_id = '22222222-2222-4222-8222-222222222222',
           work_lease_expires_at = dispatch_deadline
     WHERE dispatch_id = '21212121-2121-4121-8121-212121212121';
    PERFORM smartband_finish_radio_dispatch(
        '21212121-2121-4121-8121-212121212121',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1', 1::smallint,
        decode('a1a2a3a4a5a6a7a8', 'hex'),
        '22222222-2222-4222-8222-222222222222',
        'failed', 'connect_failed', base_time + interval '41 seconds',
        '21212121-2121-4121-8121-212121212122',
        decode('b1b2b3b4b5b6b7b8', 'hex')
    );
    SELECT array_agg(g.protocol_id ORDER BY d.attempt)
      INTO v_gateway_sequence
      FROM radio_dispatch_attempts d
      JOIN gateways g ON g.gateway_id = d.radio_gateway_id
     WHERE d.transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    IF v_gateway_sequence <> ARRAY[1,1] THEN
        RAISE EXCEPTION 'single eligible radio was not reused: %', v_gateway_sequence;
    END IF;
END;
$$;
