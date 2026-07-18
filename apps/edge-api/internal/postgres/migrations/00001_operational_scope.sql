-- +goose Up
CREATE TABLE tenants (
    tenant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE CHECK (code ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 160),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sites (
    site_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants (tenant_id),
    code text NOT NULL CHECK (code ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 160),
    timezone text NOT NULL DEFAULT 'America/Sao_Paulo',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, code),
    UNIQUE (site_id, tenant_id)
);

CREATE TABLE appliance_configuration (
    singleton_id smallint PRIMARY KEY DEFAULT 1 CHECK (singleton_id = 1),
    tenant_id uuid NOT NULL REFERENCES tenants (tenant_id),
    site_id uuid NOT NULL,
    appliance_name text NOT NULL CHECK (length(trim(appliance_name)) BETWEEN 1 AND 120),
    installed_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (site_id, tenant_id) REFERENCES sites (site_id, tenant_id)
);

CREATE TABLE events (
    event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    code text NOT NULL CHECK (code ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 160),
    status text NOT NULL CHECK (status IN ('planned', 'active', 'closed', 'cancelled')),
    starts_at timestamptz,
    ends_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at),
    FOREIGN KEY (site_id, tenant_id) REFERENCES sites (site_id, tenant_id),
    UNIQUE (site_id, code),
    UNIQUE (event_id, tenant_id, site_id)
);

CREATE UNIQUE INDEX events_one_active_per_site_idx
    ON events (site_id)
    WHERE status = 'active';

-- +goose Down
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS appliance_configuration;
DROP TABLE IF EXISTS sites;
DROP TABLE IF EXISTS tenants;
