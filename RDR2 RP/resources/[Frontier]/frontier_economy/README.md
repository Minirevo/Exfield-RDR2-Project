# Frontier Economy v1

Frontier owns the accounts, balances and journal. Frontier Core supplies stable character IDs. VORP character selection continues to work through Core. Existing VORP balances and financial tables are untouched. Every character starts at zero USD.

## Player banking

Use `/frontier_bank` in game after selecting a character. The terminal displays current cash and bank balances in USD and provides deposits, withdrawals, transfers to loaded online characters and the latest 25 entries per account. Use the player’s current server ID for a transfer. Closing via the button or Esc restores game controls. The existing `/frontier_kontostand` and ACE-gated `/frontier_gutschrift` commands remain available.

On an already migrated server, deploy this resource and restart `frontier_economy`. This release requires no new schema changes, no rerun of the identity cutover and no new permissions or trusted resources. Keep your existing server configuration and trusted resource allowlist. The command name is set in `shared/banking.lua`. The installation and migration sections below are for new deployments or upgrades from older, unmigrated versions.

The server binds each banking view to an active Frontier character and issues a unique request namespace. It parses decimal strings into integer cents, resolves online recipients itself, and checks both sessions before submitting the existing transaction procedure. The bank only accepts player self-service operations. Other resources still require the trusted resource allowlist for Economy exports. History omits internal account and operation identifiers, metadata and administrative or integration reasons. Player-entered transfer reasons are visible to both participants.

If a result is uncertain, use **Denselben Auftrag wiederholen** to replay the same request in the open banking view. A successful replay does not book the money twice. If the recipient changes sessions or the view has already been closed, check the history before submitting a new instruction. A view cannot recover its original request after closing or restarting the resource. An already submitted database transaction can complete after a character switches or the view closes.

### Test the banking UI

- Run `lua54 tests/service.lua` and `lua54 tests/banking.lua` from this resource directory. The server and client fixtures cover validation, account ownership, retry, session changes, history privacy, permissions and NUI focus handling.
- Run `node tests/ui.cjs` with Playwright and Chromium available. Set `PLAYWRIGHT_MODULE` or `BROWSER_EXECUTABLE` if using a bundled installation. This runs the page against mocked NUI responses and tests keyboard/button close, form validation, German feedback, retry, history selection and balance refresh.
- Run `python tests/migration.py PATH_TO_MARIADB_CLIENT` against a **disposable database instance**. It uses its own throwaway schema and tests provisioning, deposits, withdrawals, paired transfers, replay, a forced ledger-write failure and migration preservation. This does not apply migrations to your live schema.
- On a disposable RedM server, log in with two characters. Open the bank and confirm mouse and keyboard focus. Close with Esc, reopen and close with the button. Restart Economy while the bank is open and confirm the cursor is released. Test cash and bank movements, a transfer to the other online character, offline and self-transfer rejection, both history views and a character switch. Check in both clients that a successful transfer appears with opposite directions and matching amounts.

## Installation

1. Use MySQL 8.0.16+ or MariaDB 10.6+ with InnoDB. With Economy stopped, apply `sql/migrations/001_create_economy_tables.sql` and then `002_create_economy_routine.sql` to the schema used by oxmysql. Use the mysql/mariadb client or a SQL tool that handles `DELIMITER`. Apply them under strict SQL mode with a durable routine definer that can read and write the Economy tables. Reapplying the migrations preserves data, but recreating the routines requires checking their EXECUTE grants again.
2. Apply the Core identity migration and Economy owner cutover described below. The cutover marker is required for character account reads and provisioning.
3. Grant the FXServer database principal SELECT on the account, ledger, operation and cutover-marker tables and EXECUTE on both procedures. The procedures run as their definer, so runtime Economy access requires no direct table writes. A principal shared with other resources may already have broader schema privileges. Use a database principal with narrowly scoped grants where deployment permits. Treat the ledger and committed operation records as append-only.
4. Start `oxmysql`, `vorp_core`, `frontier_lib` and `frontier_core` before `frontier_economy`. If categories already start these dependencies, add only the final ensure after Core.

```cfg
ensure oxmysql
ensure vorp_core
ensure frontier_lib
ensure frontier_core
ensure frontier_economy
add_ace group.admin frontier.economy.admin allow
```

5. Add named server resources to `EconomyConfig.TrustedResources` only when they need access, for example `['frontier_jobs'] = true`. The allowlist is empty by default. A trusted resource owns authorization for any client request it forwards. Commands reply in German through the standard RedM chat event. The admin command also works from the server console.

Startup queues existing Core players and future character loads queue provisioning. Transient provisioning errors retry for active characters. API reads can provision immediately. Accounts are looked up exclusively by the current Frontier-owned Core ID; source IDs are never persisted as owners. Account-based mutations already submitted to MySQL finish against their resolved accounts if a player disconnects or changes character in the meantime. If the Core identity provider changes, preserve its existing stable IDs or migrate the Economy ownership mapping first.

## Money and API

All amounts and balances are integers in USD cents. Pass a Lua number such as `1250` for $12.50. The largest amount and account balance is 9,000,000,000,000 cents. Convert exact decimal input to cents before calling the API. Fractional cents, numeric strings, zero, negative amounts, NaN and infinity are rejected. Do not round input silently.

Call `exports.frontier_economy:ExportName(...)` from an allowlisted server resource in a yieldable context. Each export returns `true, result` or `false, errorCode`.

| Export | Arguments | Success result |
| --- | --- | --- |
| `GetCharacterAccounts` | `source` | `{characterId, cash, bank}`, with account rows |
| `GetCharacterBalances` | `source` | `{cash, bank, currency}` |
| `GetAccountBalance` | `accountId` | Account row `{id, account_type, balance_minor, currency}` |
| `Deposit` | `source, amountMinor, options` | Operation receipt, cash to bank |
| `Withdraw` | `source, amountMinor, options` | Operation receipt, bank to cash |
| `TransferCharacters` | `senderSource, recipientSource, amountMinor, options` | Operation receipt, bank to bank |
| `CreditAccount` | `accountId, amountMinor, options` | Operation receipt |
| `DebitAccount` | `accountId, amountMinor, options` | Operation receipt |
| `TransferAccounts` | `debitAccountId, creditAccountId, amountMinor, options` | Operation receipt |
| `GetAccountTransactions` | `accountId[, limit]` | Newest first, empty list if no entries |
| `GetCharacterTransactions` | `source, 'cash' or 'bank'[, limit]` | Newest first for the selected current account |

History defaults to 25 entries, with an allowed limit of 1–100. Each row includes ledger ID, account ID, direction, currency, amount, balances before and after, related account ID when applicable, operation ID, UTC timestamp, operation kind, actor, request key, reason, reference text and metadata JSON. Ledger and operation IDs are decimal strings. Account IDs and money values are numbers. History is server-only and may contain private data such as the administrator identifier.

```lua
local economy = exports.frontier_economy
local ok, accounts = economy:GetCharacterAccounts(playerSource)
if not ok then
    return false, accounts
end

-- payrollRunId must come from the caller's durable business operation.
return economy:CreditAccount(accounts.bank.id, 1250, {
    key = 'payroll:' .. payrollRunId .. ':' .. accounts.characterId,
    reason = 'Payroll',
    reference = tostring(payrollRunId),
    metadataJson = '{"period":"1899-07"}',
})
```

A mutation requires `options.key` (1–96 ASCII letters, digits, dots, underscores, colons or hyphens) and `options.reason` (1–255 UTF-8 bytes, nonblank). Optional `reference` is at most 128 UTF-8 bytes. Optional `metadataJson` is valid JSON text up to 4096 UTF-8 bytes. For exact retries, persist the key, resolved account IDs, amount and all option values including the exact JSON bytes. Keys are scoped to the invoking resource. A previously committed identical request returns its original receipt `{operationId, replayed = true}`. Reusing its key with different inputs returns `idempotency_conflict`. Declined requests roll back without consuming the key. After a database error the commit outcome can be unknown, so retry the same operation and key. Prefer account-based mutations for durable retries because the character behind a source can change.

Errors include `forbidden`, `character_unavailable`, `character_changed`, `identity_migration_required`, `account_not_found`, `same_account`, `insufficient_funds`, `balance_limit`, `idempotency_conflict`, `database_error`, and validation codes `invalid_account`, `invalid_amount`, `invalid_options`, `invalid_key`, `invalid_reason`, `invalid_reference`, `invalid_metadata` and `invalid_limit`.

## Commands

- `/frontier_kontostand` displays your current character's cash and bank balances.
- `/frontier_gutschrift <Spieler-ID> <bar|bank> <Cent> <Vorgangskennung> <Grund>` requires `frontier.economy.admin` in game. For example `/frontier_gutschrift 12 bank 1250 test:credit:01 Startguthaben`. The same administrator can repeat the same command for the same character and key to obtain the original receipt. The command logs the outcome and records the administrator in successful operations.

## Database and verification

The unique account key is owner type, owner ID, account type and currency. The provisioning procedure creates both zero-balance character accounts idempotently. Future owner types can use the same account and journal schema. General account mutations work with existing account IDs.

A mutation claims its unique actor/key pair and locks the account rows in ascending ID order inside one InnoDB transaction. It checks funds and headroom before changing balances. A transfer generates two journal entries with the same operation ID and reciprocal related-account IDs. Exceptions roll back the entire operation. The ledger has no application update or delete path.

Run `lua54 tests/service.lua` (or the equivalent Lua 5.4 executable) from this resource directory for the service contract test with mocked RedM and oxmysql interfaces. Then use a disposable database and a clean RedM test server with two distinct loaded characters. For API tests, temporarily allowlist a server-only test resource and invoke the above exports from a server thread. Use fresh keys unless checking replay.

| Scenario | Expected result |
| --- | --- |
| Select a new character, reconnect and repeat with the same character | Exactly one cash and one bank row, starting at zero and retaining any later balances |
| Credit cash 1000, deposit 300, then withdraw 100 | Cash 800, bank 200, and both movements have two matching ledger entries |
| Attempt to debit more than the account holds | `insufficient_funds`, balances and ledger unchanged |
| Transfer 150 from one character's bank to another | Sender decreases by 150 and recipient increases by 150, with reciprocal ledger entries |
| Transfer to a missing account or an account already at the cap | `account_not_found` or `balance_limit`, with neither side changed. To exercise the exception handler after a debit on a disposable database, temporarily add a ledger INSERT trigger that raises an error for credit entries, perform a transfer and remove the test trigger. Both balances and the journal must remain unchanged |
| Replay one successful request concurrently with the same key | One mutation, one operation ID, and the other successful responses are replays. Change the amount with the same key to verify `idempotency_conflict` |
| Concurrently submit two debits of 80 against a balance of 100 with distinct keys | Exactly one successful debit, balance 20. Also run opposite-direction transfers to exercise lock ordering |
| Switch characters on the same player source | Balance/history resolve the newly selected character and the previous character's rows persist |
| Disconnect and reconnect, then restart Economy with players online | Same accounts and balances, and loaded players can read their accounts after restart |
| Make the database unavailable and restore it | Operations surface database errors, queued provisioning recovers, and retrying with the original key cannot double-post |
| Use the credit command without ACE and call a privileged export from an unlisted resource | Both requests fail and make no financial changes |

## Character identity cutover

1. Stop Economy and Core and prevent changes to VORP characters during the migration. Back up the database and record account IDs, owners, types, currencies and balances, along with ledger and operation snapshots, using consistent reads.
2. Apply Core's `sql/migrations/001_characters.sql`. On a fresh deployment apply Economy 001 and 002 if needed. Verify the legacy owner preflight returns zero rows before running Economy 003. The original account implementation used VORP IDs, so the migration requires one exact canonical VORP `characters.charidentifier` per legacy owner. Resolve orphaned, noncanonical or ambiguous IDs outside this migration with verified ownership evidence.
3. Apply `sql/migrations/003_frontier_character_owners.sql` using a deployment principal with CREATE/DROP ROUTINE, EXECUTE and DML on the Frontier tables, CREATE for the audit and marker tables, and SELECT on VORP `characters`. The procedure changes only `owner_id` on existing character accounts, records their old and new owners, and commits with the cutover marker. Existing ledger and operation references continue to address account IDs.
4. Run the postflight queries and compare the account, ledger and operation snapshots against the backup. Install both resources from the same release before resuming traffic.

Legacy owner preflight:

```sql
SELECT a.id, a.owner_id
FROM frontier_economy_accounts a
WHERE a.owner_type = 'character'
  AND (a.owner_id NOT REGEXP '^[1-9][0-9]*$'
       OR (SELECT COUNT(*) FROM characters c
           WHERE CAST(c.charidentifier AS CHAR CHARACTER SET ascii) COLLATE ascii_bin = a.owner_id) <> 1);
```

Postflight before resuming traffic:

```sql
SELECT * FROM frontier_economy_identity_cutover WHERE id = 1;

SELECT a.id, a.owner_id, a.account_type, a.currency, a.balance_minor, m.old_owner_id
FROM frontier_economy_accounts a
LEFT JOIN frontier_economy_owner_upgrade m ON m.account_id = a.id
WHERE a.owner_type = 'character'
ORDER BY a.id;

SELECT a.id, a.owner_id
FROM frontier_economy_accounts a
LEFT JOIN frontier_character_identities i ON i.id = a.owner_id
WHERE a.owner_type = 'character' AND i.id IS NULL;
```

Expect one marker and zero unresolved owners. Compare the account query with the original snapshot by ID. Ledger and operation snapshots should match exactly. Run `python tests/migration.py PATH_TO_MARIADB_CLIENT` on a disposable local database server for the upgrade and rollback fixture. The runner accepts normal local client options after the executable, such as `--protocol=PIPE --socket=FrontierTest --user=root`, and creates and removes a randomly named test schema.

To roll back before provisioning any new character accounts, stop both resources, back up again, run `sql/rollback/003_frontier_character_owners.sql`, verify that legacy owners, account IDs, balances and journal match, and deploy both prior resources. The rollback refuses accounts introduced or reassigned after cutover. In that case do not force it. Preserve post-cutover transactions and plan a reviewed reconciliation or backup recovery. The rollback keeps Frontier identities and character profiles for a future upgrade.
