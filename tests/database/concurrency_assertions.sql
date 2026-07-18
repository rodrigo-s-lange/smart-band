DO $$
DECLARE
    v_active_reservations bigint;
    v_reserved_transactions bigint;
    v_balance bigint;
BEGIN
    SELECT count(*) INTO v_active_reservations
      FROM credit_reservations
     WHERE wallet_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       AND status = 'active';
    SELECT count(*) INTO v_reserved_transactions
      FROM transaction_intents
     WHERE transaction_id IN (
         'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1',
         'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2'
     ) AND status = 'credit_reserved';
    SELECT current_balance INTO v_balance
      FROM wallets WHERE wallet_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

    IF v_active_reservations <> 1 OR v_reserved_transactions <> 1 OR v_balance <> 100 THEN
        RAISE EXCEPTION 'concurrent reservation failed: reservations %, transactions %, balance %',
            v_active_reservations, v_reserved_transactions, v_balance;
    END IF;
END;
$$;
