"""Run the Lua contract through a disposable MariaDB schema and MySQL CLI."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from uuid import uuid4

from lupa.lua54 import LuaRuntime


def main(client, *options):
    root = Path(__file__).resolve().parents[1]
    schema = "frontier_inv_test_" + uuid4().hex
    command = [client, *options, "--batch", "--default-character-set=utf8mb4"]

    def sql(statement, with_schema=True):
        process = subprocess.run(command + ([schema] if with_schema else []),
                                 input=statement, encoding="utf-8", capture_output=True)
        if process.returncode:
            print(process.stderr, file=sys.stderr)
            raise RuntimeError(process.stderr)
        lines = process.stdout.splitlines()
        if len(lines) < 2:
            return []
        names = lines[0].split("\t")
        return [dict(zip(names, line.split("\t"))) for line in lines[1:]]

    def unescape(value):
        return re.sub(r"\\([\\nrt0])", lambda m: {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "\\": "\\"}[m[1]], value)

    def parse(row, name):
        value = row[name]
        if value == "NULL":
            return None
        if name in {"slot", "slot_limit", "weight_limit", "revision", "quantity", "bucket",
                    "x", "y", "z", "distance_limit", "replayed"}:
            return float(value) if "." in value else int(value)
        return unescape(value)

    def bind(statement, args):
        values = iter([args[i] for i in range(1, len(args) + 1)] if args is not None else [])

        def literal(_):
            value = next(values)
            if isinstance(value, (int, float)):
                return str(value)
            return "CONVERT(UNHEX('%s') USING utf8mb4)" % value.encode().hex()

        return re.sub(r"\?", literal, statement)

    lua = LuaRuntime(unpack_returned_tuples=True)

    def to_lua(value):
        if isinstance(value, dict):
            return lua.table_from({k: to_lua(v) for k, v in value.items()})
        if isinstance(value, list):
            return lua.table_from([to_lua(v) for v in value])
        return value

    def from_lua(value):
        if type(value).__name__ != "_LuaTable":
            return value
        keys = list(value)
        if keys and set(keys) == set(range(1, len(keys) + 1)):
            return [from_lua(value[i]) for i in range(1, len(keys) + 1)]
        return {k: from_lua(value[k]) for k in keys}

    def query(method, statement, args):
        statement = bind(statement, args)
        rows = sql(statement.rstrip() + ";")
        if method == "update":
            return 1
        parsed = [{key: parse(row, key) for key in row} for row in rows]
        if method == "scalar":
            return next(iter(parsed[0].values())) if parsed else None
        if method == "single":
            return to_lua(parsed[0]) if parsed else None
        if statement.startswith("CALL "):
            return to_lua([parsed])
        return to_lua(parsed)

    lua.globals().json = lua.table_from({
        "encode": lambda x: json.dumps(from_lua(x), ensure_ascii=False, separators=(",", ":")),
        "decode": lambda x: to_lua(json.loads(x)),
    })
    lua.globals().MySQL = lua.table_from({
        method: lua.table_from({"await": lambda statement, args, method=method: query(method, statement, args)})
        for method in ("scalar", "update", "single", "query")
    })
    lua.globals().MySQL.ready = lambda _: None
    sql(f"CREATE DATABASE {schema}", with_schema=False)
    try:
        sql((root / "sql/migrations/001_inventory.sql").read_text(encoding="utf-8"))
        os.chdir(root)
        lua.execute((root / "tests/service.lua").read_text(encoding="utf-8"))
        sql("""
            INSERT INTO frontier_inventory_containers (id, kind, slot_limit, weight_limit) VALUES
                ('p_race_a', 'player', 4, 7500), ('p_race_b', 'player', 4, 7500), ('g_race', 'ground', 1, 10000);
            INSERT INTO frontier_inventory_slots (container_id, slot, item_id, quantity, metadata)
                VALUES ('g_race', 1, 'apple', 1, '{}');
        """)

        def race(owner):
            changes = [
                {"id": "g_race", "revision": 0, "entries": []},
                {"id": owner, "revision": 0, "entries": [
                    {"slot": 1, "item": "apple", "quantity": 1, "metadata": "{}", "instance": ""},
                ]},
            ]
            payload = json.dumps(changes).encode().hex()
            rows = sql(f"CALL frontier_inventory_commit_v1('{owner}', 'race', 'pickup', "
                       f"CONVERT(UNHEX('{payload}') USING utf8mb4));")
            return rows[0]["code"]

        with ThreadPoolExecutor(max_workers=2) as workers:
            outcomes = list(workers.map(race, ("p_race_a", "p_race_b")))
        assert sorted(outcomes) == ["conflict", "ok"], outcomes
        assert sql("SELECT COUNT(*) AS count FROM frontier_inventory_slots WHERE container_id LIKE 'p_race_%'")[0]["count"] == "1"
        assert sql("SELECT COUNT(*) AS count FROM frontier_inventory_containers WHERE id = 'g_race'")[0]["count"] == "0"
        print("Concurrent MariaDB pickup: exactly one request committed")
    finally:
        sql(f"DROP DATABASE {schema}", with_schema=False)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: integration.py PATH_TO_MARIADB_CLIENT [client options]")
    main(*sys.argv[1:])
