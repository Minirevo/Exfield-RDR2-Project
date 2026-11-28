-- OPTIONAL, run ONCE with VORP Stables disabled and the server stopped.
-- Only imports old VORP horses for characters already mapped by Frontier Core.
-- Existing legacy IDs are kept as strings, preserving existing harness assignments.
INSERT IGNORE INTO `frontier_horses` (`id`,`owner_type`,`owner_id`,`stable`,`status`,`model`,`name`,`record`,`updated`)
SELECT CAST(s.id AS CHAR),'character',c.id,'valentine','stored',LOWER(s.modelname),s.name,
 JSON_OBJECT('id',CAST(s.id AS CHAR),'breed','legacy','sex','unknown','age',345600,
 'genes',JSON_OBJECT('speed',55,'stamina',60,'health',65),'health',IF(COALESCE(s.injured,0)>0,30,100),
 'care',100,'training',LEAST(100,GREATEST(0,COALESCE(s.xp,0))),'gear',JSON_OBJECT('saddle','horse_saddle'),'legacy',TRUE),
 UNIX_TIMESTAMP()
FROM `stables` s JOIN `frontier_character_identities` c
 ON c.provider='vorp' AND c.provider_character_id=CAST(s.charidentifier AS CHAR)
WHERE s.type='horse' AND LOWER(s.modelname) LIKE 'a_c_horse_%';
-- Inspect unmatched legacy owners before removing old tables. Keep the old tables as backup.
SELECT s.id,s.charidentifier,s.name FROM `stables` s
 LEFT JOIN `frontier_horses` h ON h.id=CAST(s.id AS CHAR) WHERE s.type='horse' AND h.id IS NULL;
