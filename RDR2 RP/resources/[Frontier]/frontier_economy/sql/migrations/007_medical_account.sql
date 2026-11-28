-- Reserved public-service wallet. No player-owned banking or business access.
INSERT IGNORE INTO frontier_economy_accounts(owner_type,owner_id,account_type,currency,balance_minor)
VALUES ('medical_service','frontier_medical','treasury','USD',0);
