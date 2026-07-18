-- name: GetApplianceContext :one
SELECT
    ac.tenant_id::text AS tenant_id,
    t.code AS tenant_code,
    t.display_name AS tenant_name,
    ac.site_id::text AS site_id,
    s.code AS site_code,
    s.display_name AS site_name,
    s.timezone,
    ac.appliance_name,
    COALESCE(e.event_id::text, '')::text AS event_id,
    COALESCE(e.code, '') AS event_code,
    COALESCE(e.display_name, '') AS event_name
FROM appliance_configuration ac
JOIN tenants t ON t.tenant_id = ac.tenant_id
JOIN sites s ON s.site_id = ac.site_id AND s.tenant_id = ac.tenant_id
LEFT JOIN events e ON e.site_id = ac.site_id AND e.status = 'active'
WHERE ac.singleton_id = 1;

-- name: ListQueue :many
SELECT
    i.protocol_id,
    i.display_code,
    i.state,
    i.created_at
FROM interaction_requests i
JOIN appliance_configuration ac ON ac.site_id = i.site_id
JOIN events e ON e.event_id = i.event_id AND e.status = 'active'
WHERE i.state IN ('queued', 'queued_ambiguous')
  AND i.expires_at > now()
ORDER BY i.created_at DESC, i.protocol_id DESC;

-- name: AuthenticateGateway :one
SELECT gateway_id::text AS gateway_id, protocol_id
FROM gateways
WHERE api_key_hash = $1 AND status = 'active'
LIMIT 1;

-- name: AuthenticateOperator :one
SELECT o.operator_id::text AS operator_id, o.display_name
FROM operator_sessions s
JOIN operators o ON o.operator_id = s.operator_id AND o.tenant_id = s.tenant_id
WHERE s.token_hash = $1
  AND s.revoked_at IS NULL
  AND s.expires_at > now()
  AND o.status = 'active'
LIMIT 1;

-- name: ListAttractions :many
SELECT protocol_id, display_name, price_minor
FROM attractions a
JOIN appliance_configuration ac ON ac.site_id = a.site_id
WHERE a.status = 'active'
ORDER BY a.display_name;

-- name: ListGateways :many
SELECT
    g.protocol_id,
    CASE WHEN EXISTS (
        SELECT 1 FROM gateway_attractions ga WHERE ga.gateway_id = g.gateway_id
    ) THEN 'both'::text ELSE 'radio'::text END AS role,
    CASE g.status
        WHEN 'active' THEN 'offline'::text
        WHEN 'maintenance' THEN 'degraded'::text
        ELSE 'offline'::text
    END AS operational_status
FROM gateways g
JOIN appliance_configuration ac ON ac.site_id = g.site_id
ORDER BY g.protocol_id;

-- name: ListBands :many
SELECT
    b.band_id::text AS band_id,
    b.created_at AS provisioned_at,
    COALESCE(w.current_balance, 0)::bigint AS balance
FROM bands b
JOIN appliance_configuration ac ON ac.tenant_id = b.tenant_id
LEFT JOIN band_assignments ba ON ba.band_id = b.band_id AND ba.status = 'active'
LEFT JOIN wallets w ON w.session_id = ba.session_id
WHERE b.status <> 'retired'
ORDER BY b.inventory_code;
