INSERT INTO frontier_properties (property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES ('building','active','Existing',100,50,10,'existing');
CALL frontier_property_seed_v1('first','One','known_room',20,40,10,4500);
CALL frontier_property_seed_v1('first','One','known_room',20,40,10,4500);
CALL frontier_property_seed_v1('near','Near','another_room',102,51,10,4500);
CALL frontier_property_seed_v1('same_room','Same','known_room',200,100,10,4500);
SELECT CONCAT(COUNT(*),':',SUM(share_bps)) FROM frontier_property_ownership WHERE party_type='government';
SELECT COUNT(*) FROM frontier_properties;
