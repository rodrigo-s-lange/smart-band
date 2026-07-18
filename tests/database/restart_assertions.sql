SELECT smartband_record_actuation_ack(
    'ffffffff-ffff-ffff-ffff-fffffffffff1', 'succeeded'
);

DO $$
DECLARE
    v_balance bigint;
    v_debits bigint;
    v_status text;
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
END;
$$;
