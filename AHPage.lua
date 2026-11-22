local _, ns = ...

---------------------------------------------------------------------------
-- (Daniel 20.11.2026: "Ich möchte, dass das Auktionshausfenster von Blizzard gar nicht mehr aufgeht und wir die Funktionen
-- in Profitdon übernehmen ... normales Kaufen und Suchen ... links die Spalte mit allen Gegenstandsklassen ... oben suchen,
-- dann kaufen: Anzahl, Preisvorschau für die Anzahl ... als ERSTER Reiter ... oben ein Knopf 'Blizzards AH anzeigen'")
-- The page Kaufen, the first book tab of the window:
--   left:   the item classes as heads with their sub classes (Blizzard's own table AuctionCategories when the game has it,
--           else built from the item classes of the client); a head or a sub class searches it
--   top:    search text (Enter or "Suchen"), the count of results, "Mehr" while the AH has more
--   middle: the browse results (C_AuctionHouse.SendBrowseQuery): item, on offer, cheapest, median of the last days and the
--           trend (History.lua); a click picks a result and searches its offers (Buy.lua ns.Select kind "ah")
--   bottom: the picked item: median and trend, the amount (free number, as in the shopping list), "Max" (what the gold and
--           the cap per click buy), the price preview for the amount (total, average, dearest offer), "Kaufen" (ns.BuyNow)
-- Buying is Buy.lua's one way (commodities: StartCommoditiesPurchase, confirmed when the quote is not higher; items: one
-- auction a click with PlaceBid), from the button's own click.
-- Blizzard's window: while the option ahHide is on (default), AuctionHouseFrame stays open (its OnHide would close the
-- AH) but is moved off the screen and see-through; the button "Blizzard-AH" over the list brings it back for this visit
-- (a second press hides it again). A watcher puts it away again when the game's panel layout moved it back.
---------------------------------------------------------------------------
local Kit = LibStub("DonCore-1.0"):Get("Kit", 23)
local C, S = Kit.C, Kit.SIZE
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local function M(c) return c and Kit.Money(c) or "" end

local A = { open = {}, results = {}, state = "idle" }
ns.AHBrowse = A

---------------------------------------------------------------------------
-- Blizzard's auction window: away or back
---------------------------------------------------------------------------
local F = {}
ns.AHFrameState = F
local OFF = -10000
local function Frame() return _G.AuctionHouseFrame end
local function Away(f)
  local l = tonumber((ns.Call(f.GetLeft, f)))
  return l ~= nil and l < OFF / 2
end
-- the option on and not shown by the button for this visit
function ns.AHHideWanted() return ns.Opt("ahHide") ~= false and not F.shown end

local function SavePoints(f)
  local pts = {}
  local n = tonumber((ns.Call(f.GetNumPoints, f))) or 0
  for i = 1, n do
    local p = { ns.Call(f.GetPoint, f, i) }
    if p[1] then pts[#pts + 1] = p end
  end
  return pts
end

-- returns true when the window was put away
function ns.AHFrameHide()
  local f = Frame()
  if not (f and f.SetAlpha and f.SetPoint and f.ClearAllPoints) then return false end
  if not Away(f) then F.points = SavePoints(f) end
  ns.Call(f.SetAlpha, f, 0)
  if f.SetClampedToScreen then ns.Call(f.SetClampedToScreen, f, false) end
  ns.Call(f.ClearAllPoints, f)
  ns.Call(f.SetPoint, f, "TOPRIGHT", UIParent, "TOPLEFT", OFF, 0)
  F.hidden = true
  return true
end

function ns.AHFrameShow()
  local f = Frame()
  F.hidden = false
  if not f then return false end
  ns.Call(f.SetAlpha, f, 1)
  if F.points and #F.points > 0 then
    ns.Call(f.ClearAllPoints, f)
    for _, p in ipairs(F.points) do ns.Call(f.SetPoint, f, unpack(p)) end
  end
  F.points = nil
  return true
end

-- the button "Blizzard-AH": shown for this visit, or away again
function ns.AHFrameToggle()
  if not ns.ScanState.open then return end
  if F.hidden then
    F.shown = true
    ns.AHFrameShow()
    if ns.AHDock then ns.AHDock("right") end
  else
    F.shown = nil
    if ns.Opt("ahHide") ~= false then ns.AHFrameHide() end
  end
  if ns.Refresh then ns.Refresh() end
end

-- Profitdon's window shut while the AH is open and Blizzard's window away: the AH is left too (nothing would show it)
function ns.AHLeave()
  if not (ns.ScanState.open and F.hidden) or F.left then return end
  F.left = true
  local f = Frame()
  if f and _G.HideUIPanel then ns.Call(_G.HideUIPanel, f)
  elseif ns.AH.CloseAuctionHouse then ns.Call(ns.AH.CloseAuctionHouse) end
end

ns.On("AUCTION_HOUSE_CLOSED", function()
  -- the window as the game left it, for the next opening (and for the option switched off)
  if F.hidden then ns.AHFrameShow() end
  F.shown, F.hidden, F.points, F.left = nil, nil, nil, nil
  A.results, A.state, A.sel, A.msg, A.full = {}, "idle", nil, nil, nil
end)

-- the watcher: the game's panel layout (another panel opened) can set the window's place again
local watch = CreateFrame("Frame")
local tick = 0
watch:SetScript("OnUpdate", function(_, dt)
  tick = tick + (tonumber(dt) or 0)
  if tick < 0.5 then return end
  tick = 0
  if not (F.hidden and ns.ScanState.open) then return end
  local f = Frame()
  if f and not Away(f) then ns.Try(ns.AHFrameHide) end
end)

---------------------------------------------------------------------------
-- Categories
---------------------------------------------------------------------------
-- Classic's item classes in the order of the game's auction window (Enum.ItemClass numbers)
local ORDER = { 2, 4, 1, 0, 7, 6, 11, 9, 5, 3, 15, 12 }
local function ClassName(c)
  return ns.Call(C_Item and C_Item.GetItemClassInfo, c) or ns.Call(_G.GetItemClassInfo, c)
end
local function SubName(c, s)
  return ns.Call(C_Item and C_Item.GetItemSubClassInfo, c, s) or ns.Call(_G.GetItemSubClassInfo, c, s)
end
local function SubClasses(c)
  local r = { ns.Call(ns.AH.GetAuctionItemSubClasses, c) }
  if type(r[1]) ~= "table" and #r == 0 then r = { ns.Call(_G.GetAuctionItemSubClasses, c) } end
  if type(r[1]) == "table" then r = r[1] end
  return r
end

-- (Daniel 20.11.2026: "juwelier kann raus wir sind bei wow forever") categories WoW Forever does not have: Jewelcrafting
-- (recipes 9/10, trade goods 7/4), by the filters (every language) and by the name
local DROP = { ["9:10"] = true, ["7:4"] = true }
local DROP_NAME = { "jewelcraft", "juwelier", "joaill", "joyer", "joalh", "ювелир" }
local function Dropped(src)
  local f = type(src.filters) == "table" and src.filters or {}
  local n, hit = 0, 0
  for _, x in ipairs(f) do
    if type(x) == "table" then
      n = n + 1
      if DROP[tostring(x.classID) .. ":" .. tostring(x.subClassID)] then hit = hit + 1 end
    end
  end
  if n > 0 and hit == n then return true end
  local name = type(src.name) == "string" and src.name:lower() or ""
  for _, w in ipairs(DROP_NAME) do if name:find(w, 1, true) then return true end end
  return false
end
ns.AHDropped = Dropped -- (tests)

local function FromGame(ac)
  local out = {}
  for i, c in ipairs(ac) do
    local token = type(c.flags) == "table" and c.flags.WOW_TOKEN_FLAG
    if type(c) == "table" and type(c.name) == "string" and not token then
      local cat = { key = "g" .. i, name = c.name, filters = type(c.filters) == "table" and c.filters or {}, subs = {} }
      -- (Daniel 20.11.2026, Bild: "keine stäbe oder so?") Blizzard's table has a third level (One-Handed: Axes, Maces,
      -- Swords ...; Two-Handed: Staves ...): read as deep as it goes
      local function Subs(node, src, depth)
        for j, s in ipairs(type(src.subCategories) == "table" and src.subCategories or {}) do
          if type(s) == "table" and type(s.name) == "string" and not Dropped(s) then
            local sub = { key = node.key .. "_" .. j, name = s.name, filters = type(s.filters) == "table" and s.filters or {}, parent = node,
              subs = {}, depth = depth }
            if depth < 3 then Subs(sub, s, depth + 1) end
            node.subs[#node.subs + 1] = sub
          end
        end
      end
      Subs(cat, c, 1)
      out[#out + 1] = cat
    end
  end
  return out
end

local function FromClasses()
  local out = {}
  for _, c in ipairs(ORDER) do
    local name = ClassName(c)
    if type(name) == "string" and name ~= "" then
      local cat = { key = "c" .. c, name = name, filters = { { classID = c } }, subs = {} }
      for _, s in ipairs(SubClasses(c)) do
        s = tonumber(s)
        local sn = s and SubName(c, s)
        if type(sn) == "string" and sn ~= "" and not Dropped({ name = sn, filters = { { classID = c, subClassID = s } } }) then
          cat.subs[#cat.subs + 1] = { key = cat.key .. "_" .. s, name = sn, filters = { { classID = c, subClassID = s } }, parent = cat }
        end
      end
      out[#out + 1] = cat
    end
  end
  return out
end

-- the tree: the game's table once it is there (Blizzard_AuctionHouseUI loads with the AH), else the item classes
function ns.AHCategories()
  if A.cats and A.catsFrom == "game" then return A.cats, "game" end
  local ac = _G.AuctionCategories
  if type(ac) == "table" and #ac > 0 then
    local cats = FromGame(ac)
    if #cats > 0 then A.cats, A.catsFrom = cats, "game" return cats, "game" end
  end
  if not A.cats then A.cats, A.catsFrom = FromClasses(), "classes" end
  return A.cats, A.catsFrom
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
local function Sorts()
  local E = Enum and Enum.AuctionHouseSortOrder
  return { { sortOrder = E and E.Price or 0, reverseSort = false } }
end

---------------------------------------------------------------------------
-- Filters (Daniel 20.11.2026: "Stufe und Qualität und Filter muss ja auch ... muss ja schon mit drin sein")
-- Blizzard's browse filters: the required level from/to (query minLevel/maxLevel), the qualities and the flags
-- (query filters, Enum.AuctionHouseFilter). Kept in ProfitdonDB.ui.ahFilter across sessions:
--   { minLevel, maxLevel, q = { [quality] = false when left out }, usable, exact, open (the filter row shown) }
-- Assumptions: the Enum names are those of the modern AH API (PoorQuality ... LegendaryQuality, UsableOnly, ExactMatch);
-- a name the client lacks is skipped (its control hidden); level 0 means "no limit", as Blizzard's own boxes send it.
-- No quality filter in the query means all qualities (the default); a chosen subset sends its qualities.
---------------------------------------------------------------------------
-- quality number, Enum.AuctionHouseFilter name, German name when the client has no ITEM_QUALITYn_DESC
-- (Artifact and Heirloom left out: Classic has no such items)
local QUALS = {
  { 0, "PoorQuality", "Schlecht" }, { 1, "CommonQuality", "Verbreitet" }, { 2, "UncommonQuality", "Selten" },
  { 3, "RareQuality", "Rar" }, { 4, "EpicQuality", "Episch" }, { 5, "LegendaryQuality", "Legendär" },
}
-- the flags that make sense on a Classic based client (UncollectedOnly and UpgradesOnly do not)
local FLAGS = {
  -- (Daniel 20.11.2026, Bild: "nur benutzbar armor kommt nichts, level 10 mage") the server's UsableOnly answers nothing on
  -- Forever: checked here (wearable by the class and the required level reached)
  { key = "usable", client = true, label = "Nur benutzbar",
    tip = { "Nur benutzbar", { "Nur, was deine Klasse tragen kann und deine Stufe schon erlaubt." } } },
  { key = "exact", enum = "ExactMatch", label = "Genauer Name",
    tip = { "Genauer Name", { "Nur Gegenstände, deren Name genau dem Suchtext entspricht." } } },
  -- (Daniel 20.11.2026: "Filter kann ich tragen ... je nach Klasse und Rüstungsart, dass er dann nur das angezeigt bekommt,
  -- was man auch tragen kann") no server filter: the result rows are checked here (Wearable)
  { key = "wear", client = true, label = "Kann ich tragen",
    tip = { "Kann ich tragen", { "Nur Rüstung und Waffen, die deine Klasse tragen kann (Stoff, Leder, Kette, Platte, Schilde, Waffenarten).",
      "Alles andere (Mats, Verbrauchbares, Schmuck) bleibt sichtbar." } } },
  -- (Daniel 20.11.2026, Bild Rezepte: "einen Filter, dass nur Unbekannte angezeigt werden. Also für den Charakter
  -- Unbekannte") recipes this character already knows are hidden (ns.AHRecipeKnown); other items stay
  { key = "unknown", client = true, label = "Nur unbekannte Rezepte",
    tip = { "Nur unbekannte Rezepte", { "Blendet Rezepte aus, die dieser Charakter schon kann.",
      "Alles, was kein Rezept ist, bleibt sichtbar." } } },
}

-- does this character know the recipe item id already? true / false; nil when it is no recipe or cannot be told.
-- First the recipes Profitdon recorded for this character (ns.LEARN: spell -> recipe item), then the item's tooltip
-- ("Bereits bekannt", ITEM_SPELL_KNOWN), cached once the tooltip had text.
local recipeSpells, knownTip = nil, {}
local function RecipeSpells()
  if recipeSpells then return recipeSpells end
  recipeSpells = {}
  for spell, d in pairs(ns.LEARN or {}) do
    local item = type(d) == "table" and tonumber(d[3])
    if item and item > 0 then
      local l = recipeSpells[item] or {}
      l[#l + 1] = spell
      recipeSpells[item] = l
    end
  end
  return recipeSpells
end
local scanTip
local function TipKnown(id)
  if knownTip[id] ~= nil then return knownTip[id] end
  local word = rawget(_G, "ITEM_SPELL_KNOWN")
  if type(word) ~= "string" or not CreateFrame then return nil end
  if not scanTip then
    local ok, t = pcall(CreateFrame, "GameTooltip", "ProfitdonScanTip", nil, "GameTooltipTemplate")
    if not (ok and t) then return nil end
    scanTip = t
  end
  scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not pcall(scanTip.SetItemByID, scanTip, id) then return nil end
  local n = scanTip.NumLines and scanTip:NumLines() or 0
  if n == 0 then return nil end
  local hit = false
  for i = 2, n do
    local fs = _G["ProfitdonScanTipTextLeft" .. i]
    local s = fs and fs.GetText and fs:GetText()
    if s == word then hit = true break end
  end
  knownTip[id] = hit
  scanTip:Hide()
  return hit
end
function ns.AHRecipeKnown(id)
  id = tonumber(id)
  if not id then return nil end
  local get = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
  local classID = type(get) == "function" and ns.Num((select(6, ns.Call(get, id))))
  if classID ~= 9 then return nil end
  local c = type(ns.db and ns.db.crafts) == "table" and ns.db.crafts[ns.Me()]
  local known = type(c) == "table" and type(c.known) == "table" and c.known
  if known then
    for _, spell in ipairs(RecipeSpells()[id] or {}) do if known[spell] then return true end end
  end
  return TipKnown(id) or false
end
function ns.AHRecipeKnownReset() recipeSpells, knownTip = nil, {} end -- (tests)

-- (Daniel 20.11.2026: "bei Rezepten fehlt mir noch die Fertigkeitsstufe als Spalte") the skill a recipe item asks for:
-- the recipe Profitdon knows for it (ns.LEARN, Crafts), else the item's tooltip ("Requires Cooking (175)",
-- ITEM_MIN_SKILL), cached once the tooltip had text. nil when it is no recipe or cannot be told.
local skillTip, skillPat = {}, nil
local function TipSkill(id)
  if skillTip[id] ~= nil then return skillTip[id] or nil end
  local word = rawget(_G, "ITEM_MIN_SKILL")
  if type(word) ~= "string" or not CreateFrame then return nil end
  if not skillPat then
    skillPat = "^" .. word:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%d?%$?s", ".+"):gsub("%%%d?%$?d", "(%%d+)") .. "$"
  end
  if not scanTip then
    local ok, t = pcall(CreateFrame, "GameTooltip", "ProfitdonScanTip", nil, "GameTooltipTemplate")
    if not (ok and t) then return nil end
    scanTip = t
  end
  scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not pcall(scanTip.SetItemByID, scanTip, id) then return nil end
  local n = scanTip.NumLines and scanTip:NumLines() or 0
  if n == 0 then return nil end
  local hit = false
  for i = 2, n do
    local fs = _G["ProfitdonScanTipTextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    local v = type(t) == "string" and tonumber(t:match(skillPat))
    if v then hit = v break end
  end
  skillTip[id] = hit
  scanTip:Hide()
  return hit or nil
end
function ns.AHRecipeSkill(id)
  id = tonumber(id)
  if not id then return nil end
  local get = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
  local classID = type(get) == "function" and ns.Num((select(6, ns.Call(get, id))))
  if classID ~= 9 then return nil end
  local best
  for _, spell in ipairs(RecipeSpells()[id] or {}) do
    local r = ns.Crafts and ns.Crafts.Recipe(spell)
    local v = r and tonumber(r.learn)
    if v and v > 0 and (not best or v < best) then best = v end
  end
  return best or TipSkill(id)
end
function ns.AHRecipeSkillReset() skillTip, skillPat = {}, nil end -- (tests)

-- armour and weapon subclasses each class can use (Dropdon/Filter.lua CLASS_USE, Classic proficiencies; where unsure
-- allowed). Armour: 0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem. Weapons: 0 axe,
-- 1 2H axe, 2 bow, 3 gun, 4 mace, 5 2H mace, 6 polearm, 7 sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown,
-- 18 crossbow, 19 wand.
local function Set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end return t end
local CLASS_USE = {
  WARRIOR = { armor = Set(0, 1, 2, 3, 4, 6), weapon = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18) },
  PALADIN = { armor = Set(0, 1, 2, 3, 4, 6, 7), weapon = Set(0, 1, 4, 5, 6, 7, 8) },
  HUNTER = { armor = Set(0, 1, 2, 3), weapon = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18) },
  ROGUE = { armor = Set(0, 1, 2), weapon = Set(0, 2, 3, 4, 7, 13, 15, 16, 18) },
  PRIEST = { armor = Set(0, 1), weapon = Set(4, 10, 15, 19) },
  SHAMAN = { armor = Set(0, 1, 2, 3, 6, 9), weapon = Set(0, 1, 4, 5, 10, 13, 15) },
  MAGE = { armor = Set(0, 1), weapon = Set(7, 10, 15, 19) },
  WARLOCK = { armor = Set(0, 1), weapon = Set(7, 10, 15, 19) },
  DRUID = { armor = Set(0, 1, 2, 8), weapon = Set(4, 5, 6, 10, 13, 15) },
}
-- can this class wear or wield the item? Anything not armour or weapon, an unknown class or item: yes (a filter never
-- hides what it cannot judge)
function ns.AHWearable(id)
  local get = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
  if type(get) ~= "function" or not id then return true end
  local ok, _, _, _, _, icon, classID, subID = pcall(get, id)
  classID, subID = ok and ns.Num(classID), ok and ns.Num(subID)
  if not (ok and icon and classID) then return true end
  local _, token = ns.Call(UnitClass, "player")
  local use = token and CLASS_USE[token]
  if not use then return true end
  if classID == 4 then return subID == nil or use.armor[subID] == true or subID > 9 end
  if classID == 2 then return subID == nil or use.weapon[subID] == true end
  return true
end
ns.AH_QUALS, ns.AH_FLAGS = QUALS, FLAGS -- (tests)
local MAXLEVEL = 999

local function FilterEnum()
  local E = Enum and Enum.AuctionHouseFilter
  return type(E) == "table" and E or nil
end
local function EnumVal(name)
  local E = FilterEnum()
  local v = E and E[name]
  return type(v) == "number" and v or nil
end
ns.AHFilterEnum = EnumVal -- (tests)

-- the saved filters (made when missing)
function ns.AHFilter()
  if not ns.db then A.tmpFilter = A.tmpFilter or { q = {} } return A.tmpFilter end
  if type(ns.db.ui) ~= "table" then ns.db.ui = {} end
  local f = ns.db.ui.ahFilter
  if type(f) ~= "table" then f = {} ns.db.ui.ahFilter = f end
  if type(f.q) ~= "table" then f.q = {} end
  return f
end

-- a level as typed: a whole number 1..MAXLEVEL, else nil (no limit)
local function Level(v)
  v = tonumber(v)
  if not v or v < 1 then return nil end
  return min(MAXLEVEL, floor(v))
end

-- the levels of the filter, from below the upper (swapped when typed the wrong way round)
function ns.AHLevels()
  local f = ns.AHFilter()
  local lo, hi = Level(f.minLevel), Level(f.maxLevel)
  if lo and hi and lo > hi then lo, hi = hi, lo end
  return lo, hi
end

-- the query's filter list, the levels and how many filters are on (for the button "Filter (n)")
function ns.AHQueryFilters()
  local f = ns.AHFilter()
  local list, n = {}, 0
  local chosen, left = {}, false
  for _, d in ipairs(QUALS) do
    local v = EnumVal(d[2])
    if v then
      if f.q[d[1]] == false then left = true else chosen[#chosen + 1] = v end
    end
  end
  if left and #chosen > 0 then
    for _, v in ipairs(chosen) do list[#list + 1] = v end
    n = n + 1
  end
  for _, fl in ipairs(FLAGS) do
    local v = fl.enum and EnumVal(fl.enum)
    if f[fl.key] and v then list[#list + 1] = v n = n + 1 end
    if f[fl.key] and fl.client then n = n + 1 end
  end
  local lo, hi = ns.AHLevels()
  if lo or hi then n = n + 1 end
  return list, lo, hi, n
end

-- everything back to Blizzard's default (all qualities, no level, no flag); the row stays as it is
function ns.AHFilterReset()
  local f = ns.AHFilter()
  f.minLevel, f.maxLevel, f.q = nil, nil, {}
  for _, fl in ipairs(FLAGS) do f[fl.key] = nil end
end

-- a short sign of the filters, to search again only when they changed
local function FilterSig()
  local list, lo, hi = ns.AHQueryFilters()
  return table.concat(list, ",") .. "|" .. tostring(lo or 0) .. "|" .. tostring(hi or 0)
end

-- (Daniel 20.11.2026, Bilder: "Die Auflistung unten kriege ich gar nicht mehr weg. Wenn ich irgendwo wegklicke, dann soll
-- das auch weggehen", "selbst wenn ich eine andere Kategorie auswähle, dann bleibt das da") the picked item let go: its
-- offers, the price tiers and the buy area empty again (only Buy.lua's own entry of this page)
function ns.AHUnpick()
  A.sel = nil
  local B = ns.BuyState
  if B and B.kind == "ah" then
    B.entry, B.plan, B.ladder, B.itemOffers, B.maxQty, B.msg, B.armed = nil, nil, nil, nil, nil, nil, nil
    B.state = "idle"
  end
end

-- start over (the x in the search box): no text, Alle Kategorien, no results, nothing picked; the filters stay
function ns.AHReset()
  ns.AHUnpick()
  A.text, A.cat, A.results, A.state, A.msg, A.full, A.hidden = "", nil, {}, nil, nil, nil, 0
end

-- the browse query of the search text and the chosen category; waits while the AH's message system is busy
function ns.AHSearch()
  knownTip = {} -- (a recipe learned since the last search shows as known)
  ns.AHUnpick()
  if not ns.ScanState.open then A.msg = "Dafür das Auktionshaus öffnen." return false end
  if not ns.AH.SendBrowseQuery then A.msg = "Suche geht in diesem Client nicht." return false end
  local ready = ns.AH.IsThrottledMessageSystemReady
  if ready and ns.Call(ready) == false then
    A.msg = "Das Auktionshaus ist noch beschäftigt, Suche gleich..."
    if not A.retry then
      A.retry = true
      ns.After(0.5, function() A.retry = nil if ns.ScanState.open then ns.AHSearch() if ns.Refresh then ns.Refresh() end end end)
    end
    return false
  end
  local cat = A.cat
  local filters, lo, hi = ns.AHQueryFilters()
  local q = { searchString = A.text or "", sorts = Sorts(), filters = filters, itemClassFilters = cat and cat.filters or {} }
  -- (as Blizzard's level boxes: an empty side is 0, no limit)
  if lo or hi then q.minLevel, q.maxLevel = lo or 0, hi or 0 end
  A.fsig = FilterSig()
  A.query, A.state, A.results, A.full, A.msg = q, "waiting", {}, nil, nil
  ns.browseOwner = "page"
  ns.Call(ns.AH.SendBrowseQuery, q)
  ns.After(6, function()
    if A.query == q and A.state == "waiting" then
      A.state, A.msg = "done", "Keine Antwort vom Auktionshaus. Nochmal suchen."
      if ns.Refresh then ns.Refresh() end
    end
  end)
  return true
end

-- (Daniel 20.11.2026: "den Gegenstand direkt im AH suchen, um vielleicht das Rezept zu sehen") from another list: the
-- name searched in Kaufen, in Alle Kategorien (a recipe's name holds the name of what it makes: both show)
function ns.AHFind(text)
  if type(text) ~= "string" or text == "" then return false end
  A.cat = nil
  if ns.SetTab then ns.SetTab("ah") end
  local p = ns.ahPage
  if p and p.text and p.text.SetText then p.text:SetText(text) end
  A.text = text
  local sent = ns.AHSearch()
  if ns.Refresh then ns.Refresh() end
  return sent
end

-- (Daniel 21.11.2026: "shift + linksklick auf ein item in der bag, dann soll es in der ah suche auftauchen") a shift
-- click on an item (bags, Baganator, chat links) ends in ChatEdit_InsertLink; while Kaufen is on the screen and no chat
-- line is open, its name is searched there. Blizzard's own window does the same with its hidden search bar, harmless.
local lastLink, lastAt
function ns.AHLinkClick(text)
  if type(text) ~= "string" or not text:find("|Hitem:", 1, true) then return false end
  local p = ns.ahPage
  if not (p and p.IsVisible and p:IsVisible()) then return false end
  local CFU = _G.ChatFrameUtil
  local getActive = (CFU and CFU.GetActiveWindow) or _G.ChatEdit_GetActiveWindow
  if getActive and getActive() then return false end
  -- one click can pass several of the hooked functions (HandleModifiedItemClick, then InsertLink): searched once
  local now = (_G.GetTime and GetTime()) or 0
  if lastLink == text and lastAt and now - lastAt < 0.3 then return false end
  local name = (_G.GetItemInfo and (GetItemInfo(text))) or text:match("|h%[(.-)%]|h")
  if not name or name == "" then return false end
  lastLink, lastAt = text, now
  ns.AHFind(name)
  return true
end
-- (Daniel 22.11.2026: "klappt nicht" with Baganator) Baganator calls ChatFrameUtil.InsertLink where the client has it,
-- not ChatEdit_InsertLink; Blizzard's bags go through HandleModifiedItemClick. All three are hooked.
if _G.hooksecurefunc then
  local function hit(text) ns.Call(ns.AHLinkClick, text) end
  if _G.ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", hit) end
  if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink then hooksecurefunc(_G.ChatFrameUtil, "InsertLink", hit) end
  if _G.HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if _G.IsModifiedClick and IsModifiedClick("CHATLINK") then hit(link) end
    end)
  end
end

-- a filter changed: searched again at once when there was a search and its filters differ (Enter and the focus lost
-- of a level box both land here; the sign keeps it to one query)
function ns.AHFilterApply()
  if not ns.ScanState.open or A.state == "idle" then return false end
  if A.fsig == FilterSig() then return false end
  return ns.AHSearch()
end

function ns.AHMore()
  if A.state ~= "done" or A.full or not ns.AH.RequestMoreBrowseResults then return end
  ns.browseOwner = "page"
  ns.Call(ns.AH.RequestMoreBrowseResults)
end

local function KeyInfo(k)
  local info = ns.Call(ns.AH.GetItemKeyInfo, k)
  return type(info) == "table" and info or nil
end

local function Read()
  local list = ns.Call(ns.AH.GetBrowseResults)
  if type(list) ~= "table" then return end
  local out = {}
  for _, r in ipairs(list) do
    local k = type(r) == "table" and r.itemKey
    local id = type(k) == "table" and ns.Num(k.itemID)
    if id then
      out[#out + 1] = { itemKey = k, id = id, min = ns.Num(r.minPrice), qty = ns.Num(r.totalQuantity), own = r.containsOwnerItem and true or nil }
    end
  end
  A.results = out
  local full = ns.AH.HasFullBrowseResults and ns.Call(ns.AH.HasFullBrowseResults)
  A.full = full ~= false
  A.state = "done"
  if ns.Refresh then ns.Refresh() end
end
local function OnBrowse()
  if ns.browseOwner ~= "page" then return end
  Read()
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)
ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", function() if ns.WindowTab and ns.WindowTab() == "ah" and ns.RefreshSoon then ns.RefreshSoon() end end)

-- a result picked: its offers searched, the amount of the box kept
function ns.AHPick(r, want)
  if not r then return end
  A.sel = r
  local w = tonumber(want) or (A.entry and A.entry.want)
  if not w or w < 1 then w = 1 end
  A.entry = { id = r.id, itemKey = r.itemKey, want = math.floor(w), browseMin = r.min, ah = true }
  ns.Select(A.entry, "ah")
end

-- the cheapest of the results first unless a column head was clicked
local SORTERS = {
  title = function(a, b) return (a.name or "") < (b.name or "") end,
  lvl = function(a, b) return (a.lvl or 0) < (b.lvl or 0) end,
  skill = function(a, b) return (a.skill or 0) < (b.skill or 0) end,
  qty = function(a, b) return (a.qty or 0) > (b.qty or 0) end,
  price = function(a, b) return (a.min or math.huge) < (b.min or math.huge) end,
  med = function(a, b) return (a.med or math.huge) < (b.med or math.huge) end,
  trend = function(a, b) return (a.pct or 0) < (b.pct or 0) end,
}

---------------------------------------------------------------------------
-- Median and trend text (History.lua)
---------------------------------------------------------------------------
local function TrendColor(dir) return dir == "up" and C.red or dir == "down" and C.green or nil end
function ns.AHHistLine(id, now)
  local H = ns.History
  if not (H and id) then return "" end
  local n = H.Window()
  local med, days = H.Median(id, n)
  if not med then return "Noch kein Preisverlauf: jeder Vollscan schreibt einen Tag mit." end
  local s = ("Median %d Tage %s (%d %s)"):format(n, M(med), days, days == 1 and "Tag mit Scan" or "Tage mit Scan")
  local pct, dir = H.Trend(id, n)
  if pct then s = s .. ("  ·  Tendenz %s %s"):format(H.WORD[dir], H.TrendText(id, n)) end
  if now and med > 0 then
    local x = (now - med) * 100 / med
    local d = x >= 0 and floor(x + 0.5) or -floor(-x + 0.5)
    s = s .. ("  ·  jetzt %s"):format(d == 0 and "wie der Median" or d > 0 and (d .. " % über dem Median") or (-d .. " % unter dem Median"))
  end
  return s
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local CAT_W = 190
local BUY_H = 104
local TIER_H = 150 -- the offer list per price tier (Daniel 20.11.2026, mockup scratch/mockups/angebotsliste.html)
local OVER = 25 -- percent over the median from which a tier is marked red
local LINE_H = 28 -- a line of the search head and of the filter row

-- a quality's name in the client's language, in its color
local function QualLabel(d)
  local name = rawget(_G, "ITEM_QUALITY" .. d[1] .. "_DESC")
  if type(name) ~= "string" or name == "" then name = d[3] end
  local c = Kit.QualityColor and Kit.QualityColor(d[1])
  if type(c) ~= "table" or not tonumber(c[1]) then return name end
  local function h(x) return ("%02x"):format(max(0, min(255, floor((tonumber(x) or 0) * 255 + 0.5)))) end
  return ("|cff%s%s%s%s|r"):format(h(c[1]), h(c[2]), h(c[3]), name)
end

-- the text of the filter button: "Filter" or "Filter (n)"
function ns.AHFilterText()
  local _, _, _, n = ns.AHQueryFilters()
  return n > 0 and ("Filter (%d)"):format(n) or "Filter"
end

-- controls flowing in lines: { { f, w, gap } ... }, a new line when the width runs out; returns the lines used
-- and puts each at its x and line (f._fx, f._fl, f._fw for the tests)
local function Flow(parent, items, x0, y0, width)
  local line, x = 0, 0
  for _, it in ipairs(items) do
    local w = it[2]
    if x > 0 and x + w > width then line, x = line + 1, 0 end
    local f = it[1]
    f._fx, f._fl, f._fw = x, line, w
    f:ClearAllPoints()
    f:SetPoint("LEFT", parent, "TOPLEFT", x0 + x, y0 - line * LINE_H - LINE_H / 2)
    if it.layout then f:Layout(w) end
    x = x + w + (it[3] or 10)
  end
  return line + 1
end

local function CatItems()
  local cats = ns.AHCategories()
  local out = {}
  out[#out + 1] = { kind = "cat", title = "Alle Kategorien", current = A.cat == nil or nil, cat = false, depth = 0 }
  for _, c in ipairs(cats) do
    local open = A.open[c.key] and true or false
    out[#out + 1] = { kind = "group", text = c.name, plainCase = true, collapsed = not open, static = #c.subs == 0 or nil, cat = c,
      color = A.cat == c and C.green or nil }
    -- (Daniel 20.11.2026, Bild: "kästchen sind nur da und machen nichts") the sub rows are plain text rows (kind "cat"),
    -- not Questdon's chain steps with their box; a sub with own subs opens with + and -
    local function Add(list, depth)
      for _, s in ipairs(list) do
        local has = s.subs and #s.subs > 0
        local sopen = has and A.open[s.key] and true or false
        out[#out + 1] = { kind = "cat", title = s.name, cat = s, depth = depth, sign = has and (sopen and "-" or "+") or nil,
          current = A.cat == s or nil }
        if sopen then Add(s.subs, depth + 1) end
      end
    end
    if open then Add(c.subs, 1) end
  end
  return out
end

local function ResultItems()
  local H = ns.History
  local B = ns.BuyState
  local items = {}
  local f = ns.AHFilter()
  local wear, usable = f.wear, f.usable
  local myLevel = ns.Num(ns.Call(UnitLevel, "player"))
  local GI = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
  A.hidden = 0
  for _, r in ipairs(A.results or {}) do
    -- the required level (GetItemInfo's fifth value; ns.ItemInfo's fourth is the icon)
    r.lvl = ns.Num((select(5, ns.Call(GI, r.id))))
    r.skill = ns.AHRecipeSkill(r.id)
    if (wear or usable) and not ns.AHWearable(r.id) then A.hidden = A.hidden + 1 r = nil
    elseif usable and r.lvl and myLevel and r.lvl > myLevel then A.hidden = A.hidden + 1 r = nil
    elseif f.unknown and ns.AHRecipeKnown(r.id) then A.hidden = A.hidden + 1 r = nil end
    if r then
    local info = KeyInfo(r.itemKey)
    local name, _, quality = ns.ItemInfo(r.id)
    r.name = (info and info.itemName) or name or ("Item " .. r.id)
    r.quality = (info and ns.Num(info.quality)) or quality
    -- (21.11.2026, Ruckler) median and trend kept per item (History.lua H.Info)
    local tt, col, dir, pct = "", nil, nil, nil
    r.med = nil
    if H then r.med, _, tt, col, dir, pct = H.Info(r.id) end
    r.pct = pct
    local sub = {}
    if r.own then sub[#sub + 1] = "mit eigenem Angebot" end
    if info and info.isCommodity == false then sub[#sub + 1] = "Einzelauktionen" end
    -- (Daniel 21.11.2026) the tooltip of this variant with its suffix stats: its link once searched, else the item key
    items[#items + 1] = { kind = "trow", title = r.name, quality = r.quality, itemID = r.id, itemKey = r.itemKey, itemLink = ns.KeyLink and ns.KeyLink(r.itemKey) or nil,
      icon = ns.Icon(r.id), sub = table.concat(sub, ", "),
      cells = { lvl = r.lvl and r.lvl > 0 and tostring(r.lvl) or "", skill = r.skill and tostring(r.skill) or "", qty = r.qty and tostring(r.qty) or "", price = M(r.min), med = M(r.med), trend = tt },
      cellColors = { trend = TrendColor(dir) },
      active = (A.sel == r and B.kind == "ah") or nil, result = r }
    end
  end
  local s = A.sort and SORTERS[A.sort]
  if s then
    local ord = {}
    for i, it in ipairs(items) do ord[it] = i end
    table.sort(items, function(a, b)
      local x, y = a.result, b.result
      if s(x, y) then return not A.desc end
      if s(y, x) then return A.desc and true or false end
      return ord[a] < ord[b]
    end)
  end
  return items
end

local function Cols()
  local n = ns.History and ns.History.Window() or 5
  return {
    { key = "title", title = "Gegenstand", sort = true },
    { key = "lvl", title = "Stufe", width = 50, sort = true },
    { key = "skill", title = "Skill", width = 50, sort = true, minWidth = 520, fold = "Skill" },
    { key = "qty", title = "Anzahl", width = 64, sort = true },
    { key = "price", title = "Preis ab", width = 96, sort = true },
    { key = "med", title = ("Median %d T"):format(n), width = 96, sort = true, minWidth = 470, fold = "Median" },
    { key = "trend", title = "Tendenz", width = 70, sort = true, minWidth = 420, fold = "Tendenz" },
  }
end
ns.AHCols = Cols -- (tests)

-- (Daniel 20.11.2026, Bild "Angebotsliste": "Ja, das sieht gut aus") the offers of the picked item per price tier,
-- cheapest first: { price, qty, cum (pieces up to here), take (bought of it by the amount), sum (cost up to here while
-- the amount covers it), state "full" | "part" | nil, over (percent over the median when > OVER), median (the tier the
-- median falls in) }. Commodities from the price ladder of the search, single auctions grouped by price.
function ns.AHTiers()
  local B = ns.BuyState
  local e = B.kind == "ah" and B.entry
  local out = {}
  if not e then return out end
  local raw = {}
  if B.ladder then
    for _, r in ipairs(B.ladder) do
      if r.unitPrice and r.unitPrice > 0 and (r.quantity or 0) > 0 then raw[#raw + 1] = { price = r.unitPrice, qty = r.quantity } end
    end
  elseif B.itemOffers then
    local by = {}
    for _, pr in ipairs(B.itemOffers) do
      if pr and pr > 0 then
        local t = by[pr]
        if not t then t = { price = pr, qty = 0 } by[pr] = t raw[#raw + 1] = t end
        t.qty = t.qty + 1
      end
    end
  end
  table.sort(raw, function(a, b) return a.price < b.price end)
  local want = tonumber(B.want or e.want) or 0
  local med = ns.History and ns.History.Median(e.id)
  local cum, sum, medDone = 0, 0, false
  for _, t in ipairs(raw) do
    local before = cum
    cum = cum + t.qty
    t.cum = cum
    local take = max(0, min(t.qty, want - before))
    if take > 0 then
      sum = sum + take * t.price
      t.take, t.sum = take, sum
      t.state = take == t.qty and "full" or "part"
    end
    if med and med > 0 then
      local pct = floor((t.price / med - 1) * 100 + 0.5)
      if pct > OVER then t.over = pct end
      if not medDone and t.price >= med then t.median, medDone = true, true end
    end
    out[#out + 1] = t
  end
  return out
end

local function TierItems()
  local items = {}
  for _, t in ipairs(ns.AHTiers()) do
    local sub = {}
    if t.state == "part" then sub[#sub + 1] = ("%d von %d"):format(t.take, t.qty) end
    if t.median then sub[#sub + 1] = "Median" end
    if t.over then sub[#sub + 1] = ("über Median +%d %%"):format(t.over) end
    items[#items + 1] = { kind = "trow", title = M(t.price), sub = table.concat(sub, ", "),
      subColor = t.over and C.red or nil,
      markColor = t.state == "full" and C.green or t.state == "part" and (C.yellow or C.gold) or nil,
      active = t.state ~= nil or nil,
      cells = { qty = tostring(t.qty), cum = tostring(t.cum), sum = t.sum and M(t.sum) or "" }, tier = t }
  end
  return items
end
ns.AHTierItems = TierItems -- (tests)
local TIER_COLS = {
  { key = "title", title = "Preis je Stück" },
  { key = "qty", title = "Anzahl", width = 64 },
  { key = "cum", title = "bis hier", width = 70 },
  { key = "sum", title = "Summe bis hier", width = 110 },
}

function ns.AHPage(parent, UI)
  UI = UI or Kit
  local p = CreateFrame("Frame", nil, parent)
  p.UI = UI
  local B = ns.BuyState
  -- left: categories
  p.cats = UI.List(p, {
    kinds = { cat = { h = 22, make = function()
      local b = CreateFrame("Button", nil, p)
      b:SetHeight(22)
      b.hl = b:CreateTexture(nil, "BACKGROUND")
      b.hl:SetAllPoints()
      if b.hl.SetColorTexture then b.hl:SetColorTexture(1, 1, 1, 0.08) end
      b.hl:Hide()
      b.text = UI.Text(b, "row", C.body)
      b:SetScript("OnEnter", function(self) self.hl:Show() end)
      b:SetScript("OnLeave", function(self) if not (self.item and self.item.current) then self.hl:Hide() end end)
      function b:SetItem(it)
        self.item = it
        self.text:ClearAllPoints()
        self.text:SetPoint("LEFT", self, "LEFT", 12 + (it.depth or 0) * 14, 0)
        self.text:SetText((it.sign and (it.sign .. " ") or "") .. (it.title or ""))
        local c = it.current and C.green or (it.depth or 0) == 0 and C.body or C.muted
        if c and self.text.SetTextColor then self.text:SetTextColor(c[1], c[2], c[3]) end
        if it.current then self.hl:Show() else self.hl:Hide() end
      end
      function b:Layout() end
      return b
    end } },
    onClick = function(it) p:PickCat(it) end,
    onToggle = function(it) p:PickCat(it, true) end })
  function p:PickCat(it, toggled)
    if not it or it.cat == nil then return end
    local c = it.cat or nil
    if toggled and c then A.open[c.key] = not it.collapsed end
    -- a sub with own subs: a click opens or shuts them and searches it
    if not toggled and c and it.kind == "cat" and c.subs and #c.subs > 0 then A.open[c.key] = not A.open[c.key] or nil end
    A.cat = c
    ns.AHSearch()
    self:Fill()
  end
  -- top: search
  -- (Daniel 20.11.2026, Bild: "ein X in dem Schreibfeld, dass man da alles direkt löschen kann ... dann soll er oben auf
  -- alle Kategorien gehen und dann das Suchfeld leer") the x empties the box and starts over: Alle Kategorien, no results
  p.text = UI.EditBox(p, { placeholder = "Suchen (Name)...", maxLetters = 60, clear = true,
    onClear = function() ns.AHReset() p:Fill() end,
    onChange = function(t) A.text = t end,
    onEnter = function() ns.AHSearch() p:Fill() end })
  p.go = UI.Button(p, "Suchen", { small = true, onClick = function() A.text = p.text:GetText() or A.text ns.AHSearch() p:Fill() end,
    tooltip = "Suchen", tooltipLines = { "Sucht den Text in der gewählten Kategorie (links).", "Ohne Text: alles der Kategorie." } })
  p.more = UI.Button(p, "Mehr", { small = true, onClick = function() ns.AHMore() end,
    tooltip = "Mehr", tooltipLines = { "Das Auktionshaus hat mehr Ergebnisse: die nächsten laden." } })
  p.count = UI.Text(p, "sub", C.muted)
  -- the filters (Blizzard's filter list): a button shows or hides their row under the search line
  local fl = ns.AHFilter()
  p.fbtn = UI.Button(p, "Filter", { small = true, onClick = function()
      local f = ns.AHFilter()
      f.open = not f.open or nil
      p:Fill()
    end, tooltip = "Filter", tooltipLines = { "Stufe, Qualität und mehr für die Suche ein- oder ausblenden.",
      "Die Zahl sagt, wie viele Filter an sind. Sie bleiben gespeichert." } })
  p.fp = CreateFrame("Frame", nil, p)
  -- the level: from and to (Enter, Tab or a click elsewhere applies it)
  p.lv = CreateFrame("Frame", nil, p.fp)
  p.lv:SetSize(170, LINE_H)
  p.lvL = UI.Text(p.lv, "sub", C.muted) p.lvL:SetText("Stufe")
  p.lvTo = UI.Text(p.lv, "sub", C.muted) p.lvTo:SetText("bis")
  local function LevelBox(field, hint)
    return UI.EditBox(p.lv, { numeric = true, maxLetters = 3, placeholder = hint,
      onChange = function(t)
        ns.AHFilter()[field] = Level(t)
        p.fbtn:SetText(ns.AHFilterText())
      end,
      onEnter = function() ns.AHFilterApply() p:Fill() end,
      onLeave = function() ns.AHFilterApply() p:Fill() end })
  end
  p.lvMin = LevelBox("minLevel", "von")
  p.lvMax = LevelBox("maxLevel", "bis")
  if p.lvMin.SetNext then p.lvMin:SetNext(p.lvMax) end
  if p.lvMin.SetTooltip then p.lvMin:SetTooltip("Stufe von", { "Benötigte Stufe ab. Leer: ohne Grenze." }) end
  if p.lvMax.SetTooltip then p.lvMax:SetTooltip("Stufe bis", { "Benötigte Stufe bis. Leer: ohne Grenze." }) end
  -- the qualities: all on is Blizzard's default (no quality filter); at least one stays on
  p.quals = {}
  for _, d in ipairs(QUALS) do
    local t = UI.Toggle(p.fp, { label = QualLabel(d),
      get = function() return ns.AHFilter().q[d[1]] ~= false end,
      set = function(v, self)
        local f = ns.AHFilter()
        if v then f.q[d[1]] = nil else f.q[d[1]] = false end
        local any = false
        for _, e in ipairs(QUALS) do if EnumVal(e[2]) and f.q[e[1]] ~= false then any = true end end
        if not any then f.q[d[1]] = nil if self and self.SetValue then self:SetValue(true) end end
        ns.AHFilterApply()
        p:Fill()
      end })
    t.qual = d
    p.quals[#p.quals + 1] = t
  end
  p.flags = {}
  for _, fd in ipairs(FLAGS) do
    local t = UI.Toggle(p.fp, { label = fd.label,
      get = function() return ns.AHFilter()[fd.key] and true or false end,
      set = function(v) ns.AHFilter()[fd.key] = v and true or nil ns.AHFilterApply() p:Fill() end })
    if t.SetTooltip then t:SetTooltip(fd.tip[1], fd.tip[2]) end
    t.flag = fd
    p.flags[#p.flags + 1] = t
  end
  p.freset = UI.Button(p.fp, "Filter zurücksetzen", { small = true, onClick = function()
      ns.AHFilterReset()
      p.lvMin:SetValue(nil) p.lvMax:SetValue(nil)
      ns.AHFilterApply()
      p:Fill()
    end, tooltip = "Filter zurücksetzen", tooltipLines = { "Alle Qualitäten, keine Stufe, keine Häkchen: wie Blizzards Standard." } })
  p.lvMin:SetValue(Level(fl.minLevel)) p.lvMax:SetValue(Level(fl.maxLevel))
  -- middle: results
  p.results = UI.Table(p, { columns = Cols(),
    onClick = function(it) if it and it.result then ns.AHPick(it.result, tonumber(p.qty:GetText())) p:Fill() end end,
    onSort = function(key)
      if A.sort == key then A.desc = not A.desc else A.sort, A.desc = key, false end
      p:Fill()
    end })
  -- the offers of the picked item per price tier; a click on a tier: the amount up to and with that tier
  p.tiers = UI.Table(p, { columns = TIER_COLS,
    onClick = function(it) p:PickTier(it and it.tier) end })
  function p:PickTier(t)
    if not (t and t.cum and B.kind == "ah") then return end
    self.qty:SetValue(t.cum)
    ns.SetWant(t.cum, false)
    self:Fill()
  end
  -- bottom: the picked item
  p.buy = CreateFrame("Frame", nil, p)
  p.icon = UI.ItemIcon(p.buy, 36)
  p.name = UI.Text(p.buy, "row", C.hero)
  p.hist = UI.Text(p.buy, "sub", C.muted)
  p.preview = UI.Text(p.buy, "sub", C.body)
  p.msg = UI.Text(p.buy, "sub", C.body)
  p.done = UI.Text(p.buy, "sub", C.green) -- what was bought of the item since the AH opened, it stays (Buy.lua ns.BoughtText)
  p.qtyL = UI.Text(p.buy, "sub", C.muted) p.qtyL:SetText("Menge")
  p.qty = UI.EditBox(p.buy, { numeric = true, min = 1, placeholder = "1",
    onChange = function(t)
      if B.kind ~= "ah" or not B.entry then return end
      -- typed: Fill leaves the box alone; a purchase changes entry.want and counts the box down. Set before SetWant:
      -- (Daniel 21.11.2026 "schreibt er 2, dann springt er nach vorne") SetWant redraws at once, and with qtyFor still
      -- old the redraw wrote the box anew and put the cursor in front
      local n = tonumber(t)
      p.qtyFor = n and n >= 1 and math.floor(n) or 0
      ns.SetWant(n, false)
      p.qtyFor = B.entry.want
    end,
    onEnter = function(self) local n = tonumber(self:GetText()) if n and B.kind == "ah" then ns.SetWant(n, true) end p:Fill() end })
  p.max = UI.Button(p.buy, "Max", { small = true, onClick = function()
      if B.kind == "ah" and B.maxQty and B.maxQty > 0 then
        p.qty:SetValue(B.maxQty)
        ns.SetWant(B.maxQty, false)
        p:Fill()
      end
    end, tooltip = "Max", tooltipLines = { "So viel, wie das Gold kauft (billigste zuerst); ab der Bestätigungsgrenze kommt ein zweiter Klick mit dem Gesamtpreis." } })
  p.go2 = UI.Button(p.buy, "Kaufen", { kind = "primary", onClick = function() ns.BuyNow() p:Fill() end,
    tooltip = "Kaufen", tooltipLines = { "Kauft die Menge zu den billigsten Angeboten.", "Stapelware: ein Klick, das Spiel bestätigt den Preis vorher.",
      "Einzelposten: nur 1 Stück je Klick, die Menge zählt mit jedem Kauf herunter.", "Tastenkürzel \"Profitdon: nächster Klick\" geht auch." } })

  -- a click anywhere outside the results, the price tiers and the buy area lets the picked item go
  local watch = CreateFrame("Frame", nil, p)
  if pcall(watch.RegisterEvent, watch, "GLOBAL_MOUSE_DOWN") then
    watch:SetScript("OnEvent", function()
      local B = ns.BuyState
      if not (p:IsVisible() and B and B.kind == "ah" and B.entry) then return end
      for _, f in ipairs({ p.results, p.tiers, p.buy }) do
        if f and f:IsVisible() and f.IsMouseOver and f:IsMouseOver() then return end
      end
      ns.AHUnpick()
      p:Fill()
    end)
  end
  p.unpickWatch = watch -- (tests)

  ns.ahPage = p
  function p:Fill()
    local open = ns.ScanState.open
    -- categories
    self.catItems = CatItems()
    self.cats:SetItems(self.catItems)
    -- search line
    local n = #(A.results or {})
    local count = A.msg or (not open and "Am Auktionshaus suchen und kaufen.")
      or (A.state == "waiting" and "Suche...") or (A.state == "done" and (n == 0 and "Nichts gefunden." or (n .. " Ergebnisse" .. (A.full and "" or ", es gibt mehr"))))
      or "Links eine Kategorie wählen oder oben suchen."
    self.count:SetText(count)
    self.more:SetShown(A.state == "done" and not A.full and n > 0 and true or false)
    if self.go.SetDisabled then self.go:SetDisabled(not open) end
    -- the filters: the button's count, the row when open, a control only where the client knows its filter
    local f = ns.AHFilter()
    self.fbtn:SetText(ns.AHFilterText())
    self.fp:SetShown(f.open and true or false)
    for _, t in ipairs(self.quals) do t:SetShown(EnumVal(t.qual[2]) ~= nil) t:Update() end
    for _, t in ipairs(self.flags) do t:SetShown(t.flag.client or EnumVal(t.flag.enum) ~= nil) t:Update() end
    if not self.lvMin._focus then self.lvMin:SetValue(Level(f.minLevel)) end
    if not self.lvMax._focus then self.lvMax:SetValue(Level(f.maxLevel)) end
    -- results
    self.resultItems = ResultItems()
    if (A.hidden or 0) > 0 and A.state == "done" then
      self.count:SetText(count .. (", %d durch Filter ausgeblendet"):format(A.hidden))
    end
    self.results:SetColumns(Cols())
    if self.results.SetSort then self.results:SetSort(A.sort, not A.desc) end
    self.results:SetItems(self.resultItems)
    self.results:SetEmpty(A.state == "waiting" and "Suche läuft..." or open and "Keine Ergebnisse." or "Das Auktionshaus öffnen, dann hier suchen.")
    -- the picked item
    local e = B.kind == "ah" and B.entry or nil
    local plan = e and B.plan or nil
    if e then
      local name, _, q = ns.ItemInfo(e.id)
      local info = KeyInfo(e.itemKey)
      self.icon:SetItem(e.id, nil, (info and ns.Num(info.quality)) or q)
      self.icon:Show()
      self.name:SetText((info and info.itemName) or name or ("Item " .. e.id))
      local now = (B.ladder and B.ladder[1] and B.ladder[1].unitPrice) or (B.itemOffers and B.itemOffers[1]) or e.browseMin
      self.hist:SetText(ns.AHHistLine(e.id, now))
    else
      self.icon:Hide()
      self.name:SetText("Kaufen")
      self.hist:SetText("Oben ein Ergebnis anklicken: Angebote, Median und Tendenz stehen dann hier.")
    end
    self.preview:SetText(e and ns.AHPreview() or "")
    self.tierItems = e and TierItems() or {}
    self.tiers:SetItems(self.tierItems)
    self.tiers:SetEmpty(e and "Angebote werden gesucht..." or "")
    self.tiers:SetShown(e and true or false)
    -- (21.11.2026 Fehler nach Kauf) "e and f()" keeps only the first return value, so hex was nil
    local st, stext, hex
    if e then st, stext, hex = ns.BuySignal(e.id) end
    self.msg:SetText(st and hex and ("|c%s%s|r"):format(hex, stext or "") or (e and B.msg) or "")
    -- (Daniel 20.11.2026: "das runterzählen lassen, wenn man einen gekauft hat") also while the cursor is still in the
    -- box: typing keeps qtyFor in step (onChange), so only another item or a purchase gets here
    if self.qtyFor ~= (e and e.want) then
      self.qtyFor = e and e.want
      self.qty:SetValue(e and e.want and e.want > 0 and e.want or nil)
    end
    local ready = plan and B.state == "ready" and not plan.post
    local spend = plan and (plan.total or plan.price)
    local single = ready and not plan.commodity and (B.want or 1) > 1
    self.go2:SetText(single and ("Kaufen: 1 von %d für %s"):format(B.want, M(spend))
      or ready and ("Kaufen: %d für %s"):format(plan.qty or 1, M(spend)) or "Kaufen")
    self.done:SetText(e and ns.BoughtText(e.id, M) or "")
    if self.go2.SetDisabled then self.go2:SetDisabled(not ready) end
    if self.max.SetDisabled then self.max:SetDisabled(not (e and (B.maxQty or 0) > 0)) end
    self:Layout(self.w or 700, self.h or 400)
  end

  function p:Layout(w, h)
    self.w, self.h = w, h
    self:SetSize(w, h)
    local pad = S.pad or 8
    local cw = min(CAT_W, max(140, floor(w * 0.26)))
    self.cats:ClearAllPoints() self.cats:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.cats:Resize(cw, max(40, h))
    local rx = cw + 8
    local rw = max(160, w - rx)
    -- search line: text, Suchen, Mehr (while there is more), Filter, the count; what does not fit goes to a next line
    -- (as Verkaufen's head, Daniel 17.11.2026 "Auf kleinen Bildschirmen passt das nicht")
    local moreOn = self.more:IsShown()
    local fw = 92
    local tw = max(100, min(260, rw - 76 - (moreOn and 62 or 0) - fw - 12 - 140))
    local head = { { self.text, tw, 6, layout = true }, { self.go, 76, 6, layout = true } }
    if moreOn then head[#head + 1] = { self.more, 56, 6, layout = true } end
    head[#head + 1] = { self.fbtn, fw, 10, layout = true }
    -- the count takes the rest of its line, at least 120 px
    local used = 0
    for _, it in ipairs(head) do used = used + it[2] + it[3] end
    local cw2 = rw - used
    local countLine = cw2 < 120
    head[#head + 1] = { self.count, countLine and rw or cw2, 0 }
    local lines = Flow(self, head, rx, 0, rw)
    UI.Fit(self.count, max(40, self.count._fw))
    self.searchLines = lines
    local top = lines * LINE_H + 4
    -- the filter row under it
    self.fp:ClearAllPoints() self.fp:SetPoint("TOPLEFT", self, "TOPLEFT", rx, -top)
    if self.fp:IsShown() then
      local lv = self.lv
      self.lvL:ClearAllPoints() self.lvL:SetPoint("LEFT", lv, "LEFT", 0, 0)
      self.lvMin:ClearAllPoints() self.lvMin:SetPoint("LEFT", lv, "LEFT", 40, 0) self.lvMin:Layout(48)
      self.lvTo:ClearAllPoints() self.lvTo:SetPoint("LEFT", lv, "LEFT", 94, 0)
      self.lvMax:ClearAllPoints() self.lvMax:SetPoint("LEFT", lv, "LEFT", 118, 0) self.lvMax:Layout(48)
      local row = { { lv, 170, 14 } }
      for _, t in ipairs(self.quals) do
        if t:IsShown() then row[#row + 1] = { t, max(40, ceil(tonumber((t:GetWidth())) or 80)), 10 } end
      end
      for _, t in ipairs(self.flags) do
        if t:IsShown() then row[#row + 1] = { t, max(40, ceil(tonumber((t:GetWidth())) or 100)), 10 } end
      end
      row[#row + 1] = { self.freset, 150, 0, layout = true }
      local fl = Flow(self.fp, row, 0, 0, rw)
      self.filterLines = fl
      self.fp:SetSize(rw, fl * LINE_H)
      top = top + fl * LINE_H + 4
    else
      self.filterLines = 0
      self.fp:SetSize(rw, 1)
    end
    self.top = top
    -- results and the buy area
    local tierH = self.tiers:IsShown() and min(TIER_H, max(60, floor((h - top - BUY_H) / 2))) or 0
    local resH = max(60, h - top - BUY_H - 4 - (tierH > 0 and tierH + 4 or 0))
    self.results:ClearAllPoints() self.results:SetPoint("TOPLEFT", self, "TOPLEFT", rx, -top)
    self.results:Layout(rw, resH)
    local by = -(top + resH + 4)
    if tierH > 0 then
      self.tiers:ClearAllPoints() self.tiers:SetPoint("TOPLEFT", self, "TOPLEFT", rx, by)
      self.tiers:Layout(rw, tierH)
      by = by - tierH - 4
    end
    self.tierH = tierH -- (tests)
    self.buy:ClearAllPoints() self.buy:SetPoint("TOPLEFT", self, "TOPLEFT", rx, by)
    self.buy:SetSize(rw, BUY_H)
    self.icon:ClearAllPoints() self.icon:SetPoint("TOPLEFT", self.buy, "TOPLEFT", pad, -4)
    local tx = pad + 36 + 8
    local lw = max(60, rw - tx - pad)
    self.name:ClearAllPoints() self.name:SetPoint("TOPLEFT", self.buy, "TOPLEFT", tx, -4)
    self.hist:ClearAllPoints() self.hist:SetPoint("TOPLEFT", self.buy, "TOPLEFT", tx, -20)
    self.preview:ClearAllPoints() self.preview:SetPoint("TOPLEFT", self.buy, "TOPLEFT", tx, -34)
    self.msg:ClearAllPoints() self.msg:SetPoint("TOPLEFT", self.buy, "TOPLEFT", tx, -48)
    UI.Fit(self.name, lw) UI.Fit(self.hist, lw) UI.Fit(self.preview, lw) UI.Fit(self.msg, lw)
    local cy = -(BUY_H - 20)
    self.qtyL:ClearAllPoints() self.qtyL:SetPoint("LEFT", self.buy, "TOPLEFT", pad, cy)
    self.qty:ClearAllPoints() self.qty:SetPoint("LEFT", self.buy, "TOPLEFT", pad + 46, cy) self.qty:Layout(64)
    self.max:ClearAllPoints() self.max:SetPoint("LEFT", self.buy, "TOPLEFT", pad + 46 + 70, cy) self.max:Layout(48)
    local gw = min(260, max(120, rw - (pad + 46 + 70 + 48) - 2 * pad - 8))
    self.go2:ClearAllPoints() self.go2:SetPoint("RIGHT", self.buy, "TOPRIGHT", -pad, cy) self.go2:Layout(gw)
    local dx = pad + 46 + 70 + 48 + 10
    self.done:ClearAllPoints() self.done:SetPoint("LEFT", self.buy, "TOPLEFT", dx, cy)
    UI.Fit(self.done, max(10, rw - dx - gw - 2 * pad))
  end
  return p
end

-- the price preview of the amount: commodities from the offers found (total, average, dearest, what is short),
-- single auctions one a click; before the search answers the cheapest of the browse list as an estimate
function ns.AHPreview()
  local B = ns.BuyState
  local e = B.kind == "ah" and B.entry
  if not e then return "" end
  local p = B.plan
  if B.state == "searching" or B.state == "browsing" then
    return e.browseMin and ("ab %s je Stück (Suchliste), Angebote werden gesucht..."):format(M(e.browseMin)) or "Angebote werden gesucht..."
  end
  if p and p.commodity then
    local s = ("%d Stück: %s, im Schnitt %s je Stück"):format(p.qty, M(p.total), M(floor((p.avg or 0) + 0.5)))
    if p.top and p.avg and p.top > p.avg + 0.5 then s = s .. (", teuerstes %s"):format(M(p.top)) end
    if p.short == "ah" then s = s .. (", nur %d im AH"):format(p.qty)
    elseif p.short == "Gold" then s = s .. ", mehr reicht das Gold nicht"
    elseif p.short == "cap" then s = s .. ", Höchstbetrag je Klick erreicht" end
    if B.maxQty then s = s .. ("  ·  Max %d"):format(B.maxQty) end
    return s
  end
  if p and not p.commodity then
    local left = (B.want or 1) - 1
    return ("Einzelposten: nur 1 Stück je Klick (%s)%s  ·  %d im AH, Max %d"):format(M(p.price), left > 0 and (", danach noch " .. left) or "",
      B.avail or 0, B.maxQty or 0)
  end
  if B.ladder and B.ladder[1] then return ("ab %s je Stück, %d im AH, Max %d"):format(M(B.ladder[1].unitPrice), B.avail or 0, B.maxQty or 0) end
  return ""
end
