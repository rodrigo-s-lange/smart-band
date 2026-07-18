-- +goose Up
CREATE TABLE interaction_requests (
    interaction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    event_id uuid NOT NULL,
    band_id uuid NOT NULL,
    session_nonce bytea NOT NULL CHECK (octet_length(session_nonce) = 8),
    display_code text NOT NULL CHECK (display_code ~ '^[0-9A-HJKMNP-TV-Z]{3}-[0-9A-HJKMNP-TV-Z]{3}$'),
    protocol_version smallint NOT NULL CHECK (protocol_version BETWEEN 1 AND 255),
    state text NOT NULL CHECK (state IN (
        'discovered', 'queued', 'queued_ambiguous', 'claimed',
        'awaiting_band_confirmation', 'confirmed_pending_validation',
        'credit_reserved', 'actuation_pending', 'completed', 'expired',
        'denied', 'confirmation_timeout', 'actuation_failed',
        'reconciliation_required', 'cancelled'
    )),
    first_authenticated_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > first_authenticated_at),
    FOREIGN KEY (event_id, tenant_id, site_id)
        REFERENCES events (event_id, tenant_id, site_id),
    FOREIGN KEY (band_id, tenant_id) REFERENCES bands (band_id, tenant_id),
    UNIQUE (band_id, session_nonce),
    UNIQUE (interaction_id, tenant_id, site_id)
);

CREATE INDEX interaction_requests_queue_idx
    ON interaction_requests (event_id, created_at DESC)
    WHERE state IN ('discovered', 'queued', 'queued_ambiguous', 'claimed');

CREATE UNIQUE INDEX interaction_requests_one_active_band_idx
    ON interaction_requests (band_id)
    WHERE state IN (
        'discovered', 'queued', 'queued_ambiguous', 'claimed',
        'awaiting_band_confirmation', 'confirmed_pending_validation',
        'credit_reserved', 'actuation_pending', 'reconciliation_required'
    );

CREATE TABLE interaction_sightings (
    sighting_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    interaction_id uuid NOT NULL,
    gateway_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    rssi smallint NOT NULL CHECK (rssi BETWEEN -127 AND 20),
    received_at timestamptz NOT NULL,
    FOREIGN KEY (interaction_id, tenant_id, site_id)
        REFERENCES interaction_requests (interaction_id, tenant_id, site_id),
    FOREIGN KEY (gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id)
);

CREATE INDEX interaction_sightings_radio_selection_idx
    ON interaction_sightings (interaction_id, received_at DESC, rssi DESC);

CREATE TABLE interaction_claims (
    claim_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    interaction_id uuid NOT NULL,
    operator_gateway_id uuid NOT NULL,
    attraction_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'released', 'expired')),
    claimed_at timestamptz NOT NULL DEFAULT now(),
    lease_expires_at timestamptz NOT NULL,
    attempt_count smallint NOT NULL DEFAULT 1 CHECK (attempt_count BETWEEN 1 AND 3),
    CHECK (lease_expires_at > claimed_at),
    FOREIGN KEY (interaction_id, tenant_id, site_id)
        REFERENCES interaction_requests (interaction_id, tenant_id, site_id),
    FOREIGN KEY (operator_gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id),
    FOREIGN KEY (attraction_id, tenant_id, site_id)
        REFERENCES attractions (attraction_id, tenant_id, site_id),
    UNIQUE (claim_id, tenant_id, site_id)
);

CREATE UNIQUE INDEX interaction_claims_one_active_idx
    ON interaction_claims (interaction_id)
    WHERE status = 'active';

-- +goose Down
DROP TABLE IF EXISTS interaction_claims;
DROP TABLE IF EXISTS interaction_sightings;
DROP TABLE IF EXISTS interaction_requests;
