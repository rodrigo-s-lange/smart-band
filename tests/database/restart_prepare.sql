SELECT smartband_reserve_credit('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1');

SELECT smartband_dispatch_actuation(
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1',
    'ffffffff-ffff-ffff-ffff-fffffffffff1'
);

UPDATE interaction_requests
   SET state = 'claimed', expires_at = now() + interval '60 seconds'
 WHERE interaction_id = 'cccccccc-cccc-cccc-cccc-ccccccccccc2';
UPDATE interaction_claims
   SET status = 'active', attempt_count = 1, lease_expires_at = now() + interval '10 seconds'
 WHERE claim_id = 'dddddddd-dddd-dddd-dddd-ddddddddddd2';
UPDATE transaction_intents
   SET status = 'claimed', updated_at = now()
 WHERE transaction_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2';
INSERT INTO interaction_sightings (
    interaction_id, gateway_id, tenant_id, site_id, rssi,
    received_at, gateway_observed_at
) VALUES (
    'cccccccc-cccc-cccc-cccc-ccccccccccc2',
    '77777777-7777-7777-7777-777777777772',
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    -40, now(), now()
);
SELECT result
  FROM smartband_start_radio_dispatch(
      decode('00000000000000e2', 'hex'),
      '12121212-1212-4212-8212-121212121212',
      decode('4142434445464748', 'hex'),
      7,
      decode('deadbeef', 'hex'),
      now()
  );
UPDATE radio_dispatch_attempts
   SET worker_id = '23232323-2323-4323-8323-232323232323',
       work_lease_expires_at = now() + interval '2 seconds'
 WHERE dispatch_id = '12121212-1212-4212-8212-121212121212';
