local _, ns = ...

---------------------------------------------------------------------------
-- Auswertung (Daniel 06.11.2026: "ich hätte gerne ne auswertung für profitdon", "mit ner möglichkeit anzugeben, dass ich z.b.
-- x silber startkapital hatte", "ich will nur die auswertung dazu haben ... startkapital gebe ich einmal an", Wahl: je Char).
--   * Startkapital je Char, einmal eingetragen (vorausgefüllt mit dem Gold jetzt), mit Zeitpunkt
--   * Gewinn seit Start = Gold + Ware in den Taschen + eingestellte Ware - Startkapital, je Tag im Schnitt
--   * Goldverlauf: ein Punkt je Stunde (Gold und Ware), höchstens 60 Tage
--   * Gewinn je Methode, gebucht von dem, was Profitdon selbst tut:
--       flip  (AH unter Händlerpreis): Kauf im AH aus, Verkauf beim Händler ein
--       craft (Herstellen): Mats im AH und beim Händler gekauft aus, Hergestelltes beim Händler oder im AH verkauft ein
--             (Daniel 08.11.2026: AH-Verkäufe eigener Produkte auch hier, auch rückwirkend, R.MoveCraftSales)
--       de    (Entzaubern): Grüne und Blaue im AH gekauft aus, Entzauberungsmats im AH verkauft ein
--       ah    (andere AH-Verkäufe): Hergestelltes und anderes im AH verkauft ein
--       fee   (Einstellgebühr): beim Einstellen aus, kommt mit dem Verkauf zurück (in der Rechnung)
--       grey  (Graues beim Händler) ein
--     AH-Verkäufe aus den Rechnungen am Briefkasten (GetInboxInvoiceInfo "seller"), jede einmal (Ablaufzeit der Mail)
-- Saved (ProfitdonDB.report[char]): start = { c, t }, gold, goods, posted = { { id, qty, unit, t, h } },
--   curve = { { hour, gold, goods } }, book = { [day] = { [method] = { out, in, n } } }; ProfitdonDB.invSeen[sig] = expiry
---------------------------------------------------------------------------
local R = {}
ns.Report = R

R.METHODS = {
  { "flip", "AH unter Händlerpreis" }, { "craft", "Herstellen" }, { "de", "Entzaubern" },
  { "ah", "Andere AH-Verkäufe" }, { "grey", "Graues beim Händler" }, { "fee", "Einstellgebühr netto" },
  { "favor", "Merchant's-Favor-Kisten" },
  -- (Daniel 08.11.2026: every way in and out, Ledger.lua) purchases by hand that fit no method, and what is no trading
  { "ahbuy", "AH-Käufe sonstige" }, { "loot", "Beute und Quests" }, { "upkeep", "Reparatur, Lehrer, Reisen" },
  { "mail", "Post und Handel" },
}
local NAME = {}
for _, m in ipairs(R.METHODS) do NAME[m[1]] = m[2] end
R.NAME = NAME

-- (Durchsicht der Rechnungen 15.11.2026) the day begins at midnight of the PC's clock, not of UTC ("Heute" began at 1 or
-- 2 at night). The offset is read once a session; without date() it is 0.
local tz
local function TZ()
  if tz then return tz end
  tz = 0
  local d, t = rawget(_G, "date"), rawget(_G, "time")
  if type(d) == "function" and type(t) == "function" then
    local ok, off = pcall(function()
      local now = t()
      local u, l = d("!*t", now), d("*t", now)
      l.isdst = false
      return t(l) - t(u)
    end)
    if ok and type(off) == "number" and math.abs(off) <= 14 * 3600 then tz = off end
  end
  return tz
end
R.TZ = TZ
function R.Day(t) return math.floor(((t or time()) + TZ()) / 86400) end

local function Store(who)
  ns.db.report = type(ns.db.report) == "table" and ns.db.report or {}
  who = who or ns.Me()
  local r = ns.db.report[who]
  if type(r) ~= "table" then r = {} ns.db.report[who] = r end
  r.book = type(r.book) == "table" and r.book or {}
  r.curve = type(r.curve) == "table" and r.curve or {}
  r.posted = type(r.posted) == "table" and r.posted or {}
  return r
end
R.Store = Store

---------------------------------------------------------------------------
-- Startkapital
---------------------------------------------------------------------------
function R.Start(who) local s = Store(who).start return s and s.c, s and s.t end
function R.SetStart(c, who)
  c = ns.Num(c)
  if not c then return false end
  local r = Store(who)
  r.start = { c = math.floor(c), t = time() }
  R.Snapshot(true)
  return true
end

---------------------------------------------------------------------------
-- Booking
---------------------------------------------------------------------------
function R.Book(method, out, inn, n)
  if not ns.db or not NAME[method] then return end
  local r = Store()
  local d = R.Day()
  r.book[d] = r.book[d] or {}
  local b = r.book[d][method] or { 0, 0, 0 }
  b[1], b[2], b[3] = b[1] + (out or 0), b[2] + (inn or 0), b[3] + (n or 1)
  r.book[d][method] = b
  -- days older than 400 go
  for day in pairs(r.book) do if d - day > 400 then r.book[day] = nil end end
end

-- per method over the last "days" days (nil: all, 0: today): { method = { out, in, n, net } }, and the sums
function R.Methods(days, who)
  local r, today = Store(who), R.Day()
  local out, tot = {}, { 0, 0, 0 }
  for day, list in pairs(r.book) do
    if not days or today - day < math.max(1, days) and (days > 0 or day == today) then
      for m, b in pairs(list) do
        local e = out[m] or { 0, 0, 0 }
        e[1], e[2], e[3] = e[1] + b[1], e[2] + b[2], e[3] + b[3]
        out[m] = e
        tot[1], tot[2] = tot[1] + b[1], tot[2] + b[2]
      end
    end
  end
  return out, tot
end

-- the item an AH sale belongs to: a disenchant mat counts for "de", everything else for "ah"
local MATS
local function IsMat(id)
  if not MATS then
    MATS = {}
    for _, list in pairs(ns.DE and ns.DE.groups or {}) do for k = 1, #list, 4 do MATS[list[k]] = true end end
  end
  return MATS[id]
end
R.IsMat = IsMat

---------------------------------------------------------------------------
-- What the character owns: gold, goods in the bags, goods posted
---------------------------------------------------------------------------
-- value of the bags: mats and what the AH sells at the cheapest offer after the cut where it beats the vendor, else the vendor
-- (Daniel 06.11.2026: "Ware 122g", "so viel dann doch nicht") what the bags are worth, carefully: bound items not at all
-- (no sale), grey only at the vendor, the AH only with an own scan row (the lower of cheapest and median, after the cut) or
-- TSM's market value, never TSM's cheapest listing (one absurd listing of a rare item made gold out of nothing)
function R.ItemValue(id)
  local P = ns.Prices
  local sell = P.Sell(id) or 0
  local _, _, q = ns.ItemInfo(id)
  if q == 0 then return sell, "vendor" end
  local r = P.Row(nil, id)
  local ah
  if r then ah = math.min(P.Low(id) or r[1], (r[2] or 0) > 0 and r[2] or r[1])
  else ah = P.TSM(id, "DBMarket") end
  ah = ah and ns.Deals.AfterCut(ah, P.Cut()) or 0
  if ah > sell then return ah, r and "ah" or "tsm" end
  return sell, "vendor"
end
function R.BagItems()
  local out = {}
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id and not info.isBound then out[id] = (out[id] or 0) + (ns.Num(info.stackCount) or 1) end
    end
  end
  return out
end
-- (Daniel 06.11.2026: "nicht realisierter Gewinn ... noch vorsichtiger", chosen "Nur Händlerpreis") the profit counts goods
-- only at the vendor price (sure); ah = true gives the careful AH value, shown as a hint only
function R.BagValue(list, ah)
  local sum = 0
  for id, n in pairs(R.BagItems()) do
    local v, src
    if ah then v, src = R.ItemValue(id) else v, src = ns.Prices.Sell(id) or 0, "vendor" end
    sum = sum + v * n
    if list and v > 0 then list[#list + 1] = { id = id, n = n, value = v * n, src = src } end
  end
  if list then table.sort(list, function(a, b) return a.value > b.value end) end
  return sum
end

-- goods posted and not sold yet (expired after their run time plus a day for the mail): at the vendor price, ah = true
-- what they bring after the cut
function R.PostedValue(who, ah)
  local r, now, sum, keep = Store(who), time(), 0, {}
  local cut = ns.Prices.Cut()
  for _, p in ipairs(r.posted) do
    if (p[2] or 0) > 0 and now - (p[4] or 0) < ((p[5] or 24) + 24) * 3600 then
      keep[#keep + 1] = p
      if ah then sum = sum + ns.Deals.AfterCut((p[3] or 0) * p[2], cut)
      else sum = sum + (ns.Prices.Sell(p[1]) or 0) * p[2] end
    end
  end
  r.posted = keep
  return sum
end

function R.Posted(id, qty, unit, hours)
  local r = Store()
  r.posted[#r.posted + 1] = { id, qty, unit, time(), hours or 24 }
  if ns.Market then ns.Market.OwnPosted(id, qty) end
end
-- (Durchsicht 15.11.2026) a posting cancelled or run out stayed in "Eingestellt" for its run time plus a day, beside the
-- same goods back in the bags (posted three times: counted three times). The game's own list of the character's
-- auctions settles it whenever the game loads it (the Auctions tab, after a cancel): the active ones are what is posted.
-- list: { { id, qty, unit (nil: kept from the posting), hours left } }
function R.SyncOwned(list)
  local r, now = Store(), time()
  local unit = {}
  for _, p in ipairs(r.posted) do if p[1] and p[3] then unit[p[1]] = p[3] end end
  local new = {}
  for _, o in ipairs(list or {}) do
    if o[1] and (o[2] or 0) > 0 then new[#new + 1] = { o[1], o[2], unit[o[1]] or o[3] or 0, now, math.max(1, math.ceil(o[4] or 24)) } end
  end
  r.posted = new
end
ns.On("OWNED_AUCTIONS_UPDATED", function()
  local A = ns.AH
  if not (ns.db and type(A) == "table" and A.GetNumOwnedAuctions and A.GetOwnedAuctionInfo) then return end
  if A.HasFullOwnedAuctionResults and ns.Call(A.HasFullOwnedAuctionResults) == false then return end
  local n = ns.Num(ns.Call(A.GetNumOwnedAuctions)) or 0
  local list = {}
  for i = 1, n do
    local o = ns.Call(A.GetOwnedAuctionInfo, i)
    local id = type(o) == "table" and type(o.itemKey) == "table" and ns.Num(o.itemKey.itemID)
    -- status 0: active (1: sold, the gold waits in the mail)
    if id and (ns.Num(o.status) or 0) == 0 then
      list[#list + 1] = { id, ns.Num(o.quantity) or 1, ns.Num(o.buyoutAmount), (ns.Num(o.timeLeftSeconds) or 86400) / 3600 }
    end
  end
  R.SyncOwned(list)
  ns.Fact("ownedSync", ("%d aktive eigene Auktionen übernommen"):format(#list))
end)
local function SoldPosted(id, qty)
  local r = Store()
  for _, p in ipairs(r.posted) do
    if p[1] == id and qty > 0 then
      local take = math.min(qty, p[2])
      p[2], qty = p[2] - take, qty - take
    end
  end
end

-- one point an hour (the last one of the hour wins), gold and goods (bags and posted)
local lastSnap = 0
function R.Snapshot(force)
  if not ns.db then return end
  if not force and GetTime() - lastSnap < 60 then return end
  lastSnap = GetTime()
  local r = Store()
  local gold = ns.Num(ns.Call(GetMoney))
  if not gold then return end
  local goods = R.BagValue() + R.PostedValue()
  r.gold, r.goods, r.t = gold, goods, time()
  -- (Durchsicht 15.11.2026) the first sum seen today, kept: "Heute" counted against the point of the running hour, which
  -- is written over all the time (18:10 100g, 18:55 130g: "Heute" about 0)
  local day = R.Day()
  if type(r.day0) ~= "table" or r.day0[1] ~= day then r.day0 = { day, gold + goods } end
  local hour = math.floor(time() / 3600)
  local last = r.curve[#r.curve]
  if last and last[1] == hour then last[2], last[3] = gold, goods
  else r.curve[#r.curve + 1] = { hour, gold, goods } end
  while #r.curve > 60 * 24 do table.remove(r.curve, 1) end
end

-- the numbers of a character: start, gold, goods, profit, days since the start, profit a day
function R.Summary(who)
  local r = Store(who)
  local me = who == nil or who == ns.Me()
  local gold = me and ns.Num(ns.Call(GetMoney)) or r.gold or 0
  local goods = me and (R.BagValue() + R.PostedValue(who)) or r.goods or 0
  local s = r.start
  local out = { gold = gold, goods = goods, total = gold + goods, start = s and s.c, since = s and s.t }
  if s then
    out.profit = out.total - s.c
    out.days = math.max(1 / 24, (time() - s.t) / 86400)
    out.perDay = math.floor(out.profit / math.max(1, out.days) + 0.5)
  end
  -- today: against the first point of today (or the start, when it is younger)
  local today = (R.Day() * 86400 - TZ()) / 3600 -- the hour today began
  if type(r.day0) == "table" and r.day0[1] == R.Day() then out.dayBase = r.day0[2]
  else for _, c in ipairs(r.curve) do if c[1] >= today then out.dayBase = c[2] + c[3] break end end end
  if s and s.t >= today * 3600 then out.dayBase = s.c end
  out.today = out.dayBase and (out.total - out.dayBase) or nil
  return out
end

-- every character of this realm with a start
function R.Chars()
  local out, realm = {}, "-" .. ns.Realm()
  for who, r in pairs(ns.db.report or {}) do
    if type(r) == "table" and who:sub(-#realm) == realm then
      local s = R.Summary(who)
      s.who, s.name, s.me = who, who:sub(1, -#realm - 1), who == ns.Me()
      out[#out + 1] = s
    end
  end
  table.sort(out, function(a, b) if a.me ~= b.me then return a.me end return a.name < b.name end)
  return out
end

-- the curve for the chart: { { hour, gold, goods } } of the last "hours" hours (nil: all)
function R.Curve(hours, who)
  local r, out = Store(who), {}
  local from = hours and (math.floor(time() / 3600) - hours) or -math.huge
  for _, c in ipairs(r.curve) do if c[1] >= from then out[#out + 1] = c end end
  return out
end

---------------------------------------------------------------------------
-- AH sales from the invoices at the mailbox
---------------------------------------------------------------------------
local byName
local function ItemByName(name)
  if not byName then
    byName = {}
    for id in pairs(ns.SellWanted and ns.SellWanted() or {}) do local n = ns.ItemInfo(id) if n then byName[n] = id end end
  end
  local id = byName[name]
  if not id then
    for bid in pairs(ns.Bags()) do if ns.ItemInfo(bid) == name then id = bid byName[name] = bid break end end
  end
  if not id then
    for mid, n in pairs(ns.DE and ns.DE.names or {}) do if n == name then id = mid end end
  end
  return id
end

-- the items the character's recipes make (and what Profitdon made for the vendor)
local function Products()
  local out = ns.Crafts and ns.Crafts.Products() or {}
  for id, how in pairs(ns.db and ns.db.made or {}) do if how then out[id] = true end end
  return out
end

-- every seller invoice once: its signature and the mail's expiry (days left), kept 31 days
function R.ReadInvoices()
  if not ns.db then return 0 end
  ns.db.invSeen = type(ns.db.invSeen) == "table" and ns.db.invSeen or {}
  local seen, now, booked = ns.db.invSeen, time(), 0
  -- (Durchsicht 15.11.2026) two invoices alike (same item, count, price, sold within 20 minutes: three pieces to one
  -- buyer) counted as one, the second and third were never booked. Each mail of this reading takes one entry of its own.
  local used = {}
  local n = ns.Num(ns.Call(GetInboxNumItems)) or 0
  for i = 1, math.min(n, 50) do
    local _, _, _, _, _, _, daysLeft = ns.Call(GetInboxHeaderInfo, i)
    local kind, name, _, bid, _, deposit, consignment, _, _, _, count = ns.Call(GetInboxInvoiceInfo, i)
    bid = ns.Num(bid)
    if kind == "seller" and bid and type(name) == "string" then
      count = ns.Num(count) or 1
      local exp = now + math.floor((ns.Num(daysLeft) or 30) * 86400)
      local sig = table.concat({ name, count, bid, ns.Num(consignment) or 0 }, "|")
      local list = seen[sig] or {}
      local known = false
      used[sig] = used[sig] or {}
      for k, e in ipairs(list) do
        if not used[sig][k] and math.abs(e - exp) < 20 * 60 then known = true used[sig][k] = true break end
      end
      if not known then used[sig][#list + 1] = true end
      if not known then
        list[#list + 1] = exp
        seen[sig] = list
        local net = bid - (ns.Num(consignment) or 0)
        local id = ItemByName(name)
        R.Book(id and IsMat(id) and "de" or id and Products()[id] and "craft" or "ah", 0, net, count)
        -- (16.11.2026) what each product brought (RecipeLog.lua)
        if id and not IsMat(id) and Products()[id] and ns.RecipeLog then ns.RecipeLog.Sold(id, count, net) end
        ns.db.invMoved = ns.db.invMoved or {}
        ns.db.invMoved[sig .. "|" .. exp] = true -- booked as it should be, nothing to move later
        -- the deposit comes back with the sale
        if (ns.Num(deposit) or 0) > 0 then R.Book("fee", 0, ns.Num(deposit), 0) end
        if id then
          SoldPosted(id, count)
          if ns.Market then ns.Market.OwnSold(id, count, net) end
        end
        booked = booked + 1
      end
    end
  end
  for sig, list in pairs(seen) do
    local keep = {}
    for _, e in ipairs(list) do if e > now - 86400 then keep[#keep + 1] = e end end
    seen[sig] = #keep > 0 and keep or nil
  end
  if booked > 0 then ns.Touch() R.Snapshot(true) if ns.Refresh then ns.Refresh() end end
  return booked
end

-- (Daniel 08.11.2026, "auch rückwirkend") the AH sales of own products booked as "ah" before: every invoice still known
-- (ProfitdonDB.invSeen, 31 days: name, count, gold, cut, mail expiry) whose item a character's recipes make is moved from
-- "ah" to "craft" in that character's book, on the day the mail was sent (expiry - 30 days) or the first later day that
-- has enough "ah"; once per invoice (ProfitdonDB.invMoved). Names the client does not know yet wait for the next try.
function R.MoveCraftSales()
  if not (ns.db and type(ns.db.invSeen) == "table" and type(ns.db.crafts) == "table") then return 0 end
  ns.db.invMoved = type(ns.db.invMoved) == "table" and ns.db.invMoved or {}
  local moved, Cr = 0, ns.Crafts
  -- product name -> characters whose recipes make it
  local makers = {}
  for who, c in pairs(ns.db.crafts) do
    if type(c) == "table" and type(c.known) == "table" then
      for spell in pairs(c.known) do
        local r = Cr and Cr.Recipe(spell)
        local name = r and r.item and r.item > 0 and ns.ItemInfo(r.item)
        if name then makers[name] = makers[name] or {} makers[name][who] = true end
      end
    end
  end
  for sig, list in pairs(ns.db.invSeen) do
    local name, count, bid, cut = sig:match("^(.*)|(%d+)|(%d+)|(%d+)$")
    local who = name and makers[name]
    if who and type(list) == "table" then
      local net, n = tonumber(bid) - tonumber(cut), tonumber(count)
      for _, exp in ipairs(list) do
        local key = sig .. "|" .. exp
        if not ns.db.invMoved[key] then
          local from = R.Day(exp - 30 * 86400)
          local done = false
          for char in pairs(who) do
            local r = ns.db.report and ns.db.report[char]
            local book = type(r) == "table" and r.book
            if type(book) == "table" then
              for d = from, from + 31 do
                local ah = book[d] and book[d].ah
                if ah and ah[2] >= net then
                  ah[2], ah[3] = ah[2] - net, ah[3] - n
                  if ah[1] == 0 and ah[2] == 0 then book[d].ah = nil end
                  local c = book[d].craft or { 0, 0, 0 }
                  c[2], c[3] = c[2] + net, c[3] + n
                  book[d].craft = c
                  done = true
                  break
                end
              end
            end
            if done then break end
          end
          ns.db.invMoved[key] = true
          if done then moved = moved + 1 end
        end
      end
    end
  end
  for key in pairs(ns.db.invMoved) do
    local exp = tonumber(key:match("|(%d+)$"))
    if exp and exp < time() - 86400 then ns.db.invMoved[key] = nil end
  end
  if moved > 0 then ns.Fact("craftMoved", ("%d AH-Verkäufe eigener Produkte nach Herstellen umgebucht"):format(moved)) end
  return moved
end

ns.On("MAIL_INBOX_UPDATE", function() R.ReadInvoices() end)
ns.On("PLAYER_LOGIN", function() ns.After(15, function() R.MoveCraftSales() end) end)
ns.On("PLAYER_MONEY", function() R.Snapshot() end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(5, function() R.Snapshot(true) end) end)
ns.On("BAG_UPDATE_DELAYED", function() ns.WhenIdle("Goldverlauf", R.Snapshot) end)

---------------------------------------------------------------------------
-- The page (book tab "Auswertung"), built from the kit like Golddon's overview
---------------------------------------------------------------------------
local RANGES = { { "24 h", 24 }, { "7 Tage", 24 * 7 }, { "Alles", nil } }
local PERIODS = { { 0, "Heute" }, { 7, "7 Tage" }, { -1, "Gesamt" } }

-- kit: the window's builders (16.11.2026, DonCore Blizz 5: with the Blizzard look its boxes, tiles, lists and money
-- boxes; the line chart stays the kit's), else DonCore's kit
function R.Page(parent, redraw, kit)
  local Kit = kit or LibStub("DonCore-1.0"):Get("Kit", 4)
  local C, S = Kit.C, Kit.SIZE
  local floor, max, min = math.floor, math.max, math.min
  local M = function(c) return c and Kit.Money(c) or "" end
  local MS = function(c) return c and Kit.Money(c, { sign = true }) or "" end
  local p = CreateFrame("Frame", nil, parent)
  p:SetPoint("TOPLEFT", 0, 0)
  p.range, p.period = 2, 7
  p.area = Kit.ScrollArea(p)
  p.area:SetPoint("TOPLEFT", 0, 0)
  local ct = p.area.content
  -- start capital: shown until it is set, or when "Startkapital ändern" is clicked
  p.startBox = Kit.Box(ct, "Startkapital", { onLayout = function(b, bw)
    p.startText:ClearAllPoints() p.startText:SetPoint("TOPLEFT", b.body, "TOPLEFT", S.pad, -8)
    Kit.Fit(p.startText, bw - 2 * S.pad)
    p.coins:ClearAllPoints() p.coins:SetPoint("TOPLEFT", b.body, "TOPLEFT", S.pad, -30) p.coins:Layout(min(220, bw - 160))
    p.startGo:ClearAllPoints() p.startGo:SetPoint("LEFT", p.coins, "RIGHT", S.gap * 2, 0) p.startGo:Layout(130)
  end })
  p.startText = Kit.Text(p.startBox.body, "sub", C.muted)
  p.startText:SetText("Mit wie viel Gold hat dieser Char angefangen? Einmal eintragen, vorausgefüllt ist das Gold jetzt.")
  p.coins = Kit.CoinBox(p.startBox.body, {})
  p.startGo = Kit.Button(p.startBox.body, "Übernehmen", { kind = "primary", small = true, onClick = function()
    if R.SetStart(p.coins:GetValue()) then p.editStart = nil ns.Print("Startkapital: " .. ns.Money(R.Start())) end
    redraw()
  end })
  p.hero = Kit.Hero(ct, { height = 64, column = 170 })
  p.tiles = {}
  for i = 1, 4 do p.tiles[i] = Kit.Tile(ct, { height = 64 }) end
  p.chartBox = Kit.Box(ct, "Goldverlauf", { onLayout = function(b, bw, bh)
    p.rangeSeg:ClearAllPoints() p.rangeSeg:SetPoint("RIGHT", b.head, "RIGHT", -S.unit, 0) p.rangeSeg:Layout(min(200, floor(bw * 0.5)))
    p.chart:ClearAllPoints() p.chart:SetPoint("TOPLEFT", b.body, "TOPLEFT", S.gap, -S.gap) p.chart:Layout(bw - 2 * S.gap, bh - 2 * S.gap)
  end })
  p.chartBox.headRoom = 204
  -- (Runde 2, 11.11.2026, Bild Auswertung: two lines without a name, a peak of 196g flattened the week) Kit 24: the legend
  -- and a peak cut at the top edge, named with its real value
  p.chart = Kit.LineChart(p.chartBox.body, {
    legend = true, clipPeak = 2, clipText = function(v) return "Spitze " .. ns.Money(v) .. " oben abgeschnitten" end,
    formatY = function(v) return Kit.Money(v, { short = true }) end,
    formatX = function(hr) return date((RANGES[p.range][2] or 999) <= 24 and "%H:%M" or "%d.%m.", hr * 3600) end,
    empty = "Noch zu wenig Werte: Profitdon schreibt jede Stunde einen Punkt." })
  local ri = {}
  for i, r in ipairs(RANGES) do ri[i] = { value = i, text = r[1] } end
  p.rangeSeg = Kit.Segmented(p.chartBox.head, { items = ri, get = function() return p.range end, set = function(v) p.range = v redraw() end })
  p.methBox = Kit.Box(ct, "Gewinn je Methode", { onLayout = function(b, bw)
    p.periodSeg:ClearAllPoints() p.periodSeg:SetPoint("RIGHT", b.head, "RIGHT", -S.unit, 0) p.periodSeg:Layout(min(200, floor(bw * 0.5)))
    p.bars:ClearAllPoints() p.bars:SetPoint("TOPLEFT", b.body, "TOPLEFT", S.pad, -4) p.bars:Layout(bw - 2 * S.pad)
  end })
  p.methBox.headRoom = 204
  local pi = {}
  for i, x in ipairs(PERIODS) do pi[i] = { value = x[1], text = x[2] } end
  p.periodSeg = Kit.Segmented(p.methBox.head, { items = pi, get = function() return p.period end, set = function(v) p.period = v redraw() end })
  p.bars = Kit.BarList(p.methBox.body, { rowH = 22 })
  for _, s in ipairs({ p.rangeSeg, p.periodSeg }) do
    s:SetHeight(22)
    for _, b in ipairs(s.fields or {}) do b:SetHeight(22) end
  end
  p.chars = Kit.List(ct, {})
  p.change = Kit.Button(ct, "Startkapital ändern", { small = true, confirm = true, onClick = function()
    p.editStart = true redraw() end })

  function p:Fill()
    local sum = R.Summary()
    self.showStart = (sum.start == nil) or self.editStart
    if self.showStart then self.coins:SetValue(sum.start or sum.gold) end
    local name = ns.Call(UnitName, "player") or "?"
    if sum.start then
      self.hero:SetData({ kicker = ("%s: Gewinn seit %s, Startkapital %s"):format(name, date("%d.%m. %H:%M", sum.since), ns.Money(sum.start)),
        title = MS(sum.profit), plainCase = true, value = MS(sum.perDay), label = "je Tag im Schnitt",
        valueColor = (sum.profit or 0) < 0 and C.red or nil })
    else
      self.hero:SetData({ kicker = name .. ": noch kein Startkapital", title = M(sum.total), plainCase = true, value = "", label = "Gold und Ware jetzt" })
    end
    self.hero._tipFn = function()
      return "Gewinn seit Start", { { "Gold", ns.Money(sum.gold) }, { "Ware in den Taschen und eingestellt", ns.Money(sum.goods) },
        { "Startkapital", sum.start and ns.Money(sum.start) or "-" }, "Ware zählt nur mit dem Händlerpreis (noch nicht verkauft)." }
    end
    local posted = R.PostedValue()
    self.tiles[1]:SetData("Gold", M(sum.gold), "im Beutel dieses Chars")
    local bagAH, postAH = R.BagValue(nil, true), R.PostedValue(nil, true)
    self.tiles[2]:SetData("Ware", M(sum.goods - posted), bagAH > sum.goods - posted and ("Händlerpreis, im AH etwa " .. M(bagAH)) or "in den Taschen, Händlerpreis")
    self.tiles[3]:SetData("Eingestellt", M(posted), postAH > posted and ("Händlerpreis, im AH nach Gebühr " .. M(postAH)) or "im AH, Händlerpreis")
    self.tiles[4]:SetData("Heute", sum.today and MS(sum.today) or "-", "Gold und Ware seit dem ersten Wert heute")
    local pts = R.Curve(RANGES[self.range][2])
    local wealth, gold = {}, {}
    for _, c in ipairs(pts) do wealth[#wealth + 1] = { c[1], c[2] + c[3] } gold[#gold + 1] = { c[1], c[2] } end
    self.chart:SetSeries({ { points = wealth, color = C.goldBright, label = "Gold und Ware" }, { points = gold, color = C.blue, label = "Gold" } })
    self.rangeSeg:Update(self.range)
    local days = self.period == -1 and nil or self.period
    local meth = R.Methods(days)
    local entries = {}
    for _, m in ipairs(R.METHODS) do
      local e = meth[m[1]]
      if e then
        local net = e[2] - e[1]
        entries[#entries + 1] = { key = m[1], text = m[2], value = math.abs(net), color = net < 0 and C.red or C.gold,
          right = Kit.Money(net, { sign = true, short = true }),
          tooltip = { m[2], { { "Ausgaben", ns.Money(e[1]) }, { "Einnahmen", ns.Money(e[2]) }, { "Gewinn", ns.Money(net) },
            { "ROI", e[1] > 0 and (ns.Deals.ROI(net, e[1]) .. " %") or "-" } } } }
      end
    end
    if #entries == 0 then entries[1] = { key = "none", text = "Noch nichts gebucht", value = 0, right = "" } end
    self.bars:SetEntries(entries)
    self.periodSeg:Update(self.period)
    local rows = { { kind = "group", text = "Alle Chars dieses Realms" } }
    for _, c in ipairs(R.Chars()) do
      rows[#rows + 1] = { kind = "note", color = c.me and C.title or C.body,
        text = ("%s: Start %s, jetzt %s, %s"):format(c.name, c.start and ns.Money(c.start) or "-", ns.Money(c.total),
          c.profit and ("Gewinn " .. ns.Money(c.profit)) or "ohne Startkapital") }
    end
    -- (Daniel 16.11.2026: "was das tasty omelett nach einkauf gebracht hat") per product in the period chosen above
    rows[#rows + 1] = { kind = "group", text = "Je Produkt (" .. ((self.period == 0 and "Heute") or (self.period == -1 and "Gesamt") or "7 Tage") .. ")" }
    local RL = ns.RecipeLog
    local list = RL and RL.Rows(days) or {}
    for i = 1, math.min(#list, 25) do
      local e = list[i]
      rows[#rows + 1] = { kind = "note", color = e.sold > 0 and e.profit < 0 and C.red or C.body, text = RL.Text(e) }
    end
    if #list == 0 then rows[#rows + 1] = { kind = "note", color = C.muted, text = "Noch nichts mitgeschrieben (zählt ab jetzt: Mats-Käufe, Herstellungen, Verkäufe)." }
    else rows[#rows + 1] = { kind = "note", color = C.muted, text = "Mats zählen mit dem Preis, zu dem sie gekauft wurden; Gefarmtes und alter Bestand kosten nichts." } end
    self.chars:SetItems(rows)
    self.charsH = 0
    for _, it in ipairs(rows) do self.charsH = self.charsH + self.chars:ItemHeight(it) end
  end

  function p:Layout(w, h)
    self:SetSize(w, h)
    self.area:Resize(w, h)
    local cw = w - 2 * S.pad - 6
    local x, y = S.pad, S.pad
    local function put(f, fx, fy, fw, fh)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", ct, "TOPLEFT", fx, -fy)
      if fh then f:SetHeight(fh) end
      if f.Layout then f:Layout(fw, fh) else f:SetWidth(fw) end
    end
    if self.showStart then put(self.startBox, x, y, cw, 90) self.startBox:Show() y = y + 90 + S.gap else self.startBox:Hide() end
    put(self.hero, x, y, cw) y = y + 64 + S.gap
    local per = cw >= 760 and 4 or 2
    local tw = floor((cw - (per - 1) * S.gap) / per)
    for i, t in ipairs(self.tiles) do
      local r, c = floor((i - 1) / per), (i - 1) % per
      put(t, x + c * (tw + S.gap), y + r * (64 + S.gap), tw)
    end
    y = y + math.ceil(#self.tiles / per) * (64 + S.gap)
    local methH = S.sub + 2 + max(1, #(self.bars.entries or {})) * 22 + S.gap
    if cw >= 760 then
      local lw = floor((cw - S.gap) * 0.58)
      local hh = max(200, methH)
      put(self.chartBox, x, y, lw, hh)
      put(self.methBox, x + lw + S.gap, y, cw - lw - S.gap, methH)
      y = y + hh + S.gap
    else
      put(self.chartBox, x, y, cw, 200) y = y + 200 + S.gap
      put(self.methBox, x, y, cw, methH) y = y + methH + S.gap
    end
    self.chars:ClearAllPoints()
    self.chars:SetPoint("TOPLEFT", ct, "TOPLEFT", x, -y)
    self.chars:Resize(cw, max(S.sub, self.charsH or S.sub))
    y = y + (self.charsH or S.sub) + S.gap
    if R.Start() and not self.showStart then
      put(self.change, x, y, 160) self.change:Show() y = y + S.buttonSmall + S.gap
    else self.change:Hide() end
    self.area:SetContentHeight(y + S.pad)
  end
  return p
end

-- /profit start <Betrag>: "1g 6s", "50s" or copper
function ns.ParseStart(text)
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
  return Kit.ParseMoney and Kit.ParseMoney(text) or tonumber(text)
end
