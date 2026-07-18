DO $$
DECLARE
    v_status text;
    v_interaction_state text;
    v_claim_status text;
    v_nonce_length integer;
BEGIN
    IF EXISTS (SELECT 1 FROM operator_sessions) THEN
        RAISE EXCEPTION 'legacy operator sessions were not invalidated';
    END IF;
    IF 2 <> (
        SELECT count(*) FROM information_schema.columns
         WHERE table_name = 'operator_sessions'
           AND column_name IN ('site_id', 'gateway_id')
           AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'operator session gateway binding is absent or nullable';
    END IF;
    SELECT status, octet_length(challenge_nonce)
      INTO STRICT v_status, v_nonce_length
      FROM transaction_intents LIMIT 1;
    IF v_status <> 'cancelled' OR v_nonce_length <> 8 THEN
        RAISE EXCEPTION 'legacy active challenge was not safely cancelled and converted';
    END IF;
    SELECT i.state, c.status INTO STRICT v_interaction_state, v_claim_status
      FROM interaction_requests i
      JOIN interaction_claims c USING (interaction_id)
     LIMIT 1;
    IF v_interaction_state <> 'cancelled' OR v_claim_status <> 'released' THEN
        RAISE EXCEPTION 'legacy interaction and claim were not released';
    END IF;
END;
$$;
