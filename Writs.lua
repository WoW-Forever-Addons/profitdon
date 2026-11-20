local _, ns = ...

---------------------------------------------------------------------------
-- Craftsman's Writs (Daniel 18.11.2026, Reddit-Post "Craftsman's Writs: A daily rep grind": "wie können wir möglichst
-- effizient mit wenig laufwegen täglich ab stormwind die dinger abgeben, und möglichst günstig dabei wegkommen";
-- chosen: tab Writs)
--   every writ (Data/Writs.lua, ATT) is a daily quest: deliver a ware to a customer for reputation (Journeyman 75,
--   Expert 125, Artisan 200) and a Coin Pouch. The writs themselves are sold in the AH one by one, so a writ costs
--   its writ item plus its ware (as a mat: vendor, own craft or AH, the cheapest), less the pouch; per reputation.
--   A writ in the bags costs nothing more; one already handed in today waits for tomorrow.
--   Customers ATT does not know: learned at the turn-in (ProfitdonDB.writSeen[quest] = { npc, uiMap, x, y }).
--   Comparison: forging a crate (Forged Delivery Receipt, 15 Favor, at Friendly) gives 50 reputation.
---------------------------------------------------------------------------
local Wr = {}
ns.Writs = Wr

Wr.REP = { 75, 125, 200 }
-- Coin Pouch per rank in copper (Daniel 18.11.2026 from his game: Journeyman 5 to 19s, Expert about 36s, Artisan about
-- 74s 56c); an estimate until Profitdon measures it
Wr.POUCH = { 1200, 3600, 7456 }
-- where a customer comes from (Data/Writs.lua field 12)
Wr.ORIGIN = { q = "Spieleraufnahmen", a = "ATT", d = "laut Beta, ungeprüft", karte = "Kartenmarkierung des Spiels" }
Wr.RANK = { "Journeyman", "Expert", "Artisan" }
Wr.FORGE_FAVOR, Wr.FORGE_REP = 15, 50

local function List() return ns.WRITS and ns.WRITS.list or {} end

-- my side: "A" or "H"
local function Side()
  local f = UnitFactionGroup and ns.Call(UnitFactionGroup, "player")
  return f == "Horde" and "H" or "A"
end

local byQuest
local function Index()
  if byQuest then return byQuest end
  byQuest = {}
  for _, w in ipairs(List()) do byQuest[w[1]] = w end
  return byQuest
end
function Wr.Is(quest) return Index()[quest] ~= nil end

-- the customer: learned at the turn-in (origin "selbst"), else the data (recordings, ATT, Daniel's partly beta list);
-- npc, uiMap, x, y (x 0: only the zone known), learned, origin; nil without one
function Wr.Customer(w)
  local seen = type(ns.db.writSeen) == "table" and ns.db.writSeen[w[1]]
  if type(seen) == "table" and seen[2] then return seen[1], seen[2], seen[3], seen[4], true, "selbst" end
  -- (18.11.2026) the game's map mark of the accepted writ quest (Wr.ScanLog): the place, the name of the data if any
  local poi = type(ns.db.writPOI) == "table" and ns.db.writPOI[w[1]]
  if type(poi) == "table" and poi[1] then return (w[8] ~= "" and w[8]) or nil, poi[1], poi[2], poi[3], true, "karte" end
  local text = type(ns.db.writText) == "table" and ns.db.writText[w[1]]
  if w[9] and w[9] > 0 then return w[8], w[9], w[10], w[11], nil, w[12] end
  if type(text) == "table" and text.npc then return text.npc, nil, nil, nil, nil, "Angebot" end
end

function Wr.MapName(uiMap)
  local info = uiMap and C_Map and ns.Call(C_Map.GetMapInfo, uiMap)
  return type(info) == "table" and info.name or (uiMap and ("Karte " .. uiMap)) or nil
end

-- the Coin Pouch of a rank: measured average or the estimate
function Wr.Pouch(rank)
  local m = type(ns.db.writPouch) == "table" and ns.db.writPouch[rank]
  if type(m) == "table" and (m[1] or 0) > 0 then return math.floor(m[2] / m[1] + 0.5), "gemessen" end
  return Wr.POUCH[rank], "geschätzt"
end

function Wr.DoneToday(quest)
  local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
  return f and ns.Call(f, quest) == true or false
end

-- gold per reputation of forging a crate (15 Favor at the gold per Favor of the cheapest crate), nil without a price
function Wr.ForgePer()
  local g = ns.Favor and ns.Favor.GoldPerFavor()
  if g then return g * Wr.FORGE_FAVOR / Wr.FORGE_REP end
end

-- one entry per writ of my side: { id (writ item), quest, ware, n, rank, prof, npc, uiMap, x, y, learned, writ (AH),
-- writSrc, wareCost, wareSrc, held, pouch, pouchSrc, total, net, rep, per, done, maxUnit }; cheapest per reputation
-- first, writs handed in today and those without a price last
function Wr.Rows()
  local out, side = {}, Side()
  local Cr = ns.Crafts
  local outer = Cr.cache
  Cr.cache = outer or {}
  local ok, err = pcall(function()
    for _, w in ipairs(List()) do
      if w[7] == "" or w[7] == side then
        local e = { id = w[2], quest = w[1], ware = w[3], n = w[4], rank = w[5], prof = w[6] }
        e.npc, e.uiMap, e.x, e.y, e.learned, e.origin = Wr.Customer(w)
        e.zone = e.uiMap and Wr.MapName(e.uiMap) or nil
        e.writ, e.writSrc = ns.AHPrice(w[2])
        local unit, src = Cr.ReagentUnit(w[3])
        if unit then e.wareCost, e.wareSrc = unit * w[4], src end
        e.held = ns.BagCount and ns.BagCount(w[2]) or 0
        e.pouch, e.pouchSrc = Wr.Pouch(w[5])
        e.rep = Wr.REP[w[5]]
        local writ = e.held > 0 and 0 or e.writ
        if writ and e.wareCost then
          e.total = writ + e.wareCost
          e.net = e.total - (e.pouch or 0)
          e.per = e.net / e.rep
        end
        e.done = Wr.DoneToday(w[1])
        if e.writ then e.maxUnit = math.max(e.writ + 2, math.floor(e.writ * 1.25)) end
        out[#out + 1] = e
      end
    end
  end)
  Cr.cache = outer
  if not ok then error(err, 0) end
  -- (Daniel 18.11.2026: "die Writs nach Zonen sortieren und dann nach Kosten je Ruf") zones with the cheapest reputation
  -- first (Wr.Zones), inside a zone cheapest per reputation; writs without a zone, then those handed in today, last
  local rank = {}
  for i, z in ipairs(Wr.Zones(out)) do rank[z.uiMap] = i end
  local function zr(e) return e.uiMap and rank[e.uiMap] or (e.uiMap and 900 or 999) end
  table.sort(out, function(a, b)
    if a.done ~= b.done then return not a.done end
    local ra, rb = zr(a), zr(b)
    if ra ~= rb then return ra < rb end
    if ra >= 900 and a.uiMap ~= b.uiMap then return (a.uiMap or 0) < (b.uiMap or 0) end
    if (a.per == nil) ~= (b.per == nil) then return a.per ~= nil end
    if a.per and a.per ~= b.per then return a.per < b.per end
    return a.quest < b.quest
  end)
  return out
end

-- the cheapest writs grouped by zone, for planning a round: { { uiMap, n, rep, net } }, best value first;
-- only writs with a known customer, a price and not handed in today
function Wr.Zones(rows)
  local by, out = {}, {}
  for _, e in ipairs(rows) do
    if e.uiMap and e.per and not e.done then
      local z = by[e.uiMap]
      if not z then z = { uiMap = e.uiMap, n = 0, rep = 0, net = 0 } by[e.uiMap] = z out[#out + 1] = z end
      z.n, z.rep, z.net = z.n + 1, z.rep + e.rep, z.net + e.net
    end
  end
  table.sort(out, function(a, b) return a.net / a.rep < b.net / b.rep end)
  return out
end

---------------------------------------------------------------------------
-- On the shopping list: a writ is a recipe of its own for Crafts.ShoppingList (spell "writ:<quest>", reagents the writ
-- item and the ware). ProfitdonDB.writPlan = { { quest, n } }
---------------------------------------------------------------------------
local function Plan()
  ns.db.writPlan = type(ns.db.writPlan) == "table" and ns.db.writPlan or {}
  return ns.db.writPlan
end
function Wr.InPlan(quest)
  for i, p in ipairs(Plan()) do if p[1] == quest then return p, i end end
end
function Wr.Add(quest, n)
  n = math.max(1, math.floor(tonumber(n) or 1))
  local p = Wr.InPlan(quest)
  if p then p[2] = n else table.insert(Plan(), { quest, n }) end
end
function Wr.Remove(quest)
  local _, i = Wr.InPlan(quest)
  if i then table.remove(Plan(), i) end
end
function Wr.Recipe(quest)
  local w = Index()[quest]
  if not w then return nil end
  return { spell = "writ:" .. quest, item = w[2], reag = { { w[2], 1 }, { w[3], w[4] } }, count = 1, writ = quest }
end
function Wr.PlanEntries()
  local out = {}
  for _, p in ipairs(Plan()) do
    local r = Wr.Recipe(p[1])
    if r then out[#out + 1] = { r = r, runs = p[2], writ = p[1] } end
  end
  return out
end

---------------------------------------------------------------------------
-- Learning at the turn-in: the customer (the npc of the reward frame, where the player stands). The Coin Pouch is an
-- item opened later, its money stays an estimate (ProfitdonDB.writPouch[rank] = { pouches, copper } is read if set)
---------------------------------------------------------------------------
local pending
local function Here()
  local m = C_Map and ns.Call(C_Map.GetBestMapForUnit, "player")
  local p = m and ns.Call(C_Map.GetPlayerMapPosition, m, "player")
  local x, y
  if p and p.GetXY then x, y = p:GetXY() end
  return m, x and math.floor(x * 1000 + 0.5) / 10, y and math.floor(y * 1000 + 0.5) / 10
end

function Wr.OnQuestComplete()
  local q = GetQuestID and ns.Num(ns.Call(GetQuestID))
  if not (q and Wr.Is(q)) then pending = nil return end
  local m, x, y = Here()
  pending = { q = q, npc = ns.Call(UnitName, "npc"), m = m, x = x, y = y }
end

function Wr.OnTurnedIn(quest)
  quest = ns.Num(quest)
  if not (quest and Wr.Is(quest)) then return end
  local p = pending
  pending = nil
  if not p or p.q ~= quest then
    local m, x, y = Here()
    p = { q = quest, m = m, x = x, y = y }
  end
  if p.m then
    ns.db.writSeen = type(ns.db.writSeen) == "table" and ns.db.writSeen or {}
    ns.db.writSeen[quest] = { p.npc or "", p.m, p.x, p.y }
    ns.Fact("writLast", ("%d bei %s (%s)"):format(quest, p.npc or "?", tostring(p.m)))
  end
  -- (the plan entry is done once the writ is handed in)
  local e = Wr.InPlan(quest)
  if e then
    e[2] = e[2] - 1
    if e[2] <= 0 then Wr.Remove(quest) end
  end
  if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- (Daniel 18.11.2026: "wenn ich jede Writ einmal kaufe, könnten wir so herausfinden wer der Kunde ist") a right click on a
-- writ shows its offer; the text names the customer. Profitdon keeps the text (ProfitdonDB.writText[quest] = { text, npc,
-- t }), also when the offer is declined; the customer's name is a known NPC name of the data found in the text
---------------------------------------------------------------------------
local names
local function KnownNames()
  if names then return names end
  names = {}
  for _, w in ipairs(List()) do if w[8] and w[8] ~= "" then names[#names + 1] = w[8] end end
  table.sort(names, function(a, b) return #a > #b end)   -- the longest name first ("Kixxle" inside "Kixxle <...>")
  return names
end
function Wr.NameIn(text)
  if type(text) ~= "string" then return nil end
  for _, n in ipairs(KnownNames()) do
    if text:find(n, 1, true) then return n end
  end
end

function Wr.OnQuestDetail()
  local q = GetQuestID and ns.Num(ns.Call(GetQuestID))
  if not (q and Wr.Is(q)) then return end
  local text = (ns.Call(GetQuestText) or "") .. "\n" .. (ns.Call(GetObjectiveText) or "")
  ns.db.writText = type(ns.db.writText) == "table" and ns.db.writText or {}
  ns.db.writText[q] = { text = text, npc = Wr.NameIn(text), t = time() }
  ns.Fact("writText", ("%d: %s"):format(q, ns.db.writText[q].npc or "Name nicht erkannt"))
  if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- (Daniel 18.11.2026, three unknown writs bought and opened: the offer only says "deliver them to the location marked on
-- your map") once a writ quest is in the log the game marks its customer on the map: Profitdon reads that mark
-- (C_QuestLog.GetQuestsOnMap over every zone of both continents) and keeps it as ProfitdonDB.writPOI[quest] = { uiMap, x, y }.
-- The quest may be abandoned afterwards, the writ item stays in the bags.
-- (18.11.2026, Daniel with 37 writs accepted: "ich sehe aber nicht", writScan: 49 zone maps, no mark, no waypoint) the
-- game shows no mark for the writs, despite the text: read once at the accept only, no scans at login or log updates
---------------------------------------------------------------------------
local zoneMaps
local function ZoneMaps()
  if zoneMaps then return zoneMaps end
  zoneMaps = {}
  local seen = {}
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  for _, cont in ipairs({ 1415, 1414 }) do   -- Eastern Kingdoms, Kalimdor
    local kids = C_Map and C_Map.GetMapChildrenInfo and ns.Call(C_Map.GetMapChildrenInfo, cont, zoneType, true)
    for _, k in ipairs(type(kids) == "table" and kids or {}) do
      local id = ns.Num(k.mapID)
      if id and not seen[id] then seen[id] = true zoneMaps[#zoneMaps + 1] = id end
    end
  end
  for id in pairs(ns.WRITS and ns.WRITS.zones or {}) do
    if not seen[id] then seen[id] = true zoneMaps[#zoneMaps + 1] = id end
  end
  return zoneMaps
end

-- the map mark of a writ quest in the log: uiMap, x, y (0-100), how ("karte" or "wegpunkt"); nil without one
-- (18.11.2026, Daniel: 17 writs accepted, nothing found) second way: the quest's waypoint (C_QuestLog.GetNextWaypoint)
local function Pct(v) return math.floor(v * 1000 + 0.5) / 10 end
function Wr.FindPOI(quest)
  local QL = C_QuestLog
  if QL and QL.GetQuestsOnMap then
    for _, m in ipairs(ZoneMaps()) do
      local list = ns.Call(QL.GetQuestsOnMap, m)
      for _, q in ipairs(type(list) == "table" and list or {}) do
        if ns.Num(q.questID) == quest and q.x and q.y then return m, Pct(q.x), Pct(q.y), "karte" end
      end
    end
  end
  if QL and QL.GetNextWaypoint then
    local m, x, y = ns.Call(QL.GetNextWaypoint, quest)
    m = ns.Num(m)
    if m and type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then return m, Pct(x), Pct(y), "wegpunkt" end
  end
end

-- every writ quest in the log whose customer Profitdon does not know yet: its map mark kept
function Wr.ScanLog()
  local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and ns.Call(C_QuestLog.GetNumQuestLogEntries)
    or GetNumQuestLogEntries and ns.Call(GetNumQuestLogEntries)
  n = ns.Num(n) or 0
  local found, writs, how = 0, 0, {}
  ns.db.writPOI = type(ns.db.writPOI) == "table" and ns.db.writPOI or {}
  for i = 1, n do
    local q
    if C_QuestLog and C_QuestLog.GetInfo then
      local info = ns.Call(C_QuestLog.GetInfo, i)
      q = type(info) == "table" and not info.isHeader and ns.Num(info.questID) or nil
    elseif GetQuestLogTitle then
      q = ns.Num(select(8, ns.Call(GetQuestLogTitle, i)))
    end
    if q and Wr.Is(q) then writs = writs + 1 end
    if q and Wr.Is(q) and not ns.db.writPOI[q] then
      local m, x, y, way = Wr.FindPOI(q)
      if m then
        how[way] = (how[way] or 0) + 1
        ns.db.writPOI[q] = { m, x, y }
        found = found + 1
        ns.Fact("writPOI", ("%d auf Karte %d (%.1f, %.1f)"):format(q, m, x, y))
      end
    end
  end
  -- what the scan saw, for the diagnosis (ProfitdonDB.facts.writScan)
  ns.Fact("writScan", ("%d Questlog-Einträge, %d Writs, %d Zonenkarten, gefunden %d (Karte %d, Wegpunkt %d), bekannt %d"):format(n, writs,
    #ZoneMaps(), found, how.karte or 0, how.wegpunkt or 0, (function() local c = 0 for _ in pairs(ns.db.writPOI) do c = c + 1 end return c end)()))
  if found > 0 then
    ns.Print(("Writs: Abgabeort von %d Writ%s von der Karte gelernt."):format(found, found == 1 and "" or "s"))
    if ns.Refresh then ns.Refresh() end
  end
  return found
end

ns.On("QUEST_ACCEPTED", function() ns.After(1, function() ns.Try(Wr.ScanLog) end) end)
ns.On("QUEST_DETAIL", function() ns.Try(Wr.OnQuestDetail) end)
ns.On("QUEST_COMPLETE", function() ns.Try(Wr.OnQuestComplete) end)
ns.On("QUEST_TURNED_IN", function(_, quest) ns.Try(Wr.OnTurnedIn, quest) end)
