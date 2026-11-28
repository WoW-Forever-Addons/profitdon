# Profitdon

## 0.2.57
- Herstellen, Berufe, Entzaubern: Solange eine Liste neu gerechnet wird (nach einem Vollscan, neuen Live-Angeboten oder Taschen), steht oben neben der Suche die gelbe Marke "Rechnet neu ...". Bis dahin zeigt die Liste den letzten Stand, danach sortiert sie sich neu.

## 0.2.56
- Kaufen: Ausrüstung "of the ..." zeigt im Tooltip und in der Spalte "Besser" die Werte der Variante schon vor dem Anklicken (bisher nur Rüstung des Grundteils).

## 0.2.55
- Herstellen: Wurden die Rezeptdaten beim Start nicht geladen, sagt Profitdon das jetzt klar (Chat beim Login und gelbe Zeile in der Liste: "bitte /reload") statt "einmal das Berufsfenster öffnen".

## 0.2.54
- Kaufen: neue Spalte "Besser" für Ausrüstung. Sie zeigt, um wie viel Prozent ein Teil besser oder schlechter ist als das, was du in dem Platz trägst, mit dem grünen Upgrade-Pfeil davor; "leer", wenn der Platz frei ist; grau, was du nicht tragen kannst. Ein Klick auf den Kopf sortiert das beste Upgrade nach oben. Braucht Geardon ab Version 1.8.

## 0.2.53
- Verkaufen: Alle Questgegenstände, die im AH gehandelt werden, stehen jetzt in der Liste, zum Beispiel die Seiten der Grünen Hügel des Schlingendorntals. Was keinen AH-Preis hat, bleibt draußen.

## 0.2.52
- Verkaufen: Craftsman's Writs (die Auftragsseiten) stehen jetzt in der Liste und lassen sich ins AH einstellen. Bisher fielen sie als Questgegenstände heraus. Andere Questgegenstände bleiben draußen.

## 0.2.51
- Gold/30 min und Gold/h unter Herstellen rechnen den Platz jetzt mit aufgeräumten Taschen: Alles zählt als frei bis auf Ruhestein, Berufswerkzeug (Hammer, Spitzhacke, Messer, Ruten, Angel, Arcane Salvager und so weiter) und Gebundenes ohne Händlerpreis. So hängt der Vergleich der Rezepte nicht davon ab, was gerade in den Taschen liegt. Die Einkaufsliste nennt weiter den echten Platz von jetzt.

## 0.2.50
- Einkaufsliste: Die Zeile unter dem Rezept nennt jetzt neben dem Platz auch, wie viele Crafts in 30 Minuten passen, bevor das Spiel dich wegen AFK ausloggt (28 Minuten Zauberzeit, Zwischenschritte mitgezählt). Gelb, wenn du mehr eingetragen hast.

## 0.2.49
- Der Optionen-Knopf in der Titelleiste war von der Rahmengrafik verdeckt. Er liegt jetzt darüber und ist zu sehen.

## 0.2.48
- Optionen-Knopf oben in der Titelleiste, links neben dem Schließen-Kreuz.
- Klick auf das Symbol Boosted Disenchanting rechnet alle Entzauberwerte so, als liefe der Buff. So siehst du vorher, ob sich der Arcane Salvager lohnt. Noch ein Klick stellt zurück. Deine eigenen Entzauberungen werden weiter nach dem echten Buff mitgeschrieben.

## 0.2.47
- Master Chef wird je Charakter gemerkt statt einmal für alle. Ein Char, der selbst kocht, rechnet mit seinem eigenen Stand. Ein Char ohne Kochen (etwa am Auktionshaus) rechnet mit dem Stand deines besten Kochs. Der Tooltip des Symbols sagt, wessen Stand gilt.

## 0.2.46
- Zwei runde Symbole oben rechts über den Listen: Master Chef und Boosted Disenchanting. Farbig, solange der Bonus eingerechnet ist, sonst grau. Der Tooltip sagt, womit gerechnet wird (Rang und Chance beim Kochen, auch für ungelernte Rezepte; Verzauberer, Buff und Prozent beim Entzaubern).

## 0.2.45
- Einkaufsliste: Rechtsklick auf eine Zeile, die du selbst herstellen würdest, bietet "Fertig kaufen statt herstellen". Die Zeile kauft dann das fertige Produkt (Händler oder AH), die Mats darunter fallen weg, und sie nennt, was Herstellen je Stück gekostet hätte. Gilt nur für diesen Einkauf; "Wieder selbst herstellen" stellt vorher zurück.

## 0.2.44
- Herstellfenster: die Zeile "Braucht ..." färbt jedes Teil einzeln wie das Spiel. Werkzeug in den Taschen (Hammer, Spanner) ist weiß, auch wenn der Amboss noch fehlt und rot bleibt.
- "Auf die Einkaufsliste" und "Auf Liste ..." springen nicht mehr zur Liste. Die Seite bleibt, wo du bist; der Menüeintrag "schon drauf: öffnen" zeigt die Liste weiterhin.

## 0.2.43
- Neuer Reiter "Auktionen": alle deine Auktionen mit Anzahl, Preis je Stück, billigstem Angebot anderer und Restzeit. Unterbotene stehen rot oben, Verkaufte am Ende. Zeile anklicken, dann "Abbrechen" (zweiter Klick bestätigt, die Gebühr steht dabei). Außerhalb des Auktionshauses zeigt der Reiter den letzten Stand.

## 0.2.42
- Kaufen: die Preisliste zeigt deine eigenen Auktionen bei ihrem Preis ("dazu 20 von dir", oder "nur du: 4 Stück", wenn nur du zu dem Preis anbietest). Sie zählen nicht als Angebot zum Kaufen.

## 0.2.41
- Einkaufsliste: ein einzelnes Stück, das mehr kostet als der Höchstbetrag je Klick (z. B. eine Waffe für 355g), ließ sich nicht kaufen ("Teurer als der Höchstbetrag je Klick"). Jetzt geht ein Stück je Klick, solange das Gold reicht, mit dem zweiten Bestätigungsklick.

## 0.2.40
- Einkaufsliste und Rezeptkosten: wer nur wenige Stück braucht, bekam den Durchschnitt der ersten 20 im AH als Preis (bei Ausrüstung den Schnitt aller Auktionen). Ein Stück kostet jetzt das billigste Angebot, mehr Stück entsprechend dazwischen.

## 0.2.39
- Einkaufsliste, "Live prüfen": Ausrüstung und andere Einzelgegenstände (keine Handelsware) wurden zwar gesucht, das Ergebnis aber nicht übernommen, die Liste blieb beim Preis des letzten Scans. Jetzt zählt das billigste Angebot, und der Preis bleibt auch nach den 15 Minuten.
- Einkaufsliste: steht ein Gegenstand laut Live-Prüfung gar nicht im AH, sagt die Zeile "gerade nicht im AH" und sein alter Preis zählt nicht mehr in "Einkauf gesamt".

## 0.2.38
- Beim Händler kaufen: führt der Händler einzelne Käufe einer Runde nicht aus, merkt Profitdon das am Gold und kauft das Fehlende von selbst nach. Die Zeile im Chat nennt, was wirklich bezahlt wurde.

## 0.2.37
- Auswertung: beim Verlassen der Welt (Ausloggen, Ladebildschirm) wurde das ganze Gold einmal als "Unterhalt" ausgegeben gebucht. Das passiert nicht mehr; die alten Fehlbuchungen werden beim nächsten Login einmal herausgenommen.
- Auswertung: "Gesamt" zeigte nur den heutigen Tag, jetzt alles seit Beginn (auch "Je Produkt").
- Herstellen, Berufe: "Rechne die Rezepte ..." blieb stehen, solange hergestellt wurde; die fertige Liste erscheint jetzt sofort.

## 0.2.36
- Einkaufsliste: der Rechtsklick auf einen Eintrag einer eigenen Liste beginnt wieder mit "Im AH suchen" (fehlte, seit Gegenstand und Kaufzeile eine Zeile sind).

## 0.2.35
- Tooltip: die Zeilen, die Profitdon in Item-Tooltips schreibt (AH, Median, Entzaubern, Händler, Shift-Details), erscheinen im englischen Client auf Englisch, im deutschen auf Deutsch. Der Rest von Profitdon bleibt deutsch.

## 0.2.34
- Optionen öffnen nur noch Profitdons eigenes Fenster; in den Spieloptionen unter AddOns steht nur ein Knopf dorthin. Fensterstil ist die gemeinsame Option der Don-Addons unter "Fenster".
- Gegenstandsnamen laden von selbst nach, statt "Item 232438" in Skillen, Entzaubern und Händler.
- Einkaufsliste: ein gekaufter Gegenstand einer eigenen Liste steht in einer Zeile mit "im AH" und Preis; die Summe ist eine eigene, lesbare Zeile (rot nur bei Goldmangel); lange Hinweise unten auf zwei Zeilen.
- Auswertung: kürzere Namen in "Gewinn je Methode", nichts mehr am rechten Rand abgeschnitten.
- Kaufen und Verkaufen ohne leere zweite Kopfzeile; "Jewelry(OBSOLETE)" nicht mehr in den Kategorien.

## 0.2.33
- Blizzard-Look: die Kopfzeilen der Listen (Kategorien in Kaufen, Gruppen in den anderen Listen) sind jetzt die Leiste des Spiels, Plus und Minus stehen rechts.

## 0.2.32
- Eigene Einkaufslisten gehören jetzt dem Char, der sie anlegt. Chip "Nur meine Listen" / "Listen aller Chars" im Reiter Einkaufsliste schaltet die Listen der anderen Chars des Accounts dazu (mit Charname am Chip).
- Rechtsklick auf eine fremde Liste: "Auf diesen Char kopieren" oder "Zu diesem Char verschieben". Eine Kopie nimmt beim erneuten Kopieren nur die fehlenden Einträge, und die fremde Liste steht neben ihrer Kopie nicht noch einmal da.
- Bisherige Listen gehören dem Char, der sie nach dem Update zuerst lädt. Preiswecker melden nur für die Listen des eigenen Chars.

## 0.2.31
- Weniger Ruckler: die Rechnung "lohnt bis" und "Platz für" jedes Rezepts macht im Hintergrund nach jedem Schritt Pause, kein Schritt der Rezeptlisten dauert länger als ein paar Millisekunden.
- Die Liste "Für Händler" wird nicht mehr nach jedem Looten und jede Minute neu gerechnet, sondern nur, wenn sich Mats, Platz in den Taschen, Preise oder Rezepte ändern.
- "Platz für" sucht ab dem letzten Ergebnis und ist dadurch viel schneller; die Zeilen einer neuen Liste werden vorab in kleinen Schritten gebaut, das Neuzeichnen und das erste Öffnen des Fensters gehen schneller.
- /profit set rechnet die Listen gleich neu.

## 0.2.30
- Einkaufsliste: Preiswecker je Gegenstand einer eigenen Liste (Rechtsklick auf den Eintrag, "Preiswecker stellen ..."). Sieht Profitdon den Gegenstand im AH zu diesem Preis oder billiger (Vollscan, Berufsscan, "Live prüfen" und jede Suche der Liste), steht eine Zeile im Chat. Die Zeile der Liste zeigt den Wecker, grün wenn erreicht. Gemeldet wird einmal, erneut erst, wenn der Preis zwischendurch darüber lag.

## 0.2.29
- Kaufen: Rechtsklick auf ein Ergebnis setzt den Gegenstand auf eine eigene Einkaufsliste (oder eine neue), wie in den anderen Reitern.

## 0.2.28
- Fenster beim Händler: die erste Zeile zum Verkaufen ist schon gewählt, ein Klick auf Verkaufen genügt; ist sie verkauft, rückt die nächste nach.
- Kaufen zählt die Anzahl in der Zeile mit herunter, auch "Kaufen läuft ..." in der Leiste erscheint jetzt.
- Ein Listeneintrag mit fester Menge wird nach dem Kauf beim selben Händlerbesuch nicht noch einmal voll angeboten; eine getippte Anzahl behält nur den Rest.

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
