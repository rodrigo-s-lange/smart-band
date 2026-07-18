-- +goose Up
CREATE TABLE outbox_events (
    outbox_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants (tenant_id),
    aggregate_type text NOT NULL,
    aggregate_id uuid NOT NULL,
    event_type text NOT NULL,
    event_version integer NOT NULL CHECK (event_version > 0),
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0)
);

CREATE INDEX outbox_events_pending_idx
    ON outbox_events (occurred_at)
    WHERE published_at IS NULL;

CREATE TABLE audit_records (
    audit_record_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants (tenant_id),
    site_id uuid,
    operator_id uuid,
    gateway_id uuid,
    action text NOT NULL,
    subject_type text NOT NULL,
    subject_id uuid,
    details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object'),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CHECK (gateway_id IS NULL OR site_id IS NOT NULL),
    FOREIGN KEY (site_id, tenant_id) REFERENCES sites (site_id, tenant_id),
    FOREIGN KEY (operator_id, tenant_id) REFERENCES operators (operator_id, tenant_id),
    FOREIGN KEY (gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id)
);

CREATE INDEX audit_records_subject_idx
    ON audit_records (subject_type, subject_id, occurred_at DESC);

-- +goose Down
DROP TABLE IF EXISTS audit_records;
DROP TABLE IF EXISTS outbox_events;
