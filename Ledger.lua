local _, ns = ...

---------------------------------------------------------------------------
-- (Daniel 08.11.2026: "alle möglichen wege der ein und ausgabe müssen berücksichtigt werden"; chosen: purchases by hand
-- sorted by item, everything outside trading on lines of its own) every change of the character's gold is booked once,
-- so the methods together are the real change of the gold. A change is sorted by what is open at that moment:
--   merchant  sales (bags minus, gold plus by the vendor price): flips first, products of the own recipes or made for the
--             vendor = craft, grey = grey, anything else = loot; bought back = booked off; purchases: what Profitdon's
--             "Mats kaufen" announced, else by item (mats or products of the own recipes = craft, else upkeep);
--             gold down without new items = upkeep (repair)
--   AH        what Profitdon announced (L.Expect: its purchases, its deposits); a deposit by hand (an auction was just
--             created) = fee; a purchase by hand = the item searched last: mats or products of the own recipes = craft,
--             green or blue gear with a disenchant group = de, worth more at the vendor = flip (counted as bought for it),
--             else ahbuy; gold up at the AH = ahbuy back
--   mail      money taken from a seller invoice was booked when the invoice was read (Report.ReadInvoices): nothing more;
--             other money from the auction house = ahbuy; money from players = mail; postage, money sent, COD = mail
--   trade     mail ("Post und Handel")
--   nothing   gold up = loot ("Beute und Quests"), gold down = upkeep ("Reparatur, Lehrer, Reisen")
-- A window counts until 2 s after it closed (the gold can come a moment later). /profit diag "ledger": booked against the
-- real change since login.
---------------------------------------------------------------------------
local L = {}
ns.Ledger = L
local GRACE, WAIT = 2, 0.3

local gold, booked0, gold0
local openAt, closedAt = {}, {}
local function Open(k) return openAt[k] or (closedAt[k] and GetTime() - closedAt[k] <= GRACE) end
local function Gold() return ns.Num(ns.Call(GetMoney)) or 0 end
local function Book(m, out, inn, n)
  if ns.Report and m then ns.Report.Book(m, out, inn, n) end
end

---------------------------------------------------------------------------
-- What Profitdon itself does: announced before the gold moves, used up by the next matching change
---------------------------------------------------------------------------
local expect = {}
-- amount < 0: gold goes out (a purchase, a deposit), > 0 comes in
function L.Expect(method, amount, n)
  expect[#expect + 1] = { m = method, a = amount, n = n or 1, t = GetTime() }
end
-- (Durchsicht 15.11.2026) the purchase failed: its announcement goes, else the next gold going out within 30 s was booked
-- under its method
function L.Unexpect(method, amount)
  for k, e in ipairs(expect) do
    if e.m == method and e.a == amount then table.remove(expect, k) return true end
  end
  return false
end
-- books the announced part of a change; returns what is left
local function UseExpected(delta)
  local now = GetTime()
  local keep = {}
  for _, e in ipairs(expect) do
    if now - e.t > 30 then -- the purchase did not happen
    elseif delta ~= 0 and (e.a < 0) == (delta < 0) and math.abs(e.a) <= math.abs(delta) + 1 then
      local a = math.abs(e.a) > math.abs(delta) and delta or e.a
      if a < 0 then Book(e.m, -a, 0, e.n) else Book(e.m, 0, a, e.n) end
      delta = delta - a
    else keep[#keep + 1] = e end
  end
  expect = keep
  return delta
end

---------------------------------------------------------------------------
-- Items: what the own recipes need and make
---------------------------------------------------------------------------
local function Recipes()
  local mats, products = {}, {}
  local Cr = ns.Crafts
  local c = ns.db and ns.db.crafts and ns.db.crafts[ns.Me()]
  if Cr and type(c) == "table" and type(c.known) == "table" then
    for spell in pairs(c.known) do
      local r = Cr.Recipe(spell)
      if r then
        if r.item and r.item > 0 then products[r.item] = true end
        for _, g in ipairs(r.reag or {}) do mats[g[1]] = true end
      end
    end
  end
  for id, how in pairs(ns.db and ns.db.made or {}) do if how then products[id] = true end end
  return mats, products
end

local function AddFlip(id, qty, cost)
  ns.db.flips = ns.db.flips or {}
  local f = ns.db.flips[id] or { q = 0, c = 0 }
  f.q, f.c, f.t = f.q + qty, f.c + cost, time()
  ns.db.flips[id] = f
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local function Counts()
  local out = {}
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id then
        local e = out[id]
        if not e then e = { n = 0, q = info.quality } out[id] = e end
        e.n = e.n + (ns.Num(info.stackCount) or 1)
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Merchant
---------------------------------------------------------------------------
local shop -- { bags, sold = { [id] = n } } while the merchant is open

local function MerchantSale(id, n, sell, quality, sign, products)
  local f = ns.db.flips and ns.db.flips[id]
  local nf = 0
  if sign > 0 and f and (f.q or 0) > 0 then
    nf = math.min(n, f.q)
    f.q = f.q - nf
    if f.q <= 0 then ns.db.flips[id] = nil end
    Book("flip", 0, nf * sell, nf)
  end
  local rest = n - nf
  if rest <= 0 then return end
  local m = products[id] and "craft" or quality == 0 and "grey" or "loot"
  if sign > 0 then Book(m, 0, rest * sell, rest) else Book(m, 0, -rest * sell, -rest) end
  -- (16.11.2026) what each product brought (RecipeLog.lua)
  if m == "craft" and ns.RecipeLog then ns.RecipeLog.Sold(id, sign * rest, sign * rest * sell) end
end

-- returns false when the gold for what left the bags has not come yet
local function MerchantSettle(delta)
  local now = Counts()
  local gone, new = {}, {}
  for id, e in pairs(shop.bags) do
    local d = e.n - (now[id] and now[id].n or 0)
    if d > 0 then gone[#gone + 1] = { id = id, n = d, q = e.q } end
  end
  if #gone > 0 and delta == 0 then return false end -- the gold for it has not come yet (or it was used up: forgotten with the next change)
  for id, e in pairs(now) do
    local d = e.n - (shop.bags[id] and shop.bags[id].n or 0)
    if d > 0 then new[#new + 1] = { id = id, n = d, q = e.q } end
  end
  table.sort(gone, function(a, b) return a.id < b.id end)
  table.sort(new, function(a, b) return a.id < b.id end)
  local mats, products = Recipes()
  local rest = delta
  -- sales
  local left = math.max(0, delta)
  for _, g in ipairs(gone) do
    local sell = ns.Prices.Sell(g.id)
    if sell and sell > 0 and sell * g.n <= left then
      left = left - sell * g.n
      rest = rest - sell * g.n
      shop.sold[g.id] = (shop.sold[g.id] or 0) + g.n
      MerchantSale(g.id, g.n, sell, g.q, 1, products)
    end
  end
  -- bought back, then purchases
  for _, b in ipairs(new) do
    local back = math.min(b.n, shop.sold[b.id] or 0)
    local sell = ns.Prices.Sell(b.id)
    if back > 0 and sell and rest < 0 then
      shop.sold[b.id] = shop.sold[b.id] - back
      b.n = b.n - back
      rest = rest + back * sell
      MerchantSale(b.id, back, sell, b.q, -1, products)
    end
  end
  if rest < 0 then rest = UseExpected(rest) end
  if rest < 0 then
    local buying = {}
    for _, b in ipairs(new) do if b.n > 0 then buying[#buying + 1] = b end end
    if #buying > 0 then
      -- split by what this vendor asks (learned at the merchant), the rest of the gold on the last item
      local spent = -rest
      for k, b in ipairs(buying) do
        local unit = ns.Prices.VendorUnit(b.id)
        local cost = k == #buying and spent or math.min(spent, (unit or 0) * b.n)
        spent = spent - cost
        Book((mats[b.id] or products[b.id]) and "craft" or "upkeep", cost, 0, b.n)
        -- bought by hand at the vendor (Profitdon's own purchases are announced and never come here)
        if (mats[b.id] or products[b.id]) and ns.RecipeLog then ns.RecipeLog.Bought(b.id, b.n, cost) end
      end
    else
      Book("upkeep", -rest, 0, 1) -- repair
    end
  elseif rest > 0 then
    Book("loot", 0, rest, 1)
  end
  shop.bags = now
  return true
end

---------------------------------------------------------------------------
-- Auction house: the item looked at last, an auction just created
---------------------------------------------------------------------------
local lastItem, lastUnit, lastQty, createdAt
-- a purchase in the AH sorted by its item (by hand, and since 20.11.2026 Profitdon's page Kaufen, AHPage.lua): mats or
-- products of the own recipes = craft, green or blue gear with a disenchant group = de, worth more at the vendor = flip,
-- else ahbuy. HandMethod only names it; HandEffects writes what the purchase was for once it went through.
function L.HandMethod(id, qty, cost)
  local mats, products = Recipes()
  local sell = ns.Prices.Sell(id)
  local g = ns.DE and ns.DE.Group(id)
  local _, _, quality = ns.ItemInfo(id)
  if mats[id] or products[id] then return "craft" end
  if g and quality and quality >= 2 then return "de" end
  if sell and sell * qty > cost then return "flip" end
  return "ahbuy"
end
function L.HandEffects(m, id, qty, cost)
  if m == "de" then
    ns.db.deBuys = ns.db.deBuys or {}
    ns.db.deBuys[id] = (ns.db.deBuys[id] or 0) + qty
  elseif m == "flip" then AddFlip(id, qty, cost)
  elseif m == "craft" and ns.RecipeLog then ns.RecipeLog.Bought(id, qty, cost) end -- bought by hand in the AH
end
local function AHSettle(delta)
  local all = delta
  delta = UseExpected(delta)
  -- the deposit was announced and is booked: the posting is settled (a purchase by hand within 5 s was booked as a fee)
  if delta ~= all then createdAt = nil end
  if delta == 0 then return end
  if delta > 0 then Book("ahbuy", 0, delta, 1) return end
  local cost = -delta
  if createdAt and GetTime() - createdAt <= 5 then createdAt = nil Book("fee", cost, 0, 1) return end
  local id = lastItem
  if not id then Book("ahbuy", cost, 0, 1) return end
  local qty = lastQty or (lastUnit and lastUnit > 0 and math.max(1, math.floor(cost / lastUnit + 0.5))) or 1
  lastQty = nil
  local m = L.HandMethod(id, qty, cost)
  L.HandEffects(m, id, qty, cost)
  Book(m, cost, 0, qty)
end

---------------------------------------------------------------------------
-- Mail: the money in the inbox, seen before it is taken
---------------------------------------------------------------------------
-- (Durchsicht 15.11.2026) the inbox is read again when it changes, and that can come before the gold is settled: the
-- mail just emptied was not in the list any more (an invoice's gold booked a second time as "Post", player gold not at
-- all). What left the list since the last reading is kept for 3 s (gone): those are the mails that gave the gold.
local inbox, gone = {}, {}
local function ReadInbox()
  local list = {}
  local n = ns.Num(ns.Call(GetInboxNumItems)) or 0
  for i = 1, math.min(n, 50) do
    local _, _, sender, _, money, cod = ns.Call(GetInboxHeaderInfo, i)
    local kind = ns.Call(GetInboxInvoiceInfo, i)
    money = ns.Num(money) or 0
    if money > 0 then list[#list + 1] = { money = money, invoice = kind, ah = kind ~= nil or sender == "Auction House" or sender == "Auktionshaus" } end
  end
  local left, t = {}, GetTime()
  for _, e in ipairs(list) do
    local k = e.money .. "|" .. tostring(e.invoice) .. "|" .. tostring(e.ah)
    left[k] = (left[k] or 0) + 1
  end
  for _, e in ipairs(inbox) do
    local k = e.money .. "|" .. tostring(e.invoice) .. "|" .. tostring(e.ah)
    if (left[k] or 0) > 0 then left[k] = left[k] - 1 else e.t = t gone[#gone + 1] = e end
  end
  inbox = list
end
local function MailSettle(delta)
  if delta < 0 then Book("mail", -delta, 0, 1) return end
  -- the mails that can have given the gold: those that just left the list first, then the ones still there
  local now, cand, nGone, sumGone = GetTime(), {}, 0, 0
  for _, e in ipairs(gone) do if now - (e.t or 0) <= 3 then cand[#cand + 1] = e nGone = nGone + 1 sumGone = sumGone + e.money end end
  gone = {}
  for _, e in ipairs(inbox) do cand[#cand + 1] = e end
  -- which mails gave the money: all that just left when their sum fits, one with exactly this sum, else the auction
  -- house first
  local pick, rest = nil, delta
  if nGone > 0 and sumGone == delta then
    pick = {}
    for k = 1, nGone do pick[k] = k end
  end
  if not pick then for k, e in ipairs(cand) do if e.money == delta then pick = { k } break end end end
  if not pick then
    pick = {}
    for pass = 1, 2 do
      for k, e in ipairs(cand) do
        if rest > 0 and (pass == 1) == (e.invoice == "seller") then pick[#pick + 1] = k rest = rest - e.money end
      end
    end
  end
  rest = delta
  local remove = {}
  for _, k in ipairs(pick) do
    local e = cand[k]
    local a = math.min(e.money, rest)
    rest = rest - a
    remove[e] = true
    if e.invoice == "seller" then -- booked with the invoice
    elseif e.ah then Book("ahbuy", 0, a, 1)
    else Book("mail", 0, a, 1) end
  end
  if rest > 0 then Book("mail", 0, rest, 1) end
  local keep = {}
  for _, e in ipairs(inbox) do if not remove[e] then keep[#keep + 1] = e end end
  inbox = keep
end
L._MailRead, L._MailSettle = function() ReadInbox() end, function(d) MailSettle(d) end -- (tests)

---------------------------------------------------------------------------
-- Settling
---------------------------------------------------------------------------
local function Baseline()
  gold = Gold()
  if gold == 0 then gold = nil return end -- the gold may not be known this early: the first change sets it
  gold0 = gold
  local _, tot = ns.Report and ns.Report.Methods(nil)
  booked0 = tot and (tot[2] - tot[1]) or 0
end

local soon
local function Settle()
  soon = nil
  if not gold then Baseline() return end
  local now = Gold()
  local delta = now - gold
  if Open("merchant") and shop then
    if not MerchantSettle(delta) then return end
  elseif delta == 0 then return
  elseif Open("ah") then AHSettle(delta)
  elseif Open("mail") then MailSettle(delta)
  elseif Open("trade") then Book("mail", delta < 0 and -delta or 0, delta > 0 and delta or 0, 1)
  else
    delta = UseExpected(delta)
    if delta > 0 then Book("loot", 0, delta, 1) elseif delta < 0 then Book("upkeep", -delta, 0, 1) end
  end
  gold = now
  if ns.RefreshSoon then ns.RefreshSoon() elseif ns.Refresh then ns.Refresh() end
end
L.Settle = Settle -- (tests)
function L._Reset() expect, openAt, closedAt, shop, gold = {}, {}, {}, nil, Gold() end -- (tests)
local function SettleSoon()
  if soon then return end
  soon = true
  ns.After(WAIT, function() ns.Try(Settle) end)
end

-- booked against the real change since login (for /profit diag)
function L.Check()
  if not (gold0 and ns.Report) then return nil end
  local _, tot = ns.Report.Methods(nil)
  local booked = (tot[2] - tot[1]) - (booked0 or 0)
  return booked, Gold() - gold0
end


ns.On("PLAYER_LOGIN", function() if not gold then Baseline() end end)
ns.On("PLAYER_ENTERING_WORLD", function() if not gold then Baseline() end end)
ns.On("PLAYER_MONEY", SettleSoon)
ns.On("BAG_UPDATE_DELAYED", function() if shop then SettleSoon() end end)
ns.On("MERCHANT_SHOW", function() openAt.merchant = true shop = { bags = Counts(), sold = {} } end)
ns.On("MERCHANT_CLOSED", function()
  ns.Try(Settle)
  openAt.merchant, closedAt.merchant, shop = nil, GetTime(), nil
end)
ns.On("AUCTION_HOUSE_SHOW", function() openAt.ah = true end)
ns.On("AUCTION_HOUSE_CLOSED", function() openAt.ah, closedAt.ah = nil, GetTime() end)
ns.On("MAIL_SHOW", function() openAt.mail = true ns.Try(ReadInbox) end)
ns.On("MAIL_INBOX_UPDATE", function() if openAt.mail then ns.Try(ReadInbox) end end)
ns.On("MAIL_CLOSED", function() openAt.mail, closedAt.mail = nil, GetTime() end)
ns.On("TRADE_SHOW", function() openAt.trade = true end)
ns.On("TRADE_CLOSED", function() openAt.trade, closedAt.trade = nil, GetTime() end)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, id) lastItem, lastUnit, lastQty = ns.Num(id), nil, nil end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, key) if type(key) == "table" then lastItem, lastUnit, lastQty = ns.Num(key.itemID), nil, nil end end)
ns.On("COMMODITY_PRICE_UPDATED", function(_, unit, total)
  unit, total = ns.Num(unit), ns.Num(total)
  lastUnit = unit
  lastQty = unit and total and unit > 0 and math.floor(total / unit + 0.5) or nil
end)
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function() createdAt = GetTime() end)
