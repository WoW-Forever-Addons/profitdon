local ADDON, ns = ...
ns.Style = LibStub("DonCore-1.0"):Get("Style", 3) -- shared kit from DonCore (Libs\DonCore\Style.lua)

---------------------------------------------------------------------------
-- Profitdon (Daniel 06.11.2026: "ein lightweight addon, das sich genau auf die sachen konzentriert, die er macht",
-- PROFITDON_PLAN.md): Yeny's way of making gold on WoW Forever and nothing else.
--   1. craft for the vendor (Herstellen), 2. disenchant (Entzaubern), 3. auctions below the vendor price (Händler),
--   4. sell mats at exactly the cheapest offer (Verkaufen).
-- Copied from Golddon and made lean (Core, Deals, Prices, Scan, Buy, Post, Crafts, Merchant), nothing linked to Golddon.
-- Only for WoW Forever (Interface 16001, C_AuctionHouse). German texts, Daniel's own addon, never published.
---------------------------------------------------------------------------
ns.NAME = "|cff4fd16bProfit|rdon"
ns.VERSION = "0.1.0"

local DEFAULTS = {
  minProfit = 10,          -- copper: a deal below this is not listed (Yeny: "auch kleine ROI mitnehmen")
  minProfitPct = 5,        -- percent of what is spent
  maxSpend = 500000,       -- one purchase click spends at most 50 gold
  confirmAbove = 100000,   -- from 10 gold on a purchase needs a second click within 5 seconds
  cutOwn = 5,              -- AH cut in percent at a faction auction house
  cutNeutral = 15,         -- at a goblin auction house
  depositPct = 15,         -- deposit estimate: percent of the vendor price per 12 hours
  sellGrey = true,         -- merchant button sells grey items
  sellVendor = true,       -- merchant button sells what Profitdon bought or crafted for the vendor
  deMinRolls = 50,         -- (15.11.2026) the disenchant table counts like this many own rolls of a group (mixed, DE.Mats)
  deBlue = true,           -- the bag button disenchants blue items too
  deEpic = false,          -- and epic ones (off: too easy to lose one)
  deAlways = false,        -- (07.11.2026) the bag button disenchants gear even when the AH pays more (off: it goes to Verkaufen)
  postDur = 2,             -- run time step when posting: 1 short, 2 middle, 3 long (hours from the client's texts)
  scanBudget = 4,          -- (Daniel 14.11.2026, the game stuttered while reading) ms of scan work per frame
  demGoodRate = 30,        -- (Daniel 14.11.2026, "Vorsichtig") demand "gut": sale rate from this percent ...
  demGoodDay = 10,         -- ... and this many tenths sold a day (10 = one a day)
  demSlowRate = 10,        -- demand "zäh" from this sale rate in percent, below it "kaum"
  demDays = 2,             -- crafts for the AH: the sales of this many days ...
  demCap = 10,             -- ... and at most this many pieces
  demOwnMin = 5,           -- (block 6) the own sale rate wins over TSM's from this many units posted through Profitdon
  postPortion = true,      -- (block 5) post only what sells in demDays days, the rest stays in the bags
  sellMinGain = 0,         -- (17.11.2026, Verkaufen-Seite) copper the AH must bring after the cut over the vendor, else "Händler zahlt mehr"
  sellMinPct = 0,          -- the same in percent of the vendor price (the larger of both counts)
  sellMade = true,         -- the sections of Verkaufen: Hergestellt, AH lohnt, Händler zahlt mehr, Ohne Preis
  sellAH = true,
  sellVendorRows = true,
  sellNoPrice = true,
  tsm = true,
  blizzLook = true,        -- option "Fensterstil": true "Blizzard-Look", false "Don-Look" (Daniel 15.11.2026, a test) Profitdon's windows from Blizzard's own templates (DonCore Blizz)
  hideRecipeList = true,   -- (Daniel 15.11.2026) the game's list of tracked recipes at the screen edge is hidden (they are on the shopping list)
  deBonus = 0,             -- (Daniel 15.11.2026) percent more mats per disenchant (a buff), counted into every disenchant value
  deBuff = true,           -- (Daniel 15.11.2026) the buff Boosted Disenchanting on the character counts its bonus by itself
  runMin = 30,             -- (Daniel 18.11.2026) Gold/30 min: a run of crafting for the vendor lasts so many minutes
  afkCap = false,          -- (16.11.2026) a craft click sends at most 28 minutes of casting (the game's AFK logout)
  ahHide = true,           -- (Daniel 20.11.2026) Blizzard's auction window stays away, the page Kaufen does its work (AHPage.lua)
  medDays = 5,             -- (Daniel 20.11.2026: "für die letzten 3 bis 5 Tage") the median and trend over so many days (History.lua)
  tooltip = true,          -- (06.11.2026) Profitdon's lines in item tooltips (Händler, AH, Entzaubern)              -- use TSM's DBMarket at run time when TSM is installed (only read, never copied)
  minimapButton = true,
}
ns.DEFAULTS = DEFAULTS

ns.db = nil
ns.AH = C_AuctionHouse
local initFns, handlers = {}, {}
local frame = CreateFrame("Frame")

function ns.OnInit(fn) initFns[#initFns + 1] = fn end
function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    pcall(frame.RegisterEvent, frame, event)
  end
  table.insert(handlers[event], fn)
end
function ns.Fire(event, ...) for _, fn in ipairs(handlers[event] or {}) do ns.Try(fn, event, ...) end end

-- facts for /profit diag (ProfitdonDB.facts), kept until seen again
function ns.Fact(k, v)
  if not ns.db then return end
  ns.db.facts = ns.db.facts or {}
  ns.db.facts[k] = { v = tostring(v), t = time() }
end

-- (16.11.2026, Blizzard look for all Don addons) the windows' Blizzard parts come from DonCore's module Blizz (minor 5,
-- Libs\DonCore\Blizz.lua), lifted from Profitdon's own Blizz.lua and BlizzKit.lua of 15.11. The module does not know
-- the option blizzLook and writes no diag line: both are done here.
ns.Blizz = LibStub("DonCore-1.0"):Get("Blizz", 5)
-- the builders of a window with tabs, controls and tables (main window, sell window): Bz.kit, or the kit when the option
-- is off or the client lacks a template. Returns the kit, true when it is Blizzard's, and the module.
-- fact: the line of /profit diag that says why (blizzMain, blizzSell)
function ns.LookKit(fact)
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 23)
  local Bz = ns.Blizz
  local kit, why
  if ns.Opt("blizzLook") == false then why = "Fensterstil Don-Look"
  elseif not Bz then why = "fehlt: DonCore Blizz"
  else
    local miss
    kit, miss = Bz.Kit()
    why = kit and "an" or ("fehlt: " .. tostring(miss))
  end
  if fact then ns.Fact(fact, why) end
  if kit then return kit, true, Bz end
  return Kit, false
end
-- the module's frame and list (the Herstellfenster): true when the option is on and the client has the templates,
-- else false and why (diag line blizzLook)
function ns.BlizzReady()
  local Bz = ns.Blizz
  if ns.Opt("blizzLook") == false then return false, "Fensterstil Don-Look" end
  if not Bz then ns.Fact("blizzLook", "fehlt: DonCore Blizz") return false, "DonCore Blizz" end
  local ok, miss = Bz.Ready()
  ns.Fact("blizzLook", miss and ("fehlt: " .. miss) or "an")
  return ok and true or false, miss
end
-- a window that failed in Blizzard's parts and came from the kit says so in the chat, once a session (the reason is
-- in /profit diag); a client without the templates stays silent
local saidLook
function ns.SayLook()
  if saidLook then return end
  saidLook = true
  ns.Print("Ein Fenster ließ sich nicht im Blizzard-Look bauen und öffnet im Don-Look. /profit diag sagt warum.")
end

ns.On("PLAYER_LOGIN", function() if ns.db then ns.db.perf = nil end end)
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    ProfitdonDB = type(ProfitdonDB) == "table" and ProfitdonDB or {}
    ns.db = ProfitdonDB
    ns.db.opt = type(ns.db.opt) == "table" and ns.db.opt or {}
    for k, v in pairs(DEFAULTS) do if ns.db.opt[k] == nil then ns.db.opt[k] = v end end
    ns.db.opt.blizzLight = nil -- (Daniel 16.11.2026: streichen) the lighter tones are always on (DonCore Blizz, all addons)
    for _, fn in ipairs(initFns) do ns.Try(fn) end
    return
  end
  for _, fn in ipairs(handlers[event] or {}) do ns.Try(fn, event, ...) end
end)
frame:RegisterEvent("ADDON_LOADED")

function ns.Opt(k) local o = ns.db and ns.db.opt return o and o[k] end

---------------------------------------------------------------------------
-- Helpers (as Golddon)
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

local said = {}
function ns.Try(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local where = tostring(err):match("^[^:]+:%d+") or tostring(err)
    if (ns.db and ns.db.debug) or not said[where] then
      said[where] = true
      print("|cff4fd16bProfitdon|r Fehler: " .. tostring(err))
    end
  end
  return ok, err
end

local function pass(ok, ...) if ok then return ... end end
function ns.Call(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end

-- (Daniel 07.11.2026: mats in the reagent bag were not offered for sale) bags 0-4 plus the reagent bag (5); a missing bag has 0 slots
ns.LASTBAG = 5
function ns.Num(v)
  if v == nil or issecret(v) then return nil end
  v = tonumber(v)
  if not v or v ~= v or v < 0 then return nil end
  return v
end

function ns.After(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, function() ns.Try(fn) end) else ns.Try(fn) end
end

function ns.Print(msg) print("|cff4fd16bProfitdon|r " .. tostring(msg)) end

function ns.Money(c, color)
  c = math.floor((tonumber(c) or 0) + 0.5)
  local neg = c < 0
  if neg then c = -c end
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  local G, S, K = "g", "s", "c"
  if color then G, S, K = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r" end
  if g > 0 then parts[#parts + 1] = g .. G end
  if s > 0 or (g > 0 and k > 0) then parts[#parts + 1] = s .. S end
  if k > 0 or #parts == 0 then parts[#parts + 1] = k .. K end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

-- name, link, quality, icon, sell price, stack size, class, item level (nil until the game has loaded the item)
function ns.ItemInfo(id)
  local GI = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, link, quality, level, _, _, _, stack, _, icon, sell, class = ns.Call(GI, id)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then ns.Call(C_Item.RequestLoadItemDataByID, id) end
  return name, link, quality, icon, ns.Num(sell), ns.Num(stack), class, ns.Num(level)
end

-- class (2 weapon, 4 armour) and equipment slot without loading the item
function ns.ItemClass(id)
  local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  local _, _, _, equipLoc, _, class = ns.Call(f, id)
  return ns.Num(class), equipLoc
end

function ns.Icon(id)
  local GI = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  return ns.Call(GI, id) or 134400
end

-- (21.11.2026, Laptop-Daten: since 21.11. the game gave an empty realm name, scans and characters landed under "|A" and
-- "Mae-") the realm name, else the normalized one, else the last one seen (ProfitdonDB.realmName), else the one realm of
-- Data/PriceSeed.lua; "?" only when nothing is known
-- (Daniel 22.11.2026: "Es gibt nur einen realm") several names in the seed are the same realm: the newest one
local function SeedRealm()
  local one, oneDay
  for k, v in pairs(ns.PRICE_SEED or {}) do
    local r = type(k) == "string" and k:match("^(.+)|[ANH]$")
    local day = type(v) == "table" and tonumber(v.day) or 0
    if r and (not one or day > oneDay or (day == oneDay and r > one)) then one, oneDay = r, day end
  end
  return one
end
function ns.Realm()
  local r = ns.Call(GetRealmName)
  if type(r) ~= "string" or r == "" then r = GetNormalizedRealmName and ns.Call(GetNormalizedRealmName) end
  if type(r) == "string" and r ~= "" then
    if ns.db and ns.db.realmName ~= r then ns.db.realmName = r end
    return r
  end
  if ns.db and type(ns.db.realmName) == "string" and ns.db.realmName ~= "" then return ns.db.realmName end
  return SeedRealm() or "?"
end

-- (21.11.2026) what was saved under an empty realm ("|A" for an auction house, "Mae-" for a character) goes to the
-- realm's key once the realm is known: moved when the realm's key is free, else merged (the empty-realm entries are the
-- newer ones: a snapshot with a time t wins when newer, the price history is merged day by day, else field by field)
local function MergeKey(name, t, from, to, later)
  local src, dst = t[from], t[to]
  t[from] = nil
  if dst == nil or type(src) ~= "table" or type(dst) ~= "table" then
    if src ~= nil then t[to] = src end
    return
  end
  if name == "hist" and ns.History and ns.History.Merge then
    -- (21.11.2026, Ruckler) at login as a background job (History.lua H.MergeLater: the store waits for it before any write)
    if later and ns.History.MergeLater then ns.History.MergeLater(src, dst) else ns.History.Merge(src, dst) end
  elseif type(src.t) == "number" and type(dst.t) == "number" then
    if src.t > dst.t then t[to] = src end
  else
    for k, v in pairs(src) do dst[k] = v end
  end
end
function ns.FixRealmKeys(later)
  local realm = ns.Realm()
  if not ns.db or realm == "?" then return 0 end
  local n = 0
  for name, t in pairs(ns.db) do
    if type(t) == "table" and name ~= "opt" then
      local moves = {}
      for k in pairs(t) do
        if type(k) == "string" then
          if k:match("^|[ANH]$") then moves[k] = realm .. k
          elseif k:match("^[^%-|]+%-$") then moves[k] = k .. realm end
        end
      end
      for from, to in pairs(moves) do MergeKey(name, t, from, to, later) n = n + 1 end
    end
  end
  if n > 0 then ns.Fact("realmFix", n .. " keys to " .. realm) end
  return n
end
ns.OnInit(function() ns.FixRealmKeys(true) end)
-- the character key: first name and realm (Profitdon keeps only the scan wait per character)
function ns.Me() return (ns.Call(UnitName, "player") or "?") .. "-" .. ns.Realm() end

-- how many of an item the bags hold (not locked)
function ns.BagCount(id)
  local n = 0
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      if type(info) == "table" and ns.Num(info.itemID) == id then n = n + (ns.Num(info.stackCount) or 1) end
    end
  end
  return n
end
-- (Daniel 12.11.2026: "er soll dann selber lernen, was wieviel stacken kann ob 10, 20 oder 5") the stack size of an item:
-- what the game says (kept in ProfitdonDB.stacks), else what it said before; nil while unknown
function ns.Stack(id)
  local s = id and select(6, ns.ItemInfo(id))
  if s and s > 0 then
    ns.db.stacks = ns.db.stacks or {}
    ns.db.stacks[id] = s
    return s
  end
  return id and ns.db and type(ns.db.stacks) == "table" and ns.db.stacks[id] or nil
end

-- every item in the bags: [id] = count
-- (Daniel 16.11.2026: "wieso das spiel ruckelig ist, sobald ich profitdon auf habe ... crafting auf, habe gecrafted")
-- what a piece of work costs, for /profit diag (ProfitdonDB.perf[name] = { calls, ms together, ms at most }, new each
-- session); without the game's clock the work just runs
function ns.Perf(name, fn, ...)
  local clock = rawget(_G, "debugprofilestop")
  if type(clock) ~= "function" or not ns.db then return fn(...) end
  local t0 = clock()
  local a, b, c = fn(...)
  local ms = clock() - t0
  ns.db.perf = type(ns.db.perf) == "table" and ns.db.perf or {}
  local p = ns.db.perf[name] or { 0, 0, 0 }
  p[1], p[2], p[3] = p[1] + 1, p[2] + ms, math.max(p[3], ms)
  ns.db.perf[name] = p
  return a, b, c
end

-- (Daniel 16.11.2026: "mach das addon nicht so belastend, wann brauchen wir eine neuberechnung überhaupt ... da reicht es
-- doch zu schauen, wenn man nicht mehr castet und nicht in der warteschleife ist") three rules for all the work that
-- events start:
--   ns.Busy(): a cast runs or the game's craft queue has crafts left (C_TradeSkillUI.GetRemainingRecasts). Nothing is
--     worked out then; the bags change with every craft and nobody looks at the numbers.
--   ns.WhenIdle(key, fn, delay): the work waits until the character is idle, once per key however many events asked
--     (a second ask replaces the first). While busy one cheap look a second.
--   ns.dataVer: counts every change of what the lists are made of (bags, bank, mail, recipes, options). A list worked
--     out for the same version (and the same scan) is taken again instead of worked out anew.
function ns.Busy()
  if ns.Call(UnitCastingInfo, "player") then return true end
  local T = rawget(_G, "C_TradeSkillUI")
  local n = type(T) == "table" and ns.Num(ns.Call(T.GetRemainingRecasts)) or 0
  return n > 0
end
local idleWork, idleArmed = {}, false
local function RunIdle()
  idleArmed = false
  if not next(idleWork) then return end
  if ns.Busy() then idleArmed = true ns.After(1, RunIdle) return end
  local list = idleWork
  idleWork = {}
  for _, fn in pairs(list) do ns.Try(fn) end
end
function ns.WhenIdle(key, fn, delay)
  idleWork[key] = fn
  if not idleArmed then idleArmed = true ns.After(delay or 0.3, RunIdle) end
end
ns.dataVer = 0
function ns.Touch() ns.dataVer = ns.dataVer + 1 end
ns.On("BAG_UPDATE_DELAYED", ns.Touch)
ns.On("PLAYERBANKSLOTS_CHANGED", ns.Touch)
ns.On("BANKFRAME_CLOSED", ns.Touch)

-- (16.11.2026) the bags read once a frame: the craft window asks for every learned recipe what the bags allow, each asked
-- every slot of every bag (150 recipes x 150 slots per refresh). A snapshot holds while the frame (GetTime) is the same
-- and no bag event came; callers get a copy (some count down in what they get). ns.bagCacheOff: the tests' bags change
-- without events.
local bagSnap, bagAt, normalSnap, normalAt
local countSnap
local function BagsDirty() bagSnap, normalSnap, countSnap = nil, nil, nil end
ns.On("BAG_UPDATE", BagsDirty)
ns.On("BAG_UPDATE_DELAYED", BagsDirty)
ns.On("ITEM_LOCK_CHANGED", BagsDirty)
local function Now() return ns.Call(GetTime) or 0 end
function ns.Bags()
  if not ns.bagCacheOff and bagSnap and bagAt == Now() then
    local copy = {}
    for id, n in pairs(bagSnap) do copy[id] = n end
    return copy
  end
  local out = ns.BagsRead()
  if not ns.bagCacheOff then
    bagSnap, bagAt = {}, Now()
    for id, n in pairs(out) do bagSnap[id] = n end
  end
  return out
end
-- (21.11.2026, Ruckler: the tooltip with Shift read every bag slot on each build, about 5 times a second) how many of an
-- item the bags hold, as ns.BagCount, from a snapshot kept until a bag event (BagsDirty) instead of one frame
function ns.BagCountKept(id)
  if ns.bagCacheOff then return ns.BagCount(id) end
  if not countSnap then countSnap = ns.BagsRead() end
  return countSnap[id] or 0
end
function ns.BagsRead()
  local out = {}
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id then out[id] = (out[id] or 0) + (ns.Num(info.stackCount) or 1) end
    end
  end
  return out
end
-- (Daniel 14.11.2026, Bild Einkaufsliste: "einen button für bank und taschenreagenzien mit einberechnen oder nicht") what
-- the shopping list counts as there: the bags with the reagent bag, and the bank.
-- The bank comes from GetItemCount (the client knows it with the bank shut), asked per item.
function ns.BankCount(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not f then return 0 end
  local all = ns.Num(ns.Call(f, id, true, false, true, true)) or 0
  local own = ns.Num(ns.Call(f, id, false, false, false, false)) or 0
  return math.max(0, all - own)
end
function ns.Owned()
  -- (Daniel 14.11.2026: "nur einen schalter mit keine vorhandenen mats aus egal welcher quelle mitrechnen") one switch
  -- (ProfitdonDB.shopNoHave): off, nothing counts as there, the list shows the whole purchase
  if ns.db and ns.db.shopNoHave then return {} end
  local base = ns.Bags()
  return setmetatable({}, { __index = function(t, id)
    local n = (base[id] or 0) + ns.BankCount(id)
    rawset(t, id, n)
    return n
  end })
end
-- (Durchsicht Runde 2, 11.11.2026, Bild 122448: 500 Linen Cloth bought, the list still said 500 to buy) what the AH sold
-- lies in the mailbox, not in the bags: bought mats are kept per character as "on the way" until the bags grow by them
-- (taken out of the mail), so the shopping list does not ask for them a second time. Mail lasts 30 days, so does an entry.
local wayPrev
function ns.OnWay()
  if not ns.db then return {} end
  ns.db.onWay = ns.db.onWay or {}
  local me = ns.Me()
  ns.db.onWay[me] = ns.db.onWay[me] or {}
  return ns.db.onWay[me]
end
function ns.OnWayAdd(id, qty)
  if not (ns.db and id and (qty or 0) > 0) then return end
  local t = ns.OnWay()
  local e = t[id] or { q = 0 }
  e.q, e.t = e.q + qty, time()
  t[id] = e
  ns.Touch()
  wayPrev = wayPrev or ns.Bags()
end
function ns.OnWayCount(id)
  local e = ns.db and ns.db.onWay and ns.db.onWay[ns.Me()] and ns.db.onWay[ns.Me()][id]
  return e and e.q or 0
end
function ns.OnWayClear()
  ns.Touch()
  if ns.db and ns.db.onWay then ns.db.onWay[ns.Me()] = nil end
  wayPrev = nil
end
function ns.OnWaySettle()
  if not ns.db then return end
  local t = ns.OnWay()
  if not next(t) then wayPrev = nil return end
  local bags = ns.Bags()
  for id, e in pairs(t) do
    local up = wayPrev and ((bags[id] or 0) - (wayPrev[id] or 0)) or 0
    if up > 0 then e.q = e.q - up end
    if e.q <= 0 or time() - (e.t or 0) > 30 * 86400 then t[id] = nil end
  end
  wayPrev = bags
end
ns.On("BAG_UPDATE_DELAYED", function() ns.Try(ns.OnWaySettle) end)

function ns.FreeSlots()
  local n = 0
  for bag = 0, ns.LASTBAG do
    local free = ns.Num(ns.Call(C_Container.GetContainerNumFreeSlots, bag))
    if free then n = n + free end
  end
  return n
end

-- (Daniel 12.11.2026, Bild: "er sagte ich kann 420 craften, aber die taschen sind voll, ohne space für die crafts", the mats
-- lay in the reagent bag) what a made item can use: the free slots of the normal bags (0-4, not the reagent bag), and per
-- item the count and the slots it fills there: [id] = { count, slots }
function ns.NormalBags()
  if not ns.bagCacheOff and normalSnap and normalAt == Now() then return normalSnap[1], normalSnap[2] end
  local free, items = ns.NormalBagsRead()
  if not ns.bagCacheOff then normalSnap, normalAt = { free, items }, Now() end
  return free, items
end
function ns.NormalBagsRead()
  local free, items = 0, {}
  for bag = 0, math.min(4, ns.LASTBAG) do
    free = free + (ns.Num(ns.Call(C_Container.GetContainerNumFreeSlots, bag)) or 0)
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id then
        local t = items[id] or { 0, 0 }
        t[1], t[2] = t[1] + (ns.Num(info.stackCount) or 1), t[2] + 1
        items[id] = t
      end
    end
  end
  return free, items
end
-- the normal-bag slots an item frees when used down to left (what stays is counted as staying in the normal bags)
-- (Daniel 16.11.2026, Bilder: "Platz für 620 Crafts", beim Händler passten nur 480 Hot Spices: "reagenzienbag i guess")
-- the free slots of the reagent bag only take what the game calls a crafting reagent (GetItemInfo's 17th value); Hot
-- Spices from the vendor are none. Only a clear yes counts: without it the item needs a normal slot.
function ns.FitsReagentBag(id)
  local GI = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return select(17, ns.Call(GI, id)) == true
end
-- free slots: of the normal bags, of the reagent bag
function ns.FreeSplit()
  local n = 0
  for bag = 0, math.min(4, ns.LASTBAG) do n = n + (ns.Num(ns.Call(C_Container.GetContainerNumFreeSlots, bag)) or 0) end
  return n, math.max(0, ns.FreeSlots() - n)
end
function ns.FreedNormal(items, id, left, stack)
  local t = items[id]
  if not t then return 0 end
  local stay = math.min(t[1], math.max(0, left))
  return math.max(0, t[2] - math.ceil(stay / math.max(1, stack or 1)))
end

---------------------------------------------------------------------------
-- Slash command /profit
---------------------------------------------------------------------------
local LIMITS = {
  minProfit = { 1, 10000000 }, minProfitPct = { 0, 500 }, maxSpend = { 1, 100000000 }, confirmAbove = { 0, 100000000 },
  cutOwn = { 0, 50 }, cutNeutral = { 0, 50 }, depositPct = { 0, 100 }, deMinRolls = { 1, 1000 }, postDur = { 1, 3 },
  demGoodRate = { 1, 100 }, demGoodDay = { 1, 1000 }, demSlowRate = { 0, 100 }, demDays = { 1, 14 }, demCap = { 1, 200 }, demOwnMin = { 1, 100 }, scanBudget = { 1, 16 },
  sellMinGain = { 0, 10000000 }, sellMinPct = { 0, 500 },
  runMin = { 5, 120 },
}
local function SetOpt(k, v)
  local o = ns.db.opt
  if DEFAULTS[k] == nil then return false end
  if type(DEFAULTS[k]) == "boolean" then
    if v == "an" or v == "on" or v == "1" or v == "true" then o[k] = true
    elseif v == "aus" or v == "off" or v == "0" or v == "false" then o[k] = false
    else o[k] = not o[k] end
  else
    local n, lim = tonumber(v), LIMITS[k]
    if not n then return false end
    if lim then n = math.max(lim[1], math.min(lim[2], n)) end
    o[k] = n
  end
  return true
end
ns.SetOpt = SetOpt

local HELP = {
  "/profit  Fenster ein/aus",
  "/profit scan  Vollscan (im Auktionshaus, alle 15 min)",
  "/profit optionen  Optionsfenster, /profit set <Name> <Wert> ändert eine",
  "/profit de  gemessene Entzauberungen im Chat",
  "/profit start <Betrag>  Startkapital dieses Chars (z. B. 1g 6s oder 50s), sonst im Reiter Auswertung",
  "/profit diag  was Profitdon über das Spiel weiß, im Fenster zum Kopieren (/profit diag chat: im Chat)",
  "/profit ware  Ware in den Taschen: Händlerpreis (zählt) und AH-Wert, die teuersten zehn",
  "/profit unterwegs  vergisst, was als gekauft im Briefkasten gemerkt ist (Einkaufsliste rechnet dann wieder nur mit den Taschen)",
  "Tastenbelegung \"Profitdon: nächster Klick\" (Optionen > Tastenbelegung > AddOns) klickt Kaufen, Einstellen oder Herstellen.",
}

SLASH_PROFITDON1, SLASH_PROFITDON2 = "/profit", "/profitdon"
SlashCmdList.PROFITDON = function(msg)
  local cmd, a, b = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
  local o = ns.db.opt
  if cmd == "" then if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "scan" then if ns.StartScan then ns.StartScan() end
  elseif (cmd == "optionen" or cmd == "options") and ns.OpenOptions and ns.OpenOptions() then
  elseif cmd == "optionen" or cmd == "options" then
    local keys = {}
    for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do ns.Print(("%s = %s"):format(k, tostring(o[k]))) end
  elseif cmd == "set" then
    local key
    for k in pairs(DEFAULTS) do if k:lower() == a then key = k end end
    if key and SetOpt(key, b) then ns.Print(key .. " = " .. tostring(o[key])) else ns.Print("Unbekannt oder ungültig: " .. a) end
  elseif cmd == "start" and ns.Report then
    local c = ns.ParseStart((msg or ""):match("^%s*%S+%s+(.+)$") or "")
    if c and ns.Report.SetStart(c) then ns.Print("Startkapital: " .. ns.Money(c)) else ns.Print("/profit start <Betrag>, z. B. /profit start 1g 6s") end
  elseif cmd == "de" then if ns.DEReport then for _, l in ipairs(ns.DEReport()) do ns.Print(l) end end
  elseif cmd == "unterwegs" then ns.OnWayClear() ns.Print("Gekaufte Mats im Briefkasten vergessen.") if ns.Refresh then ns.Refresh() end
  elseif cmd == "diag" then
    -- (Daniel 16.11.2026: "nicht im chat ausgeben sondern in einem fenster, wo alles markiert ist") "/profit diag chat"
    -- prints as before
    if ns.Diag and not ((msg or ""):lower():find("chat") or not ns.DiagShow()) then return end
    if ns.Diag then for _, l in ipairs(ns.Diag()) do ns.Print(l) end end
  elseif cmd == "ware" and ns.Report then
    local list = {}
    ns.Print("Ware in den Taschen: " .. ns.Money(ns.Report.BagValue()) .. " beim Händler (zählt im Gewinn), im AH etwa "
      .. ns.Money(ns.Report.BagValue(list, true)))
    local SRC = { ah = "AH", tsm = "TSM", vendor = "Händler" }
    for i = 1, math.min(10, #list) do
      local e = list[i]
      ns.Print(("%d× %s: %s (%s)"):format(e.n, ns.ItemInfo(e.id) or e.id, ns.Money(e.value), SRC[e.src] or e.src))
    end
  elseif cmd == "debug" then ns.db.debug = not ns.db.debug ns.Print("Debug " .. tostring(ns.db.debug))
  else for _, l in ipairs(HELP) do ns.Print(l) end end
  if ns.Refresh then ns.Refresh() end
end

-- the key binding (Bindings.xml): one key press is the hardware click for buying or posting the chosen row
BINDING_HEADER_PROFITDON = "Profitdon"
BINDING_NAME_PROFITDON_NEXT = "Profitdon: nächster Klick (Kaufen, Einstellen oder Herstellen)"
function Profitdon_Next() if ns.NextClick then ns.Try(ns.NextClick) end end

function ns.Diag()
  local out = {}
  local function add(k, v) out[#out + 1] = k .. ": " .. tostring(v) end
  add("Version", ns.VERSION)
  -- (16.11.2026) what the work of this session cost, the dearest first
  do
    local list = {}
    for k, p in pairs(type(ns.db.perf) == "table" and ns.db.perf or {}) do list[#list + 1] = { k, p } end
    table.sort(list, function(a, b) return a[2][2] > b[2][2] end)
    for i = 1, math.min(8, #list) do
      local k, p = list[i][1], list[i][2]
      add("Zeit " .. k, ("%d× je %.1f ms, höchstens %.0f ms, zusammen %.1f s"):format(p[1], p[2] / math.max(1, p[1]), p[3], p[2] / 1000))
    end
  end
  add("TSM", ns.Prices and ns.Prices.TSMReady() and "da (DBMarket wird gelesen)" or "nicht da")
  -- (Daniel 14.11.2026: "schau dir den speicher ... an"; the scan line names the Lua memory of all addons together)
  -- this addon's own share, asked only here (the game counts it through all addons, that takes a moment)
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    ns.Call(UpdateAddOnMemoryUsage)
    local mine = ns.Num(ns.Call(GetAddOnMemoryUsage, "Profitdon"))
    local all = ns.Num(ns.Call(collectgarbage, "count"))
    if mine then add("Speicher", ("Profitdon %d MB von %d MB aller Addons"):format(math.floor(mine / 1024 + 0.5), math.floor((all or 0) / 1024 + 0.5))) end
  end
  local L = ns.lists or {}
  add("Listen", ("Händler %d, Entzaubern %d"):format(#(L.vendor or {}), #(L.de or {})))
  local sd = ns.Prices and ns.Prices.SellDiffText and ns.Prices.SellDiffText()
  if sd then add("Händlerpreise", sd) end
  local st = ns.Prices and ns.Prices.Store()
  add("Scan", st and ("vor %d min, %d Auktionen"):format(math.floor((time() - st.t) / 60), st.n or 0) or "keiner")
  -- (08.11.2026, Ledger.lua) the methods against the real change of the gold since login; AH sales count when the invoice is
  -- read, the gold when it is taken from the mail, so the two can differ until then
  local booked, real = ns.Ledger and ns.Ledger.Check()
  if booked then add("Buchung", ("seit Login gebucht %s, Gold geändert %s"):format(ns.Money(booked), ns.Money(real))) end
  -- the facts by name, so two copies can be laid side by side
  local keys = {}
  for k in pairs(ns.db.facts or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do add(k, ns.db.facts[k].v) end
  return out
end
-- the lines as one plain text (no colour codes) in the Kit's copy window, all of it marked: Ctrl+C takes it (the game
-- lets no addon write the clipboard). Returns true when the window is up.
function ns.DiagText()
  local t = table.concat(ns.Diag(), "\n")
  return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
function ns.DiagShow()
  local okKit, Kit = pcall(function() return LibStub("DonCore-1.0"):Get("Kit", 4) end)
  if not (okKit and Kit and Kit.ShowCopy) then return false end
  local text, opts = ns.DiagText(), { selectAll = "Alles markieren", close = "Schließen" }
  local title, hint = "Profitdon Diagnose", "Alles ist markiert: Strg+C kopiert es, dann bei Claude einfügen."
  -- (Daniel 16.11.2026: "Gleich im neuen Stil") with blizzLook the game's dialog, else (or when it fails) the Kit's
  local UI, blizz = Kit, false
  if ns.LookKit then UI, blizz = ns.LookKit() end
  if blizz and UI and UI.ShowCopy then
    local ok, d = pcall(UI.ShowCopy, title, hint, text, opts)
    if ok and d then return true end
  end
  local d = Kit.ShowCopy(title, hint, text, opts)
  return d and true or false
end
