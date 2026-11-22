# Frontier Trade: Verträge und Lieferungen

Diese Erweiterung setzt die bestehenden öffentlich finanzierten Kaufgesuche voraus. Sie ergänzt Verträge, Teillieferungen Preisobergrenzen und ein deutsches Marktfenster. Ein Kaufgesuch kann gleichzeitig einen Lieferanten binden. Ein angenommener Vertrag benötigt keinen Warenbestand. Der Lieferant trägt seine Ware später aus dem Frontier-Inventar bei.

## Einrichten (Wegwerf- oder Testserver zuerst)

1. Economy und Inventory mit den Änderungen dieses Branches bereitstellen. Die Economy-Migration 004 und Trade-Migration 001 müssen bereits angewendet sein. Falls nicht, zuerst nach der bestehenden README einrichten.
2. Bei gestopptem Trade `sql/migrations/002_deliveries.sql` gegen das oxmysql-Schema ausführen. Der SQL-Client muss DELIMITER unterstützen. Die Runtime benötigt SELECT/INSERT/UPDATE auf den Trade-Tabellen sowie EXECUTE auf `frontier_trade_contract_v1`. Die Migration enthält keine JSON_TABLE- oder SKIP LOCKED-Ausdrücke.
3. Die Ressource `frontier_trade` in Economy und Inventory freigeben und erst nach beiden starten. Nur ein FXServer pro Schema. Die optionale Diagnose erfordert `add_ace group.admin frontier.trade.admin allow`.

## Bedienung

- `/handel` öffnet das Marktfenster mit Markt-/Produktfilter, Erstellung, Annahme, Vertragsübersicht, Lieferung, Abholung und Storno. Mit Esc schließen. Aktualisieren liest den neuen Stand nach der Rückmeldung im Chat.
- `/handelannehmen <Gesuch-ID>`, `/handelsvertraege`, `/handelliefern <Vertrags-ID> <Menge>`, `/handelslieferungen` und `/handelsabholung <Liefer-ID>` funktionieren auch per Chat.
- `/handelsvertragsstorno <Vertrags-ID>` gibt das verbleibende Kontingent wieder frei, sofern keine Lieferung läuft. Nach Fristablauf geschieht das automatisch. Der Käufer kann ein ungebundenes Gesuch stornieren oder auslaufen lassen und erhält das verbliebene Budget zurück.

## Wiederanlauf

Die SQL-Prozedur bindet und aktualisiert Mengen gemeinsam mit dem Trade-Zustand. Inventory verschiebt die Ware mit einem stabilen Schlüssel in einen privaten Container. Economy zahlt danach aus dem bestehenden Gesuchstreuhandkonto, ebenfalls mit einem stabilen Schlüssel. Nur nach bestätigter Auszahlung darf der Käufer abholen. Eine fehlgeschlagene Abholung bei vollem Inventar kann mit derselben Liefer-ID wiederholt werden. Die Ware bleibt in Treuhand. Beim Neustart setzt der Worker persistente Lieferungen in stock/payment fort. Der Arbeiter storniert niemals eine laufende Zahlung aufgrund eines Timeouts.

`/handelspruefung` zeigt wartende Lieferungen für die Serverkonsole und berechtigte Admins. Bei längerem Zahlungsstillstand die jeweiligen Economy- und Inventory-Belege vergleichen. Waren in wartenden Lieferungen weder manuell zurückbuchen noch Auszahlungen unter einer neuen ID wiederholen.

In einer leeren Testdatenbank Trade 001 und 002, dann `tests/contracts.sql` ausführen. Der Lua-Test `lua54 tests/delivery_worker.lua` simuliert einen verlorenen Zahlungsbeleg. Auf einem RedM-Testserver zwei Charaktere verbinden, Kaufgesuch finanzieren, vor Warenbesitz annehmen, Teilmengen liefern und beide Seiten inklusive Abholung prüfen. Danach Fokus, Neustart, Auszahlung und Deadline testen.

Die optionale Preisobergrenze eines neuen Gesuchs wird vollständig vorfinanziert. Der Worker erhöht den angebotenen Preis auf freie Gesuche nach Konfiguration (standardmäßig alle sechs Stunden um 20 %, mindestens einen Cent) bis zur Obergrenze. Annahme aus der Oberfläche prüft den angezeigten Preis. Der Vertrag speichert seinen Preis; die Abrechnung addiert tatsächliche Ausgaben. Überschüsse werden nach Abschluss oder Storno ausgezahlt. Alte Festpreisgesuche bleiben Festpreisgesuche.

NPC-Teilnehmer und -Simulation, Spielerbetriebe und die erweiterte Marktstatistik sind weiterhin offen.

## Verkaufsangebote

Nach Trade 002 auch `sql/migrations/003_sales.sql` anwenden. Runtime benötigt Zugriff auf die neuen Offer-/Sale-Tabellen und EXECUTE auf frontier_trade_sale_v1. Das Marktfenster kann Ware reservieren und Teilmengen kaufen. Per Chat funktionieren /handelsangebot, /handelskaufen, /handelsangebotstorno und /handelskaufabholung. Bei Storno gehen nicht verkaufte Stücke zurück in das Frontier-Inventar des Verkäufers. Reicht der Platz für die Rückgabe nicht, bleibt die Ware reserviert und die Rückgabe wird wiederholt.

Verkaufsangebote werden erst nach atomarer Warenreservierung veröffentlicht. Pro Angebot kann ein Kauf gleichzeitig bearbeitet werden. Der Worker reserviert die Kaufmenge separat, zahlt mit einem einmaligen Economy-Schlüssel und gibt die Abholung erst nach bestätigter Zahlung frei. Eindeutige Zahlungsablehnungen führen zur Warenrückgabe. Bei unbekanntem Ergebnis wird dieselbe Zahlung wiederholt.
