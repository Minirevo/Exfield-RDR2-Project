SELECT CONCAT(state,':',deposit_cents,':',landlord_bank_id IS NULL) FROM frontier_property_rentals WHERE id=1;
DELIMITER $$
CREATE PROCEDURE test_new_government_rent()
BEGIN
    DECLARE blocked BOOLEAN DEFAULT FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET blocked=TRUE;
        CALL frontier_property_rent_reserve_v2(2,@a,1,100,3600,1,25);
    END;
    SELECT CONCAT('blocked=',blocked);
END$$
DELIMITER ;
CALL test_new_government_rent();
SELECT COUNT(*) FROM frontier_property_rentals;
