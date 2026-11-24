-- Runs only in disposable CI database.
DELIMITER $$
CREATE PROCEDURE fp_test_schema()
BEGIN
 DECLARE stale BOOLEAN DEFAULT FALSE;
 START TRANSACTION;
 CALL fp_assert_revision(0);
 INSERT INTO fp_settlements VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','Test',0,0,0,100,'f_test','active',FALSE);
 INSERT INTO fp_buildings VALUES ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','cabin',20,0,0,0,9,TRUE,TRUE,1000);
 INSERT INTO fp_interiors VALUES ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','watson',1500000001,45);
 INSERT INTO fp_furniture VALUES ('cccccccccccccccccccccccccccccccc','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','property_chair',1,2,3,0);
 COMMIT;
 BEGIN
  DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET stale=TRUE;
  CALL fp_assert_revision(0);
 END;
 IF NOT stale THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Stale write accepted'; END IF;
 DELETE FROM fp_settlements WHERE id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
 IF EXISTS(SELECT 1 FROM fp_furniture) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Furniture cascade failed'; END IF;
END$$
DELIMITER ;
CALL fp_test_schema();
DROP PROCEDURE fp_test_schema;
