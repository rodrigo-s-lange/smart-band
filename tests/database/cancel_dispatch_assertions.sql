DO $$
DECLARE
    v_transaction_status text;
    v_reservation_status text;
    v_commands bigint;
BEGIN
    SELECT status INTO v_transaction_status FROM transaction_intents
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    SELECT status INTO v_reservation_status FROM credit_reservations
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';
    SELECT count(*) INTO v_commands FROM actuation_commands
     WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1';

    IF NOT (
        (v_transaction_status = 'cancelled' AND v_reservation_status = 'released' AND v_commands = 0)
        OR
        (v_transaction_status = 'actuation_pending' AND v_reservation_status = 'active' AND v_commands = 1)
    ) THEN
        RAISE EXCEPTION 'cancel/dispatch race was unsafe: transaction %, reservation %, commands %',
            v_transaction_status, v_reservation_status, v_commands;
    END IF;
END;
$$;
