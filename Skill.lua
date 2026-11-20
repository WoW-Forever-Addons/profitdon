local _, ns = ...

---------------------------------------------------------------------------
-- Skilling a profession (Daniel 07.11.2026: "mit einem andren char alchi und ingi. das skillen ist sehr teuer ... welche
-- rezepte skillpunkte gibt und wieviel der Einkaufspreis für dieses rezept ist, mit option das auf die Einkaufsliste zu
-- setzen"; chosen: cost per skill point, every own character, a collected shopping list with a count; recipes not learned
-- yet with what learning costs: "rezeptkosten aus dem Ah wenn es Drops sind oder bei welchem händler man die kaufen kann und
-- für die rezepte beim lehrer anzeigen was das lernen kostet und bei wem").
--   characters: what Crafts.lua read for each of them (ProfitdonDB.crafts[char]: skills, known recipes), this realm
--   colours: Data/Recipes.lua green and grey are the client's TrivialSkillLineRankLow and High. Checked against the known
--     Classic bands (Light Armor Kit 30/45/60, Handstitched Leather Boots 40/55/70): Low is where a recipe turns yellow,
--     green starts halfway to grey. Orange up to yellow (a point every craft), then (grey - skill) / (grey - yellow).
--   per point: (mats - what the result brings back, the better of vendor and AH after the cut) / chance, plus learning
--     cost spread over the points the recipe gives until grey (or the skill cap)
--   learning: Data/Learn.lua (trainer cost and trainers with place, recipe item: vendor, Favor vendor, the AH, else the
--     known sources; (08.11.2026) Sk.Sources, Sk.SrcText, own recordings ProfitdonDB.recipeSrc)
--   the plan: ProfitdonDB.skillPlan = { { char, spell, runs }, ... }; the shopping list sums the mats of all entries
---------------------------------------------------------------------------
local Sk = {}
ns.Skill = Sk
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local looted, seenVendor = {}, {}   -- (08.11.2026) recipe sources noted this session

local function Crafts() return type(ns.db.crafts) == "table" and ns.db.crafts or {} end
local function Short(char) return (tostring(char):gsub("%-[^%-]*$", "")) end
Sk.Short = Short

-- the profession lines with recipes in the data
local HAS = {}
local function HasRecipes(prof)
  if HAS[prof] == nil then
    HAS[prof] = false
    for _, d in pairs(ns.CRAFTS or {}) do if d[1] == prof then HAS[prof] = true break end end
  end
  return HAS[prof]
end

-- own characters of this realm with a crafting profession read, the one logged in first
function Sk.Chars()
  local out, me, realm = {}, ns.Me(), "-" .. ns.Realm()
  for char, c in pairs(Crafts()) do
    if type(c) == "table" and type(c.skills) == "table" and (char == me or char:sub(-#realm) == realm) then
      for prof in pairs(c.skills) do if HasRecipes(prof) then out[#out + 1] = char break end end
    end
  end
  table.sort(out, function(a, b) if (a == me) ~= (b == me) then return a == me end return a < b end)
  return out
end

function Sk.Char()
  local want = ns.db.skillChar
  local list = Sk.Chars()
  for _, c in ipairs(list) do if c == want then return c end end
  return list[1] or ns.Me()
end
function Sk.SetChar(char) ns.db.skillChar = char Sk.sel = nil end

function Sk.Profs(char)
  local c = Crafts()[char]
  local out = {}
  for prof in pairs(type(c) == "table" and c.skills or {}) do if HasRecipes(prof) then out[#out + 1] = prof end end
  table.sort(out, function(a, b) return ns.Crafts.ProfName(a) < ns.Crafts.ProfName(b) end)
  return out
end

function Sk.Prof(char)
  local want = ns.db.skillProf and ns.db.skillProf[char]
  local list = Sk.Profs(char)
  for _, p in ipairs(list) do if p == want then return p end end
  return list[1]
end
function Sk.SetProf(char, prof)
  ns.db.skillProf = ns.db.skillProf or {}
  ns.db.skillProf[char] = prof
  Sk.sel = nil
end

-- rank and cap of a character's profession
function Sk.Rank(char, prof)
  local c = Crafts()[char]
  local s = type(c) == "table" and c.skills and c.skills[prof]
  if not s then return nil end
  return s[1] or 0, s[2] or 0, c.t
end

---------------------------------------------------------------------------
-- Colours and chances
---------------------------------------------------------------------------
local function Bands(r)
  local grey = r.grey or 0
  if grey <= 0 then return nil end
  local yellow = (r.green and r.green > 0 and r.green <= grey) and r.green or grey
  return yellow, floor((yellow + grey) / 2), grey
end

-- chance of a point at a skill level: 1 orange, less on yellow and green, 0 grey, nil when the bands are unknown
function Sk.Chance(r, rank)
  local yellow, _, grey = Bands(r)
  if not yellow then return nil end
  if rank >= grey then return 0 end
  if rank < yellow then return 1 end
  -- (Daniel 16.11.2026, Bild Legacy "Working Overtime" 5/5: "Increases your chance to gain a skill increase ... by 20%")
  -- read with the other Legacy talents (Crafts.lua ReadLegacy); counted as 20 % more of the chance (75 % becomes 90 %),
  -- never over a point every craft. Whether the game adds 20 points instead is not measured.
  local C = ns.Crafts
  local more = C and C.LegacyPct and C.LegacyPct("Working Overtime") or 0
  return min(1, (grey - rank) / (grey - yellow) * (1 + more / 100))
end

function Sk.Color(r, rank)
  local yellow, green, grey = Bands(r)
  if not yellow then return nil end
  if rank >= grey then return "grey" end
  if rank >= green then return "green" end
  if rank >= yellow then return "yellow" end
  return "orange"
end
Sk.HEX = { orange = "ffff8040", yellow = "ffffff00", green = "ff40bf40", grey = "ff808080" }
Sk.WORD = { orange = "Orange", yellow = "Gelb", green = "Grün", grey = "Grau" }

-- crafts expected from rank until the recipe is grey or the cap is reached, and the points they give
function Sk.ToGrey(r, rank, cap)
  local _, _, grey = Bands(r)
  if not grey then return 0, 0 end
  local stop = min(grey, cap or grey)
  local n, pts = 0, 0
  for s = rank, stop - 1 do
    local c = Sk.Chance(r, s)
    if not c or c <= 0 then break end
    n, pts = n + 1 / c, pts + 1
  end
  return ceil(n - 1e-9), pts
end

---------------------------------------------------------------------------
-- Learning a recipe
-- (08.11.2026, Daniel: "viele rezepte der berufe steht forever rezept quelle unbekannt ... ziel ist alle zu kennen und woher,
-- ohne dass du falsche angaben machst"; chosen: Classic claims shown with "(Classic-Daten, in Forever ungeprüft)", Profitdon
-- records where recipe items come from). Sources: Data/Learn.lua LEARN_SRC (tools/profitdon/recipe_sources.py: ATT
-- Forever, ForeverDB Favor vendors, CMaNGOS) and ProfitdonDB.recipeSrc (own recordings below). Nothing is guessed: what
-- no source knows says "Quelle noch unbekannt" (until 07.11. a recipe item nobody sold was called a drop).
---------------------------------------------------------------------------
local function MapName(map)
  local i = map and map > 0 and C_Map and ns.Call(C_Map.GetMapInfo, map)
  return type(i) == "table" and i.name or nil
end

local CLASSIC = " |cff9d9d9d(Classic-Daten, in Forever ungeprüft)|r"
local OWN = " |cff9d9d9d(selbst gesehen)|r"
Sk.CLASSIC = CLASSIC

local function Place(p)
  if type(p) == "number" then return MapName(p) end
  if p == "World Drops" then return nil end
  return p ~= "" and p or nil
end

local function Side()
  return (ns.Call(UnitFactionGroup, "player") == "Horde") and "H" or "A"
end

-- the text of one source { kind, name, place, origin, extra }
function Sk.SrcText(x)
  local k, name, place, extra = x[1], x[2] ~= "" and x[2] or nil, Place(x[3]), x[5]
  local at = place and (" (" .. place .. ")") or ""
  local t
  if k == "v" then t = "Händler " .. (name or "?") .. at
  elseif k == "f" then
    t = "Favor-Händler " .. (name or "?") .. at
    local n = extra and tonumber(tostring(extra):match("^(%d+)"))
    if n then t = t .. ", " .. n .. " Gunst" end
  elseif k == "q" then t = "Quest " .. (name and ("\"" .. name .. "\"") or "?") .. at
  elseif k == "d" then t = "Drop von " .. (name or "?") .. (place and at or (extra and (" (" .. extra .. ")") or ""))
  elseif k == "b" then t = "Boss " .. (name or "?") .. at
  elseif k == "o" then t = "Objekt " .. (name or "?") .. at
  elseif k == "c" then t = "aus " .. (name or "?")
  elseif k == "s" then t = "mit dem Beruf"
  else -- z
    t = place and ("Drop in " .. place) or ("Weltdrop" .. (extra and (" (" .. extra .. ")") or ""))
  end
  if x[4] == "c" then t = t .. CLASSIC elseif x[4] == "s" then t = t .. OWN end
  return t
end

-- every known source of a spell: own recordings of its recipe item first, then the shipped data; Favor vendors of the
-- other faction left out
function Sk.Sources(spell, item)
  local out, seen, side = {}, {}, Side()
  local function add(x)
    if x[1] == "f" and x[5] then
      local s = tostring(x[5]):match(":(%a)$")
      if s and s ~= side then return end
    end
    local key = (x[1] or "") .. "|" .. tostring(x[2]) .. "|" .. tostring(x[3])
    if not seen[key] then seen[key] = true out[#out + 1] = x end
  end
  local mine = item and type(ns.db.recipeSrc) == "table" and ns.db.recipeSrc[item]
  if type(mine) == "table" then
    for _, r in pairs(mine) do
      if type(r) == "table" then add({ r[1], r[3] or "", r[4] or 0, "s", r[6] }) end
    end
  end
  for _, x in ipairs(ns.LEARN_SRC and ns.LEARN_SRC[spell] or {}) do add(x) end
  return out
end

local KIND = { v = "vendor", f = "favor", q = "quest", d = "drop", b = "drop", o = "drop", z = "drop", c = "drop", s = "start" }

local function Trainer(d, classic, spell)
  local fac = Side()
  local here = C_Map and ns.Call(C_Map.GetBestMapForUnit, "player")
  local best, names
  for k = 4, #d do
    local n = ns.LEARN_NPC and ns.LEARN_NPC[d[k]]
    if n and (n[5] == fac or n[5] == "" or n[5] == "N") then
      names = names or {}
      local zone = MapName(n[2])
      names[#names + 1] = n[1] .. (zone and (" (" .. zone .. ")") or "")
      if not best or (here and n[2] == here and best[2] ~= here) then best = n end
    end
  end
  local cost = (d[2] or -1) >= 0 and d[2] or nil
  -- (10.11.2026) what a trainer asked for (ReadTrainer) wins over the data
  local seen = spell and type(ns.db.learnAt) == "table" and ns.db.learnAt[spell]
  if type(seen) == "table" and tonumber(seen[2]) then cost = tonumber(seen[2]) end
  local where = best and (best[1] .. (MapName(best[2]) and (", " .. MapName(best[2])) or "")) or nil
  return { kind = "trainer", cost = cost, text = "Lehrer" .. (where and (": " .. where) or "") .. (classic and CLASSIC or ""),
    where = where, all = names, npc = best, classic = classic }
end

-- { kind = "trainer"|"vendor"|"favor"|"ah"|"drop"|"quest"|"start"|"?", cost, short (column text without a gold cost),
--   text, where, item, all (lines for the tooltip), classic }
function Sk.Learn(spell)
  local d = ns.LEARN and ns.LEARN[spell]
  if not d then return { kind = "?", text = "Quelle noch unbekannt" } end
  local src = d[1]
  if src == "t" then return Trainer(d, nil, spell) end
  local item = (d[3] or 0) > 0 and d[3] or nil
  local srcs = Sk.Sources(spell, item)
  local all = {}
  for i, x in ipairs(srcs) do if i <= 6 then all[i] = Sk.SrcText(x) end end
  local first = srcs[1]
  local function Res(t) t.all = t.all or (#all > 0 and all or nil) t.item = item return t end
  if item and src ~= "q" and src ~= "s" then
    local vp, _, limited, vname = ns.Prices.VendorBuy(item)
    if vp then
      return Res({ kind = "vendor", cost = vp, text = "Rezept beim Händler" .. (vname and (" " .. vname) or "") .. (limited and " (begrenzt)" or "") })
    end
    for _, x in ipairs(srcs) do
      if x[1] == "f" then
        local n = x[5] and tonumber(tostring(x[5]):match("^(%d+)"))
        -- (08.11.2026) in gold: the Favor at the price of the cheapest Waylaid Crate (Favor.lua)
        local gpf = n and ns.Favor and ns.Favor.GoldPerFavor()
        return Res({ kind = "favor", favor = n, cost = gpf and n * gpf or nil, short = n and (n .. " Gunst") or "Gunst",
          text = "Rezept beim " .. Sk.SrcText(x) .. (gpf and (", etwa " .. ns.Money(n * gpf) .. " über Favor-Kisten") or "") })
      end
    end
    local ah = ns.AHPrice and ns.AHPrice(item)
    if ah then return Res({ kind = "ah", cost = ah, text = "Rezept im AH" }) end
    if first then
      return Res({ kind = KIND[first[1]] or "?", classic = first[4] == "c", text = "Rezept: " .. Sk.SrcText(first) .. ", gerade nicht im AH" })
    end
    return Res({ kind = "?", text = "Rezept-Gegenstand, Quelle noch unbekannt" })
  end
  if src == "q" then
    local q
    for _, x in ipairs(srcs) do if x[1] == "q" then q = x break end end
    return Res({ kind = "quest", text = q and Sk.SrcText(q) or "Quest" })
  elseif src == "s" then return Res({ kind = "start", cost = 0, text = "mit dem Beruf" })
  end
  -- c/f/p: Forever data without a source
  if (src == "c" or src == "p") and (d[2] or -2) >= 0 then return Res(Trainer(d, true)) end
  if first then
    return Res({ kind = KIND[first[1]] or "?", cost = first[1] == "s" and 0 or nil, classic = first[4] == "c", text = Sk.SrcText(first) })
  end
  return Res({ kind = "?", text = (src == "f" and "Forever-Rezept, " or "") .. "Quelle noch unbekannt" })
end

---------------------------------------------------------------------------
-- Own recordings of recipe items (08.11.2026): looted (from a mob, an object, a container) or seen at a vendor (also the
-- Favor vendors). ProfitdonDB.recipeSrc[item]["<kind>|<id>"] = { kind, id, name, uiMap, n, extra }; store/ collects the
-- file on the play days and tools/profitdon/recipe_sources.py ships them as origin "s".
---------------------------------------------------------------------------
local function IsRecipe(id) return ns.ItemClass(id) == 9 end
Sk.IsRecipe = IsRecipe

local function Note(item, kind, id, name, extra)
  ns.db.recipeSrc = type(ns.db.recipeSrc) == "table" and ns.db.recipeSrc or {}
  local t = ns.db.recipeSrc[item] or {}
  ns.db.recipeSrc[item] = t
  local key = kind .. "|" .. tostring(id or 0)
  local map = C_Map and ns.Call(C_Map.GetBestMapForUnit, "player") or 0
  local r = t[key]
  if r then
    r[5] = (r[5] or 1) + 1
    if name and name ~= "" then r[3] = name end
    if extra then r[6] = extra end
  else
    t[key] = { kind, id or 0, name or "", ns.Num(map) or 0, 1, extra }
  end
end
Sk.Note = Note

-- the loot window: every recipe item with where it came from (once per item and source)
function Sk.ReadLoot()
  local n = ns.Num(ns.Call(GetNumLootItems)) or 0
  for i = 1, n do
    local link = ns.Call(GetLootSlotLink, i)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if id and IsRecipe(id) then
      local guid = GetLootSourceInfo and ns.Call(GetLootSourceInfo, i)
      local kind, num = "z", 0
      if type(guid) == "string" then
        local typ = guid:match("^(%a+)")
        num = tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or 0
        kind = (typ == "Creature" or typ == "Vehicle") and "d" or typ == "GameObject" and "o" or typ == "Item" and "c" or "z"
      end
      local name
      if kind == "d" and ns.Call(UnitGUID, "target") == guid then name = ns.Call(UnitName, "target") end
      if kind == "c" or kind == "z" then num = 0 end
      local once = id .. "|" .. tostring(guid)
      if not looted[once] then
        looted[once] = true
        Note(id, kind, num, name)
      end
    end
  end
end

-- the vendor window: every recipe item it sells, for gold or another cost (Favor)
function Sk.ReadMerchant()
  local n = ns.Num(ns.Call(GetMerchantNumItems)) or 0
  if n == 0 then return end
  local guid = ns.Call(UnitGUID, "npc")
  local npc = type(guid) == "string" and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or 0
  local name = ns.Call(UnitName, "npc") or ""
  for i = 1, n do
    local link = ns.Call(GetMerchantItemLink, i)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if id and IsRecipe(id) then
      local info = C_MerchantFrame and ns.Call(C_MerchantFrame.GetItemInfo, i)
      local price, ext
      if type(info) == "table" then price, ext = ns.Num(info.price), info.hasExtendedCost
      elseif GetMerchantItemInfo then
        local _, _, p, _, _, _, _, e = ns.Call(GetMerchantItemInfo, i)
        price, ext = ns.Num(p), e
      end
      if not seenVendor[npc .. "|" .. id] then
        seenVendor[npc .. "|" .. id] = true
        if ext and GetMerchantItemCostItem then
          local _, value = ns.Call(GetMerchantItemCostItem, i, 1)
          Note(id, "f", npc, name, (ns.Num(value) or 0) .. ":" .. Side())
        else
          Note(id, "v", npc, name, price)
        end
      end
    end
  end
end
ns.On("LOOT_READY", function() ns.Try(Sk.ReadLoot) end)
ns.On("MERCHANT_SHOW", function() ns.Try(Sk.ReadMerchant) end)

-- (Daniel 10.11.2026, Greater Discolored Healing Potion offered at Alchemy 150: "Mitschreiben") the profession trainer's
-- window: the skill each recipe asks for and its cost, ProfitdonDB.learnAt[spell] = { level, cost }; Crafts.lua takes the
-- level over the data. The service is matched by the item it makes (its name where several recipes make it), else by name.
local byName
local function ServiceSpell(i, name)
  local Cr = ns.Crafts
  local link = GetTrainerServiceItemLink and ns.Call(GetTrainerServiceItemLink, i)
  local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
  if item then
    local hit, n = nil, 0
    for spell, d in pairs(ns.CRAFTS or {}) do
      if d[3] == item then
        n = n + 1
        if n == 1 or (name and Cr.SpellName(spell) == name) then hit = spell end
      end
    end
    if n == 1 or (hit and name and Cr.SpellName(hit) == name) then return hit end
  end
  if type(name) ~= "string" or name == "" then return nil end
  if not byName then
    byName = {}
    for spell in pairs(ns.CRAFTS or {}) do
      local s = Cr.SpellName(spell)
      if s then byName[s] = byName[s] == nil and spell or false end
    end
  end
  return byName[name] or nil
end
function Sk.ReadTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceSkillReq) then return end
  local n = ns.Num(ns.Call(GetNumTrainerServices)) or 0
  local changed = false
  for i = 1, n do
    local name = ns.Call(GetTrainerServiceInfo, i)
    local _, level = ns.Call(GetTrainerServiceSkillReq, i)
    level = ns.Num(level)
    local spell = level and level > 0 and ServiceSpell(i, name)
    if spell then
      local cost = GetTrainerServiceCost and ns.Num((ns.Call(GetTrainerServiceCost, i))) or nil
      ns.db.learnAt = type(ns.db.learnAt) == "table" and ns.db.learnAt or {}
      local old = ns.db.learnAt[spell]
      if type(old) ~= "table" or old[1] ~= level or (cost and old[2] ~= cost) then
        ns.db.learnAt[spell] = { level, cost or (type(old) == "table" and old[2]) or nil }
        changed = true
      end
    end
  end
  if changed then
    ns.Crafts.Forget()
    if ns.Refresh then ns.Refresh() end
  end
end
ns.On("TRAINER_SHOW", function() ns.Try(Sk.ReadTrainer) end)
ns.On("TRAINER_UPDATE", function() ns.Try(Sk.ReadTrainer) end)

---------------------------------------------------------------------------
-- The rows
---------------------------------------------------------------------------
-- every recipe of the profession that still gives points at the character's rank: cheapest point first; second value:
-- notes { noBands = n, noPrice = n, capped = bool }
function Sk.Rows(char, prof)
  local out, st = {}, { noBands = 0, noPrice = 0 }
  local rank, cap = Sk.Rank(char, prof)
  if not rank then return out, st end
  local c = Crafts()[char]
  local known = type(c.known) == "table" and c.known or {}
  local stop = (cap and cap > rank) and cap or nil
  st.capped = not stop
  local Cr = ns.Crafts
  Cr.cache = {}
  Cr.assumeChar = char ~= ns.Me() and char or nil
  local ok, err = pcall(function()
    for spell, d in pairs(ns.CRAFTS or {}) do
      if d[1] == prof then
        local r = Cr.Recipe(spell)
        -- (10.11.2026) not learned yet: only from the skill it surely can be learned at (Crafts.lua Cr.LearnGate)
        local can = r and (known[spell] or Cr.LearnGate(r) <= rank)
        local chance = can and Sk.Chance(r, rank)
        if can and chance == nil then st.noBands = st.noBands + 1 end
        if chance and chance > 0 then
          local crafts, pts = Sk.ToGrey(r, rank, stop)
          local e = { r = r, spell = spell, id = r.item, known = known[spell] and true or false, chance = chance,
            color = Sk.Color(r, rank), crafts = crafts, pts = pts, char = char, prof = prof }
          if not e.known then
            e.learn = Sk.Learn(spell)
            if r.learnMax then e.learn.text = e.learn.text .. " (Lernstufe noch unbekannt, spätestens " .. r.learnMax .. ")" end
          end
          local v = Cr.Value(r)
          if v then
            e.v, e.cost = v, v.cost
            -- (Durchsicht 15.11.2026) what comes back over the AH is the expected value (sale rate, lost deposit: v.ahExp),
            -- as the AH tab counts it; the price after the cut alone only without demand numbers
            local ahBack = v.ahExp or v.ahNet
            e.back = max(v.vendor or 0, ahBack or 0)
            e.per = (v.cost - e.back) / chance
            local lc = e.learn and e.learn.cost or 0
            local spread = lc > 0 and lc / max(1, pts) or 0
            e.perAll = e.per + spread
            -- (Daniel 08.11.2026: "zweigeteilt skillen pro punkt an händler skillen pro punkt an ah") each way on its own
            e.perV = (v.cost - (v.vendor or 0)) / chance + spread
            if ahBack then e.perA = (v.cost - ahBack) / chance + spread end
          else
            st.noPrice = st.noPrice + 1
          end
          out[#out + 1] = e
        end
      end
    end
  end)
  Cr.cache, Cr.assumeChar = nil, nil
  if not ok then error(err, 0) end
  table.sort(out, function(a, b)
    if (a.perAll == nil) ~= (b.perAll == nil) then return a.perAll ~= nil end
    if a.perAll and a.perAll ~= b.perAll then return a.perAll < b.perAll end
    return a.spell < b.spell
  end)
  return out, st
end

---------------------------------------------------------------------------
-- The plan (the shopping list of the skilling)
---------------------------------------------------------------------------
local function Plan()
  ns.db.skillPlan = type(ns.db.skillPlan) == "table" and ns.db.skillPlan or {}
  return ns.db.skillPlan
end
Sk.Plan = Plan

function Sk.InPlan(char, spell)
  for i, p in ipairs(Plan()) do if p[1] == char and p[2] == spell then return p, i end end
end

function Sk.Add(char, spell, runs)
  runs = max(1, floor(tonumber(runs) or 1))
  local p = Sk.InPlan(char, spell)
  if p then p[3] = runs else table.insert(Plan(), { char, spell, runs }) end
end

function Sk.Remove(char, spell)
  local _, i = Sk.InPlan(char, spell)
  if i then table.remove(Plan(), i) end
end

function Sk.Clear() ns.db.skillPlan = {} end

-- the entries for Crafts.ShoppingList: { r, runs, char }
function Sk.PlanEntries()
  local out = {}
  for _, p in ipairs(Plan()) do
    local r = ns.Crafts.Recipe(p[2])
    if r then out[#out + 1] = { r = r, runs = p[3], char = p[1] } end
  end
  return out
end
