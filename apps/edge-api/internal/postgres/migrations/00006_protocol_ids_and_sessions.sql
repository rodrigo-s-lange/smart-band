-- +goose Up
ALTER TABLE gateways ADD COLUMN protocol_id integer;
ALTER TABLE gateways ADD COLUMN api_key_hash bytea;
ALTER TABLE attractions ADD COLUMN protocol_id integer;
ALTER TABLE interaction_requests ADD COLUMN protocol_id bigint;
ALTER TABLE transaction_intents ADD COLUMN protocol_id bytea;

WITH numbered AS (
    SELECT gateway_id, row_number() OVER (ORDER BY created_at, gateway_id) - 1 AS value
      FROM gateways
)
UPDATE gateways g
   SET protocol_id = numbered.value,
       api_key_hash = decode(repeat('00', 32), 'hex')
  FROM numbered
 WHERE numbered.gateway_id = g.gateway_id;

WITH numbered AS (
    SELECT attraction_id, row_number() OVER (ORDER BY created_at, attraction_id) - 1 AS value
      FROM attractions
)
UPDATE attractions a SET protocol_id = numbered.value
  FROM numbered WHERE numbered.attraction_id = a.attraction_id;

WITH numbered AS (
    SELECT interaction_id, row_number() OVER (ORDER BY created_at, interaction_id) - 1 AS value
      FROM interaction_requests
)
UPDATE interaction_requests i SET protocol_id = numbered.value
  FROM numbered WHERE numbered.interaction_id = i.interaction_id;

UPDATE transaction_intents
   SET protocol_id = substring(uuid_send(transaction_id) FROM 1 FOR 8);

ALTER TABLE gateways ALTER COLUMN protocol_id SET NOT NULL;
ALTER TABLE gateways ALTER COLUMN api_key_hash SET NOT NULL;
ALTER TABLE gateways ADD CHECK (protocol_id BETWEEN 0 AND 65535);
ALTER TABLE gateways ADD CHECK (octet_length(api_key_hash) = 32);
ALTER TABLE gateways ADD UNIQUE (protocol_id);

ALTER TABLE attractions ALTER COLUMN protocol_id SET NOT NULL;
ALTER TABLE attractions ADD CHECK (protocol_id BETWEEN 0 AND 65535);
ALTER TABLE attractions ADD UNIQUE (protocol_id);

ALTER TABLE interaction_requests ALTER COLUMN protocol_id SET NOT NULL;
ALTER TABLE interaction_requests ADD CHECK (protocol_id BETWEEN 0 AND 4294967295);
ALTER TABLE interaction_requests ADD UNIQUE (protocol_id);

ALTER TABLE transaction_intents ALTER COLUMN protocol_id SET NOT NULL;
ALTER TABLE transaction_intents ADD CHECK (octet_length(protocol_id) = 8);
ALTER TABLE transaction_intents ADD UNIQUE (protocol_id);

CREATE TABLE operator_sessions (
    token_hash bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
    operator_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CHECK (expires_at > created_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    FOREIGN KEY (operator_id, tenant_id) REFERENCES operators (operator_id, tenant_id)
);

CREATE INDEX operator_sessions_active_idx
    ON operator_sessions (expires_at)
    WHERE revoked_at IS NULL;

-- +goose Down
DROP TABLE IF EXISTS operator_sessions;
ALTER TABLE transaction_intents DROP COLUMN IF EXISTS protocol_id;
ALTER TABLE interaction_requests DROP COLUMN IF EXISTS protocol_id;
ALTER TABLE attractions DROP COLUMN IF EXISTS protocol_id;
ALTER TABLE gateways DROP COLUMN IF EXISTS api_key_hash;
ALTER TABLE gateways DROP COLUMN IF EXISTS protocol_id;
