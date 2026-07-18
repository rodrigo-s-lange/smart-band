-- +goose Up
-- actuation_failed retains an active credit reservation and therefore blocks a
-- second interaction for the same band, just like reconciliation_required.
DO $$
BEGIN
    IF EXISTS (
        SELECT band_id
          FROM interaction_requests
         WHERE state IN (
             'discovered', 'queued', 'queued_ambiguous', 'claimed',
             'awaiting_band_confirmation', 'confirmed_pending_validation',
             'credit_reserved', 'actuation_pending', 'actuation_failed',
             'reconciliation_required'
         )
         GROUP BY band_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION
            'cannot enforce one active interaction per band: conflicting rows require manual reconciliation';
    END IF;
END;
$$;

DROP INDEX interaction_requests_one_active_band_idx;
CREATE UNIQUE INDEX interaction_requests_one_active_band_idx
    ON interaction_requests (band_id)
    WHERE state IN (
        'discovered', 'queued', 'queued_ambiguous', 'claimed',
        'awaiting_band_confirmation', 'confirmed_pending_validation',
        'credit_reserved', 'actuation_pending', 'actuation_failed',
        'reconciliation_required'
    );

-- Preserve the v00009 implementation so rollback restores it byte-for-byte.
-- The wrapper lets the existing function perform all authorization and locking
-- first, then translates the unique-index rejection for actuation_failed into
-- the same domain error used by its explicit active-state check.
ALTER FUNCTION smartband_record_authenticated_sighting(
    uuid, uuid, bytea, text, smallint, smallint, smallint, timestamptz, timestamptz
) RENAME TO smartband_record_authenticated_sighting_v00009;

CREATE FUNCTION smartband_record_authenticated_sighting(
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
BEGIN
    RETURN QUERY
    SELECT *
      FROM smartband_record_authenticated_sighting_v00009(
          p_gateway_id,
          p_band_id,
          p_session_nonce,
          p_display_code,
          p_protocol_version,
          p_request_ttl_seconds,
          p_rssi,
          p_gateway_observed_at,
          p_received_at
      );
EXCEPTION WHEN unique_violation THEN
    IF NOT EXISTS (
        SELECT 1
          FROM interaction_requests
         WHERE band_id = p_band_id
           AND session_nonce = p_session_nonce
    ) AND EXISTS (
        SELECT 1
          FROM interaction_requests
         WHERE band_id = p_band_id
           AND state IN (
               'discovered', 'queued', 'queued_ambiguous', 'claimed',
               'awaiting_band_confirmation', 'confirmed_pending_validation',
               'credit_reserved', 'actuation_pending', 'actuation_failed',
               'reconciliation_required'
           )
    ) THEN
        RAISE EXCEPTION 'band already has an active interaction'
            USING ERRCODE = '23505';
    END IF;
    RAISE;
END;
$$;

-- +goose Down
DROP FUNCTION smartband_record_authenticated_sighting(
    uuid, uuid, bytea, text, smallint, smallint, smallint, timestamptz, timestamptz
);
ALTER FUNCTION smartband_record_authenticated_sighting_v00009(
    uuid, uuid, bytea, text, smallint, smallint, smallint, timestamptz, timestamptz
) RENAME TO smartband_record_authenticated_sighting;

DROP INDEX interaction_requests_one_active_band_idx;
CREATE UNIQUE INDEX interaction_requests_one_active_band_idx
    ON interaction_requests (band_id)
    WHERE state IN (
        'discovered', 'queued', 'queued_ambiguous', 'claimed',
        'awaiting_band_confirmation', 'confirmed_pending_validation',
        'credit_reserved', 'actuation_pending', 'reconciliation_required'
    );
