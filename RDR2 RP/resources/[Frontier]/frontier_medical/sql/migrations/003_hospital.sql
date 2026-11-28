-- Run after economy 007 and medical 001/002. Durable department supply and billing records.
CREATE TABLE IF NOT EXISTS frontier_medical_supply_orders (
 id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 doctor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 doctor_name VARCHAR(193) NOT NULL, hospital VARCHAR(24) NOT NULL,
 items_json TEXT NOT NULL, amount_minor INT UNSIGNED NOT NULL,
 funding_hour BIGINT UNSIGNED NOT NULL, created_at BIGINT UNSIGNED NOT NULL,
 status VARCHAR(16) NOT NULL DEFAULT 'pending', debit_receipt VARCHAR(32) NULL,
 KEY ix_med_supply_doctor(doctor,funding_hour),KEY ix_med_supply_state(status)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS frontier_medical_invoices (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 patient VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, patient_name VARCHAR(193) NOT NULL,
 doctor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, doctor_name VARCHAR(193) NOT NULL,
 hospital VARCHAR(24) NOT NULL, amount_minor BIGINT UNSIGNED NOT NULL DEFAULT 0,
 status VARCHAR(16) NOT NULL, created_at BIGINT UNSIGNED NOT NULL, due_at BIGINT UNSIGNED NOT NULL,
 paid_at BIGINT UNSIGNED NULL,payer_account BIGINT UNSIGNED NULL, payment_receipt VARCHAR(32) NULL,
 previous_status VARCHAR(16) NULL, resolved_by VARCHAR(64) NULL, resolved_at BIGINT UNSIGNED NULL,
 reported_by VARCHAR(64) NULL,reported_at BIGINT UNSIGNED NULL,
 KEY ix_med_invoice_patient(patient,status), KEY ix_med_invoice_doctor(doctor,status), KEY ix_med_invoice_status(status)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS frontier_medical_charges (
 request_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 patient VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, patient_name VARCHAR(193) NOT NULL,
 doctor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, doctor_name VARCHAR(193) NOT NULL,
 life INT UNSIGNED NOT NULL, hospital VARCHAR(24) NOT NULL, region VARCHAR(24) NOT NULL,
 treatment VARCHAR(48) NOT NULL, label VARCHAR(96) NOT NULL, price_minor INT UNSIGNED NOT NULL,
 created_at BIGINT UNSIGNED NOT NULL, eligible BOOLEAN NOT NULL DEFAULT FALSE,
 invoice_id BIGINT UNSIGNED NULL,
 KEY ix_med_charge_patient(patient,doctor,life,eligible,invoice_id),
 CONSTRAINT fk_med_charge_invoice FOREIGN KEY(invoice_id) REFERENCES frontier_medical_invoices(id)
) ENGINE=InnoDB;
-- Transaction: claim all unbilled successful treatment lines for one doctor/patient/life.
DROP PROCEDURE IF EXISTS frontier_medical_issue_invoice_v1;
DELIMITER $$
CREATE PROCEDURE frontier_medical_issue_invoice_v1(
 IN p_patient VARCHAR(64), IN p_doctor VARCHAR(64), IN p_life INT UNSIGNED,
 IN p_status VARCHAR(16), IN p_now BIGINT UNSIGNED, IN p_due BIGINT UNSIGNED
)
proc: BEGIN
 DECLARE v_id BIGINT UNSIGNED;
 DECLARE v_total BIGINT UNSIGNED DEFAULT 0;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_status NOT IN ('pending','waived') THEN SELECT 'invalid_status' AS code; LEAVE proc; END IF;
 START TRANSACTION;
 INSERT INTO frontier_medical_invoices(patient,patient_name,doctor,doctor_name,hospital,status,created_at,due_at)
 SELECT patient,patient_name,doctor,doctor_name,hospital,p_status,p_now,p_due
 FROM frontier_medical_charges WHERE patient=p_patient AND doctor=p_doctor AND life=p_life AND eligible=TRUE AND invoice_id IS NULL
 ORDER BY created_at,request_key LIMIT 1;
 IF ROW_COUNT()<>1 THEN ROLLBACK; SELECT 'no_charges' AS code; LEAVE proc; END IF;
 SET v_id=LAST_INSERT_ID();
 UPDATE frontier_medical_charges SET invoice_id=v_id
 WHERE patient=p_patient AND doctor=p_doctor AND life=p_life AND eligible=TRUE AND invoice_id IS NULL;
 SELECT COALESCE(SUM(price_minor),0) INTO v_total FROM frontier_medical_charges WHERE invoice_id=v_id;
 IF v_total=0 THEN ROLLBACK; SELECT 'no_charges' AS code; LEAVE proc; END IF;
 UPDATE frontier_medical_invoices SET amount_minor=v_total,
 resolved_by=IF(p_status='waived',p_doctor,NULL),resolved_at=IF(p_status='waived',p_now,NULL)
 WHERE id=v_id;
 COMMIT;
 SELECT 'ok' AS code,CAST(v_id AS CHAR) AS invoice_id,v_total AS amount_minor;
END$$
DELIMITER ;
