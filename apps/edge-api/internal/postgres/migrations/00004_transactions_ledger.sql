-- +goose Up
CREATE TABLE transaction_intents (
    transaction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    interaction_id uuid NOT NULL UNIQUE,
    claim_id uuid NOT NULL UNIQUE,
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    wallet_id uuid NOT NULL,
    attraction_id uuid NOT NULL,
    operator_gateway_id uuid NOT NULL,
    radio_gateway_id uuid NOT NULL,
    amount bigint NOT NULL CHECK (amount > 0),
    challenge_nonce bytea NOT NULL CHECK (octet_length(challenge_nonce) = 16),
    status text NOT NULL CHECK (status IN (
        'awaiting_band_confirmation', 'confirmed_pending_validation',
        'credit_reserved', 'actuation_pending', 'completed', 'denied',
        'confirmation_timeout', 'actuation_failed',
        'reconciliation_required', 'cancelled'
    )),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (interaction_id, tenant_id, site_id)
        REFERENCES interaction_requests (interaction_id, tenant_id, site_id),
    FOREIGN KEY (claim_id, tenant_id, site_id)
        REFERENCES interaction_claims (claim_id, tenant_id, site_id),
    FOREIGN KEY (wallet_id, tenant_id) REFERENCES wallets (wallet_id, tenant_id),
    FOREIGN KEY (attraction_id, tenant_id, site_id)
        REFERENCES attractions (attraction_id, tenant_id, site_id),
    FOREIGN KEY (operator_gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id),
    FOREIGN KEY (radio_gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id),
    UNIQUE (transaction_id, tenant_id),
    UNIQUE (transaction_id, tenant_id, site_id)
);

CREATE TABLE credit_reservations (
    reservation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id uuid NOT NULL UNIQUE,
    tenant_id uuid NOT NULL,
    wallet_id uuid NOT NULL,
    amount bigint NOT NULL CHECK (amount > 0),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'consumed', 'released')),
    reserved_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CHECK ((status = 'active' AND resolved_at IS NULL) OR
           (status <> 'active' AND resolved_at IS NOT NULL)),
    FOREIGN KEY (transaction_id, tenant_id)
        REFERENCES transaction_intents (transaction_id, tenant_id),
    FOREIGN KEY (wallet_id, tenant_id) REFERENCES wallets (wallet_id, tenant_id),
    UNIQUE (reservation_id, tenant_id)
);

CREATE INDEX credit_reservations_active_wallet_idx
    ON credit_reservations (wallet_id)
    WHERE status = 'active';

CREATE TABLE actuation_commands (
    actuation_command_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    operator_gateway_id uuid NOT NULL,
    attraction_id uuid NOT NULL,
    attempt_number smallint NOT NULL CHECK (attempt_number BETWEEN 1 AND 3),
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'succeeded', 'not_executed', 'ambiguous')),
    created_at timestamptz NOT NULL DEFAULT now(),
    acknowledged_at timestamptz,
    CHECK ((status = 'pending' AND acknowledged_at IS NULL) OR
           (status <> 'pending' AND acknowledged_at IS NOT NULL)),
    FOREIGN KEY (transaction_id, tenant_id, site_id)
        REFERENCES transaction_intents (transaction_id, tenant_id, site_id),
    FOREIGN KEY (operator_gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id),
    FOREIGN KEY (attraction_id, tenant_id, site_id)
        REFERENCES attractions (attraction_id, tenant_id, site_id),
    UNIQUE (transaction_id, attempt_number)
);

CREATE TABLE ledger_entries (
    ledger_entry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    wallet_id uuid NOT NULL,
    transaction_id uuid,
    entry_kind text NOT NULL CHECK (entry_kind IN ('load', 'debit', 'refund', 'adjustment')),
    amount bigint NOT NULL CHECK (amount <> 0),
    balance_after bigint NOT NULL CHECK (balance_after >= 0),
    reason text,
    operator_id uuid,
    committed_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((entry_kind = 'debit' AND amount < 0 AND transaction_id IS NOT NULL) OR
           (entry_kind <> 'debit')),
    FOREIGN KEY (wallet_id, tenant_id) REFERENCES wallets (wallet_id, tenant_id),
    FOREIGN KEY (transaction_id, tenant_id)
        REFERENCES transaction_intents (transaction_id, tenant_id),
    FOREIGN KEY (operator_id, tenant_id) REFERENCES operators (operator_id, tenant_id)
);

CREATE UNIQUE INDEX ledger_entries_one_debit_per_transaction_idx
    ON ledger_entries (transaction_id)
    WHERE entry_kind = 'debit';

CREATE TABLE operational_resolutions (
    resolution_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    site_id uuid NOT NULL,
    operator_id uuid NOT NULL,
    operator_gateway_id uuid NOT NULL,
    action text NOT NULL CHECK (action IN (
        'retry_actuation', 'release_reservation', 'manual_confirmation'
    )),
    reason text NOT NULL CHECK (length(trim(reason)) >= 3),
    resolved_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (transaction_id, tenant_id, site_id)
        REFERENCES transaction_intents (transaction_id, tenant_id, site_id),
    FOREIGN KEY (operator_id, tenant_id) REFERENCES operators (operator_id, tenant_id),
    FOREIGN KEY (operator_gateway_id, tenant_id, site_id)
        REFERENCES gateways (gateway_id, tenant_id, site_id)
);

CREATE OR REPLACE FUNCTION smartband_validate_reservation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction transaction_intents%ROWTYPE;
BEGIN
    SELECT * INTO v_transaction FROM transaction_intents
     WHERE transaction_id = NEW.transaction_id;
    IF NOT FOUND OR v_transaction.tenant_id <> NEW.tenant_id
       OR v_transaction.wallet_id <> NEW.wallet_id
       OR v_transaction.amount <> NEW.amount
       OR v_transaction.status <> 'confirmed_pending_validation' THEN
        RAISE EXCEPTION 'reservation does not match a confirmable transaction'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER credit_reservations_match_transaction
BEFORE INSERT ON credit_reservations
FOR EACH ROW EXECUTE FUNCTION smartband_validate_reservation();

CREATE OR REPLACE FUNCTION smartband_validate_actuation_command()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction transaction_intents%ROWTYPE;
BEGIN
    SELECT * INTO v_transaction FROM transaction_intents
     WHERE transaction_id = NEW.transaction_id;
    IF NOT FOUND OR v_transaction.tenant_id <> NEW.tenant_id
       OR v_transaction.site_id <> NEW.site_id
       OR v_transaction.operator_gateway_id <> NEW.operator_gateway_id
       OR v_transaction.attraction_id <> NEW.attraction_id
       OR v_transaction.status NOT IN ('credit_reserved', 'actuation_failed') THEN
        RAISE EXCEPTION 'actuation command does not match a reserved transaction'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER actuation_commands_match_transaction
BEFORE INSERT ON actuation_commands
FOR EACH ROW EXECUTE FUNCTION smartband_validate_actuation_command();

CREATE OR REPLACE FUNCTION smartband_validate_ledger_entry()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction transaction_intents%ROWTYPE;
    v_reservation credit_reservations%ROWTYPE;
BEGIN
    IF NEW.entry_kind IN ('refund', 'adjustment')
       AND (NEW.operator_id IS NULL OR length(trim(COALESCE(NEW.reason, ''))) < 3) THEN
        RAISE EXCEPTION 'refund and adjustment require operator and reason'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.entry_kind = 'debit' THEN
        SELECT * INTO v_transaction FROM transaction_intents
         WHERE transaction_id = NEW.transaction_id;
        SELECT * INTO v_reservation FROM credit_reservations
         WHERE transaction_id = NEW.transaction_id;
        IF NOT FOUND OR v_transaction.status <> 'actuation_pending'
           OR v_transaction.tenant_id <> NEW.tenant_id
           OR v_reservation.status <> 'active'
           OR v_reservation.wallet_id <> NEW.wallet_id
           OR NEW.amount <> -v_reservation.amount THEN
            RAISE EXCEPTION 'debit requires a matching active reservation and pending actuation'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER ledger_entries_validate_insert
BEFORE INSERT ON ledger_entries
FOR EACH ROW EXECUTE FUNCTION smartband_validate_ledger_entry();

CREATE OR REPLACE FUNCTION smartband_reject_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'ledger_entries is append-only' USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER ledger_entries_append_only
BEFORE UPDATE OR DELETE ON ledger_entries
FOR EACH ROW EXECUTE FUNCTION smartband_reject_ledger_mutation();

CREATE OR REPLACE FUNCTION smartband_reserve_credit(p_transaction_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction transaction_intents%ROWTYPE;
    v_balance bigint;
    v_reserved bigint;
    v_reservation_id uuid;
BEGIN
    SELECT * INTO v_transaction
      FROM transaction_intents
     WHERE transaction_id = p_transaction_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'transaction % not found', p_transaction_id USING ERRCODE = 'P0002';
    END IF;

    SELECT reservation_id INTO v_reservation_id
      FROM credit_reservations
     WHERE transaction_id = p_transaction_id;
    IF FOUND THEN
        RETURN v_reservation_id;
    END IF;

    IF v_transaction.status <> 'confirmed_pending_validation' THEN
        RAISE EXCEPTION 'transaction % cannot reserve from status %',
            p_transaction_id, v_transaction.status USING ERRCODE = '23514';
    END IF;

    SELECT current_balance INTO v_balance
      FROM wallets
     WHERE wallet_id = v_transaction.wallet_id
     FOR UPDATE;

    SELECT COALESCE(sum(amount), 0) INTO v_reserved
      FROM credit_reservations
     WHERE wallet_id = v_transaction.wallet_id
       AND status = 'active';

    IF v_balance - v_reserved < v_transaction.amount THEN
        RAISE EXCEPTION 'insufficient available balance' USING ERRCODE = '23514';
    END IF;

    INSERT INTO credit_reservations (
        transaction_id, tenant_id, wallet_id, amount
    ) VALUES (
        v_transaction.transaction_id, v_transaction.tenant_id,
        v_transaction.wallet_id, v_transaction.amount
    ) RETURNING reservation_id INTO v_reservation_id;

    UPDATE transaction_intents
       SET status = 'credit_reserved', updated_at = now()
     WHERE transaction_id = p_transaction_id;

    UPDATE interaction_requests
       SET state = 'credit_reserved'
     WHERE interaction_id = v_transaction.interaction_id;

    RETURN v_reservation_id;
END;
$$;

CREATE OR REPLACE FUNCTION smartband_dispatch_actuation(
    p_transaction_id uuid,
    p_actuation_command_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction transaction_intents%ROWTYPE;
    v_attempt_number smallint;
    v_existing_command_id uuid;
    v_existing_transaction_id uuid;
BEGIN
    SELECT * INTO v_transaction
      FROM transaction_intents
     WHERE transaction_id = p_transaction_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'transaction % not found', p_transaction_id USING ERRCODE = 'P0002';
    END IF;

    SELECT actuation_command_id, transaction_id
      INTO v_existing_command_id, v_existing_transaction_id
      FROM actuation_commands
     WHERE actuation_command_id = p_actuation_command_id;
    IF FOUND THEN
        IF v_existing_transaction_id <> p_transaction_id THEN
            RAISE EXCEPTION 'actuation command % belongs to another transaction',
                p_actuation_command_id USING ERRCODE = '23514';
        END IF;
        RETURN v_existing_command_id;
    END IF;

    IF v_transaction.status NOT IN ('credit_reserved', 'actuation_failed') THEN
        RAISE EXCEPTION 'transaction % cannot dispatch from status %',
            p_transaction_id, v_transaction.status USING ERRCODE = '23514';
    END IF;

    SELECT (COALESCE(max(attempt_number), 0) + 1)::smallint INTO v_attempt_number
      FROM actuation_commands
     WHERE transaction_id = p_transaction_id;

    IF v_attempt_number > 3 THEN
        RAISE EXCEPTION 'transaction % exhausted actuation attempts',
            p_transaction_id USING ERRCODE = '23514';
    END IF;

    INSERT INTO actuation_commands (
        actuation_command_id, transaction_id, tenant_id, site_id,
        operator_gateway_id, attraction_id, attempt_number
    ) VALUES (
        p_actuation_command_id, v_transaction.transaction_id,
        v_transaction.tenant_id, v_transaction.site_id,
        v_transaction.operator_gateway_id, v_transaction.attraction_id,
        v_attempt_number
    );

    UPDATE transaction_intents
       SET status = 'actuation_pending', updated_at = now()
     WHERE transaction_id = p_transaction_id;
    UPDATE interaction_requests
       SET state = 'actuation_pending'
     WHERE interaction_id = v_transaction.interaction_id;

    RETURN p_actuation_command_id;
END;
$$;

CREATE OR REPLACE FUNCTION smartband_cancel_before_dispatch(p_transaction_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction transaction_intents%ROWTYPE;
BEGIN
    SELECT * INTO v_transaction
      FROM transaction_intents
     WHERE transaction_id = p_transaction_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'transaction % not found', p_transaction_id USING ERRCODE = 'P0002';
    END IF;
    IF v_transaction.status = 'cancelled' THEN
        RETURN true;
    END IF;
    IF v_transaction.status <> 'credit_reserved' THEN
        RAISE EXCEPTION 'transaction % cannot cancel from status %',
            p_transaction_id, v_transaction.status USING ERRCODE = '23514';
    END IF;

    UPDATE credit_reservations
       SET status = 'released', resolved_at = now()
     WHERE transaction_id = p_transaction_id AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active reservation missing for transaction %',
            p_transaction_id USING ERRCODE = '23514';
    END IF;

    UPDATE transaction_intents SET status = 'cancelled', updated_at = now()
     WHERE transaction_id = p_transaction_id;
    UPDATE interaction_requests SET state = 'cancelled'
     WHERE interaction_id = v_transaction.interaction_id;
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION smartband_record_actuation_ack(
    p_actuation_command_id uuid,
    p_result text,
    p_acknowledged_at timestamptz DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_command actuation_commands%ROWTYPE;
    v_transaction transaction_intents%ROWTYPE;
    v_reservation credit_reservations%ROWTYPE;
    v_balance bigint;
    v_ledger_entry_id uuid;
BEGIN
    IF p_result NOT IN ('succeeded', 'not_executed', 'ambiguous') THEN
        RAISE EXCEPTION 'invalid actuation result %', p_result USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_command
      FROM actuation_commands
     WHERE actuation_command_id = p_actuation_command_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'actuation command % not found', p_actuation_command_id USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_transaction
      FROM transaction_intents
     WHERE transaction_id = v_command.transaction_id
     FOR UPDATE;

    IF v_command.status <> 'pending' THEN
        IF v_command.status <> p_result THEN
            RAISE EXCEPTION 'conflicting ack for command %', p_actuation_command_id USING ERRCODE = '23514';
        END IF;
        SELECT ledger_entry_id INTO v_ledger_entry_id
          FROM ledger_entries
         WHERE transaction_id = v_command.transaction_id
           AND entry_kind = 'debit';
        RETURN v_ledger_entry_id;
    END IF;

    IF v_transaction.status <> 'actuation_pending' THEN
        RAISE EXCEPTION 'transaction % cannot accept ack from status %',
            v_transaction.transaction_id, v_transaction.status USING ERRCODE = '23514';
    END IF;

    UPDATE actuation_commands
       SET status = p_result, acknowledged_at = p_acknowledged_at
     WHERE actuation_command_id = p_actuation_command_id;

    IF p_result = 'not_executed' THEN
        UPDATE transaction_intents SET status = 'actuation_failed', updated_at = now()
         WHERE transaction_id = v_command.transaction_id;
        UPDATE interaction_requests SET state = 'actuation_failed'
         WHERE interaction_id = v_transaction.interaction_id;
        RETURN NULL;
    ELSIF p_result = 'ambiguous' THEN
        UPDATE transaction_intents SET status = 'reconciliation_required', updated_at = now()
         WHERE transaction_id = v_command.transaction_id;
        UPDATE interaction_requests SET state = 'reconciliation_required'
         WHERE interaction_id = v_transaction.interaction_id;
        RETURN NULL;
    END IF;

    SELECT * INTO v_reservation
      FROM credit_reservations
     WHERE transaction_id = v_command.transaction_id
     FOR UPDATE;

    IF NOT FOUND OR v_reservation.status <> 'active' THEN
        RAISE EXCEPTION 'active reservation missing for transaction %',
            v_command.transaction_id USING ERRCODE = '23514';
    END IF;

    SELECT current_balance INTO v_balance
      FROM wallets
     WHERE wallet_id = v_reservation.wallet_id
     FOR UPDATE;

    IF v_balance < v_reservation.amount THEN
        RAISE EXCEPTION 'wallet balance below reserved amount' USING ERRCODE = '23514';
    END IF;

    UPDATE wallets
       SET current_balance = current_balance - v_reservation.amount,
           revision = revision + 1,
           updated_at = now()
     WHERE wallet_id = v_reservation.wallet_id
     RETURNING current_balance INTO v_balance;

    INSERT INTO ledger_entries (
        tenant_id, wallet_id, transaction_id, entry_kind, amount, balance_after
    ) VALUES (
        v_reservation.tenant_id, v_reservation.wallet_id,
        v_reservation.transaction_id, 'debit', -v_reservation.amount, v_balance
    ) RETURNING ledger_entry_id INTO v_ledger_entry_id;

    UPDATE credit_reservations
       SET status = 'consumed', resolved_at = p_acknowledged_at
     WHERE reservation_id = v_reservation.reservation_id;

    UPDATE transaction_intents SET status = 'completed', updated_at = now()
     WHERE transaction_id = v_command.transaction_id;
    UPDATE interaction_requests SET state = 'completed'
     WHERE interaction_id = v_transaction.interaction_id;

    RETURN v_ledger_entry_id;
END;
$$;

-- +goose Down
DROP FUNCTION IF EXISTS smartband_record_actuation_ack(uuid, text, timestamptz);
DROP FUNCTION IF EXISTS smartband_cancel_before_dispatch(uuid);
DROP FUNCTION IF EXISTS smartband_dispatch_actuation(uuid, uuid);
DROP FUNCTION IF EXISTS smartband_reserve_credit(uuid);
DROP TRIGGER IF EXISTS ledger_entries_append_only ON ledger_entries;
DROP FUNCTION IF EXISTS smartband_reject_ledger_mutation();
DROP TRIGGER IF EXISTS ledger_entries_validate_insert ON ledger_entries;
DROP FUNCTION IF EXISTS smartband_validate_ledger_entry();
DROP TRIGGER IF EXISTS actuation_commands_match_transaction ON actuation_commands;
DROP FUNCTION IF EXISTS smartband_validate_actuation_command();
DROP TRIGGER IF EXISTS credit_reservations_match_transaction ON credit_reservations;
DROP FUNCTION IF EXISTS smartband_validate_reservation();
DROP TABLE IF EXISTS operational_resolutions;
DROP TABLE IF EXISTS ledger_entries;
DROP TABLE IF EXISTS actuation_commands;
DROP TABLE IF EXISTS credit_reservations;
DROP TABLE IF EXISTS transaction_intents;
