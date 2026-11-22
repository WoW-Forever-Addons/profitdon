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

-- (21.11.2026, Ruckler) H.ver counts every change of the history (a reading, a scan, a new day rolled, a merge): the
-- tooltip and the AH page keep median and trend per item for the same version (H.Info)
H.ver = 0
local function Bump() H.ver = H.ver + 1 end
H.Bump = Bump

-- (21.11.2026, Ruckler) the roll of a whole store (all items) at login, after UTC midnight and the merge of an empty-realm
-- history run as background jobs, a few ms a frame. A store a job will change is "pending": the store itself is only
-- changed at the job's end, so reading it meanwhile gives the same values (H.Days counts the days from h.day), and
-- whatever writes to it (H.Add, H.AddScan, H.Merge, H.Prune) first finishes the job at once, so every result stays
-- the one the old all-at-once way gave. PLAYER_LOGOUT finishes all jobs before the game saves.
local jobs, pending = {}, {}
local hurry, sliceStart = false, 0
H.SLICE = 4 -- ms a frame
local function Clock() local f = rawget(_G, "debugprofilestop") return type(f) == "function" and f() or nil end
local function Yield()
  if hurry or not coroutine.running() then return end
  local t = Clock()
  if t == nil or t - sliceStart >= H.SLICE then coroutine.yield() end
end
local function JobDone(j)
  for _, h in ipairs(j.stores) do if pending[h] == j then pending[h] = nil end end
end
local function RunJob(j, all)
  if coroutine.status(j.co) ~= "suspended" then JobDone(j) return end
  local was = hurry
  if all then hurry = true end
  sliceStart = Clock() or 0
  local ok, err = coroutine.resume(j.co)
  while ok and all and coroutine.status(j.co) == "suspended" do ok, err = coroutine.resume(j.co) end
  hurry = was
  if not ok then JobDone(j) ns.Try(error, err, 0) end
  if coroutine.status(j.co) == "dead" then JobDone(j) end
end
-- a store's job finished now (nothing when none, or when it is the job that runs)
local function Ready(h)
  local j = h and pending[h]
  if not j or coroutine.running() == j.co then return end
  RunJob(j, true)
end
H.Ready = Ready
local worker
local function Work()
  while jobs[1] and coroutine.status(jobs[1].co) == "dead" do JobDone(table.remove(jobs, 1)) end
  local j = jobs[1]
  if not j then if worker then worker:SetScript("OnUpdate", nil) end return end
  RunJob(j)
end
-- fn(pause) as a job that will change the stores in the list
local function Later(stores, fn)
  local j = { stores = stores }
  j.co = coroutine.create(function() fn(Yield) end)
  for _, h in ipairs(stores) do
    if pending[h] then Ready(h) end
    pending[h] = j
  end
  jobs[#jobs + 1] = j
  worker = worker or CreateFrame("Frame")
  worker:SetScript("OnUpdate", Work)
  return j
end
-- every job finished now (logout; the tests)
function H.FinishJobs()
  for _, j in ipairs(jobs) do RunJob(j, true) end
  jobs = {}
  if worker then worker:SetScript("OnUpdate", nil) end
end
function H.JobsLeft() local n = 0 for _, j in ipairs(jobs) do if coroutine.status(j.co) ~= "dead" then n = n + 1 end end return n end

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
  Ready(h)
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
  Bump()
end

-- (21.11.2026, Core.lua ns.FixRealmKeys) two histories of one auction house (one saved under an empty realm name) into
-- dst: both rolled to today, today's readings put together (the newest TODAY_MAX), each earlier day from dst, else src
-- pause: yields inside a job (H.MergeLater)
function H.Merge(src, dst, pause)
  if type(src) ~= "table" or type(dst) ~= "table" then return end
  Ready(src) Ready(dst)
  src.t, src.d = type(src.t) == "table" and src.t or {}, type(src.d) == "table" and src.d or {}
  dst.t, dst.d = type(dst.t) == "table" and dst.t or {}, type(dst.d) == "table" and dst.d or {}
  local day = math.max(H.Today(), src.day or 0, dst.day or 0)
  src.day, dst.day = src.day or day, dst.day or day
  Roll(src, day, pause)
  Roll(dst, day, pause)
  local done = 0
  for id, s in pairs(src.t) do
    done = done + 1
    if pause and done % 256 == 0 then pause() end
    local list = Nums(dst.t[id])
    for _, v in ipairs(Nums(s)) do list[#list + 1] = v end
    while #list > H.TODAY_MAX do table.remove(list, 1) end
    local out = {}
    for i, v in ipairs(list) do out[i] = v and Int(v) or "" end
    dst.t[id] = table.concat(out, ",")
  end
  for id, s in pairs(src.d) do
    done = done + 1
    if pause and done % 256 == 0 then pause() end
    local a, b = Nums(dst.d[id]), Nums(s)
    local out = {}
    for i = 1, math.max(#a, #b) do
      local v = a[i] or b[i]
      out[i] = v and Int(v) or ""
    end
    dst.d[id] = table.concat(out, ",")
  end
  Bump()
end
-- (21.11.2026, Ruckler) the same as a background job (Core.lua ns.FixRealmKeys at login): both stores pending until done
function H.MergeLater(src, dst)
  if type(src) ~= "table" or type(dst) ~= "table" then return end
  Later({ src, dst }, function(pause) H.Merge(src, dst, pause) end)
end

-- one reading of an item (price per unit in copper)
function H.Add(key, id, price, pause)
  price = tonumber(price)
  if not (id and price and price > 0) then return end
  local h = Store(key, true)
  Ready(h)
  local day = H.Today()
  if day > (h.day or day) then Roll(h, day, pause) end
  local list = Nums(h.t[id])
  list[#list + 1] = price
  while #list > H.TODAY_MAX do table.remove(list, 1) end
  local s = {}
  for i, v in ipairs(list) do s[i] = v and Int(v) or "" end
  h.t[id] = table.concat(s, ",")
  Bump()
end

-- a whole scan: agg as ns.Aggregate gives it (v[6] the cheapest real offer, else v[1])
function H.AddScan(key, agg, pause)
  local h = Store(key, true)
  Ready(h)
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
-- (Daniel 22.11.2026, Wolf Bracers without any price: "Es gibt nur einen realm") Forever has one AH per side, the game
-- names it differently ("EU4 Realm 7 PvE", "EU5 Realm 1 PvE", "" since 21.11.), so the seed of every realm key of the
-- same side counts: the own key first, then the others, the newest first
local seedList, seedListOf, seedListKey = nil, nil, nil
local function SeedsFor(key)
  local S = ns.PRICE_SEED
  if type(S) ~= "table" then return {} end
  if seedListOf == S and seedListKey == key then return seedList end
  local side = type(key) == "string" and key:match("|([ANH])$")
  local list = {}
  for k, v in pairs(S) do
    if type(v) == "table" and type(v.d) == "table" and (k == key or (side and type(k) == "string" and k:match("|([ANH])$") == side)) then
      list[#list + 1] = { k == key and 1 or 0, tonumber(v.day) or 0, v }
    end
  end
  table.sort(list, function(a, b) if a[1] ~= b[1] then return a[1] > b[1] end return a[2] > b[2] end)
  for i, e in ipairs(list) do list[i] = e[3] end
  seedList, seedListOf, seedListKey = list, S, key
  return list
end
function H.SeedDays(id, key, out)
  local today = H.Today()
  for _, seed in ipairs(SeedsFor(key or ns.Prices.StoreKey())) do
    local s = seed.d[id]
    local shift = today - (tonumber(seed.day) or 0)
    if s and shift >= 0 then
      for i, v in ipairs(Nums(s)) do
        local ago = shift + i - 1
        if ago >= H.KEEP then break end
        if v and out[ago] == nil then out[ago] = v end
      end
    end
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
local function MedianOfDays(days, n)
  local list = {}
  for ago = 0, n - 1 do if days[ago] then list[#list + 1] = days[ago] end end
  return Median(list), #list
end
function H.Median(id, n, key)
  return MedianOfDays(H.Days(id, key), n or Window())
end

-- (Daniel: "wohin die Tendenz ist") the newer days against the older ones: the median of the newer half of the window
-- against the median of the older half (5 days: today and yesterday against the three before). Needs a value on both
-- sides. Returns pct (whole percent, + dearer), dir "up" / "down" / "flat", or nil.
local function TrendOfDays(days, n)
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
function H.Trend(id, n, key)
  return TrendOfDays(H.Days(id, key), n or Window())
end

-- short text for a cell ("+12 %", "-8 %", "±0 %") and its colour (dearer red, cheaper green for a buyer)
local function TextOf(pct, dir)
  if not pct then return "", nil end
  local s = pct > 0 and ("+" .. pct .. " %") or pct < 0 and (pct .. " %") or "±0 %"
  return s, dir == "up" and "red" or dir == "down" and "green" or nil, dir, pct
end
function H.TrendText(id, n, key)
  return TextOf(H.Trend(id, n, key))
end

-- (21.11.2026, Ruckler: Blizzard builds a bag tooltip about 5 times a second, each build ran H.Days twice with its
-- CSV parsing and sorts) median, days, trend text, colour, direction and pct of the window for the tooltip and the AH
-- page, worked out once per item and kept while nothing they come from changed: the history (H.ver, the tables
-- themselves), the seed, the day, the window (option medDays) and the auction house (StoreKey)
local info, infoN, stamp = {}, 0, {}
H.INFO_MAX = 4000
function H.Info(id)
  local n, key = Window(), ns.Prices.StoreKey()
  local hist = ns.db.hist
  local store = type(hist) == "table" and hist[key] or nil
  local s, day = stamp, H.Today()
  if s.ver ~= H.ver or s.day ~= day or s.n ~= n or s.key ~= key or s.hist ~= hist or s.store ~= store
    or s.seed ~= ns.PRICE_SEED or infoN >= H.INFO_MAX then
    stamp = { ver = H.ver, day = day, n = n, key = key, hist = hist, store = store, seed = ns.PRICE_SEED }
    info, infoN = {}, 0
  end
  local e = info[id]
  if not e then
    local days = H.Days(id, key)
    local med, cnt = MedianOfDays(days, n)
    local tt, col, dir, pct = TextOf(TrendOfDays(days, n))
    e = { med, cnt, tt, col, dir, pct }
    info[id] = e
    infoN = infoN + 1
  end
  return e[1], e[2], e[3], e[4], e[5], e[6]
end
H.WORD = { up = "steigt", down = "fällt", flat = "gleich" }

-- the old days of all items once a day, also when no scan comes (the store does not grow with old values)
function H.Prune(key)
  local h = Store(key)
  if h and H.Today() > (h.day or 0) then Roll(h, H.Today()) end
end

-- (21.11.2026, Ruckler) every store that needs a new day rolled, as background jobs (at login, after UTC midnight)
function H.PruneLater()
  if type(ns.db) ~= "table" or type(ns.db.hist) ~= "table" then return 0 end
  local n, today = 0, H.Today()
  for _, h in pairs(ns.db.hist) do
    if type(h) == "table" and type(h.t) == "table" and type(h.d) == "table" and not pending[h] and today > (h.day or 0) then
      n = n + 1
      Later({ h }, function(pause) Roll(h, today, pause) end)
    end
  end
  return n
end
-- the next UTC midnight (and a few seconds): the day's roll before the first search of the new day needs it
local function AtMidnight()
  local now = tonumber(time()) or 0
  ns.After(86400 - now % 86400 + 5, function() ns.Try(H.PruneLater) AtMidnight() end)
end
ns.OnInit(function()
  if type(ns.db.hist) == "table" then ns.Try(H.PruneLater) end
  AtMidnight()
end)
ns.On("PLAYER_LOGOUT", function() H.FinishJobs() end)
