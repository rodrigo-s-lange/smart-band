-- +goose Up
CREATE TABLE participants (
    participant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants (tenant_id),
    external_reference text,
    display_name text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, external_reference),
    UNIQUE (participant_id, tenant_id)
);

CREATE TABLE operators (
    operator_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants (tenant_id),
    login text NOT NULL,
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 160),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, login),
    UNIQUE (operator_id, tenant_id)
);

CREATE TABLE bands (
    band_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants (tenant_id),
    inventory_code text NOT NULL,
    protocol_id bigint NOT NULL CHECK (protocol_id BETWEEN 0 AND 4294967295),
    encrypted_key bytea NOT NULL CHECK (octet_length(encrypted_key) >= 16),
    key_version integer NOT NULL DEFAULT 1 CHECK (key_version > 0),
    status text NOT NULL DEFAULT 'available'
        CHECK (status IN ('available', 'assigned', 'maintenance', 'retired', 'lost')),
    transaction_counter bigint NOT NULL DEFAULT 0 CHECK (transaction_counter >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, inventory_code),
    UNIQUE (tenant_id, protocol_id),
    UNIQUE (band_id, tenant_id)
);

CREATE TABLE gateways (
    gateway_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 160),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'retired')),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (site_id, tenant_id) REFERENCES sites (site_id, tenant_id),
    UNIQUE (site_id, code),
    UNIQUE (gateway_id, tenant_id, site_id)
);

CREATE TABLE attractions (
    attraction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 160),
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'maintenance', 'retired')),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (site_id, tenant_id) REFERENCES sites (site_id, tenant_id),
    UNIQUE (site_id, code),
    UNIQUE (attraction_id, tenant_id, site_id)
);

CREATE TABLE gateway_attractions (
    gateway_id uuid NOT NULL,
    attraction_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (gateway_id, attraction_id),
    FOREIGN KEY (gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id),
    FOREIGN KEY (attraction_id, tenant_id, site_id)
        REFERENCES attractions (attraction_id, tenant_id, site_id)
);

CREATE UNIQUE INDEX gateway_attractions_one_primary_idx
    ON gateway_attractions (attraction_id)
    WHERE is_primary;

CREATE TABLE operational_sessions (
    session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participant_id uuid,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed', 'cancelled')),
    opened_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    CHECK (closed_at IS NULL OR closed_at >= opened_at),
    FOREIGN KEY (event_id, tenant_id, site_id)
        REFERENCES events (event_id, tenant_id, site_id),
    FOREIGN KEY (participant_id, tenant_id)
        REFERENCES participants (participant_id, tenant_id),
    UNIQUE (session_id, tenant_id),
    UNIQUE (session_id, tenant_id, site_id, event_id)
);

CREATE TABLE wallets (
    wallet_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    session_id uuid NOT NULL,
    current_balance bigint NOT NULL DEFAULT 0 CHECK (current_balance >= 0),
    revision bigint NOT NULL DEFAULT 0 CHECK (revision >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (session_id, tenant_id)
        REFERENCES operational_sessions (session_id, tenant_id),
    UNIQUE (session_id),
    UNIQUE (wallet_id, tenant_id)
);

CREATE TABLE band_assignments (
    assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    session_id uuid NOT NULL,
    band_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'released', 'lost')),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    released_at timestamptz,
    CHECK (released_at IS NULL OR released_at >= assigned_at),
    FOREIGN KEY (session_id, tenant_id)
        REFERENCES operational_sessions (session_id, tenant_id),
    FOREIGN KEY (band_id, tenant_id) REFERENCES bands (band_id, tenant_id),
    UNIQUE (assignment_id, tenant_id)
);

CREATE UNIQUE INDEX band_assignments_one_active_band_idx
    ON band_assignments (band_id)
    WHERE status = 'active';

CREATE UNIQUE INDEX band_assignments_one_active_session_idx
    ON band_assignments (session_id)
    WHERE status = 'active';

-- +goose Down
DROP TABLE IF EXISTS band_assignments;
DROP TABLE IF EXISTS wallets;
DROP TABLE IF EXISTS operational_sessions;
DROP TABLE IF EXISTS gateway_attractions;
DROP TABLE IF EXISTS attractions;
DROP TABLE IF EXISTS gateways;
DROP TABLE IF EXISTS bands;
DROP TABLE IF EXISTS operators;
DROP TABLE IF EXISTS participants;
