INSERT INTO tenants (tenant_id, code, display_name)
VALUES ('11111111-1111-1111-1111-111111111111', 'legacy', 'Legacy fixture');

INSERT INTO sites (site_id, tenant_id, code, display_name)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111', 'legacy-site', 'Legacy site'
);

INSERT INTO appliance_configuration (tenant_id, site_id, appliance_name)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222', 'legacy-appliance'
);

INSERT INTO events (event_id, tenant_id, site_id, code, display_name, status)
VALUES (
    '33333333-3333-3333-3333-333333333333',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222', 'legacy-event', 'Legacy event', 'active'
);

INSERT INTO bands (
    band_id, tenant_id, inventory_code, protocol_id, encrypted_key
) VALUES (
    '66666666-6666-6666-6666-666666666666',
    '11111111-1111-1111-1111-111111111111', 'LEGACY-BAND', 1,
    decode(repeat('11', 32), 'hex')
);

INSERT INTO gateways (gateway_id, tenant_id, site_id, code, display_name)
VALUES (
    '77777777-7777-7777-7777-777777777777',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222', 'legacy-gateway', 'Legacy gateway'
);

INSERT INTO attractions (
    attraction_id, tenant_id, site_id, code, display_name, price_minor
) VALUES (
    '88888888-8888-8888-8888-888888888888',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222', 'legacy-attraction', 'Legacy attraction', 10
);

INSERT INTO operational_sessions (session_id, tenant_id, site_id, event_id)
VALUES (
    '99999999-9999-9999-9999-999999999999',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
);

INSERT INTO wallets (wallet_id, tenant_id, session_id, current_balance)
VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    '99999999-9999-9999-9999-999999999999', 100
);

INSERT INTO interaction_requests (
    interaction_id, tenant_id, site_id, event_id, band_id, session_nonce,
    display_code, protocol_version, state, first_authenticated_at, expires_at
) VALUES (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333',
    '66666666-6666-6666-6666-666666666666', decode('0102030405060708', 'hex'),
    'M7K-3PX', 1, 'claimed', now(), now() + interval '60 seconds'
);

INSERT INTO interaction_claims (
    claim_id, interaction_id, operator_gateway_id, attraction_id,
    tenant_id, site_id, lease_expires_at
) VALUES (
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '77777777-7777-7777-7777-777777777777',
    '88888888-8888-8888-8888-888888888888',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222', now() + interval '30 seconds'
);

INSERT INTO transaction_intents (
    transaction_id, interaction_id, claim_id, tenant_id, site_id, wallet_id,
    attraction_id, operator_gateway_id, radio_gateway_id, amount,
    challenge_nonce, status
) VALUES (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '88888888-8888-8888-8888-888888888888',
    '77777777-7777-7777-7777-777777777777',
    '77777777-7777-7777-7777-777777777777', 10,
    decode(repeat('31', 16), 'hex'), 'awaiting_band_confirmation'
);
