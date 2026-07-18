DO $$
DECLARE
    v_missing bigint;
    v_transaction_protocol bytea;
BEGIN
    SELECT
        (SELECT count(*) FROM gateways
          WHERE protocol_id IS NULL OR octet_length(api_key_hash) <> 32)
      + (SELECT count(*) FROM attractions WHERE protocol_id IS NULL)
      + (SELECT count(*) FROM interaction_requests WHERE protocol_id IS NULL)
      + (SELECT count(*) FROM transaction_intents WHERE protocol_id IS NULL)
      INTO v_missing;
    SELECT protocol_id INTO v_transaction_protocol FROM transaction_intents LIMIT 1;
    IF v_missing <> 0 OR octet_length(v_transaction_protocol) <> 8 THEN
        RAISE EXCEPTION 'stage 4 upgrade backfill failed';
    END IF;
END;
$$;
