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
        # A disposable post-cutover character starts with one account of each type.
        sql("""
            CALL frontier_economy_provision_v1('f_000000000000000000000000000000ee');
            CALL frontier_economy_provision_v1('f_000000000000000000000000000000ee');
        """)
        new_owner = "f_000000000000000000000000000000ee"
        rows = sql(f"SELECT id, account_type, balance_minor FROM frontier_economy_accounts "
                   f"WHERE owner_id = '{new_owner}' ORDER BY account_type").splitlines()
        assert len(rows) == 2
        (bank, bank_type, bank_balance), (cash, cash_type, cash_balance) = (row.split("\t") for row in rows)
        assert (bank_type, bank_balance, cash_type, cash_balance) == ("bank", "0", "cash", "0")
        recipient = sql("SELECT a.id FROM frontier_economy_accounts a JOIN frontier_economy_owner_upgrade m "
                        "ON m.account_id = a.id WHERE m.old_owner_id = '12' AND a.account_type = 'bank'")

        def post(key, kind, debit, credit, amount, error=None):
            return sql(f"CALL frontier_economy_apply_v1('bank:fixture', '{key}', '{kind}', "
                       f"{debit}, {credit}, {amount}, 'Fixture', '', '{{}}', 'USD')", expect_error=error)

        def pair():
            return sql(f"SELECT balance_minor FROM frontier_economy_accounts WHERE id IN ({bank}, {cash}) "
                       "ORDER BY account_type").splitlines()

        assert post("seed", "credit", 0, cash, 1000).startswith("ok")
        assert post("deposit", "transfer", cash, bank, 325).startswith("ok")
        assert pair() == ["325", "675"]
        assert post("deposit", "transfer", cash, bank, 325).split("\t")[-1] == "1"
        assert pair() == ["325", "675"]
        assert post("withdraw", "transfer", bank, cash, 125).startswith("ok")
        assert pair() == ["200", "800"]
        assert post("too-much-cash", "transfer", cash, bank, 801) == "insufficient_funds"
        assert post("too-much-bank", "transfer", bank, cash, 201) == "insufficient_funds"

        transfer = post("online-transfer", "transfer", bank, recipient, 200).split("\t")
        assert transfer[0] == "ok"
        entries = sql(f"SELECT account_id, related_account_id, entry_type, amount_minor "
                      f"FROM frontier_economy_ledger WHERE operation_id = {int(transfer[1])} "
                      "ORDER BY entry_type").splitlines()
        assert {tuple(row.split("\t")) for row in entries} == {
            (bank, recipient, "debit", "200"), (recipient, bank, "credit", "200"),
        }

        assert post("restore-bank", "transfer", cash, bank, 300).startswith("ok")
        before_failed = {statement: sql(statement) for statement in (balance, ledger, operations)}
        sql("""
            DELIMITER //
            CREATE TRIGGER frontier_test_ledger_failure BEFORE INSERT ON frontier_economy_ledger
            FOR EACH ROW BEGIN
                IF NEW.entry_type = 'credit' THEN
                    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fixture ledger write failed';
                END IF;
            END//
            DELIMITER ;
        """.replace("            DELIMITER", "DELIMITER"))
        post("rollback-transfer", "transfer", bank, recipient, 100, error="Fixture ledger write failed")
        assert all(sql(statement) == value for statement, value in before_failed.items())
        sql("DROP TRIGGER frontier_test_ledger_failure")
        print("Frontier Economy provisioning, movements, paired ledger and forced rollback checks passed")
        print("Frontier Economy migration, replay and rollback checks passed")
    finally:
        sql(f"DROP DATABASE {schema}", use_schema=False)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: migration.py PATH_TO_MYSQL_CLIENT [client options]")
    main(*sys.argv[1:])
