-- +goose Up
-- Operator sessions are transient. Existing sessions predate gateway binding and
-- cannot be upgraded without inventing security context, so force a new login.
DELETE FROM operator_sessions;

ALTER TABLE operator_sessions ADD COLUMN site_id uuid NOT NULL;
ALTER TABLE operator_sessions ADD COLUMN gateway_id uuid NOT NULL;
ALTER TABLE operator_sessions
    ADD FOREIGN KEY (gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id);

UPDATE interaction_claims c
   SET status = 'released'
  FROM transaction_intents t
 WHERE t.claim_id = c.claim_id
   AND octet_length(t.challenge_nonce) <> 8
   AND t.status = 'awaiting_band_confirmation';

UPDATE interaction_requests i
   SET state = 'cancelled'
  FROM transaction_intents t
 WHERE t.interaction_id = i.interaction_id
   AND octet_length(t.challenge_nonce) <> 8
   AND t.status = 'awaiting_band_confirmation';

UPDATE transaction_intents
   SET status = 'cancelled', updated_at = now()
 WHERE octet_length(challenge_nonce) <> 8
   AND status = 'awaiting_band_confirmation';

ALTER TABLE transaction_intents
    DROP CONSTRAINT transaction_intents_challenge_nonce_check;

UPDATE transaction_intents
   SET challenge_nonce = substring(challenge_nonce FROM 1 FOR 8)
 WHERE octet_length(challenge_nonce) <> 8;

ALTER TABLE transaction_intents
    ADD CONSTRAINT transaction_intents_challenge_nonce_check
        CHECK (octet_length(challenge_nonce) = 8);
ALTER TABLE transaction_intents
    DROP CONSTRAINT transaction_intents_status_check;
ALTER TABLE transaction_intents
    ADD CONSTRAINT transaction_intents_status_check CHECK (status IN (
        'claimed', 'awaiting_band_confirmation', 'confirmed_pending_validation',
        'credit_reserved', 'actuation_pending', 'completed', 'denied',
        'confirmation_timeout', 'actuation_failed',
        'reconciliation_required', 'cancelled'
    ));

CREATE OR REPLACE FUNCTION smartband_claim_interaction(
    p_interaction_protocol_id bigint,
    p_operator_id uuid,
    p_operator_gateway_protocol_id integer,
    p_attraction_protocol_id integer,
    p_transaction_protocol_id bytea,
    p_challenge_nonce bytea,
    p_now timestamptz
) RETURNS TABLE (
    outcome text,
    transaction_protocol_id bytea,
    radio_gateway_protocol_id integer,
    lease_expires_at timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
    interaction_row interaction_requests%ROWTYPE;
    operator_gateway_row gateways%ROWTYPE;
    attraction_row attractions%ROWTYPE;
    radio_gateway_row gateways%ROWTYPE;
    wallet_row wallets%ROWTYPE;
    claim_uuid uuid;
    selected_lease_expires_at timestamptz := p_now + interval '10 seconds';
    violated_constraint text;
BEGIN
    IF octet_length(p_transaction_protocol_id) <> 8 OR octet_length(p_challenge_nonce) <> 8 THEN
        RAISE EXCEPTION 'transaction protocol id and challenge nonce must contain 8 bytes'
            USING ERRCODE = '22023';
    END IF;

    PERFORM smartband_expire_discovery(p_now);

    SELECT * INTO interaction_row
      FROM interaction_requests
     WHERE protocol_id = p_interaction_protocol_id
     FOR UPDATE;

    IF NOT FOUND THEN
        outcome := 'not_found'; RETURN NEXT; RETURN;
    END IF;
    IF interaction_row.state = 'queued_ambiguous' THEN
        outcome := 'ambiguous'; RETURN NEXT; RETURN;
    END IF;
    IF interaction_row.state <> 'queued' OR interaction_row.expires_at <= p_now THEN
        outcome := 'not_claimable'; RETURN NEXT; RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM operators o
         WHERE o.operator_id = p_operator_id
           AND o.tenant_id = interaction_row.tenant_id
           AND o.status = 'active'
    ) THEN
        outcome := 'invalid_operator_gateway'; RETURN NEXT; RETURN;
    END IF;

    SELECT * INTO operator_gateway_row
      FROM gateways g
     WHERE g.protocol_id = p_operator_gateway_protocol_id
       AND g.tenant_id = interaction_row.tenant_id
       AND g.site_id = interaction_row.site_id
       AND g.status = 'active';
    IF NOT FOUND THEN
        outcome := 'invalid_operator_gateway'; RETURN NEXT; RETURN;
    END IF;

    SELECT * INTO attraction_row
      FROM attractions a
     WHERE a.protocol_id = p_attraction_protocol_id
       AND a.tenant_id = interaction_row.tenant_id
       AND a.site_id = interaction_row.site_id
       AND a.status = 'active'
       AND a.price_minor > 0
       AND EXISTS (
           SELECT 1 FROM gateway_attractions ga
            WHERE ga.gateway_id = operator_gateway_row.gateway_id
              AND ga.attraction_id = a.attraction_id
              AND ga.tenant_id = a.tenant_id
              AND ga.site_id = a.site_id
       );
    IF NOT FOUND THEN
        outcome := 'invalid_attraction'; RETURN NEXT; RETURN;
    END IF;

    SELECT w.* INTO wallet_row
      FROM band_assignments ba
      JOIN operational_sessions os
        ON os.session_id = ba.session_id
       AND os.tenant_id = ba.tenant_id
       AND os.event_id = interaction_row.event_id
       AND os.status = 'active'
      JOIN wallets w
        ON w.session_id = os.session_id
       AND w.tenant_id = os.tenant_id
     WHERE ba.band_id = interaction_row.band_id
       AND ba.tenant_id = interaction_row.tenant_id
       AND ba.status = 'active'
     LIMIT 1;
    IF NOT FOUND THEN
        outcome := 'no_wallet'; RETURN NEXT; RETURN;
    END IF;

    SELECT g.* INTO radio_gateway_row
      FROM interaction_sightings s
      JOIN gateways g
        ON g.gateway_id = s.gateway_id
       AND g.tenant_id = s.tenant_id
       AND g.site_id = s.site_id
       AND g.status = 'active'
     WHERE s.interaction_id = interaction_row.interaction_id
       AND s.received_at >= p_now - interval '10 seconds'
       AND s.received_at <= p_now
     ORDER BY s.rssi DESC, s.received_at DESC, g.protocol_id ASC
     LIMIT 1;
    IF NOT FOUND THEN
        outcome := 'no_radio_gateway'; RETURN NEXT; RETURN;
    END IF;

    BEGIN
        INSERT INTO interaction_claims (
            interaction_id, operator_gateway_id, attraction_id, tenant_id,
            site_id, claimed_at, lease_expires_at, attempt_count
        ) VALUES (
            interaction_row.interaction_id, operator_gateway_row.gateway_id,
            attraction_row.attraction_id, interaction_row.tenant_id,
            interaction_row.site_id, p_now, selected_lease_expires_at, 1
        ) RETURNING claim_id INTO claim_uuid;

        INSERT INTO transaction_intents (
            interaction_id, claim_id, tenant_id, site_id, wallet_id,
            attraction_id, operator_gateway_id, radio_gateway_id, amount,
            challenge_nonce, status, created_at, updated_at, protocol_id
        ) VALUES (
            interaction_row.interaction_id, claim_uuid, interaction_row.tenant_id,
            interaction_row.site_id, wallet_row.wallet_id, attraction_row.attraction_id,
            operator_gateway_row.gateway_id, radio_gateway_row.gateway_id,
            attraction_row.price_minor, p_challenge_nonce, 'claimed', p_now, p_now,
            p_transaction_protocol_id
        );
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
        IF violated_constraint = 'transaction_intents_protocol_id_key' THEN
            outcome := 'transaction_id_collision'; RETURN NEXT; RETURN;
        END IF;
        outcome := 'not_claimable'; RETURN NEXT; RETURN;
    END;

    UPDATE interaction_requests SET state = 'claimed'
     WHERE interaction_id = interaction_row.interaction_id;

    PERFORM smartband_emit_interaction_event(
        interaction_row.tenant_id,
        interaction_row.interaction_id,
        'interaction.claimed',
        p_now,
        jsonb_build_object(
            'interaction_id', interaction_row.protocol_id,
            'transaction_id', encode(p_transaction_protocol_id, 'hex'),
            'operator_gateway_id', operator_gateway_row.protocol_id,
            'attraction_id', attraction_row.protocol_id,
            'claimed_at', p_now
        )
    );

    outcome := 'claimed';
    transaction_protocol_id := p_transaction_protocol_id;
    radio_gateway_protocol_id := radio_gateway_row.protocol_id;
    lease_expires_at := selected_lease_expires_at;
    RETURN NEXT;
END;
$$;

-- +goose Down
DROP FUNCTION IF EXISTS smartband_claim_interaction(
    bigint, uuid, integer, integer, bytea, bytea, timestamptz
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM transaction_intents WHERE status = 'claimed') THEN
        RAISE EXCEPTION 'cannot downgrade while claimed transactions exist';
    END IF;
END;
$$;

ALTER TABLE transaction_intents
    DROP CONSTRAINT transaction_intents_status_check;
ALTER TABLE transaction_intents
    ADD CONSTRAINT transaction_intents_status_check CHECK (status IN (
        'awaiting_band_confirmation', 'confirmed_pending_validation',
        'credit_reserved', 'actuation_pending', 'completed', 'denied',
        'confirmation_timeout', 'actuation_failed',
        'reconciliation_required', 'cancelled'
    ));
ALTER TABLE transaction_intents
    DROP CONSTRAINT transaction_intents_challenge_nonce_check;
UPDATE transaction_intents
   SET challenge_nonce = challenge_nonce || decode(repeat('00', 8), 'hex')
 WHERE octet_length(challenge_nonce) = 8;
ALTER TABLE transaction_intents
    ADD CONSTRAINT transaction_intents_challenge_nonce_check
        CHECK (octet_length(challenge_nonce) = 16);

DELETE FROM operator_sessions;
ALTER TABLE operator_sessions DROP COLUMN gateway_id;
ALTER TABLE operator_sessions DROP COLUMN site_id;
