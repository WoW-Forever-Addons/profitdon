local _, ns = ...

---------------------------------------------------------------------------
-- Full scan of the auction house (from Golddon's Scan.lua, lean): ns.AH.ReplicateItems, once every 15 minutes per
-- character; every auction read once in chunks, the raw rows stay in memory. Saved per auction house: lowest, median,
-- quantity, auctions and the cheapest real offer per item. Lists worked out from the rows:
--   vendor: buyout under what the vendor pays (Händler)
--   de:     gear whose expected mats after the cut are worth more than its buyout (Entzaubern > AH)
-- A full scan another addon asked for is read along (the game's 15 minutes are spent anyway). Own auctions are skipped.
---------------------------------------------------------------------------
local S = { phase = "idle", open = false, done = 0, total = 0 }
ns.ScanState = S
local FULL_EVERY, SETTLE, TIMEOUT = 15 * 60, 1.5, 120
-- (Daniel 08.11.2026, 268000 auctions: the game nearly froze after the scan, then stuttered for a while) all work of the
-- scan in slices of at most BUDGET ms per frame; reading at most READ_MAX auctions per frame
-- (Daniel 14.11.2026, 223000 auctions: "während des Ladens ist der rechner guuut am arbeiten und das spiel ruckelt"; diag:
-- reading 2007 ms in 247 frames = 8 ms on top of every frame, longest frame 89 ms) the slice is the option scanBudget
-- (4 ms, was 8) and halves while the game is slow anyway (the last frame over 33 ms): the scan takes a few seconds longer
local READ_MAX = 2000
local lastDt = 0
-- (Daniel 14.11.2026, diag: reading 145 s at 10 frames a second, our work 2 ms of each 100 ms frame) halving on a slow
-- frame only made the slow time five times longer: the frames were slow for another reason. On a slow frame the slice
-- is an eighth of the frame (at least half the option, at most 20 ms): not felt next to 100 ms, and the reading ends soon
local function Budget()
  local b = ns.Opt and ns.Opt("scanBudget") or 4
  if lastDt > 0.033 then b = math.max(b / 2, math.min(20, lastDt * 1000 / 8)) end
  return math.max(1, b)
end
ns.ScanBudget = Budget
function ns.ScanFrame(dt) lastDt = tonumber(dt) or 0 end -- (tests) the last frame's length

local raw
ns.lists = { vendor = {}, de = {} }

local driver = CreateFrame("Frame")
local function notify() if ns.Refresh then ns.Refresh() end end
local T -- times of the last scan: T[step] = { ms, frames, max }, T[1..] the steps in order, T.worst, T.mem0, T.mem1
-- (Daniel 14.11.2026: 10 frames a second while reading, though the scan's own work was 2 ms a frame) the progress of a
-- running scan redrew the whole window four times a second (lists, chips, bar; not measured before): only the status
-- line now, and what it costs is counted (T.draws, T.drawMs, T.drawMax)
local function progress()
  local f = ns.RefreshStatus or ns.Refresh
  if not f then return end
  local p = debugprofilestop
  local t0 = p and p() or 0
  f()
  if T and p then
    local ms = p() - t0
    T.draws, T.drawMs, T.drawMax = (T.draws or 0) + 1, (T.drawMs or 0) + ms, math.max(T.drawMax or 0, ms)
  end
end

local function LastScan() return ns.db and ns.db.lastScanBy and ns.db.lastScanBy[ns.Me()] end
local function SetLastScan(t)
  ns.db.lastScanBy = ns.db.lastScanBy or {}
  ns.db.lastScanBy[ns.Me()] = t
end

function ns.ScanWait()
  local last = LastScan() or 0
  return math.max(0, last + FULL_EVERY - time())
end

local function InCombat() return ns.Call(InCombatLockdown) == true end

---------------------------------------------------------------------------
-- Jobs: the heavy work runs in a coroutine that yields when its slice is spent; outside a job the same functions simply
-- run to the end (tests, an option changed before any scan). Each step's work, frames and slowest slice are kept for
-- /profit diag ("scanTimes", "scanLate").
---------------------------------------------------------------------------
local function Now()
  local f = debugprofilestop
  if f then return f() end
  return (GetTime() or 0) * 1000
end
local inJob, sliceStart = false, 0
local function Pause()
  if inJob and Now() - sliceStart >= Budget() then coroutine.yield() end
end

local function Took(step, ms)
  if not T then return end
  local s = T[step]
  if not s then s = { ms = 0, frames = 0, max = 0 } T[step] = s T[#T + 1] = step end
  s.ms, s.frames, s.max = s.ms + ms, s.frames + 1, math.max(s.max, ms)
  if ms > (T.worst or 0) then T.worst, T.worstStep = ms, step end
end
local NAMES = { read = "Lesen", agg = "Gruppieren", save = "Speichern", market = "Markt", compute = "Rechnen" }
local function Mem() return ns.Num(ns.Call(collectgarbage, "count")) end
function ns.ScanTimes()
  if not T then return nil end
  local parts = {}
  for _, k in ipairs(T) do
    local s = T[k]
    if NAMES[k] then parts[#parts + 1] = ("%s %d ms in %d Frames"):format(NAMES[k] or k, math.floor(s.ms + 0.5), s.frames) end
  end
  local txt = table.concat(parts, ", ") .. (", längster Frame %d ms%s"):format(math.floor((T.worst or 0) + 0.5),
    T.worstStep and (" (" .. (NAMES[T.worstStep] or T.worstStep) .. ")") or "")
  if T.mem0 and T.mem1 then txt = txt .. (", Lua-Speicher %d auf %d MB"):format(math.floor(T.mem0 / 1024 + 0.5), math.floor(T.mem1 / 1024 + 0.5)) end
  -- (Daniel 14.11.2026: the gentler scan took 147 s instead of 30, the steps above explained only a part) where the
  -- seconds went: waiting for the auction house, reading (with the frames a second the game made then), working out;
  -- and the item data asked for
  if T.waitS then txt = txt .. (", Warten %d s"):format(math.floor(T.waitS + 0.5)) end
  if T.readS then
    txt = txt .. (", Lesen %d s"):format(math.floor(T.readS + 0.5))
    if (T.readFrames or 0) > 0 and T.readS > 0 then txt = txt .. (" (%d Bilder/s)"):format(math.floor(T.readFrames / T.readS + 0.5)) end
  end
  if T.finS then txt = txt .. (", Auswerten %d s"):format(math.floor(T.finS + 0.5)) end
  if T.req then txt = txt .. (", %d Itemanfragen"):format(T.req) end
  if T.draws then txt = txt .. (", Anzeige %d mal %d ms (längste %d ms)"):format(T.draws, math.floor(T.drawMs + 0.5), math.floor(T.drawMax + 0.5)) end
  if T.waitFrames and (T.waitS or 0) > 0 then txt = txt .. (", Bilder/s beim Warten %d"):format(math.floor(T.waitFrames / T.waitS + 0.5)) end
  if T.finFrames and (T.finS or 0) > 0 then txt = txt .. (", beim Auswerten %d"):format(math.floor(T.finFrames / T.finS + 0.5)) end
  return txt
end

local jobber = CreateFrame("Frame")
local job
local function Slice()
  local j = job
  sliceStart = Now()
  j.mark = sliceStart
  inJob = true
  local ok, err = coroutine.resume(j.co)
  inJob = false
  local t = Now()
  if j.step then Took(j.step, t - j.mark) end
  if T and t - sliceStart > (T.worst or 0) then T.worst, T.worstStep = t - sliceStart, j.step end
  if not ok or coroutine.status(j.co) == "dead" then
    if job == j then job = nil jobber:SetScript("OnUpdate", nil) end
    if not ok then
      ns.Try(error, err, 0)
      -- (Daniel 17.11.2026, diag "scanFail: Fehler beim Auswerten" without the error) the error itself for /profit diag
      ns.Fact("scanError", ("%s (%s)"):format(tostring(err), tostring(j.step or j.kind)))
      if j.fail then j.fail(err) end
    elseif j.done then j.done() end
  end
end
-- inside a job: the next step (the time so far goes to the step before)
local function StepTo(name)
  local j = job
  if not (j and inJob) then return end
  local t = Now()
  if j.step then Took(j.step, t - j.mark) end
  j.step, j.mark = name, t
end
-- fn runs as a job, done after it, fail after an error; now: the first slice at once (an option change, the tests: the
-- result is there at once when it fits into one slice)
local function StartJob(kind, fn, done, fail, now)
  local j = { kind = kind, done = done, fail = fail }
  j.co = coroutine.create(fn)
  job = j
  jobber:SetScript("OnUpdate", function(_, dt) lastDt = tonumber(dt) or 0 if job then Slice() else jobber:SetScript("OnUpdate", nil) end end)
  if now then Slice() end
end
function ns.ScanBusy() return job ~= nil end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
local function Sorted(map)
  local out = {}
  for _, v in pairs(map) do out[#out + 1] = v end
  table.sort(out, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return a.id < b.id end)
  return out
end

local function AddTo(map, id, d, count)
  local e = map[id]
  if not e then e = { id = id, count = 0, cost = 0, ret = 0, profit = 0, n = 0 } map[id] = e end
  e.count, e.cost, e.ret, e.profit, e.n = e.count + count, e.cost + d.cost, e.ret + d.ret, e.profit + d.profit, e.n + 1
  return e
end

-- an item with thousands of auctions: sorted in runs of RUN numbers, then merged with pauses (Daniel's /profit diag
-- 08.11.2026: longest frame 47 ms); returns the sorted list (r itself or a new one)
local RUN = 2048
local function SortLong(r)
  local m = #r
  if m <= RUN * 2 then table.sort(r) return r end
  local tmp = {}
  for s = 1, m, RUN do
    local e = math.min(m, s + RUN - 1)
    local n = 0
    for k = s, e do n = n + 1 tmp[n] = r[k] end
    for k = #tmp, n + 1, -1 do tmp[k] = nil end
    table.sort(tmp)
    for k = 1, n do r[s + k - 1] = tmp[k] end
    Pause()
  end
  local src, dst, w = r, {}, RUN
  while w < m do
    local o = 1
    for s = 1, m, 2 * w do
      local i, iend = s, math.min(s + w - 1, m)
      local j, jend = iend + 1, math.min(s + 2 * w - 1, m)
      while i <= iend and j <= jend do
        if src[i] <= src[j] then dst[o] = src[i] i = i + 1 else dst[o] = src[j] j = j + 1 end
        o = o + 1
        if o % 1024 == 0 then Pause() end
      end
      while i <= iend do dst[o] = src[i] i, o = i + 1, o + 1 end
      while j <= jend do dst[o] = src[j] j, o = j + 1, o + 1 end
    end
    src, dst, w = dst, src, w * 2
  end
  return src
end

-- per item: { min, weighted median, quantity, auctions, plain median, cheapest real offer, first 20, first 100 }
-- (08.11.2026) no table per auction any more (268000 small tables, 50 MB of garbage): per item one list of row numbers,
-- sorted by the unit price of the row; the same results as Deals.Median and Deals.LowOffer on { unit, count }.
-- (Daniel 08.11.2026 /profit diag: longest frame 47 ms) a sort with a Lua compare function cannot be paused and is slow
-- for an item with thousands of auctions: the list holds plain numbers (unit price in quarter copper, row number in the
-- low bits) that table.sort compares itself; afterwards only the row numbers stay. raw.rows keeps the lists for Compute.
function ns.Aggregate()
  if not raw then return end
  if raw.agg then return raw.agg end
  local ids, cnt, bo = raw.id, raw.cnt, raw.bo
  local shift = 2
  while shift <= raw.n do shift = shift * 2 end
  local top = math.floor(2 ^ 52 / shift) -- highest quarter copper that still fits next to the row number
  local rows = {}
  for i = 1, raw.n do
    local c, b = cnt[i], bo[i]
    if b > 0 and c > 0 then
      local id = ids[i]
      local r = rows[id]
      if not r then r = {} rows[id] = r end
      r[#r + 1] = math.min(top, math.floor(b * 4 / c)) * shift + i
    end
    if i % 1024 == 0 then Pause() end
  end
  local agg, done = {}, 0
  for id, r in pairs(rows) do
    if #r > RUN * 2 then r = SortLong(r) rows[id] = r else table.sort(r) end
    local m, q = #r, 0
    for k = 1, m do
      local i = r[k] % shift
      r[k] = i
      q = q + cnt[i]
      if k % 2048 == 0 then Pause() end
    end
    local function U(k) local i = r[k] return bo[i] / cnt[i] end
    local half, run, wmed = q / 2, 0, nil
    for k = 1, m do
      run = run + cnt[r[k]]
      if run >= half then wmed = U(k) break end
    end
    wmed = wmed or U(m)
    local plain = U(math.floor((m + 1) / 2))
    -- the cheapest real offer: cheap single offers far under the next passed over (as Deals.LowOffer)
    local skipped, k = 0, 1
    while k < m and k <= 3 do
      local c = cnt[r[k]]
      if U(k) * 2 < U(k + 1) and (skipped + c) * 10 <= q then skipped, k = skipped + c, k + 1 else break end
    end
    local low = U(k)
    -- (Daniel 06.11.2026, Rough Stone 8c in the AH, the list said 25c: the median of all 9471) what the first 20 and the first
    -- 100 units cost on average, cheapest first
    local function Depth(n)
      local got, cost = 0, 0
      for x = 1, m do
        local take = math.min(cnt[r[x]], n - got)
        got, cost = got + take, cost + take * U(x)
        if got >= n then break end
      end
      return got > 0 and math.ceil(cost / got) or nil
    end
    agg[id] = { math.floor(U(1) + 0.5), math.floor(wmed + 0.5), q, m, math.floor(plain + 0.5), math.floor(low + 0.5), Depth(20), Depth(100) }
    -- (Daniel 09.11.2026: "wie lange wir mit positivem cashflow rauskommen") the price ladder: what the first 50, 200, 500,
    -- 1000, 2000 units cost on average (only for items with more than 100 on offer)
    if q > 100 then agg[id][9], agg[id][10], agg[id][11], agg[id][12], agg[id][13] = Depth(50), Depth(200), Depth(500), Depth(1000), Depth(2000) end
    done = done + m
    if done >= 256 then done = 0 Pause() end
  end
  raw.agg, raw.rows = agg, rows
  return agg
end

-- (Daniel 16.11.2026: "eine scan option, dass man nur den beruf scannt") the same numbers as one row of ns.Aggregate,
-- from the offers of one search: offers = { { unit price, count }, ... } in any order. full = false (the search loaded
-- only its first offers): no ladder, the amounts are not all there.
function ns.AggOffers(offers, full)
  local r = {}
  for _, o in ipairs(offers or {}) do if o[1] and o[1] > 0 and o[2] and o[2] > 0 then r[#r + 1] = o end end
  local m = #r
  if m == 0 then return nil end
  table.sort(r, function(a, b) return a[1] < b[1] end)
  local q = 0
  for k = 1, m do q = q + r[k][2] end
  local function U(k) return r[k][1] end
  local half, run, wmed = q / 2, 0, nil
  for k = 1, m do
    run = run + r[k][2]
    if run >= half then wmed = U(k) break end
  end
  wmed = wmed or U(m)
  local plain = U(math.floor((m + 1) / 2))
  local skipped, k = 0, 1
  while k < m and k <= 3 do
    local c = r[k][2]
    if U(k) * 2 < U(k + 1) and (skipped + c) * 10 <= q then skipped, k = skipped + c, k + 1 else break end
  end
  local low = U(k)
  local function Depth(n)
    local got, cost = 0, 0
    for x = 1, m do
      local take = math.min(r[x][2], n - got)
      got, cost = got + take, cost + take * U(x)
      if got >= n then break end
    end
    return got > 0 and math.ceil(cost / got) or nil
  end
  local v = { math.floor(U(1) + 0.5), math.floor(wmed + 0.5), q, m, math.floor(plain + 0.5), math.floor(low + 0.5), Depth(20), Depth(100) }
  if q > 100 and full ~= false then v[9], v[10], v[11], v[12], v[13] = Depth(50), Depth(200), Depth(500), Depth(1000), Depth(2000) end
  return v
end

-- (08.11.2026) the lists per item: the vendor price and the disenchant group once per item, not once per auction (268000
-- GetItemInfo calls, and a load request for every auction of an item the client did not know yet). Kept per item in
-- raw.vmap, raw.dmap and raw.pend, so late item info only works out the items that arrived (ns.ComputeItems).
local function Context()
  local DE = ns.DE
  local values = {}
  return { skill = ns.Crafts and ns.Crafts.MySkill(333), Value = function(g)
    local v = values[g]
    if v == nil then v = DE.Value(g, raw.key) or false values[g] = v end
    return v or nil
  end }
end

local function Item(id, ctx)
  local D, DE = ns.Deals, ns.DE
  local r = raw.rows[id]
  raw.vmap[id], raw.dmap[id], raw.pend[id] = nil, nil, nil
  if not r then return end
  local cnt, bo = raw.cnt, raw.bo
  -- (Daniel 11.11.2026: "die tauchen immer auf ... sie sind sofort weg ... falsche preise hinterlegt"; Greater Magic Wand:
  -- 2039 auctions from 3s, the data file says the vendor pays 15s 35c (Classic), Forever's vendor pays 2s) the price of the
  -- data file is only a guess: what would pay by it waits for the game's own price (ItemInfo asked for it) and is worked
  -- out again when it arrives (raw.pend, Late)
  local sell, src = ns.Prices.Sell(id)
  local guess = src == "data"
  local g, how, v -- the disenchant group only for items offered one by one
  local pending = 0
  for k = 1, #r do
    local i = r[k]
    local c, b = cnt[i], bo[i]
    if not sell then pending = pending + 1 end
    local d = sell and D.VendorFlip(c, b, sell)
    if d and guess then pending = pending + 1
    elseif d then AddTo(raw.vmap, id, d, c).unit = sell end
    if c == 1 then
      if how == nil then g, how = DE.Group(id) how = how or false v = g and ctx.Value(g) end
      if how == "wait" then pending = pending + 1 end
      local f = v and D.DEFlip(b, v)
      if f then
        local e = AddTo(raw.dmap, id, f, 1)
        e.group, e.unitValue, e.how = g, v, how
        e.best = math.min(e.best or b, b)
        -- (Durchsicht 15.11.2026) every paying offer's price: "sicher ab" counts with the n cheapest (DE.SureAtOffers)
        e.prices = e.prices or {}
        e.prices[#e.prices + 1] = b
        e.skill = DE.Skill(g)
        e.tooHigh = ctx.skill and e.skill and ctx.skill < e.skill or nil
      end
    end
    if k % 2048 == 0 then Pause() end
  end
  if pending > 0 then raw.pend[id] = pending end
  return #r
end

-- (Daniel 16.11.2026, Bild: Bright Sphere "Preis ab 18s 70c", the search said 25s 77c: "Preis ab stimmt hier auch nicht
-- mehr, das darf sich ruhig aktualisieren wenn man einkauft") a disenchant row is worked out again from what is known now:
-- the group and value of the data and the own rolls (not those of the scan), and the newest search of the item: offers
-- under its cheapest are gone (bought or taken by others). Offers that no longer pay drop out; none left: the row goes.
-- Only rows with the scan's offer prices (e.prices); lists kept from before stay as they are.
function ns.DELive(e)
  if type(e) ~= "table" or type(e.prices) ~= "table" then return e end
  local DE, D = ns.DE, ns.Deals
  local g = DE.Group(e.id) or e.group
  local v = g and DE.Value(g)
  if not v then return e end
  local fresh = ns.FreshLow and ns.FreshLow(e.id)
  -- the scan's offers stay kept (scanPrices): the row is worked out from them each time, nothing is lost
  e.scanPrices = e.scanPrices or e.prices
  local keep, cost, profit = {}, 0, 0
  for _, p in ipairs(e.scanPrices) do
    local f = (not fresh or p >= fresh) and D.DEFlip(p, v)
    if f then keep[#keep + 1] = p cost, profit = cost + p, profit + f.profit end
  end
  table.sort(keep)
  e.group, e.unitValue, e.prices, e.sorted = g, v, keep, true
  e.n, e.count, e.cost, e.profit = #keep, #keep, cost, profit
  e.best = keep[1]
  e.skill = DE.Skill(g)
  if not keep[1] then e.gone = true end
  return e
end

local function Publish()
  local pending = 0
  for _, n in pairs(raw.pend) do pending = pending + n end
  ns.lists = { vendor = Sorted(raw.vmap), de = Sorted(raw.dmap), pending = pending, key = raw.key, t = raw.t, n = raw.n }
  local keep = { key = raw.key, t = raw.t, n = raw.n }
  for _, k in ipairs({ "vendor", "de" }) do
    keep[k] = {}
    for i = 1, math.min(300, #ns.lists[k]) do keep[k][i] = ns.lists[k][i] end
  end
  ns.db.lastLists = keep
end

function ns.Compute()
  if not raw then return end
  ns.Aggregate()
  raw.vmap, raw.dmap, raw.pend = {}, {}, {}
  local ctx, done = Context(), 0
  for id in pairs(raw.rows) do
    done = done + (Item(id, ctx) or 0)
    if done >= 256 then done = 0 Pause() end
  end
  Publish()
end

-- only these items again (their item info came late); the others keep their rows
function ns.ComputeItems(ids)
  if not (raw and raw.rows and raw.vmap) then return 0 end
  local ctx, n = Context(), 0
  for id in pairs(ids) do
    Item(id, ctx)
    n = n + 1
    if n % 64 == 0 then Pause() end -- (14.11.2026: 4747 late items in two runs, the longer one 105 ms in one frame)
  end
  Publish()
  return n
end

-- the lists once more in slices (an option changed); called again while a job runs: once more after it, so the newest
-- state counts
local rerun
function ns.ComputeLater(done)
  if not raw then if done then done() end return end
  if job then rerun = done or rerun or true return end
  StartJob("compute", function() StepTo("again") ns.Compute() end, function()
    if done then done() end
    if rerun then local r = rerun rerun = nil ns.ComputeLater(type(r) == "function" and r or nil) end
  end, function() rerun = nil end, true)
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
local elapsed = 0
local issecret = issecretvalue or function() return false end

local function NewRaw()
  local own = {}
  own[ns.Call(UnitName, "player") or "?"] = true
  -- (Durchsicht 15.11.2026) the other characters of the account on this realm are own offers too: a scan with A kept B's
  -- auctions as the market, the next scan with B left them out, and they counted as sold (Market.Update)
  local realm = "-" .. (ns.Realm and ns.Realm() or "")
  for who in pairs(type(ns.db) == "table" and type(ns.db.report) == "table" and ns.db.report or {}) do
    if type(who) == "string" and #who > #realm and who:sub(-#realm) == realm then own[who:sub(1, -#realm - 1)] = true end
  end
  return { id = {}, cnt = {}, bo = {}, tl = ns.AH and ns.AH.GetReplicateItemTimeLeft and {} or nil, asked = {}, n = 0, key = ns.Prices.StoreKey(), own = own, recomputes = 0 }
end

local function fail(msg)
  driver:SetScript("OnUpdate", nil)
  ns.Fact("scanFail", msg)
  if (S.done or 0) == 0 then SetLastScan(S.prevScan) end
  S.phase, S.msg = "failed", msg
  ns.Print(msg)
  notify()
end

-- (08.11.2026) late item info: the items that arrived are gathered until it has been quiet for 1 s (at most 5 s after the
-- first), then only they are worked out again (ns.ComputeItems; Daniel's /profit diag: 18 full runs of 616 ms before)
local lateFirst, lateLast, lateTimer, arrived = 0, 0, nil, {}
local function LateCheck()
  local now = GetTime()
  if now - lateLast < 1 and now - lateFirst < 5 then ns.After(0.5, LateCheck) return end
  lateTimer = nil
  if not raw or S.phase ~= "done" then arrived = {} return end
  local ids = arrived
  arrived = {}
  local r = raw
  local function note(n, ms, max)
    r.recomputes = r.recomputes + 1
    r.lateItems = (r.lateItems or 0) + n
    r.lateMs = (r.lateMs or 0) + ms
    r.lateMax = math.max(r.lateMax or 0, max)
    ns.Fact("scanLate", ("%d mal nachgerechnet, %d Items, zusammen %d ms (längster Frame %d ms)"):format(r.recomputes, r.lateItems,
      math.floor(r.lateMs + 0.5), math.floor(r.lateMax + 0.5)))
    notify()
  end
  if job then -- something else is being worked out: in one go as before
    local t0 = Now()
    local n = ns.ComputeItems(ids)
    note(n, Now() - t0, Now() - t0)
    return
  end
  -- in slices like the scan itself (the first one at once)
  local n, sum, max, mark = 0, 0, 0, Now()
  local function lap() local t = Now() sum, max, mark = sum + (t - mark), math.max(max, t - mark), t end
  local j
  StartJob("late", function() n = ns.ComputeItems(ids) end, function() note(n, sum, max) end, nil, false)
  j = job
  local resume = coroutine.resume
  -- measure every slice of this job: the runner knows only the scan's steps
  local co = j.co
  j.co = coroutine.create(function()
    while true do
      mark = Now()
      local ok, err = resume(co)
      lap()
      if not ok then error(err, 0) end
      if coroutine.status(co) == "dead" then return end
      coroutine.yield()
    end
  end)
  Slice()
end
local function Late(id)
  arrived[id] = true
  lateLast = GetTime()
  if lateTimer then return end
  lateTimer, lateFirst = true, lateLast
  ns.After(1, LateCheck)
end

local function Finished()
  S.phase = "done"
  local L = ns.lists
  S.msg = (S.passive and "Mitgelesen: " or "") .. ("%d Auktionen gelesen. Unter Händlerpreis %d, zum Entzaubern %d."):format(raw.n, #L.vendor, #L.de)
  ns.Print(S.msg)
  if T then
    T.mem1 = Mem()
    if T.finT0 then T.finS = GetTime() - T.finT0 end
    T.req = raw.requested or 0
  end
  ns.Fact("scan", ("%d Auktionen, %.1f s, %s"):format(raw.n, GetTime() - (S.startT or GetTime()), S.passive and "mitgelesen" or "eigener Scan"))
  ns.Fact("scanTimes", ns.ScanTimes())
  if rerun then rerun = nil ns.ComputeLater(notify)
  elseif raw.lateSeen then for id in pairs(raw.pend) do Late(id) end end -- item info came while the lists were worked out
  notify()
end

local function Finish()
  raw.asked = nil
  raw.t = time()
  StepTo("agg") ns.Aggregate()
  StepTo("save") ns.Prices.SaveScan(raw.key, raw.agg, raw.n, Pause)
  StepTo("market") if ns.Market then ns.Market.Update(raw, Pause) end
  StepTo("compute") ns.Compute()
end

local function readChunk()
  local C = ns.AH
  local start = Now()
  local first = S.done
  repeat
    local stop = math.min(S.total, S.done + 25) -- (Daniel's /profit diag: about 28 µs per auction, 11 ms per frame with 250)
    for i = S.done, stop - 1 do
      local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = pcall(C.GetReplicateItemInfo, i)
      itemID, count = ok and ns.Num(itemID), ok and ns.Num(count)
      if owner ~= nil and issecret(owner) then owner = nil end
      if itemID and count and count > 0 and not (owner and raw.own[owner]) then
        local n = raw.n + 1
        raw.n = n
        raw.id[n], raw.cnt[n], raw.bo[n] = itemID, count, ns.Num(buyout) or 0
        if raw.tl then -- (13.11.2026) the time left band for the market estimate (Market.lua)
          local okT, tl = pcall(C.GetReplicateItemTimeLeft, i)
          raw.tl[n] = okT and tl or -1
        end
        if not raw.asked[itemID] and not (ns.G and ns.G.sell[itemID]) then
          raw.asked[itemID] = true
          -- (14.11.2026) only what the client does not hold yet: every answer goes as an event to all addons (TSM,
          -- Auctionator, bag addons), thousands of them in the seconds of the reading
          if C_Item and C_Item.RequestLoadItemDataByID
            and not (C_Item.IsItemDataCachedByID and ns.Call(C_Item.IsItemDataCachedByID, itemID) == true) then
            raw.requested = (raw.requested or 0) + 1
            ns.Call(C_Item.RequestLoadItemDataByID, itemID)
          end
        end
      end
    end
    S.done = stop
  until S.done >= S.total or S.done - first >= READ_MAX or Now() - start >= Budget()
  Took("read", Now() - start)
end

local drawn = 0
local function onUpdate(_, dt)
  elapsed = elapsed + (tonumber(dt) or 0)
  lastDt = tonumber(dt) or 0
  if S.phase == "finishing" then
    if not job then -- the job ended (done or failed) without telling: nothing more to wait for
      driver:SetScript("OnUpdate", nil)
      if S.phase == "finishing" then fail("Scan abgebrochen (Fehler beim Auswerten, /profit debug zeigt ihn).") end
    else
      if T then T.finFrames = (T.finFrames or 0) + 1 end
      if GetTime() - drawn >= 0.25 then drawn = GetTime() progress() end
    end
    return
  end
  if not S.open then return fail("Auktionshaus geschlossen, Scan abgebrochen.") end
  if InCombat() then S.msg = "Pause: im Kampf." return end
  if S.phase == "waiting" then
    -- (Daniel 06.11.2026, 95000 auctions: "der bricht irgendwann ab") the update event can come late or not at all: from 5 s on
    -- the count is polled too; when it stays the same for SETTLE seconds the reading starts without the event
    if not S.lastUpdate and elapsed >= 5 then
      local n = ns.Num(ns.Call(ns.AH.GetNumReplicateItems)) or 0
      if n > 0 then
        if n ~= S.polled then S.polled, S.polledAt = n, elapsed
        elseif elapsed - (S.polledAt or elapsed) >= SETTLE then S.lastUpdate = elapsed - SETTLE end
      end
    end
    if S.lastUpdate and elapsed - S.lastUpdate >= SETTLE then
      local n = ns.Num(ns.Call(ns.AH.GetNumReplicateItems)) or 0
      if n == 0 then return fail("Das Auktionshaus hat keine Auktionen geschickt (leer oder vom Spiel noch gesperrt). Knopf ist wieder frei.") end
      S.phase, S.total, S.done = "reading", math.floor(n), 0
      if T then T.waitS, T.readT0, T.readFrames = elapsed, GetTime(), 0 end
    elseif elapsed > TIMEOUT then
      return fail("Keine Antwort vom Auktionshaus nach 2 min (das Spiel sperrt den Vollscan wohl noch). Knopf ist wieder frei.")
    else
      S.msg = ("Warte auf das Auktionshaus... %d s"):format(math.floor(elapsed))
    end
  elseif S.phase == "reading" then
    readChunk()
    if T then T.readFrames = (T.readFrames or 0) + 1 end
    S.msg = ("Lese %d / %d"):format(S.done, S.total)
    if S.done >= S.total then
      S.phase, S.msg = "finishing", "Werte aus..."
      if T then T.readS, T.finT0 = GetTime() - (T.readT0 or GetTime()), GetTime() end
      if job then job = nil jobber:SetScript("OnUpdate", nil) end -- an older recompute: the new scan replaces it
      rerun = nil
      StartJob("scan", Finish, function()
        driver:SetScript("OnUpdate", nil)
        Finished()
      end, function(err)
        driver:SetScript("OnUpdate", nil)
        fail("Scan abgebrochen (Fehler beim Auswerten: " .. tostring(err) .. ").")
      end)
    end
  end
  if S.phase == "waiting" and T then T.waitFrames = (T.waitFrames or 0) + 1 end
  if GetTime() - drawn >= 0.25 then drawn = GetTime() progress() end
end
local function Guarded(self, dt)
  local ok = ns.Try(onUpdate, self, dt)
  if not ok then fail("Scan abgebrochen (Fehler, /profit debug zeigt ihn).") end
end

local function Begin(passive)
  raw = NewRaw()
  elapsed = 0
  T = { mem0 = Mem() }
  S.startT = GetTime()
  S.phase, S.done, S.total, S.msg, S.passive = "waiting", 0, 0, passive and "Lese den Vollscan eines anderen Addons mit..." or "Frage alle Auktionen ab...", passive
  S.lastUpdate = passive and 0 or nil
  S.polled, S.polledAt = nil, nil
  S.prevScan = LastScan()
  SetLastScan(time())
  driver:SetScript("OnUpdate", Guarded)
end

function ns.StartScan()
  if S.phase == "waiting" or S.phase == "reading" or S.phase == "finishing" then return false end
  if not S.open then ns.Print("Erst das Auktionshaus öffnen.") return false end
  if ns.ProfScanBusy and ns.ProfScanBusy() then ns.Print("Der Berufsscan läuft noch.") return false end
  if InCombat() then ns.Print("Nicht im Kampf.") return false end
  if not (ns.AH and ns.AH.ReplicateItems) then ns.Print("Dieser Client hat keinen Vollscan.") return false end
  local wait = ns.ScanWait()
  if wait > 0 then ns.Print(("Vollscan erst in %d min wieder erlaubt."):format(math.ceil(wait / 60))) return false end
  Begin(false)
  if not pcall(ns.AH.ReplicateItems) then
    driver:SetScript("OnUpdate", nil)
    SetLastScan(S.prevScan)
    S.phase = "failed"
    return fail("Das Spiel hat den Scan abgelehnt.")
  end
  notify()
  return true
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
  if S.phase == "waiting" or S.phase == "reading" then S.lastUpdate = elapsed return end
  if S.phase == "finishing" or not S.open or ns.ScanWait() > 0 then return end
  Begin(true)
  notify()
end)

-- late item data (new Forever items: vendor price, quality and level for the disenchant rule): only for items the lists
-- still wait for, gathered (Late)
ns.On("GET_ITEM_INFO_RECEIVED", function(_, id)
  if raw and S.phase == "finishing" then raw.lateSeen = true return end
  if not (raw and raw.pend) or S.phase ~= "done" then return end
  local n = ns.Num(id)
  if n and raw.pend[n] then Late(n) end
end)
ns.On("AUCTION_HOUSE_SHOW", function() S.open = true notify() end)
ns.On("AUCTION_HOUSE_CLOSED", function() S.open = false notify() end)
ns.On("PLAYER_LOGIN", function()
  local f = AuctionHouseFrame
  if f and f.IsShown and f:IsShown() then S.open = true ns.Fire("AUCTION_HOUSE_SHOW") end
end)

-- after /reload: the saved lists of this auction house (at most 2 hours old)
ns.OnInit(function()
  local k = ns.db.lastLists
  if type(k) == "table" and k.t and time() - k.t < 2 * 3600 and k.key == ns.Prices.StoreKey() then
    ns.lists = { vendor = k.vendor or {}, de = k.de or {}, pending = 0, key = k.key, t = k.t, n = k.n, restored = true }
    for _, l in pairs({ ns.lists.vendor, ns.lists.de }) do for _, e in ipairs(l) do e.gone = nil end end
  end
end)

-- a row of the vendor list worked out with another vendor price than the game's (saved lists of an older version, a
-- price that changed): it does not count
function ns.VendorStale(e)
  local sell, src = ns.Prices.Sell(e.id)
  if src == "refused" then return true end -- (22.11.2026) the vendor does not buy it (Prices.lua P.Refused)
  if src ~= "game" then return false end
  local unit = e.unit or ((e.count or 0) > 0 and e.ret and e.ret / e.count)
  return unit ~= nil and math.abs(unit - sell) > 0.5
end

function ns._SetRaw(r) raw = r end -- (tests)
