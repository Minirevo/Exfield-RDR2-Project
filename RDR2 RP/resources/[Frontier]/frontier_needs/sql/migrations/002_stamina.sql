-- Apply after 001_needs.sql (MariaDB). Existing needs remain unchanged.
ALTER TABLE frontier_needs_state ADD COLUMN IF NOT EXISTS stamina SMALLINT UNSIGNED NOT NULL DEFAULT 1000;
