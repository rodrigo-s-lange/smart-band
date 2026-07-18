INSERT INTO tenants (tenant_id, code, display_name)
VALUES ('11111111-1111-1111-1111-111111111111', 'vrplay', 'VRPlay');

INSERT INTO sites (site_id, tenant_id, code, display_name)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111',
    'shopping-piloto', 'VRPlay — Shopping Piloto'
);

INSERT INTO appliance_configuration (tenant_id, site_id, appliance_name)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    'vrplay-shopping-piloto'
);

INSERT INTO events (event_id, tenant_id, site_id, code, display_name, status)
VALUES (
    '33333333-3333-3333-3333-333333333333',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    'operacao-regular', 'Operação regular', 'active'
);

INSERT INTO participants (participant_id, tenant_id, external_reference, display_name)
VALUES (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111111', 'fixture-1', 'Participante de teste'
);

INSERT INTO operators (operator_id, tenant_id, login, display_name)
VALUES (
    '55555555-5555-5555-5555-555555555555',
    '11111111-1111-1111-1111-111111111111', 'operador-1', 'Operador de teste'
);

INSERT INTO bands (
    band_id, tenant_id, inventory_code, protocol_id, encrypted_key, status
) VALUES
    ('66666666-6666-6666-6666-666666666661', '11111111-1111-1111-1111-111111111111',
     'BAND-001', 1, decode(repeat('11', 32), 'hex'), 'assigned'),
    ('66666666-6666-6666-6666-666666666662', '11111111-1111-1111-1111-111111111111',
     'BAND-002', 2, decode(repeat('22', 32), 'hex'), 'assigned');

INSERT INTO gateways (
    gateway_id, tenant_id, site_id, code, display_name, protocol_id, api_key_hash
)
VALUES
    ('77777777-7777-7777-7777-777777777771', '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222', 'gateway-1', 'Gateway operador', 1,
     decode('f2bb58dacc874fec3b553e1eec858314417af6fcce64dd69f3938174d5ac8131', 'hex')),
    ('77777777-7777-7777-7777-777777777772', '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222', 'gateway-2', 'Gateway de rádio', 2,
     decode('f2bb58dacc874fec3b553e1eec858314417af6fcce64dd69f3938174d5ac8131', 'hex'));

INSERT INTO attractions (
    attraction_id, tenant_id, site_id, code, display_name, price_minor, protocol_id
) VALUES (
    '88888888-8888-8888-8888-888888888888',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    'vr-corrida', 'VR Corrida', 80, 10
);

INSERT INTO gateway_attractions (
    gateway_id, attraction_id, tenant_id, site_id, is_primary
) VALUES (
    '77777777-7777-7777-7777-777777777771',
    '88888888-8888-8888-8888-888888888888',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222', true
);

INSERT INTO operational_sessions (
    session_id, tenant_id, site_id, event_id, participant_id
) VALUES (
    '99999999-9999-9999-9999-999999999999',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333',
    '44444444-4444-4444-4444-444444444444'
);

INSERT INTO wallets (wallet_id, tenant_id, session_id, current_balance)
VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    '99999999-9999-9999-9999-999999999999', 100
);

INSERT INTO ledger_entries (
    ledger_entry_id, tenant_id, wallet_id, entry_kind, amount, balance_after, reason
) VALUES (
    'abababab-abab-abab-abab-abababababab',
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'load', 100, 100, 'Carga inicial da fixture'
);

INSERT INTO band_assignments (assignment_id, tenant_id, session_id, band_id)
VALUES (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '11111111-1111-1111-1111-111111111111',
    '99999999-9999-9999-9999-999999999999',
    '66666666-6666-6666-6666-666666666661'
);

INSERT INTO interaction_requests (
    interaction_id, tenant_id, site_id, event_id, band_id, session_nonce,
    display_code, protocol_version, state, first_authenticated_at, expires_at,
    protocol_id
) VALUES
    ('cccccccc-cccc-cccc-cccc-ccccccccccc1',
     '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     '33333333-3333-3333-3333-333333333333', '66666666-6666-6666-6666-666666666661',
     decode('0102030405060708', 'hex'), 'M7K-3PX', 1, 'confirmed_pending_validation', now(), now() + interval '60 seconds', 101),
    ('cccccccc-cccc-cccc-cccc-ccccccccccc2',
     '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     '33333333-3333-3333-3333-333333333333', '66666666-6666-6666-6666-666666666662',
     decode('1112131415161718', 'hex'), 'N8M-4QY', 1, 'confirmed_pending_validation', now(), now() + interval '60 seconds', 102);

INSERT INTO interaction_claims (
    claim_id, interaction_id, operator_gateway_id, attraction_id,
    tenant_id, site_id, lease_expires_at
) VALUES
    ('dddddddd-dddd-dddd-dddd-ddddddddddd1', 'cccccccc-cccc-cccc-cccc-ccccccccccc1',
     '77777777-7777-7777-7777-777777777771', '88888888-8888-8888-8888-888888888888',
     '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() + interval '30 seconds'),
    ('dddddddd-dddd-dddd-dddd-ddddddddddd2', 'cccccccc-cccc-cccc-cccc-ccccccccccc2',
     '77777777-7777-7777-7777-777777777771', '88888888-8888-8888-8888-888888888888',
     '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() + interval '30 seconds');

INSERT INTO transaction_intents (
    transaction_id, interaction_id, claim_id, tenant_id, site_id, wallet_id,
    attraction_id, operator_gateway_id, radio_gateway_id, amount,
    challenge_nonce, status, protocol_id
) VALUES
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1', 'cccccccc-cccc-cccc-cccc-ccccccccccc1',
     'dddddddd-dddd-dddd-dddd-ddddddddddd1', '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
     '88888888-8888-8888-8888-888888888888', '77777777-7777-7777-7777-777777777771',
     '77777777-7777-7777-7777-777777777772', 80, decode(repeat('31', 16), 'hex'),
     'confirmed_pending_validation', decode('00000000000000e1', 'hex')),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2', 'cccccccc-cccc-cccc-cccc-ccccccccccc2',
     'dddddddd-dddd-dddd-dddd-ddddddddddd2', '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
     '88888888-8888-8888-8888-888888888888', '77777777-7777-7777-7777-777777777771',
     '77777777-7777-7777-7777-777777777772', 80, decode(repeat('32', 16), 'hex'),
     'confirmed_pending_validation', decode('00000000000000e2', 'hex'));

INSERT INTO operator_sessions (token_hash, operator_id, tenant_id, expires_at)
VALUES (
    decode('58a11eec97f6f992da0f999abe1736e08d5271edd68d80835286e218c25eddfb', 'hex'),
    '55555555-5555-5555-5555-555555555555',
    '11111111-1111-1111-1111-111111111111', now() + interval '1 day'
);
