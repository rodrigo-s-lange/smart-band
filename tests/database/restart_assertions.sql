SELECT smartband_record_actuation_ack(
    'ffffffff-ffff-ffff-ffff-fffffffffff1', 'succeeded'
);

DO $$
DECLARE
    v_balance bigint;
    v_debits bigint;
    v_status text;
    v_dispatches bigint;
    v_payload text;
BEGIN
    SELECT current_balance INTO v_balance FROM wallets
     WHERE wallet_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    SELECT count(*) INTO v_debits FROM ledger_entries
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1'
       AND entry_kind = 'debit';
    SELECT status INTO v_status FROM transaction_intents
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    IF v_balance <> 20 OR v_debits <> 1 OR v_status <> 'completed' THEN
        RAISE EXCEPTION 'restart recovery failed: balance %, debits %, status %',
            v_balance, v_debits, v_status;
    END IF;
    SELECT count(*), min(encode(payload, 'hex'))
      INTO v_dispatches, v_payload
      FROM radio_dispatch_attempts
     WHERE dispatch_id = '12121212-1212-4212-8212-121212121212'
       AND status = 'pending';
    IF v_dispatches <> 1 OR v_payload <> 'deadbeef' THEN
        RAISE EXCEPTION 'persisted radio work was not recovered: count %, payload %',
            v_dispatches, v_payload;
    END IF;

    -- Leave the fixture downgrade-safe after proving the persisted work survived.
    DELETE FROM radio_dispatch_result_audit
     WHERE dispatch_id = '12121212-1212-4212-8212-121212121212';
    DELETE FROM radio_dispatch_attempts
     WHERE dispatch_id = '12121212-1212-4212-8212-121212121212';
    UPDATE transaction_intents SET status = 'cancelled', updated_at = now()
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2';
    UPDATE interaction_requests SET state = 'expired'
     WHERE interaction_id = 'cccccccc-cccc-cccc-cccc-ccccccccccc2';
    UPDATE interaction_claims SET status = 'expired'
     WHERE claim_id = 'dddddddd-dddd-dddd-dddd-ddddddddddd2';
END;
$$;
