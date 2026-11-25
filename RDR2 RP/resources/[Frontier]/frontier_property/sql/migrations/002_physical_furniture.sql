-- Apply before starting the updated resource. Existing legacy furniture stays recoverable.
CREATE TABLE IF NOT EXISTS fp_plot_furniture (
 id CHAR(32) PRIMARY KEY, settlement_id CHAR(32) NOT NULL, item_id VARCHAR(48) NOT NULL,
 x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,heading DOUBLE NOT NULL,
 INDEX(settlement_id),FOREIGN KEY(settlement_id) REFERENCES fp_settlements(id) ON DELETE CASCADE
) ENGINE=InnoDB;
