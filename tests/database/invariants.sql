DO $$
BEGIN
    BEGIN
        INSERT INTO appliance_configuration (
            singleton_id, tenant_id, site_id, appliance_name
        ) VALUES (
            2, '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222', 'segunda-appliance'
        );
        RAISE EXCEPTION 'singleton constraint was not enforced';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO events (
            tenant_id, site_id, code, display_name, status
        ) VALUES (
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222',
            'evento-ativo-duplicado', 'Evento ativo duplicado', 'active'
        );
        RAISE EXCEPTION 'one-active-event constraint was not enforced';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

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
        RAISE EXCEPTION 'one-active-interaction constraint was not enforced';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    UPDATE interaction_requests SET state = 'expired'
     WHERE interaction_id = 'cccccccc-cccc-cccc-cccc-ccccccccccc1';
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
            decode('0102030405060708', 'hex'), 'Q2R-6TZ', 1, 'expired',
            now(), now() + interval '60 seconds', 104
        );
        RAISE EXCEPTION 'durable band nonce constraint was not enforced';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    UPDATE interaction_requests SET state = 'confirmed_pending_validation'
     WHERE interaction_id = 'cccccccc-cccc-cccc-cccc-ccccccccccc1';

    BEGIN
        INSERT INTO interaction_claims (
            interaction_id, operator_gateway_id, attraction_id,
            tenant_id, site_id, lease_expires_at
        ) VALUES (
            'cccccccc-cccc-cccc-cccc-ccccccccccc1',
            '77777777-7777-7777-7777-777777777771',
            '88888888-8888-8888-8888-888888888888',
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222', now() + interval '30 seconds'
        );
        RAISE EXCEPTION 'one-active-claim constraint was not enforced';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
END;
$$;

SELECT smartband_reserve_credit('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1');

SELECT smartband_dispatch_actuation(
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1',
    'ffffffff-ffff-ffff-ffff-fffffffffff1'
);

SELECT smartband_record_actuation_ack(
    'ffffffff-ffff-ffff-ffff-fffffffffff1', 'succeeded'
);
SELECT smartband_record_actuation_ack(
    'ffffffff-ffff-ffff-ffff-fffffffffff1', 'succeeded'
);

DO $$
DECLARE
    v_balance bigint;
    v_debits bigint;
BEGIN
    SELECT current_balance INTO v_balance FROM wallets
     WHERE wallet_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    SELECT count(*) INTO v_debits FROM ledger_entries
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1'
       AND entry_kind = 'debit';
    IF v_balance <> 20 OR v_debits <> 1 THEN
        RAISE EXCEPTION 'ack idempotency failed: balance %, debits %', v_balance, v_debits;
    END IF;

    BEGIN
        UPDATE ledger_entries SET reason = 'mutação proibida'
         WHERE ledger_entry_id = 'abababab-abab-abab-abab-abababababab';
        RAISE EXCEPTION 'append-only ledger trigger was not enforced';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
END;
$$;
