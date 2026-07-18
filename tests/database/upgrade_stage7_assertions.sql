DO $$
BEGIN
    IF to_regclass('public.operator_sessions') IS NOT NULL THEN
        RAISE EXCEPTION 'operator sessions still exist after gateway identity migration';
    END IF;

    IF to_regclass('public.operators') IS NOT NULL THEN
        RAISE EXCEPTION 'human operator registry still exists';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND column_name = 'operator_id'
           AND table_name IN ('operational_resolutions', 'ledger_entries', 'audit_records')
    ) THEN
        RAISE EXCEPTION 'operational tables still carry human operator identity';
    END IF;

    IF to_regprocedure(
        'smartband_claim_interaction(bigint,integer,integer,bytea,bytea,timestamp with time zone)'
    ) IS NULL THEN
        RAISE EXCEPTION 'gateway-authenticated claim function is absent';
    END IF;

    INSERT INTO ledger_entries (
        tenant_id, wallet_id, entry_kind, amount, balance_after, reason
    ) VALUES (
        '11111111-1111-1111-1111-111111111111',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'adjustment', 1, 101, 'Ajuste auditado pela appliance'
    );
END;
$$;
