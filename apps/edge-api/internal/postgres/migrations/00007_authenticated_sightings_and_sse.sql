-- +goose Up
CREATE SEQUENCE interaction_protocol_id_seq AS bigint
    MINVALUE 0 MAXVALUE 4294967295 NO CYCLE;

DO $$
DECLARE
    current_max bigint;
BEGIN
    SELECT max(protocol_id) INTO current_max FROM interaction_requests;
    IF current_max IS NULL THEN
        PERFORM setval('interaction_protocol_id_seq', 0, false);
    ELSE
        PERFORM setval('interaction_protocol_id_seq', current_max, true);
    END IF;
END;
$$;

ALTER TABLE interaction_requests
    ALTER COLUMN protocol_id SET DEFAULT nextval('interaction_protocol_id_seq');
ALTER SEQUENCE interaction_protocol_id_seq OWNED BY interaction_requests.protocol_id;

ALTER TABLE interaction_sightings
    ADD COLUMN gateway_observed_at timestamptz;

ALTER TABLE outbox_events
    ADD COLUMN stream_sequence bigint GENERATED ALWAYS AS IDENTITY;
ALTER TABLE outbox_events
    ADD CONSTRAINT outbox_events_stream_sequence_key UNIQUE (stream_sequence);

CREATE OR REPLACE FUNCTION smartband_emit_interaction_event(
    p_tenant_id uuid,
    p_interaction_uuid uuid,
    p_event_type text,
    p_occurred_at timestamptz,
    p_payload jsonb
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    event_uuid uuid := gen_random_uuid();
BEGIN
    INSERT INTO outbox_events (
        outbox_event_id, tenant_id, aggregate_type, aggregate_id,
        event_type, event_version, payload, occurred_at
    ) VALUES (
        event_uuid, p_tenant_id, 'interaction_request', p_interaction_uuid,
        p_event_type, 1,
        jsonb_build_object(
            'event_id', event_uuid,
            'event_type', p_event_type,
            'version', 1,
            'occurred_at', p_occurred_at,
            'correlation_id', p_interaction_uuid,
            'payload', p_payload
        ),
        p_occurred_at
    );
END;
$$;

CREATE OR REPLACE FUNCTION smartband_expire_discovery(p_now timestamptz)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    expired_row record;
    clear_row record;
BEGIN
    FOR expired_row IN
        UPDATE interaction_requests
           SET state = 'expired'
         WHERE state IN ('discovered', 'queued', 'queued_ambiguous')
           AND expires_at <= p_now
        RETURNING interaction_id, tenant_id, protocol_id
    LOOP
        PERFORM smartband_emit_interaction_event(
            expired_row.tenant_id,
            expired_row.interaction_id,
            'interaction.expired',
            p_now,
            jsonb_build_object(
                'interaction_id', expired_row.protocol_id,
                'stage', 'queued',
                'expired_at', p_now
            )
        );
    END LOOP;

    FOR clear_row IN
        UPDATE interaction_requests candidate
           SET state = 'queued'
         WHERE candidate.state = 'queued_ambiguous'
           AND candidate.expires_at > p_now
           AND NOT EXISTS (
               SELECT 1
                 FROM interaction_requests peer
                WHERE peer.interaction_id <> candidate.interaction_id
                  AND peer.event_id = candidate.event_id
                  AND peer.display_code = candidate.display_code
                  AND peer.state IN ('discovered', 'queued', 'queued_ambiguous')
                  AND peer.expires_at > p_now
           )
        RETURNING candidate.interaction_id, candidate.tenant_id,
                  candidate.protocol_id, candidate.display_code,
                  candidate.first_authenticated_at
    LOOP
        PERFORM smartband_emit_interaction_event(
            clear_row.tenant_id,
            clear_row.interaction_id,
            'interaction.queued',
            p_now,
            jsonb_build_object(
                'interaction_id', clear_row.protocol_id,
                'display_code', clear_row.display_code,
                'ambiguity_status', 'clear',
                'queued_at', clear_row.first_authenticated_at,
                'collides_with', jsonb_build_array()
            )
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION smartband_record_authenticated_sighting(
    p_gateway_id uuid,
    p_band_id uuid,
    p_session_nonce bytea,
    p_display_code text,
    p_protocol_version smallint,
    p_request_ttl_seconds smallint,
    p_rssi smallint,
    p_gateway_observed_at timestamptz,
    p_received_at timestamptz
) RETURNS TABLE (interaction_protocol_id bigint, created boolean)
LANGUAGE plpgsql
AS $$
DECLARE
    scope_row record;
    interaction_row record;
    queued_row record;
    collision_ids bigint[];
BEGIN
    IF octet_length(p_session_nonce) <> 8 THEN
        RAISE EXCEPTION 'session_nonce must contain 8 bytes' USING ERRCODE = '22023';
    END IF;
    IF p_request_ttl_seconds <> 60 THEN
        RAISE EXCEPTION 'unsupported request ttl' USING ERRCODE = '22023';
    END IF;

    SELECT ac.tenant_id, ac.site_id, e.event_id
      INTO STRICT scope_row
      FROM appliance_configuration ac
      JOIN events e ON e.site_id = ac.site_id
                   AND e.tenant_id = ac.tenant_id
                   AND e.status = 'active'
      JOIN gateways g ON g.gateway_id = p_gateway_id
                     AND g.tenant_id = ac.tenant_id
                     AND g.site_id = ac.site_id
                     AND g.status = 'active'
     WHERE ac.singleton_id = 1;

    IF NOT EXISTS (
        SELECT 1
          FROM bands b
          JOIN band_assignments ba ON ba.band_id = b.band_id AND ba.status = 'active'
          JOIN operational_sessions os ON os.session_id = ba.session_id
                                      AND os.tenant_id = b.tenant_id
                                      AND os.event_id = scope_row.event_id
                                      AND os.status = 'active'
         WHERE b.band_id = p_band_id
           AND b.tenant_id = scope_row.tenant_id
           AND b.status = 'assigned'
    ) THEN
        RAISE EXCEPTION 'band is not active in the current event' USING ERRCODE = '23514';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('display-code:' || p_display_code, 0));
    PERFORM pg_advisory_xact_lock(hashtextextended('band:' || p_band_id::text, 0));
    PERFORM smartband_expire_discovery(p_received_at);

    SELECT interaction_id, protocol_id
      INTO interaction_row
      FROM interaction_requests
     WHERE band_id = p_band_id AND session_nonce = p_session_nonce;

    IF FOUND THEN
        INSERT INTO interaction_sightings (
            interaction_id, gateway_id, tenant_id, site_id, rssi,
            received_at, gateway_observed_at
        ) VALUES (
            interaction_row.interaction_id, p_gateway_id, scope_row.tenant_id,
            scope_row.site_id, p_rssi, p_received_at, p_gateway_observed_at
        );
        interaction_protocol_id := interaction_row.protocol_id;
        created := false;
        RETURN NEXT;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM interaction_requests
         WHERE band_id = p_band_id
           AND state IN (
               'discovered', 'queued', 'queued_ambiguous', 'claimed',
               'awaiting_band_confirmation', 'confirmed_pending_validation',
               'credit_reserved', 'actuation_pending', 'reconciliation_required'
           )
    ) THEN
        RAISE EXCEPTION 'band already has an active interaction' USING ERRCODE = '23505';
    END IF;

    INSERT INTO interaction_requests (
        tenant_id, site_id, event_id, band_id, session_nonce, display_code,
        protocol_version, state, first_authenticated_at, expires_at
    ) VALUES (
        scope_row.tenant_id, scope_row.site_id, scope_row.event_id, p_band_id,
        p_session_nonce, p_display_code, p_protocol_version, 'discovered',
        p_received_at, p_received_at + make_interval(secs => p_request_ttl_seconds)
    )
    RETURNING interaction_id, protocol_id, expires_at INTO interaction_row;

    INSERT INTO interaction_sightings (
        interaction_id, gateway_id, tenant_id, site_id, rssi,
        received_at, gateway_observed_at
    ) VALUES (
        interaction_row.interaction_id, p_gateway_id, scope_row.tenant_id,
        scope_row.site_id, p_rssi, p_received_at, p_gateway_observed_at
    );

    PERFORM smartband_emit_interaction_event(
        scope_row.tenant_id,
        interaction_row.interaction_id,
        'interaction.discovered',
        p_received_at,
        jsonb_build_object(
            'interaction_id', interaction_row.protocol_id,
            'display_code', p_display_code,
            'first_gateway_id', (SELECT protocol_id FROM gateways WHERE gateway_id = p_gateway_id),
            'rssi', p_rssi,
            'expires_at', interaction_row.expires_at
        )
    );

    SELECT array_agg(protocol_id ORDER BY protocol_id)
      INTO collision_ids
      FROM interaction_requests
     WHERE event_id = scope_row.event_id
       AND display_code = p_display_code
       AND state IN ('discovered', 'queued', 'queued_ambiguous')
       AND expires_at > p_received_at;

    FOR queued_row IN
        UPDATE interaction_requests
           SET state = CASE WHEN cardinality(collision_ids) > 1
                            THEN 'queued_ambiguous' ELSE 'queued' END
         WHERE event_id = scope_row.event_id
           AND display_code = p_display_code
           AND state IN ('discovered', 'queued', 'queued_ambiguous')
           AND expires_at > p_received_at
        RETURNING interaction_id, tenant_id, protocol_id, display_code,
                  first_authenticated_at
    LOOP
        PERFORM smartband_emit_interaction_event(
            queued_row.tenant_id,
            queued_row.interaction_id,
            'interaction.queued',
            p_received_at,
            jsonb_build_object(
                'interaction_id', queued_row.protocol_id,
                'display_code', queued_row.display_code,
                'ambiguity_status', CASE WHEN cardinality(collision_ids) > 1
                                         THEN 'duplicate_code' ELSE 'clear' END,
                'queued_at', queued_row.first_authenticated_at,
                'collides_with', to_jsonb(array_remove(collision_ids, queued_row.protocol_id))
            )
        );
    END LOOP;

    interaction_protocol_id := interaction_row.protocol_id;
    created := true;
    RETURN NEXT;
END;
$$;

-- +goose Down
DROP FUNCTION IF EXISTS smartband_record_authenticated_sighting(
    uuid, uuid, bytea, text, smallint, smallint, smallint, timestamptz, timestamptz
);
DROP FUNCTION IF EXISTS smartband_expire_discovery(timestamptz);
DROP FUNCTION IF EXISTS smartband_emit_interaction_event(uuid, uuid, text, timestamptz, jsonb);
ALTER TABLE outbox_events DROP CONSTRAINT IF EXISTS outbox_events_stream_sequence_key;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS stream_sequence;
ALTER TABLE interaction_sightings DROP COLUMN IF EXISTS gateway_observed_at;
ALTER TABLE interaction_requests ALTER COLUMN protocol_id DROP DEFAULT;
DROP SEQUENCE IF EXISTS interaction_protocol_id_seq;
