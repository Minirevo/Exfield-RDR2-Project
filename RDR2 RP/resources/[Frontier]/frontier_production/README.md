# Frontier Produktion v1

`/produktion` öffnet Produktion, Rezepte, Lager und Mitarbeiter. Jede Frontier-Figur erhält automatisch einen privaten Produktionsbetrieb. Spielerbetrieb pausiert bei Abmeldung und läuft bei Rückkehr weiter. NPC-Aufträge laufen nach erfolgreicher Lohnbuchung über persistente Datenbankzeit, auch wenn die Figur abwesend ist und nach einem Neustart.

## Installation

- Abgeschlossene Aufträge bleiben sichtbar, solange sich noch Waren im Produktionslager befinden. Sobald das Lager vollständig abgeholt wurde, werden die zugehörigen abgeschlossenen Aufträge aus der Auftragsliste und Datenbank entfernt.

1. Vorhandene Core-, Economy- und Inventory-Migrationen müssen angewendet sein. `sql/migrations/001_production.sql` in der oxmysql-Datenbank mit einem SQL-Client ausführen, der DELIMITER unterstützt. Die Runtime braucht SELECT/INSERT/UPDATE auf den beiden Produktionstabellen und EXECUTE auf frontier_production_start_v1 und frontier_production_employee_v1.
2. Die Änderungen an Economy, Inventory und Trade zusammen mit dieser Ressource deployen. Bei eigenen Serverkonfigurationen die bestehenden Allowlist-Einträge erhalten und `frontier_production = true` unter TrustedResources von Economy und Inventory ergänzen.
3. Oxmysql, VORP Core, Frontier Lib, Core, Economy und Inventory starten, dann `ensure frontier_production`. Frontier Trade kann die konfigurierten Zutaten und Ergebnisse über seinen bestehenden Markt handeln. Für die Produktion selbst ist der Markt optional.
4. Standardrezepte heißen Brot backen, Fleisch braten, Holzbretter herstellen und Eisen schmelzen. Rohstoffe können im Testserver über die bestehenden administrativen Inventory-Werkzeuge bereitgestellt werden.

## Betrieb und Buchungen

- Wähle Rezept, Chargenzahl und Ausführung. Vor der ausdrücklichen Bestätigung zeigt die Oberfläche Zutaten, vorhandenen Bestand, Ergebnis, Zeit und Lohn. Der Server verwendet ausschließlich validierte Regeln aus config.lua. Der Auftrag speichert einen Schnappschuss von Menge, Zutaten, Ergebnis, Dauer und Lohn.
- Inventory reserviert exakt alle Zutaten gemeinsam. Beim Abschluss werden die Zutaten atomar in fertige Produkte umgewandelt. Ein volles Produktionslager hält den Auftrag zurück. Nach Platzfreigabe verarbeitet der Worker ihn erneut.
- Der maximale Lagerbestand ist standardmäßig 100 Einheiten, zusätzlich greifen Slots und Gewicht. Eine einzelne Abholung oder „Alles abholen“ wird atomar übertragen. Bei zu wenig Platz oder Gewicht im Spielerinventar bleibt der Bestand im Produktionslager.
- Das vorhandene Charakter-Bankkonto ist das vorläufige Betriebskonto. Der NPC-Lohn wird nur für einen gestarteten NPC-Auftrag berechnet, anteilig in Echtzeit und einmal vor Laufbeginn gebucht. Der Standard von 200 Cent pro 3600 Sekunden wird proportional auf ganze Cent aufgerundet. Die Abbuchung erscheint im Economy-Ledger. Der logische Mitarbeiter hat kein eigenes Spielerkonto, die Gebühr fließt aus dem Spiel. Job-ID und Lohnschlüssel bleiben bei Neustarts gleich.
- Vor dem Anlegen eines Auftrags prüft der Server den tatsächlichen Zutatenbestand des Spielers und nennt fehlende Mengen. Die anschließende atomare Reservierung bleibt als zweite Sicherheitsprüfung bestehen. Abgelehnte Reservierungsversuche werden nicht in der aktiven Auftragsliste angezeigt.
- Bei fehlendem Geld bleiben Zutaten reserviert. Über den Auftrag kann der Besitzer die Lohnprüfung erneut starten oder stornieren und Zutaten zurückgeben. Laufende Aufträge können ebenfalls abgebrochen werden; reservierte Zutaten werden in das Spielerinventar zurückgegeben. Bei vollem Spielerinventar wartet die Zutatenrückgabe. Entlassung ist möglich, wenn kein NPC-Auftrag offen ist.
- Spielerzeit wird in kurzen serverseitigen Checkpoints gespeichert. Bei einem abrupten Prozessausfall kann seit dem letzten erfolgreichen Checkpoint gespeicherte Laufzeit fehlen. NPC-Zeit beginnt nach bestätigter Lohnbuchung. Pro Datenbank einen FXServer-Worker einsetzen.
- Nach einer unterbrochenen Bestätigung dieselbe Anfrage im offenen Fenster wiederholen. Wenn die Oberfläche geschlossen wurde, erst den Auftrags- oder Lagerstand prüfen. Es gibt keine automatische Verknüpfung mit einem Property-System. Die persistente Eigentümergrenze liegt an der Figur und kann später durch eine Betriebszuordnung ersetzt werden.

## Tests

`tests/production.sql` ausschließlich in einem frisch migrierten Wegwerfschema ausführen. Prüft SQL-Schutz vor doppeltem Start, Eigentümerkonflikt, zu vielen NPC-Aufträgen und Entlassung während eines Auftrags. `lua54 tests/inventory.lua` aus dieser Ressource prüft die neuen Inventory-Exports mit simulierten Containern. `lua54 tests/worker.lua` prüft pausierte Spieleraufträge, Offline-NPC-Produktion und Lohn-Replay mit simulierten Schnittstellen. Die Browser-Suite läuft mit `node tests/ui.cjs` und Playwright.

Auf dem RedM-Testserver zwei Charaktere benutzen. Brotauftrag starten und Zutaten zählen. Einen Spielerauftrag abmelden, verbinden und die pausierte Zeit prüfen. Einen NPC-Auftrag mit und ohne Geld starten, Ledger und Zutaten prüfen, den Server während des bezahlten Auftrags neu starten. Lager füllen, Auftrag auf Lagerplatz warten lassen und einzelne Mengen sowie alles abholen. Doppelklick, ungültige Mengen und Zugriff aus der anderen Figur prüfen. Live-Tests sind erst nach Testdeployment belastbar.

## Änderungsumfang

Neue Ressource frontier_production mit Migration, Server, Client, NUI und Tests. Inventory erhält zwei isolierte Production-Exports für private Lager und atomare Übergänge sowie eine Standardfreigabe. Economy ergänzt die Freigabe für bestehende Konten und Abbuchungen. Trade ergänzt die Produktliste. Vorhandene Migrationen werden nicht erneut angewendet.
