local _, ns = ...

---------------------------------------------------------------------------
-- The window, built from DonCore's kit only (as Golddon's): Kit.Window "ProfitdonFrame" (place and size in
-- ProfitdonDB.win), four book tabs, the lists of a tab as chips, every list a Kit.Table, the chosen row in a Kit.ActionBar
-- under the list with its action button. Every disenchant row and its tooltip show the single mats with chance and count.
--   Herstellen: Für Händler (recipes, mats, vendor price, profit, ROI, AH netto), Für Auktionshaus (the same against the
--               AH after the cut), Skillen (Skill.lua: cost per skill point
--               for any own character, learning cost), Einkaufsliste (the chosen recipe and everything put on it from Skillen)
--   Entzaubern: Im AH (gear under its expected mats), Herstellen (crafts to disenchant), Tasche (the bag button)
--   Händler:    auctions under the vendor price
--   Verkaufen:  mats and crafted goods at exactly the cheapest offer
---------------------------------------------------------------------------
local Core = LibStub("DonCore-1.0")
local Kit = Core:Get("Kit", 23)
local C, S = Kit.C, Kit.SIZE
-- (Daniel 15.11.2026, Blizzard-Optik) the builders of the window's parts: the kit, or the same calls made from Blizzard's
-- templates (DonCore module Blizz, ns.LookKit) when the client has them and the option blizzLook is on; chosen in Build
local UI = Kit
local W
local group, tab = "craft", "craft"
local floor, max, min = math.floor, math.max, math.min

-- (Daniel 19.11.2026: "die Einkaufsliste auch unten als Reiter haben ... eigene Listen") Einkaufsliste is a book tab
-- of its own: the list from Herstellen (chip "Aus Herstellen") and the own lists (ShopLists.lua), one chip each
-- (Daniel 20.11.2026: "Diese Such-/Kaufseite als ERSTEN Reiter unten") Kaufen, the AH's search and purchase (AHPage.lua)
local GROUPS = { { "ah", "Kaufen" }, { "craft", "Herstellen" }, { "shop", "Einkaufsliste" }, { "prof", "Berufe" }, { "de", "Entzaubern" }, { "vendor", "Händler" }, { "sell", "Verkaufen" }, { "report", "Auswertung" } }
local SUBS = { ah = { "ah" }, craft = { "craft", "ahcraft", "skill" }, shop = { "shop" }, prof = { "pvendor", "pah" }, de = { "deah", "demake", "debag" }, vendor = { "vendor", "crates", "writs" }, sell = { "sell" }, report = { "report" } }
local GROUP_OF = {}
for g, list in pairs(SUBS) do for _, k in ipairs(list) do GROUP_OF[k] = g end end
local TABS = {
  ah = { "Kaufen", "Suchen und kaufen wie im Auktionshaus: links Kategorien, oben Suche, unten Menge, Preisvorschau, Median und Tendenz." },
  craft = { "Für Händler", "Rezepte des Chars: Mats (Händler ohne Grenze, sonst selbst hergestellt oder AH), Händlerpreis, Gewinn und ROI." },
  -- (Daniel 07.11.2026: "da gerne noch einen reiter neben für händler \"für auktionshaus\"")
  ahcraft = { "Für Auktionshaus", "Rezepte des Chars: Mats gegen das billigste Angebot des Ergebnisses im AH nach Gebühr, Gewinn und ROI." },
  -- (Daniel 08.11.2026) Berufe: every recipe of the chosen profession, also not learned, for a twink to take up
  pvendor = { "An Händler", "Alle Rezepte des Berufs im Spiel, als hätte ein Char ihn ganz oben: Mats (Zwischenschritte des Berufs selbst hergestellt, wenn billiger), Händlerpreis, Gewinn, ROI, Zauberzeit." },
  pah = { "An AH", "Alle Rezepte des Berufs im Spiel gegen das billigste Angebot des Ergebnisses im AH nach Gebühr, Gewinn, ROI, Zauberzeit." },
  skill = { "Skillen", "Rezepte, die dem Char jetzt Punkte bringen: je Punkt: minus = kostet, plus = bringt Gewinn (Mats gegen Verkaufswert, durch die Chance, mit Lernkosten). \"je Punkt\" nimmt das Bessere, \"Händler\" und \"AH\" je einen Weg. Billigste zuerst." },
  shop = { "Aus Herstellen", "Die Mats des gewählten Rezepts und aller Rezepte aus Skillen, abzüglich der Taschen. AH-Zeile anklicken: Kauf je Klick." },
  deah = { "Im AH", "Grüne und Blaue im AH, deren erwartete Mats nach Gebühr mehr wert sind als der Preis." },
  demake = { "Herstellen", "Herstellen zum Entzaubern: erwartete Mats des Ergebnisses gegen die Matkosten." },
  debag = { "Tasche", "Was der Knopf entzaubert, ein Klick je Gegenstand. Im AH mehr Wertes bleibt liegen (außer zum Entzaubern gekauft)." },
  vendor = { "Unter Händlerpreis", "Sofortkauf unter Händlerpreis: kaufen, beim Händler mit dem Profitdon-Knopf verkaufen." },
  -- (Daniel 08.11.2026: Merchant's-Favor-Kisten "droppen random und können im ah gekauft werden") Favor.lua
  crates = { "Favor-Kisten", "Waylaid Crates im AH: Kiste plus billigstes Bündel, geteilt durch die Gunst. Billigste Gunst zuerst, Zeile anklicken: im AH suchen und kaufen." },
  -- (Daniel 18.11.2026: Craftsman's Writs "möglichst effizient mit wenig laufwegen ... möglichst günstig") Writs.lua
  writs = { "Writs", "Craftsman's Writs: Writ im AH plus Ware, abzüglich Coin Pouch, je Ruf. Je Gebiet eine Kopfzeile mit + und - (billigster Ruf zuerst), darin je Ruf; ein Spaltenklick sortiert in jedem Gebiet. Zeile anklicken: Writ im AH kaufen. Rechtsklick auf einen Writ in der Tasche: Profitdon merkt sich den Kunden aus dem Angebot." },
  sell = { "Verkaufen", "Entzauberungsmats, Hergestelltes und Ausrüstung, die im AH mehr bringt als Entzaubern: genau zum Preis des billigsten Angebots, nicht darunter." },
  -- (Daniel 06.11.2026) Report.lua: Startkapital je Char, Gewinn seit Start, Goldverlauf, Gewinn je Methode
  report = { "Auswertung", "Gewinn seit dem Startkapital, Goldverlauf und Gewinn je Methode." },
}
local CRAFT_MODE = { craft = "vendor", ahcraft = "ah", demake = "de" }
local PROF_MODE = { pvendor = "vendor", pah = "ah" }
local KIND = { deah = "de", vendor = "vendor", shop = "mats", sell = "post", crates = "crate", writs = "writ" }
ns.WINDOW_SUBS = SUBS -- (tests)
-- the own lists: chip key "sl<id>" -> list id
local LISTKEY = {}
local function IsShop(k) return k == "shop" or LISTKEY[k] ~= nil end
ns.WindowIsShop = IsShop -- (tests)
local function ListKey(id) return "sl" .. tostring(id) end

local SkillRows
local function M(c) return c and Kit.Money(c) or "" end
local function MS(c) return c and Kit.Money(c, { sign = true }) or "" end
local function Pct(p) return p and (p .. " %") or "" end
-- gold an hour of crafting: the profit of one craft over its time (steps on the way included); a recipe with a cooldown
-- makes one per cooldown at most. nil without a time or a profit.
local function GPH(v, profit)
  if not (profit and v and v.time and v.time > 0) then return nil end
  local per = v.time
  local cd = v.r and ns.Crafts.CooldownSec(v.r.spell)
  if type(cd) == "number" and cd > per then per = cd end
  return math.floor(profit * 3600 / per + 0.5)
end
ns.WindowGPH = GPH -- (tests)
-- (Daniel 18.11.2026) the gain of a run (Crafts.lua Cr.Run), nil without one
local function RunGain(run) return type(run) == "table" and run.gain or nil end
-- (14.11.2026) a shopping list row whose mats lie in the bank says so: they have to be fetched before crafting
local function BankBit(e)
  if ns.db.shopNoHave or not e.id or (e.held or 0) <= 0 then return "" end
  local b = math.min(e.held, ns.BankCount(e.id))
  return b > 0 and (", davon %d in der Bank"):format(b) or ""
end
local function ItemName(id)
  local name, _, quality = ns.ItemInfo(id)
  return name or ("Item " .. id), quality
end

local function Col(key, title, width, extra)
  -- (Daniel 06.11.2026: "spalten auch immer sortierbar machen ... nach roi") every number column sorts
  local c = { key = key, title = title, width = width, sort = key ~= "title" }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local ITEM = Col("title", "Gegenstand", nil, { sort = true })
-- (Durchsicht 11.11.2026) one word per meaning in every list: "Kosten" what the mats cost, "Mat-Wert" what disenchanting
-- brings, "Anzahl" a count, "ab Skill" the skill a recipe is learned at; "AH Gewinn" alone (the two numbers "1s 90c (+92c)"
-- were cut off in 84 px, the AH price itself stays in the tooltip). The shopping list is a tree: its heads do not sort.
-- (Daniel 15.11.2026: "machbar überall weglassen") no column "Machbar" any more; the Herstellfenster says what can be made
local NOSORT = { sort = false }
-- (Daniel 18.11.2026: "Profit pro Stunde, Profit pro halbe Stunde ... mit dem Platzbedarf") for the vendor: what one run of
-- crafting really brings (Crafts.lua Cr.Run: time, room and the last count that pays), and Gold/h as two runs back to
-- back; the head names the run's length (option runMin), set before each draw. ROI and Gold/h give way first.
local RUNCOL = Col("run", "Gold/30 min", 84)
local GPHCOL = Col("gph", "Gold/h", 76, { minWidth = 700, fold = "1 h" })
local ROIFOLD = { minWidth = 760, fold = "ROI" }
local COLS = {
  report = { ITEM },
  -- (Daniel 16.11.2026: "ich stelle ja sachen in 1000facher ausfertigung über den tag her ... crispy lizard sinnvoller, weil
  -- es mehr crafts die stunde raus haut ... eine spalte mit gold / h ... dafür dann bei an händler den ah preis raus") for
  -- the vendor: gold an hour of crafting instead of "AH Gewinn" (the AH numbers stay in the tooltip)
  -- (Daniel 18.11.2026: "die Spalte Gold pro 30 Minuten oder Gold pro Stunde, was man da vorne eingestellt hat, als
  -- allererste Spalte") the run stands right after the name
  craft = { ITEM, RUNCOL, Col("time", "Zeit", 60, { minWidth = 700, fold = "Zeit" }), Col("cost", "Kosten", 84), Col("vendor", "Händler", 84), Col("profit", "Gewinn", 84),
    Col("roi", "ROI", 56, ROIFOLD), GPHCOL },
  ahcraft = { ITEM, Col("time", "Zeit", 60, { minWidth = 700, fold = "Zeit" }), Col("cost", "Kosten", 84), Col("ah", "AH netto", 84), Col("profit", "Gewinn", 84),
    Col("roi", "ROI", 56), Col("dem", "Absatz", 64), Col("vendor", "Händler", 84, { minWidth = 760, fold = "H" }) },
  skill = { ITEM, Col("chance", "Chance", 56), Col("crafts", "bis grau", 60), Col("per", "je Punkt", 84), Col("perv", "Händler", 76, { minWidth = 700, fold = "H" }),
    Col("pera", "AH", 76, { minWidth = 700, fold = "AH" }), Col("learn", "Lernen", 84),
    Col("cost", "Kosten", 84, { minWidth = 760, fold = "Kosten" }) },
  pvendor = { ITEM, RUNCOL, Col("learn", "ab Skill", 60), Col("rcost", "Rezept", 76, { minWidth = 760, fold = "Rezept" }), Col("time", "Zeit", 60, { minWidth = 700, fold = "Zeit" }), Col("cost", "Kosten", 84),
    Col("vendor", "Händler", 84), Col("profit", "Gewinn", 84), Col("roi", "ROI", 56, ROIFOLD), GPHCOL },
  pah = { ITEM, Col("learn", "ab Skill", 60), Col("rcost", "Rezept", 76, { minWidth = 760, fold = "Rezept" }), Col("time", "Zeit", 60, { minWidth = 700, fold = "Zeit" }), Col("cost", "Kosten", 84),
    Col("ah", "AH netto", 84), Col("profit", "Gewinn", 84), Col("roi", "ROI", 56), Col("dem", "Absatz", 64), Col("vendor", "Händler", 84, { minWidth = 760, fold = "H" }) },
  shop = { Col("title", "Gegenstand", nil, NOSORT), Col("need", "Anzahl", 64, NOSORT), Col("unit", "je Stück", 84, NOSORT), Col("cost", "Summe", 96, NOSORT) },
  -- (Daniel 15.11.2026, Bild Im AH: "irreführend mit dem gewinn. man müsste dazu ja alles aufkaufen ... vielleicht eher
  -- durchschnittlicher gewinn pro disenchant. aber auch dafür müsste man ja etliche kaufen") the profit per piece at the
  -- cheapest offer, and "sicher ab": so many pieces until the average is likely to show (Disenchant.lua DE.SureAt);
  -- the sum over all offers stays in the tooltip
  deah = { ITEM, Col("count", "Anzahl", 56), Col("cost", "Preis ab", 84), Col("value", "Mat-Wert", 84), Col("profit", "Gewinn je Stück", 104),
    Col("sure", "sicher ab", 70) },
  demake = { ITEM, Col("cost", "Kosten", 84), Col("value", "Mat-Wert", 90), Col("profit", "Gewinn", 84), Col("roi", "ROI", 56) },
  debag = { ITEM, Col("value", "Mat-Wert", 90) },
  crates = { ITEM, Col("gain", "Gunst", 50), Col("crate", "Kiste", 84), Col("bundle", "Bündel", 84), Col("total", "Gesamt", 84), Col("per", "je Gunst", 84) },
  writs = { ITEM, Col("rep", "Ruf", 44), Col("writ", "Writ", 76), Col("ware", "Ware", 76), Col("net", "netto", 76, { minWidth = 700, fold = "n" }), Col("per", "je Ruf", 70) },
  vendor = { ITEM, Col("count", "Anzahl", 56), Col("cost", "Kosten", 84), Col("profit", "Gewinn", 84), Col("roi", "ROI", 56) },
  sell = { ITEM, Col("count", "Anzahl", 56), Col("unit", "je Stück", 84), Col("ret", "nach Gebühr", 96), Col("profit", "mehr als Händler", 110, { minWidth = 700, fold = "+" }) },
}
ns.WindowCols = COLS -- (tests)
-- the columns of a list as shown: a run of 60 min is the hour itself, Gold/h would say the same twice
-- (Daniel 18.11.2026: "dass man die Spalten mit einem Linksklick verschieben kann ... so anpassen kann, wie man das
-- braucht") in the order the player dragged them to, kept per list in ProfitdonDB.ui.cols[list] (DonCore Kit 30,
-- Kit.ColumnOrder); a right click on a head brings the list's own order back
local function BaseCols(t)
  local cols = COLS[t] or (LISTKEY[t] and COLS.shop)
  if (ns.Opt("runMin") or 30) ~= 60 or not cols then return cols end
  local out = {}
  for _, c in ipairs(cols) do if c ~= GPHCOL then out[#out + 1] = c end end
  return out
end
local function ColKit() return LibStub("DonCore-1.0"):Get("Kit", 30) end
function ns.WindowColsNow(t)
  local cols = BaseCols(t)
  local saved = type(ns.db.ui) == "table" and type(ns.db.ui.cols) == "table" and ns.db.ui.cols[t]
  if not (cols and saved) then return cols end
  return (ColKit().ColumnOrder(cols, saved))
end
-- from, to: column keys; both nil: the own order back
function ns.WindowMoveCol(t, from, to)
  ns.db.ui = ns.db.ui or {}
  ns.db.ui.cols = ns.db.ui.cols or {}
  if not from then ns.db.ui.cols[t] = nil return end
  local cols = BaseCols(t)
  if not cols then return end
  local _, keys = ColKit().ColumnOrder(cols, ns.db.ui.cols[t], from, to)
  ns.db.ui.cols[t] = keys
end

-- colour codes of the notes inside a line
local YEL, RED, GRN, MUT = "|cffe6b422", "|cffe0524a", "|cff4fd16b", "|cff8792a8"
ns.WINDOW_COLS = COLS -- (tests)

-- (Durchsicht 11.11.2026, Gold Core: the row never said that a mat was counted as made by oneself, only the tooltip did)
-- the mats of a row in one line, a mat made on the way marked "(selbst)"; second value: the made mats whose recipe this
-- character has not learned (Berufe counts the profession as complete); cooldown: the yellow word in front of the line
local function PartsText(v)
  local parts, missing = {}, {}
  for _, p in ipairs(v.parts) do
    local t = p.n .. "× " .. ItemName(p.id)
    if p.src == "craft" then
      t = t .. " " .. YEL .. "(selbst)|r"
      if p.via and not ns.Crafts.IKnow(p.via.spell) then missing[#missing + 1] = (ItemName(p.id)) end
    end
    parts[#parts + 1] = t
  end
  return table.concat(parts, ", "), missing
end
local function CooldownLead(v)
  local cd = ns.Crafts.CooldownText(v.r.spell)
  if not cd then return "" end
  -- (Daniel 14.11.2026) and what is left of it: green "bereit", yellow "bereit in 1 T 22 h"
  local st, left = ns.Crafts.CooldownState(v.r.spell)
  if st then return (left > 0 and YEL or "|cff4fd16b") .. cd .. ", " .. st .. "|r  " end
  return YEL .. cd .. "|r  "
end

-- (Daniel 07.11.2026: "blizzards tooltip möglich, wenn ich mit der maus direkt drüber bin?") the game's item tooltip
-- (Kit.ItemTipFn over itemID), Profitdon's lines below it under a heading
local function TipLines(tip)
  local lines, short
  if type(tip) == "table" and type(tip[2]) == "table" then
    lines = { { "Profitdon", color = C.gold } }
    for _, l in ipairs(tip[2]) do lines[#lines + 1] = l end
    -- (Daniel 18.11.2026: "den liest sich doch kein arsch durch") lines marked detail show only with Shift held
    local hasDetail = false
    for _, l in ipairs(lines) do if type(l) == "table" and l.detail then hasDetail = true end end
    if hasDetail then
      short = {}
      for _, l in ipairs(lines) do if not (type(l) == "table" and l.detail) then short[#short + 1] = l end end
      short[#short + 1] = { "Shift: Mats einzeln, Absatz, Zeit", color = C.muted }
    end
  end
  local shift = short and IsShiftKeyDown and IsShiftKeyDown()
  return (short and not shift) and short or lines, short, short and lines or nil
end
-- (24.11.2026, Ruckler, Laptop: Herstellen drew in 191 ms, every row's tooltip worked out at every redraw) a tooltip given
-- as a function is worked out when it is first read (the mouse over the row, Shift)
local lazyTip = { __index = function(it, k)
  if k ~= "tipLines" and k ~= "tipShort" and k ~= "tipFull" then return nil end
  local f = rawget(it, "tipFn")
  if not f then return nil end
  rawset(it, "tipFn", nil)
  local ok, tip = pcall(f)
  if not ok then ns.Try(error, tip, 0) tip = nil end
  local lines, short, full = TipLines(tip)
  rawset(it, "tipLines", lines) rawset(it, "tipShort", short) rawset(it, "tipFull", full)
  return rawget(it, k)
end }
local function Row(id, sub, cells, entry, tip, extra)
  local name, q = ItemName(id)
  local lines, short, full
  if type(tip) ~= "function" then lines, short, full = TipLines(tip) end
  local it = { kind = "trow", title = name, quality = q, itemID = id, icon = ns.Icon(id), sub = sub or "", cells = cells or {},
    entry = entry, id = id, tipLines = lines, tipShort = short, tipFull = full,
    -- (Daniel 21.11.2026: "überall fehlen die werte der ausrüstung wenn es of the ... ist") a piece from the bags: the
    -- tooltip of the piece itself (its link), with the suffix stats
    itemLink = type(entry) == "table" and type(entry.link) == "string" and entry.link or nil }
  for k, v in pairs(extra or {}) do it[k] = v end
  if type(tip) == "function" then it.tipFn = tip setmetatable(it, lazyTip) end
  return it
end
-- (24.11.2026) a row of a craft list is built once for its recipe's value (v, new with every new reckoning, Crafts.lua
-- Cr.RowsSoon) and taken again at the next redraw; only "chosen" is set anew. An item name still missing builds it again.
-- (24.11.2026, Runde 5: the redraw after a new list took 16.5 ms on the laptop, every row built at once) rowPause: set
-- (Daniel 24.11.2026, Bild Herstellen: "steht manchmal ganz lange da und wenn ich erneut auf für händler klicke erscheint
-- direkt alles") the window shows "Rechne die Rezepte ..." instead of a list: the finished list is drawn at once, not
-- after the casting and the craft queue (ns.WhenIdle waited as long as he crafted)
local calcNote
local function DrawDone()
  if not (W and W:IsShown()) then return end
  if calcNote then calcNote = nil ns.After(0.05, ns.Refresh) else ns.WhenIdle("Hauptfenster", ns.Refresh, 0.05) end
end
ns.WindowCalcNote = function() return calcNote end -- (tests)
-- while the job "Fenster Zeilen" (ns.RowsDone) builds the rows ahead, a slice may end before each row built
local rowPause
local function KeptRow(v, key, build)
  local kept = v._rows
  local it = kept and kept[key]
  if it then return it end
  if rowPause then rowPause() end
  local miss0 = ns.infoMiss
  it = build()
  if ns.infoMiss == miss0 then
    v._rows = kept or {}
    v._rows[key] = it
  end
  return it
end

-- tooltip of a disenchant row: the mats with chance and count, their value, the rates' source
local function DETip(id, group, head)
  local lines = {}
  for _, l in ipairs(head or {}) do lines[#lines + 1] = l end
  for _, l in ipairs(ns.DE.TipLines(group, nil, id)) do lines[#lines + 1] = l end
  return { ItemName(id), lines }
end

-- (Daniel 09.11.2026, Berufe) the rough price of learning a recipe: trainer, vendor, Favor in gold over the cheapest crate,
-- AH; shown only, the profit stays without it. Returns the sort value and the cell text.
local function RecipeCost(v)
  local l = ns.Skill.Learn(v.r.spell)
  if l.cost then return l.cost, (l.kind == "favor" and "~" or "") .. M(l.cost) end
  if l.kind == "favor" then return nil, l.short or "Gunst" end
  return nil, l.kind == "quest" and "Quest" or l.kind == "drop" and "Drop" or "unbekannt"
end

-- (Daniel 14.11.2026, demand) "gut 4": the label in its colour and the pieces the AH takes now; the sort value is the
-- expected profit of those pieces (what a round at the AH brings), unknown last
local DEM_COLOR = { good = "|cff4fd16b", slow = "|cffffd24a", poor = "|cffff6b6b" }
local function DemCell(v)
  local d = v.dem
  if not d then return "|cff9a9a9a?|r", -1e12 end
  local text = DEM_COLOR[d.label] .. ns.Market.LABEL[d.label] .. "|r" .. (d.label ~= "poor" and (" " .. d.qty) or "")
  return text, (v.ahExpProfit or 0) * math.max(d.qty, 0) + (d.label == "good" and 2 or d.label == "slow" and 1 or 0)
end
local function DemLines(v, lines)
  -- (Daniel 18.11.2026: tooltip "den liest sich doch kein arsch durch") only the recommendation without Shift
  local function add(l) if type(l) == "table" and l[1] ~= "Empfehlung" then l.detail = true end lines[#lines + 1] = l end
  local d = v.dem
  if not d then add({ "Absatz im AH", "unbekannt (keine Verkaufszahlen)" }) return end
  local function dec(n) return (("%.1f"):format(n):gsub("%.", ",")) end
  add({ "Absatz im AH", ("%s: %s je Tag, Quote %d %%%s"):format(ns.Market.LABEL[d.label], dec(d.perDay), math.floor(d.rate * 100 + 0.5),
    d.src == "own" and " (eigene Scans)" or d.src == "sold" and " (eigene Verkäufe)" or " (TSM Region)") })
  if d.ownRate then add({ "Quote aus eigenen Verkäufen", ("%d von %d eingestellten verkauft"):format(d.sold, d.posted) }) end
  if d.offers then
    add({ "Angebote jetzt", d.supply and ("%d, Vorrat für %s Tage"):format(d.offers, dec(d.supply)) or tostring(d.offers) })
  end
  if d.avg then add({ "Verkauft im Schnitt für", M(d.avg) }) end
  if v.ahExp then add({ "Erwartet je Craft (Quote, sonst Händler)", M(v.ahExp) .. ", Gewinn " .. MS(v.ahExpProfit) }) end
  if v.ahExp and (v.vendor or 0) > 0 then
    local h = (ns.POST_HOURS and ns.POST_HOURS[ns.Opt("postDur")]) or 24
    local share, n = ns.Deals.DepositSeen(h)
    add({ ("Einstellgebühr (%d h, %s)"):format(h, share and ("gemessen aus %d Einstellungen"):format(n) or (ns.Deals.DEP_STEP[h] and ("%d %% vom Händlerpreis"):format(ns.Deals.DEP_STEP[h]) or "geschätzt")),
      M(ns.Deals.Deposit(v.vendor, 1, h)) })
  end
  if d.label == "poor" then add({ "Empfehlung", "nicht fürs AH herstellen" })
  elseif v.ahExp and (v.vendor or 0) >= v.ahExp then add({ "Empfehlung", "zum Händler: er zahlt mehr, als das AH erwarten lässt" })
  elseif d.qty > 0 then
    add({ "Empfehlung", ("höchstens %d ins AH%s, Rest zum Händler"):format(d.qty, d.have > 0 and (" (%d schon da)"):format(d.have) or "") })
  else add({ "Empfehlung", ("nichts herstellen, %d schon da"):format(d.have) }) end
end

-- (Daniel 18.11.2026, Bild Light Leather Pants: "den tooltip innerhalb von profitdon überdenken, den liest sich doch kein
-- arsch durch"; gewählt: "Fazit oben, Shift für Details") first whether it pays and where, then mats and sale in one line
-- each and what can be made now; every line marked detail shows only with Shift (Row: tipShort / tipFull)
local function Verdict(label, parts)
  local best
  for _, p in ipairs(parts) do if p[2] and (not best or p[2] > best[2]) then best = p end end
  local txt = {}
  for _, p in ipairs(parts) do if p[2] then txt[#txt + 1] = p[1] .. " " .. MS(p[2]) end end
  local good = best and best[2] > 0
  return { (good and GRN .. "Lohnt|r" or RED .. "Lohnt nicht|r") .. (label or ""), table.concat(txt, " · ") }
end

local function CraftTip(v, deMode)
  local lines = {}
  local Cr = ns.Crafts
  local function D(l) l.detail = true lines[#lines + 1] = l end
  local cdText = Cr.CooldownText(v.r.spell)
  if deMode then
    lines[#lines + 1] = Verdict(nil, { { "Entzaubern", v.deProfit } })
  else
    local parts = { { "Händler", v.profit } }
    if v.ahNet then table.insert(parts, v.mode == "ah" and 1 or 2, { "AH", v.ahProfit }) end
    lines[#lines + 1] = Verdict(nil, parts)
  end
  lines[#lines + 1] = { "Mats", M(v.cost) }
  if not deMode then
    lines[#lines + 1] = { ("Verkauf (%s Stück%s)"):format(Cr.YieldText(v.r), v.r.min and ", im Schnitt" or ""),
      "Händler " .. M(v.vendor) .. (v.ahNet and (" · AH " .. M(v.ahNet) .. (v.ahFromAvg and " (Schnitt)" or "")) or "") }
  end
  if cdText then lines[#lines + 1] = { cdText, "höchstens 1 je Abklingzeit" } end
  if v.view then
    local _, rcText = RecipeCost(v)
    local known = v.knownBy and #v.knownBy > 0
    lines[#lines + 1] = { "Rezept", known and "gelernt" or ("%s, ab Stufe %s"):format(rcText or "?", v.r.learnMax and ("≤" .. v.r.learnMax) or tostring(v.r.learn or 0)) }
  else
    lines[#lines + 1] = { "Machbar jetzt", (v.maxCraft or 0) > 0 and tostring(v.maxCraft) or "0 (Mats oder Platz fehlen)" }
  end
  -- details with Shift
  for _, p in ipairs(v.parts) do
    local how = p.src == "vendor" and "Händler" or p.src == "craft" and "herstellen" or "AH"
    D({ ("%d× %s (%s)"):format(p.n, ItemName(p.id), how), M(p.unit * p.n) })
  end
  if deMode then
    for _, l in ipairs(ns.DE.TipLines(v.group, nil, v.id)) do if type(l) == "table" then D(l) else D({ l }) end end
  else
    local yl = Cr.YieldLine(v.r)
    if yl then if type(yl) == "table" then D(yl) else D({ yl }) end end
    D({ "ROI Händler" .. (v.ahNet and " · AH" or ""), Pct(v.roi) .. (v.ahNet and (" · " .. Pct(v.ahRoi)) or "") })
    if v.mode == "ah" or v.dem then DemLines(v, lines) end
  end
  if v.time then
    local gain = deMode and v.deProfit or (v.mode == "ah" and v.ahProfit or v.profit)
    -- (Daniel 18.11.2026) at the cheapest price and without a limit: only the best case, the run below says what is real
    local per = gain and v.time > 0 and not cdText and (", bestenfalls " .. MS(math.floor(gain * 3600 / v.time + 0.5)) .. " je Stunde") or ""
    D({ "Zeit je Herstellung", Cr.Dur(v.time) .. per })
    for _, st in ipairs(v.steps or {}) do
      local n = st.crafts
      local nt = math.abs(n - math.floor(n + 0.5)) < 0.05 and tostring(math.floor(n + 0.5)) or (("%.1f"):format(n):gsub("%.", ","))
      D({ ("  davon %s× %s herstellen"):format(nt, ItemName(st.id)), Cr.Dur(n * st.each) })
    end
  end
  -- (Daniel 18.11.2026: "Profit pro halbe Stunde ... mit dem Platzbedarf") the run: how many, what stops it, the gain
  if not deMode and v.mode ~= "ah" then
    local function RunLine(label, run)
      if type(run) ~= "table" then return end
      if (run.n or 0) < 1 then D({ label, "lohnt nicht (" .. run.limit .. ")" }) return end
      local why = ({ Zeit = "Zeit voll", Platz = "Taschen voll", Preis = "danach zu teuer", Abklingzeit = "Abklingzeit" })[run.limit] or run.limit
      D({ label, ("%d× herstellen, %s, %s"):format(run.n, why, MS(run.gain)) })
    end
    RunLine(("Lauf %d min"):format(ns.Opt("runMin") or 30), v.run)
    RunLine("Eine Stunde", v.runH)
  end
  if v.view and v.knownBy and #v.knownBy > 0 then
    local names = {}
    for _, ch in ipairs(v.knownBy) do names[#names + 1] = ns.Skill.Short(ch) end
    D({ "Gelernt von", table.concat(names, ", ") })
  elseif v.view then
    local l = ns.Skill.Learn(v.r.spell)
    D({ "Lernen: " .. l.text, l.cost and M(l.cost) or l.short or "" })
    for i, n in ipairs(l.all or {}) do if i <= 6 then D({ "  " .. n }) end end
  end
  return { ItemName(v.id), lines }
end

-- (Daniel 07.11.2026) Skillen: every recipe that gives the chosen character points now, the cheapest point first
local function SkillTip(e)
  local lines = {}
  local col = e.color and ("|c%s%s|r"):format(ns.Skill.HEX[e.color], ns.Skill.WORD[e.color]) or "?"
  lines[#lines + 1] = { "Farbe, Chance auf einen Punkt", col .. ", " .. floor(e.chance * 100 + 0.5) .. " %" }
  lines[#lines + 1] = { "Bis grau (oder Stufengrenze)", ("%d Crafts für %d Punkte"):format(e.crafts, e.pts) }
  if e.v then
    for _, p in ipairs(e.v.parts) do
      local how = p.src == "vendor" and "Händler" or p.src == "craft" and "herstellen" or "AH"
      lines[#lines + 1] = { ("%d× %s (%s)"):format(p.n, ItemName(p.id), how), M(p.unit * p.n) }
    end
    lines[#lines + 1] = { "Mats je Craft", M(e.cost) }
    lines[#lines + 1] = { "Ergebnis bringt zurück (Händler oder AH netto)", M(e.back) }
    -- (Daniel 07.11.2026, Swiftness Potion "+74" in green read as profit: "da mach ich doch kein gewinn mit") the sign is what
    -- Daniel gains: minus is a cost, plus a gain
    lines[#lines + 1] = { e.back >= e.cost and "Gewinn je Craft" or "Verlust je Craft", MS(e.back - e.cost) }
    -- (Daniel 08.11.2026, Goblin Deviled Clams "+1s 33" bei +10c je Craft: "die rechnung ist doch nicht richtig?") a point
    -- takes 1 / chance crafts, the line says so
    local perPt = 1 / math.max(e.chance, 0.001)
    local nTxt = perPt >= 1.05 and (", etwa %s Crafts"):format(perPt < 10 and string.format("%.1f", perPt):gsub("%.", ",") or floor(perPt + 0.5)) or ""
    lines[#lines + 1] = { (e.per > 0 and "Kostet je Punkt (ohne Lernen" or "Bringt je Punkt (ohne Lernen") .. nTxt .. ")", MS(-e.per) }
    lines[#lines + 1] = { "Je Punkt, Ergebnis an den Händler", e.perV and MS(-e.perV) or "?" }
    lines[#lines + 1] = { "Je Punkt, Ergebnis ins AH", e.perA and MS(-e.perA) or "kein AH-Preis" }
  else
    lines[#lines + 1] = "Keinen Preis für eine Mat (Vollscan im AH)."
  end
  if e.learn then
    lines[#lines + 1] = { "Noch nicht gelernt: " .. e.learn.text, e.learn.cost and M(e.learn.cost) or e.learn.short or "?" }
    for i, n in ipairs(e.learn.all or {}) do if i <= 6 then lines[#lines + 1] = "  " .. n end end
  end
  local p = ns.Skill.InPlan(e.char, e.spell)
  if p then lines[#lines + 1] = ("Auf der Einkaufsliste: %d×"):format(p[3]) end
  return { ItemName(e.id), lines }
end

SkillRows = function(out)
  local Sk = ns.Skill
  local char = Sk.Char()
  local prof = Sk.Prof(char)
  if not prof then
    out[#out + 1] = { kind = "note", text = "Noch keine Berufe gelesen: mit dem Char einloggen und einmal das Berufsfenster öffnen." }
    return
  end
  local rows, st = Sk.Rows(char, prof)
  for _, e in ipairs(rows) do
    -- (Daniel 16.11.2026: "zuerst in grün oder rot schreiben, ob das rezept bereits gelernt ist oder fehlt ... am ende geht es
    -- schnell unter") learned or missing leads the line
    local lead = e.learn and (RED .. "fehlt|r: " .. e.learn.text .. ", ") or (GRN .. "gelernt|r, ")
    local sub = lead .. ("|c%s%s|r %d %%"):format(Sk.HEX[e.color] or "ffffffff", Sk.WORD[e.color] or "?", floor(e.chance * 100 + 0.5))
    local p = Sk.InPlan(char, e.spell)
    if p then sub = sub .. (", |cff4fd16bauf der Liste (%d×)|r"):format(p[3]) end
    local learnCost = e.learn and e.learn.cost
    local it = Row(e.id, sub, { chance = floor(e.chance * 100 + 0.5) .. " %", crafts = e.crafts, per = e.perAll and MS(-e.perAll) or "",
      perv = e.perV and MS(-e.perV) or "", pera = e.perA and MS(-e.perA) or "",
      learn = e.learn and (learnCost and M(learnCost) or e.learn.short or "?") or "gelernt", cost = M(e.cost) }, e, SkillTip(e),
      { sv = { chance = e.chance, crafts = e.crafts, per = e.perAll and -e.perAll, perv = e.perV and -e.perV, pera = e.perA and -e.perA, learn = learnCost or (e.learn and 1e12 or 0), cost = e.cost } })
    it.active = Sk.sel and Sk.sel.char == char and Sk.sel.spell == e.spell or false
    out[#out + 1] = it
  end
  if #rows == 0 then out[#out + 1] = { kind = "note", text = "Kein Rezept bringt auf dieser Stufe noch Punkte (oder die Stufendaten fehlen)." } end
  -- (Runde 2, 11.11.2026, Bild Skillen bei 150/150: the note stood below 73 recipes) on top and yellow
  if st.capped then out[#out + 1] = { kind = "note", top = true, color = C.yellow, text = "Stufengrenze erreicht: erst beim Lehrer die nächste Stufe lernen, vorher bringt kein Rezept Punkte. \"bis grau\" zählt ohne Grenze." } end
  if st.noPrice > 0 then out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne Preis für eine Mat (Vollscan im AH füllt sie)."):format(st.noPrice) } end
  if st.noBands > 0 then out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne Skillstufen in den Daten."):format(st.noBands) } end
end

-- (Daniel 14.11.2026: "bei der Herstellungseiten fehlt mir ein suchfeld") the search box over the craft lists: the rows
-- whose result or one of whose mats has the text in its name (plain, any case)
local find = ""
local function Found(rows)
  if find == "" then return rows, 0 end
  local out = {}
  local function has(id)
    local name = id and ItemName(id)
    return type(name) == "string" and name:lower():find(find, 1, true) ~= nil
  end
  for _, v in ipairs(rows) do
    local hit = has(v.r.item)
    if not hit then for _, g in ipairs(v.r.reag or {}) do if has(g[1]) then hit = true break end end end
    if hit then out[#out + 1] = v end
  end
  return out, #rows - #out
end
function ns.SetFind(t) find = tostring(t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
local function FoundNote(out, hidden)
  if hidden > 0 then out[#out + 1] = { kind = "note", top = true, text = ("Suche \"%s\": %d Rezepte ausgeblendet."):format(find, hidden) } end
end

-- (Daniel 16.11.2026: "zuerst in grün oder rot schreiben, ob das rezept bereits gelernt ist oder fehlt") Berufe and
-- Entzaubern > Herstellen with all recipes
local function KnownLead(v)
  if v.knownBy and #v.knownBy > 0 then
    local names = {}
    for _, ch in ipairs(v.knownBy) do names[#names + 1] = ns.Skill.Short(ch) end
    return GRN .. "gelernt: " .. table.concat(names, ", ") .. "|r  "
  end
  return RED .. "fehlt|r  "
end

-- the rows of the list on screen
local function Rows()
  local out, B, Cr, DE = {}, ns.BuyState, ns.Crafts, ns.DE
  local function sel(e) return (B.entry == e and KIND[tab] == B.kind) or (Cr.sel and e and Cr.sel.r == e.r and Cr.sel.mode == e.mode) end
  if PROF_MODE[tab] then
    local mode, prof = PROF_MODE[tab], Cr.ViewProf()
    if not prof then out[1] = { kind = "note", text = "Keine Rezeptdaten." } return out end
    local rows, missing, st = Cr.ProfRowsSoon(prof, mode)
    if not rows then calcNote = true out[1] = { kind = "note", text = "Rechne die Rezepte ..." } return out end
    local hidden
    rows, hidden = Found(rows)
    FoundNote(out, hidden)
    for _, v in ipairs(rows) do
     out[#out + 1] = KeptRow(v, tab, function()
      local ptext, lacking = PartsText(v)
      -- (Daniel 16.11.2026: "zuerst in grün oder rot schreiben, ob das rezept bereits gelernt ist oder fehlt") first in the line
      local lead = KnownLead(v)
      local who = ""
      -- (Durchsicht 11.11.2026) Berufe counts the profession as complete: a step on the way this character cannot make is named
      -- (11.11.2026, Bild 134859: "Zwischenrezept fehlt dir: L..." cut off) short, the note on top explains the yellow
      if #lacking > 0 then who = YEL .. "dir fehlt: " .. table.concat(lacking, ", ") .. "|r" end
      local sub = lead .. CooldownLead(v) .. ptext .. (who ~= "" and ("  " .. who) or "")
      -- (Daniel 09.11.2026) what the recipe costs, only shown, not taken off the profit
      local rc, rcText = RecipeCost(v)
      -- (Daniel 14.11.2026, demand) for the AH the profit is the expected one where the demand is known
      local ahP, ahR = v.ahExpProfit or v.ahProfit, v.ahExpProfit and v.ahExpRoi or v.ahRoi
      local demText, demSort = DemCell(v)
      local run, gph = RunGain(v.run), RunGain(v.runH)
      local cells = { learn = v.r.learnMax and (v.r.learnMax .. "?") or v.r.learn or 0, rcost = rcText, time = Cr.Dur(v.time), cost = M(v.cost), vendor = M(v.vendor), profit = MS(mode == "ah" and ahP or v.profit),
        roi = Pct(mode == "ah" and ahR or v.roi), ah = mode == "ah" and M(v.ahNet) or MS(v.ahProfit), dem = demText, run = MS(run), gph = MS(gph) }
      return Row(v.id, sub, cells, v, function() return CraftTip(v) end, { sv = { learn = ns.Crafts.LearnGate(v.r), rcost = rc or 1e12, time = v.time or 1e9, cost = v.cost, vendor = v.vendor,
        profit = mode == "ah" and ahP or v.profit, roi = mode == "ah" and ahR or v.roi, ah = mode == "ah" and v.ahNet or v.ahProfit, dem = demSort, run = run or -1e12, gph = gph or -1e12 } })
     end)
      out[#out].active = sel(v)
    end
    if #rows > 0 then
      out[#out + 1] = { kind = "note", top = true, color = C.yellow, text = "Gerechnet, als wäre der Beruf voll gelernt: Zwischenschritte dieses Berufs gelten als selbst herstellbar. Vorn steht grün, wer ein Rezept kann, rot \"fehlt\", wenn es keiner deiner Chars kann; gelb, welcher Zwischenschritt dir fehlt." }
    end
    local scan = ns.Prices.Store() ~= nil
    if missing > 0 then
      out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne Preis für eine Mat (Preise: %s)."):format(missing, scan and "Scan" or (ns.Prices.TSMReady() and "TSM" or "keine Preise")) }
    end
    if st.below > 0 and not ns.db.craftAll then
      out[#out + 1] = { kind = "note", text = ("%d Rezepte unter dem Mindestgewinn (%s). \"Alle Rezepte\" zeigt sie."):format(st.below, ns.Money(ns.Opt("minProfit") or 0)) }
    end
    if (st.data or 0) > 0 then out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne Ergebnis oder Reagenzdaten (z. B. Verzauberungen)."):format(st.data) } end
    if mode == "ah" and st.noAH > 0 then out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne AH-Preis für das Ergebnis (nicht im Scan)."):format(st.noAH) } end
    return out
  end
  if CRAFT_MODE[tab] then
    local mode = CRAFT_MODE[tab]
    -- (Daniel 21.11.2026) Entzaubern > Herstellen: also every recipe of one or all professions, as in Berufe
    local view = tab == "demake" and Cr.DeView() or "mine"
    local rows, missing, st
    if view ~= "mine" then rows, missing, st = Cr.ProfRowsSoon(view, mode) else rows, missing, st = Cr.RowsSoon(mode) end
    if not rows then calcNote = true out[1] = { kind = "note", text = "Rechne die Rezepte ..." } return out end
    local hidden
    rows, hidden = Found(rows)
    FoundNote(out, hidden)
    for _, v in ipairs(rows) do
     out[#out + 1] = KeptRow(v, tab, function()
      local cells
      if mode == "de" then
        cells = { cost = M(v.cost), value = M(v.de), profit = MS(v.deProfit), roi = Pct(v.deRoi) }
        local lead = ""
        if v.view then
          lead = KnownLead(v) .. (view == "all" and (MUT .. Cr.ProfName(v.r.prof) .. "|r  ") or "")
        end
        return Row(v.id, lead .. CooldownLead(v) .. DE.Text(v.group), cells, v, function() return CraftTip(v, true) end,
          { sv = { cost = v.cost, value = v.de, profit = v.deProfit, roi = v.deRoi } })
      elseif mode == "ah" then
        local ahP, ahR = v.ahExpProfit or v.ahProfit, v.ahExpProfit and v.ahExpRoi or v.ahRoi
        local demText, demSort = DemCell(v)
        cells = { count = v.maxCraft, time = Cr.Dur(v.time), cost = M(v.cost), ah = M(v.ahNet), profit = MS(ahP), roi = Pct(ahR), vendor = M(v.vendor), dem = demText }
        return Row(v.id, CooldownLead(v) .. PartsText(v), cells, v, function() return CraftTip(v) end,
          { sv = { count = v.maxCraft, time = v.time or 1e9, cost = v.cost, ah = v.ahNet, profit = ahP, roi = ahR, vendor = v.vendor, dem = demSort } })
      else
        local run, gph = RunGain(v.run), RunGain(v.runH)
        cells = { count = v.maxCraft, time = Cr.Dur(v.time), cost = M(v.cost), vendor = M(v.vendor), profit = MS(v.profit), roi = Pct(v.roi),
          ah = MS(v.ahProfit), run = MS(run), gph = MS(gph) }
        return Row(v.id, CooldownLead(v) .. PartsText(v), cells, v, function() return CraftTip(v) end,
          { sv = { count = v.maxCraft, time = v.time or 1e9, cost = v.cost, vendor = v.vendor, profit = v.profit, roi = v.roi, ah = v.ahProfit, run = run or -1e12, gph = gph or -1e12 } })
      end
     end)
      out[#out].active = sel(v)
    end
    -- (Runde 2, 11.11.2026, Bild Entzaubern > Herstellen: five rows, all red, no word on it) a list of losses only says so
    local plus = false
    for _, v in ipairs(rows) do
      local p
      if mode == "de" then p = v.deProfit elseif mode == "ah" then p = v.ahExpProfit or v.ahProfit else p = v.profit end
      if p and p > 0 then plus = true break end
    end
    if #rows > 0 and not plus then
      out[#out + 1] = { kind = "note", top = true, color = C.yellow, text = (mode == "de" and "Kein Rezept lohnt gerade zum Entzaubern: alle %d mit Verlust."
        or "Kein Rezept bringt gerade Gewinn: alle %d mit Verlust."):format(#rows) }
    end
    -- (Daniel's screenshot 06.11.2026: an empty list with "Nichts über dem Mindestgewinn") the note says why rows are missing
    local scan = ns.Prices.Store() ~= nil
    local src = scan and "Scan" or (ns.Prices.TSMReady() and "TSM" or "keine Preise")
    if missing > 0 then
      out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne Preis für eine Mat (Preise: %s).%s"):format(missing, src,
        scan and "" or " Vollscan im AH füllt sie.") }
    end
    if st.below > 0 and not ns.db.craftAll then
      out[#out + 1] = { kind = "note", text = ("%d Rezepte unter dem Mindestgewinn (%s). \"Alle Rezepte\" zeigt sie."):format(st.below, ns.Money(ns.Opt("minProfit") or 0)) }
    end
    if (st.data or 0) > 0 then out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne Reagenzdaten: einmal das Berufsfenster öffnen."):format(st.data) } end
    if mode == "ah" and (st.noAH or 0) > 0 then out[#out + 1] = { kind = "note", text = ("%d Rezepte ohne AH-Preis für das Ergebnis (nicht im Scan)."):format(st.noAH) } end
    if mode == "de" and st.noDE > 0 then out[#out + 1] = { kind = "note", text = ("%d Rezepte machen nichts Entzauberbares."):format(st.noDE) } end
    if view ~= "mine" and #rows > 0 then
      out[#out + 1] = { kind = "note", top = true, color = C.yellow, text = "Gerechnet, als wäre der Beruf voll gelernt. Vorn steht grün, wer ein Rezept kann, rot \"fehlt\", wenn es keiner deiner Chars kann." }
    end
    if st.known == 0 and view == "mine" then out[#out + 1] = { kind = "note", text = "Noch keine Rezepte gelesen: einmal das Berufsfenster öffnen." } end
  elseif tab == "skill" then
    SkillRows(out)
  elseif IsShop(tab) then
    local v = Cr.sel
    local Sk = ns.Skill
    local lid = LISTKEY[tab]
    local entries = lid and ns.ShopLists.Entries(lid) or Cr.ShopEntries()
    if #entries == 0 then
      out[#out + 1] = { kind = "note", text = lid and "Die Liste ist leer: in einem Reiter (oder auf der Seite Verkaufen) Rechtsklick auf einen Gegenstand oder Writ, dann \"Auf Liste\". Rechtsklick auf den Chip der Liste: umbenennen oder löschen."
        or "Noch nichts auf der Liste: in \"Für Händler\", \"Für Auktionshaus\" oder im Reiter Berufe ein Rezept anklicken, in \"Skillen\" Rezepte auf die Liste setzen oder im Berufsfenster \"Track Recipe\" ankreuzen." }
      if W then W.shopDone = nil end
    else
      -- (Daniel 07.11.2026: "oben drüber dann was damit hergestellt wird", "Einkaufsliste als baum, dann reicht es ja oben
      -- ein X für das löschen") each recipe on top with its mats indented below, its X takes the whole branch off the list
      local SRC = { vendor = "beim Händler (Knopf Mats kaufen)", ah = "im AH", craft = "selbst herstellen", stock = "in den Taschen", mail = "gekauft" }
      local sumAH, sumVendor, noPrice, wayN, firstHead = 0, 0, 0, 0, nil
      local goneN = 0
      local favorCost, favorN = 0, 0
      local shop = Cr.ShoppingList(entries, true)
      -- (Daniel 24.11.2026, Fenstercheck b6 67 s: "nicht noch einen zweiten da unter ... könnte dann direkt daneben stehen")
      -- an item of an own list that is bought as it is (one row below its head, the item itself, not made): one row, the
      -- purchase row with the head's count field, X and right click (it.listHead)
      local mergedHead = {}
      for i, e in ipairs(shop) do
        local c, n = shop[i + 1], shop[i + 2]
        if e.head and e.en and e.en.list and e.en.r and e.en.r.listItem and c and not c.head and not c.alt
          and c.id == e.en.r.listItem and c.src ~= "craft" and (c.depth or 0) <= 1 and (not n or n.head) then
          mergedHead[c] = e
        end
      end
      local function ListSub(en)
        local how = en.fixed and ("fest %d kaufen, Taschen zählen nicht"):format(en.runs) or ("Vorrat %d halten, Taschen abgezogen"):format(en.runs)
        -- (Daniel 24.11.2026) the price alarm of the entry
        if en.alarm then how = how .. ", " .. (en.alarmOn and GRN or "") .. ("Wecker ab %s%s"):format(M(en.alarm), en.alarmOn and " erreicht|r" or "") end
        return how .. "  (Rechtsklick: ändern)"
      end
      local function ListRemove(en)
        return function() ns.ShopLists.Remove(en.list, en.kind, en.key) ns.Refresh() end
      end
      local function ListHeadEntry(en)
        return { head = true, planRow = true, char = en.char, spell = en.r.spell, prof = en.r.prof, id = en.r.item, runs = en.runs, r = en.r,
          listId = en.list, listKind = en.kind, listKey = en.key, fixed = en.fixed }
      end
      for i, e in ipairs(shop) do
        if e.head and shop[i + 1] and mergedHead[shop[i + 1]] == e then
          -- drawn with its purchase row below
        elseif e.head then
          local en = e.en
          local mode = en.chosen and v and v.mode or nil
          local known = Cr.IKnow(en.r.spell)
          -- (Durchsicht 11.11.2026, Bild Einkaufsliste: the profit stood in 150 characters of small print) the profit of the
          -- chosen count and per craft in the title, the limits ("lohnt bis", "AH hat nur für") in a line of their own below
          local where = en.chosen and (v and v.view and "Gewählt in Berufe" or "Gewählt in Herstellen")
            or en.tracked and "Verfolgt im Berufsfenster"
            or not en.favor and not en.writ and not en.list and ("Skillen: %s, %s"):format(Cr.ProfName(en.r.prof), Sk.Short(en.char)) or nil
          local sub = where and ("%s, %d× herstellen, ergibt %s je Mal"):format(where, en.runs, Cr.YieldText(en.r))
          -- (16.11.2026, "Auf Platz kürzen") the chosen count does not fit the bags: bought only for what fits
          if sub and en.want then sub = sub .. ", " .. RED .. ("gekürzt: Platz nur für %d von %d|r"):format(en.runs, en.want) end
          -- (Daniel 13.11.2026) a Favor crate: the crate and its bundle make a sealed crate for the turn-in
          if en.favor then
            local gain = ns.Favor.Gain(en.favor)
            sub = ("Favor-Kiste: %d× Kiste füllen%s"):format(en.runs, gain and (", %d Gunst je Kiste, zusammen %d"):format(gain, gain * en.runs) or "")
            -- (Daniel 22.11.2026: "was mir bei der anzahl die ich kaufe je gunst kostet") the purchase of these rows over the
            -- Favor they bring; what the bags hold costs nothing here, as in the sum below
            if gain and gain > 0 and e.cost then
              -- (Daniel 22.11.2026) less the money of each turn-in (5s)
              local net = math.max(0, e.cost - ns.Favor.Money(en.favor) * en.runs)
              sub = sub .. (", Einkauf je Gunst %s"):format(M(math.floor(net / (gain * en.runs) + 0.5)))
              favorCost, favorN = favorCost + net, favorN + gain * en.runs
            end
          end
          -- (Daniel 18.11.2026) a Craftsman's Writ: the writ item and its ware, handed in to the customer
          if en.writ then
            local Wr = ns.Writs
            local w
            for _, x in ipairs(ns.WRITS and ns.WRITS.list or {}) do if x[1] == en.writ then w = x end end
            local npc, uiMap = w and Wr.Customer(w)
            sub = ("Writ: Ware abgeben bei %s, %d Ruf"):format(npc and npc ~= "" and (npc .. ", " .. (Wr.MapName(uiMap) or "?")) or "dem Kunden auf der Karte", w and Wr.REP[w[5]] or 0)
          end
          if en.chosen and not known then sub = sub .. ", " .. YEL .. "Rezept nicht gelernt|r" end
          -- (Daniel 19.11.2026) an own list: a stock to hold or a fixed amount, per entry
          if en.list then sub = (en.writ and (sub .. ", ") or "") .. ListSub(en) end
          -- (Daniel 09.11.2026) how many crafts still pay with the mats bought cheapest first
          local be = not en.list and Cr.Breakeven(en.r, mode) or nil
          local tip, at, held, warn, way
          if be then
            local src = be.src == "live" and "live" or "Scan"
            -- (Daniel 10.11.2026: "wie viel Gewinn ich mit der Anzahl an crafts bekomme und je craft anstatt die Gesamtsumme
            -- aller möglichen crafts") the profit of the chosen count and per craft first; the best count stays in the tip
            at, held, way = Cr.ProfitAt(en.r, mode, en.runs, e)
            local bits, level = {}, 0
            if be.best <= 0 then bits[#bits + 1] = RED .. "lohnt nicht|r (" .. src .. ")" level = 2
            elseif en.runs <= be.best then bits[#bits + 1] = GRN .. ("lohnt bis ~%d|r (%s)"):format(be.best, src)
            else bits[#bits + 1] = YEL .. ("lohnt nur bis ~%d|r (%s)"):format(be.best, src) level = 1 end
            if at and at < 0 then level = 2 end
            if be.zero then bits[#bits + 1] = ("ab ~%d Verlust"):format(be.zero) end
            if be.short then
              bits[#bits + 1] = (be.short < en.runs and YEL or "") .. ("AH hat Mats nur für ~%d"):format(be.short) .. (be.short < en.runs and "|r" or "")
              if be.short < en.runs then level = math.max(level, 1) end
            end
            -- (Daniel 10.11.2026, Iron Grenade -1s29c in Herstellen, +28g here: "So lassen") cash: what the bags hold costs
            -- nothing here, Herstellen counts it at its price; the line says so
            if held then bits[#bits + 1] = "Mats aus den Taschen gratis gerechnet" end
            -- (11.11.2026, Bild 134857) the profit jumps once the mats are bought: they are paid, the line says so
            if way then bits[#bits + 1] = "gekaufte Mats (Briefkasten) sind schon bezahlt und gratis gerechnet" end
            -- (Daniel 12.11.2026: "hinweis wieviel man einkaufen kann wäre gut") the crafts the bags hold, bought to made
            local roomN, roomUnsure = Cr.RoomCrafts(en.r)
            if roomN then
              local tight = roomN < en.runs and not en.want
              -- (16.11.2026) a typed count above the room is bought ahead: the line says so
              bits[#bits + 1] = (tight and YEL or "") .. ("Platz für %s%d Crafts"):format(roomUnsure and "~" or "", roomN) .. (tight and ", mehr auf Vorrat (Briefkasten)" or "") .. (tight and "|r" or "")
              if tight then level = math.max(level, 1) end
            end
            local cd = Cr.CooldownText(en.r.spell)
            if cd then
              bits[#bits + 1] = YEL .. cd .. ": nur 1 je Abklingzeit|r"
              if en.runs > 1 then level = math.max(level, 1) end
            end
            warn = { kind = "note", text = "      " .. table.concat(bits, "  ·  "), warn = level == 2 or nil, color = level == 2 and C.red or C.muted }
            local lines = {
              { "Ein Craft bringt" .. (mode == "ah" and " (AH nach Gebühr)" or en.chosen and " (Händler)" or ""), M(be.worth) },
              { ("Gewinn bei %d Crafts"):format(en.runs), at and MS(at) or "?" },
              { "Gewinn je Craft (Schnitt)", at and MS(math.floor(at / en.runs + 0.5)) or "?" },
              { "Lohnt bis etwa", be.best > 0 and (tostring(be.best) .. " Crafts") or "nicht" },
              { "Gewinn dabei (höchstens)", MS(be.gain) },
            }
            if be.zero then lines[#lines + 1] = { "Ab da Verlust insgesamt", be.zero .. " Crafts" } end
            if be.short then lines[#lines + 1] = { "AH hat Mats nur für etwa", be.short .. " Crafts" } end
            if roomN then
              lines[#lines + 1] = { "Platz in den Taschen für", roomN .. " Crafts" }
              lines[#lines + 1] = ("%d freie Plätze; gerechnet mit allen Mats beim Kauf und %s Stück je Craft am Ende."):format(ns.FreeSlots(), Cr.YieldText(en.r))
              if roomUnsure then lines[#lines + 1] = "Stapelgröße noch unbekannt (geschätzt): " .. table.concat(roomUnsure, ", ") .. ". Einmal in die Taschen oder den Tooltip, dann lernt Profitdon sie." end
            end
            lines[#lines + 1] = "Mats günstigste zuerst gekauft, was in den Taschen liegt, kostet nichts."
            if held then lines[#lines + 1] = "Darum kann hier Gewinn stehen, wo Herstellen (alle Mats zum Marktpreis) Verlust zeigt." end
            lines[#lines + 1] = be.src == "live" and "Preise: aktuelle Angebote im AH (Live prüfen)." or "Preise: Stufen des letzten Vollscans, am AH mit \"Live prüfen\" genau."
            tip = { ns.ItemInfo(en.r.item) or "", lines }
          end
          local hit = Row(en.r.item, sub, { need = en.runs },
            { head = true, chosen = en.chosen, planRow = not en.chosen, char = en.char, spell = en.r.spell, prof = en.r.prof, id = en.r.item,
              runs = en.runs, r = en.r, be = be, at = at, known = known, favor = en.favor, writ = en.writ, tracked = en.tracked,
              listId = en.list, listKind = en.kind, listKey = en.key, fixed = en.fixed },
            tip, { sv = {}, removeTip = en.tracked and "Von der Einkaufsliste nehmen (der Haken im Berufsfenster geht aus)" or "Von der Einkaufsliste nehmen", onRemove = function()
              if en.list then ns.ShopLists.Remove(en.list, en.kind, en.key)
              elseif en.chosen then Cr.sel = nil elseif en.tracked then Cr.Untrack(en.r.spell) elseif en.favor then ns.Favor.Remove(en.favor) elseif en.writ then ns.Writs.Remove(en.writ) else Sk.Remove(en.char, en.r.spell) end
              ns.Refresh()
            end,
            -- (Daniel 08.11.2026: "bei der anzahl unter kaufen wollte ich ein beschreibbarer feld ... die mats drunter sollten
            -- sich dann dementsprechend anpassen") the count of crafts typed right in the row (Kit item.edit); since the
            -- Durchsicht 11.11.2026 the only place for it (it stood three times: above, in the row, in the bar)
            edit = { key = "need", value = en.runs, tip = en.list and (en.fixed and "Wie viele jedes Mal kaufen" or "Wie viele vorrätig halten") or "Wie oft herstellen: die Mats darunter rechnen mit", onCommit = function(item, n)
              ns.SetHeadRuns(item.entry, n)
              ns.Refresh()
            end } })
          if at then
            -- (Daniel 17.11.2026, Bild Seasoned Wolf Kabob: Berufe +1s 98 je Craft, hier +22 je Craft: "Gewinn widerspricht
            -- sich", "Herstellen nennt beides") the list counts one craft at the cheapest mats, this line the average over
            -- all crafts, the dearer offers included: the first craft beside the average when they differ
            local avg = math.floor(at / en.runs + 0.5)
            local first = en.runs > 1 and Cr.ProfitAt(en.r, mode, 1)
            local per = ("%s je Craft"):format(MS(avg))
            if first and first ~= avg then per = ("erster Craft %s, im Schnitt %s je Craft"):format(MS(first), MS(avg)) end
            hit.title = ("%s   %s%s %s|r %s(%s)|r"):format(hit.title, at >= 0 and GRN or RED, at >= 0 and "Gewinn" or "Verlust", MS(at), MUT, per)
            if first and first > avg and tip then
              table.insert(tip[2], 4, { "Erster Craft", MS(first) })
              table.insert(tip[2], 5, "Die ersten Crafts nutzen die billigsten Angebote, jeder weitere kauft teurer: darum weniger im Schnitt.")
            end
          end
          firstHead = firstHead or hit.entry
          local hs = W.headSel
          hit.active = hs and hs.spell == en.r.spell and hs.char == en.char and (hs.chosen or false) == (en.chosen or false) or false
          out[#out + 1] = hit
          if warn then out[#out + 1] = warn end
        else
          -- (Durchsicht 11.11.2026, Bild Einkaufsliste: Heavy Stone "Kaufen 200, 15g 58s" under a powder that lay in the bags)
          -- the other way of a mat that is already there is an offer, not a to-do: grey, no count, not in the sum
          local optional = e.alt and e.parent and e.parent.need == 0
          local target = e.forItem and ("%d× %s"):format(e.forRuns or 1, (ItemName(e.forItem))) or nil
          -- what a purchase of this row is for (the bar and the second click of a big purchase say it)
          if e.alt and e.forVia then
            e.purpose = optional and ("freiwillig: %s liegt schon in den Taschen"):format((ItemName(e.forVia)))
              or ("anderer Weg: %s selbst herstellen statt kaufen"):format((ItemName(e.forVia)))
          elseif e.forVia then
            e.purpose = ("für %s (selbst herstellen)%s"):format((ItemName(e.forVia)), target and (" für " .. target) or "")
          elseif target then e.purpose = "für " .. target end
          local srcText = SRC[e.src] or e.src
          -- (Daniel 24.11.2026: "icebreaker ist bei einer suche gar nicht im ah") the live check found no offer: the row
          -- says so, its old price is not part of the sum
          local gone = e.none and e.src == "ah" and not e.alt and (e.need or 0) > 0
          if gone then srcText = RED .. "gerade nicht im AH (live geprüft)|r" end
          if e.src == "craft" and e.via and e.via.spell and not Cr.IKnow(e.via.spell) then
            local who = Cr.WhoMakes(e.via.spell)
            if who then srcText = ("herstellen lassen (%s)"):format(Sk.Short(who)) end
          end
          local sub = (e.alt and "oder herstellen: " or "") .. srcText .. (e.crafts and (", %d× herstellen"):format(e.crafts) or "") .. (e.held > 0 and (", %d da"):format(e.held) or "") .. BankBit(e)
            .. (e.way and (", %d im Briefkasten"):format(e.way) or "")
          if e.way and not e.alt then wayN = wayN + 1 end
          if optional then sub = ("freiwillig (%s ist da): nur, wenn du mehr davon selbst herstellen willst"):format((ItemName(e.forVia))) end
          if e.altEach then
            local cheaper = e.unit and e.altEach < e.unit
            sub = sub .. (", hergestellt %s je Stück%s"):format(M(e.altEach),
              cheaper and (e.timeBuy and " " .. YEL .. "(billiger, kostet aber Zeit)|r" or " |cff4fd16b(billiger)|r") or "")
          end
          -- (Daniel 22.11.2026: "wäre es nicht besser ich kaufe die modulatoren und könnte in der zeit essen craften") bought
          -- because the time of making it is worth more: what making would save an hour against the best Gold/h
          if e.timeBuy and (e.timeBuy.sec or 0) > 0 and not optional then
            local g, h = Cr.GoldHour()
            local perH = math.floor(e.timeBuy.save / e.timeBuy.sec * 3600 + 0.5)
            sub = sub .. (", selbst herstellen spart nur %s/h, %s bringt %s/h"):format(M(perH),
              h and h.item and (ItemName(h.item)) or "Herstellen für den Händler", M(g or 0))
          end
          local it = Row(e.id, sub, { need = (not optional) and e.need or "", unit = gone and "" or M(e.unit), cost = (not gone and not optional and (e.need or 0) > 0) and M(e.cost) or "" }, e, nil,
            { indent = (e.depth or 0) * 14, sv = { need = e.need, unit = e.unit, cost = e.cost } })
          if optional then it.titleColor = C.quiet it.subColor = C.quiet it.cellColors = { unit = C.quiet } end
          it.active = B.entry and B.kind == "mats" and B.entry.id == e.id
          local mh = mergedHead[e]
          if mh then
            local en = mh.en
            it.listHead, it.indent = ListHeadEntry(en), 0
            it.sub = sub .. ((e.need or 0) ~= en.runs and (", %d kaufen"):format(e.need or 0) or "") .. ", " .. ListSub(en)
            it.removeTip, it.onRemove = "Von der Einkaufsliste nehmen", ListRemove(en)
            local head = it.listHead
            it.edit = { key = "need", value = en.runs, tip = en.fixed and "Wie viele jedes Mal kaufen" or "Wie viele vorrätig halten",
              onCommit = function(_, n) ns.SetHeadRuns(head, n) ns.Refresh() end }
          end
          out[#out + 1] = it
          if not e.alt and (e.need or 0) > 0 and e.src ~= "craft" then
            if gone then goneN = goneN + 1
            elseif not e.cost then noPrice = noPrice + 1
            elseif e.src == "vendor" then sumVendor = sumVendor + e.cost
            else sumAH = sumAH + e.cost end
          end
        end
      end
      -- (Durchsicht 11.11.2026) what the whole list costs against the gold there is
      local gold = ns.Num(ns.Call(GetMoney)) or 0
      local total = sumAH + sumVendor
      local short = total > gold
      -- (Runde 2, 11.11.2026, Bild 122448: "Einkauf: AH 2g" stayed after everything was bought) nothing left to buy: the line
      -- says so and where the bought mats are; W.shopDone lets the bar go on to the recipe (Draw)
      local way = wayN > 0 and ("  ·  %d Posten im Briefkasten abholen"):format(wayN) or ""
      -- (Daniel 24.11.2026, Fenstercheck b6 s0056: "Summenzeile dunkelrot und winzig") the sum is a row of its own in the
      -- row's type: the total in the title and in the column Summe, the parts below; red only when the gold is short.
      -- item.text keeps the whole line (sumLine: the tests and the bar read it)
      if total == 0 and noPrice == 0 and goneN == 0 then
        out[#out + 1] = { kind = "trow", sumLine = true, title = "Einkauf: nichts mehr zu kaufen", titleColor = C.green, markColor = C.green,
          sub = ("dein Gold %s%s"):format(ns.Money(gold), way), cells = {},
          text = ("Einkauf: nichts mehr zu kaufen%s  ·  dein Gold %s"):format(way, ns.Money(gold)) }
        W.shopDone = firstHead
      else
        local favorBit = favorN > 0 and ("  ·  je Gunst %s (%d Gunst)"):format(ns.Money(math.floor(favorCost / favorN + 0.5)), favorN) or ""
        local missBit = short and ("  ·  es fehlen " .. ns.Money(total - gold)) or ""
        local priceBit = (noPrice > 0 and ("  ·  %d Mats ohne Preis"):format(noPrice) or "")
          .. (goneN > 0 and ("  ·  %d gerade nicht im AH"):format(goneN) or "")
        out[#out + 1] = { kind = "trow", sumLine = true, markColor = short and C.red or nil,
          title = ("Einkauf gesamt %s%s"):format(ns.Money(total), short and ("   %sEs fehlen %s|r"):format(RED, ns.Money(total - gold)) or ""),
          titleColor = C.title,
          sub = ("AH %s  ·  Händler %s%s  ·  dein Gold %s%s%s"):format(ns.Money(sumAH), ns.Money(sumVendor), favorBit, ns.Money(gold), priceBit, way),
          cells = { cost = ns.Money(total) },
          text = ("Einkauf: AH %s  ·  Händler %s  ·  gesamt %s%s  ·  dein Gold %s%s%s%s"):format(ns.Money(sumAH), ns.Money(sumVendor), ns.Money(total),
            favorBit, ns.Money(gold), missBit, priceBit, way) }
        W.shopDone = nil
      end
    end
  elseif tab == "deah" or tab == "vendor" then
    local list = ns.lists[KIND[tab]] or {}
    local high, shown = 0, 0
    for _, e in ipairs(list) do
      if tab == "vendor" and not e.gone and ns.VendorStale(e) then e.gone = true end
      if tab == "deah" then ns.DELive(e) end
      if not e.gone then
        local it
        shown = shown + 1
        if tab == "deah" then
          local sub = DE.Text(e.group)
          -- (16.11.2026, "TSM-Wert als Prüfung") TSM sees the item's value far from ours: said in front, in yellow
          local tsm, off = DE.TSMCheck(e.id, e.group)
          if off then sub = YEL .. "TSM: " .. ns.Money(tsm) .. "|r  " .. sub end
          if e.tooHigh then sub = ("|cffe0524aVerzauberkunst %d nötig|r  "):format(e.skill) .. sub high = high + 1 end
          local per = (e.unitValue or 0) - (e.best or 0)
          -- (Durchsicht 15.11.2026) with the n cheapest offers, not n times the cheapest; lists kept from before have no
          -- prices: the old reckoning
          local sure, luck
          if type(e.prices) == "table" and e.prices[1] then
            if not e.sorted then table.sort(e.prices) e.sorted = true end
            sure = DE.SureAtOffers(e.group, e.prices)
            luck = not sure and per > 0
          else
            sure = DE.SureAt(e.group, e.best)
            -- the AH has fewer paying offers than it takes for the average: luck
            luck = sure and sure > (e.n or 0)
          end
          local head = { { "Gewinn je Stück im Schnitt (billigstes Angebot)", MS(per) } }
          if sure then
            head[#head + 1] = { "Sicher ab", ("%d Stück"):format(sure) }
            head[#head + 1] = "So viele der billigsten Angebote kaufen und entzaubern, dann liegt der Schnitt mit etwa 84 % im Plus. Ein einzelnes Stück kann weit darunter liegen."
          end
          if luck then head[#head + 1] = { ("Das AH hat nur %d lohnende Angebote: Glückssache."):format(e.n or 0), color = C.yellow } end
          head[#head + 1] = { ("Alle %d Angebote zusammen kosten"):format(e.n), M(e.cost) }
          head[#head + 1] = { "Gewinn, wenn alle gekauft (Schnitt)", MS(e.profit) }
          if e.how == "rule" then head[#head + 1] = "Gruppe aus der Regel (neues Forever-Item)." end
          it = Row(e.id, sub, { count = e.n, cost = M(e.best), value = M(e.unitValue), profit = MS(per),
              sure = sure and ((sure >= DE.SURE_MAX and ">" or "") .. sure) or (luck and "Glück" or "") }, e,
            DETip(e.id, e.group, head),
            { sv = { count = e.n, cost = e.best, value = e.unitValue, profit = per, sure = sure or DE.SURE_MAX + 1 } })
          if luck then it.cellColors = { sure = C.yellow } end
          it.luck = luck or nil
          -- (Runde 2, 11.11.2026, Bild Im AH: every row red "Verzauberkunst 150 nötig") what this character cannot
          -- disenchant yet: grey and below the rest
          if e.tooHigh then it.low = true it.titleColor = C.quiet it.cellColors = { count = C.quiet, cost = C.quiet, value = C.quiet, profit = C.quiet, sure = C.quiet } end
        else
          it = Row(e.id, (e.n > 1 and ("%d Auktionen"):format(e.n) or ""), { count = e.count, cost = M(e.cost), profit = MS(e.profit),
            roi = Pct(ns.Deals.ROI(e.profit, e.cost)) }, e, nil,
            { sv = { count = e.count, cost = e.cost, profit = e.profit, roi = ns.Deals.ROI(e.profit, e.cost) } })
        end
        it.active = sel(e)
        out[#out + 1] = it
      end
    end
    if tab == "deah" and shown > 0 then
      local my = Cr.MySkill and Cr.MySkill(333)
      if not my then
        out[#out + 1] = { kind = "note", top = true, color = C.yellow, text = "Dieser Char hat keine Verzauberkunst (oder ihr Berufsfenster war noch nie offen): kaufen lohnt nur für einen Verzauberer." }
      elseif high > 0 then
        out[#out + 1] = { kind = "note", top = true, color = C.yellow, text = ("%d von %d brauchen mehr Verzauberkunst, als du hast (%d): grau, unten."):format(high, shown, my) }
      end
    end
  elseif tab == "crates" then
    local F = ns.Favor
    local list, noPrice, noGain = F.Rows(), 0, 0
    ns.lists.crate = list
    local SRC = { vendor = "Händler", ah = "AH", craft = "selbst herstellen", stock = "Taschen" }
    for _, e in ipairs(list) do
      -- (Runde 2) a bundle made by oneself carries the yellow "(selbst)" of the recipe lists
      local sub = e.bid and (e.bsrc == "craft" and ("+ %d× %s %s(selbst)|r"):format(e.bn, ItemName(e.bid), YEL)
        or ("+ %d× %s (%s)"):format(e.bn, ItemName(e.bid), SRC[e.bsrc] or e.bsrc or "?")) or "Bündel ohne Preis"
      if not e.gain then sub = sub .. ", |cffe6b422Gunst noch unbekannt|r" noGain = noGain + 1
      elseif e.gainSrc == "gemessen" then sub = sub .. ", |cff4fd16bGunst gemessen|r" end
      if not e.crate then noPrice = noPrice + 1 end
      local lines = {
        { "Kiste im AH" .. (e.crateSrc and (" (" .. e.crateSrc .. ")") or ""), e.crate and M(e.crate) or "nicht im AH" },
        { "Billigstes Bündel", e.bundle and M(e.bundle) or "?" },
        { "Gunst beim Abgeben" .. (e.gainSrc and (" (" .. e.gainSrc .. ")") or ""), e.gain and tostring(e.gain) or "noch unbekannt" },
        { "Geld beim Abgeben (" .. (e.moneySrc or "50c je Gunst") .. ")", "-" .. M(e.money or 0) },
        { "Gold je Gunst", e.per and M(math.floor(e.per + 0.5)) or "?" },
      }
      for i = 1, #(ns.G.crates or {}) do
        local c = ns.G.crates[i]
        if c[1] == e.id then
          for k = 1, #c[3], 2 do
            local unit = ns.Crafts.ReagentUnit(c[3][k])
            lines[#lines + 1] = { ("  %d× %s"):format(c[3][k + 1], ItemName(c[3][k])), unit and M(unit * c[3][k + 1]) or "?" }
          end
        end
      end
      local total = e.crate and e.bundle and (e.crate + e.bundle) or nil
      local it = Row(e.id, sub, { gain = e.gain or "?", crate = e.crate and M(e.crate) or "", bundle = M(e.bundle), total = M(total),
        per = e.per and M(math.floor(e.per + 0.5)) or "" }, e, { ItemName(e.id), lines },
        { sv = { gain = e.gain, crate = e.crate, bundle = e.bundle, total = total, per = e.per } })
      it.active = sel(e)
      out[#out + 1] = it
    end
    local fav = F.Held()
    if fav then out[#out + 1] = { kind = "note", text = ("Deine Gunst: %d. Beim Abgeben misst Profitdon, wie viel eine Kiste bringt."):format(fav) } end
    if noPrice > 0 then out[#out + 1] = { kind = "note", text = ("%d Kisten ohne AH-Preis (Vollscan im AH füllt sie)."):format(noPrice) } end
    if noGain > 0 then out[#out + 1] = { kind = "note", text = ("%d Kisten mit Gunst noch unbekannt (Artisan): einmal abgeben, dann steht sie da."):format(noGain) } end
  elseif tab == "writs" then
    -- (Daniel 18.11.2026: Craftsman's Writs "möglichst effizient mit wenig laufwegen täglich ab stormwind ... möglichst
    -- günstig") per writ: writ item in the AH plus ware, less the Coin Pouch, per reputation; zones for the round on top
    local Wr = ns.Writs
    local list = Wr.Rows()
    ns.lists.writ = list
    local SRC = { vendor = "Händler", ah = "AH", craft = "selbst herstellen", stock = "Taschen" }
    local forge = Wr.ForgePer()
    -- (Daniel 18.11.2026: "zonen wie bei questdons liste", "mit + und - zum aufmachen", "dann braucht man die zone auch
    -- nicht mehr in klein darunter") a gold header per zone with + / -, cheapest reputation first (Wr.Rows order), the
    -- writs below; folded zones kept in ProfitdonDB.ui.writFold[key]; a column click sorts inside each zone (Sort)
    if not ns.db.writSortV2 then
      ns.db.writSortV2 = true
      if ns.db.ui and ns.db.ui.sort then ns.db.ui.sort.writs = nil end
    end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.writFold = type(ns.db.ui.writFold) == "table" and ns.db.ui.writFold or {}
    local fold = ns.db.ui.writFold
    -- (Daniel 18.11.2026: "1x kalimdor und 1x easten kingdoms zum aufklappen und zuklappen. drunter dann die einzelnen
    -- zonen (vielleicht noch levelbereich der zone in () dahinter") continents on top, zones indented below with their
    -- level range (Data/Writs.lua zones, ForeverDB), then unknown customers and today's writs
    local ZD = ns.WRITS and ns.WRITS.zones or {}
    local CONT = { c0 = "Östliche Königreiche", c1 = "Kalimdor", cx = "Andere Gebiete", none = "Kunde noch unbekannt", done = "Heute abgegeben" }
    local function Top(e)
      if e.done then return "done" end
      if not e.uiMap then return "none" end
      local z = ZD[e.uiMap]
      return z and ("c" .. z[1]) or "cx"
    end
    local buckets, sums = {}, {}
    local function Add(k, e)
      local s = sums[k]
      if not s then s = { n = 0, rep = 0, net = 0, priced = 0 } sums[k] = s end
      s.n = s.n + 1
      if e.per and not e.done then s.rep, s.net, s.priced = s.rep + e.rep, s.net + e.net, s.priced + 1 end
    end
    for _, e in ipairs(list) do
      local t = Top(e)
      buckets[t] = buckets[t] or {}
      table.insert(buckets[t], e)
      Add(t, e)
      if t:sub(1, 1) == "c" then Add("z" .. e.uiMap, e) end
    end
    local function Right(s) return s.priced > 0 and ("%d Ruf, %s"):format(s.rep, M(math.floor(s.net + 0.5))) or nil end
    local function Head(k, text, indent)
      local s = sums[k]
      out[#out + 1] = { kind = "group", text = text, count = ("%d Writs"):format(s.n), right = Right(s), collapsed = fold[k] and true or false,
        foldKey = k, plainCase = true, indent = indent }
    end
    local unknown, noPrice = 0, 0
    local function EmitRow(e)

      local coords = e.x and e.x > 0 and (" (%.0f, %.0f)"):format(e.x, e.y or 0) or ""
      local from = e.learned and (" " .. GRN .. "gelernt|r") or e.origin == "d" and (" " .. MUT .. "(laut Beta, ungeprüft)|r") or ""
      local who = e.npc and e.npc ~= "" and (e.npc .. coords .. from)
        or e.uiMap and (MUT .. "Kunde im Gebiet unbekannt|r" .. from)
        or (YEL .. "Kunde noch unbekannt|r")
      if not e.uiMap and e.npc then who = who .. " " .. MUT .. "(aus dem Angebot, Ort unbekannt)|r" end
      local sub = ("%s, %s"):format(Wr.RANK[e.rank], who)
      if e.done and e.zone then sub = sub .. ", " .. e.zone end
      if e.held > 0 then sub = sub .. ", " .. GRN .. ("%d in den Taschen|r"):format(e.held) end
      local lines = {
        { "Writ im AH" .. (e.writSrc and (" (" .. e.writSrc .. ")") or ""), e.writ and M(e.writ) or "nicht im AH" },
        { ("Ware: %d× %s (%s)"):format(e.n, ItemName(e.ware), SRC[e.wareSrc] or e.wareSrc or "?"), e.wareCost and M(e.wareCost) or "?" },
        { ("Coin Pouch (%s)"):format(e.pouchSrc or "?"), e.pouch and ("-" .. M(e.pouch)) or "?" },
        { "Ruf", tostring(e.rep) },
        { "Gold je Ruf", e.per and M(math.floor(e.per + 0.5)) or "?" },
      }
      if e.held > 0 then lines[#lines + 1] = { "Writ liegt in den Taschen: kostet nichts mehr", "" } end
      lines[#lines + 1] = { "Kunde laut", e.learned and "Abgabe bei dir" or Wr.ORIGIN[e.origin or ""] or e.origin or "unbekannt" }
      -- (Daniel 18.11.2026) the offer text of a right click on the writ, also when declined
      local offer = type(ns.db.writText) == "table" and ns.db.writText[e.quest]
      if type(offer) == "table" and offer.text then lines[#lines + 1] = { "Angebot: " .. offer.text:gsub("%s+", " "):sub(1, 220), "" } end
      local it = Row(e.id, sub, { rep = e.rep, writ = e.held > 0 and "da" or M(e.writ), ware = M(e.wareCost), net = M(e.net and math.floor(e.net + 0.5)),
        per = e.per and M(math.floor(e.per + 0.5)) or "" }, e, { ItemName(e.id), lines },
        { sv = { rep = e.rep, writ = e.writ, ware = e.wareCost, net = e.net, per = e.per } })
      it.active = sel(e)
      if e.done then it.done = true end
      out[#out + 1] = it
    end
    for _, t in ipairs({ "c0", "c1", "cx", "none", "done" }) do
      local b = buckets[t]
      if b then
        Head(t, CONT[t], nil)
        local zoneKey
        for _, e in ipairs(b) do
          if not e.uiMap then unknown = unknown + 1 end
          if not e.per then noPrice = noPrice + 1 end
          if not fold[t] then
            if t:sub(1, 1) == "c" then
              local zk = "z" .. e.uiMap
              if zk ~= zoneKey then
                zoneKey = zk
                local z = ZD[e.uiMap]
                Head(zk, (e.zone or "?") .. (z and (" (%d-%d)"):format(z[2], z[3]) or ""), 16)
              end
              if not fold[zk] then EmitRow(e) end
            else
              EmitRow(e)
            end
          end
        end
      end
    end
    if forge then
      out[#out + 1] = { kind = "note", text = ("Zum Vergleich Kiste fälschen (ab Freundlich, Forged Delivery Receipt für %d Gunst, %d Ruf): %s je Ruf."):format(Wr.FORGE_FAVOR, Wr.FORGE_REP, M(math.floor(forge + 0.5))) }
    end
    out[#out + 1] = { kind = "note", text = "Jeder Writ geht einmal am Tag. Coin Pouch geschätzt (Journeyman 12s, Expert 36s, Artisan 74s)." }
    if unknown > 0 then out[#out + 1] = { kind = "note", text = ("%d Writs mit unbekanntem Kunden: das Spiel zeigt ihn auf der Karte, beim Abgeben merkt Profitdon ihn sich."):format(unknown) } end
    if noPrice > 0 then out[#out + 1] = { kind = "note", text = ("%d Writs ohne Preis (Vollscan im AH füllt sie)."):format(noPrice) } end
  elseif tab == "debag" then
    local list, kept, vend = DE.BagList()
    for _, e in ipairs(list) do out[#out + 1] = Row(e.id, DE.Text(e.group), { value = M(e.value) }, nil, DETip(e.id, e.group), { sv = { value = e.value } }) end
    if kept > 0 then out[#out + 1] = { kind = "note", text = ("%d Gegenstände bleiben liegen: im AH nach Gebühr mehr wert als die Mats (Reiter Verkaufen)."):format(kept) } end
    if (vend or 0) > 0 then out[#out + 1] = { kind = "note", text = ("%d Gegenstände bleiben liegen: der Händler zahlt mehr als die Mats wert sind."):format(vend) } end
  elseif tab == "sell" then
    for _, e in ipairs(ns.SellList()) do
      local sub = e.unit and "billigstes Angebot im letzten Scan" or "kein Scanpreis: Klick sucht"
      if e.gear then sub = "Ausrüstung, AH mehr als Entzaubern (" .. M(e.deValue) .. "): Klick sucht genau diese Variante" end
      local it = Row(e.id, sub,
        { count = e.count, unit = M(e.unit), ret = M(e.ret), profit = MS(e.profit) }, e, nil,
        { sv = { count = e.count, unit = e.unit, ret = e.ret, profit = e.profit } })
      local linkName = e.gear and type(e.link) == "string" and e.link:match("%[(.-)%]")
      if linkName and linkName ~= "" then it.title = linkName end
      it.active = sel(e)
      out[#out + 1] = it
    end
  end
  return out
end

-- (Daniel 06.11.2026: "spalten auch immer sortierbar machen. also das man nach roi, oder so sortieren kann") a click on a
-- column head sorts the list by it (high first), a second click turns it round; kept per list in ProfitdonDB.ui.sort.
-- Notes stay below the rows, rows without a value at the end; the shopping list keeps made reagents under their parent.
-- (Runde 2, 11.11.2026) without a click: APPLY_SORT sorts a list itself (Entzaubern im AH by profit, it came by mat value);
-- SHOW_SORT names the order a list comes in, the head shows its arrow when the rows really are in that order
-- (Daniel 18.11.2026) the vendor lists by the gain of a run
local APPLY_SORT = { deah = { key = "profit" }, craft = { key = "run" }, pvendor = { key = "run" } }
local SHOW_SORT = { craft = { key = "profit" }, ahcraft = { key = "profit" }, pvendor = { key = "profit" }, pah = { key = "profit" }, demake = { key = "profit" },
  vendor = { key = "profit" }, skill = { key = "per" }, crates = { key = "per", asc = true } }
local function SortState()
  ns.db.ui = ns.db.ui or {}
  ns.db.ui.sort = ns.db.ui.sort or {}
  return ns.db.ui.sort[tab] or APPLY_SORT[tab]
end
-- the order on screen when nothing was clicked: the list's own order, if the rows are in it
local function ShownSort(items)
  local s = SortState()
  if s or IsShop(tab) then return not IsShop(tab) and s or nil end
  local d = SHOW_SORT[tab]
  if not d then return nil end
  local last, n = nil, 0
  for _, it in ipairs(items or {}) do
    local x = it.kind == "trow" and it.sv and it.sv[d.key]
    if x then
      if last and ((d.asc and x < last) or (not d.asc and x > last)) then return nil end
      last, n = x, n + 1
    end
  end
  return n > 1 and d or nil
end
function ns.SortBy(key)
  ns.db.ui = ns.db.ui or {}
  ns.db.ui.sort = ns.db.ui.sort or {}
  local cur = ns.db.ui.sort[tab] or APPLY_SORT[tab] or (W and W.shownSort)
  local s
  if cur and cur.key == key then s = { key = key, asc = not cur.asc } else s = { key = key, asc = key == "title" } end
  ns.db.ui.sort[tab] = s
  return s
end
local function Sort(items)
  local s = SortState()
  if IsShop(tab) then return items end
  local rows, notes, tops = {}, {}, {}
  for i, it in ipairs(items) do
    if it.kind == "trow" then it._i = i rows[#rows + 1] = it elseif it.top then tops[#tops + 1] = it else notes[#notes + 1] = it end
  end
  -- (Durchsicht 11.11.2026) a note marked top stays above the rows (what the whole list assumes)
  -- (Runde 2) a row marked low (nothing this character can do now) goes below the others
  -- (18.11.2026) a list with group headers (writs by zone) keeps its own order without a column click
  if not s then
    for _, it in ipairs(items) do if it.kind == "group" then return items end end
    for _, r in ipairs(rows) do if not r.low then tops[#tops + 1] = r end end
    for _, r in ipairs(rows) do if r.low then tops[#tops + 1] = r end end
    for _, n in ipairs(notes) do tops[#tops + 1] = n end
    return tops
  end
  local function Less(a, b)
    local x, y
    if (a.low or false) ~= (b.low or false) then return not a.low end
    if s.key == "title" then x, y = a.title or "", b.title or ""
    else x, y = a.sv and a.sv[s.key], b.sv and b.sv[s.key] end
    if x == nil and y ~= nil then return false end
    if y == nil and x ~= nil then return true end
    if x ~= nil and x ~= y then if s.asc then return x < y end return x > y end
    return a._i < b._i
  end
  -- (Daniel 18.11.2026, writs by zone) a list with group headers: the rows are sorted inside each group, the headers
  -- stay where they are
  local grouped = false
  for _, it in ipairs(items) do if it.kind == "group" then grouped = true break end end
  if grouped then
    local outL, seg, tail = {}, {}, {}
    local function Flush() table.sort(seg, Less) for _, r in ipairs(seg) do outL[#outL + 1] = r end seg = {} end
    for _, it in ipairs(items) do
      if it.kind == "trow" then seg[#seg + 1] = it
      elseif it.kind == "group" then Flush() outL[#outL + 1] = it
      elseif it.top then outL[#outL + 1] = it
      else tail[#tail + 1] = it end
    end
    Flush()
    for _, n in ipairs(tail) do outL[#outL + 1] = n end
    return outL
  end
  table.sort(rows, Less)
  for _, r in ipairs(rows) do tops[#tops + 1] = r end
  for _, n in ipairs(notes) do tops[#tops + 1] = n end
  return tops
end
-- (Daniel 11.11.2026: "besseres optisches Signal, ob Kauf durchgegangen ist oder nicht") the row of an item just bought:
-- a green, red or yellow bar on its left and the outcome in front of its second line, for ns.SIGNAL_SEC seconds
local SIGNAL_COLOR = { ok = "green", fail = "red", unclear = "yellow", sent = "yellow" }
local function Signals(items)
  if not (KIND[tab] and tab ~= "sell" and ns.BuySignal) then return items end
  for _, it in ipairs(items) do
    local e = it.entry
    if it.kind == "trow" and e and not e.head and e.id then
      local st, text, hex = ns.BuySignal(e.id)
      if st then
        it.markColor = C[SIGNAL_COLOR[st]]
        it.sub = ("|c%s%s|r%s"):format(hex, text, (it.sub and it.sub ~= "") and ("  ·  " .. it.sub) or "")
        it.subColor = nil
      end
    end
  end
  return items
end
ns.WindowRows = function() return Sort(Signals(Rows())) end

-- the rows of a list in the order on screen (sorted): "next row" after a gone offer follows what Daniel sees
function ns.VisibleList(kind)
  if W and W:IsShown() and KIND[tab] == kind and W.items then
    local out = {}
    -- the recipe rows of the shopping list are not bought
    for _, it in ipairs(W.items) do if it.entry and not it.entry.head then out[#out + 1] = it.entry end end
    return out
  end
  return ns.lists[kind] or {}
end

function ns.SelectFirst()
  if not W or not W:IsShown() then return end
  for _, it in ipairs(W.items or {}) do
    if it.entry and KIND[tab] and not it.entry.gone and not it.entry.head then ns.Select(it.entry, KIND[tab]) return end
  end
end

---------------------------------------------------------------------------
-- The action bar
---------------------------------------------------------------------------
local Draw
local Page, PAGES -- (24.11.2026) the window's own pages, built when first wanted (BuildWith)
-- the chosen row of Skillen (rows are built anew on every draw)
local function SkillSel()
  local s = ns.Skill.sel
  if not (s and W and W.items) then return nil end
  for _, it in ipairs(W.items) do
    local e = it.entry
    if e and e.spell == s.spell and e.char == s.char and not e.planRow then return e end
  end
end
-- (Daniel 08.11.2026, Bild der Einkaufsliste: "wenn ich da noch ne anzahl einstellen könnte wie viele ich bauen will und
-- dementsprechend sich die zahlen der mats dann anpassen") a recipe row of the shopping list is selected with a click, the
-- Anzahl field of the bar sets how many times it is crafted (chosen recipe: ProfitdonDB.craftRuns, Skillen: the plan)
local function HeadSel()
  local s = W and W.headSel
  if not (s and IsShop(tab) and W.items) then return nil end
  for _, it in ipairs(W.items) do
    local e = it.entry
    if e and e.head and e.spell == s.spell and e.char == s.char and (e.chosen or false) == (s.chosen or false) then return e end
  end
end
local function SetHeadRuns(e, n)
  n = tonumber(n)
  if not (e and n and n >= 1) then return end
  n = floor(n)
  if e.listId then
    ns.ShopLists.SetN(e.listId, e.listKind, e.listKey, n)
  elseif e.chosen then
    if ns.Crafts.sel then ns.Crafts.SetRuns(ns.Crafts.sel, n) end
  elseif e.tracked then
    ns.Crafts.SetTrackRuns(e.spell, n)
  elseif e.favor then
    ns.Favor.Add(e.favor, n)
  elseif e.writ then
    ns.Writs.Add(e.writ, n)
  else
    ns.Skill.Add(e.char, e.spell, n)
  end
end
ns.SetHeadRuns = SetHeadRuns -- (tests)

-- (11.11.2026, Bilder 134859 und 134925: the bar showed Heavy Dynamite, chosen in Für Händler, under Leatherworking and
-- under Entzaubern > Herstellen, "entzaubert ." without a value) the chosen recipe counts only in a list that shows it
local function CraftSel()
  local v = ns.Crafts.sel
  if not (v and W and W.items) then return nil end
  for _, it in ipairs(W.items) do if it.kind == "trow" and it.active and it.entry and it.entry.r == v.r then return v end end
  return nil
end
ns.WindowCraftSel = CraftSel -- (tests)

-- (Daniel 15.11.2026: "Alle herstellen aus dem Hauptfenster raus") crafting is done in the Herstellfenster beside the
-- profession window (CraftWin.lua); the bar here only leads to the shopping list
local function Primary()
  local B, Cr = ns.BuyState, ns.Crafts
  local h = HeadSel()
  if h then
    if h.chosen then
      -- (Durchsicht 11.11.2026) chosen in Berufe and not learned: nothing to craft
      if not h.known then return { text = "Rezept nicht gelernt", disabled = true } end
      return nil
    end
    -- (13.11.2026) a Favor crate: back to the crates
    if h.tracked then return nil end -- (15.11.2026) tracked in the profession window: made in the Herstellfenster
    if h.favor then return { text = "Favor-Kisten öffnen", onClick = function() W.headSel = nil ns.SetTab("crates") end } end
    if h.writ then return { text = "Writs öffnen", onClick = function() W.headSel = nil ns.SetTab("writs") end } end
    return { text = "In Skillen öffnen", onClick = function()
      local Sk = ns.Skill
      Sk.SetChar(h.char) Sk.SetProf(h.char, h.prof)
      Sk.sel = { char = h.char, spell = h.spell }
      W.headSel = nil
      ns.SetTab("skill")
    end }
  end
  if tab == "skill" then
    local e, Sk = SkillSel(), ns.Skill
    if not e then return nil end
    local shop = { text = "Einkaufsliste", onClick = function() ns.SetTab("shop") end }
    if Sk.InPlan(e.char, e.spell) then
      return { text = "Von der Liste nehmen", onClick = function() Sk.Remove(e.char, e.spell) Draw() end }, shop
    end
    return { text = "Auf die Einkaufsliste", kind = "primary", onClick = function()
      Sk.Add(e.char, e.spell, W.skillRuns or max(1, e.crafts))
      Draw()
    end }, shop
  end
  if PROF_MODE[tab] then
    if not CraftSel() then return nil end
    return { text = "Einkaufsliste", kind = "primary", onClick = function() ns.SetTab("shop") end }
  end
  if CRAFT_MODE[tab] then
    local v = CraftSel()
    if not v then return nil end
    return { text = "Einkaufsliste", kind = "primary", onClick = function() ns.SetTab("shop") end }
  end
  if KIND[tab] then
    local p = B.plan
    local label = tab == "sell" and "Einstellen" or "Kaufen"
    if p and p.commodity and not p.post then label = ("Kaufen: %d für %s (Schnitt %s)"):format(p.qty, M(p.total), M(floor(p.avg + 0.5)))
    elseif p and p.post then label = ("Einstellen: %d zu %s"):format(p.qty, M(p.unit))
    elseif p then label = "Kaufen: " .. M(p.price) end
    local buy = { text = label, kind = "primary", disabled = not (p and B.state == "ready"), onClick = function() ns.BuyNow() end }
    -- (Daniel 13.11.2026: "auch auf die einkaufsliste zu packen? also einmal die crate dann die mats dazu") the chosen crate
    -- goes on the shopping list with its bundle
    if tab == "crates" and B.entry and B.kind == "crate" then
      local F, id = ns.Favor, B.entry.id
      if F.InPlan(id) then
        return buy, { text = "Von der Einkaufsliste nehmen", onClick = function() F.Remove(id) Draw() end }
      end
      return buy, { text = "Auf die Einkaufsliste", onClick = function() F.Add(id, B.want or 1) ns.SetTab("shop") end }
    end
    -- (Daniel 18.11.2026) the chosen writ goes on the shopping list with its ware
    if tab == "writs" and B.entry and B.kind == "writ" then
      local Wr, q = ns.Writs, B.entry.quest
      if Wr.InPlan(q) then
        return buy, { text = "Von der Einkaufsliste nehmen", onClick = function() Wr.Remove(q) Draw() end }
      end
      return buy, { text = "Auf die Einkaufsliste", onClick = function() Wr.Add(q, 1) ns.SetTab("shop") end }
    end
    return buy
  end
end

-- (Fenstercheck 24.11.2026, Bild b6 s0056: the text of an own list ended in "Se...") a long text of the bar in two lines:
-- split after a ". ", ": " or "; " where the longer of the two lines is shortest (the sub line below the title)
function ns.BarText(text)
  text = tostring(text or "")
  if #text <= 130 then return text, nil end
  local best, bestLen
  for pos in text:gmatch("()[%.:;] ") do
    local len = math.max(pos, #text - pos - 1)
    if pos > 20 and (not best or len < bestLen) then best, bestLen = pos, len end
  end
  if not best then return text, nil end
  return text:sub(1, best), (text:sub(best + 2):gsub("^%s+", ""))
end

local function FillBar()
  local B, Cr = ns.BuyState, ns.Crafts
  local id, sub
  local h = HeadSel()
  if h then
    id = h.id
    -- (Durchsicht 11.11.2026, Bild Einkaufsliste: "Alle herstellen (0)" grey without a reason, "(60)" beside 200 chosen)
    -- the bar says how far the mats in the bags go and what is missing
    local can, miss = Cr.Missing(h.r, h.runs or 1)
    local runs = h.runs or 1
    if h.listId and h.listKind == "item" then
      local have = ns.Owned()[h.id] or 0
      sub = W.msg or (h.fixed and ("Jedes Mal %d kaufen, %d in den Taschen."):format(runs, have) or ("Vorrat %d, %d in den Taschen."):format(runs, have))
    else
    sub = W.msg or (miss and ("Mats für %d von %d da. Fehlt: %s"):format(math.min(can, runs), runs, miss)
      or ("Alle Mats für %d× da. Herstellen: Berufsfenster öffnen."):format(runs))
    -- (Runde 2) bought mats lie in the mailbox, not in the bags
    if not W.msg and miss and next(ns.OnWay()) then sub = sub .. "  " .. YEL .. "Gekauftes erst aus dem Briefkasten holen.|r" end
    end
    if not W.msg and h.chosen and Cr.sel then
      local n = Cr.MaxCraft(Cr.sel)
      if n < math.min(can, runs) then sub = sub .. (" Platz in den Taschen nur für %d."):format(n) end
    end
  elseif tab == "skill" then
    local e, Sk = SkillSel(), ns.Skill
    if e then
      id = e.id
      sub = (e.perAll and ("Je Punkt %s, "):format(MS(-e.perAll)) or "") .. ("%d Crafts bis grau (%d Punkte)"):format(e.crafts, e.pts)
        .. (e.learn and (", lernen: " .. (e.learn.cost and M(e.learn.cost) or e.learn.short or "?")) or "")
    else
      local char = Sk.Char()
      local prof = Sk.Prof(char)
      local rank, cap, t = Sk.Rank(char, prof)
      local title = prof and ("%s %d/%d, %s"):format(ns.Crafts.ProfName(prof), rank or 0, cap or 0, Sk.Short(char)) or TABS.skill[2]
      W.bar:SetData({ title = title, sub = t and ("gelesen " .. date("%d.%m. %H:%M", t)) or nil, titleColor = C.muted })
      W.bar:SetActions({})
      W.qty:Hide()
      return
    end
  elseif PROF_MODE[tab] then
    local v = CraftSel()
    if v then
      id = v.id
      local names = {}
      for _, ch in ipairs(v.knownBy or {}) do names[#names + 1] = ns.Skill.Short(ch) end
      sub = ("Mats %s, %s, ab Stufe %s, %s"):format(M(v.cost), tab == "pah" and ("AH netto " .. M(v.ahNet)) or ("Händler " .. M(v.vendor)),
        v.r.learnMax and ("? (spätestens " .. v.r.learnMax .. ")") or tostring(v.r.learn or 0), #names > 0 and ("gelernt: " .. table.concat(names, ", ")) or ("lernen: " .. ns.Skill.Learn(v.r.spell).text))
    end
  elseif CRAFT_MODE[tab] then
    local v = CraftSel()
    if v then
      id = v.id
      sub = W.msg or ("Kosten %s, %s"):format(M(v.cost), tab == "demake" and ("entzaubert " .. M(v.de))
        or tab == "ahcraft" and ("AH netto " .. M(v.ahNet)) or ("Händler " .. M(v.vendor)))
      if not W.msg then
        -- (Durchsicht 11.11.2026) a loss, a cooldown and why nothing can be made now stand in the bar
        if (v.show or 0) < 0 then sub = RED .. "Verlust " .. MS(v.show) .. " je Herstellung|r, " .. sub end
        local cd = Cr.CooldownText(v.r.spell)
        if cd then sub = sub .. ", " .. YEL .. cd .. "|r" end
        if Cr.MaxCraft(v) == 0 then
          local _, miss = Cr.Missing(v.r, 1)
          sub = sub .. (miss and (". Fehlt für eine Herstellung: " .. miss) or ". Kein Platz in den Taschen.")
        end
      end
    end
  elseif KIND[tab] and B.entry and B.kind == KIND[tab] then
    id = B.entry.id
    sub = B.msg or (B.state == "searching" and "Suche..." or "")
    if B.plan and not B.msg then
      local p = B.plan
      sub = p.post and ("nach Gebühr %s"):format(M(p.ret)) or (p.profit and ("Gewinn " .. MS(p.profit)) or "")
      if p.commodity and not p.post and p.avg then
        sub = ("Schnitt %s je Stück%s"):format(M(floor(p.avg + 0.5)), p.top and p.top > p.avg + 0.5 and (", teuerstes " .. M(p.top)) or "")
          .. (p.short == "ah" and (", nur %d im AH"):format(p.qty) or p.short == "Gold" and ", mehr Gold fehlt" or p.short == "cap" and ", Höchstbetrag je Klick" or "")
          .. (p.profit and (", Gewinn " .. MS(p.profit)) or "")
      end
    end
  end
  if not id then
    local t, s2 = ns.BarText(TABS[tab] and TABS[tab][2] or "")
    W.bar:SetData({ title = t, sub = s2, titleColor = C.muted })
    W.bar:SetActions({})
    return
  end
  local name, q = ItemName(id)
  local title = name
  if KIND[tab] and not h and B.entry and B.kind == KIND[tab] then
    -- (Durchsicht 11.11.2026, Gold Core) what the purchase is for, beside the name
    if B.entry.purpose then title = name .. "  " .. MUT .. B.entry.purpose .. "|r" end
    -- (Daniel 11.11.2026) the outcome of the last purchase of this item stays in front for a while, in colour
    local st, text, hex = ns.BuySignal(id)
    if st and not B.armed then sub = ("|c%s%s|r%s"):format(hex, text, (sub and sub ~= "") and ("  ·  " .. sub) or "")
    elseif not B.armed and ns.BoughtText and ns.BoughtText(id) then
      -- (Daniel 20.11.2026) after the signal the sum bought since the AH opened stays
      sub = ("|cff4fd16b%s|r%s"):format(ns.BoughtText(id), (sub and sub ~= "") and ("  ·  " .. sub) or "")
    end
  end
  W.bar:SetData({ icon = ns.Icon(id), itemID = id, quality = q, title = title, sub = sub })
  local a, b = Primary()
  W.bar:SetActions({ a, b })
  -- (Daniel 06.11.2026) the amount to buy, left of the buy button; empty = what pays (shopping list: what is missing)
  if tab == "skill" then
    -- (Daniel 07.11.2026) how many crafts go on the list: empty = until grey
    local e = SkillSel()
    W.qty:SetShown(e and W.bar.nActions > 0 and true or false)
    if e and not W.qty._focus and W.qtySkill ~= e.spell then
      local p = ns.Skill.InPlan(e.char, e.spell)
      W.skillRuns = p and p[3] or nil
      W.qty:SetValue(W.skillRuns or "")
    end
    W.qtySkill = e and e.spell
    W.bar:Layout(W.bar._w or W.bar:GetWidth())
    return
  end
  W.qtySkill = nil
  -- (Durchsicht 11.11.2026) a recipe row has its count in the row only
  if HeadSel() then
    W.qty:Hide()
    W.bar:Layout(W.bar._w or W.bar:GetWidth())
    return
  end
  local showQty = KIND[tab] and B.kind ~= "post" and B.isCommodity ~= false and W.bar.nActions > 0
  W.qty:SetShown(showQty and true or false)
  if showQty then
    if not W.qty._focus and (W.qtyPlan ~= B.plan or W.qtyEntry ~= B.entry) then
      W.qty:SetValue(B.want or (B.plan and B.plan.qty) or "")
    end
    W.qtyPlan, W.qtyEntry = B.plan, B.entry
  end
  W.bar:Layout(W.bar._w or W.bar:GetWidth())
end

---------------------------------------------------------------------------
-- Layout and drawing
---------------------------------------------------------------------------
local function DrawStatus()
  local S0, L = ns.ScanState, ns.lists
  local wait = ns.ScanWait()
  local busy = S0.phase == "waiting" or S0.phase == "reading" or S0.phase == "finishing"
  local status = S0.msg or ""
  if not busy then
    local age = L.t and ("Scan vor %d min, %s Auktionen%s. "):format(floor((time() - L.t) / 60), Kit.Thousands(L.n or 0), L.restored and " (gespeichert)" or "") or "Noch kein Scan. "
    -- (Durchsicht 11.11.2026) old prices in colour: yellow from 30 minutes, red from 2 hours or without a scan
    local mins = L.t and (time() - L.t) / 60
    if not mins then age = RED .. age .. "|r"
    elseif mins >= 120 then age = RED .. age .. "Preise alt, neu scannen. |r"
    elseif mins >= 30 then age = YEL .. age .. "Preise älter. |r" end
    status = age .. (wait > 0 and ("Nächster Vollscan in %d min."):format(math.ceil(wait / 60)) or "")
    if ns.Prices.TSMReady() then status = status .. " TSM an." end
    -- (Daniel 16.11.2026) the scan of one profession: its progress, afterwards how long ago
    local PS = ns.ProfScanState
    local run = ns.ProfScanText and ns.ProfScanText()
    if run then status = run
    elseif PS and PS.okAt then status = status .. (" Beruf %s gescannt vor %d min."):format(PS.label or "", floor((time() - PS.okAt) / 60)) end
  end
  W:SetStatus(status)
  local psRun = ns.ProfScanBusy and ns.ProfScanBusy()
  W.scan:SetDisabled(not (S0.open and wait == 0 and not busy and not psRun))
  if W.pscan then
    W.pscan:SetText(psRun and "Stopp" or "Beruf scannen")
    W.pscan:SetDisabled(not (psRun or (S0.open and not busy)))
  end
end

local function Place()
  local w, h = W.bw or 700, W.bh or 400
  -- (Daniel 15.11.2026, Bild Blizzard-Optik: "suchen oben nur wenn man fenster ganz groß zieht") Blizzard's buttons are
  -- wider than the kit's chips: there the lists stand in the first row beside the portrait and the controls (search,
  -- switches, Vollscan) in a second row of their own above the table
  -- (Fenstercheck 24.11.2026, Bilder b6 s0008, s0096: Kaufen and Verkaufen with an empty row on top) the pages of their own
  -- have no chips: their controls (Vollscan) take the first row, the page starts right below it
  local two = W.blizz and not (tab == "ah" or tab == "sell") and true or false
  local top = two and 64 or 36
  local cy = two and -39 or -6
  W.listPage:SetSize(w, h)
  W.chips:ClearAllPoints()
  W.chips:SetPoint("TOPLEFT", W.listPage, "TOPLEFT", S.pad + (W.atticX or 0), -6)
  local craftish = (CRAFT_MODE[tab] or PROF_MODE[tab]) and true or false
  W.all:Update() W.useHave:Update()
  -- (Daniel 09.11.2026) the AH mats of the list searched live, and the chosen recipe set to what still pays
  local live = IsShop(tab) and ns.ScanState.open and W.items and #W.items > 0
  if live then
    local L = ns.LiveState
    W.live:SetText(L and L.busy and ("Live... %d/%d"):format((L.total or 0) - #L.queue, L.total or 0) or "Live prüfen")
  end
  -- (Daniel 20.11.2026: "oben ein Knopf 'Blizzards AH anzeigen'") on every list while the AH is open and its window is kept away
  local ahBtn = W.ahBlizz and ns.ScanState.open and ns.Opt("ahHide") ~= false and true or false
  if ahBtn then W.ahBlizz:SetText(ns.AHFrameState.hidden and "Blizzard-AH" or "Blizzard-AH weg") end
  local bestHead
  for _, it in ipairs(IsShop(tab) and W.items or {}) do
    local e = it.entry
    if e and e.head and e.chosen and e.be and e.be.best > 0 and e.be.best ~= e.runs then bestHead = e end
  end
  if bestHead then W.best:SetText(("Auf %d"):format(bestHead.be.best)) end
  -- (Durchsicht 11.11.2026, Kit 23) the controls over the list from the right edge: Kit.PlaceRight in place of the
  -- hand-counted row
  local rx = UI.PlaceRight(W.listPage, {
    { W.scan, 90 },
    { W.pscan, 110, (tab == "skill" or PROF_MODE[tab]) and true or false },
    { W.all, W.all.w, craftish },
    { W.search, 150, craftish },
    { W.sChar, 120, tab == "skill" },
    { W.sProf, 130, tab == "skill" },
    { W.pProf, 150, PROF_MODE[tab] and true or false },
    { W.dProf, 150, tab == "demake" },
    { W.clear, 100, tab == "shop" and #ns.Skill.Plan() > 0 },
    { W.live, 100, live and true or false },
    { W.best, 80, bestHead and true or false },
    { W.useHave, W.useHave.w, IsShop(tab) },
    { W.favCraft, W.favCraft.w, tab == "crates" },
    { W.listEdit, 90, LISTKEY[tab] ~= nil },
    { W.ahBlizz, 110, ahBtn },
  }, { y = cy })
  -- the secure bag button hangs on UIParent, only anchored to the window: a protected child would make the Kit window
  -- itself protected (no closing or opening in combat); in combat it is left as it is
  local deb = ns.DE.Button(UIParent)
  if deb.SetFrameStrata and not ns.Call(InCombatLockdown) then deb:SetFrameStrata("DIALOG") end
  if tab == "debag" then
    if not ns.Call(InCombatLockdown) then
      deb:Show() deb:ClearAllPoints() deb:SetPoint("TOPRIGHT", W.listPage, "TOPRIGHT", -rx, cy) deb:SetWidth(240)
      ns.DE.UpdateButton()
    end
    rx = rx + 240 + S.gap
  elseif not ns.Call(InCombatLockdown) then deb:Hide() end
  W.chips:Layout(max(120, w - (two and S.pad or rx) - S.pad - (W.atticX or 0)))
  -- (Daniel 20.11.2026) Kaufen has its own page (AHPage.lua): categories, search, results, the purchase
  if W.ahPage then W.ahPage:SetShown(tab == "ah") end
  if tab == "ah" and W.ahPage then
    W.table:Hide() W.bar:Hide()
    if W.sellPage then W.sellPage:Hide() end
    W.ahPage:ClearAllPoints()
    W.ahPage:SetPoint("TOPLEFT", W.listPage, "TOPLEFT", 0, -top)
    W.ahPage:Layout(w, max(80, h - top))
    return
  end
  -- (Daniel 17.11.2026, Verkaufen-Seite neu) Verkaufen has its own page (SellPage.lua): head, sections, offers
  if tab == "sell" and W.sellPage then
    W.table:Hide() W.bar:Hide()
    W.sellPage:Show()
    W.sellPage:ClearAllPoints()
    W.sellPage:SetPoint("TOPLEFT", W.listPage, "TOPLEFT", 0, -top)
    W.sellPage:Layout(w, max(80, h - top))
    return
  end
  if W.sellPage then W.sellPage:Hide() end
  W.table:Show() W.bar:Show()
  local barH = S.head
  W.table:ClearAllPoints()
  W.table:SetPoint("TOPLEFT", W.listPage, "TOPLEFT", 0, -top)
  W.table:Layout(w, max(40, h - top - barH))
  W.bar:ClearAllPoints()
  W.bar:SetPoint("BOTTOMLEFT", W.listPage, "BOTTOMLEFT", 0, 0)
  W.bar:Layout(w)
end

local function ChipCounts()
  for _, k in ipairs(SUBS[group] or {}) do
    local chip = W.chips:Chip(k)
    local n
    if k == "deah" or k == "vendor" then n = 0 for _, e in ipairs(ns.lists[KIND[k]] or {}) do if not e.gone then n = n + 1 end end end
    -- (Durchsicht 11.11.2026) the cheap counts on every chip, so a list with something to do shows it unopened
    if k == "debag" then n = #(ns.DE.BagList())
    elseif k == "sell" then n = ns.SellWaiting()
    elseif k == "shop" then n = #ns.Skill.Plan() + #ns.Crafts.Tracked() + (ns.Crafts.sel and 1 or 0)
    elseif LISTKEY[k] then local l = ns.ShopLists.Get(LISTKEY[k]) n = l and #l.items or 0
    elseif k == tab and not n then
      -- (Runde 2, Bild Entzaubern > Herstellen: "7" over five rows) only rows count, not the notes
      n = 0
      for _, it in ipairs(W.items) do if it.kind == "trow" then n = n + 1 end end
    end
    if chip then chip:SetCount((n and n > 0) and n or nil) end
  end
  -- the book tabs: a mark where something waits (to sell, to disenchant, under the vendor price)
  local wait = { sell = ns.SellWaiting() > 0, de = #(ns.DE.BagList()) > 0, vendor = false }
  for _, e in ipairs(ns.lists.vendor or {}) do if not e.gone then wait.vendor = true break end end
  for _, t in ipairs(W.tabs or {}) do
    if t.SetAlert and wait[t.key] ~= nil then t:SetAlert(wait[t.key] and t.key ~= group) end
  end
end

-- (Runde 2, 11.11.2026, Bilder Tasche, Unter Händlerpreis, Verkaufen: the empty list repeated the text of the bar) an empty
-- list says why it is empty
function ns.EmptyText(k)
  local L = ns.lists or {}
  local mins = L.t and floor((time() - L.t) / 60)
  local scan = mins and ("im letzten Vollscan (vor %d min)"):format(mins) or nil
  if k == "vendor" then return scan and ("Kein Sofortkauf unter Händlerpreis " .. scan .. ".") or "Noch kein Vollscan: im Auktionshaus \"Vollscan\" drücken, dann stehen hier Sofortkäufe unter Händlerpreis." end
  if k == "deah" then return scan and ("Nichts " .. scan .. ", dessen Mats nach Gebühr mehr wert sind als der Preis.") or "Noch kein Vollscan: im Auktionshaus \"Vollscan\" drücken, dann stehen hier Grüne und Blaue zum Entzaubern." end
  if k == "debag" then return "Nichts zum Entzaubern in den Taschen." end
  if k == "sell" then return "Nichts in den Taschen, das im AH mehr bringt als beim Händler oder entzaubert." end
  return TABS[k] and TABS[k][2] or ""
end

Draw = function()
  if not (W and W:IsShown() and W.built) then return end
  if tab == "report" then Page("rep") elseif tab == "sell" then Page("sellPage") elseif tab == "ah" then Page("ahPage") end
  if tab == "report" then
    W.listPage:Hide() W.rep:Show()
    W.rep:Fill()
    W.rep:Layout(W.bw or 700, (W.bh or 400) - (W.repTop or 0))
    ns.Try(DrawStatus)
    return
  end
  if W.rep then W.rep:Hide() end
  W.listPage:Show()
  local miss0 = ns.infoMiss
  W.items = Sort(Signals(Rows()))
  -- (Runde 2, 11.11.2026) everything of the shopping list is there or bought: once the purchase signal of the chosen mat
  -- has gone, the bar goes on to the recipe ("Alle herstellen"), once per finished list
  if IsShop(tab) then
    local B, d = ns.BuyState, W.shopDone
    if not d then W.doneJump = nil
    elseif not W.headSel and W.doneJump ~= d.spell and B.kind == "mats" and B.entry and (B.entry.need or 0) <= 0 and not ns.BuySignal(B.entry.id) then
      W.headSel = { spell = d.spell, char = d.char, chosen = d.chosen }
      W.doneJump = d.spell
      W.items = Sort(Signals(Rows()))
    end
  end
  local s = ShownSort(W.items)
  W.shownSort = s
  local runMin = ns.Opt("runMin") or 30
  RUNCOL.title = runMin == 60 and "Gold/h" or ("Gold/%d min"):format(runMin)
  W.table:SetColumns(ns.WindowColsNow(tab))
  W.table:SetSort(s and s.key, s and s.asc)
  W.table:SetItems(W.items)
  W.table:SetEmpty(ns.EmptyText(tab))
  -- (Runde 2, Bild Verkaufen: one chip "Verkaufen" under the tab "Verkaufen") a group with one list shows no chip
  -- (Daniel 20.11.2026, Bild: "kann hier leider keine eigene einkaufsliste anlegen") Einkaufsliste always shows its chips: "+ Neue Liste"
  for _, c in ipairs(W.chips.chips) do if GROUP_OF[c.key] == group and (#SUBS[group] > 1 or group == "shop") then c:Show() else c:Hide() end end
  W.chips:SetActive(tab)
  ChipCounts()
  ns.Try(DrawStatus)
  FillBar()
  if tab == "sell" and W.sellPage then W.sellPage.w, W.sellPage.h = W.bw or 700, W.bh or 400 W.sellPage:Fill() end
  if tab == "ah" and W.ahPage then W.ahPage.w, W.ahPage.h = W.bw or 700, W.bh or 400 W.ahPage:Fill() end
  Place()
  ns.NameRetry(ns.infoMiss ~= miss0)
end

ns.NameFn(Draw, "Window.lua Draw")
ns.NameFn(DrawStatus, "Window.lua DrawStatus")
function ns.Refresh() if W and W:IsShown() then ns.Perf("Hauptfenster " .. tostring(tab), ns.Try, Draw) end end
ns.NameFn(ns.Refresh, "Window.lua Refresh")
-- (Daniel 16.11.2026: "ruckelig ... crafting auf, habe gecrafted und wollte in profitdon rumstöbern") the events of the
-- game (bags, item data, the profession window) redraw the whole window: every craft did it, several times. They come
-- together into one redraw a second later; while a cast runs (crafting) it waits until the casting stops, at most 8 s.
-- A click in the window still draws at once (ns.Refresh).
-- (16.11.2026, Daniel: "wenn man nicht mehr castet und nicht in der warteschleife ist") it waits while busy (ns.Busy:
-- a cast or the game's craft queue), however long the queue runs
function ns.RefreshSoon()
  if not (W and W:IsShown()) then return end
  ns.WhenIdle("Hauptfenster", ns.Refresh, 1)
end
-- (14.11.2026) the progress of a running scan: the status line only, not the whole window
function ns.RefreshStatus() if W and W:IsShown() and W.built then ns.Try(DrawStatus) end end

-- the book tab of the group lit; SelectTab calls onTab, which must not switch again (it went round and round)
local function ShowTab()
  W.syncing = true
  W:SelectTab(group)
  W.syncing = nil
end

local function SwitchTab(k)
  if not GROUP_OF[k] then return end
  if k ~= tab then ns.Select(nil) W.msg = nil end
  tab, group = k, GROUP_OF[k]
  ns.db.ui = ns.db.ui or {}
  ns.db.ui[group] = k
  -- the merchant's "Mats kaufen" buys for the list shown last
  if group == "shop" then ns.ShopLists.SetActive(LISTKEY[k]) end
  ShowTab()
end
function ns.SetTab(k) if W then SwitchTab(k) Draw() else tab, group = k, GROUP_OF[k] or group end end
function ns.WindowTab() return W and W:IsShown() and tab or nil end
function ns.WindowFrame() return W end

-- (Daniel 18.11.2026) a zone of the writs folded with + / -, kept for the next look
-- (Daniel 18.11.2026) Shift pressed or let go over a row: its tooltip with or without the detail lines, shown again
function ns.WindowShift(down, items)
  items = items or (W and W.items)
  if not items then return end
  for _, it in ipairs(items) do
    -- (24.11.2026) a tooltip not worked out yet (Row, lazyTip) is worked out with the Shift of the moment it is read
    if rawget(it, "tipFull") then it.tipLines = down and it.tipFull or it.tipShort end
  end
  local tt = GameTooltip
  local owner = tt and tt.IsShown and tt:IsShown() and tt.GetOwner and tt:GetOwner()
  -- (22.11.2026, Daniel: "Window.lua:1639: attempt to index field 'item' (a number value)") a tooltip of another addon's or
  -- Blizzard's frame whose field item is a number: only Profitdon's rows (a table) are shown again
  if owner and type(owner.item) == "table" and owner.item.tipFull and owner.GetScript then
    local enter = owner:GetScript("OnEnter")
    if enter then pcall(enter, owner) end
  end
end
ns.On("MODIFIER_STATE_CHANGED", function(_, key, down)
  if key == "LSHIFT" or key == "RSHIFT" then ns.Try(ns.WindowShift, down == 1) end
end)
function ns.WindowToggle(it)
  if it and it.foldKey and ns.db.ui and ns.db.ui.writFold then ns.db.ui.writFold[it.foldKey] = it.collapsed or nil Draw() end
end
local function OnRowClick(it, button)
  if not it or it.kind ~= "trow" then return end
  local e = it.entry
  if button == "RightButton" then
    -- (Daniel 24.11.2026: "rechtsklick im ah ansehen geht nicht mehr") the entry's menu begins with the AH search again
    if e and e.head and e.listId then ns.ListEntryMenu(e, ns.FindItems(it)) return end
    if it.listHead then ns.ListEntryMenu(it.listHead, ns.FindItems(it)) return end
    local kind, key = ns.ListTarget(it)
    if kind then ns.ListAddMenu(kind, key, it.title, ns.FindItems(it)) end
    return
  end
  W.msg = nil
  if CRAFT_MODE[tab] or PROF_MODE[tab] then
    ns.Crafts.sel = (ns.Crafts.sel == e) and nil or e
  elseif tab == "skill" then
    local Sk = ns.Skill
    if e and Sk.sel and Sk.sel.spell == e.spell and Sk.sel.char == e.char then Sk.sel = nil
    elseif e then Sk.sel = { char = e.char, spell = e.spell } end
  elseif e and e.head then
    -- (08.11.2026) a recipe on the shopping list: selected, the bar sets its count (Skillen opens from the bar's button)
    local s = W.headSel
    if s and s.spell == e.spell and s.char == e.char and (s.chosen or false) == (e.chosen or false) then W.headSel = nil
    else W.headSel = { spell = e.spell, char = e.char, chosen = e.chosen } end
    W.qtyHead = nil
  elseif e and KIND[tab] then
    if W then W.headSel = nil end
    ns.Select(e, KIND[tab])
  end
  Draw()
end
ns.WindowClick = function(it, button) OnRowClick(it, button) end -- (tests)

-- (24.11.2026, Ruckler, Laptop: the first opening 2603 ms) a page of its own is built when it is first wanted: by the job
-- after the window or by its tab. A failure in Blizzard's look builds it with the kit (Diag blizzMain names it).
PAGES = { "sellPage", "ahPage", "rep" }
local PAGE_MAKE = {
  sellPage = function(kit) return ns.SellPage(W.listPage, kit) end,
  ahPage = function(kit) return ns.AHPage(W.listPage, kit) end,
  rep = function(kit) return ns.Report.Page(W.repParent or W.body, function() if Draw then Draw() end end, kit) end,
}
Page = function(k)
  if not W then return nil end
  if W[k] then return W[k] end
  local ok, p = pcall(PAGE_MAKE[k], UI)
  if not ok then
    ns.Fact("blizzMain", "Fehler " .. k .. ": " .. tostring(p))
    if UI == Kit then error(p, 0) end
    p = PAGE_MAKE[k](Kit)
  end
  W[k] = p
  p:Hide()
  return p
end
ns.WindowPage = function(k) return Page(k) end -- (tests)

local function BuildWith()
  ns.db.win = ns.db.win or {}
  W = UI.Window("ProfitdonFrame", { title = "Profitdon", logo = "Interface\\AddOns\\Profitdon\\Media\\portrait",
    -- (16.11.2026, DonCore Blizz 5) the module's frame would put a button for DonCore's options window at the top right,
    -- over the first row; Profitdon's Blizzard window had none (its options live in the game's own window)
    options = UI == Kit and "Profitdon" or nil, hint = "/profit optionen", footer = true, attic = true, store = ns.db.win, width = 760, height = 520,
    onTab = function(key)
      if W and W.built and not W.syncing then
        local k = ns.db.ui and ns.db.ui[key]
        SwitchTab((k and GROUP_OF[k] == key) and k or SUBS[key][1]) Draw()
      end
    end,
    onClose = function()
      local b = ns.DE.Button(UIParent) if not ns.Call(InCombatLockdown) then b:Hide() end
      -- (20.11.2026) Blizzard's window is away: shutting Profitdon leaves the AH (nothing else would show it)
      if ns.AHLeave then ns.AHLeave() end
    end,
    onLayout = function(win, w, h, mode)
      win.bw, win.bh, win.mode = w, h, mode
      if win.built then if tab == "report" then if win.rep then win.rep:Layout(w, h - (win.repTop or 0)) end else Place() end end
    end })
  -- (Daniel 10.11.2026: "taschen sollen gerne in den Vordergrund, wenn geöffnet") the bags (Baganator, Blizzard's) live on
  -- MEDIUM and come up when shown; the Kit's HIGH kept Profitdon above them. MEDIUM and toplevel: whatever was opened or
  -- clicked last is on top, as with the AH window
  ns.Call(W.SetFrameStrata, W, "MEDIUM")
  W:Hide()
  for _, g in ipairs(GROUPS) do W:AddTab(g[1], g[2]) end
  W.listPage = CreateFrame("Frame", nil, W.body)
  W.listPage:SetPoint("TOPLEFT", 0, 0)
  local lp = W.listPage
  W.chips = UI.ChipBar(lp, { onChange = function(key, _, _, button)
    if not W.built then return end
    SwitchTab(key) Draw()
    if button == "RightButton" and LISTKEY[key] then ns.ListMenu(LISTKEY[key]) end
  end })
  for _, g in ipairs(GROUPS) do
    for _, k in ipairs(SUBS[g[1]]) do
      local chip = W.chips:Add(k, TABS[k][1])
      chip:SetTooltip(TABS[k][1], { TABS[k][2] })
    end
  end
  -- (Daniel 14.11.2026, Bilder: "bau mal alle schalter um, dass man das ordentlich erkennt", "vll mit wahlschalter",
  -- "alles sollen gleich aussehen") every on/off choice over the list is the kit's switch with its name beside it
  local function Switch(label, get, set, tip, lines)
    local t = UI.Toggle(lp, { label = label, get = get, set = set })
    t:SetTooltip(tip, lines)
    if S.buttonSmall then t:SetHeight(S.buttonSmall) end -- on one line with the small buttons beside it
    t.w = math.max(40, math.ceil(tonumber(t:GetWidth()) or 0))
    return t
  end
  W.scan = UI.Button(lp, "Vollscan", { small = true, onClick = function() ns.StartScan() end,
    tooltip = "Vollscan", tooltipLines = { "Liest alle Auktionen (am Auktionshaus, höchstens alle 15 Minuten)." } })
  -- (Daniel 16.11.2026: "eine scan option, dass man nur den beruf scannt") the profession shown, item by item (Buy.lua)
  W.pscan = UI.Button(lp, "Beruf scannen", { small = true, onClick = function()
      if ns.ProfScanBusy() then ns.ProfScanStop() return end
      local prof
      if tab == "skill" then prof = ns.Skill.Prof(ns.Skill.Char()) else prof = ns.Crafts.ViewProf() end
      if prof then ns.ProfScan(prof) end
    end,
    tooltip = "Beruf scannen", tooltipLines = { "Sucht jeden Gegenstand des gewählten Berufs einzeln (Mats, Ergebnisse, Rezepte).",
      "Nur was im letzten Vollscan im AH stand; Neues sieht erst der nächste Vollscan.",
      "Geht jederzeit am Auktionshaus, dauert aber einige Minuten." } })
  W.all = Switch("Alle Rezepte", function() return ns.db.craftAll and true or false end, function(v) ns.db.craftAll = v or nil Draw() end,
    "Alle Rezepte", { "An: auch Rezepte unter dem Mindestgewinn (mit Verlust).", "Aus: nur was den Mindestgewinn bringt." })
  W.search = UI.SearchBox(lp, { placeholder = "Suchen...", width = 150, onChange = function(t) ns.SetFind(t) Draw() end })
  -- (Daniel 07.11.2026) Skillen: whose professions and which one
  W.sChar = UI.Dropdown(lp, {
    items = function()
      local list = {}
      for _, c in ipairs(ns.Skill.Chars()) do list[#list + 1] = { value = c, text = ns.Skill.Short(c) } end
      if #list == 0 then list[1] = { value = ns.Me(), text = ns.Skill.Short(ns.Me()) } end
      return list
    end,
    get = function() return ns.Skill.Char() end,
    set = function(v) ns.Skill.SetChar(v) Draw() end })
  W.sProf = UI.Dropdown(lp, {
    items = function()
      local list = {}
      for _, p in ipairs(ns.Skill.Profs(ns.Skill.Char())) do list[#list + 1] = { value = p, text = ns.Crafts.ProfName(p) } end
      if #list == 0 then list[1] = { value = 0, text = "Kein Beruf" } end
      return list
    end,
    get = function() return ns.Skill.Prof(ns.Skill.Char()) or 0 end,
    set = function(v) if v ~= 0 then ns.Skill.SetProf(ns.Skill.Char(), v) end Draw() end })
  -- (Daniel 08.11.2026) Berufe: which profession, all in the data
  W.pProf = UI.Dropdown(lp, {
    items = function()
      local list = {}
      for _, p in ipairs(ns.Crafts.ProfList()) do list[#list + 1] = { value = p, text = ns.Crafts.ProfName(p) } end
      if #list == 0 then list[1] = { value = 0, text = "Kein Beruf" } end
      return list
    end,
    get = function() return ns.Crafts.ViewProf() or 0 end,
    set = function(v) if v ~= 0 then ns.Crafts.SetViewProf(v) end Draw() end })
  -- (Daniel 21.11.2026, Bild Entzaubern > Herstellen: "alle rezepte und alle berufe auswählbar machen")
  W.dProf = UI.Dropdown(lp, {
    items = function()
      local list = { { value = "mine", text = "Meine Rezepte" }, { value = "all", text = "Alle Berufe" } }
      for _, p in ipairs(ns.Crafts.ProfList()) do list[#list + 1] = { value = p, text = ns.Crafts.ProfName(p) } end
      return list
    end,
    get = function() return ns.Crafts.DeView() end,
    set = function(v) ns.Crafts.SetDeView(v) Draw() end })
  W.clear = UI.Button(lp, "Liste leeren", { small = true, confirm = true, onClick = function() ns.Skill.Clear() Draw() end,
    tooltip = "Liste leeren", tooltipLines = { "Nimmt alle Rezepte aus Skillen von der Einkaufsliste." } })
  W.live = UI.Button(lp, "Live prüfen", { small = true, onClick = function()
      local ids, seen = {}, {}
      for _, it in ipairs(W.items or {}) do
        local e = it.entry
        if e and not e.head and e.src == "ah" and (e.need or 0) > 0 and not seen[e.id] then seen[e.id] = true ids[#ids + 1] = e.id end
      end
      ns.LiveCheck(ids)
      Draw()
    end, tooltip = "Live prüfen", tooltipLines = { "Sucht die AH-Mats der Liste nacheinander im AH.", "Danach rechnen Preise und \"lohnt bis\" mit den echten Angeboten (15 Minuten)." } })
  -- (Daniel 14.11.2026: "einen button für bank und taschenreagenzien mit einberechnen oder nicht", then "oder nur einen
  -- schalter mit keine vorhandenen mats aus egal welcher quelle mitrechnen") one switch for all that is there
  W.useHave = Switch("Vorhandenes einrechnen", function() return not ns.db.shopNoHave end, function(v) ns.db.shopNoHave = not v or nil Draw() end,
    "Vorhandenes einrechnen", { "An: Mats aus Taschen, Reagenzientasche, Bank und Briefkasten zählen als vorhanden.", "Aus: nichts zählt, die Liste zeigt den ganzen Einkauf." })
  -- (Daniel 23.11.2026, Bild Favor-Kisten: "eine auswahl, ob mit selbst herstellen oder ohne")
  W.favCraft = Switch("Selbst herstellen", function() return not ns.db.favorNoCraft end,
    function(v) ns.db.favorNoCraft = not v or nil if ns.Favor.Forget then ns.Favor.Forget() end Draw() end,
    "Selbst herstellen", { "An: ein Bündel kommt hergestellt, wo das billiger ist (gelb \"(selbst)\").",
      "Aus: jedes Bündel gekauft, beim Händler oder im AH.", "Gilt auch für Gold je Gunst in Skillen und Writs." })
  W.best = UI.Button(lp, "Auf", { small = true, onClick = function()
      for _, it in ipairs(W.items or {}) do
        local e = it.entry
        if e and e.head and e.chosen and e.be and e.be.best > 0 then SetHeadRuns(e, e.be.best) end
      end
      ns.Refresh()
    end, tooltip = "Lohnende Menge", tooltipLines = { "Setzt die Anzahl auf die Crafts, bis zu denen der Gewinn noch steigt." } })
  W.table = UI.Table(lp, { onClick = function(it, button) OnRowClick(it, button) end,
    -- (Daniel 18.11.2026) a zone of the writs folded with + / -, kept for the next look
    onToggle = function(it) ns.WindowToggle(it) end,
    onSort = function(key) ns.SortBy(key) Draw() end,
    -- (Daniel 18.11.2026) a head dragged onto another moves its column; a right click: the own order back
    onMove = function(from, to) ns.WindowMoveCol(tab, from, to) Draw() end })
  W.bar = UI.ActionBar(lp)
  W.ahBlizz = UI.Button(lp, "Blizzard-AH", { small = true, onClick = function() ns.AHFrameToggle() end,
    tooltip = "Blizzard-AH", tooltipLines = { "Zeigt Blizzards Auktionsfenster für diesen Besuch, nochmal drücken: wieder weg.",
      "Ganz abschalten: Optionen, \"Blizzards Auktionsfenster verstecken\"." } })
  -- (Durchsicht 11.11.2026, Kit 23) the amount box of the bar is the kit's a:Input (it was an own box hung into the bar
  -- with the bar's Layout written over)
  W.qty = W.bar:Input({ numeric = true, placeholder = "Anzahl", width = 60,
    onChange = function(t)
      if tab == "skill" then
        local n = tonumber(t)
        W.skillRuns = n and n > 0 and floor(n) or nil
        local e = SkillSel()
        if e and W.skillRuns and ns.Skill.InPlan(e.char, e.spell) then ns.Skill.Add(e.char, e.spell, W.skillRuns) end
        return
      end
      if HeadSel() then return end
      ns.SetWant(t, false)
    end,
    onEnter = function(self)
      if tab == "skill" or HeadSel() then Draw() return end
      ns.SetWant(self:GetText(), true)
    end })
  -- (Blizzard-Optik) the first 36 px of the body stand beside the portrait: the Auswertung starts below them
  W.repParent = W.body
  if W.blizz then
    W.repParent = CreateFrame("Frame", nil, W.body)
    W.repParent:SetPoint("TOPLEFT", 4, -40)
    W.repParent:SetSize(10, 10)
    W.repTop = 44
  end
  -- (24.11.2026) the pages Verkaufen, Kaufen and Auswertung (two thirds of the window's frames) come in the frames after
  -- the window, or at once when their tab is shown first (Pages)
  local win = W
  ns.Job("Fenster Seiten", function(pause)
    for _, k in ipairs(PAGES) do if W ~= win then return end Page(k) pause() end
  end)
  local tick = 0
  W:SetScript("OnUpdate", function(_, dt)
    tick = tick + (tonumber(dt) or 0)
    if tick >= 2 then tick = 0 ns.Try(DrawStatus) end
  end)
  -- (Daniel 19.11.2026) the own lists: a button for its menu, the chips
  W.listEdit = UI.Button(lp, "Liste ...", { small = true, onClick = function() if LISTKEY[tab] then ns.ListMenu(LISTKEY[tab]) end end,
    tooltip = "Liste", tooltipLines = { "Umbenennen oder löschen.", "Einträge: Rechtsklick auf einen Gegenstand oder Writ in einem Reiter." } })
  W.newList = W.chips:Add("slnew", "+ Neue Liste", nil, { add = true, onClick = function() ns.AskListName("Neue Liste", "", function(name)
    local l = ns.ShopLists.New(name)
    if l then ns.SyncListTabs() ns.SetTab(ListKey(l.id)) end
  end) end })
  -- (Daniel 24.11.2026) the lists of the other characters of the account too, or only the own ones
  W.allLists = W.chips:Add("slall", "Nur meine Listen", nil, { add = true, onClick = function()
    ns.ShopLists.SetShowAll(not ns.ShopLists.ShowAll())
    ns.SyncListTabs()
    ns.Refresh()
  end })
  GROUP_OF.slall = "shop"
  W.newList:SetTooltip("Neue Liste", { "Eine eigene Einkaufsliste mit Namen (Writ-Route, Barfood ...).", "Einträge: Rechtsklick auf einen Gegenstand oder Writ in einem Reiter, \"Auf Liste\"." })
  GROUP_OF.slnew = "shop"
  W.built = true
  ns.SyncListTabs()
  W:Layout()
end

local function Build()
  UI = ns.LookKit("blizzMain")
  if UI ~= Kit then
    local ok, err = pcall(BuildWith)
    if ok then return end
    -- a template did not do what its source says: the kit's window, and the reason for /profit diag
    ns.Fact("blizzMain", "Fehler: " .. tostring(err))
    ns.SayLook()
    if W and W.Hide then pcall(W.Hide, W) end
    W, UI = nil, Kit
  end
  BuildWith()
end
ns.WindowReset = function() if W then W:Hide() end W = nil end -- (tests: build the window anew)
ns.WindowBlizz = function() return W and W.blizz or false end

local function ToggleWindow(show, where)
  if not W then ns.Perf("Fenster bauen", Build) end
  if show == nil then show = not W:IsShown() end
  if show and where then SwitchTab(where) end
  W:SetShown(show)
  if not show and not ns.Call(InCombatLockdown) then ns.DE.Button(UIParent):Hide() end
  -- (20.11.2026) Blizzard's window is away: shutting Profitdon leaves the AH (the Kit's window calls onClose only for x)
  if not show and ns.AHLeave then ns.AHLeave() end
  if show then
    ShowTab()
    ns.Perf("Fenster zeigen " .. tostring(tab), Draw)
  end
end
-- (24.11.2026, Laptop: the first opening stood in the slow-call log as `call ?` with 2603 ms) opening and shutting under
-- a name of its own (/profit diag "Zeit Fenster öffnen", ProfitdonDB.slow "Window.lua Fenster öffnen")
function ns.ToggleWindow(show, where) return ns.Perf("Fenster öffnen", ToggleWindow, show, where) end
ns.NameFn(ns.ToggleWindow, "Window.lua Fenster öffnen")

-- the window beside Blizzard's (mode "right"), or in its place while that is kept away ("over")
function ns.AHDock(mode)
  if not W then return end
  local ahf = AuctionHouseFrame
  local x = ahf and (mode == "over" and ahf.GetLeft and ns.Call(ahf.GetLeft, ahf) or ns.Call(ahf.GetRight, ahf))
  local t = ahf and ns.Call(ahf.GetTop, ahf)
  if mode == "over" and not (ahf and ahf.GetLeft) then mode, x = "right", ahf and ns.Call(ahf.GetRight, ahf) end
  x, t = tonumber(x), tonumber(t)
  if x and t then
    local k = (ns.Call(ahf.GetEffectiveScale, ahf) or 1) / (ns.Call(W.GetEffectiveScale, W) or 1)
    W:ClearAllPoints()
    W:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x * k + (mode == "over" and 0 or 4), t * k)
    if W.Save then W:Save() end
  end
end
ns.On("AUCTION_HOUSE_SHOW", function()
  if not W then Build() end
  -- (Daniel 10.11.2026: "das fenster beim öffnen des AHs zum start so ausrichten") every opening of the AH puts the window
  -- right next to it, tops level; the place is kept against UIParent (the AH frame is gone once closed)
  -- (Daniel 20.11.2026) Blizzard's window kept away: Profitdon takes its place, on the page Kaufen
  local hide = ns.AHHideWanted and ns.AHHideWanted()
  ns.AHDock(hide and "over" or "right")
  if hide and ns.AHFrameHide and ns.AHFrameHide() then
    ns.ToggleWindow(true, "ah")
    -- the game may show its window a moment later (loading Blizzard_AuctionHouseUI): away again
    ns.After(0.2, function() if ns.ScanState.open and ns.AHHideWanted() then ns.AHFrameHide() end end)
    return
  end
  ns.ToggleWindow(true)
end)
-- (Daniel 15.11.2026: "Hauptfenster schließt immer beim Verlassen des AH")
ns.On("AUCTION_HOUSE_CLOSED", function()
  if W and W:IsShown() then ns.ToggleWindow(false) else ns.Refresh() end
end)
ns.On("BAG_UPDATE_DELAYED", function() if W and W:IsShown() and (tab == "debag" or tab == "sell" or IsShop(tab) or tab == "craft" or tab == "ahcraft" or tab == "skill") then ns.RefreshSoon() end end)
-- (24.11.2026, Ruckler, DonMonitor Riverglades: eight hitches of 27 to 66 ms in a minute with the window open) item data
-- of any addon redrew the whole tab: only when an item was missing since the last look (Core.lua ns.infoMiss)
local missSeen
local function ItemDataCame()
  if not (W and W:IsShown()) or missSeen == ns.infoMiss then return end
  missSeen = ns.infoMiss
  ns.RefreshSoon()
end
ns.On("GET_ITEM_INFO_RECEIVED", ItemDataCame)
-- (Fenstercheck 24.11.2026, Bilder b6 s0046, s0080, s0088: "Item 232438", "Item 3775" in Skillen, Entzaubern, Händler
-- until the next click) the game loads an item it keeps in its own cache without GET_ITEM_INFO_RECEIVED, only with
-- ITEM_DATA_LOAD_RESULT (the answer to C_Item.RequestLoadItemDataByID, Core.lua ns.ItemInfo; Questdon waits for both)
ns.On("ITEM_DATA_LOAD_RESULT", ItemDataCame)
-- and when neither comes (Forever does not answer for some items, DonCore Kit.ItemWait): a drawing that still missed a
-- name looks again 2 s later, at most 4 times in a row; a drawing with every name stops it
local nameTries, nameArmed = 0, false
function ns.NameRetry(missed)
  if not missed then nameTries = 0 return end
  if nameArmed or nameTries >= 4 then return end
  nameTries, nameArmed = nameTries + 1, true
  ns.After(2, function()
    nameArmed = false
    if W and W:IsShown() then missSeen = nil ns.RefreshSoon() end
  end)
end
ns.OnInit(function()
  local ui = ns.db.ui
  if type(ui) == "table" and ui.craft then tab = ui.craft end
end)
-- (24.11.2026, Ruckler) a craft list worked out as a job (Crafts.lua Cr.RowsSoon) is drawn once it is done, when the
-- character is idle (as every redraw of the game's events), right away otherwise
-- (24.11.2026, Runde 5) the rows of a new craft list are built first as a job of their own (KeptRow, a slice may end
-- before each row), the redraw then takes them; no pause inside a pcall: Rows() calls KeptRow straight from its loops.
-- With the window shut too (the list worked out ahead, ns.WindowPrewarm): its first opening then draws kept rows.
function ns.RowsDone()
  local shown = W and W:IsShown()
  if not (CRAFT_MODE[tab] or PROF_MODE[tab]) then if shown then DrawDone() end return end
  ns.Job("Fenster Zeilen", function(pause)
    local function p() rowPause = nil pause() rowPause = p end
    rowPause = p
    Rows()
    rowPause = nil
    DrawDone()
  end, function() rowPause = nil end)
end
-- (24.11.2026, Laptop: the first opening on Herstellen 2603 ms) the list the window opens on is worked out after the
-- login in the background (slices of 4 ms), the first opening shows it at once (a newer one follows as a job)
function ns.WindowPrewarm()
  if W and W:IsShown() then return end
  local Cr = ns.Crafts
  if CRAFT_MODE[tab] then
    local view = tab == "demake" and Cr.DeView() or "mine"
    if view ~= "mine" then Cr.ProfRowsSoon(view, CRAFT_MODE[tab]) else Cr.RowsSoon(CRAFT_MODE[tab]) end
  elseif PROF_MODE[tab] and Cr.ViewProf() then
    Cr.ProfRowsSoon(Cr.ViewProf(), PROF_MODE[tab])
  end
end
ns.On("PLAYER_LOGIN", function() ns.After(15, ns.WindowPrewarm) end)

---------------------------------------------------------------------------
-- Options in DonCore's one options window (/profit optionen)
---------------------------------------------------------------------------
local G = 10000
-- (Runde 2, 11.11.2026, without a picture, from the code: 15 options in one flat list, two of them with a single value)
-- { key, label, steps, unit, group, hidden }: group is the heading the option stands under; hidden keeps an option out of
-- the window (the two AH cuts have one value each; /profit set cutOwn <n> still changes them)
-- { key, label, steps, unit, group, hidden, tip }: steps nil is a switch, a list of numbers a value list (shown with the
-- unit), a list of { value, text } pairs a choice with named entries (20.11.2026, Fensterstil: values false and true);
-- tip is the line below the name
local OPTS = {
  { "minProfit", "Mindestgewinn", { 1, 5, 10, 25, 50, 100, 500, G }, "money", "Was lohnt" },
  { "minProfitPct", "Mindestgewinn in % vom Einsatz", { 0, 5, 10, 20, 50 }, "pct", "Was lohnt" },
  { "runMin", "Herstellen für den Händler: ein Lauf dauert (Gold je Lauf)", { 15, 30, 60 }, "min", "Was lohnt" },
  { "timeValue", "Zeit mitrechnen: Zwischenteile kaufen, wenn Selbermachen je Stunde weniger spart als dein bestes Gold/h", nil, nil, "Was lohnt", nil,
    "Gold/h aus der Liste \"Für Händler\" (einmal öffnen, gilt 3 Tage)" },
  { "demGoodRate", "Absatz gut ab Verkaufsquote", { 20, 30, 40, 50 }, "pct", "Was lohnt" },
  { "demSlowRate", "Absatz zäh ab Verkaufsquote, darunter kaum", { 5, 10, 15, 20 }, "pct", "Was lohnt" },
  { "demDays", "Fürs AH herstellen: Verkäufe von so vielen Tagen", { 1, 2, 3, 5, 7 }, nil, "Was lohnt" },
  { "demCap", "Fürs AH höchstens so viele Stück", { 5, 10, 20, 50 }, nil, "Was lohnt" },
  { "demOwnMin", "Eigene Verkaufsquote ab so vielen eingestellten Stück", { 3, 5, 10, 20 }, nil, "Was lohnt" },
  { "maxSpend", "Höchstens je Kaufklick", { 10 * G, 50 * G, 100 * G, 500 * G }, "money", "Kaufen und Einstellen" },
  { "confirmAbove", "Zweiter Klick ab", { G, 10 * G, 50 * G, 100 * G }, "money", "Kaufen und Einstellen" },
  { "postDur", "Laufzeit beim Einstellen", { 1, 2, 3 }, "dur", "Kaufen und Einstellen" },
  { "postPortion", "Nur einstellen, was in den Absatztagen verkauft wird", nil, nil, "Kaufen und Einstellen" },
  { "ahHide", "Blizzards Auktionsfenster verstecken (Reiter Kaufen sucht und kauft, Knopf \"Blizzard-AH\" zeigt es)", nil, nil, "Kaufen und Einstellen" },
  { "sellMinGain", "Verkaufen: AH muss mindestens so viel mehr bringen als der Händler", { 0, 10, 100, 1000, G }, "money", "Verkaufen" },
  { "sellMinPct", "Verkaufen: AH muss mindestens so viel % über dem Händlerpreis liegen", { 0, 10, 25, 50, 100 }, "pct", "Verkaufen" },
  { "sellMade", "Abschnitt \"Hergestellt\" zeigen", nil, nil, "Verkaufen" },
  { "sellAH", "Abschnitt \"AH lohnt\" zeigen", nil, nil, "Verkaufen" },
  { "sellVendorRows", "Abschnitt \"Händler zahlt mehr\" zeigen", nil, nil, "Verkaufen" },
  { "sellNoPrice", "Abschnitt \"Ohne Preis\" zeigen", nil, nil, "Verkaufen" },
  { "cutOwn", "AH-Gebühr Fraktion", { 5 }, "pct", nil, true },
  { "cutNeutral", "AH-Gebühr neutral", { 15 }, "pct", nil, true },
  { "deBlue", "Taschenknopf entzaubert auch Blaue", nil, nil, "Entzaubern" },
  { "deEpic", "Taschenknopf entzaubert auch Epische", nil, nil, "Entzaubern" },
  { "deAlways", "Ausrüstung immer entzaubern, auch wenn das AH mehr zahlt", nil, nil, "Entzaubern" },
  { "deMinRolls", "Entzauber-Tabelle zählt wie so viele eigene Würfe", { 20, 50, 100, 200 }, nil, "Entzaubern" },
  { "deBuff", "Buff \"Boosted Disenchanting\" erkennen und einrechnen, solange er läuft", nil, nil, "Entzaubern" },
  { "deBonus", "Bonus auf Entzauber-Mats immer einrechnen (ohne Buff)", { 0, 5, 10, 15, 20 }, "pct", "Entzaubern" },
  { "sellGrey", "Händlerknopf verkauft Graues (graue Rüstung und Waffen nicht, wenn das AH mehr zahlt)", nil, nil, "Händler" },
  { "sellVendor", "Händlerknopf verkauft für den Händler Gekauftes und Hergestelltes", nil, nil, "Händler" },
  { "autoCrate", "Favor-Kisten beim Inventory Intake von selbst abgeben (Shift hält es an)", nil, nil, "Händler" },
  { "tsm", "TSM-Marktwert nutzen, wenn TSM da ist", nil, nil, "Preise und Anzeige" },
  -- (Daniel 20.11.2026) the page Kaufen: the days of the median and the trend (History.lua)
  { "medDays", "Median und Tendenz über so viele Tage", { 3, 5, 7 }, nil, "Preise und Anzeige" },
  { "scanBudget", "Vollscan: Rechenzeit je Bild in ms (kleiner läuft ruhiger, dauert länger)", { 2, 4, 8 }, nil, "Preise und Anzeige" },
  { "tooltip", "Preise im Item-Tooltip (Shift: Einzelheiten)", nil, nil, "Preise und Anzeige" },
  -- (24.11.2026, Fenstercheck) the look (blizzLook) is no longer here: DonCore's shared item ns.LookOption under the
  -- heading "Fenster" (below), the same name as in all Don addons, value db.opt.blizzLook as before
  { "afkCap", "Herstellen höchstens 28 Minuten je Klick (sonst loggt das Spiel nach 30 Minuten ohne Eingabe aus)", nil, nil, "Preise und Anzeige" },
  { "hideRecipeList", "Blizzards Liste verfolgter Rezepte ausblenden (sie stehen auf der Einkaufsliste)", nil, nil, "Preise und Anzeige" },
}
ns.WINDOW_OPTS = OPTS -- (tests)
-- a choice with named entries: the steps are { value, text } pairs
local function Named(o) return type(o[3]) == "table" and type(o[3][1]) == "table" end
-- the shared words of the look option (DonCore Settings 6: "Window style", in the game's language)
local SW = Core:Get("Settings", 6)
function ns.OptLabel(key)
  for _, o in ipairs(OPTS) do if o[1] == key then return o[2] end end
  if key == "blizzLook" and SW then return SW.LookWord("Window style") end
  return key
end
local Opt = Core:Get("Options", 8)
if Opt then
  local function Step(o, v)
    if o[4] == "money" then return ns.Money(v) end
    if o[4] == "pct" then return v .. " %" end
    if o[4] == "h" then return v .. " h" end
    if o[4] == "min" then return v .. " min" end
    if o[4] == "dur" then return (ns.POST_HOURS[v] or "?") .. " h" end
    return tostring(v)
  end
  local items, main = {}, {}
  local head
  for _, o in ipairs(OPTS) do if not o[6] then
    if o[5] and o[5] ~= head then head = o[5] main[#main + 1] = "header:" .. head end
    local it = { key = o[1], name = o[2], tip = o[7] }
    if Named(o) then
      it.kind = "dropdown"
      it.options = function()
        local list = {}
        for _, p in ipairs(o[3]) do list[#list + 1] = { p[1], p[2] } end
        return list
      end
    elseif o[3] then
      it.kind = "dropdown"
      it.options = function()
        local list, cur, seen = {}, ns.Opt(o[1]), false
        for _, s in ipairs(o[3]) do list[#list + 1] = { s, Step(o, s) } if s == cur then seen = true end end
        if cur ~= nil and not seen then
          list[#list + 1] = { cur, Step(o, cur) }
          table.sort(list, function(a, b) return a[1] < b[1] end)
        end
        return list
      end
    end
    items[#items + 1] = it
    main[#main + 1] = o[1]
  end end
  ns.WINDOW_OPT_MAIN = main -- (tests)
  -- (24.11.2026, Fenstercheck) the heading "Fenster" with the shared look option and the minimap button
  main[#main + 1] = "header:Fenster"
  if ns.LookOption then
    items[#items + 1] = ns.LookOption({ addon = "Profitdon", note = "Wirkt nach /reload." })
    main[#main + 1] = "blizzLook"
  end
  if ns.MinimapOption then
    items[#items + 1] = ns.MinimapOption({ name = "Minimap-Knopf zeigen", tip = "Profitdons Knopf am Rand der Minimap." })
    main[#main + 1] = "minimapButton"
  end
  Opt.Register("Profitdon", { name = "Profitdon", order = 11,
    tabs = { { key = "main", title = "Profitdon", text = "Was als lohnend gilt, wie viel ein Klick ausgeben darf, Entzaubern und Händlerknopf.",
      icon = "Interface\\AddOns\\Profitdon\\Media\\minimap", main = main } },
    pages = function() return { { items = items } } end,
    db = function() return ns.db and ns.db.opt end,
    default = function(key) return ns.DEFAULTS[key] end,
    changed = function() ns.OptionChanged() end,
    T = function(s) return s end,
  })
end
---------------------------------------------------------------------------
-- (24.11.2026, Fenstercheck, Daniel: "Bei den Optionen immer nur das Optionsfenster des jeweiligen Addons aufmachen")
-- Profitdon's own full pages in the game's options window (15.11.2026, BlizzOptions) are gone: the options live in
-- DonCore's window only (the look follows Fensterstil), Blizzard's AddOns list keeps DonCore's short page with the button
-- that opens it (Settings 7, BuildSettings with ownWindow). Values live in ProfitdonDB.opt as ever.
---------------------------------------------------------------------------
local SETTINGS_WORDS = { Options = "Optionen", Open = "Öffnen" }
local function BlizzPage()
  if not ns.BuildSettings then return nil end
  local ok, cat = pcall(ns.BuildSettings, { name = "Profitdon", ownWindow = true, pages = {},
    T = function(s) return SETTINGS_WORDS[s] or s end })
  if not ok then ns.Fact("blizzOptions", "Fehler: " .. tostring(cat)) return nil end
  return cat
end
ns.BlizzPage = BlizzPage -- (tests)
ns.OnInit(BlizzPage)
-- tab: optional tab key of the window ("main")
function ns.OpenOptions(tab)
  if Opt and Opt.Open("Profitdon", tab) then return true end
end
-- (08.11.2026) the lists in slices (Scan.lua ComputeLater), not 268000 auctions in one frame
function ns.OptionChanged()
  ns.Touch()
  -- (21.11.2026, Ruckler) the tooltip's kept values (Disenchant.lua DE.TipValue, History.lua H.Info) go
  if ns.DE then ns.DE.ver = (ns.DE.ver or 0) + 1 end
  if ns.History and ns.History.Bump then ns.History.Bump() end
  if ns.Crafts and ns.Crafts.ApplyRecipeList then ns.Crafts.ApplyRecipeList() end
  if ns.ComputeLater then ns.ComputeLater(ns.Refresh) return end
  if ns.Compute then ns.Try(ns.Compute) end
  ns.Refresh()
end

---------------------------------------------------------------------------
-- (Daniel 19.11.2026) own shopping lists (ShopLists.lua): a chip per list in the book tab Einkaufsliste, the menus
---------------------------------------------------------------------------
-- the chips follow the lists: new ones added before "+ Neue Liste", renamed ones renamed, deleted ones gone
function ns.SyncListTabs()
  for k in pairs(LISTKEY) do GROUP_OF[k] = nil TABS[k] = nil KIND[k] = nil end
  for k in pairs(LISTKEY) do LISTKEY[k] = nil end
  local subs = { "shop" }
  for _, l in ipairs(ns.ShopLists.Visible()) do
    local k = ListKey(l.id)
    local who = ns.ShopLists.OwnerName(l)
    LISTKEY[k], GROUP_OF[k], KIND[k] = l.id, "shop", "mats"
    TABS[k] = { who and ("%s (%s)"):format(l.name, who) or l.name, (who and ("Liste von " .. who .. " (Rechtsklick: auf diesen Char kopieren oder verschieben). ") or "") .. "Je Eintrag Vorrat halten (Taschen abgezogen) oder feste Menge. Herstellbares (auch von einem anderen Char) mit Mats, wenn billiger. AH-Zeile anklicken: Kauf je Klick." }
    subs[#subs + 1] = k
  end
  SUBS.shop = subs
  if not (W and W.chips) then return end
  -- first: a list that is gone (deleted, or hidden with the other characters' lists) is no tab while the chips move
  if not GROUP_OF[tab] then SwitchTab("shop") end
  for _, k in ipairs(subs) do
    if k ~= "shop" then
      local chip = W.chips:Chip(k)
      if not chip then chip = W.chips:Add(k, TABS[k][1]) end
      chip:SetText(TABS[k][1])
      if chip.Show then chip:Show() end
      chip:SetTooltip(TABS[k][1], { TABS[k][2], "Rechtsklick: umbenennen oder löschen." })
    end
  end
  -- the switch for the other characters' lists and "+ Neue Liste" stay last
  local chips = W.chips.chips
  for _, last in ipairs({ "slall", "slnew" }) do
    for i, c in ipairs(chips) do if c.key == last then table.remove(chips, i) chips[#chips + 1] = c break end end
  end
  for _, c in ipairs(chips) do if c.key and c.key:sub(1, 2) == "sl" and c.key ~= "slnew" and c.key ~= "slall" and not LISTKEY[c.key] then c:Hide() end end
  if W.allLists then
    local all = ns.ShopLists.ShowAll()
    W.allLists:SetText(all and "Listen aller Chars" or "Nur meine Listen")
    W.allLists:SetTooltip("Listen der anderen Chars", { all and "Gezeigt: die Listen aller Chars dieses Accounts. Klick: nur die eigenen." or "Gezeigt: nur die Listen dieses Chars. Klick: auch die der anderen Chars dieses Accounts.",
      "Eine fremde Liste, die es hier schon als Kopie gibt, steht nur einmal da.", "Rechtsklick auf eine fremde Liste: auf diesen Char kopieren oder verschieben." })
  end
  W.chips:Place()
end

-- what a row puts on a list: a writ (writs tab, a writ on a list) or the item
function ns.ListTarget(it)
  local e = it and it.entry
  if e and e.quest and tab == "writs" then return "writ", e.quest end
  if e and e.head and e.writ then return "writ", e.writ end
  local id = it and (it.itemID or (e and e.id))
  if id then return "item", id end
end

local function ShowMenu(title, items)
  local menu = UI.Menu or Kit.Menu
  menu(title, items)
  ns.lastMenu = { title = title, items = items } -- (tests)
end

-- (Daniel 20.11.2026: "den Gegenstand direkt im AH suchen, um vielleicht das Rezept zu sehen") the first entries of a
-- row's right click: its item searched in Kaufen, in Berufe and Herstellen also the recipe item that teaches it
function ns.FindItems(it)
  local e = it and it.entry
  local id = it and (it.itemID or (e and e.id))
  local name = id and ns.ItemInfo(id)
  if not name and id and type(it.title) == "string" and not it.title:find("^Item %d") then name = it.title end
  local items = {}
  if not name or tab == "ah" then return items end
  items[1] = { text = "Im AH suchen", onClick = function() ns.AHFind(name) end }
  local spell = e and e.r and e.r.spell
  local scroll = spell and ns.Skill.Learn(spell).item
  local sname = scroll and ns.ItemInfo(scroll)
  if sname then items[2] = { text = "Rezept im AH suchen", onClick = function() ns.AHFind(sname) end } end
  return items
end

-- right click on a row: on which list (first: what the row offers besides, ns.FindItems)
function ns.ListAddMenu(kind, key, title, first)
  local SL = ns.ShopLists
  local items = {}
  for _, x in ipairs(first or {}) do items[#items + 1] = x end
  for _, l in ipairs(SL.Visible()) do
    local there = SL.Find(l.id, kind, key)
    items[#items + 1] = { text = there and ("Auf \"%s\" (schon drauf: öffnen)"):format(l.name) or ("Auf Liste \"%s\""):format(l.name), onClick = function()
      if not there then SL.Add(l.id, kind, key, 1) end
      ns.SyncListTabs()
      ns.SetTab(ListKey(l.id))
    end }
  end
  items[#items + 1] = { text = "Auf neue Liste ...", onClick = function()
    ns.AskListName("Neue Liste", "", function(name)
      local l = SL.New(name)
      if not l then return end
      SL.Add(l.id, kind, key, 1)
      ns.SyncListTabs()
      ns.SetTab(ListKey(l.id))
    end)
  end }
  ShowMenu(title or "Auf Liste", items)
end
-- the same entries for other pages (Verkaufen)
function ns.ListAddItems(kind, key)
  local SL, items = ns.ShopLists, {}
  for _, l in ipairs(SL.Visible()) do
    if not SL.Find(l.id, kind, key) then
      items[#items + 1] = { text = ("Auf Liste \"%s\""):format(l.name), onClick = function() SL.Add(l.id, kind, key, 1) ns.SyncListTabs() ns.Refresh() end }
    end
  end
  items[#items + 1] = { text = "Auf neue Liste ...", onClick = function()
    ns.AskListName("Neue Liste", "", function(name)
      local l = SL.New(name)
      if l then SL.Add(l.id, kind, key, 1) ns.SyncListTabs() ns.Refresh() end
    end)
  end }
  return items
end

-- right click on an entry of an own list: stock or fixed, remove
function ns.ListEntryMenu(e, first)
  local SL = ns.ShopLists
  local id, kind, key = e.listId, e.listKind, e.listKey
  local items = {}
  for _, x in ipairs(first or {}) do items[#items + 1] = x end
  items[#items + 1] = { text = (e.fixed and "  " or "• ") .. "Vorrat halten (Taschen abgezogen)", onClick = function() SL.SetFixed(id, kind, key, false) ns.Refresh() end }
  items[#items + 1] = { text = (e.fixed and "• " or "  ") .. "Feste Menge jedes Mal kaufen", onClick = function() SL.SetFixed(id, kind, key, true) ns.Refresh() end }
  -- (Daniel 24.11.2026) a price alarm per item: a line in the chat once the AH offers it at that price or below
  if kind == "item" then
    local le = SL.Find(id, kind, key)
    local alarm = le and le.alarm
    items[#items + 1] = { text = alarm and ("Preiswecker ändern (%s) ..."):format(M(alarm)) or "Preiswecker stellen ...", onClick = function()
      ns.AskMoney("Preiswecker: " .. (ItemName(key) or ""), alarm or (ns.Prices.Row(nil, key) and ns.Prices.Low(key)) or nil, function(c)
        SL.SetAlarm(id, kind, key, c)
        -- what is known now counts at once
        if c then SL.CheckAlarms(nil, key) end
        ns.Refresh()
      end)
    end }
    if alarm then items[#items + 1] = { text = "Preiswecker aus", onClick = function() SL.SetAlarm(id, kind, key, nil) ns.Refresh() end } end
  end
  items[#items + 1] = { text = "Von der Liste nehmen", onClick = function() SL.Remove(id, kind, key) ns.Refresh() end }
  ShowMenu(ItemName(e.id) or "Eintrag", items)
end

-- a small dialog for a price per piece ("12g 50s" or "12,5"); empty: onOk(nil)
local moneyDlg
function ns.AskMoney(title, value, onOk)
  if moneyDlg and moneyDlg.ui ~= UI then moneyDlg:Hide() moneyDlg = nil end
  if not moneyDlg then
    moneyDlg = UI.Dialog(UI == Kit and "ProfitdonMoney" or "ProfitdonMoneyB", { title = title, width = 340, height = 170 })
    moneyDlg.ui = UI
    moneyDlg.text = UI.Text(moneyDlg.body, "sub", C.body)
    moneyDlg.text:SetPoint("TOPLEFT", moneyDlg.body, "TOPLEFT", 0, -4)
    moneyDlg.text:SetText("Preis je Stück, z. B. 12g 50s oder 12,5. Meldung im Chat,\nsobald das AH es so billig oder billiger anbietet.")
    moneyDlg.edit = UI.MoneyBox(moneyDlg.body, { placeholder = "Preis je Stück", onEnter = function() moneyDlg.ok() end })
    moneyDlg.edit:SetPoint("TOPLEFT", moneyDlg.body, "TOPLEFT", 0, -44)
    moneyDlg.edit:SetSize(300, 26)
    moneyDlg.ok = function()
      local c = moneyDlg.edit:GetValue()
      moneyDlg:Hide()
      if moneyDlg.onOk then ns.Try(moneyDlg.onOk, c and c >= 1 and c or nil) end
    end
    moneyDlg:SetButtons({ { text = "Abbrechen", onClick = function(d) d:Hide() end }, { text = "OK", kind = "primary", onClick = function() moneyDlg.ok() end } })
  end
  moneyDlg.onOk = onOk
  moneyDlg:SetTitle(title)
  moneyDlg.edit:SetValue(value)
  moneyDlg:Show()
  if moneyDlg.edit.SetFocus then moneyDlg.edit:SetFocus() end
  return moneyDlg
end

-- right click on a list chip (or its button): rename, delete
function ns.ListMenu(id)
  local SL = ns.ShopLists
  local l = SL.Get(id)
  if not l then return end
  local items = {}
  -- (Daniel 24.11.2026) a list of another character: onto this one, without doubles
  if not SL.Mine(l) then
    items[#items + 1] = { text = "Auf diesen Char kopieren", onClick = function()
      local own, n = SL.Copy(id)
      if not own then return end
      ns.Print(("Liste \"%s\" von %s kopiert: %d Einträge neu."):format(l.name, SL.OwnerName(l) or "?", n or 0))
      ns.SyncListTabs()
      ns.SetTab(ListKey(own.id))
    end }
    items[#items + 1] = { text = "Zu diesem Char verschieben", onClick = function()
      local own = SL.Take(id)
      if not own then return end
      ns.SyncListTabs()
      ns.SetTab(ListKey(own.id))
    end }
  end
  for _, x in ipairs({
    { text = "Umbenennen ...", onClick = function()
      ns.AskListName("Liste umbenennen", l.name, function(name) if SL.Rename(id, name) then ns.SyncListTabs() ns.Refresh() end end)
    end },
    { text = ("Löschen (%d Einträge)"):format(#l.items), onClick = function()
      ns.AskConfirm(("Liste \"%s\" löschen?"):format(l.name), ("%d Einträge gehen mit."):format(#l.items), function()
        SL.Delete(id)
        ns.SyncListTabs()
        ns.SetTab("shop")
      end)
    end },
  }) do items[#items + 1] = x end
  ShowMenu(l.name, items)
end

-- a small dialog for the name of a list
-- (Daniel 20.11.2026, Bild "Neue Liste": "noch altes don fenster") built with the window's look (UI), anew when it changes
local nameDlg
function ns.AskListName(title, value, onOk)
  if nameDlg and nameDlg.ui ~= UI then nameDlg:Hide() nameDlg = nil end
  if not nameDlg then
    nameDlg = UI.Dialog(UI == Kit and "ProfitdonListName" or "ProfitdonListNameB", { title = title, width = 340, height = 140 })
    nameDlg.ui = UI
    nameDlg.edit = UI.EditBox(nameDlg.body, { placeholder = "Name der Liste", maxLetters = 40, onEnter = function() nameDlg.ok() end })
    nameDlg.edit:SetPoint("TOPLEFT", nameDlg.body, "TOPLEFT", 0, -4)
    nameDlg.edit:SetSize(300, 26)
    nameDlg.ok = function()
      local name = nameDlg.edit:GetValue()
      if not name or name:gsub("%s", "") == "" then return end
      nameDlg:Hide()
      if nameDlg.onOk then ns.Try(nameDlg.onOk, name) end
    end
    nameDlg:SetButtons({ { text = "Abbrechen", onClick = function(d) d:Hide() end }, { text = "OK", kind = "primary", onClick = function() nameDlg.ok() end } })
  end
  nameDlg.onOk = onOk
  nameDlg:SetTitle(title)
  nameDlg.edit:SetValue(value or "")
  nameDlg:Show()
  if nameDlg.edit.SetFocus then nameDlg.edit:SetFocus() end
  return nameDlg
end
-- yes or no before something goes for good
local askDlg
function ns.AskConfirm(title, text, onYes)
  if askDlg and askDlg.ui ~= UI then askDlg:Hide() askDlg = nil end
  if not askDlg then
    askDlg = UI.Dialog(UI == Kit and "ProfitdonAsk" or "ProfitdonAskB", { title = title, width = 340, height = 130 })
    askDlg.ui = UI
    askDlg.text = UI.Text(askDlg.body, "sub", C.body)
    askDlg.text:SetPoint("TOPLEFT", askDlg.body, "TOPLEFT", 0, -4)
    askDlg:SetButtons({ { text = "Abbrechen", onClick = function(d) d:Hide() end },
      { text = "Löschen", kind = "primary", onClick = function(d) d:Hide() if d.onYes then ns.Try(d.onYes) end end } })
  end
  askDlg.onYes = onYes
  askDlg:SetTitle(title)
  askDlg.text:SetText(text or "")
  askDlg:Show()
  return askDlg
end
