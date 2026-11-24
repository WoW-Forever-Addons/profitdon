# Profitdon

## 0.2.27
- Hauptfenster öffnet ohne Standbild: Rezeptlisten rechnen im Hintergrund in kleinen Schritten, solange steht die letzte Liste oder "Rechne die Rezepte ...".
- Neuzeichnen von Herstellen, Berufe und Entzaubern > Herstellen ohne Neuberechnung der Zeilen und Tooltips; Itemdaten werden je Sitzung behalten.
- /profit diag nennt die Zeiten für Fenster öffnen, bauen und zeigen.

## 0.2.26
- Weniger Ruckler: Umbuchen der AH-Verkäufe, Rezepte und Altdaten lesen nach dem Login sowie das Berufsfenster beim Herstellen laufen in kleinen Schritten über mehrere Frames.
- Das Hauptfenster zeichnet bei neuen Itemdaten nur neu, wenn vorher ein Gegenstand fehlte.
- /profit diag zeigt unter "Langsam" die teuersten Aufrufe der letzten drei Tage.

## 0.2.25
- Favor-Kisten: neuer Schalter "Selbst herstellen" oben rechts. Aus: jedes Bündel wird gekauft (Händler oder AH) statt hergestellt, Gold je Gunst rechnet dann nur mit Kaufen.

## 0.2.24
- Favor-Kisten: jede Abgabe gibt 50c je Gunst zurück (2s 50c bis 10s), das rechnet Profitdon jetzt für jede Kiste ein, bis es selbst gemessen hat.
- Meldung "That bag is full.": /profit diag zeigt unter bagFull, was in dem Moment los war (letztes Herstellen, Taschen mit freien Plätzen und Art, Cursor, offene Fenster).

## 0.2.23
- Fehler behoben: Shift über einem fremden Fenster (z. B. beim Anklicken eines NPCs) meldete "Window.lua:1639: attempt to index field 'item'".

## 0.2.22
- Favor-Kisten: das Geld, das jede Abgabe zurückgibt (5s), zählt jetzt mit, in "Gold je Gunst" und in der Einkaufsliste. Profitdon misst den Betrag bei jeder Abgabe nach.

## 0.2.21
- Favor-Kisten: die Abgabe klappt jetzt auch, wenn der NPC die Kistenquest mit gelbem "!" anbietet (annehmen, abschließen, Belohnung). /profit diag zeigt unter crateAuto, was zuletzt passiert ist.

## 0.2.20
- Favor-Kisten geben sich beim Inventory Intake (Marcy Baker, Dokimi) von selbst ab: NPC anklicken genügt, Quest wählen, abschließen und Belohnung nehmen macht Profitdon. Shift beim Anklicken hält es an, Option unter Händler.

## 0.2.19
- Unter Händlerpreis: Gegenstände, die der Händler gar nicht annimmt, fallen raus (z. B. Blinding Powder, das Spiel nennt dafür 1s 25c). Lehnt ein Händler etwas ab, das der Profitdon-Knopf verkaufen wollte, merkt Profitdon sich das und zeigt es nicht mehr an.

## 0.2.18
- Ruckler bei Beute und beim Herstellen behoben: die Favor-Kisten werden mit einem Taschendurchlauf statt 15 gezählt, im Kampf gar nicht (einmal danach).
- Händlerfenster und Writ-Reiter lesen die Taschen einmal statt je Zeile. Der Minuten-Schnappschuss der Auswertung wartet im Kampf.

## 0.2.17
- Herstellen rechnet die eigene Zeit mit: ein Zwischenteil (z. B. Copper Modulator) wird gekauft, wenn Selbermachen je Stunde weniger spart, als dein bestes Rezept in "Für Händler" je Stunde bringt. Die Zeile nennt beides. Option "Zeit mitrechnen" unter "Was lohnt".
- Einkaufsliste: Favor-Kisten zeigen, was der Einkauf je Gunst kostet, in der Kistenzeile und in der Summe unten.

## 0.2.16
- Intern: Rucklersuche schreibt Aufrufe ab 8 ms mit. Keine sichtbare Änderung.

## 0.2.15
- Intern: langsame Aufrufe (ab 8 ms) werden für die Rucklersuche mitgeschrieben. Keine sichtbare Änderung.

## 0.2.14
- Shift+Linksklick in die Suche von Kaufen klappt jetzt auch aus Baganator und Blizzards Taschen (der Client nimmt einen neueren Weg für Links).

## 0.2.13

- Tooltip: Preise aus den mitgelieferten Scans gelten jetzt für den Realm, egal unter welchem Namen das Spiel ihn meldet (EU4 Realm 7, EU5 Realm 1 oder leer). Vorher fehlte dann jeder Preis.
- Tooltip: grüne Ausrüstung ohne bekannten Preis zeigt wieder "AH: keine Angebote bekannt".

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
