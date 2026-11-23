-- Keep historical treasury fields for reconciliation. New settlements never post to them.
ALTER TABLE frontier_property_foreclosures
    MODIFY COLUMN treasury_bank_id BIGINT UNSIGNED NULL,
    ADD COLUMN IF NOT EXISTS settlement_mode ENUM('legacy','sink') NOT NULL DEFAULT 'legacy';

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_foreclosure_open_v2(
    IN target BIGINT UNSIGNED, IN threshold BIGINT UNSIGNED, IN grace_seconds INT UNSIGNED,
    IN reduction_bps INT UNSIGNED, IN penalty_bps INT UNSIGNED)
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
    IF estate IS NOT NULL
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
           state_penalty_cents,owner_payout_cents,treasury_bank_id,settlement_mode)
        VALUES (target,valuation,deduction,debt_payment,debt-debt_payment,penalty,surplus-penalty,NULL,'sink');
        SET liquidation=LAST_INSERT_ID();
        INSERT INTO frontier_property_foreclosure_payees (foreclosure_id,owner_id,share_bps)
            SELECT liquidation,party_id,share_bps FROM frontier_property_ownership WHERE property_id=target;
        UPDATE frontier_properties SET status='inactive' WHERE id=target;
        UPDATE frontier_property_furniture SET state='recovery'
            WHERE property_id=target AND state='placed' AND lease_id IS NOT NULL;
    END IF;
    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE frontier_foreclosure_finish_v2(IN liquidation BIGINT UNSIGNED)
BEGIN
    DECLARE target BIGINT UNSIGNED DEFAULT NULL;
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE land_version BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT MAX(property_id) INTO target FROM frontier_property_foreclosures WHERE id=liquidation;
    SELECT id INTO estate FROM frontier_properties WHERE id=target FOR UPDATE;
    IF estate IS NOT NULL AND EXISTS (SELECT 1 FROM frontier_property_foreclosures
        WHERE id=liquidation AND state='pending')
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
