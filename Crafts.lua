local _, ns = ...

---------------------------------------------------------------------------
-- Crafting (PROFITDON_PLAN.md "Umfang" 1 and 2; reading and the reagent rule from Golddon's Crafts.lua, only the
-- character logged in): Yeny's crafts for the vendor (Rough Dynamite: mats 30c, vendor 60c for two) and crafts to
-- disenchant (Gloves of Meditation).
--   reading: the spell check over Data/Recipes.lua at login and on skill changes, the profession window when it opens
--     (ProfitdonDB.crafts[me] = { skills = { [prof] = { rank, max } }, known = { [spell] = true } })
--   a reagent costs (Daniel 05.11. for Golddon): 1. an unlimited vendor (when not dearer than the AH), 2. made from its
--     own recipe when this character has the profession at the recipe's level, the cheaper of that and the AH, 3. the AH
--   per recipe: mats, vendor price of the result, profit and ROI; beside it what the AH pays after the cut (as Yeny's
--     sheet: NPC-Gewinn, ROI, AH netto, AH-Gewinn)
--   "Alle herstellen": as many as the mats in the bags and the room in the bags allow, one CraftRecipe call
--   shopping list: the mats for the chosen number of crafts less what the bags hold, a made reagent with its own mats
---------------------------------------------------------------------------
local Cr = {}
ns.Crafts = Cr

local PROFS = {
  [171] = { 2259, "Alchemy", "Alchimie" }, [164] = { 2018, "Blacksmithing", "Schmiedekunst" },
  [202] = { 4036, "Engineering", "Ingenieurskunst" }, [165] = { 2108, "Leatherworking", "Lederverarbeitung" },
  [197] = { 3908, "Tailoring", "Schneiderei" }, [185] = { 2550, "Cooking", "Kochkunst" },
  [129] = { 3273, "First Aid", "Erste Hilfe" }, [186] = { 2575, "Mining", "Bergbau" },
  [333] = { 7411, "Enchanting", "Verzauberkunst" },
}
Cr.PROFS = PROFS

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = ns.Call(C_Spell.GetSpellInfo, id)
    if type(i) == "table" then return i.name end
  end
  return (ns.Call(GetSpellInfo, id))
end
Cr.SpellName = SpellName
function Cr.ProfName(id)
  local p = PROFS[id]
  if not p then return tostring(id) end
  return SpellName(p[1]) or p[3]
end

local parsed = {}
Cr.FOREVER_SPELL = 1229000 -- (tools/build_recipes.py FOREVER_SPELL_MIN) the first spell id of Forever's new recipes
-- the skill from which a recipe surely can be learned: the known level, for an unsure Forever recipe its yellow start
function Cr.LearnGate(r) return r.learnMax or r.learn or 0 end
-- "a:1,b:2" in item order, to compare reagent lists from the data and the game
local function SortedReag(s)
  local t = {}
  for item, n in tostring(s or ""):gmatch("(%d+):(%d+)") do t[#t + 1] = { tonumber(item), tonumber(n) } end
  table.sort(t, function(a, b) return a[1] < b[1] end)
  for i, x in ipairs(t) do t[i] = x[1] .. ":" .. x[2] end
  return table.concat(t, ",")
end
function Cr.Recipe(spell)
  local r = parsed[spell]
  if r ~= nil then return r or nil end
  local d = ns.CRAFTS and ns.CRAFTS[spell]
  local x = ns.db and ns.db.craftExtra and ns.db.craftExtra[spell]
  -- (08.11.2026) what the game's window said wins: reagents, result, the most and the least a craft makes
  if d and x and (x[4] or "") ~= "" then
    local mx = x[5] or x[3] or d[4]
    d = { d[1], d[2], x[2] or d[3], mx, x[4], d[6], d[7], (x[3] and x[3] < mx) and x[3] or nil }
  elseif d and d[5] == "" and x then d = { d[1], d[2], d[3], d[4], x[4], d[6], d[7], d[8] } end
  if not d and x then d = { x[1], 0, x[2], x[5] or x[3], x[4], 0, 0, x[3] } end
  if not d then parsed[spell] = false return nil end
  -- (Daniel 07.11.2026, Ez-Thro Dynamite: "das rezept gibt 1-3 aus nicht immer 3") count is the most a craft makes, min
  -- the least (Data/Recipes.lua field 8, only where it differs); values and planned crafts use the average (Cr.Avg)
  local mn = tonumber(d[8])
  -- (Daniel 10.11.2026, Greater Discolored Healing Potion offered at Alchemy 150) the client says 1 for every Forever
  -- recipe, so a Forever recipe without a learn level in the data is unsure: what a trainer showed wins (Skill.lua
  -- ReadTrainer, ProfitdonDB.learnAt[spell] = { level, cost }); until then it counts as learnable only from its yellow
  -- start (r.learnMax; no trainer teaches a recipe later than that)
  local seen = ns.db and type(ns.db.learnAt) == "table" and ns.db.learnAt[spell]
  seen = type(seen) == "table" and tonumber(seen[1]) or nil
  local learn = seen or d[2] or 0
  r = { spell = spell, prof = d[1], learn = learn, item = d[3], count = d[4], green = d[6], grey = d[7], reag = {},
    min = (mn and mn > 0 and mn < (d[4] or 1)) and mn or nil, learnSeen = seen and true or nil }
  if learn == 0 and not seen and spell >= Cr.FOREVER_SPELL and (r.green or 0) > 1 then r.learnMax = r.green end
  for item, n in tostring(d[5] or ""):gmatch("(%d+):(%d+)") do r.reag[#r.reag + 1] = { tonumber(item), tonumber(n) } end
  parsed[spell] = r
  return r
end
-- (Daniel 08.11.2026, Heavy Dynamite 1-5: "wie ist die chancenverteilung?", Wahl: mitschreiben) a recipe with a range is
-- counted per craft: ProfitdonDB.yields[spell] = { n = crafts, sum = made, c = { [made] = crafts } }. From YIELD_MIN crafts the
-- measured average counts; before that the middle of least and most (the classic roll: every number as likely).
local YIELD_MIN = 30
Cr.YIELD_MIN = YIELD_MIN
function Cr.Yields(spell)
  local y = ns.db and ns.db.yields and ns.db.yields[spell]
  return type(y) == "table" and y or nil
end
function Cr.RecordYield(spell, made)
  ns.db.yields = type(ns.db.yields) == "table" and ns.db.yields or {}
  local y = ns.db.yields[spell] or { n = 0, sum = 0, c = {} }
  y.n, y.sum = y.n + 1, y.sum + made
  y.c[made] = (y.c[made] or 0) + 1
  ns.db.yields[spell] = y
  Cr.ResetMakes()
  return y
end

---------------------------------------------------------------------------
-- (Daniel 16.11.2026, chat with Malte: "bei Kochen kannst du ja noch 50% extra result skillen ... im legacy"; "Muss
-- Profitdon auch noch mit einberechnen die 50%"; gewählt "Auslesen plus messen") Forever's Legacy tree runs on
-- Blizzard's traits (C_Traits, LEGACY_TREE_PROFESSIONS_ID 1187 in the client's API documentation). Its talent
-- "Master Chef" gives a chance of one more result when cooking (on the web 10 % a rank up to 50 %; the sources differ):
-- the rank is read from the tree, the percent from the talent's own text of that rank (rank x 10 when the text has
-- none). Read at login and when the traits change; /profit diag line legacyChef says what was found.
---------------------------------------------------------------------------
Cr.LEGACY_TREE, Cr.CHEF_NAME, Cr.CHEF_RANK_PCT, Cr.COOKING = 1187, "Master Chef", 10, 185
-- percent a rank when a talent's text has no number (Daniel's tooltip 16.11.2026: Bartering 2/2 = 10 %)
Cr.LEGACY_RANK_PCT = { ["Master Chef"] = 10, ["Bartering"] = 5 }
-- (Daniel 16.11.2026, Bild Bartering 2/2 "Reduces the gold price of items from all vendors by 10%.": "das kann er ja auch
-- mit einrechnen, wenn geskillt") the percent of a Legacy talent as last read (0 without)
function Cr.LegacyPct(name)
  local t = ns.db and ns.db.legacy and ns.db.legacy[name]
  return type(t) == "table" and tonumber(t.pct) or 0
end
function Cr.ReadLegacy()
  local T = rawget(_G, "C_Traits")
  if type(T) ~= "table" or type(T.GetConfigIDByTreeID) ~= "function" then return nil, "kein C_Traits" end
  local cfg = ns.Call(T.GetConfigIDByTreeID, Cr.LEGACY_TREE)
  if not cfg then return nil, "kein Legacy-Baum (Konfiguration)" end
  local nodes = ns.Call(T.GetTreeNodes, Cr.LEGACY_TREE)
  if type(nodes) ~= "table" then return nil, "keine Knoten" end
  local seen, all = {}, {}
  for _, node in ipairs(nodes) do
    local info = ns.Call(T.GetNodeInfo, cfg, node)
    if type(info) == "table" then
      local rank = ns.Num(info.activeRank) or ns.Num(info.currentRank) or 0
      local eids = {}
      if type(info.activeEntry) == "table" and info.activeEntry.entryID then eids[1] = info.activeEntry.entryID end
      for _, e in ipairs(type(info.entryIDs) == "table" and info.entryIDs or {}) do eids[#eids + 1] = e end
      for _, eid in ipairs(eids) do
        local entry = ns.Call(T.GetEntryInfo, cfg, eid)
        local def = type(entry) == "table" and entry.definitionID and ns.Call(T.GetDefinitionInfo, entry.definitionID)
        local spell = type(def) == "table" and ns.Num(def.spellID)
        local name = type(def) == "table" and def.overrideName
        if (not name or name == "") and spell then
          local si = C_Spell and C_Spell.GetSpellInfo and ns.Call(C_Spell.GetSpellInfo, spell)
          name = type(si) == "table" and si.name or (GetSpellInfo and ns.Call(GetSpellInfo, spell))
        end
        if type(name) == "string" and name ~= "" then
          seen[#seen + 1] = name
          -- (16.11.2026) every talent of the tree with its rank and the percent of its text (Bartering: "Reduces the gold
          -- price of items from all vendors by 10%." at rank 2/2)
          if not all[name] or rank > (all[name].rank or 0) then
            local pct
            if rank > 0 then
              local text = T.GetTraitDescription and ns.Call(T.GetTraitDescription, eid, rank)
              if type(text) ~= "string" and spell and C_Spell and C_Spell.GetSpellDescription then text = ns.Call(C_Spell.GetSpellDescription, spell) end
              pct = type(text) == "string" and tonumber(text:match("(%d+)%%")) or nil
            end
            local per = Cr.LEGACY_RANK_PCT[name] or 0
            local from = pct and "Talenttext" or ("Rang x " .. per)
            all[name] = { rank = rank, max = ns.Num(info.maxRanks), pct = rank > 0 and (pct or rank * per) or 0, from = from }
          end
        end
      end
    end
  end
  local chef = all[Cr.CHEF_NAME]
  if chef then return chef, nil, all end
  return { rank = 0, pct = 0, from = "nicht im Baum" }, ("%d Talente gelesen, kein %s"):format(#seen, Cr.CHEF_NAME), all
end
local function LegacyNow()
  local ok, res, why, all = pcall(Cr.ReadLegacy)
  if not ok then ns.Fact("legacyChef", "Fehler: " .. tostring(res)) return end
  if not res then ns.Fact("legacyChef", why or "nicht lesbar") return end
  local oldBarter = Cr.LegacyPct("Bartering") + 1000 * Cr.LegacyPct("Working Overtime")
  if type(all) == "table" then
    ns.db.legacy = {}
    local parts = {}
    for name, t in pairs(all) do
      ns.db.legacy[name] = { rank = t.rank, pct = t.pct }
      if t.rank > 0 then parts[#parts + 1] = ("%s %d%s (%d %%)"):format(name, t.rank, t.max and ("/" .. t.max) or "", t.pct) end
    end
    table.sort(parts)
    ns.Fact("legacy", #parts > 0 and table.concat(parts, ", ") or "nichts geskillt")
    if Cr.LegacyPct("Bartering") + 1000 * Cr.LegacyPct("Working Overtime") ~= oldBarter and ns.Touch then ns.Touch() end
  end
  local old = ns.db.legacyChef
  ns.db.legacyChef = { rank = res.rank, pct = res.pct, t = time() }
  ns.Fact("legacyChef", ("%s Rang %d%s: %d %% Extra-Ergebnis beim Kochen (%s)%s"):format(Cr.CHEF_NAME, res.rank,
    res.max and ("/" .. res.max) or "", res.pct, res.from, why and (", " .. why) or ""))
  if not (old and old.pct == res.pct) then
    if Cr.ResetMakes then Cr.ResetMakes() end
    if ns.Touch then ns.Touch() end
  end
end
ns.On("PLAYER_LOGIN", function() ns.After(6, LegacyNow) end)
ns.On("TRAIT_CONFIG_UPDATED", function() ns.After(1, LegacyNow) end)
ns.LegacyNow = LegacyNow -- (tests)
-- the extra result of a recipe's profession in percent (0 without)
function Cr.BonusPct(r)
  if not (r and r.prof == Cr.COOKING) then return 0 end
  local c = ns.db and ns.db.legacyChef
  return type(c) == "table" and tonumber(c.pct) or 0
end

-- (same) what a recipe really gives, also one of fixed count: the products created (the game's "You create" lines, any
-- number of them a craft) against the crafts cast, per recipe in ProfitdonDB.yieldsAll[spell] = { casts, units, b }. b:
-- the bonus it was measured with; another bonus starts it anew. From YIELD_MIN crafts the measured average counts.
local lastCast = {} -- [item] = { spell, at }
function Cr.MeasuredAll(r)
  local y = ns.db and ns.db.yieldsAll and ns.db.yieldsAll[r.spell]
  if type(y) ~= "table" or (y.b or 0) ~= Cr.BonusPct(r) or (y.casts or 0) < YIELD_MIN then return nil, y end
  return y.units / y.casts, y
end
function Cr.CountCast(spell)
  local r = Cr.Recipe(spell)
  if not (r and r.item and r.item > 0) or r.min then return end
  ns.db.yieldsAll = type(ns.db.yieldsAll) == "table" and ns.db.yieldsAll or {}
  local b = Cr.BonusPct(r)
  local y = ns.db.yieldsAll[spell]
  if type(y) ~= "table" or (y.b or 0) ~= b then y = { casts = 0, units = 0, b = b } ns.db.yieldsAll[spell] = y end
  y.casts = y.casts + 1
  lastCast[r.item] = { spell = spell, at = GetTime() }
end
function Cr.CountCreated(item, n)
  local c = lastCast[item]
  if not (c and GetTime() - c.at < 10) then return end
  local y = ns.db.yieldsAll and ns.db.yieldsAll[c.spell]
  if type(y) == "table" then
    y.units = y.units + n
    if y.casts == YIELD_MIN then if Cr.ResetMakes then Cr.ResetMakes() end end
  end
end

-- what one craft makes on average (1 to 3: 2, or measured), and the text of it ("1-3" or "3")
-- (16.11.2026) a fixed count: measured when there are enough crafts, else the count plus the Legacy bonus
function Cr.Avg(r)
  local c = math.max(1, r and r.count or 1)
  if r and r.min then
    local y = Cr.Yields(r.spell)
    if y and y.n >= YIELD_MIN then return y.sum / y.n end
    return (r.min + c) / 2
  end
  if r then
    local m = Cr.MeasuredAll(r)
    if m then return m end
    -- (Daniel 16.11.2026, the first round with Master Chef 5/5 measured: Seasoned Wolf Kabob 744 from 214 crafts = 3.48
    -- with 3 a craft; three recipes of 1 a craft 239 from 159 = 1.50) the bonus is one more piece at that chance, not
    -- that share of the count on top (3 would have become 4.5)
    return c + Cr.BonusPct(r) / 100
  end
  return c
end
-- (Daniel 13.11.2026: "beim Dynamit herstellen ... Engpässe jetzt eher gegen Ende ... wenn zu oft mal 4 oder 5 kommen")
-- what n crafts give at most in practice: the average plus two and a half spreads of the sum (the yields of single
-- crafts scatter), so a run of high yields still finds room; a fixed count gives exactly n * count
function Cr.Upper(r, n)
  local avg = Cr.Avg(r)
  if n <= 0 then return 0 end
  -- (16.11.2026) a bonus result now and then: room for its spread too (one more of the count, chance p)
  if not (r and r.min) then
    local p = Cr.BonusPct(r) / 100
    if p <= 0 then return avg * n end
    local c = math.max(1, r and r.count or 1)
    return math.min(avg * n + 2.5 * math.sqrt(n * p * (1 - p)), (c + 1) * n)
  end
  local var
  local y = Cr.Yields(r.spell)
  if y and y.n >= YIELD_MIN then
    local sq = 0
    for k, c in pairs(y.c) do sq = sq + (tonumber(k) or 0) ^ 2 * c end
    var = math.max(0, sq / y.n - (y.sum / y.n) ^ 2)
  else
    local w = math.max(1, r.count or 1) - r.min + 1
    var = (w * w - 1) / 12
  end
  return math.min(avg * n + 2.5 * math.sqrt(n * var), math.max(1, r.count or 1) * n)
end
-- a tooltip line about the yield: measured share of every count, or the estimate and how far the counting is
function Cr.YieldLine(r)
  if not (r and r.min) then return nil end
  local y = Cr.Yields(r.spell)
  local function Num(v) return (("%.1f"):format(v)):gsub("%.", ",") end
  if y and y.n >= YIELD_MIN then
    local parts = {}
    for k = r.min, r.count do parts[#parts + 1] = ("%d: %d %%"):format(k, math.floor((y.c[k] or 0) * 100 / y.n + 0.5)) end
    return { ("Ertrag gemessen (%d Mal)"):format(y.n), "Schnitt " .. Num(y.sum / y.n) .. " (" .. table.concat(parts, ", ") .. ")" }
  end
  return { "Ertrag geschätzt", ("Schnitt %s, jede Zahl gleich oft; gemessen %d von %d"):format(Num((r.min + r.count) / 2), y and y.n or 0, YIELD_MIN) }
end

local Mine -- defined below (the crafts of the logged-in character)
-- counting (Daniel 08.11.2026: 50 crafts, 43 counted, too few 1s and too many 2s): no longer the bags before and after a cast
-- (a quick next craft started before the bags reported, two crafts became one), but the game's own line for every craft,
-- "You create: %sx%d." (LOOT_ITEM_CREATED_SELF_MULTIPLE, one piece LOOT_ITEM_CREATED_SELF) in CHAT_MSG_LOOT, read in the
-- client's language like Questdon reads it. The product goes to the known recipe with a range that makes it.
local function ToPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local out, i = { "^" }, 1
  while i <= #fmt do
    local c = fmt:sub(i, i)
    if c == "%" then
      local conv, e = fmt:match("^%%%d+%$[%-%d%.]*([sdif])()", i)
      if not conv then conv, e = fmt:match("^%%[%-%d%.]*([sdif])()", i) end
      if conv then
        out[#out + 1] = conv == "s" and "(.-)" or "(%d+)"
        i = e
      elseif fmt:sub(i + 1, i + 1) == "%" then
        out[#out + 1] = "%%"
        i = i + 2
      else return nil end
    else
      out[#out + 1] = c:find("[%^%$%(%)%.%[%]%*%+%-%?]") and ("%" .. c) or c
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  return table.concat(out)
end
local patterns = {}
local function Created(msg)
  for _, g in ipairs({ "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
    local fmt = rawget(_G, g)
    local p = patterns[g]
    if not p or p.fmt ~= fmt then p = { fmt = fmt, pat = ToPattern(fmt) } patterns[g] = p end
    if p.pat then
      local link, n = msg:match(p.pat)
      if link then return link, tonumber(n) or 1 end
    end
  end
end
-- the known recipe with a range that makes this item
local function RangeRecipe(item)
  for spell in pairs(Mine().known) do
    local r = Cr.Recipe(spell)
    if r and r.min and r.item == item then return r end
  end
end
ns.On("CHAT_MSG_LOOT", function(_, msg)
  if type(msg) ~= "string" then return end
  local link, n = Created(msg)
  local item = link and tonumber(link:match("item:(%d+)"))
  if item and n then Cr.CountCreated(item, n) end -- (16.11.2026) every recipe's real yield
  if item and n and ns.RecipeLog then ns.RecipeLog.Created(item, n) end
  local r = item and RangeRecipe(item)
  if not (r and n and n >= r.min and n <= r.count) then return end
  local s = Cr.RecordYield(r.spell, n)
  ns.Fact("yieldLast", ("%s: %d Stück (%d Mal gezählt)"):format(ns.ItemInfo(item) or item, n, s.n))
end)
-- the counts made by the bags until 08.11.2026 are dropped (two crafts could count as one)
ns.OnInit(function()
  if ns.db.yieldsV ~= 2 then ns.db.yields, ns.db.yieldsV = nil, 2 end
end)
-- cast time (Daniel 08.11.2026: "Wenn wir jetzt noch eine Casttime hätten ... kommulierte Casttime, wenn mehrere Schritte
-- notwendig sind"): seconds of one craft from the game (C_Spell.GetSpellInfo castTime, GetSpellInfo), the real cast once
-- measured (UnitCastingInfo at UNIT_SPELLCAST_START, ProfitdonDB.castTimes[spell]) wins
function Cr.CastTime(spell)
  local m = ns.db and ns.db.castTimes and ns.db.castTimes[spell]
  if m then return m end
  local ms
  if C_Spell and C_Spell.GetSpellInfo then
    local i = ns.Call(C_Spell.GetSpellInfo, spell)
    if type(i) == "table" then ms = i.castTime end
  end
  if not ms and GetSpellInfo then ms = select(4, ns.Call(GetSpellInfo, spell)) end
  ms = tonumber(ms)
  if ms and ms > 0 then return ms / 1000 end
end
ns.On("UNIT_SPELLCAST_START", function(_, unit, _, spell)
  if unit ~= "player" or not (spell and ns.CRAFTS and ns.CRAFTS[spell] or Cr.Recipe(spell or 0)) then return end
  local _, _, _, s, e = ns.Call(UnitCastingInfo, "player")
  s, e = tonumber(s), tonumber(e)
  if s and e and e > s then
    ns.db.castTimes = ns.db.castTimes or {}
    ns.db.castTimes[spell] = math.floor((e - s) / 100 + 0.5) / 10
  end
end)
-- the seconds of one craft with the crafts of the reagents made here on the way (as the price counts them: made when
-- that is the cheapest way), and those steps { id, crafts, each }; nil when a cast time is not known
function Cr.Time(r, depth)
  depth = depth or 0
  local t = r and Cr.CastTime(r.spell)
  if not t then return nil end
  local steps = {}
  for _, g in ipairs(r.reag) do
    local _, src, _, _, via = Cr.ReagentUnit(g[1])
    if src == "craft" and via and depth < 3 then
      local sub = Cr.Time(via, depth + 1)
      if not sub then return nil end
      local n = g[2] / Cr.Avg(via)
      t = t + n * sub
      steps[#steps + 1] = { id = g[1], crafts = n, each = sub }
    end
  end
  return t, steps
end
-- "3 s", "7,5 s", "2:05 min", "1:10 h"
function Cr.Dur(sec)
  if not sec then return "?" end
  if sec < 59.95 then
    local s = (sec >= 10 or math.abs(sec - math.floor(sec + 0.5)) < 0.05) and tostring(math.floor(sec + 0.5)) or (("%.1f"):format(sec):gsub("%.", ","))
    return s .. " s"
  end
  local s = math.floor(sec + 0.5)
  if s < 3600 then return ("%d:%02d min"):format(math.floor(s / 60), s % 60) end
  return ("%d:%02d h"):format(math.floor(s / 3600), math.floor(s / 60) % 60)
end

function Cr.YieldText(r)
  local c = math.max(1, r and r.count or 1)
  if r and r.min then return r.min .. "-" .. c end
  return tostring(c)
end
function Cr.Forget() parsed = {} Cr.ResetMakes() end

---------------------------------------------------------------------------
-- Reading the character
---------------------------------------------------------------------------
function Mine()
  ns.db.crafts = type(ns.db.crafts) == "table" and ns.db.crafts or {}
  local me = ns.Me()
  local c = ns.db.crafts[me]
  if type(c) ~= "table" then c = {} ns.db.crafts[me] = c end
  c.skills = type(c.skills) == "table" and c.skills or {}
  c.known = type(c.known) == "table" and c.known or {}
  return c
end
Cr.Mine = Mine

function Cr.MySkill(prof)
  if not ns.db then return nil end
  local s = Mine().skills[prof]
  return s and s[1] or nil
end

local function ReadSkills()
  local list = {}
  if type(GetProfessions) == "function" then
    local idx = { ns.Call(GetProfessions) }
    for i = 1, 5 do
      if idx[i] then
        local _, _, rank, max, _, _, line = ns.Call(GetProfessionInfo, idx[i])
        line = ns.Num(line)
        if line and PROFS[line] then list[#list + 1] = { line, ns.Num(rank) or 0, ns.Num(max) or 0 } end
      end
    end
  end
  return list
end

local function Knows(id) return (ns.Call(IsPlayerSpell, id) or ns.Call(IsSpellKnown, id)) and true or false end

-- the spell check: only adds (only a window removes)
local last = -100
function Cr.Read(force)
  if not ns.db then return 0 end
  if not force and GetTime() - last < 20 then return 0 end
  last = GetTime()
  local skills = ReadSkills()
  if #skills == 0 then return 0 end
  local c = Mine()
  local found = 0
  for _, s in ipairs(skills) do
    c.skills[s[1]] = { s[2], s[3] }
    for spell, d in pairs(ns.CRAFTS or {}) do
      if d[1] == s[1] and d[2] <= s[2] and Knows(spell) then
        if not c.known[spell] then found = found + 1 end
        c.known[spell] = true
      end
    end
  end
  c.t = time()
  ns.Fact("craftRead", ("%d Berufe, %d neue Rezepte"):format(#skills, found))
  if found > 0 then ns.Touch() end -- new recipes: the kept lists are worked out anew
  if found > 0 and ns.Refresh then ns.Refresh() end
  return found
end

-- the open profession window: the whole profession with a learned flag (Forever), new recipes the data lacks are kept
-- (Daniel 16.11.2026: "ruckelig ... crafting auf, habe gecrafted") the game says TRADE_SKILL_LIST_UPDATE after every
-- craft; each time every recipe of the profession was read with its whole schematic, then the main window drawn anew.
-- The full reading now runs once a session per profession, again when the recipes, the learned ones or the skill
-- change; in between only the cooldowns of the recipes that have one. The window is drawn when something changed.
local readSig, castSeen = {}, {}
-- a recipe just made is read with the cooldowns in between (a cooldown the data lacks shows after the first craft)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spell)
  if unit == "player" and ns.Num(spell) then
    castSeen[ns.Num(spell)] = true
    if Cr.Recipe(ns.Num(spell)) then
      Cr.CountCast(ns.Num(spell))
      if ns.RecipeLog then ns.RecipeLog.Cast(ns.Num(spell)) end -- (16.11.2026) what each product brought
    end
  end
end)
local function ReadWindow()
  if not ns.db then return end
  local c = Mine()
  local T = C_TradeSkillUI
  if not (T and type(T.GetAllRecipeIDs) == "function") then return end
  if ns.Call(T.IsTradeSkillLinked) or ns.Call(T.IsTradeSkillGuild) or ns.Call(T.IsNPCCrafting) then return end
  local info = ns.Call(T.GetBaseProfessionInfo)
  local prof = type(info) == "table" and ns.Num(info.professionID)
  local ids = ns.Call(T.GetAllRecipeIDs)
  if not (prof and PROFS[prof] and type(ids) == "table") then return end
  ns.db.craftExtra = ns.db.craftExtra or {}
  local learned, changed = {}, false
  local nLearned0 = 0
  for _, id in ipairs(ids) do
    local ri = ns.Call(T.GetRecipeInfo, id)
    if type(ri) == "table" and ri.learned == true then learned[id] = true nLearned0 = nLearned0 + 1 end
  end
  local sig = table.concat({ #ids, nLearned0, type(info) == "table" and tostring(info.skillLevel) or "?", tostring(info and info.maxSkillLevel) }, ":")
  local full = readSig[prof] ~= sig
  readSig[prof] = sig
  for _, id in ipairs(ids) do
    if learned[id] and (full or castSeen[id] or Cr.HasCooldown(id) or (type(c.cd) == "table" and c.cd[id])) then
      -- (Daniel 11.11.2026: "Mitlernen") a recipe seen on a cooldown of a minute or more is kept as one for good
      -- (GetRecipeCooldown: seconds left, isDayCooldown; C_Spell.GetSpellCooldown: { duration }; both unchecked on Forever)
      if not (ns.db.craftCD and ns.db.craftCD[id]) then
        local left, day = ns.Call(T.GetRecipeCooldown, id)
        local sc = C_Spell and ns.Call(C_Spell.GetSpellCooldown, id)
        local dur = type(sc) == "table" and ns.Num(sc.duration) or 0
        if day == true or (ns.Num(left) or 0) >= 60 or dur >= 60 then
          ns.db.craftCD = ns.db.craftCD or {}
          ns.db.craftCD[id] = time()
          changed = true
        end
      end
      -- (Daniel 14.11.2026: "kann profitdon mein cooldowns z.b. für arkanitbarren auslesen?") when the cooldown of a
      -- learned recipe ends, per character (c.cd[spell] = time it is ready; 0: seen ready, never seen running). A recipe
      -- seen ready keeps the old end, so the note at login still names what was used before.
      do
        local left = ns.Num((ns.Call(T.GetRecipeCooldown, id)))
        if left and left > 0 then
          c.cd = type(c.cd) == "table" and c.cd or {}
          c.cd[id] = time() + math.floor(left + 0.5)
        elseif Cr.HasCooldown(id) then
          c.cd = type(c.cd) == "table" and c.cd or {}
          if not c.cd[id] or c.cd[id] > time() then c.cd[id] = c.cd[id] and time() or 0 end
        end
      end
      -- (Daniel 08.11.2026, Rough Dynamite: "er stellt da ja garantiert 2 stück her und braucht je 1 leinenstoff und 1
      -- powder", the data had Classic's 2 powder) every learned recipe: what the game's window says wins over the shipped
      -- data (Forever changed some), kept in craftExtra only where it differs; until then only recipes without reagents
      local d = ns.CRAFTS and ns.CRAFTS[id]
      local sch = full and ns.Call(T.GetRecipeSchematic, id, false)
      if type(sch) == "table" and (ns.Num(sch.outputItemID) or 0) > 0 then
        local reag = {}
        for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
          local r = slot.reagents and slot.reagents[1]
          if r and ns.Num(r.itemID) and ns.Num(slot.quantityRequired) then reag[#reag + 1] = r.itemID .. ":" .. slot.quantityRequired end
        end
        local out, qmin = ns.Num(sch.outputItemID), ns.Num(sch.quantityMin) or 1
        local qmax = math.max(qmin, ns.Num(sch.quantityMax) or qmin)
        local game = SortedReag(table.concat(reag, ","))
        local same = d and #reag > 0 and SortedReag(d[5]) == game and d[3] == out and (d[4] or 1) == qmax
          and (tonumber(d[8]) or d[4] or 1) == qmin
        local old = ns.db.craftExtra[id]
        if #reag > 0 and not same then
          if not (old and old[2] == out and old[3] == qmin and old[5] == qmax and SortedReag(old[4]) == game) then
            ns.db.craftExtra[id] = { prof, out, qmin, table.concat(reag, ","), qmax }
            parsed[id] = nil
            changed = true
          end
        elseif same and old then
          ns.db.craftExtra[id] = nil
          parsed[id] = nil
          changed = true
        end
      end
    end
  end
  if not next(learned) then return end
  for spell in pairs(c.known) do local r = Cr.Recipe(spell) if r and r.prof == prof and not learned[spell] then c.known[spell] = nil end end
  for spell in pairs(learned) do if Cr.Recipe(spell) then c.known[spell] = true end end
  -- (Daniel 14.11.2026, the transmutes Arcanite, Gold and Truesilver Bar learned but not in the lists) what this reading
  -- saw, for /profit diag: all recipes of the window, learned, learned without data, and what the game says of the transmutes
  do
    local nLearned, noData = 0, {}
    for spell in pairs(learned) do
      nLearned = nLearned + 1
      if not Cr.Recipe(spell) and #noData < 8 then noData[#noData + 1] = tostring(spell) end
    end
    local inList = {}
    for _, id in ipairs(ids) do inList[id] = true end
    local probe = {}
    for _, id in ipairs({ 17187, 11479, 11480 }) do
      local ri = ns.Call(T.GetRecipeInfo, id)
      probe[#probe + 1] = ("%d %s/%s/%s"):format(id, inList[id] and "Liste" or "fehlt", type(ri) == "table" and tostring(ri.learned) or "keine Info",
        c.known[id] and "gemerkt" or "nicht gemerkt")
    end
    ns.Fact("craftWin", ("Beruf %d: %d Rezepte im Fenster, %d gelernt, ohne Daten: %s; %s"):format(prof, #ids, nLearned,
      #noData > 0 and table.concat(noData, ",") or "keine", prof == 171 and table.concat(probe, ", ") or ""))
  end
  if type(info) == "table" and ns.Num(info.skillLevel) then c.skills[prof] = { ns.Num(info.skillLevel), ns.Num(info.maxSkillLevel) or 0 } end
  c.t = time()
  if changed then Cr.ResetMakes() end
  castSeen = {}
  if full or changed then
    ns.Touch()
    if ns.RefreshSoon then ns.RefreshSoon() elseif ns.Refresh then ns.Refresh() end
  end
end
Cr.ReadWindow = function() return ns.Perf("Berufsfenster lesen", ReadWindow) end
Cr.ReadWindowReset = function() readSig = {} end -- (tests)

local winPending
local function WindowSoon()
  if winPending then return end
  winPending = true
  ns.WhenIdle("Berufsfenster", function() winPending = nil Cr.ReadWindow() end, 0.6)
end
ns.On("PLAYER_LOGIN", function() ns.After(8, function() Cr.Read(true) end) end)
ns.On("SKILL_LINES_CHANGED", function() ns.After(2, function() Cr.Read() end) end)
ns.On("NEW_RECIPE_LEARNED", function() ns.After(1, function() Cr.Read(true) end) end)
ns.On("TRADE_SKILL_SHOW", WindowSoon)
ns.On("TRADE_SKILL_LIST_UPDATE", WindowSoon)

-- the items the character's recipes make
function Cr.Products()
  local out = {}
  if not ns.db then return out end
  for spell in pairs(Mine().known) do local r = Cr.Recipe(spell) if r and r.item and r.item > 0 then out[r.item] = true end end
  return out
end

---------------------------------------------------------------------------
-- Prices of reagents
---------------------------------------------------------------------------
local makes
function Cr.ResetMakes() makes = nil end
function Cr.MakesItem(id)
  if not makes then
    makes = {}
    for spell in pairs(ns.CRAFTS or {}) do
      local r = Cr.Recipe(spell)
      if r and r.item and r.item > 0 and #r.reag > 0 then makes[r.item] = makes[r.item] or {} table.insert(makes[r.item], r) end
    end
  end
  return makes[id]
end

-- (Daniel 11.11.2026, Gold Core: "1000 iron bar gekauft, nur um dann festzustellen, dass ich vorher iron zu gold
-- transmutieren soll. 1. habe ich das rezept nicht, 2. hat es abklingzeit") recipes with a cooldown never make a reagent
-- on the way: one craft an hour or a day is no source for a run. ns.CRAFT_CD (Data/Recipes.lua, the client's cooldown
-- tables: the transmutes, Mooncloth, Refined Scale of Onyxia) and what the profession window showed on cooldown
-- (ProfitdonDB.craftCD, ReadWindow; "Mitlernen", for recipes of a build newer than the data).
function Cr.HasCooldown(spell)
  return (ns.CRAFT_CD and ns.CRAFT_CD[spell] or ns.db and ns.db.craftCD and ns.db.craftCD[spell]) and true or false
end
-- (Durchsicht 11.11.2026) the cooldown for the rows: seconds from the data, true when only seen in the profession window
-- (length unknown), nil without one; Cr.CooldownText: "Abklingzeit 1:00 h" / "Abklingzeit"
function Cr.CooldownSec(spell)
  local sec = ns.CRAFT_CD and tonumber(ns.CRAFT_CD[spell])
  if sec and sec > 0 then return sec end
  return Cr.HasCooldown(spell) or nil
end
function Cr.CooldownText(spell)
  local cd = Cr.CooldownSec(spell)
  if not cd then return nil end
  return cd == true and "Abklingzeit" or ("Abklingzeit " .. Cr.Dur(cd))
end
-- (Daniel 14.11.2026) the cooldown left: seconds (0: ready) and the character it was read for (this one first, else
-- another of the realm who knows the recipe); nil when no profession window showed it yet
function Cr.CooldownLeft(spell)
  local me, realm = ns.Me(), "-" .. ns.Realm()
  local all = ns.db and type(ns.db.crafts) == "table" and ns.db.crafts or {}
  local function of(char)
    local c = all[char]
    local e = type(c) == "table" and type(c.cd) == "table" and tonumber(c.cd[spell])
    if e then return math.max(0, e - time()), char end
  end
  local left, who = of(me)
  if left then return left, who end
  for char in pairs(all) do
    if char ~= me and char:sub(-#realm) == realm then
      left, who = of(char)
      if left then return left, who end
    end
  end
end
-- "1 T 22 h", "3:20 h", "12:00 min"
function Cr.Left(sec)
  if sec >= 86400 then return ("%d T %d h"):format(math.floor(sec / 86400), math.floor(sec % 86400 / 3600)) end
  return Cr.Dur(sec)
end
-- "bereit" / "bereit in 1 T 22 h", with the name when it is another character's
function Cr.CooldownState(spell)
  local left, who = Cr.CooldownLeft(spell)
  if not left then return nil end
  local txt = left > 0 and ("bereit in " .. Cr.Left(left)) or "bereit"
  if who ~= ns.Me() and ns.Skill and ns.Skill.Short then txt = txt .. " (" .. ns.Skill.Short(who) .. ")" end
  return txt, left
end
-- at login: the cooldowns of the realm's characters that ran out (seen running once)
function Cr.ReadyNote()
  local realm, me, out = "-" .. ns.Realm(), ns.Me(), {}
  for char, c in pairs(ns.db and type(ns.db.crafts) == "table" and ns.db.crafts or {}) do
    if type(c) == "table" and type(c.cd) == "table" and (char == me or char:sub(-#realm) == realm) then
      for spell, e in pairs(c.cd) do
        local r = tonumber(e) and e > 0 and e <= time() and Cr.Recipe(spell)
        if r then out[#out + 1] = ("%s (%s)"):format(ns.ItemInfo(r.item) or ("Item " .. r.item), ns.Skill and ns.Skill.Short and ns.Skill.Short(char) or char) end
      end
    end
  end
  table.sort(out)
  return #out > 0 and ("Abklingzeit vorbei: " .. table.concat(out, ", ")) or nil
end
ns.On("PLAYER_LOGIN", function() ns.After(10, function() local t = Cr.ReadyNote() if t then ns.Print(t) end end) end)
-- this character has learned the recipe (the rows say when a step on the way is only assumed, Berufe)
function Cr.IKnow(spell) return Mine().known[spell] and true or false end

local function CanMake(r)
  if Cr.HasCooldown(r.spell) then return false end
  -- (Berufe) the profession looked at counts as had at its top
  if Cr.assume and r.prof == Cr.assume then return true end
  -- the recipe itself must be learned, the skill alone is not enough (until 11.11.2026 it was)
  -- (Durchsicht der Rechnungen 15.11.2026) Cr.assumeChar: the skill plan of another character counts with that
  -- character's recipes (it counted the steps the logged-in one can make)
  local who = Cr.assumeChar and type(ns.db.crafts) == "table" and ns.db.crafts[Cr.assumeChar]
  if type(who) == "table" then return type(who.known) == "table" and who.known[r.spell] and true or false end
  if Mine().known[r.spell] then return true end
  -- (Daniel 19.11.2026, own lists: "wenn ich es selber herstellen kann oder einer meiner Chars") any character of the realm
  return Cr.anyChar and Cr.WhoMakes(r.spell) ~= nil or false
end
Cr.CanMake = CanMake
-- the character that knows a recipe: this one first, else another of the realm; nil: none
function Cr.WhoMakes(spell)
  if Mine().known[spell] then return ns.Me() end
  local realm = "-" .. ns.Realm()
  for char, c in pairs(ns.db and type(ns.db.crafts) == "table" and ns.db.crafts or {}) do
    if type(c) == "table" and type(c.known) == "table" and c.known[spell] and char:sub(-#realm) == realm then return char end
  end
end

-- (Daniel 22.11.2026, Bild Einkaufsliste Sealed Apprentice Crate, 188 Copper Modulator und 376 Bolts selbst hergestellt:
-- "wäre es nicht besser ich kaufe die modulatoren und könnte in der zeit essen craften zum verkauf?"; gewählt "Ja,
-- automatisch") time has a price: the gold an hour of crafting for the vendor brings (the best Gold/h of the list
-- "Für Händler", kept per realm when that list is worked out). A reagent is made only when made plus the gold of its
-- casting time stays at or under the AH price. Option timeValue off, or no Gold/h known yet: gold alone as before.
function Cr.GoldHour()
  if not ns.Opt("timeValue") then return nil end
  local h = type(ns.db.goldHour) == "table" and ns.db.goldHour[ns.Realm()]
  if type(h) == "table" and (h.g or 0) > 0 and time() - (h.t or 0) < 3 * 86400 then return h.g, h end
end
function Cr.SetGoldHour(rows)
  local best
  for _, v in ipairs(rows or {}) do
    local g = v.runH and v.runH.gain
    if g and g > 0 and (not best or g > best.g) then best = { g = g, spell = v.r.spell, item = v.r.item } end
  end
  ns.db.goldHour = type(ns.db.goldHour) == "table" and ns.db.goldHour or {}
  if best then best.t = time() end
  ns.db.goldHour[ns.Realm()] = best
end
-- the gold of sec seconds of casting
function Cr.TimeGold(sec)
  local g = Cr.GoldHour()
  return (g and sec and sec > 0) and math.floor(sec * g / 3600 + 0.5) or 0
end

-- unit, src ("vendor", "craft", "ah"), AH quantity, cheapest AH offer, recipe (craft), seconds of casting for one unit
-- made (its steps on the way included), and when bought for the time: the gold one unit made would save and its seconds
local function Unit(id, depth, seen)
  local low, med, qty = ns.Prices.AH(id)
  local vu = ns.Prices.VendorUnit(id)
  -- (Daniel 06.11.2026: "wieso hat er so falsche preise?", the median of all offers was far over the cheapest) a run buys about
  -- 20: the average of the cheapest 20 units
  local ah = low and ns.Prices.Buy(id, 20) or nil
  if vu and (not ah or vu <= ah) then return vu, "vendor", nil, low end
  local list = depth < 3 and Cr.MakesItem(id)
  if list then
    seen[id] = true
    local best, via, bestSec, bestEff
    for _, r in ipairs(list) do
      local sum = CanMake(r) and 0 or nil
      local sec = sum and (Cr.CastTime(r.spell) or 0) or 0
      for _, g in ipairs(sum and r.reag or {}) do
        if seen[g[1]] then sum = nil break end
        local u, s2, _, _, _, t2 = Unit(g[1], depth + 1, seen)
        if not u then sum = nil break end
        sum = sum + u * g[2]
        if s2 == "craft" then sec = sec + (t2 or 0) * g[2] end
      end
      if sum then
        local avg = Cr.Avg(r)
        local each, s1 = math.ceil(sum / avg), sec / avg
        local eff = each + Cr.TimeGold(s1)
        if not bestEff or eff < bestEff then best, via, bestSec, bestEff = each, r, s1, eff end
      end
    end
    seen[id] = nil
    if best and (not ah or bestEff <= ah) then return best, "craft", nil, low, via, bestSec end
    -- cheaper made in gold, dearer once the time counts: bought, the row says what making would save
    if best and ah and best < ah then return ah, "ah", qty, low, nil, nil, { save = ah - best, sec = bestSec, via = via } end
  end
  if ah then return ah, "ah", qty, low end
  if vu then return vu, "vendor", nil, low end
  return nil
end

function Cr.ReagentUnit(id)
  local c = Cr.cache
  if c and c[id] then return unpack(c[id], 1, 7) end
  local res = { Unit(id, 0, {}) }
  if c then c[id] = res end
  return unpack(res, 1, 7)
end

-- one recipe: mats cost, vendor price, profit and ROI at the vendor, what the AH brings after the cut, the disenchant value
-- of the result; nil and the reason ("data", "price")
function Cr.Value(r)
  local P, D = ns.Prices, ns.Deals
  if not (r and r.item and r.item > 0) or #r.reag == 0 then return nil, "data" end
  local cost, parts = 0, {}
  for _, g in ipairs(r.reag) do
    local unit, src, qty, low, via = Cr.ReagentUnit(g[1])
    if not unit then return nil, "price" end
    cost = cost + unit * g[2]
    parts[#parts + 1] = { id = g[1], n = g[2], unit = unit, src = src, qty = qty, low = low, via = via }
  end
  local count = Cr.Avg(r)
  local time, steps = Cr.Time(r)
  local sell, sellSrc = P.Sell(r.item)
  local vendor = math.floor((sell or 0) * count + 0.5)
  local low = P.Low(r.item)
  local ahNet = low and D.AfterCut(math.floor(low * count + 0.5), P.Cut()) or nil
  -- sellGuess: the vendor price is the data file's (Classic), the game has not said its own yet
  local v = { r = r, id = r.item, sellGuess = sellSrc == "data" or nil, cost = cost, parts = parts, vendor = vendor, profit = vendor - cost, roi = D.ROI(vendor - cost, cost),
    time = time, steps = steps, ahNet = ahNet, ahProfit = ahNet and ahNet - cost or nil, ahRoi = ahNet and D.ROI(ahNet - cost, cost) or nil }
  -- (Daniel 14.11.2026, demand) the honest AH value of one craft: the lower of the average sale price and the cheapest offer,
  -- sold with the sale rate; what stays goes to the vendor less the lost deposit. Without an offer the sale average alone.
  local dem, exp = Cr.AhExpect(r, vendor, low, count)
  v.dem = dem
  if exp then
    v.ahExp, v.ahExpProfit, v.ahExpRoi = exp, exp - cost, D.ROI(exp - cost, cost)
    if not v.ahNet then
      v.ahNet = D.AfterCut(math.floor(dem.avg * count + 0.5), P.Cut())
      v.ahProfit, v.ahRoi, v.ahFromAvg = v.ahNet - cost, D.ROI(v.ahNet - cost, cost), true
    end
  end
  local g = ns.DE.Group(r.item)
  if g then
    local ev = ns.DE.Value(g)
    if ev then v.group, v.de = g, math.floor(ev * count + 0.5) v.deProfit = v.de - cost v.deRoi = D.ROI(v.deProfit, cost) end
  end
  return v
end

-- demand of the result and the expected AH value of one craft (nil without demand numbers or without any price)
function Cr.AhExpect(r, vendor, low, count)
  local P, D = ns.Prices, ns.Deals
  local dem = ns.Market and ns.Market.Demand and ns.Market.Demand(r.item) or nil
  if not dem then return nil end
  count = count or Cr.Avg(r)
  if vendor == nil then vendor = math.floor((P.Sell(r.item) or 0) * count + 0.5) end
  if low == nil then low = P.Low(r.item) end
  local price = dem.avg and low and math.min(dem.avg, low) or dem.avg or low
  if not price then return dem end
  local net = D.AfterCut(math.floor(price * count + 0.5), P.Cut())
  local dep = vendor > 0 and D.Deposit(vendor, 1, (ns.POST_HOURS and ns.POST_HOURS[ns.Opt("postDur")]) or 24) or 0
  local back = math.max(0, vendor - dep)
  return dem, math.floor(dem.rate * net + (1 - dem.rate) * back + 0.5)
end

-- the crafts for the AH the demand allows (dem.qty pieces), nil without demand numbers
function Cr.AhCrafts(r, dem)
  if not (dem and dem.qty) then return nil end
  return math.ceil(dem.qty / math.max(1, Cr.Avg(r)))
end

-- the rows: "vendor" (crafts for the vendor), "ah" (for the auction house) or "de" (crafts to disenchant), best profit first; with
-- ProfitdonDB.craftAll also the ones under the minimum profit
function Cr.Rows(mode)
  Cr.cache = {}
  local st = { known = 0, price = 0, data = 0, below = 0, noDE = 0, noAH = 0 }
  local ok, rows = pcall(function()
    local out = {}
    local all = ns.db.craftAll
    for spell in pairs(Mine().known) do
      st.known = st.known + 1
      local r = Cr.Recipe(spell)
      local v, why = r and Cr.Value(r)
      if not v then st[why or "data"] = (st[why or "data"] or 0) + 1
      else
        -- (Daniel 07.11.2026) "ah": crafts for the auction house, against the cheapest offer of the result after the cut
        local profit
        if mode == "de" then profit = v.deProfit elseif mode == "ah" then profit = v.ahExpProfit or v.ahProfit else profit = v.profit end
        local cost = v.cost
        if not profit and mode == "ah" then st.noAH = st.noAH + 1
        elseif not profit then st.noDE = st.noDE + 1
        elseif not (all or ns.Deals.Worth(profit, cost)) then st.below = st.below + 1
        -- (Daniel 16.11.2026: "paar sekunden da dann weg") a gain that rests on a guessed vendor price waits for the game's
        elseif mode ~= "ah" and mode ~= "de" and v.sellGuess and profit > 0 then st.wait = (st.wait or 0) + 1
        else
          v.mode, v.show = mode, profit
          v.maxCraft = Cr.MaxCraft(v)
          -- (Daniel 18.11.2026) the run of 30 min and two of them (Gold/h), for the vendor list
          if mode == "vendor" then Cr.RunsOf(v) end
          out[#out + 1] = v
        end
      end
    end
    table.sort(out, function(a, b) if a.show ~= b.show then return a.show > b.show end return a.r.spell < b.r.spell end)
    -- (22.11.2026) the best Gold/h of this character's vendor list is the price of an hour of crafting (Cr.GoldHour)
    if mode == "vendor" then Cr.SetGoldHour(out) end
    return out
  end)
  Cr.cache = nil
  if not ok then error(rows, 0) end
  -- second value: the count of recipes lacking a price (as before), third: why the others are not shown
  return rows, st.price, st
end

-- (Daniel 16.11.2026: "wann brauchen wir eine neuberechnung überhaupt") a list of the craft tabs worked out every recipe's
-- value at every redraw, a click on a row too. It is kept for the same scan, live offers, data version (bags, recipes,
-- options), switch "all" and minute (cooldowns end), and taken again.
local memo = {}
local function Memo(name, f)
  return function(...)
    local st = ns.Prices.Store()
    local a1, a2 = ...
    local key = table.concat({ tostring(a1), tostring(a2), st and st.t or 0, ns.liveVer or 0, ns.dataVer or 0,
      ns.db.craftAll and 1 or 0, math.floor(time() / 60), tostring(Cr.assumeChar) }, "|")
    local m = memo[name]
    if not ns.bagCacheOff and m and m.key == key then return m[1], m[2], m[3] end
    local r1, r2, r3 = f(...)
    memo[name] = { key = key, r1, r2, r3 }
    return r1, r2, r3
  end
end
Cr.Rows = Memo("Rows", Cr.Rows)
Cr.MemoReset = function() memo = {} end

-- how many crafts the bags allow: mats in the bags, room for the results (free slots times the stack, and the room in
-- the stacks there are)
-- (Daniel 16.11.2026, Bild Herstellfenster "Mats für 103 von 380" with mats for 300: "ich müsste doch mehr als 100
-- herstellen können?") second and third value: what the mats alone allow, and the free normal slots when the room is
-- what limits (nil otherwise); the window says which of the two it is
function Cr.MaxCraft(v)
  local bags = ns.Bags()
  local n = math.huge
  for _, g in ipairs(v.r.reag) do n = math.min(n, math.floor((bags[g[1]] or 0) / g[2])) end
  if n == math.huge then n = 0 end
  local byMats, roomFree = n, nil
  local stack = ns.Stack(v.r.item) or 1
  local have = bags[v.r.item] or 0
  local part = (stack > 1 and have % stack > 0) and (stack - have % stack) or 0
  -- (Daniel 12.11.2026: "stellt nur wenige dynamit her, weil er denkt der platz reicht nicht aus") a recipe with a
  -- range (Heavy Dynamite 1-5) counts with what one craft gives on average, not with its top; when the bags do fill,
  -- the game stops by itself and the button shows the rest
  local per = math.max(1, Cr.Avg(v.r))
  -- (12.11.2026) the results go into the normal bags only: their free slots, and what the mats free there
  local free, normal = ns.NormalBags()
  -- (Daniel 12.11.2026: "kann jetzt nicht mehr craften, weil 3 rauskämen" ... "da muss ein platz mehr luft sein") the game
  -- wants room for the top of a range before the craft: one normal slot stays free
  free = math.max(0, free - 1)
  -- (Daniel 11.11.2026, Bild: "Erst 174× Heavy Blasting Powder" with 754 Heavy Stone in the bags) the mats used up free
  -- their slots as the crafting goes: k crafts fit when the results find room in the free slots and the emptied ones
  local function fits(k)
    local freed = 0
    for _, g in ipairs(v.r.reag) do
      -- (Daniel 16.11.2026: "gehe davon aus, dass reagenzien aus der reagent bag zuletzt genommen werden", his
      -- assumption, not measured) the mats go from the normal bags first: their slots empty before the reagent bag's
      local inNormal = normal[g[1]] and normal[g[1]][1] or 0
      freed = freed + ns.FreedNormal(normal, g[1], inNormal - k * g[2], ns.Stack(g[1]) or 1)
    end
    return Cr.Upper(v.r, k) <= (free + freed) * stack + part
  end
  -- (Daniel 16.11.2026, Bild: 320 Bronze Framework, bags full of their mats, "kein platz in den taschen. lag es an mir?")
  -- room is needed all the way, not only at the end: the mats free their slots only as their stacks empty, the first
  -- craft needs its room before anything is freed. Only the end was checked (320 fitted once all mats were gone), so the
  -- button said 320 with no slot to start. Now checked from the first craft on, in steps of about half a result stack
  -- (at most 64 looks); where it fails, the count is narrowed down there.
  if n > 0 then
    local step = math.max(1, math.floor(stack / per / 2), math.ceil(n / 64))
    local good, bad, k = 0, nil, 1
    while k <= n do
      if not fits(k) then bad = k break end
      good = k
      if k == n then break end
      k = math.min(n, k + step)
    end
    if bad then
      local lo, hi = good, bad
      while hi - lo > 1 do
        local m = math.floor((lo + hi) / 2)
        if fits(m) then lo = m else hi = m end
      end
      n = lo
      roomFree = free + 1
    end
  end
  -- (Durchsicht 11.11.2026) a recipe on a cooldown is made once, whatever the bags hold
  if n > 1 and Cr.HasCooldown(v.r.spell) then n = 1 end
  return n, byMats, roomFree
end

-- (Daniel 12.11.2026: "40 freie plätze wieviel crafts soll ich einkaufen?" ... "hinweis wieviel man einkaufen kann wäre
-- gut") how many crafts the bags hold from buying to the end: the free slots and those the mats of the list already fill
-- (they are used up) must take every mat of the list at the start (a made step turns its mats into it, about the same
-- room) and the results at the end (the average yield). Returns n, and the names whose stack size the game has not said
-- yet (counted as 20, 1 for the result) or nil. Kept 5 s.
local roomCache = {}
function Cr.RoomCrafts(r)
  if not r then return nil end
  local free = ns.FreeSlots()
  local bags = ns.Bags()
  local sig = { r.spell, free }
  for _, g in ipairs(r.reag) do sig[#sig + 1] = bags[g[1]] or 0 end
  sig[#sig + 1] = bags[r.item] or 0
  local key = table.concat(sig, "|")
  local c = roomCache[r.spell]
  if c and c.key == key and GetTime() - c.at < 5 then return c.n, c.unsure end
  local unsure, named = {}, {}
  local function St(id, dflt)
    local s = ns.Stack(id)
    if not s then
      if not named[id] then named[id] = true unsure[#unsure + 1] = ns.ItemInfo(id) or ("Item " .. id) end
      return dflt
    end
    return s
  end
  local function slots(id, n, dflt) return n > 0 and math.ceil(n / St(id, dflt)) or 0 end
  -- the slots the list's mats fill now (they go as the crafting goes)
  local held = 0
  local list1 = Cr.ShoppingList({ { r = r, runs = 1 } })
  local ids = {}
  for _, e in ipairs(list1) do if not e.alt and not e.head then ids[e.id] = true end end
  for id in pairs(ids) do held = held + slots(id, bags[id] or 0, 20) end
  local room = free + held
  -- (12.11.2026) the results only fit the normal bags (not the reagent bag): its free slots and what the mats fill there
  local freeN, normal = ns.NormalBags()
  local roomN = math.max(0, freeN - 1) -- (12.11.2026) one slot of air, as in MaxCraft
  for id in pairs(ids) do roomN = roomN + ns.FreedNormal(normal, id, 0, St(id, 20)) end
  local stackR = St(r.item, 1)
  local haveR = bags[r.item] or 0
  local avg = Cr.Avg(r)
  local function fits(n)
    local start, startN = 0, 0
    for _, e in ipairs(Cr.ShoppingList({ { r = r, runs = n } })) do
      if not e.alt and not e.head then
        -- a made step holds what is in the bags of it now; its mats are rows of their own
        local amount = e.src == "craft" and (e.held or 0) or e.total
        local s = slots(e.id, amount, 20)
        start = start + s
        -- (Daniel 16.11.2026, "Platz für 620", 480 Hot Spices fitted) what is no reagent for the game needs normal slots
        if not ns.FitsReagentBag(e.id) then startN = startN + s end
      end
    end
    local finish = math.ceil((haveR + Cr.Upper(r, n)) / stackR) - math.ceil(haveR / stackR)
    -- (Daniel 16.11.2026, 320 Bronze Framework bought, bags full: "lag es an mir?") with every mat in, two slots must
    -- still be free: one for the first results, one of air (MaxCraft); the mats free theirs only as they run out
    return start + 2 <= room and startN + 1 <= roomN and finish <= roomN
  end
  local lo, hi = 0, 1
  while hi <= 5000 and fits(hi) do lo = hi hi = hi * 2 end
  hi = math.min(hi, 5001)
  while hi - lo > 1 do
    local m = math.floor((lo + hi) / 2)
    if fits(m) then lo = m else hi = m end
  end
  local u = #unsure > 0 and unsure or nil
  roomCache[r.spell] = { key = key, at = GetTime(), n = lo, unsure = u }
  return lo, u
end

-- (Durchsicht 11.11.2026, Bild Einkaufsliste: "Alle herstellen (0)" grey without a word, "(60)" beside 200 chosen) what
-- the bags lack for runs crafts: the count the mats allow and "479 Wool Cloth, 1358 Heavy Blasting Powder" (nil: all there)
function Cr.Missing(r, runs)
  local bags = ns.Bags()
  local can, miss = math.huge, {}
  runs = math.max(1, math.floor(tonumber(runs) or 1))
  for _, g in ipairs(r.reag) do
    local have = bags[g[1]] or 0
    can = math.min(can, math.floor(have / g[2]))
    local lack = g[2] * runs - have
    if lack > 0 then miss[#miss + 1] = ("%d %s"):format(lack, ns.ItemInfo(g[1]) or ("Item " .. g[1])) end
  end
  if can == math.huge then can = 0 end
  return can, #miss > 0 and table.concat(miss, ", ") or nil
end

-- crafts planned for the shopping list: chosen in the window (ProfitdonDB.craftRuns[spell]), else one stack of results
-- (Daniel 16.11.2026: "Bei der Einkaufsliste kann ich aber dann trotzdem mehr einkaufen als Platz ist? Manchmal will man
-- ja auch auf Vorrat einkaufen. Vorausgewählt sollte da immer sein entweder so viel wie möglich was an platz da ist oder
-- wenn nur bis xx crafts rentabel dann nur bis da hin") the count chosen beforehand: as many as the bags hold from buying
-- to the end (Cr.RoomCrafts), but not past the last count that pays (Cr.Breakeven best), and for the AH not past what
-- the demand takes (14.11.2026). A typed count stands as typed, also above the room (buying ahead).
function Cr.Runs(v)
  local runs = ns.db.craftRuns and ns.db.craftRuns[v.r.spell]
  if runs then return runs end
  if Cr.HasCooldown(v.r.spell) then return 1 end
  local n = Cr.RoomCrafts(v.r)
  if not n or n < 1 then
    local stack = select(6, ns.ItemInfo(v.r.item)) or 20
    n = math.max(1, math.ceil(stack / Cr.Avg(v.r)))
  end
  local be = Cr.Breakeven(v.r, v.mode)
  if be and be.best and be.best > 0 then n = math.min(n, be.best) end
  if v.mode == "ah" and v.dem then n = math.min(n, math.max(1, Cr.AhCrafts(v.r, v.dem) or 1)) end
  return math.max(1, n)
end
function Cr.RunsTyped(v) return ns.db.craftRuns and ns.db.craftRuns[v.r.spell] and true or false end
function Cr.SetRuns(v, n)
  ns.db.craftRuns = ns.db.craftRuns or {}
  ns.db.craftRuns[v.r.spell] = n and math.max(1, math.floor(n)) or nil
  -- (Daniel 16.11.2026, Bild Bronze Framework "319× herstellen", "fehlt 40": "ich hatte nur für 300 eingekauft ... vorher von
  -- 320 auf 300 runtergesetzt"; gewählt "Liste setzt Auftrag") the job of the Herstellfenster follows the list's number:
  -- it stands at exactly that many still to make, an old rest goes. A purchase after it with the same number changes
  -- nothing more (JobAdd).
  local t = Cr.JobTable and Cr.JobTable()
  local j = t and t[v.r.spell]
  if j then
    local runs = Cr.Runs(v)
    j.runs, j.list, j.madeAt = (j.made or 0) + runs, runs, j.made or 0
    j.t = time()
    if ns.Touch then ns.Touch() end
  end
end

local function max1(n) return math.max(1, math.floor(tonumber(n) or 1)) end

-- the cheapest known recipe that makes id: cost of one unit made, the recipe
-- (07.11.2026) a recipe this character can make but a mat lacks a price: no cost, but the recipe still (the tree shows it)
local function Route(id)
  local best, via, any
  for _, r in ipairs(Cr.MakesItem(id) or {}) do
    local sum = CanMake(r) and 0 or nil
    if sum and not any then any = r end
    for _, g in ipairs(sum and r.reag or {}) do
      local u = g[1] ~= id and Cr.ReagentUnit(g[1])
      if not u then sum = nil break end
      sum = sum + u * g[2]
    end
    if sum then
      local each = math.ceil(sum / Cr.Avg(r))
      if not best or each < best then best, via = each, r end
    end
  end
  return best, via or any
end
Cr.Route = Route

-- the shopping list of a row for its runs: { id, total, held, need, src, unit, cost, maxUnit, depth }; a reagent made
-- here brings its own mats (depth 1, 2). maxUnit: the AH price limit of a purchase (10 % over the price counted)
-- (Daniel 16.11.2026, Bild beim Händler: Stonescale Oil, 610 gewählt, "Inventory is full", "obwohl ich genau nach seiner
-- menge eingekauft habe"; gewählt "Auf Platz kürzen") what is bought for a recipe: the chosen count, but not more than
-- the bags hold from buying to the end (Cr.RoomCrafts). Returns the crafts to buy for and, when cut, the chosen count.
-- (Daniel 16.11.2026, later: "kann ich aber dann trotzdem mehr einkaufen als Platz ist? ... auf Vorrat") a typed count
-- is bought as typed (the list says it is more than the room); only the count chosen beforehand keeps to the room
function Cr.BuyRuns(r, runs, typed)
  runs = max1(runs)
  if typed then return runs end
  local room = r and Cr.RoomCrafts(r)
  if room and room >= 1 and room < runs then return room, runs end
  return runs
end
-- the recipes of the shopping list (the tab and the merchant's "Mats kaufen" go by the same): the plan of "Skillen", the
-- Favor crates, what is tracked in the profession window, and the chosen recipe
function Cr.ShopEntries()
  local entries = ns.Skill and ns.Skill.PlanEntries() or {}
  for _, en in ipairs(ns.Favor and ns.Favor.PlanEntries() or {}) do entries[#entries + 1] = en end
  -- (Daniel 18.11.2026) Craftsman's Writs: the writ item and its ware
  for _, en in ipairs(ns.Writs and ns.Writs.PlanEntries() or {}) do entries[#entries + 1] = en end
  -- (Daniel 15.11.2026) what is tracked in the profession window stands on the list too
  for _, en in ipairs(Cr.Tracked()) do
    local dup = false
    for _, o in ipairs(entries) do if o.r == en.r then dup = true end end
    if not dup then entries[#entries + 1] = en end
  end
  local v = Cr.sel
  if v and v.r then
    local dup = false
    for _, en in ipairs(entries) do if en.r == v.r then dup = true end end
    if not dup then
      local runs, want = Cr.BuyRuns(v.r, Cr.Runs(v), Cr.RunsTyped(v))
      entries[#entries + 1] = { r = v.r, runs = runs, want = want, chosen = true }
    end
  end
  return entries
end
function Cr.Shopping(v)
  if not (v and v.parts) then return {} end
  return Cr.ShoppingList({ { r = v.r, runs = (Cr.BuyRuns(v.r, Cr.Runs(v), Cr.RunsTyped(v))) } })
end

-- (Daniel 07.11.2026, Skillen: "mit option das auf die Einkaufsliste zu setzen", a collected list) the mats of several
-- recipes { r, runs } summed per item (first seen first), the bags counted once.
-- grouped (Daniel 07.11.2026: "oben drüber dann was damit hergestellt wird ... darunter eingerückt coarse powder und wool
-- cloth und unter coarse powder eingerückt der coarse stone"): a row { head = true, en } per recipe, its mats one step
-- in below it; the bags are still counted once over all recipes (the first recipe takes what is there)
-- (Durchsicht der Rechnungen 15.11.2026) what the rows from..to of a list cost to buy: cost (nil when a row has no
-- price), short (the AH has not that many), live, held (bags counted free), way (bought, in the mailbox)
local function Tally(rows, from, to)
  local cost, short, live, held, way = 0, false, false, false, false
  for i = from or 1, to or #rows do
    local e = rows[i]
    if not e.alt and not e.head then
      if (e.held or 0) > 0 then held = true end
      -- (11.11.2026, Bild 134857: +1g 76s before the purchase, +19g 48s after it) bought and in the mailbox costs nothing
      -- either: the caller says so
      if e.way then way = true end
      if e.need > 0 and e.src ~= "craft" then
        if not e.cost then return nil end
        cost = cost + e.cost
        short, live = short or e.short or false, live or e.live or false
      end
    end
  end
  return cost, short, live, held, way
end

function Cr.ShoppingList(entries, grouped)
  local out = {}
  local groups = {}
  local function collect(list)
    local order, totals = {}, {}
    for _, en in ipairs(list) do
      for _, g in ipairs(en.r and en.r.reag or {}) do
        if not totals[g[1]] then order[#order + 1] = g[1] totals[g[1]] = 0 end
        totals[g[1]] = totals[g[1]] + g[2] * max1(en.runs)
      end
    end
    return order, totals
  end
  if grouped then
    for _, en in ipairs(entries or {}) do
      local o, t = collect({ en })
      groups[#groups + 1] = { en = en, order = o, totals = t }
    end
  else
    local o, t = collect(entries or {})
    if #o > 0 then groups[1] = { order = o, totals = t } end
  end
  if #groups == 0 then return out end
  -- (Daniel 19.11.2026) own lists: recipes of every character count, a fixed entry buys its amount whatever the bags hold
  local anyBefore = Cr.anyChar
  for _, en in ipairs(entries or {}) do if en.anyChar then Cr.anyChar = true end end
  local fixedNow = false
  local left = ns.Owned() -- (14.11.2026) bags, and by the two switches of the list the reagent bag and the bank
  -- (Durchsicht Runde 2, 11.11.2026) bought at the AH and still in the mailbox: counted like the bags, named apart (e.way)
  local wayLeft = {}
  -- (Daniel 14.11.2026: "dritten schalter für briefkasten", then "nur einen schalter ... egal welcher quelle") off: the mail does not count
  if not ns.db.shopNoHave then for id, w in pairs(ns.OnWay()) do wayLeft[id] = w.q end end
  local base = grouped and 1 or 0
  Cr.cache = {}
  -- (Durchsicht 11.11.2026, Gold Core: 1000 Iron Bar bought for a step that could not be made) every row says what it is
  -- for: e.forItem (the recipe's result), e.forVia (the reagent made on the way it goes into, nil: straight into the
  -- result), e.forRuns; alt rows (the other way, "oder herstellen") carry e.parent, the row they would replace
  local headItem, headRuns, headSpell
  -- (Durchsicht der Rechnungen 15.11.2026) a mat that stands in two rows (straight and in a step, in two steps, in two
  -- recipes) was priced from the cheapest offer in each row: 100 units at 1s in the AH, then 10s, two rows of 100 came to
  -- 2g, 200 units cost 11g. taken[id]: the units of the item the rows before bought; a row pays what its units cost
  -- after those (the average of from + need less the average of from), never under the average of all of them.
  local taken = {}
  local function AhPrice(id, need)
    local P = ns.Prices
    local from = taken[id] or 0
    taken[id] = from + need
    local all = P.Buy(id, from + need)
    local unit = all
    local tAll, short, src = P.BuyTotal(id, from + need)
    if from > 0 and all then
      -- both sums from the same source (the live offers or the ladder); without one, from the averages
      local tBefore = tAll and P.BuyTotal(id, from)
      if tBefore then unit = math.max(all, math.ceil((tAll - tBefore) / need))
      else
        local before = P.Buy(id, from)
        if before then unit = math.max(all, math.ceil((all * (from + need) - before * from) / need)) end
      end
    end
    -- without a price ladder (100 units or fewer in the AH) BuyTotal says nothing: the scan's count of units does
    if src ~= "live" and not short then
      local _, _, offers = P.AH(id)
      if offers and from + need > offers then short = true end
    end
    return unit, short and true or false, src == "live"
  end
  local function add(id, total, depth, unit, src, via, forVia)
    local held = fixedNow and 0 or math.min(total, math.max(0, left[id] or 0))
    left[id] = (left[id] or 0) - held
    local way = fixedNow and 0 or math.min(total - held, math.max(0, wayLeft[id] or 0))
    wayLeft[id] = (wayLeft[id] or 0) - way
    local need = total - held - way
    -- (Durchsicht 15.11.2026) at the depth limit a made reagent is not opened any more: it stood there as "make" without
    -- mats and cost nothing (long chains, leather). It is bought there: vendor or AH, without a price the list has none.
    if src == "craft" and depth >= 3 + base then
      local vu = ns.Prices.VendorUnit(id)
      if vu then src, unit, via = "vendor", vu, nil else src, unit, via = "ah", ns.Prices.Buy(id, 20), nil end
    end
    -- (Durchsicht 15.11.2026) buy or make was settled at the price of 20 units; many more cost more: 20 at 1s, then 10s,
    -- made 2s, 500 units stayed "buy" at 9s 60c. Settled again at the amount needed.
    -- (22.11.2026) the casting time counts here too (Cr.GoldHour)
    if src == "ah" and need > 20 and depth < 3 + base then
      local each, r = Route(id)
      local at = each and r and ns.Prices.Buy(id, (taken[id] or 0) + need)
      local sec = at and (Cr.Time(r) or 0) / Cr.Avg(r) or 0
      if at and each + Cr.TimeGold(sec) < at then src, unit, via = "craft", each, r end
    end
    local timeBuy = src == "ah" and select(7, Cr.ReagentUnit(id)) or nil
    local short, live
    if src == "ah" and need > 0 then
      local u
      u, short, live = AhPrice(id, need)
      unit = u or unit
    end
    local e = { id = id, total = total, held = held, way = way > 0 and way or nil, need = need, depth = depth, src = need == 0 and (held < total and "mail" or "stock") or src, unit = unit,
      cost = (src ~= "craft" and unit) and unit * need or nil, maxUnit = unit and math.max(unit + 2, math.ceil(unit * 1.25)) or nil, via = via,
      short = short or nil, live = live or nil, timeBuy = timeBuy,
      forItem = headItem, forRuns = headRuns, forVia = forVia, forSpell = headSpell }
    out[#out + 1] = e
    -- (Daniel 06.11.2026: "unter rough powder eingerückt dann rough stone sehen ... bei den anderen rezepten natürlich auch")
    -- bought, but a known recipe makes it: its mats indented below as the other way, with what one unit costs made
    -- (Daniel 07.11.2026: "auch wenn was in den taschen da ist, ich will den baum, vielleicht will ich ja mehr als 20 machen")
    -- all in the bags: the way to make it still shows, for the whole amount
    if ((need > 0 and src ~= "craft") or need == 0) and depth < 3 + base then
      local each, r = Route(id)
      if r then
        local crafts = math.ceil((need > 0 and need or total) / Cr.Avg(r))
        e.altEach, e.altCrafts = each, crafts
        for _, g in ipairs(r.reag) do
          local u, s2 = Cr.ReagentUnit(g[1])
          local t = g[2] * crafts
          local held2 = fixedNow and 0 or math.min(t, math.max(0, left[g[1]] or 0))
          local n2 = t - held2
          if s2 == "ah" and n2 > 0 then u = ns.Prices.Buy(g[1], n2) or u end
          out[#out + 1] = { id = g[1], total = t, held = held2, need = n2, depth = depth + 1, alt = true, src = n2 == 0 and "stock" or s2 or "ah",
            unit = u, cost = u and u * n2 or nil, maxUnit = u and math.max(u + 2, math.ceil(u * 1.25)) or nil,
            parent = e, forItem = headItem, forRuns = headRuns, forVia = id, forSpell = headSpell }
        end
      end
    end
    if need > 0 and src == "craft" and via and depth < 3 + base then
      local crafts = math.ceil(need / Cr.Avg(via))
      e.crafts = crafts
      for _, g in ipairs(via.reag) do
        local u, s2, _, _, via2 = Cr.ReagentUnit(g[1])
        add(g[1], g[2] * crafts, depth + 1, u, s2 or "ah", via2, id)
      end
    end
  end
  -- the sources now, not those of the moment the row was chosen (a vendor visited since, a fresh scan)
  for _, grp in ipairs(groups) do
    local head
    if grouped then head = { head = true, en = grp.en, depth = 0 } out[#out + 1] = head end
    local first = #out + 1
    headItem, headRuns = grp.en and grp.en.r and grp.en.r.item or nil, grp.en and max1(grp.en.runs) or nil
    headSpell = grp.en and grp.en.r and grp.en.r.spell or nil
    fixedNow = grp.en and grp.en.fixed and true or false
    for _, id in ipairs(grp.order) do
      local u, src, _, _, via = Cr.ReagentUnit(id)
      add(id, grp.totals[id], base, u, src or "ah", via)
    end
    -- (Durchsicht 15.11.2026) the head of a recipe counted the bags and the AH's cheap offers for itself alone: two
    -- recipes with the same mat both showed a profit the rows below did not have. Its sums are those of its own rows.
    if head then head.cost, head.short, head.live, head.held, head.way = Tally(out, first, #out) head.tallied = true end
  end
  Cr.cache = nil
  Cr.anyChar = anyBefore
  return out
end

---------------------------------------------------------------------------
-- (Daniel 09.11.2026: "wie lange wir mit positivem cashflow rauskommen? die einkaufswerte sind ja nur mittelwerte") how
-- many crafts still pay when the mats are bought cheapest first: the cost of n crafts is the shopping list for n (what the
-- bags hold costs nothing, AH mats over the price ladder or the live offers, Prices.BuyTotal), against n times what one
-- craft brings (vendor, or the AH after the cut). Returns { best, gain (the profit at best), zero (from here the whole
-- run loses, nil while it pays up to the cap), short (the AH has not that many), src "live"|"scan" }; nil without a value.
---------------------------------------------------------------------------
Cr.BE_CAP = 5000
function Cr.CraftWorth(r, mode)
  local count = Cr.Avg(r)
  local vendor = math.floor((ns.Prices.Sell(r.item) or 0) * count + 0.5)
  local low = ns.Prices.Low(r.item)
  local ah = low and ns.Deals.AfterCut(math.floor(low * count + 0.5), ns.Prices.Cut()) or nil
  if mode == "ah" then return ah end
  if mode == "vendor" then return vendor > 0 and vendor or nil end
  return math.max(vendor, ah or 0) > 0 and math.max(vendor, ah or 0) or nil
end

local function ListCost(r, n)
  return Tally(Cr.ShoppingList({ { r = r, runs = n } }))
end

-- (Durchsicht 15.11.2026) what n crafts bring, one reckoning for ProfitAt and Breakeven: for the AH with demand numbers
-- what the demand takes at the expected AH value and the rest at the vendor (Breakeven counted every piece at the full
-- AH price: "lohnt bis ~5000" in green beside a loss in red). Returns a function of n.
local function Revenue(r, mode, worth)
  if mode == "ah" then
    local dem, exp = Cr.AhExpect(r)
    local a = exp and Cr.AhCrafts(r, dem)
    if a then
      local vendor = math.floor((ns.Prices.Sell(r.item) or 0) * Cr.Avg(r) + 0.5)
      return function(n) local k = math.min(n, a) return k * exp + (n - k) * vendor end
    end
  end
  return function(n) return n * worth end
end

-- (Daniel 10.11.2026: "wie viel Gewinn ich mit der Anzahl an crafts bekomme und je craft") the profit of exactly n crafts,
-- the same reckoning as Breakeven; nil without a value
-- head: the head row of the grouped list (its sums are those of its own rows, the bags shared with the recipes above it)
function Cr.ProfitAt(r, mode, n, head)
  local worth = r and n and n > 0 and Cr.CraftWorth(r, mode)
  if not worth then return nil end
  local cost, held, way, _
  if type(head) == "table" and head.tallied then cost, held, way = head.cost, head.held, head.way
  else cost, _, _, held, way = ListCost(r, n) end
  if not cost then return nil end
  -- (Daniel 14.11.2026: "dass man immer einen Teil davon verkauft") for the AH with demand numbers: what the demand takes
  -- at the expected AH value, the rest at the vendor
  return Revenue(r, mode, worth)(n) - cost, held, way
end

local beCache = {}
function Cr.Breakeven(r, mode)
  local worth = r and Cr.CraftWorth(r, mode)
  if not worth then return nil end
  local st = ns.Prices.Store()
  local key = table.concat({ r.spell, mode or "", st and st.t or 0, ns.liveVer or 0, ns.db.shopNoHave and 1 or 0, ns.dataVer or 0, tostring(Cr.assume), tostring(Cr.assumeChar) }, "|")
  local c = beCache[key]
  -- (16.11.2026) kept while nothing it is made of changed (dataVer); the tests change the bags without events: 5 s there
  if c and GetTime() - c.at < (ns.bagCacheOff and 5 or 600) then return c.res end
  local seen, anyLive, shortAt = {}, false, nil
  local revenue = Revenue(r, mode, worth)
  local function P(n)
    if seen[n] == nil then
      local cost, short, live = ListCost(r, n)
      if not cost then seen[n] = false
      else
        seen[n] = revenue(n) - cost
        anyLive = anyLive or live
        if short and (not shortAt or n < shortAt) then shortAt = n end
      end
    end
    return seen[n] or nil
  end
  -- a grid that grows by a third, the best point on it, then narrowed down between its neighbours (the profit rises,
  -- then falls: the dearer offers come last)
  local grid, n = {}, 1
  while n < Cr.BE_CAP do grid[#grid + 1] = n n = math.max(n + 1, math.floor(n * 4 / 3)) end
  grid[#grid + 1] = Cr.BE_CAP
  local bi, bv
  for i, g in ipairs(grid) do
    local v = P(g)
    if not v then break end
    if not bv or v > bv then bi, bv = i, v end
    if shortAt then break end
    if bv and v < 0 and bv > 0 and i > bi + 3 then break end
  end
  if not bi then beCache[key] = { at = GetTime(), res = nil } return nil end
  local lo, hi = grid[math.max(1, bi - 1)], grid[math.min(#grid, bi + 1)]
  while hi - lo > 2 do
    local m1 = lo + math.floor((hi - lo) / 3)
    local m2 = hi - math.floor((hi - lo) / 3)
    local v1, v2 = P(m1), P(m2)
    if not v1 or not v2 then break end
    if v1 < v2 then lo = m1 else hi = m2 end
  end
  local best, gain = grid[bi], bv
  for k = lo, hi do local v = P(k) if v and v > gain then best, gain = k, v end end
  -- the run as a whole turns into a loss: past best the first n with a profit under 0
  local zero
  if gain > 0 then
    local a, b
    for _, g in ipairs(grid) do
      if g > best then
        local v = P(g)
        if v and v < 0 then b = g break end
        a = g
      end
    end
    if b then
      a = a or best
      while b - a > 1 do
        local m = math.floor((a + b) / 2)
        local v = P(m)
        if v and v < 0 then b = m else a = m end
      end
      zero = b
    end
  end
  local res = { best = gain > 0 and best or 0, gain = gain, zero = zero, short = shortAt, src = anyLive and "live" or "scan", worth = worth }
  beCache[key] = { at = GetTime(), res = res }
  return res
end

-- (Daniel 18.11.2026: "Rezepte gerade Richtung Kochen hochprofitabel zuerst klingen pro Stunde, dann aber nur eine
-- bestimmte Anzahl an Crafts überhaupt profitabel ist ... das nimmt dann natürlich mehr Platz weg ... die Crafts lässt
-- man ja immer nur so eine halbe Stunde laufen"; gewählt "So bauen", Lauf wählbar, vorbelegt 30 min, erst nur Händler)
-- what one run of crafting for the vendor really brings: as many crafts as the smallest of three limits allows, the
-- casting time of the run (option runMin, the steps on the way counted), the room of the bags from buying to the end
-- (Cr.RoomCrafts) and the last count that still pays (Cr.Breakeven, the AH offers grow dearer). The gain is that of
-- exactly so many crafts (Cr.ProfitAt, every mat bought; mats in the bags count with their price, else a recipe looks
-- good only because its mats lie there). k runs back to back (Gold/h: as many runs as fill an hour, two of 30 min): the
-- time and the room count k times (the vendor empties the bags in between), the AH prices go on into the dearer offers.
-- Returns { n, gain, limit = "Zeit" | "Platz" | "Preis" | "Abklingzeit", sec } or nil without a price.
function Cr.RunSec() return math.max(60, (ns.Opt("runMin") or 30) * 60) end
function Cr.Run(v, k)
  if not (v and v.r) then return nil end
  k = k or 1
  local r = v.r
  local keep = ns.db.shopNoHave
  ns.db.shopNoHave = true
  local ok, res = pcall(function()
    if Cr.HasCooldown(r.spell) then
      local g = Cr.ProfitAt(r, "vendor", 1)
      return g and { n = 1, gain = g, limit = "Abklingzeit", sec = v.time } or nil
    end
    local caps = {}
    local t = v.time and v.time > 0 and v.time or Cr.CastTime(r.spell)
    if t and t > 0 then caps[#caps + 1] = { math.floor(Cr.RunSec() * k / t), "Zeit" } end
    ns.db.shopNoHave = keep -- the room is that of the bags as they are
    local room = Cr.RoomCrafts(r)
    ns.db.shopNoHave = true
    if room then caps[#caps + 1] = { math.floor(room * k), "Platz" } end
    local be = Cr.Breakeven(r, "vendor")
    if not be then return nil end
    caps[#caps + 1] = { be.best or 0, "Preis" }
    local n, limit = math.huge, nil
    for _, c in ipairs(caps) do if c[1] < n then n, limit = c[1], c[2] end end
    if n == math.huge or n < 1 then return { n = 0, gain = 0, limit = limit or "Preis" } end
    local g = Cr.ProfitAt(r, "vendor", n)
    if not g then return nil end
    return { n = n, gain = g, limit = limit, sec = t and n * t or nil }
  end)
  ns.db.shopNoHave = keep
  if not ok then error(res, 0) end
  return res
end
-- v.run (one run), v.runH (the runs of an hour, Gold/h); a failure leaves them nil and the list stands (ns.Try reports it)
function Cr.RunsOf(v)
  local ok1, a = ns.Try(Cr.Run, v, 1)
  local ok2, b = ns.Try(Cr.Run, v, 3600 / Cr.RunSec())
  v.run, v.runH = ok1 and a or nil, ok2 and b or nil
end

-- (Daniel 11.11.2026: "sollte zuerst die zwischenschritte craften, nacheinander ... dann zum schluss das hauptgegenstand
-- ... blizzard verlangt für jeden schritt einen klick. also einmal z.b. alles herstellen für powder, dann zweiter klick
-- alles herstellen für dynamit") the next click of "Alle herstellen": a reagent the bags lack for the wanted runs and a
-- learned recipe without a cooldown makes from what the bags hold comes first, the deepest step first; then the recipe
-- itself. Returns { r, n, step = true } for a step on the way, { r, n } for the recipe (n = 0: nothing to make).
-- (Daniel 15.11.2026: "damit sich das Spiel nicht immer ausloggt beim Craften ... Mach so viele wie in 30 Minuten
-- reinpassen") the game logs out after 30 minutes without input and a running craft queue is no input: one click
-- starts at most what fits into AFK_SEC of casting (28 minutes, a little air), the rest is the next click
-- (Daniel 16.11.2026, Bild "Alle herstellen (405)" sent 324: "Grenze aufheben") off by default now: one click sends all
-- the bags allow; option afkCap brings the 28 minutes back
Cr.AFK_SEC = 28 * 60
function Cr.TimeCap(r, n)
  if not ns.Opt("afkCap") then return n end
  local t = Cr.CastTime(r.spell)
  if not t or t <= 0 then t = 3 end
  return math.max(1, math.min(n, math.floor(Cr.AFK_SEC / t)))
end
function Cr.NextStep(v, runs)
  local s = Cr.NextStepAll(v, runs)
  if s.n > 0 then
    local n = Cr.TimeCap(s.r, s.n)
    if n < s.n then s.n, s.capped = n, true end
  end
  return s
end
function Cr.NextStepAll(v, runs)
  runs = max1(runs or Cr.Runs(v))
  local bags = ns.Bags()
  local function step(r, want, depth, seen)
    seen[r.item] = true
    for _, g in ipairs(r.reag) do
      local lack = g[2] * want - (bags[g[1]] or 0)
      if lack > 0 and not seen[g[1]] and depth < 3 then
        local _, r2 = Route(g[1])
        if r2 and CanMake(r2) then
          local crafts = math.ceil(lack / Cr.Avg(r2))
          local sub = step(r2, crafts, depth + 1, seen)
          if sub then return sub end
          local n = math.min(crafts, (Cr.MaxCraft({ r = r2 })))
          if n > 0 then return { r = r2, n = n, step = true } end
        end
      end
    end
    seen[r.item] = nil
  end
  return step(v.r, runs, 0, {}) or { r = v.r, n = Cr.MaxCraft(v) }
end

-- "Alle herstellen": the profession window of the recipe must be open; returns ok and a message. One call is one step
-- (Cr.NextStep): the steps on the way first, one per click, the recipe itself last
-- (15.11.2026, Herstellfenster) n crafts of one recipe now: ok (the game took it), else a message
function Cr.CraftNow(r, n)
  if n <= 0 then return false, "Keine Mats in den Taschen (oder kein Platz)." end
  local T = C_TradeSkillUI
  local info = T and ns.Call(T.GetBaseProfessionInfo)
  local prof = type(info) == "table" and ns.Num(info.professionID)
  if not (T and T.CraftRecipe) or prof ~= r.prof then
    -- (Daniel 11.11.2026: "wenn ich auf herstellen klicke, kann er doch bitte das entsprechende berufefenster öffnen")
    -- the click opens the window of the step's profession; the list of the window comes a moment later, so the
    -- crafting is the next click
    if T and T.CraftRecipe and T.OpenTradeSkill then
      local okO, opened = pcall(T.OpenTradeSkill, r.prof)
      if okO and opened ~= false then
        return false, ("Fenster %s geöffnet. Noch einmal klicken zum Herstellen."):format(Cr.ProfName(r.prof))
      end
    end
    return false, ("Erst das Fenster %s öffnen."):format(Cr.ProfName(r.prof))
  end
  local ok = pcall(T.CraftRecipe, r.spell, n)
  if not ok then return false, "Herstellen abgelehnt." end
  return true
end
function Cr.CraftAll(v, runs)
  local s = Cr.NextStep(v, runs)
  local r, n = s.r, s.n
  local ok, why = Cr.CraftNow(r, n)
  if not ok then return false, why end
  local name = ns.ItemInfo(r.item) or ("Item " .. r.item)
  if s.step then
    return true, ("Stelle erst %d× %s her (für %s). Danach noch einmal klicken."):format(n, name, ns.ItemInfo(v.r.item) or ("Item " .. v.r.item))
  end
  if s.capped then
    ns.db.made = ns.db.made or {}
    ns.db.made[v.r.item] = v.mode or "vendor"
    return true, ("Stelle %d× %s her (knapp 30 Minuten, sonst loggt das Spiel aus). Danach noch einmal klicken."):format(n, name)
  end
  ns.db.made = ns.db.made or {}
  ns.db.made[v.r.item] = v.mode or "vendor" -- the merchant button sells what was made for the vendor
  return true, ("Stelle %d× %s her."):format(n, name)
end

---------------------------------------------------------------------------
-- (Daniel 15.11.2026: "Wenn ich ein Rezept aus meinem Berufefenster auf Track recipe mache, können wir das direkt in
-- Profitdon in die Einkaufsliste packen? Dort muss es dann auch verschwinden, wenn ich track recipe wieder aus mache
-- oder es in der einkaufsliste lösche") the recipes tracked in the profession window stand on the shopping list. The
-- list reads them from the game every time (C_TradeSkillUI.GetRecipesTracked), so nothing has to be kept in step: the
-- tick off takes the row away, the X of the row takes the tick off (SetRecipeTracked). Only the count of crafts is
-- Profitdon's own (ProfitdonDB.trackRuns[spell], 1 until typed).
---------------------------------------------------------------------------
-- the entries for Cr.ShoppingList: { r, runs, tracked = true }
function Cr.Tracked()
  local out = {}
  local T = C_TradeSkillUI
  if not (ns.db and T and type(T.GetRecipesTracked) == "function") then return out end
  local ok, ids = pcall(T.GetRecipesTracked, false)
  if not ok or type(ids) ~= "table" then return out end
  local runs = type(ns.db.trackRuns) == "table" and ns.db.trackRuns or {}
  for _, id in ipairs(ids) do
    id = ns.Num(id)
    local r = id and Cr.Recipe(id)
    if r and r.item and r.item > 0 and #r.reag > 0 then out[#out + 1] = { r = r, runs = max1(runs[id]), tracked = true } end
  end
  return out
end
function Cr.SetTrackRuns(spell, n)
  ns.db.trackRuns = type(ns.db.trackRuns) == "table" and ns.db.trackRuns or {}
  ns.db.trackRuns[spell] = n and max1(n) or nil
end
-- the X of the shopping list: the tick in the profession window goes off
function Cr.Untrack(spell)
  local T = C_TradeSkillUI
  if not (T and type(T.SetRecipeTracked) == "function") then return false end
  local ok = pcall(T.SetRecipeTracked, spell, false, false)
  if ok and ns.db and type(ns.db.trackRuns) == "table" then ns.db.trackRuns[spell] = nil end
  return ok
end
-- (Daniel 15.11.2026: "Profitdon darf dann gerne die blizzard rezeptliste ausblenden") the tracked recipes stand on the
-- shopping list, so the game's own list of them at the screen edge (the recipe part of the objective tracker) is made
-- invisible (alpha 0, nothing is hooked). The option hideRecipeList off brings it back. The part's name is not in
-- data/wowui (Blizzard_ObjectiveTracker is not extracted): the known names are tried, /profit diag says which was
-- found (line recipeList). Never in combat.
-- (22.11.2026, Daniel's error "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'Profitdon'"
-- in Blizzard_MawBuffs from the scenario part of the tracker) the part is no longer folded: SetCollapsed writes
-- self.isCollapsed and marks the tracker dirty, Blizzard's next tracker update reads those values and runs tainted.
-- Only SetAlpha (a frame method, no Lua field of Blizzard's) is used; the invisible part keeps its height.
Cr.RECIPE_PARTS = { "ProfessionsRecipeTracker", "ProfessionsRecipeObjectiveTracker", "ProfessionsRecipeTrackerModule" }
local partHidden, headHidden
function Cr.ApplyRecipeList()
  if not ns.db or ns.Call(InCombatLockdown) then return end
  local hide = ns.Opt("hideRecipeList") ~= false
  if not hide and not partHidden then return end
  local found
  for _, n in ipairs(Cr.RECIPE_PARTS) do
    local m = rawget(_G, n)
    if type(m) == "table" and type(m.SetAlpha) == "function" then
      found = found or n
      pcall(m.SetAlpha, m, hide and 0 or 1)
    end
  end
  partHidden = hide and found ~= nil
  -- (Daniel 15.11.2026, Bild "All Objectives": "kannst du das auch noch ausblenden?") with the recipes gone only the
  -- head of Blizzard's tracker stood there. It goes too while nothing else shows below it: every other part of the
  -- tracker (ObjectiveTrackerFrame.modules, as Blizzard's container reads them) is empty (GetContentsHeight 0) or made
  -- invisible (Questdon hides the quest parts that way). Blizzard's code never touches the head's alpha itself.
  local otf = rawget(_G, "ObjectiveTrackerFrame")
  local head = type(otf) == "table" and type(otf.Header) == "table" and type(otf.Header.SetAlpha) == "function" and otf.Header or nil
  local headGone = false
  if head then
    local others = false
    for _, m in ipairs(type(otf.modules) == "table" and otf.modules or {}) do
      local mine = false
      for _, n in ipairs(Cr.RECIPE_PARTS) do if rawget(_G, n) == m then mine = true end end
      if not mine and type(m) == "table" then
        local h = type(m.GetContentsHeight) == "function" and ns.Num(ns.Call(m.GetContentsHeight, m)) or 0
        local a = type(m.GetAlpha) == "function" and ns.Num(ns.Call(m.GetAlpha, m)) or 1
        if h > 0 and a > 0 then others = true end
      end
    end
    headGone = partHidden and not others
    if headGone then pcall(head.SetAlpha, head, 0) headHidden = true
    elseif headHidden then pcall(head.SetAlpha, head, 1) headHidden = nil end
  end
  ns.Fact("recipeList", found and (found .. (hide and " ausgeblendet" or " sichtbar") .. (headGone and ", Kopf des Trackers auch" or "")) or "Blizzards Rezeptliste nicht gefunden")
end
function Cr.TrackerHeadHidden() return headHidden and true or false end -- (tests)
function Cr.RecipeListHidden() return partHidden and true or false end -- (tests)
ns.On("TRACKED_RECIPE_UPDATE", function(_, id, tracked)
  id = ns.Num(id)
  if id and not tracked and ns.db and type(ns.db.trackRuns) == "table" then ns.db.trackRuns[id] = nil end
  if ns.Refresh then ns.Refresh() end
  Cr.ApplyRecipeList()
  ns.After(0.3, Cr.ApplyRecipeList) -- the game draws its list a moment after the event
end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(2, Cr.ApplyRecipeList) end)
ns.On("PLAYER_REGEN_ENABLED", function() Cr.ApplyRecipeList() end)
-- another part of the tracker gets or loses its content (a quest watched, an achievement, a scenario): the head follows
local headSoon
local function HeadSoon()
  if headSoon then return end
  headSoon = true
  ns.After(0.5, function() headSoon = nil Cr.ApplyRecipeList() end)
end
for _, e in ipairs({ "QUEST_WATCH_LIST_CHANGED", "CONTENT_TRACKING_UPDATE", "TRACKED_ACHIEVEMENT_LIST_CHANGED", "SCENARIO_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
  ns.On(e, HeadSoon)
end

---------------------------------------------------------------------------
-- (Daniel 15.11.2026: "Neues Fenster ... zeigt, was über die Einkaufsliste gekauft wurde") craft jobs: a recipe whose mats
-- were bought over the shopping list (Buy.lua RecordBuy, Merchant.lua "Mats kaufen") is kept in ProfitdonDB.jobs[spell] =
-- { runs, made, mode, t } until it was made runs times (UNIT_SPELLCAST_SUCCEEDED of the recipe) or taken off by hand.
-- The Herstellfenster (CraftWin.lua) shows the jobs of the recipes this character knows.
---------------------------------------------------------------------------
Cr.JOB_DAYS = 14
local function JobTable()
  ns.db.jobs = type(ns.db.jobs) == "table" and ns.db.jobs or {}
  return ns.db.jobs
end
Cr.JobTable = JobTable -- (Cr.SetRuns, above)
function Cr.JobAdd(spell, runs, mode)
  if type(spell) ~= "number" or not Cr.Recipe(spell) then return end -- a Favor crate ("favor:<id>") is no recipe
  -- (Daniel 15.11.2026, Durchsicht der Rechnungen: 100 gekauft, 60 hergestellt, noch einmal für 80 gekauft: "Rest plus
  -- Neukauf") a purchase after crafts were made is a new round: what is still open plus the list's number, made from 0.
  -- Every mat of one list calls this with the same number: no crafts since and the same number changes nothing; another
  -- number without crafts since replaces the last round's share. j.list: the list's number of the last round, j.madeAt:
  -- made when it was set.
  local t = JobTable()
  local j = t[spell]
  runs = max1(runs)
  if not j then j = { made = 0, runs = runs, list = runs, madeAt = 0 }
  else
    local made, list, at = j.made or 0, j.list or j.runs or runs, j.madeAt or 0
    if made > at then
      -- (Daniel 18.11.2026, Bild Herstellfenster "594× herstellen", Mats für 590, "fehlt 4": "ich habe nur 590 eingekauft
      -- über die Liste") the rest of the last round counts only as far as the bags hold mats for it, beyond what the new
      -- number already takes from them (with "Vorhandenes einrechnen" the list counts the bags into its number). The
      -- purchase is not in the bags yet when this runs (AH: mailbox, vendor: the bags update after the call).
      local rest = math.max(0, (j.runs or 0) - made)
      if rest > 0 then
        local r, bags, can = Cr.Recipe(spell), ns.Bags(), math.huge
        for _, g in ipairs(r and r.reag or {}) do can = math.min(can, math.floor((bags[g[1]] or 0) / g[2])) end
        if can == math.huge then can = 0 end
        rest = math.min(rest, math.max(0, can - (ns.db.shopNoHave and 0 or runs)))
      end
      j.runs = rest + runs
      j.made, j.madeAt, j.list = 0, 0, runs
    elseif runs ~= list then
      j.runs = math.max(runs, (j.runs or 0) - list + runs)
      j.list = runs
    end
  end
  j.t = time()
  if mode then j.mode = mode end
  t[spell] = j
  return j
end
function Cr.JobRemove(spell) if ns.db then JobTable()[spell] = nil end end
function Cr.JobMade(spell)
  local j = ns.db and JobTable()[spell]
  if not j then return end
  j.made = (j.made or 0) + 1
  if j.made >= j.runs then
    JobTable()[spell] = nil
    -- (Daniel 16.11.2026, Bild beim Händler nach 610 Stonescale Oil: "Mats kaufen: 610× Leaded Vial ... das sollte nach
    -- dem 1. mal einkaufen abgehakt sein") all of it made: the recipe is no longer the chosen one, nothing is bought again
    -- the same for an entry of "Skillen" of this character: made, off the list
    local was = Cr.sel and Cr.sel.r and Cr.sel.r.spell == spell
    if was then Cr.sel = nil end
    local Sk = ns.Skill
    for _, en in ipairs(Sk and Sk.PlanEntries() or {}) do
      if en.r and en.r.spell == spell and en.char == ns.Me() then Sk.Remove(en.char, spell) was = true end
    end
    if was and ns.Refresh then ns.Refresh() end
  end
  return true
end
-- the crafts of a job still to make, nil without a job
function Cr.JobLeft(spell)
  local j = ns.db and JobTable()[spell]
  return j and math.max(0, (j.runs or 0) - (j.made or 0)) or nil
end
-- the jobs of this character, oldest first: { spell, r, runs (still to make), mode }
function Cr.Jobs()
  local out = {}
  if not ns.db then return out end
  local now = time()
  for spell, j in pairs(JobTable()) do
    if now - (j.t or 0) > Cr.JOB_DAYS * 86400 then JobTable()[spell] = nil
    else
      local r = Cr.Recipe(spell)
      if r and Cr.IKnow(spell) then out[#out + 1] = { spell = spell, r = r, runs = math.max(1, j.runs - (j.made or 0)), mode = j.mode, t = j.t or 0 } end
    end
  end
  table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.spell < b.spell end)
  return out
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if unit ~= "player" or not ns.db then return end
  spellID = ns.Num(spellID)
  -- (16.11.2026) the shown rows count down by themselves (CraftWin.lua ns.CraftWinTick); worked out anew once idle
  if spellID and Cr.JobMade(spellID) and ns.CraftWinRefresh then ns.WhenIdle("Herstellfenster", ns.CraftWinRefresh, 0.3) end
end)

-- the rows of one job as Daniel drew them (15.11.2026): the product as a head, below it one step in what has to be made
-- first (a reagent the bags lack and a learned recipe without a cooldown makes, as Cr.NextStepAll; its own mats one more
-- step in) and the mats, last the product itself. Rows: { head, id, runs } / { step, r, id, depth, crafts (needed), n
-- (possible now), want, have } / { mat, id, depth, want, have } / { final, r, id, n, runs }
function Cr.JobRows(job)
  local out = {}
  local bags = ns.Bags()
  out[1] = { head = true, id = job.r.item, runs = job.runs, job = job, depth = 0 }
  local function walk(r, want, depth, seen)
    seen[r.item] = true
    for _, g in ipairs(r.reag) do
      local need, have = g[2] * want, bags[g[1]] or 0
      local lack = need - have
      local r2
      if lack > 0 and not seen[g[1]] and depth < 3 then
        local _, via = Route(g[1])
        if via and CanMake(via) then r2 = via end
      end
      if r2 then
        local crafts = math.ceil(lack / Cr.Avg(r2))
        local mc, mm, mf = Cr.MaxCraft({ r = r2 })
        out[#out + 1] = { step = true, r = r2, id = g[1], depth = depth + 1, crafts = crafts, n = math.min(crafts, mc),
          mats = mm, roomFree = mc < crafts and mf or nil, want = need, have = have, job = job }
        walk(r2, crafts, depth + 1, seen)
      else
        out[#out + 1] = { mat = true, id = g[1], depth = depth + 1, want = need, have = have, job = job }
      end
    end
    seen[r.item] = nil
  end
  walk(job.r, job.runs, 0, {})
  -- (Daniel 16.11.2026: "ich will ja alles alles herstellen, wenn es ein endprodukt ist") the product is made as far as
  -- the mats go; the room is only said (roomN: what Profitdon thinks fits). Full bags stop the game by itself, the rest
  -- stays on the button. Steps keep the room check (their output is the next step's mats).
  local mc, mm, mf = Cr.MaxCraft({ r = job.r })
  local n = math.min(job.runs, mm or mc)
  -- (16.11.2026) no room even for the first craft: nothing can start, the button is off and the line says so
  local noRoom = n > 0 and mc == 0
  if noRoom then n = 0 end
  -- (Daniel 16.11.2026, Bild "Mats für 44 von 380" while 548 Heavy Blasting Powder were still to make: "hab mehr mats in den
  -- taschen als für 44") steps still to make: the line says the rest comes with them
  local pend = false
  for _, row in ipairs(out) do if row.step and (row.crafts or 0) > 0 then pend = true end end
  out[#out + 1] = { final = true, r = job.r, id = job.r.item, depth = 0, runs = job.runs, n = n,
    mats = mm, roomN = (not noRoom and mc < n) and mc or nil, roomFree = mc < (mm or 0) and mf or nil, noRoom = noRoom or nil, job = job,
    stepsLeft = pend or nil }
  return out
end
-- (Daniel 16.11.2026: "unten dürfte sich auch mitändern und muss nicht stehen bleiben") what the bags hold now for a recipe,
-- by its mats alone (no room check): cheap, for the counts shown while crafting
function Cr.MatsNow(r)
  local bags = ns.Bags()
  local n = math.huge
  for _, g in ipairs(r.reag) do n = math.min(n, math.floor((bags[g[1]] or 0) / g[2])) end
  return n == math.huge and 0 or n
end

-- one click on a row of the Herstellfenster: at most what fits into the AFK time (Cr.TimeCap); ok, message
function Cr.CraftRow(row)
  if not (row and row.r) then return false end
  local n = (row.n or 0) > 0 and Cr.TimeCap(row.r, row.n) or 0
  local ok, why = Cr.CraftNow(row.r, n)
  if not ok then return false, why end
  local name = ns.ItemInfo(row.r.item) or ("Item " .. row.r.item)
  if row.final and row.job then
    ns.db.made = ns.db.made or {}
    ns.db.made[row.r.item] = row.job.mode or "vendor" -- the merchant button sells what was made for the vendor
  end
  -- third value: the crafts sent (the craft window counts their time down)
  if n < row.n then return true, ("Stelle %d× %s her (knapp 30 Minuten, sonst loggt das Spiel aus). Danach noch einmal klicken."):format(n, name), n end
  return true, ("Stelle %d× %s her."):format(n, name), n
end

-- what the bags allow besides the jobs: the learned recipes of one profession (nil: all) with mats for at least one
-- craft, by name; skip[spell] leaves a recipe out. Rows: { other, r, id, n }
function Cr.Others(prof, skip)
  local out = {}
  if not ns.db then return out end
  for spell in pairs(Mine().known) do
    local r = not (skip and skip[spell]) and Cr.Recipe(spell)
    if r and r.item and r.item > 0 and #r.reag > 0 and (not prof or r.prof == prof) then
      local n = Cr.MaxCraft({ r = r })
      if n > 0 then out[#out + 1] = { other = true, r = r, id = r.item, n = n, depth = 0 } end
    end
  end
  table.sort(out, function(a, b)
    local na, nb = ns.ItemInfo(a.id) or "", ns.ItemInfo(b.id) or ""
    if na ~= nb then return na < nb end
    return a.r.spell < b.r.spell
  end)
  return out
end

---------------------------------------------------------------------------
-- (Daniel 08.11.2026: "eine Übersicht über alle Berufe ... Auswählbar mit Dropdown. Dann dort alle Rezepte ... die wir im Spiel
-- haben. und dann ein reiter für an händler und an AH ... So könnte man noch explizit andere Berufe mit Twinks angehen")
-- Berufe: every recipe of one profession in the data (Data/Recipes.lua and what the game's window said), valued as if a
-- character had that profession at its top: the reagents of the same profession may be made on the way (when cheaper);
-- other professions only as this character can make them. Who of the own characters knows it, and from which skill.
---------------------------------------------------------------------------
-- professions with recipes that make an item, sorted by name
function Cr.ProfList()
  local has = {}
  for spell, d in pairs(ns.CRAFTS or {}) do
    if type(d) == "table" and (d[3] or 0) > 0 and d[1] then has[d[1]] = true end
  end
  for _, x in pairs(ns.db and type(ns.db.craftExtra) == "table" and ns.db.craftExtra or {}) do
    if type(x) == "table" and x[1] and (x[2] or 0) > 0 then has[x[1]] = true end
  end
  local out = {}
  for p in pairs(has) do if PROFS[p] then out[#out + 1] = p end end
  table.sort(out, function(a, b) return Cr.ProfName(a) < Cr.ProfName(b) end)
  return out
end
-- the profession shown: the chosen one (ProfitdonDB.profView), else one of this character, else the first
function Cr.ViewProf()
  local list = Cr.ProfList()
  local want = ns.db.profView
  for _, p in ipairs(list) do if p == want then return p end end
  for _, p in ipairs(list) do if Mine().skills[p] then return p end end
  return list[1]
end
function Cr.SetViewProf(p) ns.db.profView = p Cr.sel = nil end
-- (Daniel 21.11.2026) Entzaubern > Herstellen: "mine" (the recipes of this character, as before), "all" (every
-- profession in the data) or one profession (ProfitdonDB.deView)
function Cr.DeView()
  local want = ns.db.deView
  if want == "all" then return "all" end
  for _, p in ipairs(Cr.ProfList()) do if p == want then return p end end
  return "mine"
end
function Cr.SetDeView(v) ns.db.deView = (v ~= "mine") and v or nil Cr.sel = nil end
-- the own characters (this realm) who know a recipe
function Cr.KnownBy(spell)
  local out, me, realm = {}, ns.Me(), "-" .. ns.Realm()
  for char, c in pairs(type(ns.db.crafts) == "table" and ns.db.crafts or {}) do
    if type(c) == "table" and type(c.known) == "table" and c.known[spell] and (char == me or char:sub(-#realm) == realm) then
      out[#out + 1] = char
    end
  end
  table.sort(out, function(a, b) if a == me then return true elseif b == me then return false end return a < b end)
  return out
end
-- the rows of the profession: mode "vendor" or "ah" as in Cr.Rows, every recipe, learnable or known
-- (Daniel 21.11.2026, Bild Entzaubern > Herstellen: "alle rezepte und alle berufe auswählbar machen") also mode "de"
-- (crafts to disenchant) and prof "all": every profession, each valued as if at its own top
function Cr.ProfRows(prof, mode)
  local st = { known = 0, price = 0, data = 0, below = 0, noAH = 0, noDE = 0 }
  local ok, rows = pcall(function()
    local out, seen = {}, {}
    local all = ns.db.craftAll
    local function one(spell, pf)
      if seen[spell] then return end
      local r = Cr.Recipe(spell)
      if not (r and r.prof == pf) then return end
      seen[spell] = true
      st.known = st.known + 1
      -- (all professions: only gear gets valued, the rest is skipped before the costly part)
      if mode == "de" and r.item and r.item > 0 and not ns.DE.Group(r.item) then st.noDE = st.noDE + 1 return end
      local v, why = Cr.Value(r)
      if not v then st[why or "data"] = (st[why or "data"] or 0) + 1 return end
      local profit
      if mode == "de" then profit = v.deProfit elseif mode == "ah" then profit = v.ahExpProfit or v.ahProfit else profit = v.profit end
      if not profit then if mode == "de" then st.noDE = st.noDE + 1 else st.noAH = st.noAH + 1 end return end
      if not (all or ns.Deals.Worth(profit, v.cost)) then st.below = st.below + 1 return end
      if mode == "vendor" and v.sellGuess and profit > 0 then st.wait = (st.wait or 0) + 1 return end
      v.mode, v.show, v.view = mode, profit, true
      v.knownBy = Cr.KnownBy(spell)
      if mode == "vendor" then Cr.RunsOf(v) end
      out[#out + 1] = v
    end
    -- each profession on its own: the cache and the made-on-the-way steps belong to the profession assumed
    for _, pf in ipairs(prof == "all" and Cr.ProfList() or { prof }) do
      Cr.cache, Cr.assume = {}, pf
      for spell in pairs(ns.CRAFTS or {}) do one(spell, pf) end
      for spell in pairs(type(ns.db.craftExtra) == "table" and ns.db.craftExtra or {}) do one(spell, pf) end
    end
    table.sort(out, function(a, b) if a.show ~= b.show then return a.show > b.show end return a.r.spell < b.r.spell end)
    return out
  end)
  Cr.cache, Cr.assume = nil, nil
  if not ok then error(rows, 0) end
  return rows, st.price, st
end
Cr.ProfRows = Memo("ProfRows", Cr.ProfRows)
