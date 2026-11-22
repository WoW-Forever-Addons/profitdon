# Profitdon

## 0.2.12

- Fehler behoben: "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'Profitdon'" aus Blizzards Questtracker (Szenario, Maw Buffs). Profitdon klappt Blizzards Rezeptliste nicht mehr zu, sondern macht sie nur unsichtbar.

## 0.2.11

- Daten vom 21.11.: Lehrerpreise, Rezepte, Writs und Preisbasis aus den Aufzeichnungen und AH-Scans weiterer Spieler.

## 0.2.10
- Kaufen im Auktionshaus: nach einem Kauf kam ein Lua-Fehler (AHPage.lua), die Meldung "Gekauft" steht jetzt wieder farbig.
- Kaufen: Shift+Linksklick auf einen Gegenstand (Taschen, Chatlink) sucht ihn direkt, solange Kaufen offen ist und keine Chatzeile.
- Entzaubern > Herstellen: Auswahl "Meine Rezepte", "Alle Berufe" oder ein Beruf, wie in Berufe gerechnet, vorn gelernt oder fehlt.

## 0.2.9
- Flüssiger: der Tooltip merkt sich Median, Tendenz, Entzauberwert und Taschenzahl, statt sie beim Zeigen auf
  Gegenstände mehrmals je Sekunde neu zu rechnen; die Preisgeschichte rollt am Tagesanfang in kleinen Schritten.

## 0.2.8
- Tooltip: der Hinweis "AH: keine Angebote bekannt" entfällt bei seelengebundenen Gegenständen und Questgegenständen,
  die nie ins AH kommen.

## 0.2.7
- Tooltip: hat ein Gegenstand gar keinen AH-Preis (kein Scan, keine Preisgeschichte, kein TSM), steht dort jetzt grau
  "AH: keine Angebote bekannt" statt nichts.

## 0.2.6
- Tooltip: graue Zeile "Median n Tage" mit Tendenz aus der Preisgeschichte, auch für Gegenstände, die im letzten Scan
  fehlen ("nicht im letzten Scan"). Nur zur Anzeige, keine Rechnung nimmt den Median als AH-Preis.

## 0.2.5
- Median und Tendenz: die mitgelieferte Preisgeschichte nimmt jetzt jeden Scan eines Tages aus den Preisgeschichten
  aller unserer Konten und PCs (vorher nur den letzten Vollscan je Einsammeln), 7383 Gegenstände, Stand 21.11.
- Leerer Realmname im Spiel: Scans, Preisgeschichte und Figurdaten landen weiter beim Realm (zuletzt bekannter Name);
  was schon unter leerem Realm gespeichert war, wird beim Laden zum Realm zusammengeführt.
- Lehrerdaten (Data/Learn.lua) aufgefrischt.

## 0.2.4
- Ausrüstung mit Zufallssuffix ("of the Bear", "of Healing"): der Tooltip zeigt jetzt die Werte genau dieser Variante,
  in Kaufen, Verkaufen, Entzaubern und den anderen Listen (vorher nur der Grundgegenstand ohne Werte).

## 0.2.3
- Rechtsklick auf eine Zeile (Berufe, Herstellen und andere Listen): "Im AH suchen" sucht den Gegenstand im Reiter Kaufen,
  "Rezept im AH suchen" das Rezept dazu.
- Kaufen: neue Spalte Skill, die Fertigkeitsstufe, die ein Rezept verlangt.

## 0.2.2
- Kaufen und Einkaufsliste: "Gekauft: Anzahl für Preis" bleibt stehen, bis das Auktionshaus schließt (Summe je Gegenstand).
- Kaufen: bei Einzelposten zählt das Mengenfeld mit jedem Kauf herunter; Knopf und Vorschau sagen klar "nur 1 Stück je Klick".

## 0.2.1
- Kaufen: Spalte Stufe, Kategorien bis zur dritten Ebene (z. B. Stäbe), Nur benutzbar prüft Klasse und Stufe,
  ohne Juwelierskunst, neuer Filter Nur unbekannte Rezepte.
- Kaufen: die eingegebene Menge wird gekauft, die Grenze je Kaufklick gilt dort nicht mehr (Bestätigung mit Gesamtpreis bleibt).
- Kaufen: Klick daneben, neue Suche oder andere Kategorie schließen die Angebotsliste.
- Kaufen: x im Suchfeld leert es und springt zurück auf Alle Kategorien.

## 0.2.0
- Erste Version auf CurseForge (ungelistet, nur über den Link).
- Einkaufsliste als eigener Reiter, eigene Listen mit Namen (Vorrat halten oder feste Menge je Eintrag, Rechtsklick
  "Auf Liste" in jedem Reiter, Herstellen statt Kaufen auch mit Rezepten anderer Chars).
- Neuer erster Reiter Kaufen statt Blizzards Auktionsfenster: Kategorien, Suche, Menge frei mit Preisvorschau,
  Median der letzten Tage und Tendenz (Startwerte aus den bisherigen Scans), Angebotsliste je Preisstufe (Klick setzt die
  Menge), Filter Stufe, Qualität, Nur benutzbar, Genauer Name und Kann ich tragen; Blizzards Fenster per Knopf.
- Verkaufen: Klick auf ein Angebot übernimmt dessen Preis je Stück.
