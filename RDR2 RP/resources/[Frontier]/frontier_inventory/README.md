# Frontier Inventory v1

Frontier Inventory verwaltet Charakterinventare, Stapel, Metadaten, Lager und Bodenfunde. Der Besitzschlüssel ist die dauerhafte Frontier-Charakter-ID. VORP-Gegenstände und bestehende VORP-Abläufe bleiben in ihrem eigenen Inventar. Es gibt keine automatische Übernahme und keine Verbindung zu Frontier Economy.

## Installation

1. Das Verzeichnis `frontier_inventory` unter `RDR2 RP/resources/[Frontier]/` bereitstellen.
2. In der von oxmysql verwendeten Datenbank die Datei `sql/migrations/001_inventory.sql` vollständig ausführen. Verwende einen SQL-Client, der `DELIMITER` verarbeitet. Die Migration braucht CREATE und Indexrechte sowie CREATE ROUTINE und gegebenenfalls ALTER ROUTINE. Die Runtime benötigt SELECT und INSERT/UPDATE für Gegenstände und Container, SELECT/INSERT/UPDATE/DELETE für Slots, SELECT/INSERT/UPDATE für Belege, DELETE für abgelaufene Bodencontainer und EXECUTE auf `frontier_inventory_commit_v1`. Getestet mit MariaDB 10.11.14. Für MySQL 8.0.21+ oder andere MariaDB-Versionen die Migration zuerst auf einer Wegwerfdatenbank testen. Die bestehenden Core-Migrationen müssen bereits vorhanden sein.
3. OneSync muss aktiviert sein. Ergänze `ensure frontier_inventory` nach Core. Die übrigen Dienste können aus ihrer bestehenden Konfiguration gestartet werden.

```cfg
ensure oxmysql
ensure vorp_core
ensure frontier_lib
ensure frontier_core
ensure frontier_inventory
add_ace group.admin frontier.inventory.admin allow
```

Der letzte Eintrag ist für das Testlager und den optionalen Testbefehl. Die bestehende Konfiguration für Frontier Economy ist unabhängig.

## Bedienung

- `/inventar` oder standardmäßig **F6** öffnet die Tasche nach der Charakterauswahl. **Esc** oder **Schließen** gibt den Spieleingabefokus frei.
- Einen belegten Platz anklicken. Bei Verschieben, Teilen und Lageraktionen Menge und Zielplatz eingeben. Ein Klick auf einen leeren Platz übernimmt dessen Nummer. Verschieben auf einen passenden belegten Platz stapelt. **Tasche sortieren** räumt nach Gegenstands-ID auf.
- **Geben** zeigt in Reichweite befindliche Frontier-Charaktere. Für den Abschluss prüft der Server Entfernung, Routing-Bucket, Kapazität und beide Sitzungen erneut.
- **Ablegen** erzeugt einen Bodenfund an der Serverposition. Der helle Marker zeigt einen Fund abseits der NUI. Mit **F7** den nächsten Fund aufheben oder im Inventar auf seinen Namen klicken. Das Aufheben übernimmt den gesamten Bodenstapel. Gegenstände am Boden sind für andere Personen im selben Routing-Bucket erreichbar und laufen standardmäßig nach 24 Stunden ab. Ein erfolgreich aufgehobener Fund wird atomar gelöscht. Abgelaufene Funde und leere Platzhalter werden bereinigt.
- Das Testlager liegt in Valentine bei den in `InventoryConfig.TestStorage` angegebenen Koordinaten, Bucket 0. In Reichweite mit `/inventarlager` öffnen. Das Lager benötigt standardmäßig die Admin-ACE. `InventoryConfig.TestStorage = false` deaktiviert es.
- Wenn der Client das Cfx-Key-Mapping bereitstellt, kann die Belegung in dessen Tastatureinstellungen geändert werden. RedM-Builds mit Raw-Keymap verwenden `/inventartaste F5` bis `F11` und speichern die Auswahl lokal. Die Aufhebetaste ist davon ausgenommen. Die genaue Einbindung ins Einstellungsmenü hängt vom RedM-Build ab. `/inventar` und Aufheben über die NUI bleiben verfügbar.
- Für Wegwerftests `InventoryConfig.Development = true` setzen. Ein berechtigter Admin kann danach beispielsweise `/frontier_inv_test bread 5` benutzen. Im regulären Betrieb ist der Befehl deaktiviert.

`config.lua` enthält Slots, Gewichtsgrenzen (Gramm), Distanzen, Ablaufzeit, Anfrageintervalle, Protokollierung sowie die Optionen für Tod, Handlungsunfähigkeit und Testbetrieb. Slot- und Gewichtsgrenzen werden beim Anlegen gespeichert. Änderungen an diesen Standardwerten betreffen neu angelegte Inventare und Lager. Ändere vorhandene Kapazitäten nur nach Prüfung ihrer Belegung und ihres Gewichts.

## Server-API

Beim Aufruf gibt jeder Export `true, Wert` oder `false, Fehlercode` zurück. Trage den exakten Namen der Serverressource in `InventoryConfig.TrustedResources` ein. Character-Exporte erwarten eine aktuelle RedM-Spieler-ID und lösen den Frontier-Besitzer intern auf. Rufe Datenbank-Exporte aus einem Kontext auf, der auf das Ergebnis warten darf.

| Export | Argumente und Ergebnis |
| --- | --- |
| `GetInventory` | `source`, liefert Plätze, Gewicht, Kapazität und Revision |
| `GetItemCount` | `source, item`, liefert die Gesamtmenge |
| `HasItem` | `source, item, quantity`, liefert einen booleschen Wert |
| `AddItem`, `RemoveItem` | `source, item, quantity[, metadataJson[, requestId]]` |
| `MoveItem`, `SplitItem` | `source, {slot, target, quantity, revision?}[, requestId]` |
| `UseItem` | `source, {slot, revision?}[, requestId]` |
| `DropItem` | `source, {slot, quantity, revision?}[, requestId]` |
| `GiveItem` | `source, {slot, recipient, quantity, revision?}[, requestId]` |
| `GetNearbyPlayers` | `source`, liefert Liste der Spieler-IDs und Namen |
| `RegisterItem` | `id, definition`, registriert eine dauerhafte Definition |
| `RegisterUsableItem` | `item, callback, 'consume' oder 'keep'` |
| `CreateStorage` | `{id, name, slots?, grams?, ace?, x?, y?, z?, bucket?, distance?}` |
| `OpenStorage` | `source, storageId`, öffnet das Lager nach ACE- und Distanzprüfung |
| `GetStorageContents` | `storageId`, liefert einen Inventar-Snapshot für vertrauenswürdige Ressourcen |
| `AddItemToStorage`, `RemoveItemFromStorage` | `storageId, item, quantity[, metadataJson[, requestId]]` |
| `SetRestricted` | `source, blocked`, sperrt die Sitzung serverseitig und schließt die Oberfläche |

Eine Lagerdefinition ohne Position kann nur über den autorisierten Serveraufruf geöffnet werden. Die optionale leere ACE-Zeichenkette erlaubt Zugriff auf ein Lager ohne zusätzliche ACE-Prüfung, weiterhin mit Sitzungs- und gegebenenfalls Distanzprüfung. Direkte Lager-Exporte sind für vertrauenswürdige Backend-Ressourcen vorgesehen, etwa Häuser oder Camps. Lager-IDs und Gegenstandsdefinitionen können mit denselben Eigenschaften erneut registriert werden. Änderungen an bereits gespeicherten Definitionen müssen geplant migriert werden.

```lua
local inv = exports.frontier_inventory
local ok, issue = inv:RegisterItem('camp_ration', {
    name = 'Lagerration', description = 'Eine Portion für unterwegs.',
    category = 'Nahrung', grams = 200, maxStack = 5,
    drop = true, transfer = true, store = true, usable = true,
    metadata = '{"charge":"standard"}',
})
if not ok then return false, issue end

inv:RegisterUsableItem('camp_ration', function(source, item)
    return item.metadata.charge == 'standard'
end, 'consume')

-- Verwende dieselbe serverseitig gespeicherte ID bei Wiederholungen.
return inv:AddItem(playerSource, 'camp_ration', 2, nil, 'camp-delivery-42')
```

```lua
local ok, id = exports.frontier_inventory:CreateStorage({
    id = 'camp_locker', name = 'Lagerkiste', slots = 25, grams = 30000,
    x = -281.0, y = 806.0, z = 119.4, distance = 3.0,
    ace = 'frontier.camp.storage',
})
if ok then return exports.frontier_inventory:OpenStorage(playerSource, id) end
```

Gegenstände haben ganzzahlige Gramm, einen positiven maximalen Stapel (1 für Einzelstücke) und optionale Felder `icon`, `classification`, `condition` und `metadata`. Bei `condition = true` kann Metadatum `condition` eine ganze Zahl von 0 bis 100 enthalten. Metadaten sind JSON-Objekte bis 8192 Byte. Beim Stapeln müssen Gegenstand und gespeicherte JSON-Zeichenkette übereinstimmen. Einzelstücke behalten ihre eindeutige Instanz-ID beim Verschieben, Ablegen und Aufheben. Gewichts- und Stapelgrenzen gelten auch für Exporte.

Ein Usable-Callback muss synchron ein boolesches Ergebnis liefern und darf keine irreversiblen Effekte auslösen. Bei `consume` wird ein Stück nach Zustimmung mit der Inventartransaktion entfernt. Andere Ressourcen können für Folgewirkungen das lokale Server-Event `frontier:inventoryItemUsed(source, characterId, itemId, requestId)` nach erfolgreicher Buchung abonnieren. Die Nachricht ist kein dauerhaftes Ereignisprotokoll. Die Beispiel-Callbacks für Verband und Tonikum erlauben das Verbrauchen ohne Gameplay-Effekt.

## Zuverlässigkeit und Tests

Die Datenbank sperrt betroffene Container in fester Reihenfolge und prüft ihre Revisionen. Beide Seiten einer Bewegung sowie der Wiederholungsbeleg werden in derselben Transaktion geschrieben. Fehlschläge veröffentlichen keine Teiländerung. Ein bestätigter Auftrag kann mit derselben ID und denselben Argumenten wiederholt werden. Verwende für Export-Aufträge eine global eindeutige ID aus 1 bis 64 Kleinbuchstaben, Ziffern, Unterstrichen, Doppelpunkten oder Bindestrichen. Ohne ID wird pro Aufruf eine neue erstellt. Erfolgreiche Belege bleiben gespeichert. Auf dem Client bleiben Sitzungskennungen und Wiederholungen an ein offenes Inventar gebunden. Ein bereits an die Datenbank gesendeter Auftrag kann nach dem Schließen oder Wechsel noch abschließen.

- MariaDB-Integration: `python tests/integration.py PFAD_ZUM_MARIADB_CLIENT [Clientoptionen]` mit Python und Lupa (Lua 5.4), auf einer isolierten Instanz mit CREATE/DROP DATABASE. Das Skript verwendet eine eigene Wegwerfdatenbank.
- Client-Logik: `lua54 tests/client.lua` aus dem Ressourcenverzeichnis.
- NUI: `node tests/ui.cjs` mit Playwright und Chromium. Bei einer gebündelten Laufzeit können `PLAYWRIGHT_MODULE` und `BROWSER_EXECUTABLE` gesetzt werden.

Auf einem RedM-Testserver mit zwei Clients prüfen: Charakter auswählen und Inventar öffnen, mit Esc und Schaltfläche schließen, bei offenem Inventar die Ressource neu starten und den Mauszeiger prüfen. Danach Testgegenstände hinzufügen, stapeln, teilen, benutzen, geben und ablegen. Beide Spieler sollen gleichzeitig denselben Fund aufheben. Entferne dich vom Lager, wechsle den Routing-Bucket und prüfe die Sperren. Nach reconnect, Charakterwechsel und Serverneustart Bestände und einen noch nicht abgelaufenen Fund kontrollieren.

Falls das Inventar nicht öffnet, zuerst geladenen Frontier-Charakter, OneSync, Reihenfolge und SQL-Migration prüfen. Bei einem nicht sichtbaren Hotkey-Menü die lokale Tastenwahl verwenden. Bei einem grauen Bildschirm die NUI im Testserver mit laufender Bank und sonstigen Overlays prüfen. Die Seite ist beim Start ausgeblendet und setzt keinen Vollbildhintergrund.

## Exclusive inventory deployment
See RDR2 RP/FRONTIER-INVENTORY-CUTOVER.md. Frontier consumables remain linked to the VORP needs engine until phase 2; old VORP item registration is disabled.
