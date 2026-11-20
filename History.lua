local _, ns = ...

---------------------------------------------------------------------------
-- (Daniel 20.11.2026: "Beim Einkaufen wäre besonders wichtig, dass wir den Median der Preise der Waren angezeigt bekommen,
-- für die letzten 3 bis 5 Tage, und wohin die Tendenz ist") a small price history per item: every full scan and every
-- search of one item (Berufsscan) puts the item's cheapest real offer (Prices row field 5, low outliers passed over)
-- into the day it was read; a day's value is the median of its readings. The scan store itself keeps only the newest scan
-- per auction house (Prices.SaveScan), so the days live here.
-- Saved per realm and side, ProfitdonDB.hist[key] = { day = the day of the newest reading (days since 1970, UTC),
--   t = { [id] = "p,p,p" } the readings of that day (at most TODAY_MAX, the newest kept),
--   d = { [id] = "m1,m2,...,m6" } the medians of the days before (m1 the day before `day`, empty for a day without one) }
-- KEEP days in all (today and 29 before); an item without any value goes. About 6000 items take a few hundred KB.
--   H.Days(id)        { [daysAgo] = value } of the last KEEP days
--   H.Median(id, n)   median of the day values of the last n days (option medDays, 5 by default), the days counted
--   H.Trend(id, n)    the newer half of the n days against the older half: pct and "up" / "down" / "flat" (within FLAT %)
---------------------------------------------------------------------------
local H = {}
ns.History = H
H.KEEP = 30 -- (Daniel 20.11.2026: 30 Tage aufbewahren, Median und Tendenz über medDays)
H.TODAY_MAX = 12
H.FLAT = 5 -- percent: a change within this counts as steady

local floor = math.floor

function H.Today() return floor((tonumber(time()) or 0) / 86400) end

local function Store(key, make)
  key = key or ns.Prices.StoreKey()
  ns.db.hist = type(ns.db.hist) == "table" and ns.db.hist or (make and {} or nil)
  if not ns.db.hist then return nil end
  local h = ns.db.hist[key]
  if type(h) ~= "table" and make then h = { day = H.Today(), t = {}, d = {} } ns.db.hist[key] = h end
  return type(h) == "table" and h or nil
end
H.Store = Store

local function Nums(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for v in (s .. ","):gmatch("([^,]*),") do out[#out + 1] = tonumber(v) or false end
  return out
end
H.Nums = Nums -- (tests)

-- the median of a list of numbers (false and nil left out); nil for none
local function Median(list)
  local v = {}
  for _, x in ipairs(list) do if type(x) == "number" then v[#v + 1] = x end end
  if #v == 0 then return nil end
  table.sort(v)
  local m = (#v + 1) / 2
  if m == floor(m) then return v[m] end
  return floor((v[floor(m)] + v[floor(m) + 1]) / 2 + 0.5)
end
H.MedianOf = Median

local function Int(x) return ns.Prices.Int and ns.Prices.Int(x) or ("%.0f"):format(x) end

-- a new day: today's readings become one value at the front of each item's days, the gap filled with empties
local function Roll(h, day, pause)
  local gap = day - (h.day or day)
  if gap <= 0 then return end
  local d, done = {}, 0
  local ids = {}
  for id in pairs(h.t) do ids[id] = true end
  for id in pairs(h.d) do ids[id] = true end
  for id in pairs(ids) do
    done = done + 1
    if pause and done % 256 == 0 then pause() end
    local m = Median(Nums(h.t[id]))
    local old = Nums(h.d[id])
    -- the readings of h.day lie `gap` days back from the new day: the days between stay empty
    local list = {}
    for _ = 2, gap do list[#list + 1] = "" end
    list[#list + 1] = m and Int(m) or ""
    for _, v in ipairs(old) do list[#list + 1] = v and Int(v) or "" end
    while #list > H.KEEP - 1 do list[#list] = nil end
    local any = false
    for _, v in ipairs(list) do if v ~= "" then any = true break end end
    if any then
      while list[#list] == "" do list[#list] = nil end
      d[id] = table.concat(list, ",")
    end
  end
  h.d, h.t, h.day = d, {}, day
end

-- one reading of an item (price per unit in copper)
function H.Add(key, id, price, pause)
  price = tonumber(price)
  if not (id and price and price > 0) then return end
  local h = Store(key, true)
  local day = H.Today()
  if day > (h.day or day) then Roll(h, day, pause) end
  local list = Nums(h.t[id])
  list[#list + 1] = price
  while #list > H.TODAY_MAX do table.remove(list, 1) end
  local s = {}
  for i, v in ipairs(list) do s[i] = v and Int(v) or "" end
  h.t[id] = table.concat(s, ",")
end

-- a whole scan: agg as ns.Aggregate gives it (v[6] the cheapest real offer, else v[1])
function H.AddScan(key, agg, pause)
  local h = Store(key, true)
  local day = H.Today()
  if day > (h.day or day) then Roll(h, day, pause) end
  local done = 0
  for id, v in pairs(agg or {}) do
    done = done + 1
    if pause and done % 256 == 0 then pause() end
    if type(v) == "table" then H.Add(key, id, v[6] or v[1]) end
  end
end

-- (Daniel 20.11.2026: "etliche Tage mit Auktionshaus-Scans ... die könnte man doch jetzt erstmal nehmen") the days of
-- the scans kept in the workshop's data store (Data/PriceSeed.lua, tools/profitdon/build_price_seed.py) fill the days the
-- own history has no value for; older than KEEP days they drop out by themselves
function H.SeedDays(id, key, out)
  local seed = ns.PRICE_SEED and ns.PRICE_SEED[key or ns.Prices.StoreKey()]
  local s = seed and seed.d and seed.d[id]
  if not s then return out end
  local shift = H.Today() - (tonumber(seed.day) or 0)
  if shift < 0 then return out end
  for i, v in ipairs(Nums(s)) do
    local ago = shift + i - 1
    if ago >= H.KEEP then break end
    if v and out[ago] == nil then out[ago] = v end
  end
  return out
end

-- { [daysAgo] = value } for the last KEEP days (own history first, the seed for the days without one)
function H.Days(id, key)
  local h = Store(key)
  local out = {}
  if not h then return H.SeedDays(id, key, out) end
  local shift = H.Today() - (h.day or H.Today())
  if shift < 0 then shift = 0 end
  local today = Median(Nums(h.t[id]))
  if today then out[shift] = today end
  for i, v in ipairs(Nums(h.d[id])) do
    if v and shift + i < H.KEEP then out[shift + i] = v end
  end
  H.SeedDays(id, key, out)
  return out
end

local function Window() return tonumber(ns.Opt and ns.Opt("medDays")) or 5 end
H.Window = Window

-- median of the day values of the last n days, and how many days had one
function H.Median(id, n, key)
  n = n or Window()
  local days = H.Days(id, key)
  local list = {}
  for ago = 0, n - 1 do if days[ago] then list[#list + 1] = days[ago] end end
  return Median(list), #list
end

-- (Daniel: "wohin die Tendenz ist") the newer days against the older ones: the median of the newer half of the window
-- against the median of the older half (5 days: today and yesterday against the three before). Needs a value on both
-- sides. Returns pct (whole percent, + dearer), dir "up" / "down" / "flat", or nil.
function H.Trend(id, n, key)
  n = n or Window()
  local days = H.Days(id, key)
  local cut = floor(n / 2)
  local new, old = {}, {}
  for ago = 0, n - 1 do
    local v = days[ago]
    if v then if ago < cut then new[#new + 1] = v else old[#old + 1] = v end end
  end
  local a, b = Median(new), Median(old)
  if not (a and b and b > 0) then return nil end
  local x = (a - b) * 100 / b
  local pct = x >= 0 and floor(x + 0.5) or -floor(-x + 0.5)
  local dir = math.abs(pct) < H.FLAT and "flat" or pct > 0 and "up" or "down"
  return pct, dir, a, b
end

-- short text for a cell ("+12 %", "-8 %", "±0 %") and its colour (dearer red, cheaper green for a buyer)
function H.TrendText(id, n, key)
  local pct, dir = H.Trend(id, n, key)
  if not pct then return "", nil end
  local s = pct > 0 and ("+" .. pct .. " %") or pct < 0 and (pct .. " %") or "±0 %"
  return s, dir == "up" and "red" or dir == "down" and "green" or nil, dir, pct
end
H.WORD = { up = "steigt", down = "fällt", flat = "gleich" }

-- the old days of all items once a day, also when no scan comes (the store does not grow with old values)
function H.Prune(key)
  local h = Store(key)
  if h and H.Today() > (h.day or 0) then Roll(h, H.Today()) end
end

ns.OnInit(function()
  if type(ns.db.hist) ~= "table" then return end
  for key in pairs(ns.db.hist) do pcall(H.Prune, key) end
end)
