"""Exercise the upgrade against an isolated schema on a disposable MySQL/MariaDB instance."""

import subprocess
import sys
from pathlib import Path
from uuid import uuid4


def main(client, *options):
    economy = Path(__file__).resolve().parents[1]
    schema = "frontier_test_" + uuid4().hex
    command = [client, *options, "--batch", "--skip-column-names", "--default-character-set=utf8mb4"]

    def sql(statement, *, use_schema=True, expect_error=None):
        args = [*command, schema] if use_schema else command
        result = subprocess.run(args, input=statement, text=True, encoding="utf-8", capture_output=True)
        if expect_error:
            assert result.returncode and expect_error in result.stderr, result.stderr
        elif result.returncode:
            raise RuntimeError(result.stderr)
        return result.stdout.strip()

    def read(relative):
        return (economy / relative).read_text(encoding="utf-8")

    sql(f"CREATE DATABASE {schema}", use_schema=False)
    try:
        sql(read("../frontier_core/sql/migrations/001_characters.sql"))
        sql(read("sql/migrations/001_create_economy_tables.sql"))
        sql(read("sql/migrations/002_create_economy_routine.sql"))
        upgrade = read("sql/migrations/003_frontier_character_owners.sql")
        rollback = read("sql/rollback/003_frontier_character_owners.sql")

        sql("""
            CREATE TABLE characters (charidentifier INT NOT NULL, identifier VARCHAR(128)) ENGINE=InnoDB;
            INSERT INTO characters VALUES (11, 'owner:A'), (12, 'owner:B'), (12, 'owner:C');
            CALL frontier_economy_provision_v1('11');
            CALL frontier_economy_provision_v1('12');
            SET @bank = (SELECT id FROM frontier_economy_accounts WHERE owner_id = '11' AND account_type = 'bank');
            SET @target = (SELECT id FROM frontier_economy_accounts WHERE owner_id = '12' AND account_type = 'bank');
            CALL frontier_economy_apply_v1('test', 'credit-1', 'credit', 0, @bank, 1200, 'Seed', '', '{}', 'USD');
            CALL frontier_economy_apply_v1('test', 'transfer-1', 'transfer', @bank, @target, 125, 'Transfer', '', '{}', 'USD');
        """)
        owners = "SELECT id, owner_id FROM frontier_economy_accounts ORDER BY id;"
        balance = "SELECT id, owner_type, account_type, currency, balance_minor FROM frontier_economy_accounts ORDER BY id;"
        ledger = "SELECT * FROM frontier_economy_ledger ORDER BY id;"
        operations = """
            SELECT id, actor, request_key, HEX(fingerprint), kind, reason,
                   reference_text, metadata_json, completed
            FROM frontier_economy_operations ORDER BY id;
        """
        original_owners = sql(owners)
        snapshots = {statement: sql(statement) for statement in (balance, ledger, operations)}
        assert len(snapshots[ledger].splitlines()) == 3
        assert len(snapshots[operations].splitlines()) == 2

        sql(upgrade, expect_error="Unresolved or ambiguous legacy Economy owner")
        assert sql(owners) == original_owners
        assert sql("SELECT COUNT(*) FROM frontier_economy_identity_cutover") == "0"
        sql("DELETE FROM characters WHERE identifier = 'owner:C'")
        sql(upgrade)
        migrated_owners = sql(owners)
        assert migrated_owners != original_owners
        assert sql("SELECT COUNT(*) FROM frontier_character_identities") == "2"
        assert sql("SELECT COUNT(*) FROM frontier_economy_owner_upgrade") == "4"
        assert sql("SELECT COUNT(*) FROM frontier_economy_identity_cutover") == "1"
        assert all(row.split("\t")[1].startswith("f_") for row in migrated_owners.splitlines())
        assert all(sql(statement) == expected for statement, expected in snapshots.items())

        sql(upgrade)
        assert sql(owners) == migrated_owners
        replay = sql("""
            SET @bank = (SELECT id FROM frontier_economy_owner_upgrade m
                         JOIN frontier_economy_accounts a ON a.id = m.account_id
                         WHERE m.old_owner_id = '11' AND a.account_type = 'bank');
            SET @target = (SELECT id FROM frontier_economy_owner_upgrade m
                           JOIN frontier_economy_accounts a ON a.id = m.account_id
                           WHERE m.old_owner_id = '12' AND a.account_type = 'bank');
            CALL frontier_economy_apply_v1('test', 'transfer-1', 'transfer', @bank, @target, 125, 'Transfer', '', '{}', 'USD');
        """)
        assert replay.split("\t")[0] == "ok" and replay.split("\t")[-1] == "1"
        sql(rollback)
        assert sql(owners) == original_owners
        assert all(sql(statement) == expected for statement, expected in snapshots.items())

        sql(upgrade)
        assert sql(owners) == migrated_owners
        sql("CALL frontier_economy_provision_v1('f_000000000000000000000000000000ff')")
        sql(rollback, expect_error="Rollback requires the original migrated account set")
        assert sql("SELECT COUNT(*) FROM frontier_economy_identity_cutover") == "1"
        print("Frontier Economy migration, replay and rollback checks passed")
    finally:
        sql(f"DROP DATABASE {schema}", use_schema=False)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: migration.py PATH_TO_MYSQL_CLIENT [client options]")
    main(*sys.argv[1:])
