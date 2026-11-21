# Frontier Economy 0.1

Frontier owns the accounts, balances and journal. Frontier Core supplies stable character IDs. VORP character selection continues to work through Core. Existing VORP balances and financial tables are untouched. Every character starts at zero USD.

## Installation

1. Use MySQL 8.0.16+ or MariaDB 10.6+ with InnoDB. With Economy stopped, apply `sql/migrations/001_create_economy_tables.sql` and then `002_create_economy_routine.sql` to the schema used by oxmysql. Use the mysql/mariadb client or a SQL tool that handles `DELIMITER`. Apply them under strict SQL mode with a durable routine definer that can read and write the Economy tables. Reapplying the migrations preserves data, but recreating the routines requires checking their EXECUTE grants again.
2. Grant the FXServer database principal SELECT on the three `frontier_economy_*` tables and EXECUTE on both procedures. The procedures run as their definer, so runtime Economy access requires no direct table writes. A principal shared with other resources may already have broader schema privileges. Use a database principal with narrowly scoped grants where deployment permits. Treat the ledger and committed operation records as append-only.
3. Start `oxmysql`, `vorp_core`, `frontier_lib` and `frontier_core` before `frontier_economy`. If categories already start these dependencies, add only the final ensure after Core.

```cfg
ensure oxmysql
ensure vorp_core
ensure frontier_lib
ensure frontier_core
ensure frontier_economy
add_ace group.admin frontier.economy.admin allow
```

4. Add named server resources to `EconomyConfig.TrustedResources` only when they need access, for example `['frontier_jobs'] = true`. The allowlist is empty by default. A trusted resource owns authorization for any client request it forwards. Commands reply in German through the standard RedM chat event. The admin command also works from the server console.

Startup queues existing Core players and future character loads queue provisioning. Transient provisioning errors retry for active characters. API reads can provision immediately. Accounts are looked up by the current Core character ID; source IDs are never persisted as owners. Account-based mutations already submitted to MySQL finish against their resolved accounts if a player disconnects or changes character in the meantime. If the Core identity provider changes, preserve its existing stable IDs or migrate the Economy ownership mapping first.

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

Errors include `forbidden`, `character_unavailable`, `character_changed`, `account_not_found`, `same_account`, `insufficient_funds`, `balance_limit`, `idempotency_conflict`, `database_error`, and validation codes `invalid_account`, `invalid_amount`, `invalid_options`, `invalid_key`, `invalid_reason`, `invalid_reference`, `invalid_metadata` and `invalid_limit`.

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
