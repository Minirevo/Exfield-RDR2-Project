# Frontier Trade

Aktuelle Installation, Verträge, Teillieferungen und Marktfenster stehen in [DELIVERIES.md](DELIVERIES.md).

This branch implements the first executable slice of the Trade blueprint. Characters create fixed-price public purchase requests in Valentine. Economy moves the budget from the character bank account into a dedicated hold before Trade publishes a request. Cancellation and expiry return the held funds through the existing ledger routine. Each funding and release has a stable idempotency key. Inventory validates the configured product IDs.

## Install on a test server

1. Verify the current Frontier Core, Economy and Inventory installations and take a backup.
2. Apply `frontier_economy/sql/migrations/004_trade_holds.sql` with a SQL client that supports DELIMITER, followed by `frontier_trade/sql/migrations/001_requests.sql`. Grant the runtime EXECUTE on the new Economy procedure plus SELECT, INSERT and UPDATE on the new Trade table. No earlier migrations need to be repeated. The new files do not require JSON_TABLE or SKIP LOCKED.
3. Deploy the included Economy/Inventory changes. Set `['frontier_trade'] = true` in each resource's server-side `TrustedResources` table. Existing assignments remain in place. The hold exports additionally require the exact invoking resource `frontier_trade`.
4. Start `frontier_trade` after Economy and Inventory. Use one Trade worker (one FXServer instance per schema). Restart the dependent resources during rollout.

Try `/handelsgesuch valentine bread 10 25` as a loaded character with at least 250 bank cents. The command returns a request UUID. Use `/handelsstatus UUID` for your request, `/handelsmarkt valentine` to view up to 20 funded listings and `/handelsstorno UUID` to cancel your open request. Only confirmed funding makes an offer public. Cancellation is available once published. The worker retries indeterminate SQL/API responses; if a confirmation is lost, check the original UUID before submitting another request. Jobs that remain in retry should be reconciled using Economy's ledger and the Trade request state.

## Scope and verification

Player purchase requests now support contract acceptance, partial delivery, settlement, and a German market window. Selling offers reserve inventory before listing and support partial purchases. NPC market activity is configurable. Businesses can integrate through the property adapter once a provider exists. Private agreements remain open. A refund can wait in retry if the original bank account cannot accept the returned amount. Leave Trade running until all funded listings, contracts and pending deliveries have been resolved before disabling it.

Run `lua54 tests/requests.lua` from this directory. On a disposable RedM/MariaDB 10.4.32 setup, test insufficient funds, funded visibility, owner-only cancellation, expiry, and restart after an Economy commit but before the Trade state update. Compare both account ledger entries. Attempt privileged generic account movements to a hold and verify they are rejected.
