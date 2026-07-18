SELECT smartband_reserve_credit('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1');
SELECT smartband_dispatch_actuation(
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1',
    'ffffffff-ffff-ffff-ffff-fffffffffff1'
);
SELECT smartband_record_actuation_ack(
    'ffffffff-ffff-ffff-ffff-fffffffffff1', 'ambiguous'
);

DO $$
DECLARE
    v_balance bigint;
    v_debits bigint;
    v_reservation_status text;
    v_transaction_status text;
BEGIN
    SELECT current_balance INTO v_balance FROM wallets
     WHERE wallet_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    SELECT count(*) INTO v_debits FROM ledger_entries WHERE entry_kind = 'debit';
    SELECT status INTO v_reservation_status FROM credit_reservations
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    SELECT status INTO v_transaction_status FROM transaction_intents
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    IF v_balance <> 100 OR v_debits <> 0 OR v_reservation_status <> 'active'
       OR v_transaction_status <> 'reconciliation_required' THEN
        RAISE EXCEPTION 'ambiguous ack safety failed: balance %, debits %, reservation %, transaction %',
            v_balance, v_debits, v_reservation_status, v_transaction_status;
    END IF;
END;
$$;
