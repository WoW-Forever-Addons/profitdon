local _, ns = ...

---------------------------------------------------------------------------
-- Prices (from Golddon's Prices.lua, without the ledger): vendor sell price (the game, else CMaNGOS), vendor buy price
-- (learned at the merchant, else ForeverDB), the own full scan per auction house (lowest, median, quantity, auctions,
-- cheapest without low outliers) and, optional, TSM's market value read at run time.
-- Saved: ProfitdonDB.ah["<realm>|<A|H|N>"] = { t = scan time, n = auctions, i = { [item] = "min,med,qty,n,low" } }
---------------------------------------------------------------------------
local P = {}
ns.Prices = P

local NEUTRAL = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true, ["Beutebucht"] = true, ["Ewige Warte"] = true }

function P.AtNeutral()
  local sub, zone = ns.Call(GetSubZoneText) or "", ns.Call(GetZoneText) or ""
  return NEUTRAL[sub] or NEUTRAL[zone] or false
end

function P.StoreKey(neutral)
  if neutral == nil then neutral = P.AtNeutral() end
  local fac = neutral and "N" or ((ns.Call(UnitFactionGroup, "player") == "Horde") and "H" or "A")
  return ns.Realm() .. "|" .. fac
end

function P.Cut(neutral)
  if neutral == nil then neutral = P.AtNeutral() end
  return neutral and ns.Opt("cutNeutral") or ns.Opt("cutOwn")
end

---------------------------------------------------------------------------
-- Vendor
---------------------------------------------------------------------------
-- (Daniel 11.11.2026, "Erst messen") how often Forever's vendor price is another than the Classic one of the data file:
-- every item once per session, kept in ProfitdonDB.sellDiff = { n = checked, d = differing, ids = { [id] = "data>game" } }
-- (at most 300 ids), shown by /profit diag
local checked = {}
local function Measure(id, sell)
  if checked[id] then return end
  checked[id] = true
  local g = ns.G and ns.G.sell[id]
  if not g or not ns.db then return end
  local m = ns.db.sellDiff
  if type(m) ~= "table" then m = { n = 0, d = 0, ids = {} } ns.db.sellDiff = m end
  local known = m.ids[id] ~= nil
  if not m.seen then m.seen = {} end
  if m.seen[id] then return end
  m.seen[id] = 1
  m.n = m.n + 1
  if g ~= sell then
    m.d = m.d + 1
    if not known and m.d <= 300 then m.ids[id] = g .. ">" .. sell end
  end
end

function P.SellDiffText()
  local m = ns.db and ns.db.sellDiff
  if type(m) ~= "table" or (m.n or 0) == 0 then return nil end
  return ("%d Items verglichen, bei %d zahlt Forevers Händler anders als Classic"):format(m.n, m.d or 0)
end

function P.Sell(id)
  local _, _, _, _, sell = ns.ItemInfo(id)
  if sell then
    Measure(id, sell)
    if ns.Market then ns.Market.VendorSeen(id, sell) end
    return sell, "game"
  end
  -- (Daniel 16.11.2026, Bild: Iron Grenade oben in "Für Händler", "paar sekunden da dann weg"; the data says 5s, Forever's
  -- vendor pays 1s 25c) the item is not loaded yet: what the game said last time (ProfitdonDB.vsell, Market.VendorSeen)
  -- comes before the data file's guess
  local seen = ns.db and type(ns.db.vsell) == "table" and tonumber(ns.db.vsell[id])
  if seen then return seen, "seen" end
  local g = ns.G and ns.G.sell[id]
  if g then return g, "data" end
  return nil
end

-- cheapest vendor of the own faction: price for one stack, stack size, limited, vendor name, uiMap, x, y, learned
-- unlimited = true: only a vendor without a stock limit
-- (Daniel 16.11.2026, Legacy "Bartering": vendors take 10 % less gold) the price a vendor shows has the discount in it
-- (Daniel's merchant: Mild Spices 9c, Fine Thread 90c, the data 10c and 1s): a learned price counts with the discount of
-- now (it keeps the discount it was seen with, [9]; none kept: seen with today's), the data's prices get it taken off
local function Barter()
  local C = ns.Crafts
  return C and C.LegacyPct and math.max(0, math.min(90, C.LegacyPct("Bartering"))) or 0
end
P.Barter = Barter
function P.VendorBuy(id, unlimited)
  local l = ns.db.buy and ns.db.buy[id]
  local now = Barter()
  if l and not (unlimited and l[3] == 1) then
    local at = tonumber(l[9]) or now
    local price = l[1]
    if at ~= now then price = math.floor(price / (1 - at / 100) * (1 - now / 100) + 0.5) end
    return price, l[2], l[3] == 1, l[4], l[5], l[6], l[7], true
  end
  local rows = ns.G and ns.G.buy[id]
  if not rows then return nil end
  local fac = (ns.Call(UnitFactionGroup, "player") == "Horde") and "H" or "A"
  for k = 1, #rows, 4 do
    local npc = ns.G.npc[rows[k]] or {}
    local limited = (tonumber(rows[k + 3]) or 0) > 0
    if (npc[5] == fac or npc[5] == "N" or npc[5] == "" or npc[5] == nil) and not (unlimited and limited) then
      return math.floor(rows[k + 1] * (1 - now / 100) + 0.5), rows[k + 2], limited, npc[1], npc[2], npc[3], npc[4], false
    end
  end
  return nil
end

-- unit price at an unlimited vendor, nil when none sells it
function P.VendorUnit(id)
  local price, stack = P.VendorBuy(id, true)
  if price and stack and stack > 0 then return math.ceil(price / stack) end
end

---------------------------------------------------------------------------
-- Auction house: the own scan
---------------------------------------------------------------------------
local cache = {}

function P.Store(key)
  key = key or P.StoreKey()
  return ns.db.ah and ns.db.ah[key]
end

local function Row(key, id)
  key = key or P.StoreKey()
  local st = P.Store(key)
  if not st then return nil end
  local c = cache[key]
  if not c or c.t ~= st.t then c = { t = st.t, rows = {} } cache[key] = c end
  local r = c.rows[id]
  if r == nil then
    local s = st.i[id]
    if s then
      -- min, median, quantity, auctions, cheapest real, average of the first 20, of the first 100 (older scans: 4 or 5 fields)
      r = {}
      for v in s:gmatch("[^,]+") do r[#r + 1] = tonumber(v) end
      if not (r[1] and r[2] and r[3] and r[4]) then r = false end
    else r = false end
    c.rows[id] = r
  end
  return r or nil
end
P.Row = Row
function P.Invalidate() cache = {} end

-- lowest buyout per unit, median per unit, quantity, auctions, scan age in seconds
function P.AH(id, key)
  local r = Row(key, id)
  if not r then
    -- no own scan row: TSM (lowest buyout of its last scan, else market value), source "tsm"
    local mv = P.TSM(id, "DBMarket")
    local lo = P.TSM(id, "DBMinBuyout") or mv
    if lo then return lo, mv or lo, nil, nil, nil, "tsm" end
    return nil
  end
  local st = P.Store(key)
  return r[1], r[2] > 0 and r[2] or r[1], r[3], r[4], time() - ((st.pt and st.pt[id]) or st.t), "scan"
end

-- the cheapest real offer (low outliers passed over), nil without a scan
function P.Low(id, key)
  local r = Row(key, id)
  if not r then return P.TSM(id, "DBMinBuyout") or P.TSM(id, "DBMarket") end
  if r[5] and r[5] >= r[1] then return r[5] end
  return r[1]
end

---------------------------------------------------------------------------
-- (Daniel 09.11.2026: "wie lange wir mit positivem cashflow rauskommen? die einkaufswerte sind ja nur mittelwerte"; chosen:
-- the scan's price ladder, and live at the AH the real offers) what n units cost together, cheapest first.
-- Live: the offers of the newest commodity search of the item (ns.liveBook, Buy.lua), newer than the scan and at most 15
-- minutes old. Scan: the ladder points (0, 20, 50, 100, 200, 500, 1000, 2000 units and their average), linear in between,
-- past the last point at the step of the last stretch. Returns total, short (fewer on offer than n), "live" or "scan";
-- nil without a ladder (old scan rows: P.Buy keeps its old estimate).
---------------------------------------------------------------------------
P.LIVE_AGE = 900
function P.Live(id)
  local b = ns.liveBook and ns.liveBook[id]
  if not b then return nil end
  local st = P.Store()
  if time() - b.t > P.LIVE_AGE or (st and st.t > b.t) then return nil end
  return b
end

function P.BuyTotal(id, n, key, scanOnly)
  if not n or n <= 0 then return 0, false, "scan" end
  local b = not scanOnly and P.Live(id)
  -- (Durchsicht 15.11.2026) a live search without any offer of others: 0 for n units became 1 copper a piece in P.Buy.
  -- Nothing can be bought now: the scan's ladder tells the price, marked short.
  local none = b and not b.rows[1]
  if none then
    local t, _, src = P.BuyTotal(id, n, key, true)
    if t then return t, true, src end
    return nil
  end
  if b then
    local got, total, last = 0, 0, nil
    for _, o in ipairs(b.rows) do
      local take = math.min(o.quantity, n - got)
      got, total, last = got + take, total + take * o.unitPrice, o.unitPrice
      if got >= n then break end
    end
    if got >= n then return total, false, "live" end
    if b.full or not last then return total + (n - got) * (last or 0), true, "live" end
    -- the search loaded only the cheapest offers: the rest at the last price seen, at least what the scan says
    local s = P.BuyTotal(id, n, key, true)
    local s2 = P.BuyTotal(id, got, key, true)
    local rest = (s and s2) and math.max((n - got) * last, s - s2) or (n - got) * last
    return total + rest, false, "live"
  end
  local r = Row(key, id)
  if not (r and r[12]) then return nil end
  local q = r[3]
  local pts = { { 0, 0 } }
  for _, x in ipairs({ { 20, r[6] }, { 50, r[8] }, { 100, r[7] }, { 200, r[9] }, { 500, r[10] }, { 1000, r[11] }, { 2000, r[12] } }) do
    local k = math.min(x[1], q)
    if k > pts[#pts][1] then pts[#pts + 1] = { k, k * x[2] } end
    if x[1] >= q then break end
  end
  local short = n > q
  for i = 2, #pts do
    local a, c = pts[i - 1], pts[i]
    if n <= c[1] then return a[2] + (n - a[1]) * (c[2] - a[2]) / (c[1] - a[1]), short, "scan" end
  end
  local a, c = pts[#pts - 1], pts[#pts]
  local step = (c[2] - a[2]) / math.max(1, c[1] - a[1])
  return c[2] + (n - c[1]) * math.max(step, r[2] or 0), short, "scan"
end

-- what one unit costs on average when n units are bought at the AH, cheapest first: the ladder or the live offers
-- (BuyTotal); old scan rows the first 20 or 100 of the scan, more than 100 the median; without a scan row TSM's cheapest;
-- nil without a price
function P.Buy(id, n, key)
  local tot = n and n > 20 and P.BuyTotal(id, n, key)
  if tot and tot > 0 then return math.max(1, math.ceil(tot / n)) end
  local r = Row(key, id)
  if not r then return P.Low(id, key) end
  n = n or 20
  local low = (r[5] and r[5] >= r[1]) and r[5] or r[1]
  local v
  if n <= 20 then v = r[6] elseif n <= 100 then v = r[7] else v = math.max(r[7] or 0, r[2] or 0) end
  return math.max(low, v or low)
end

-- (Daniel 13.11.2026, Bild: "Fehler: integer overflow attempting to store 10000000100", the scan stopped) WoW's %d takes
-- only 32 bits; an auction at 1 million gold is 10 000 000 000 copper: whole numbers as %.0f
local function Int(x) return ("%.0f"):format(math.floor(tonumber(x) or 0)) end
P.Int = Int -- (tests)
local function RowText(v)
  local s = table.concat({ Int(v[1]), Int(v[2]), Int(v[3]), Int(v[4]), Int(v[6] or v[1]), Int(v[7] or v[1]), Int(v[8] or v[2]) }, ",")
  -- the ladder (fields 8 to 12: the first 50, 200, 500, 1000, 2000 on average), all five or none
  if v[9] and v[10] and v[11] and v[12] and v[13] then
    s = s .. "," .. table.concat({ Int(v[9]), Int(v[10]), Int(v[11]), Int(v[12]), Int(v[13]) }, ",")
  end
  return s
end
-- (Daniel 16.11.2026, Berufsscan) one item's row written anew from a search (v as a row of ns.Aggregate; nil: nothing on
-- offer, the row goes). Without a scan yet a store of its own starts (part = true). st.pt[id]: when the row was read.
function P.SaveItem(key, id, v)
  key = key or P.StoreKey()
  ns.db.ah = ns.db.ah or {}
  local st = ns.db.ah[key]
  if not st then st = { t = time(), i = {}, n = 0, part = true } ns.db.ah[key] = st end
  st.i[id] = v and RowText(v) or nil
  st.pt = st.pt or {}
  st.pt[id] = time()
  local c = cache[key]
  if c then c.rows[id] = nil end
  -- (Daniel 20.11.2026) the day's price history (History.lua)
  if v and ns.History then ns.History.Add(key, id, v[6] or v[1]) end
end
-- when the item's row was read: by a search of its own (Berufsscan), else the scan
function P.RowTime(id, key)
  local st = P.Store(key)
  return st and ((st.pt and st.pt[id]) or st.t) or nil
end

function P.SaveScan(key, agg, count, pause)
  ns.db.ah = ns.db.ah or {}
  local i = {}
  local done = 0
  for id, v in pairs(agg) do
    -- (14.11.2026: 78 ms in one frame for 5900 items) in slices inside the scan's job
    done = done + 1
    if pause and done % 256 == 0 then pause() end
    i[id] = RowText(v)
  end
  ns.db.ah[key] = { t = time(), i = i, n = count }
  local keys = {}
  for k in pairs(ns.db.ah) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return (ns.db.ah[a].t or 0) > (ns.db.ah[b].t or 0) end)
  for n = 4, #keys do ns.db.ah[keys[n]] = nil end
  P.Invalidate()
  -- (Daniel 20.11.2026: median of the last days and the trend) each scan is a reading of the day (History.lua)
  if ns.History then ns.History.AddScan(key, agg, pause) end
end

---------------------------------------------------------------------------
-- (Daniel 06.11.2026: "Checke die Möglichkeit, ob wir TSM daten dazu nutzen können") TSM, only read at run time with
-- pcall, nothing copied into our files. Names checked in TradeSkillMaster 4.15.2 (App/API.lua):
-- TSM_API.GetCustomPriceValue(customPriceStr, itemString) with the item string "i:<id>"; price sources DBMarket,
-- DBMinBuyout, DBHistorical, DBRegionMarketAvg, DBRegionSaleRate (LibTSMApp/Source/Config/AuctionDBConfig.lua).
-- The own scan stays the source of the cheapest offer now (buying, posting); TSM's market value only smooths the value
-- of disenchant mats (the lower of the two counts).
---------------------------------------------------------------------------
function P.TSMReady()
  return ns.Opt("tsm") and type(_G.TSM_API) == "table" and type(_G.TSM_API.GetCustomPriceValue) == "function" or false
end
function P.TSM(id, source)
  if not P.TSMReady() then return nil end
  local ok, v = pcall(_G.TSM_API.GetCustomPriceValue, source or "DBMarket", "i:" .. id)
  if ok and type(v) == "number" and v > 0 then return math.floor(v) end
end

-- (Daniel 14.11.2026, demand) TSM's value sources DBRegionSoldPerDay and DBRegionSaleRate (LibTSMApp AuctionDBConfig.lua
-- RegisterNumberSource: already divided by 1000) are decimals and may be 0: not floored, 0 is an answer
function P.TSMNum(id, source)
  if not P.TSMReady() then return nil end
  local ok, v = pcall(_G.TSM_API.GetCustomPriceValue, source, "i:" .. id)
  if ok and type(v) == "number" and v >= 0 then return v end
end

-- what one unit of a mat brings at the AH after the cut: the cheapest real offer (Daniel: posted at exactly that price),
-- the lower of it and TSM's market value when TSM has one; source "scan", "tsm" or "scan+tsm"
function P.MatNet(id, key)
  local low, tsm = P.Low(id, key), P.TSM(id)
  local unit, src
  if low and tsm then unit, src = math.min(low, tsm), "scan+tsm"
  elseif low then unit, src = low, "scan"
  elseif tsm then unit, src = tsm, "tsm" end
  if not unit then return nil end
  return ns.Deals.AfterCut(unit, P.Cut()), unit, src
end
