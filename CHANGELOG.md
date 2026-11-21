# Profitdon

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
