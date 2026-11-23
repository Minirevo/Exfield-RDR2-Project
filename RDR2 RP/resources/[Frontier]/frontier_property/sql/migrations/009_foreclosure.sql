ALTER TABLE frontier_property_finance
    ADD COLUMN IF NOT EXISTS next_due DATETIME NULL,
    ADD COLUMN IF NOT EXISTS debt_since DATETIME NULL;

CREATE TABLE IF NOT EXISTS frontier_property_upkeep_payments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    property_id BIGINT UNSIGNED NOT NULL,
    account_id BIGINT UNSIGNED NOT NULL,
    amount_cents BIGINT UNSIGNED NOT NULL,
    state ENUM('pending','paid','declined') NOT NULL DEFAULT 'pending',
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_frontier_upkeep_work (state,retry_at,id),
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_property_foreclosures (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    property_id BIGINT UNSIGNED NOT NULL UNIQUE,
    valuation_cents BIGINT UNSIGNED NOT NULL,
    deduction_cents BIGINT UNSIGNED NOT NULL,
    debt_paid_cents BIGINT UNSIGNED NOT NULL,
    debt_forgiven_cents BIGINT UNSIGNED NOT NULL,
    state_penalty_cents BIGINT UNSIGNED NOT NULL,
    owner_payout_cents BIGINT UNSIGNED NOT NULL,
    treasury_bank_id BIGINT UNSIGNED NOT NULL,
    treasury_paid BOOLEAN NOT NULL DEFAULT FALSE,
    state ENUM('pending','done') NOT NULL DEFAULT 'pending',
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_frontier_foreclosure_work (state,retry_at,id),
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_property_foreclosure_payees (
    foreclosure_id BIGINT UNSIGNED NOT NULL,
    owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    share_bps SMALLINT UNSIGNED NOT NULL,
    bank_id BIGINT UNSIGNED NULL,
    paid BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (foreclosure_id,owner_id),
    FOREIGN KEY (foreclosure_id) REFERENCES frontier_property_foreclosures(id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_upkeep_accrue_v1(
    IN target BIGINT UNSIGNED, IN rate INT UNSIGNED, IN period_seconds INT UNSIGNED)
BEGIN
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE valuation BIGINT UNSIGNED;
    DECLARE next_charge DATETIME;
    DECLARE periods BIGINT UNSIGNED;
    DECLARE charge DECIMAL(30,0);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id,estimated_value_cents INTO estate,valuation FROM frontier_properties
        WHERE id=target AND status='active' FOR UPDATE;
    IF estate IS NOT NULL AND EXISTS (SELECT 1 FROM frontier_property_ownership
        WHERE property_id=target AND party_type='character')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_sales WHERE property_id=target AND state='reserved') THEN
        INSERT IGNORE INTO frontier_property_finance (property_id) VALUES (target);
        UPDATE frontier_property_finance SET next_due=DATE_ADD(UTC_TIMESTAMP(), INTERVAL period_seconds SECOND)
            WHERE property_id=target AND next_due IS NULL;
        SELECT next_due INTO next_charge FROM frontier_property_finance WHERE property_id=target;
        IF next_charge<=UTC_TIMESTAMP() THEN
            SET periods=1+TIMESTAMPDIFF(SECOND,next_charge,UTC_TIMESTAMP()) DIV period_seconds;
            SET charge=GREATEST(1,CAST(valuation AS DECIMAL(24,0))*rate DIV 10000)*periods;
            UPDATE frontier_property_finance SET debt_since=COALESCE(debt_since,next_due),
                debt_cents=LEAST(9000000000000,debt_cents+charge),
                next_due=DATE_ADD(next_due,INTERVAL (period_seconds*periods) SECOND)
                WHERE property_id=target;
        END IF;
    END IF;
    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE frontier_upkeep_reserve_v1(
    IN target BIGINT UNSIGNED, IN actor CHAR(34), IN bank BIGINT UNSIGNED, IN expected BIGINT UNSIGNED)
BEGIN
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE payment BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO estate FROM frontier_properties WHERE id=target AND status='active' FOR UPDATE;
    IF estate IS NOT NULL AND expected>0
      AND (SELECT debt_cents FROM frontier_property_finance WHERE property_id=target)=expected
      AND EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target
        AND party_type='character' AND party_id=actor)
      AND NOT EXISTS (SELECT 1 FROM frontier_property_upkeep_payments WHERE property_id=target AND state='pending') THEN
        INSERT INTO frontier_property_upkeep_payments (property_id,account_id,amount_cents) VALUES (target,bank,expected);
        SET payment=LAST_INSERT_ID();
    END IF;
    COMMIT;
    SELECT payment AS id;
END$$

CREATE OR REPLACE PROCEDURE frontier_upkeep_finish_v1(IN payment BIGINT UNSIGNED, IN collected BOOLEAN)
BEGIN
    DECLARE target BIGINT UNSIGNED DEFAULT NULL;
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE amount BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT MAX(property_id) INTO target FROM frontier_property_upkeep_payments WHERE id=payment;
    SELECT id INTO estate FROM frontier_properties WHERE id=target FOR UPDATE;
    SELECT amount_cents INTO amount FROM frontier_property_upkeep_payments
        WHERE id=payment AND state='pending' FOR UPDATE;
    IF estate IS NOT NULL AND amount IS NOT NULL THEN
        IF collected THEN
            UPDATE frontier_property_finance SET debt_since=IF(debt_cents<=amount,NULL,debt_since),
                debt_cents=debt_cents-LEAST(debt_cents,amount) WHERE property_id=target;
        END IF;
        UPDATE frontier_property_upkeep_payments SET state=IF(collected,'paid','declined') WHERE id=payment;
    END IF;
    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE frontier_foreclosure_open_v1(
    IN target BIGINT UNSIGNED, IN threshold BIGINT UNSIGNED, IN grace_seconds INT UNSIGNED,
    IN reduction_bps INT UNSIGNED, IN penalty_bps INT UNSIGNED, IN treasury BIGINT UNSIGNED)
BEGIN
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE liquidation BIGINT UNSIGNED;
    DECLARE debt BIGINT UNSIGNED;
    DECLARE valuation BIGINT UNSIGNED;
    DECLARE deduction BIGINT UNSIGNED;
    DECLARE debt_payment BIGINT UNSIGNED;
    DECLARE surplus BIGINT UNSIGNED;
    DECLARE penalty BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO estate FROM frontier_properties WHERE id=target AND status='active' FOR UPDATE;
    IF estate IS NOT NULL AND treasury>0
      AND EXISTS (SELECT 1 FROM frontier_property_finance WHERE property_id=target AND debt_cents>=threshold
        AND TIMESTAMPDIFF(SECOND,debt_since,UTC_TIMESTAMP())>=grace_seconds)
      AND (SELECT SUM(share_bps) FROM frontier_property_ownership WHERE property_id=target AND party_type='character')=10000
      AND NOT EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target AND party_type<>'character')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_sales WHERE property_id=target AND state='reserved')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_rentals WHERE property_id=target
        AND (state='reserved' OR (state='active' AND ends_at>UTC_TIMESTAMP())))
      AND NOT EXISTS (SELECT 1 FROM frontier_property_furniture WHERE property_id=target AND state='pending')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_build_jobs j JOIN frontier_property_construction b
        ON b.id=j.site_id WHERE b.property_id=target AND j.state='pending')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_upkeep_payments WHERE property_id=target AND state='pending') THEN
        SELECT debt_cents INTO debt FROM frontier_property_finance WHERE property_id=target;
        SELECT LEAST(9000000000000,IF(property_type='building',estimated_value_cents,0)
            +COALESCE((SELECT SUM(value_cents) FROM frontier_property_construction
              WHERE property_id=target AND state='complete'),0)
            +COALESCE((SELECT SUM(price_cents) FROM frontier_property_furniture
              WHERE property_id=target AND state='placed' AND lease_id IS NULL),0))
            INTO valuation FROM frontier_properties WHERE id=target;
        SET deduction=valuation*reduction_bps DIV 10000;
        SET debt_payment=LEAST(debt,valuation-deduction);
        SET surplus=valuation-deduction-debt_payment;
        SET penalty=surplus*penalty_bps DIV 10000;
        INSERT INTO frontier_property_foreclosures
          (property_id,valuation_cents,deduction_cents,debt_paid_cents,debt_forgiven_cents,
           state_penalty_cents,owner_payout_cents,treasury_bank_id)
        VALUES (target,valuation,deduction,debt_payment,debt-debt_payment,penalty,surplus-penalty,treasury);
        SET liquidation=LAST_INSERT_ID();
        INSERT INTO frontier_property_foreclosure_payees (foreclosure_id,owner_id,share_bps)
            SELECT liquidation,party_id,share_bps FROM frontier_property_ownership WHERE property_id=target;
        UPDATE frontier_properties SET status='inactive' WHERE id=target;
        UPDATE frontier_property_furniture SET state='recovery'
            WHERE property_id=target AND state='placed' AND lease_id IS NOT NULL;
    END IF;
    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE frontier_foreclosure_finish_v1(IN liquidation BIGINT UNSIGNED)
BEGIN
    DECLARE target BIGINT UNSIGNED DEFAULT NULL;
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE land_version BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT MAX(property_id) INTO target FROM frontier_property_foreclosures WHERE id=liquidation;
    SELECT id INTO estate FROM frontier_properties WHERE id=target FOR UPDATE;
    IF estate IS NOT NULL AND EXISTS (SELECT 1 FROM frontier_property_foreclosures
        WHERE id=liquidation AND state='pending' AND treasury_paid=1)
      AND NOT EXISTS(SELECT 1 FROM frontier_property_foreclosure_payees WHERE foreclosure_id=liquidation AND paid=0) THEN
        SELECT revision INTO land_version FROM frontier_land_revision WHERE id=1 FOR UPDATE;
        UPDATE frontier_land_claims SET state='declined' WHERE property_id=target AND state='owned';
        IF ROW_COUNT()>0 THEN UPDATE frontier_land_revision SET revision=revision+1 WHERE id=1; END IF;
        UPDATE frontier_property_construction SET state='seized' WHERE property_id=target;
        UPDATE frontier_property_furniture SET state='void' WHERE property_id=target AND state='placed';
        DELETE FROM frontier_property_ownership WHERE property_id=target;
        DELETE FROM frontier_property_permissions WHERE property_id=target;
        DELETE FROM frontier_property_private_offers WHERE property_id=target;
        UPDATE frontier_property_finance SET debt_cents=0,debt_since=NULL WHERE property_id=target;
        UPDATE frontier_property_sales SET state='cancelled' WHERE property_id=target AND state='offered';
        UPDATE frontier_property_foreclosures SET state='done' WHERE id=liquidation;
    END IF;
    COMMIT;
END$$
DELIMITER ;
