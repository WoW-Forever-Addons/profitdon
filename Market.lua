local _, ns = ...

---------------------------------------------------------------------------
-- (Daniel 13.11.2026, TSM uninstalled: "können die nicht auch Profitdon mitschreiben? Verkaufszahlen und so?"; chosen: vendor
-- prices, own sales, market sales estimated) what the market sells, estimated from two full scans: an offer with "very long"
-- left (12 to 48 h) in one scan cannot have expired by the next scan within 12 h; when it is gone it was bought (or taken
-- back by its seller, which counts too: the estimate is high rather than low). Offers are told apart by item, stack and
-- buyout only (the replicate list has no auction id): a seller who posts the same again hides a sale.
-- Saved per realm and side (ProfitdonDB.mkt[key]): t = time of the snapshot, s = { [id] = "count:buyout*k;..." } (the very
-- long offers of the last scan), d = { [id] = { sold units, offered units, seconds watched, gold of the sold, comparisons } },
-- halved when an item has been watched for more than 14 days, so old weeks fade. n = comparisons made.
-- Read by tools/profitdon/skill_path.py (sold per day, average price, sale rate) instead of TSM's region data.
---------------------------------------------------------------------------
local M = {}
ns.Market = M
M.WINDOW = 12 * 3600
M.MIN_GAP = 10 * 60
M.MAX_KEYS = 200 -- per item in the snapshot (an item with more price steps keeps 200 of them)
M.HALF = 14 * 86400

function M.VeryLong()
  local e = _G.Enum and _G.Enum.AuctionHouseTimeLeftBand
  return e and e.VeryLong or 3
end

-- (Durchsicht der Rechnungen 15.11.2026) how long a "very long" offer runs at least: until then it cannot have run out,
-- so one that is gone was sold. 12 h was taken over from Retail and never measured for Forever (run times 2/8/24 h: with
-- Classic's band, over 8 h, offers ran out between 8 and 12 h and counted as sold). The game names the band itself
-- (C_AuctionHouse.GetTimeLeftBandInfo: least and most seconds); the least is the window, at most the 12 h of before.
local window
function M.Window()
  if window then return window end
  local A = ns.AH
  local f = type(A) == "table" and A.GetTimeLeftBandInfo
  if type(f) ~= "function" then return M.WINDOW end
  local ok, lo, hi = pcall(f, M.VeryLong())
  lo = ok and tonumber(lo) or nil
  if lo and lo >= 3600 then
    window = math.min(M.WINDOW, lo)
    ns.Fact("mktBand", ("sehr lang = %.1f bis %.1f h, Vergleich bis %.1f h Abstand"):format(lo / 3600, (tonumber(hi) or 0) / 3600, window / 3600))
    return window
  end
  return M.WINDOW
end

function M.Store(key)
  ns.db.mkt = type(ns.db.mkt) == "table" and ns.db.mkt or {}
  local s = ns.db.mkt[key]
  if type(s) ~= "table" then s = {} ns.db.mkt[key] = s end
  s.d = type(s.d) == "table" and s.d or {}
  return s
end

local function Key(count, buyout) return count .. ":" .. ns.Prices.Int(buyout) end

-- raw: the scan's rows (Scan.lua: id, cnt, bo, tl, n, key, t); pause: yields inside the scan job
function M.Update(raw, pause)
  pause = pause or function() end
  if not (raw and raw.tl and raw.key and ns.db) then return end
  local s = M.Store(raw.key)
  local now = raw.t or time()
  local vl = M.VeryLong()
  local ids, cnt, bo, tl = raw.id, raw.cnt, raw.bo, raw.tl
  local prev = type(s.s) == "table" and s.s or nil
  local gap = s.t and now - s.t
  local compare = prev and gap and gap >= M.MIN_GAP and gap < M.Window()
  local cur, snap = {}, {}
  for i = 1, raw.n do
    local id, b = ids[i], bo[i]
    if b and b > 0 then
      local k
      if compare and prev[id] then
        k = Key(cnt[i], b)
        local c = cur[id]
        if not c then c = {} cur[id] = c end
        c[k] = (c[k] or 0) + 1
      end
      if tl[i] == vl then
        k = k or Key(cnt[i], b)
        local c = snap[id]
        if not c then c = {} snap[id] = c end
        c[k] = (c[k] or 0) + 1
      end
    end
    if i % 1024 == 0 then pause() end
  end
  local items, soldAll = 0, 0
  if compare then
    for id, str in pairs(prev) do
      local c = cur[id] or {}
      local sold, offered, gold = 0, 0, 0
      for count, buyout, k in tostring(str):gmatch("(%d+):(%d+)%*(%d+)") do
        count, k = tonumber(count), tonumber(k)
        local gone = math.max(0, k - (c[count .. ":" .. buyout] or 0))
        sold = sold + gone * count
        gold = gold + gone * tonumber(buyout)
        offered = offered + k * count
      end
      local d = type(s.d[id]) == "table" and s.d[id] or { 0, 0, 0, 0, 0 }
      d[1], d[2], d[3], d[4], d[5] = (d[1] or 0) + sold, (d[2] or 0) + offered, (d[3] or 0) + gap, (d[4] or 0) + gold, (d[5] or 0) + 1
      if d[3] > M.HALF then for j = 1, 5 do d[j] = d[j] / 2 end end
      s.d[id] = d
      items, soldAll = items + 1, soldAll + sold
      if items % 256 == 0 then pause() end
    end
    s.n = (s.n or 0) + 1
  end
  local out, keep = {}, 0
  for id, c in pairs(snap) do
    local parts = {}
    for k, v in pairs(c) do
      parts[#parts + 1] = k .. "*" .. v
      if #parts >= M.MAX_KEYS then break end
    end
    out[id] = table.concat(parts, ";")
    keep = keep + 1
    if keep % 256 == 0 then pause() end
  end
  s.s, s.t = out, now
  if compare then
    ns.Fact("market", ("Vergleich %d nach %.1f h: %d Items, %d Stück weg"):format(s.n, gap / 3600, items, soldAll))
  else
    ns.Fact("market", gap and ("kein Vergleich, Abstand %.1f h (10 min bis 12 h)"):format(gap / 3600) or "erster Scan gemerkt")
  end
  return compare
end

-- what the market sells of an item, from the comparisons so far: units a day, average price, share of the very long offers
-- that sold within a day; nil without a day of watching
function M.Stats(id, key)
  local s = ns.db and type(ns.db.mkt) == "table" and ns.db.mkt[key or ns.Prices.StoreKey()]
  local d = s and type(s.d) == "table" and s.d[id]
  if type(d) ~= "table" or (d[3] or 0) < 86400 then return nil end
  local perDay = d[1] / (d[3] / 86400)
  local avg = d[1] > 0 and d[4] / d[1] or nil
  local x = d[2] > 0 and d[1] / d[2] or 0
  local rate = 1 - (1 - math.min(1, x)) ^ (86400 / (d[3] / math.max(1, d[5] or 1)))
  return perDay, avg, rate
end

---------------------------------------------------------------------------
-- Demand (Daniel 14.11.2026: "kann man gut im AH verkaufen ... dass man immer einen Teil davon verkauft ... oder nur 10 Stück
-- herstellt"; chosen: label, amount, honest profit, split AH and vendor; careful thresholds). Does an item sell at the AH?
--   numbers: Profitdon's own scan comparisons (M.Stats) when a day is watched, else TSM's region sale data read at run
--     time (DBRegionSoldPerDay = average per auction house and day, DBRegionSaleRate = share of postings that sell,
--     DBRegionSaleAvg; TSM docs "Which value sources can I use"). TSM's sales come from its users only: rather too low.
--   label: "good" from demGoodRate % and demGoodDay tenths a day, "slow" from demSlowRate %, else "poor"; no numbers at
--     all is nil ("unbekannt"), never "does not sell"
--   amount for the AH: demDays days of sales, at most demCap, less what is there already (bags and bank); "poor": 0
--   supply: offers at the AH now divided by the sales a day (days of stock on the market)
---------------------------------------------------------------------------
M.LABEL = { good = "gut", slow = "zäh", poor = "kaum" }
-- what is there already (bags and bank): read once per frame, a list asks for hundreds of items
local ownT, ownAt
local function Have(id)
  local now = GetTime and GetTime() or 0
  if not ownT or ownAt ~= now then ownT, ownAt = ns.Owned and ns.Owned() or {}, now end
  return ownT[id] or 0
end
function M.ForgetOwned() ownT = nil end
-- (Daniel 14.11.2026, block 6) the own sale rate: units sold of units posted through Profitdon (ProfitdonDB.sold), from
-- demOwnMin posted units on; rate, posted, sold, sold a day since the first posting. Postings still running count as not
-- sold yet, sales of what was posted by hand count as sold: capped at 1.
function M.OwnRate(id)
  local e = ns.db and type(ns.db.sold) == "table" and ns.db.sold[id]
  if type(e) ~= "table" or (e[1] or 0) < ns.Opt("demOwnMin") then return nil end
  local days = math.max(1, (time() - (e[4] or time())) / 86400)
  return math.min(1, (e[2] or 0) / e[1]), e[1], e[2] or 0, (e[2] or 0) / days
end
function M.Demand(id, key)
  local P = ns.Prices
  local perDay, avg, rate = M.Stats(id, key)
  local src = perDay and "own" or nil
  if not src then
    perDay, rate = P.TSMNum(id, "DBRegionSoldPerDay"), P.TSMNum(id, "DBRegionSaleRate")
    avg = P.TSM(id, "DBRegionSaleAvg")
    if perDay or rate or avg then src = "tsm" end
  end
  -- own postings tell the rate best: they were posted at Profitdon's price on this auction house
  local orate, oposted, osold, operDay = M.OwnRate(id)
  if not src and orate then src, perDay = "sold", operDay end
  if not src then return nil end
  if orate then rate = orate end
  -- (Durchsicht 15.11.2026) TSM gave only a part (no units a day): the own sales' units a day, not 0 and "kaum"
  if orate and not perDay then perDay = operDay end
  perDay, rate = perDay or 0, math.min(1, rate or 0)
  local _, _, offers = P.AH(id, key)
  offers = offers or P.TSM(id, "DBNumAuctions")
  local d = { perDay = perDay, rate = rate, avg = avg and avg > 0 and avg or nil, src = src, offers = offers,
    supply = perDay > 0 and offers and offers / perDay or nil, ownRate = orate ~= nil, posted = oposted, sold = osold }
  if rate * 100 >= ns.Opt("demGoodRate") and perDay * 10 >= ns.Opt("demGoodDay") then d.label = "good"
  elseif rate * 100 >= ns.Opt("demSlowRate") and perDay > 0 then d.label = "slow"
  else d.label = "poor" end
  if d.label == "poor" then d.want, d.qty, d.have = 0, 0, 0
  else
    d.want = math.max(1, math.min(ns.Opt("demCap"), math.ceil(perDay * ns.Opt("demDays"))))
    d.have = Have(id)
    d.qty = math.max(0, d.want - d.have)
  end
  return d
end

---------------------------------------------------------------------------
-- Own sales (ProfitdonDB.sold[id] = { posted units, sold units, gold after the cut, first time }): posted through Profitdon
-- (Report.Posted), sold from the seller invoices at the mailbox (Report.ReadInvoices, also what was posted by hand)
---------------------------------------------------------------------------
local function Own(id)
  ns.db.sold = type(ns.db.sold) == "table" and ns.db.sold or {}
  local e = ns.db.sold[id]
  if type(e) ~= "table" then e = { 0, 0, 0, time() } ns.db.sold[id] = e end
  return e
end
function M.OwnPosted(id, qty)
  if not (ns.db and id and qty) then return end
  local e = Own(id)
  e[1] = e[1] + qty
end
function M.OwnSold(id, qty, net)
  if not (ns.db and id and qty) then return end
  local e = Own(id)
  e[2], e[3] = e[2] + qty, e[3] + (net or 0)
end

---------------------------------------------------------------------------
-- Vendor prices from the game (ProfitdonDB.vsell[id] = copper): every price Prices.Sell gets from the item info, so the
-- skill plan needs no TSM item cache
---------------------------------------------------------------------------
function M.VendorSeen(id, sell)
  if not (ns.db and id and type(sell) == "number") then return end
  ns.db.vsell = type(ns.db.vsell) == "table" and ns.db.vsell or {}
  if ns.db.vsell[id] ~= sell then ns.db.vsell[id] = sell end
end
