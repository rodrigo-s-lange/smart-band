-- +goose Up
ALTER TABLE transaction_intents
    ALTER COLUMN radio_gateway_id DROP NOT NULL,
    ADD COLUMN confirmation_expires_at timestamptz;

CREATE TABLE radio_dispatch_attempts (
    dispatch_id uuid PRIMARY KEY,
    transaction_id uuid NOT NULL,
    attempt smallint NOT NULL CHECK (attempt BETWEEN 1 AND 3),
    radio_gateway_id uuid,
    challenge_nonce bytea NOT NULL CHECK (octet_length(challenge_nonce) = 8),
    protocol_version integer NOT NULL CHECK (protocol_version BETWEEN 0 AND 65535),
    payload bytea NOT NULL,
    status text NOT NULL CHECK (status IN (
        'waiting_for_radio', 'pending', 'delivered', 'failed', 'timed_out'
    )),
    failure_kind text CHECK (failure_kind IN (
        'gateway_offline', 'connect_failed', 'write_not_confirmed',
        'transport_error', 'no_radio_gateway'
    )),
    selection_deadline timestamptz,
    dispatch_deadline timestamptz,
    worker_id uuid,
    work_lease_expires_at timestamptz,
    created_at timestamptz NOT NULL,
    resolved_at timestamptz,
    CHECK (
        (status = 'waiting_for_radio' AND radio_gateway_id IS NULL
            AND selection_deadline IS NOT NULL AND dispatch_deadline IS NULL
            AND failure_kind IS NULL AND resolved_at IS NULL)
        OR
        (status = 'pending' AND radio_gateway_id IS NOT NULL
            AND selection_deadline IS NULL AND dispatch_deadline IS NOT NULL
            AND failure_kind IS NULL AND resolved_at IS NULL)
        OR
        (status = 'delivered' AND radio_gateway_id IS NOT NULL
            AND selection_deadline IS NULL AND dispatch_deadline IS NOT NULL
            AND failure_kind IS NULL AND resolved_at IS NOT NULL)
        OR
        (status = 'failed' AND failure_kind IS NOT NULL AND resolved_at IS NOT NULL)
        OR
        (status = 'timed_out' AND radio_gateway_id IS NOT NULL
            AND failure_kind IS NULL AND resolved_at IS NOT NULL)
    ),
    CHECK ((worker_id IS NULL) = (work_lease_expires_at IS NULL)),
    FOREIGN KEY (transaction_id) REFERENCES transaction_intents (transaction_id),
    FOREIGN KEY (radio_gateway_id) REFERENCES gateways (gateway_id),
    UNIQUE (transaction_id, attempt)
);

CREATE INDEX radio_dispatch_attempts_ready_idx
    ON radio_dispatch_attempts (dispatch_deadline, created_at)
    WHERE status = 'pending';
CREATE INDEX radio_dispatch_attempts_waiting_idx
    ON radio_dispatch_attempts (selection_deadline, created_at)
    WHERE status = 'waiting_for_radio';

CREATE TABLE radio_dispatch_result_audit (
    result_audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dispatch_id uuid NOT NULL REFERENCES radio_dispatch_attempts (dispatch_id),
    received_at timestamptz NOT NULL,
    reported_outcome text NOT NULL CHECK (reported_outcome IN ('delivered', 'failed', 'timed_out')),
    reported_failure_kind text,
    classification text NOT NULL CHECK (classification IN ('accepted', 'duplicate', 'stale'))
);

CREATE FUNCTION smartband_select_radio_gateway(
    p_transaction_id uuid,
    p_now timestamptz
) RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT candidate.gateway_id
      FROM (
        SELECT DISTINCT ON (s.gateway_id)
               s.gateway_id, s.rssi, s.received_at, g.protocol_id
          FROM transaction_intents t
          JOIN interaction_sightings s ON s.interaction_id = t.interaction_id
          JOIN gateways g
            ON g.gateway_id = s.gateway_id
           AND g.tenant_id = t.tenant_id
           AND g.site_id = t.site_id
           AND g.status = 'active'
         WHERE t.transaction_id = p_transaction_id
           AND s.received_at >= p_now - interval '10 seconds'
           AND s.received_at <= p_now
         ORDER BY s.gateway_id, s.rssi DESC, s.received_at DESC
      ) candidate
     ORDER BY EXISTS (
                  SELECT 1
                    FROM radio_dispatch_attempts previous
                   WHERE previous.transaction_id = p_transaction_id
                     AND previous.radio_gateway_id = candidate.gateway_id
              ),
              candidate.rssi DESC,
              candidate.received_at DESC,
              candidate.protocol_id ASC
     LIMIT 1;
$$;

CREATE FUNCTION smartband_start_radio_dispatch(
    p_transaction_protocol_id bytea,
    p_dispatch_id uuid,
    p_challenge_nonce bytea,
    p_protocol_version integer,
    p_payload bytea,
    p_now timestamptz
) RETURNS TABLE (
    result text,
    attempt smallint,
    radio_gateway_id uuid,
    status text,
    deadline timestamptz
)
LANGUAGE plpgsql
AS $$
DECLARE
    transaction_row transaction_intents%ROWTYPE;
    claim_row interaction_claims%ROWTYPE;
    selected_radio uuid;
BEGIN
    IF octet_length(p_transaction_protocol_id) <> 8
       OR octet_length(p_challenge_nonce) <> 8 THEN
        RAISE EXCEPTION 'transaction id and challenge nonce must contain 8 bytes'
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO transaction_row
      FROM transaction_intents
     WHERE protocol_id = p_transaction_protocol_id
     FOR UPDATE;
    IF NOT FOUND THEN
        result := 'not_found'; RETURN NEXT; RETURN;
    END IF;

    SELECT * INTO claim_row
      FROM interaction_claims
     WHERE claim_id = transaction_row.claim_id
     FOR UPDATE;
    IF transaction_row.status <> 'claimed' OR claim_row.status <> 'active' THEN
        result := 'not_claimed'; RETURN NEXT; RETURN;
    END IF;

    IF EXISTS (
        SELECT 1 FROM radio_dispatch_attempts
         WHERE transaction_id = transaction_row.transaction_id
    ) THEN
        result := 'already_started'; RETURN NEXT; RETURN;
    END IF;

    selected_radio := smartband_select_radio_gateway(transaction_row.transaction_id, p_now);
    attempt := 1;
    radio_gateway_id := selected_radio;
    IF selected_radio IS NULL THEN
        status := 'waiting_for_radio';
        deadline := p_now + interval '10 seconds';
        INSERT INTO radio_dispatch_attempts (
            dispatch_id, transaction_id, attempt, challenge_nonce,
            protocol_version, payload, status, selection_deadline, created_at
        ) VALUES (
            p_dispatch_id, transaction_row.transaction_id, 1, p_challenge_nonce,
            p_protocol_version, p_payload, status, deadline, p_now
        );
    ELSE
        status := 'pending';
        deadline := p_now + interval '10 seconds';
        INSERT INTO radio_dispatch_attempts (
            dispatch_id, transaction_id, attempt, radio_gateway_id,
            challenge_nonce, protocol_version, payload, status,
            dispatch_deadline, created_at
        ) VALUES (
            p_dispatch_id, transaction_row.transaction_id, 1, selected_radio,
            p_challenge_nonce, p_protocol_version, p_payload, status,
            deadline, p_now
        );
    END IF;

    UPDATE transaction_intents
       SET radio_gateway_id = selected_radio,
           challenge_nonce = p_challenge_nonce,
           updated_at = p_now
     WHERE transaction_id = transaction_row.transaction_id;
    UPDATE interaction_claims
       SET attempt_count = 1, lease_expires_at = deadline
     WHERE claim_id = transaction_row.claim_id;

    result := 'started';
    RETURN NEXT;
END;
$$;

CREATE FUNCTION smartband_promote_waiting_radio(p_now timestamptz)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    waiting_row record;
    selected_radio uuid;
    promoted integer := 0;
BEGIN
    FOR waiting_row IN
        SELECT d.dispatch_id, d.transaction_id, t.claim_id
          FROM radio_dispatch_attempts d
          JOIN transaction_intents t USING (transaction_id)
          JOIN interaction_claims c ON c.claim_id = t.claim_id
         WHERE d.status = 'waiting_for_radio'
           AND d.selection_deadline > p_now
           AND t.status = 'claimed'
           AND c.status = 'active'
         ORDER BY d.created_at
         FOR UPDATE OF d SKIP LOCKED
    LOOP
        selected_radio := smartband_select_radio_gateway(waiting_row.transaction_id, p_now);
        IF selected_radio IS NULL THEN
            CONTINUE;
        END IF;
        UPDATE radio_dispatch_attempts
           SET status = 'pending', radio_gateway_id = selected_radio,
               selection_deadline = NULL,
               dispatch_deadline = p_now + interval '10 seconds'
         WHERE dispatch_id = waiting_row.dispatch_id
           AND status = 'waiting_for_radio';
        IF FOUND THEN
            UPDATE transaction_intents
               SET radio_gateway_id = selected_radio, updated_at = p_now
             WHERE transaction_id = waiting_row.transaction_id;
            UPDATE interaction_claims
               SET lease_expires_at = p_now + interval '10 seconds'
             WHERE claim_id = waiting_row.claim_id;
            promoted := promoted + 1;
        END IF;
    END LOOP;
    RETURN promoted;
END;
$$;

CREATE FUNCTION smartband_finish_radio_dispatch(
    p_dispatch_id uuid,
    p_transaction_id uuid,
    p_attempt smallint,
    p_challenge_nonce bytea,
    p_worker_id uuid,
    p_reported_outcome text,
    p_failure_kind text,
    p_now timestamptz,
    p_next_dispatch_id uuid,
    p_next_challenge_nonce bytea
) RETURNS TABLE (result text, next_status text, next_dispatch_id uuid)
LANGUAGE plpgsql
AS $$
DECLARE
    dispatch_row radio_dispatch_attempts%ROWTYPE;
    transaction_row transaction_intents%ROWTYPE;
    claim_row interaction_claims%ROWTYPE;
    interaction_row interaction_requests%ROWTYPE;
    gateway_protocol_id integer;
    selected_radio uuid;
    next_deadline timestamptz;
    effective_failure text;
    duplicate_result boolean;
BEGIN
    IF p_reported_outcome NOT IN ('delivered', 'failed', 'timed_out')
       OR octet_length(p_challenge_nonce) <> 8
       OR octet_length(p_next_challenge_nonce) <> 8 THEN
        RAISE EXCEPTION 'invalid radio dispatch result' USING ERRCODE = '22023';
    END IF;
    IF p_reported_outcome = 'failed' AND p_failure_kind NOT IN (
        'gateway_offline', 'connect_failed', 'write_not_confirmed',
        'transport_error', 'no_radio_gateway'
    ) THEN
        RAISE EXCEPTION 'invalid radio failure kind' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO dispatch_row
      FROM radio_dispatch_attempts
     WHERE dispatch_id = p_dispatch_id
     FOR UPDATE;
    IF NOT FOUND THEN
        result := 'stale'; RETURN NEXT; RETURN;
    END IF;

    SELECT * INTO transaction_row FROM transaction_intents
     WHERE transaction_id = dispatch_row.transaction_id FOR UPDATE;
    SELECT * INTO claim_row FROM interaction_claims
     WHERE claim_id = transaction_row.claim_id FOR UPDATE;
    SELECT * INTO interaction_row FROM interaction_requests
     WHERE interaction_id = transaction_row.interaction_id FOR UPDATE;

    IF dispatch_row.transaction_id <> p_transaction_id
       OR dispatch_row.attempt <> p_attempt
       OR dispatch_row.challenge_nonce <> p_challenge_nonce
       OR transaction_row.challenge_nonce <> p_challenge_nonce
       OR claim_row.attempt_count <> p_attempt THEN
        INSERT INTO radio_dispatch_result_audit (
            dispatch_id, received_at, reported_outcome, reported_failure_kind, classification
        ) VALUES (p_dispatch_id, p_now, p_reported_outcome, p_failure_kind, 'stale');
        result := 'stale'; RETURN NEXT; RETURN;
    END IF;

    IF dispatch_row.status NOT IN ('pending', 'waiting_for_radio') THEN
        duplicate_result :=
            (dispatch_row.status = 'delivered' AND p_reported_outcome = 'delivered') OR
            (dispatch_row.status = 'timed_out' AND p_reported_outcome = 'timed_out') OR
            (dispatch_row.status = 'failed' AND p_reported_outcome = 'failed'
                AND dispatch_row.failure_kind = p_failure_kind);
        INSERT INTO radio_dispatch_result_audit (
            dispatch_id, received_at, reported_outcome, reported_failure_kind, classification
        ) VALUES (
            p_dispatch_id, p_now, p_reported_outcome, p_failure_kind,
            CASE WHEN duplicate_result THEN 'duplicate' ELSE 'stale' END
        );
        result := CASE WHEN duplicate_result THEN 'duplicate' ELSE 'stale' END;
        RETURN NEXT; RETURN;
    END IF;

    IF transaction_row.status <> 'claimed' OR claim_row.status <> 'active' THEN
        INSERT INTO radio_dispatch_result_audit (
            dispatch_id, received_at, reported_outcome, reported_failure_kind, classification
        ) VALUES (p_dispatch_id, p_now, p_reported_outcome, p_failure_kind, 'stale');
        result := 'stale'; RETURN NEXT; RETURN;
    END IF;

    IF dispatch_row.status = 'waiting_for_radio' THEN
        IF p_reported_outcome <> 'failed'
           OR p_failure_kind <> 'no_radio_gateway'
           OR p_now < dispatch_row.selection_deadline THEN
            INSERT INTO radio_dispatch_result_audit (
                dispatch_id, received_at, reported_outcome, reported_failure_kind, classification
            ) VALUES (p_dispatch_id, p_now, p_reported_outcome, p_failure_kind, 'stale');
            result := 'stale'; RETURN NEXT; RETURN;
        END IF;
    ELSE
        IF p_reported_outcome = 'timed_out' THEN
            IF p_now < dispatch_row.dispatch_deadline THEN
                INSERT INTO radio_dispatch_result_audit (
                    dispatch_id, received_at, reported_outcome,
                    reported_failure_kind, classification
                ) VALUES (
                    p_dispatch_id, p_now, p_reported_outcome,
                    p_failure_kind, 'stale'
                );
                result := 'stale'; RETURN NEXT; RETURN;
            END IF;
        ELSIF p_worker_id IS NULL OR dispatch_row.worker_id <> p_worker_id
              OR dispatch_row.dispatch_deadline < p_now
              OR claim_row.lease_expires_at < p_now THEN
            INSERT INTO radio_dispatch_result_audit (
                dispatch_id, received_at, reported_outcome, reported_failure_kind, classification
            ) VALUES (p_dispatch_id, p_now, p_reported_outcome, p_failure_kind, 'stale');
            result := 'stale'; RETURN NEXT; RETURN;
        END IF;
    END IF;

    INSERT INTO radio_dispatch_result_audit (
        dispatch_id, received_at, reported_outcome, reported_failure_kind, classification
    ) VALUES (p_dispatch_id, p_now, p_reported_outcome, p_failure_kind, 'accepted');

    IF p_reported_outcome = 'delivered' THEN
        UPDATE radio_dispatch_attempts
           SET status = 'delivered', resolved_at = p_now,
               worker_id = NULL, work_lease_expires_at = NULL
         WHERE dispatch_id = p_dispatch_id;
        UPDATE transaction_intents
           SET status = 'awaiting_band_confirmation',
               confirmation_expires_at = p_now + interval '10 seconds',
               updated_at = p_now
         WHERE transaction_id = transaction_row.transaction_id;
        UPDATE interaction_requests SET state = 'awaiting_band_confirmation'
         WHERE interaction_id = interaction_row.interaction_id;
        UPDATE interaction_claims SET lease_expires_at = p_now + interval '10 seconds'
         WHERE claim_id = claim_row.claim_id;
        SELECT protocol_id INTO gateway_protocol_id FROM gateways
         WHERE gateway_id = dispatch_row.radio_gateway_id;
        PERFORM smartband_emit_interaction_event(
            interaction_row.tenant_id, interaction_row.interaction_id,
            'interaction.confirmation_requested', p_now,
            jsonb_build_object(
                'interaction_id', interaction_row.protocol_id,
                'transaction_id', encode(transaction_row.protocol_id, 'hex'),
                'dispatch_id', dispatch_row.dispatch_id,
                'radio_gateway_id', gateway_protocol_id,
                'attempt', dispatch_row.attempt,
                'challenge_nonce', encode(dispatch_row.challenge_nonce, 'hex'),
                'delivered_at', p_now
            )
        );
        result := 'accepted'; next_status := 'delivered'; RETURN NEXT; RETURN;
    END IF;

    effective_failure := CASE
        WHEN p_reported_outcome = 'timed_out' THEN 'timed_out'
        ELSE p_failure_kind
    END;
    UPDATE radio_dispatch_attempts
       SET status = CASE WHEN p_reported_outcome = 'timed_out' THEN 'timed_out' ELSE 'failed' END,
           failure_kind = CASE WHEN p_reported_outcome = 'failed' THEN p_failure_kind ELSE NULL END,
           resolved_at = p_now, worker_id = NULL, work_lease_expires_at = NULL
     WHERE dispatch_id = p_dispatch_id;

    SELECT protocol_id INTO gateway_protocol_id FROM gateways
     WHERE gateway_id = dispatch_row.radio_gateway_id;
    PERFORM smartband_emit_interaction_event(
        interaction_row.tenant_id, interaction_row.interaction_id,
        'radio.dispatch_failed', p_now,
        jsonb_strip_nulls(jsonb_build_object(
            'interaction_id', interaction_row.protocol_id,
            'transaction_id', encode(transaction_row.protocol_id, 'hex'),
            'dispatch_id', dispatch_row.dispatch_id,
            'radio_gateway_id', gateway_protocol_id,
            'attempt', dispatch_row.attempt,
            'challenge_nonce', encode(dispatch_row.challenge_nonce, 'hex'),
            'failure_kind', effective_failure,
            'failed_at', p_now
        ))
    );

    IF dispatch_row.attempt = 3 THEN
        UPDATE interaction_requests SET state = 'expired'
         WHERE interaction_id = interaction_row.interaction_id;
        UPDATE interaction_claims
           SET status = 'expired', lease_expires_at = p_now
         WHERE claim_id = claim_row.claim_id;
        UPDATE transaction_intents
           SET status = 'cancelled', confirmation_expires_at = NULL, updated_at = p_now
         WHERE transaction_id = transaction_row.transaction_id;
        PERFORM smartband_emit_interaction_event(
            interaction_row.tenant_id, interaction_row.interaction_id,
            'interaction.expired', p_now,
            jsonb_build_object(
                'interaction_id', interaction_row.protocol_id,
                'transaction_id', encode(transaction_row.protocol_id, 'hex'),
                'attempt', dispatch_row.attempt,
                'reason', 'radio_attempts_exhausted',
                'stage', 'claimed',
                'expired_at', p_now
            )
        );
        result := 'accepted'; next_status := 'exhausted'; RETURN NEXT; RETURN;
    END IF;

    selected_radio := smartband_select_radio_gateway(transaction_row.transaction_id, p_now);
    next_deadline := p_now + interval '10 seconds';
    IF selected_radio IS NULL THEN
        INSERT INTO radio_dispatch_attempts (
            dispatch_id, transaction_id, attempt, challenge_nonce,
            protocol_version, payload, status, selection_deadline, created_at
        ) VALUES (
            p_next_dispatch_id, transaction_row.transaction_id, dispatch_row.attempt + 1,
            p_next_challenge_nonce, dispatch_row.protocol_version, dispatch_row.payload,
            'waiting_for_radio', next_deadline, p_now
        );
        next_status := 'waiting_for_radio';
    ELSE
        INSERT INTO radio_dispatch_attempts (
            dispatch_id, transaction_id, attempt, radio_gateway_id,
            challenge_nonce, protocol_version, payload, status,
            dispatch_deadline, created_at
        ) VALUES (
            p_next_dispatch_id, transaction_row.transaction_id, dispatch_row.attempt + 1,
            selected_radio, p_next_challenge_nonce, dispatch_row.protocol_version,
            dispatch_row.payload, 'pending', next_deadline, p_now
        );
        next_status := 'pending';
    END IF;

    UPDATE interaction_claims
       SET attempt_count = dispatch_row.attempt + 1,
           lease_expires_at = next_deadline
     WHERE claim_id = claim_row.claim_id;
    UPDATE transaction_intents
       SET radio_gateway_id = selected_radio,
           challenge_nonce = p_next_challenge_nonce,
           updated_at = p_now
     WHERE transaction_id = transaction_row.transaction_id;

    result := 'accepted';
    next_dispatch_id := p_next_dispatch_id;
    RETURN NEXT;
END;
$$;

-- +goose Down
DROP FUNCTION smartband_finish_radio_dispatch(
    uuid, uuid, smallint, bytea, uuid, text, text, timestamptz, uuid, bytea
);
DROP FUNCTION smartband_promote_waiting_radio(timestamptz);
DROP FUNCTION smartband_start_radio_dispatch(bytea, uuid, bytea, integer, bytea, timestamptz);
DROP FUNCTION smartband_select_radio_gateway(uuid, timestamptz);

UPDATE transaction_intents transaction
   SET radio_gateway_id = (
       SELECT attempt.radio_gateway_id
         FROM radio_dispatch_attempts attempt
        WHERE attempt.transaction_id = transaction.transaction_id
          AND attempt.radio_gateway_id IS NOT NULL
        ORDER BY attempt.attempt DESC
        LIMIT 1
   )
 WHERE transaction.radio_gateway_id IS NULL;

DROP TABLE radio_dispatch_result_audit;
DROP TABLE radio_dispatch_attempts;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM transaction_intents WHERE radio_gateway_id IS NULL) THEN
        RAISE EXCEPTION 'cannot downgrade while a transaction has no radio gateway';
    END IF;
END;
$$;

ALTER TABLE transaction_intents
    DROP COLUMN confirmation_expires_at,
    ALTER COLUMN radio_gateway_id SET NOT NULL;
