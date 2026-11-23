# Frontier Property

First executable property-ownership slice for Frontier.

## Install

1. Back up the server and database.
2. Apply `sql/migrations/001_property.sql` to the Frontier database.
3. Add real property locations to `config.lua`. Each site needs a unique lowercase ID, label, type, purchase price in cents, rent amount (reserved for the rental phase), and in-world coordinates.
4. Add `ensure frontier_property` after `frontier_core` and `frontier_economy`.
5. Restart the server. The resource seeds configured sites without overwriting their ownership.

## Commands

- `/immobilien` — list configured properties and availability.
- `/immobilie_kaufen <ID>` — purchase an available property using the character bank account.
- `/immobilie_rechte <ID> <Charakter-ID> <manager|employee>` — owner grants business access.

Purchases are idempotent. If the server stops after the debit but before ownership is finalized, the worker retries the same Economy request key and completes the ownership update without charging twice.

## Access API

- `GetTradePropertyAccess(characterId, propertyId, action)` — callable only by `frontier_trade`.
- `GetProductionPropertyAccess(characterId, propertyId, action)` — callable only by `frontier_production`.
- `GetPropertyAccess(characterId, propertyId, action)` — restricted to the Frontier business resources.

Owners and managers can view, trade and produce. Employees can trade and produce. Access is checked server-side on every call.

## Current scope

This slice implements persistent configured sites, purchase, ownership, member roles and provider APIs. Rental billing, sale/transfer, physical doors/interiors, map blips, and full Trade/Production ownership migration are deliberately separate follow-up work. Trade's existing `PropertyProvider` setting can be set to `frontier_property` when its site-aware flows are wired to the adapter. Production remains character-owned until its schema and job model are migrated safely.
