local _, ns = ...

---------------------------------------------------------------------------
-- Buying (from Golddon's Buy.lua, lean): a click on a row searches the item (fresh offers), the buy button (or the key
-- binding "nächster Klick") then takes only what still pays:
--   vendor: under the vendor price; de: one item under its expected mats; mats: a reagent of the shopping list up to the
--   quantity still needed, at most its price limit
--   commodities: StartCommoditiesPurchase, confirmed only when the game's quote is not higher than planned
--   items: one auction per click, PlaceBid(auctionID, buyout)
-- At most "maxSpend" per click, from "confirmAbove" a second click. Bought for the vendor: ProfitdonDB.flips (the merchant
-- button sells it); bought to disenchant: ProfitdonDB.deBuys (the bag button takes it even when the AH pays more).
---------------------------------------------------------------------------
local B = { state = "idle" }
ns.BuyState = B
local D = ns.Deals

local function notify() if ns.Refresh then ns.Refresh() end end

local function Sorts()
  local E = Enum and Enum.AuctionHouseSortOrder
  return { { sortOrder = E and E.Price or 0, reverseSort = false } }
end

-- highest price per unit that still pays
local function MaxUnit(kind, id, entry)
  if kind == "vendor" then local sell = ns.Prices.Sell(id) return sell and (sell - 0.5) end
  if kind == "de" then return entry.unitValue and (entry.unitValue - (ns.Opt("minProfit") or 0)) end
  if kind == "mats" or kind == "crate" or kind == "writ" then return entry.maxUnit end
  -- (Daniel 20.11.2026) the page Kaufen (AHPage.lua): plain buying, the amount typed decides, no price limit
  if kind == "ah" then return math.huge end
end

-- (Daniel 06.11.2026, Edged Bastard Sword at 14s still listed, Strange Dust "Keine Angebote gefunden") the search goes like
-- Blizzard's own: first a browse query by name (every variant of the item with its cheapest price, random suffixes "of the Boar"
-- included, which a plain item key search does not find), then the detail search of the cheapest variant that still pays.
-- Blizzard's search line only gets the name: a second query of its own pushed Profitdon's out (only one runs at a time).
local function Detail(key)
  B.key, B.state, B.msg = key, "searching", "Suche aktuelle Angebote..."
  ns.Call(ns.AH.SendSearchQuery, key, Sorts(), false)
  local asked = B.entry
  ns.After(3, function()
    if B.entry == asked and B.state == "searching" and not B.retried then
      B.retried = true
      ns.Call(ns.AH.SendSearchQuery, key, Sorts(), false)
    end
  end)
end

-- (Durchsicht der Rechnungen 15.11.2026) a purchase the game has not answered yet. The search that follows a purchase
-- (0.6 / 0.8 s) can come before the answer: entry.need is still the old number then, and the same amount stood ready a
-- second time. What is on its way counts as there already (Need), for 10 s (after 8 s the signal says "unclear").
local waiting
local function Pending(id)
  if waiting and waiting.id == id and GetTime() - (waiting.t or 0) < 10 then return waiting.qty or 0 end
  return 0
end
local function Need(entry)
  local n = entry and tonumber(entry.need)
  if not n then return nil end
  return math.max(0, n - Pending(entry.id))
end
ns.BuyNeed = Need -- (tests)
-- (Durchsicht 15.11.2026) a second single-piece purchase sent before the first was answered wrote over `waiting`: the
-- first answer found no record (flips, deBuys and the mailbox count missed it). The older ones wait here by auction.
local waitMore = {}
local function Park()
  if waiting and not waiting.commodity and waiting.auctionID and GetTime() - (waiting.t or 0) < 10 then waitMore[waiting.auctionID] = waiting end
end
local function Failed(w)
  if w and ns.Ledger and ns.Ledger.Unexpect and ns.BuyMethod then ns.Ledger.Unexpect(w.method or ns.BuyMethod(w.kind), -(w.cost or 0)) end
end

function ns.Select(entry, kind, keepWant)
  if not keepWant or B.entry ~= entry then B.want, B.wantAuto, B.postQty, B.postUnit, B.offers = nil, nil, nil, nil, nil end
  -- (Daniel 08.11.2026: "wenn ich dann die mats anklicke, dass direkt die passende anzahl für den kauf vorausgewählt sind") a mat
  -- of the shopping list starts with what is missing as the amount (cheapest offers first, the field can change it)
  -- (Durchsicht 15.11.2026) wantAuto: the amount was put there, not typed; the price limit of the list still holds
  if kind == "mats" and not B.want and entry and (Need(entry) or 0) >= 1 then B.want, B.wantAuto = math.floor(Need(entry)), true end
  -- (Daniel 20.11.2026, page Kaufen) the amount lives on the entry (AHPage.lua) and counts down with every purchase
  -- (what is on its way counts as bought)
  if kind == "ah" and entry then
    local left = math.floor(tonumber(entry.want) or 0) - Pending(entry.id)
    B.want, B.wantAuto = left >= 1 and left or nil, nil
  end
  B.armed, B.entry, B.kind, B.id = nil, entry, kind, entry and entry.id
  B.state, B.plan, B.msg, B.retried = "idle", nil, nil, nil
  B.ladder, B.itemOffers, B.maxQty, B.avail = nil, nil, nil, nil
  if not entry then notify() return end
  if not ns.ScanState.open then B.msg = "Dafür das Auktionshaus öffnen." notify() return end
  -- the page Kaufen picked one variant from its browse list: its detail search at once
  if kind == "ah" and type(entry.itemKey) == "table" then Detail(entry.itemKey) notify() return end
  local name = ns.ItemInfo(entry.id)
  ns.ShowInAH(entry.id)
  if type(name) == "string" and name ~= "" and ns.AH.SendBrowseQuery then
    B.state, B.msg, B.name = "browsing", "Suche aktuelle Angebote...", name
    ns.browseOwner = "buy" -- (20.11.2026) the browse answer is Buy.lua's, not the page Kaufen's (AHPage.lua)
    local query = { searchString = name, sorts = Sorts(), filters = {}, itemClassFilters = {} }
    ns.Call(ns.AH.SendBrowseQuery, query)
    ns.After(3, function()
      if B.entry == entry and B.state == "browsing" and not B.retried then
        B.retried = true
        ns.Call(ns.AH.SendBrowseQuery, query)
      end
    end)
  else
    local key = ns.Call(ns.AH.MakeItemKey, entry.id)
    if not key then B.msg = "Suche nicht möglich." notify() return end
    Detail(key)
  end
  notify()
end

-- the newest price seen in a search, per item (the rows show it until the next scan: the scan said 71c, the search 60c)
ns.fresh = {}
function ns.FreshLow(id)
  local f = ns.fresh[id]
  local st = ns.Prices.Store()
  if f and (not st or f.t >= st.t) then return f.p end
end

-- the game's own auction window shows the item too (Golddon 05.11.2026)
function ns.ShowInAH(id)
  local name = id and ns.ItemInfo(id)
  if type(name) ~= "string" or name == "" then return end
  if ns.AHFrameState and ns.AHFrameState.hidden then return end -- (20.11.2026) kept away (AHPage.lua): nothing to show
  local f = AuctionHouseFrame
  local sb = f and f.SearchBar
  if sb and f.IsShown and f:IsShown() then
    ns.After(0.3, function()
      if not f:IsShown() then return end
      if f.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
        ns.Call(f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.Buy)
      end
      if sb.SearchBox and sb.SearchBox.SetText then sb.SearchBox:SetText(name) end
    end)
  end
end

-- the offer of this row is gone: the row is marked, the next one of the list is searched
local function Gone()
  local e, kind = B.entry, B.kind
  if not e or kind == "mats" or kind == "ah" then return end
  e.gone = true
  local list = ns.VisibleList and ns.VisibleList(kind) or ns.lists[kind] or {}
  local nxt, after = nil, false
  for _, x in ipairs(list) do
    if x == e then after = true elseif after and not x.gone then nxt = x break end
  end
  if not nxt then B.msg = "Weg. Das war die letzte Zeile." return end
  B.msg = "Weg. Suche die nächste Zeile..."
  ns.After(0.5, function()
    if B.entry == e and ns.ScanState.open then ns.Select(nxt, kind) B.lockUntil = GetTime() + 1 end
  end)
end

local function Spend()
  local money = ns.Num(ns.Call(GetMoney))
  local cap = ns.Opt("maxSpend")
  -- (Daniel 20.11.2026, Bild Flask: "10 habe ich eingegeben, aber 2 kann ich nur kaufen") the page Kaufen buys the amount
  -- typed, only the gold limits it (from confirmAbove a second click with the total); the cap stays for the rest
  if B.kind == "ah" then cap = math.huge end
  if money and money < cap then return money, true end
  return cap, false
end
-- (Daniel 24.11.2026, Bild Einkaufsliste: Destiny, "Teurer als der Höchstbetrag je Klick", "kaufen auch ausgeblendet")
-- one piece cannot be split over clicks: what the list asks for (mats, crate, writ) is bought as one piece dearer than
-- the cap too, while the gold pays it (from confirmAbove with the second click). one: the price of the cheapest piece.
local function SpendOne(one)
  local spend, byMoney = Spend()
  if byMoney or not one or one <= spend then return spend, byMoney end
  if not (B.kind == "mats" or B.kind == "crate" or B.kind == "writ") then return spend, byMoney end
  local money = ns.Num(ns.Call(GetMoney)) or 0
  if money < one then return money, true end
  return one, false
end

local function PlanCommodity()
  local id = B.id
  local n = ns.Num(ns.Call(ns.AH.GetNumCommoditySearchResults, id)) or 0
  local res = {}
  -- (Daniel 24.11.2026, Bild Kaufen Raptor Egg: "meine eigenen auktionen fehlen mir irgendwie noch") own[price]: the units
  -- of the player's own auctions at that price, for the price list of the page Kaufen (B.ownOffers)
  local own = {}
  for i = 1, math.min(n, 200) do
    local r = ns.Call(ns.AH.GetCommoditySearchResultInfo, id, i)
    local mine = type(r) == "table" and r.containsOwnerItem and (ns.Num(r.numOwnerItems) or ns.Num(r.quantity) or 0) or 0
    local q = type(r) == "table" and (ns.Num(r.quantity) or 0) - mine
    if q and q > 0 then res[#res + 1] = { unitPrice = ns.Num(r.unitPrice), quantity = q } end
    local p = mine > 0 and ns.Num(r.unitPrice)
    if p then own[p] = (own[p] or 0) + mine end
  end
  B.ownOffers = B.kind == "ah" and next(own) and own or nil
  local maxUnit = MaxUnit(B.kind, id, B.entry)
  if not maxUnit or B.kind == "de" then B.plan, B.msg = nil, "Keine Stapelware." return end
  local spend, byMoney = SpendOne(res[1] and res[1].unitPrice)
  -- (Daniel 20.11.2026, page Kaufen) the offers kept for the price preview, and what the gold (and the cap per click)
  -- buys at most, cheapest first
  if B.kind == "ah" then
    B.ladder = res
    local can, sum, avail = 0, 0, 0
    for _, r in ipairs(res) do
      avail = avail + (r.quantity or 0)
      if r.unitPrice and r.unitPrice > 0 then
        local n = math.min(r.quantity or 0, math.floor((spend - sum) / r.unitPrice))
        if n > 0 then can, sum = can + n, sum + n * r.unitPrice end
      end
    end
    B.maxQty, B.avail = can, avail
    if not B.want then B.plan, B.msg = nil, res[1] and "Menge eintragen." or "Keine Angebote gefunden." return end
  end
  -- (Daniel 06.11.2026: "unten will ich ne anzahl eintragen können und dann soll da stehen für welchen schnitt ich die anzahl
  -- einkaufe") a typed amount: the cheapest offers first up to that amount, no price limit, the average per unit shown
  -- (Durchsicht 15.11.2026) only a typed amount lifts the limit: the amount the list put there (wantAuto) bought every
  -- offer up to the need, also the dear rest far over the price the list counted with
  if B.want and not (B.wantAuto and B.kind == "mats") then
    local qty, total, top = 0, 0, nil
    for _, r in ipairs(res) do
      if not r.unitPrice then break end
      local n = math.min(r.quantity or 0, B.want - qty)
      if total + n * r.unitPrice > spend then n = math.floor((spend - total) / r.unitPrice) end
      if n <= 0 then break end
      qty, total, top = qty + n, total + n * r.unitPrice, r.unitPrice
      if qty >= B.want then break end
    end
    if qty == 0 then B.plan, B.msg = nil, res[1] and (byMoney and "Nicht genug Gold." or "Teurer als der Höchstbetrag je Klick.") or "Keine Angebote gefunden." return end
    local value = B.kind == "vendor" and (ns.Prices.Sell(id) or 0) * qty or nil
    B.plan = { commodity = true, qty = qty, total = total, avg = total / qty, top = top, want = B.want,
      short = qty < B.want and (total + (top or 0) > spend and (byMoney and "Gold" or "cap") or "ah") or nil,
      profit = value and value - total or nil }
    B.msg = nil
    return
  end
  local qtyCap = B.kind == "mats" and Need(B.entry) or nil
  -- (Daniel 06.11.2026) every row of the shopping list searches; what the bags hold already is not bought again
  if B.kind == "mats" and (qtyCap or 0) <= 0 then B.plan, B.msg = nil, ns.MatsThereText(B.entry) return end
  local qty, total = D.CommodityTake(res, maxUnit, spend, qtyCap)
  local value = B.kind == "vendor" and (ns.Prices.Sell(id) or 0) * qty or nil
  if qty > 0 and (B.kind == "mats" or B.kind == "crate" or B.kind == "writ" or D.Worth(value - total, total)) then
    B.plan = { commodity = true, qty = qty, total = total, avg = total / qty, profit = value and value - total or nil }
    B.msg = nil
    -- fewer than needed because the next offer is over the limit: say so, a typed amount buys without the limit
    if B.kind == "mats" and qtyCap and qty < qtyCap then
      local nxt
      local run = 0
      for _, r in ipairs(res) do run = run + (r.quantity or 0) if run > qty then nxt = r.unitPrice break end end
      if nxt and nxt > maxUnit then
        B.plan.limited = maxUnit
        B.msg = ("%d von %d bis %s je Stück, der Rest kostet ab %s. Menge eintippen kauft ohne Grenze."):format(qty, qtyCap, ns.Money(maxUnit), ns.Money(nxt))
      end
    end
  else
    B.plan = nil
    B.msg = B.kind == "mats" and ("Nichts mehr bis " .. ns.Money(maxUnit) .. " je Stück.") or "Nichts mehr unter dem Grenzpreis."
    if res[1] and res[1].unitPrice and res[1].unitPrice <= maxUnit and res[1].unitPrice > spend then
      B.msg = byMoney and "Nicht genug Gold." or "Teurer als der Höchstbetrag je Klick."
    elseif res[1] and res[1].unitPrice and res[1].unitPrice > maxUnit then Gone()
    elseif not res[1] then B.msg = "Keine Angebote gefunden. Zeile nochmal anklicken." end
  end
end

-- (Daniel 21.11.2026: "überall fehlen die werte der ausrüstung wenn es of the ... ist") the link of a variant from its
-- offers, kept per item key (ID and suffix) for the tooltip of the Kaufen row; nil until searched once
ns.keyLinks = ns.keyLinks or {}
local function KeyStr(key)
  return type(key) == "table" and ns.Num(key.itemID) and (ns.Num(key.itemID) .. ":" .. (ns.Num(key.itemSuffix) or 0)) or nil
end
-- (28.11.2026, Daniel with a picture: Kaufen "Adventurer's Bandana of Shadow Protection" showed only 130 Armor before any
-- search) until a search taught the link, a link built from the key: the suffix as Forever's bonus ID, else as field 7;
-- taken only when the game's tooltip of that link has the variant's name (GetItemKeyInfo), so a wrong guess is never shown
local guessed = {}
local function TipName(link)
  local get = C_TooltipInfo and C_TooltipInfo.GetHyperlink
  if type(get) ~= "function" then return nil end
  local ok, data = pcall(get, link)
  local line = ok and type(data) == "table" and type(data.lines) == "table" and data.lines[1]
  return type(line) == "table" and line.leftText or nil
end
local function GuessLink(key, k)
  local g = guessed[k]
  if g ~= nil then return g or nil end
  local id, s = ns.Num(key.itemID), math.abs(ns.Num(key.itemSuffix) or 0)
  if not id or s == 0 then return nil end
  local info = ns.AH and ns.AH.GetItemKeyInfo and ns.Call(ns.AH.GetItemKeyInfo, key)
  local name = type(info) == "table" and info.itemName
  if type(name) ~= "string" or name == "" then return nil end -- not kept: the name comes later
  for _, link in ipairs({ ("item:%d::::::::::::1:%d"):format(id, s), ("item:%d::::::%d"):format(id, s), ("item:%d::::::%d"):format(id, -s) }) do
    local tn = TipName(link)
    if tn == nil then return nil end -- the game does not know it yet: ask again next time
    if tn == name then guessed[k] = link return link end
  end
  guessed[k] = false
  return nil
end
function ns.KeyLink(key)
  local k = KeyStr(key)
  if not k then return nil end
  return ns.keyLinks[k] or GuessLink(key, k)
end

local function PlanItem()
  local n = ns.Num(ns.Call(ns.AH.GetNumItemSearchResults, B.key)) or 0
  local maxUnit = MaxUnit(B.kind, B.id, B.entry)
  -- (24.11.2026) every auction is one piece: the cheapest one the list may buy sets the amount of the click
  local one
  for i = 1, math.min(n, 200) do
    local r = ns.Call(ns.AH.GetItemSearchResultInfo, B.key, i)
    local p = type(r) == "table" and not r.containsOwnerItem and ns.Num(r.buyoutAmount)
    if p and p > 0 and (not one or p < one) then one = p end
  end
  local spend, byMoney = SpendOne(one)
  local best, capped, low
  local ahOffers, ownOffers = {}, {}
  for i = 1, math.min(n, 200) do
    local r = ns.Call(ns.AH.GetItemSearchResultInfo, B.key, i)
    if i == 1 and type(r) == "table" and type(r.itemLink) == "string" and KeyStr(B.key) then ns.keyLinks[KeyStr(B.key)] = r.itemLink end
    local price = type(r) == "table" and not r.containsOwnerItem and ns.Num(r.auctionID) and ns.Num(r.buyoutAmount)
    if price and price > 0 and (not low or price < low) then low = price end
    -- (24.11.2026) the player's own auctions, for the price list of the page Kaufen
    local mine = type(r) == "table" and r.containsOwnerItem and ns.Num(r.buyoutAmount)
    if mine and mine > 0 then ownOffers[mine] = (ownOffers[mine] or 0) + math.max(1, ns.Num(r.quantity) or 1) end
    if price then
      -- (15.11.2026) one auction is one piece at buyoutAmount: r.quantity counts the like offers the game groups into the
      -- row, a click buys one of them
      local q = 1
      local d
      if B.kind == "vendor" then
        local sell = ns.Prices.Sell(B.id)
        d = sell and D.VendorFlip(q, price, sell)
      elseif B.kind == "de" then
        d = q == 1 and D.DEFlip(price, B.entry.unitValue) or nil
      elseif B.kind == "crate" or B.kind == "writ" then
        -- (08.11.2026) a Waylaid Crate: the cheapest offer up to its price limit, the cheaper the better
        d = maxUnit and price / q <= maxUnit and { profit = maxUnit * q - price } or nil
      elseif B.kind == "mats" then
        local left = Need(B.entry) or q
        if left <= 0 then B.msg = ns.MatsThereText(B.entry) end
        d = maxUnit and price / q <= maxUnit and q <= left and { profit = maxUnit * q - price } or nil
      elseif B.kind == "ah" then
        -- (page Kaufen) the cheapest auction, one a click, while the amount is not reached
        d = (B.want or 0) >= 1 and { profit = -price } or nil
        ahOffers[#ahOffers + 1] = price
      end
      if d and price > spend then capped = true end
      if d and price <= spend and (not best or d.profit > best.profit) then
        best = { auctionID = r.auctionID, price = price, qty = q, profit = d.profit }
      end
    end
  end
  if low then ns.fresh[B.id] = { p = low, t = time() } ns.SellDirty() end
  B.plan = best
  B.msg = nil
  if B.kind == "ah" then
    -- (page Kaufen) single auctions: the offers cheapest first; Max = as many as the gold pays one after another
    table.sort(ahOffers)
    local can, sum = 0, 0
    local money = ns.Num(ns.Call(GetMoney)) or 0
    for _, p in ipairs(ahOffers) do
      if p > spend or sum + p > money then break end
      can, sum = can + 1, sum + p
    end
    B.ladder, B.maxQty, B.avail = nil, can, #ahOffers
    B.itemOffers = ahOffers
    B.ownOffers = next(ownOffers) and ownOffers or nil
    if not best then B.msg = n == 0 and "Keine Angebote gefunden." or (B.want or 0) < 1 and "Menge eintragen."
      or (byMoney and "Nicht genug Gold." or "Teurer als der Höchstbetrag je Klick.") end
    return
  end
  if not best then
    B.msg = capped and (byMoney and "Nicht genug Gold." or "Teurer als der Höchstbetrag je Klick.") or "Nichts mehr unter dem Grenzpreis."
    if n == 0 then B.msg = "Keine Angebote gefunden. Zeile nochmal anklicken."
    elseif not capped then Gone() end
  end
end

-- (Auswertung) the method a purchase is booked for; announced to the ledger before the gold moves (Ledger.lua books it
-- when the gold goes out, so a failed purchase books nothing and nothing counts twice)
local function Method(kind) return kind == "vendor" and "flip" or kind == "de" and "de" or (kind == "crate" or kind == "writ") and "favor" or "craft" end
local function Announce(kind, cost, qty)
  if not ns.Ledger then return end
  -- (page Kaufen) plain buying is booked by its item, as a purchase by hand (Ledger.lua L.HandMethod)
  local m = Method(kind)
  if kind == "ah" and ns.Ledger.HandMethod and B.id then m = ns.Ledger.HandMethod(B.id, qty or 1, cost) end
  ns.Ledger.Expect(m, -cost, qty)
  return m
end
ns.BuyMethod = Method

-- nothing left to buy of a mat: where it is (bags, or bought and still in the mailbox)
function ns.MatsThereText(e)
  local way = e and e.id and ns.OnWayCount(e.id) or 0
  if way > 0 then return ("Nichts mehr zu kaufen: %d gekauft, im Briefkasten abholen."):format(way) end
  return "Alles da (in den Taschen)."
end

function ns.RecordBuy(id, qty, cost, kind)
  -- what a purchase was for (the gold itself: Ledger.lua)
  if kind == "vendor" then
    ns.db.flips = ns.db.flips or {}
    local f = ns.db.flips[id] or { q = 0, c = 0 }
    f.q, f.c, f.t = f.q + qty, f.c + cost, time()
    ns.db.flips[id] = f
  elseif kind == "de" then
    ns.db.deBuys = ns.db.deBuys or {}
    ns.db.deBuys[id] = (ns.db.deBuys[id] or 0) + qty
  elseif kind == "mats" then
    if ns.RecipeLog then ns.RecipeLog.Bought(id, qty, cost) end -- (16.11.2026) the mat's price for what it goes into
    if B.entry and B.entry.id == id and B.entry.need then B.entry.need = math.max(0, B.entry.need - qty) end
    -- (Daniel 24.11.2026, gewählt "Nur dieser Einkauf") bought ready instead of made: with the row filled the choice ends
    if B.entry and B.entry.id == id and B.entry.buyReady and (B.entry.need or 0) <= 0 and ns.Crafts then ns.Crafts.SetBuyReady(id, false) end
    -- (Durchsicht Runde 2) the purchase lies in the mailbox: the shopping list counts it as on the way
    ns.OnWayAdd(id, qty)
    -- (Daniel 15.11.2026) bought over the shopping list: the recipe it was for is a job of the Herstellfenster
    local e, Cr = B.entry, ns.Crafts
    if e and e.forSpell and Cr and Cr.JobAdd then
      Cr.JobAdd(e.forSpell, e.forRuns, Cr.sel and Cr.sel.r.spell == e.forSpell and Cr.sel.mode or nil)
    end
  elseif kind == "ah" then
    -- (Daniel 20.11.2026, page Kaufen) sorted like a purchase by hand (flips, deBuys, recipe log), the amount counts down,
    -- the purchase lies in the mailbox (the shopping list counts it as on the way)
    local L = ns.Ledger
    if L and L.HandMethod then L.HandEffects(L.HandMethod(id, qty, cost), id, qty, cost) end
    if B.entry and B.entry.id == id and B.entry.want then B.entry.want = math.max(0, B.entry.want - qty) end
    if ns.OnWayAdd then ns.OnWayAdd(id, qty) end
  end
end

---------------------------------------------------------------------------
-- (Daniel 11.11.2026: "Beim Kaufen über die Einkaufsliste besseres optisches Signal, ob Kauf durchgegangen ist oder
-- nicht") the outcome of the last purchase per item, apart from B.msg (the search that follows a purchase after 0.8 s
-- wrote "Suche aktuelle Angebote..." over "Gekauft"): ns.lastBuy[id] = { state "sent"|"ok"|"fail"|"unclear", qty, cost,
-- t }. The window marks the row and the bar green, red or yellow for SIGNAL_SEC seconds, a sound tells the two apart,
-- a purchase without an answer after 8 s turns "unclear" (bags and gold tell).
---------------------------------------------------------------------------
ns.lastBuy = {}
-- (Daniel 20.11.2026: "eine Bestätigung da unten neben, wenn das gekauft ist, damit das nicht weggeht") what was bought
-- of an item since the AH opened, summed over the clicks; it stays until the AH shuts (the signal above goes after 20 s)
ns.boughtSum = {}
function ns.BoughtText(id, money)
  local s = id and ns.boughtSum[id]
  if not s or s.qty < 1 then return nil end
  return ("Gekauft: %d für %s"):format(s.qty, (money or ns.Money)(s.cost))
end
ns.SIGNAL_SEC = 20
local SOUND = { ok = 120, fail = 847 } -- LOOT_WINDOW_COIN_SOUND, igQuestFailed
local function Signal(id, state, qty, cost)
  if not id then return end
  local e = { state = state, qty = qty, cost = cost, t = GetTime() }
  ns.lastBuy[id] = e
  if state == "ok" then
    local s = ns.boughtSum[id] or { qty = 0, cost = 0 }
    s.qty, s.cost = s.qty + (qty or 1), s.cost + (cost or 0)
    ns.boughtSum[id] = s
  end
  if SOUND[state] then ns.Call(PlaySound, SOUND[state], "Master") end
  local name = ns.ItemInfo(id) or ("Item " .. id)
  if state == "ok" then ns.Print(("|cff4fd16bGekauft:|r %d× %s für %s"):format(qty or 1, name, ns.Money(cost or 0)))
  elseif state == "fail" then ns.Print(("|cffe0524aKauf fehlgeschlagen:|r %d× %s, nichts abgebucht."):format(qty or 1, name))
  elseif state == "sent" then
    ns.After(8, function()
      if ns.lastBuy[id] == e then Signal(id, "unclear", qty, cost) notify() end
    end)
    return
  end
  ns.After(ns.SIGNAL_SEC + 0.5, function() if ns.lastBuy[id] == e then ns.lastBuy[id] = nil notify() end end)
end
-- the signal of an item while it shows: state, text, colour code
function ns.BuySignal(id)
  local e = id and ns.lastBuy[id]
  if not e or GetTime() - e.t > ns.SIGNAL_SEC then return nil end
  local what = ("%d für %s"):format(e.qty or 1, ns.Money(e.cost or 0))
  if e.state == "ok" then return "ok", "Gekauft: " .. what, "ff4fd16b" end
  if e.state == "fail" then return "fail", "Kauf fehlgeschlagen (" .. what .. "), nichts abgebucht", "ffe0524a" end
  if e.state == "unclear" then return "unclear", "Keine Antwort vom AH zu " .. what .. ": Taschen und Gold prüfen", "ffe6b422" end
  return "sent", "Kauf gesendet: " .. what .. " ...", "ffe6b422"
end

function ns.BuyNow()
  local p = B.plan
  if not p or B.state ~= "ready" then return end
  if B.lockUntil and GetTime() < B.lockUntil then return end
  local spend = p.total or p.price or 0
  local since = B.armed and (GetTime() - B.armed)
  if since and since < 0.4 then return end
  -- (Durchsicht 11.11.2026) the second click says what is bought and what for; posting without a live offer (the price
  -- is the old scan's) asks for one too
  if (spend >= ns.Opt("confirmAbove") or p.confirm) and not (since and since < 5) then
    local what = B.entry and B.entry.purpose
    B.armed = GetTime()
    B.msg = p.confirm and (p.confirm .. " Zum Einstellen nochmal klicken.")
      or (("Großer Kauf (%s)%s: zum Bestätigen nochmal klicken."):format(ns.Money(spend), what and (", " .. what) or ""))
    notify()
    return
  end
  B.armed = nil
  if p.post then
    ns.PostNow(p)
    B.plan, B.entry, B.state = nil, nil, "idle"
    ns.After(1, notify)
  elseif p.commodity then
    B.state, B.msg = "quote", "Preis wird bestätigt..."
    ns.Call(ns.AH.StartCommoditiesPurchase, B.id, p.qty)
  else
    B.state = "buying"
    local ok = pcall(ns.AH.PlaceBid, p.auctionID, p.price)
    if ok then
      Park()
      waiting = { id = B.id, qty = p.qty, cost = p.price, kind = B.kind, auctionID = p.auctionID, t = GetTime(), money = ns.Num(ns.Call(GetMoney)) }
      waiting.method = Announce(B.kind, p.price, p.qty)
      B.msg = "Kauf gesendet: " .. ns.Money(p.price)
      Signal(B.id, "sent", p.qty, p.price)
    else B.msg = "Kauf abgelehnt." Signal(B.id, "fail", p.qty, p.price) end
    B.plan = nil
    ns.After(0.6, function() if B.entry then ns.Select(B.entry, B.kind) end end)
  end
  notify()
end

-- the amount typed in the bar: plan again from the offers already found, else search again (Enter)
function ns.SetWant(n, search)
  n = tonumber(n)
  B.want, B.wantAuto = n and n >= 1 and math.floor(n) or nil, nil
  if not B.entry or B.kind == "post" then return end
  if B.kind == "ah" then B.entry.want = B.want or 0 end
  if B.state == "ready" and B.isCommodity then PlanCommodity() notify()
  elseif B.state == "ready" and B.kind == "ah" and B.isCommodity == false then PlanItem() notify()
  elseif search and B.state ~= "searching" and B.state ~= "browsing" and B.state ~= "quote" then ns.Select(B.entry, B.kind, true) end
end

-- (PROFITDON_PLAN.md "Warteschlange Nächster Klick per Tastenkürzel") the key binding: buy or post the planned row, else
-- search the first row of the list on screen; (11.11.2026) one step of "Alle herstellen" per key press, since
-- 15.11.2026 in the Herstellfenster beside the profession window (CraftWin.lua ns.CraftClick)
function ns.NextClick()
  if B.plan and B.state == "ready" then return ns.BuyNow() end
  if B.state == "searching" or B.state == "quote" or B.state == "buying" then return end
  if ns.CraftClick and ns.CraftClick() then return end
  if ns.SelectFirst then ns.SelectFirst() end
end

---------------------------------------------------------------------------
-- (Daniel 09.11.2026) live offers for the shopping list: every commodity search keeps its offers, cheapest first, in
-- ns.liveBook[id] = { t, rows = { { unitPrice, quantity } }, full }; Prices.BuyTotal counts with them for 15 minutes.
-- "Live prüfen" searches the AH mats of the list one after another (only while no buy search runs).
---------------------------------------------------------------------------
ns.liveBook = {}
local function KeepBook(id)
  local n = ns.Num(ns.Call(ns.AH.GetNumCommoditySearchResults, id)) or 0
  local rows = {}
  for i = 1, math.min(n, 1000) do
    local r = ns.Call(ns.AH.GetCommoditySearchResultInfo, id, i)
    local q = type(r) == "table" and (ns.Num(r.quantity) or 0) - (r.containsOwnerItem and (ns.Num(r.numOwnerItems) or ns.Num(r.quantity) or 0) or 0)
    local p = type(r) == "table" and ns.Num(r.unitPrice)
    if q and q > 0 and p then rows[#rows + 1] = { unitPrice = p, quantity = q } end
  end
  local full = ns.AH.HasFullCommoditySearchResults and ns.Call(ns.AH.HasFullCommoditySearchResults, id)
  ns.liveBook[id] = { t = time(), rows = rows, full = full and true or false }
  if rows[1] then ns.fresh[id] = { p = rows[1].unitPrice, t = time() } ns.SellDirty() end
  ns.liveVer = (ns.liveVer or 0) + 1
  if ns.ShopLists then ns.ShopLists.Alarm(id, rows[1] and rows[1].unitPrice or nil) end -- (24.11.2026) price alarms
end
-- (Daniel 24.11.2026, Bild Einkaufsliste: Destiny 418g in der Liste, 349g im AH; Taran Icebreaker 79g, "bei einer suche gar
-- nicht im ah ... trotz live prüfen") the live check kept only commodity answers: a piece of equipment answers with
-- ITEM_SEARCH_RESULTS_UPDATED, was dropped after 4 s and the list stayed at the price of the last scan. Its offers are
-- kept the same way (one auction a row, cheapest first) and become the item's row in the scan store as in the
-- Berufsscan, so the price holds after the 15 minutes; a full answer without an offer takes the old row away.
local function KeepItemBook(id, key)
  local n = ns.Num(ns.Call(ns.AH.GetNumItemSearchResults, key)) or 0
  local rows, offers = {}, {}
  for i = 1, math.min(n, 500) do
    local r = ns.Call(ns.AH.GetItemSearchResultInfo, key, i)
    local p = type(r) == "table" and not r.containsOwnerItem and ns.Num(r.buyoutAmount)
    if p and p > 0 then
      local q = math.max(1, ns.Num(r.quantity) or 1)
      rows[#rows + 1] = { unitPrice = p, quantity = q }
      offers[#offers + 1] = { p, q }
    end
  end
  table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
  local full = not ns.AH.HasFullItemSearchResults or ns.Call(ns.AH.HasFullItemSearchResults, key) ~= false
  ns.liveBook[id] = { t = time(), rows = rows, full = full }
  if rows[1] then
    ns.Prices.SaveItem(nil, id, ns.AggOffers(offers, full))
    ns.fresh[id] = { p = rows[1].unitPrice, t = time() }
    ns.SellDirty()
  elseif full then
    ns.Prices.SaveItem(nil, id, nil)
    ns.fresh[id] = nil
    ns.SellDirty()
  end
  ns.liveVer = (ns.liveVer or 0) + 1
  if ns.ShopLists then ns.ShopLists.Alarm(id, rows[1] and rows[1].unitPrice or nil) end
end

local L = { queue = {}, busy = nil }
ns.LiveState = L
local function LiveNext()
  L.busy = nil
  if not ns.ScanState.open then L.queue = {} notify() return end
  local id = table.remove(L.queue, 1)
  if not id then L.done = time() notify() return end
  if B.state == "searching" or B.state == "browsing" or B.state == "quote" or B.state == "buying" then
    table.insert(L.queue, 1, id)
    ns.After(1, LiveNext)
    return
  end
  local key = ns.Call(ns.AH.MakeItemKey, id)
  if not key then return LiveNext() end
  L.busy = id
  ns.Call(ns.AH.SendSearchQuery, key, Sorts(), false)
  ns.After(4, function() if L.busy == id then LiveNext() end end)
  notify()
end
-- ids: the AH mats of the list
function ns.LiveCheck(ids)
  if not ns.ScanState.open then return false end
  if ns.ProfScanBusy and ns.ProfScanBusy() then ns.Print("Der Berufsscan läuft noch.") return false end
  L.queue, L.done, L.total = {}, nil, 0
  for _, id in ipairs(ids or {}) do L.queue[#L.queue + 1] = id L.total = L.total + 1 end
  LiveNext()
  return true
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, id)
  id = ns.Num(id)
  if id then KeepBook(id) end
  if L.busy and L.busy == id then L.busy = "wait" ns.After(0.3, LiveNext) notify() end
  if (B.state ~= "searching" and B.state ~= "ready") or ns.Num(id) ~= B.id then return end
  B.isCommodity, B.state = true, "ready"
  if B.kind == "post" then ns.PlanPost(true) else PlanCommodity() end
  notify()
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, key)
  -- (24.11.2026) the answer of the live check for a piece of equipment
  local lid = type(key) == "table" and ns.Num(key.itemID)
  if lid and L.busy == lid then
    KeepItemBook(lid, key)
    L.busy = "wait"
    ns.After(0.3, LiveNext)
    notify()
  end
  if B.state ~= "searching" and B.state ~= "ready" then return end
  if type(key) == "table" and ns.Num(key.itemID) ~= B.id then return end
  B.isCommodity, B.state = false, "ready"
  if B.kind == "post" then ns.PlanPost(false) else PlanItem() end
  notify()
end)

---------------------------------------------------------------------------
-- (Daniel 16.11.2026, Bilder Skillen und Berufe: "eine scan option, dass man nur den beruf scannt") the scan of one
-- profession: every item of its recipes (results, mats, recipe items) searched one after another, at any time (the full
-- scan is locked for 15 minutes). Each answer becomes the item's row in the scan store (ns.AggOffers, Prices.SaveItem),
-- so the prices stay as after a full scan. An item without an answer after two tries keeps its old row.
---------------------------------------------------------------------------
local PS = { queue = {} }
ns.ProfScanState = PS
function ns.ProfScanItems(prof)
  local Cr, seen, out = ns.Crafts, {}, {}
  local function add(id) id = tonumber(id) if id and id > 0 and not seen[id] then seen[id] = true out[#out + 1] = id end end
  local function take(spell)
    local r = Cr.Recipe(spell)
    if not (r and r.prof == prof) then return end
    add(r.item)
    for _, g in ipairs(r.reag or {}) do add(g[1]) end
    local d = ns.LEARN and ns.LEARN[spell]
    if type(d) == "table" then add(d[3]) end
  end
  for spell in pairs(ns.CRAFTS or {}) do take(spell) end
  for spell in pairs(ns.db and type(ns.db.craftExtra) == "table" and ns.db.craftExtra or {}) do take(spell) end
  table.sort(out)
  return out
end

local function PSStatus() if ns.RefreshStatus then ns.RefreshStatus() end end
local function PSEnd(msg, ok)
  PS.busy, PS.queue, PS.running = nil, {}, nil
  PS.msg, PS.done = msg, time()
  if ok then PS.okAt = time() end
  ns.liveVer = (ns.liveVer or 0) + 1
  if msg then ns.Print(msg) end
  notify()
end
local PSNext
local function PSAsk(id, try)
  local key = ns.Call(ns.AH.MakeItemKey, id)
  if not key then PS.miss = PS.miss + 1 return PSNext() end
  PS.busy, PS.try = id, try
  ns.Call(ns.AH.SendSearchQuery, key, Sorts(), false)
  local run = PS.run
  ns.After(4, function()
    if PS.run ~= run or PS.busy ~= id or PS.try ~= try then return end
    if try == 1 then PSAsk(id, 2) else PS.miss = PS.miss + 1 PSNext() end
  end)
end
PSNext = function()
  PS.busy = nil
  if not PS.running then return end
  if not ns.ScanState.open then
    return PSEnd(("Berufsscan abgebrochen (Auktionshaus zu): %d von %d gelesen."):format(PS.total - #PS.queue, PS.total))
  end
  local id = PS.queue[1]
  if not id then
    return PSEnd(("Berufsscan %s: %d Gegenstände in %d s gelesen%s."):format(PS.label or "", PS.total - PS.miss, math.floor(GetTime() - PS.t0 + 0.5),
      (PS.miss > 0 and (", %d ohne Antwort (alter Preis bleibt)"):format(PS.miss) or "")
        .. ((PS.skipped or 0) > 0 and (", %d nicht gesucht (im letzten Vollscan nicht im AH)"):format(PS.skipped) or "")), true)
  end
  -- a buy search or the live check runs, or the game takes no search right now: a moment later
  local L = ns.LiveState
  local wait = B.state == "searching" or B.state == "browsing" or B.state == "quote" or B.state == "buying" or (L and L.busy)
  local ready = ns.AH.IsThrottledMessageSystemReady
  if not wait and ready and ns.Call(ready) == false then wait = true end
  if wait then
    PS.busy = "wait"
    local run = PS.run
    ns.After(0.3, function() if PS.run == run and PS.busy == "wait" then PSNext() end end)
    return
  end
  table.remove(PS.queue, 1)
  PSStatus()
  PSAsk(id, 1)
end
function ns.ProfScanBusy() return PS.running and true or false end
function ns.ProfScanText()
  if PS.running then return ("Berufsscan %s: %d von %d..."):format(PS.label or "", PS.total - #PS.queue, PS.total) end
end
function ns.ProfScanStop()
  if PS.running then PSEnd(("Berufsscan gestoppt: %d von %d gelesen."):format(PS.total - #PS.queue, PS.total)) end
end
function ns.ProfScan(prof)
  if PS.running then return false end
  if not ns.ScanState.open then ns.Print("Dafür das Auktionshaus öffnen.") return false end
  if ns.ScanBusy and ns.ScanBusy() then ns.Print("Der Vollscan läuft noch.") return false end
  local ids = ns.ProfScanItems(prof)
  if #ids == 0 then ns.Print("Keine Rezeptdaten für diesen Beruf.") return false end
  -- (Daniel 16.11.2026: "Berufescann dauert ja ewig"; 412 searches for Engineering, 245 of the items on offer in his last
  -- scan; chosen "Nur was im AH stand") only what the last full scan saw on offer; without a full scan everything
  local st = ns.Prices.Store()
  PS.skipped = 0
  if st and not st.part and type(st.i) == "table" then
    local keep = {}
    for _, id in ipairs(ids) do if st.i[id] then keep[#keep + 1] = id end end
    PS.skipped = #ids - #keep
    ids = keep
    if #ids == 0 then ns.Print("Im letzten Vollscan stand nichts von diesem Beruf im AH.") return false end
  end
  PS.run = (PS.run or 0) + 1
  PS.queue, PS.total, PS.miss, PS.t0, PS.running = ids, #ids, 0, GetTime(), true
  PS.label, PS.msg, PS.done = ns.Crafts.ProfName(prof), nil, nil
  PSNext()
  return true
end
-- the answer of the search that runs: its offers become the item's row
local function PSTake(id, offers, full)
  if #offers > 0 then
    local v = ns.AggOffers(offers, full)
    ns.Prices.SaveItem(nil, id, v)
    if v then ns.fresh[id] = { p = v[1], t = time() } ns.SellDirty() end
  elseif full then
    ns.Prices.SaveItem(nil, id, nil)
    ns.fresh[id] = nil
  end
  PS.busy = "wait"
  local run = PS.run
  ns.After(0.1, function() if PS.run == run and PS.busy == "wait" then PSNext() end end)
end
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, id)
  id = ns.Num(id)
  if not (PS.running and id and PS.busy == id) then return end
  local b = ns.liveBook[id] -- kept just before by KeepBook
  local offers = {}
  for _, o in ipairs(b and b.rows or {}) do offers[#offers + 1] = { o.unitPrice, o.quantity } end
  PSTake(id, offers, not b or b.full)
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, key)
  local id = type(key) == "table" and ns.Num(key.itemID)
  if not (PS.running and id and PS.busy == id) then return end
  local n = ns.Num(ns.Call(ns.AH.GetNumItemSearchResults, key)) or 0
  local offers = {}
  for i = 1, math.min(n, 500) do
    local r = ns.Call(ns.AH.GetItemSearchResultInfo, key, i)
    local price = type(r) == "table" and not r.containsOwnerItem and ns.Num(r.buyoutAmount)
    if price and price > 0 then offers[#offers + 1] = { price, math.max(1, ns.Num(r.quantity) or 1) } end
  end
  local full = ns.AH.HasFullItemSearchResults and ns.Call(ns.AH.HasFullItemSearchResults, key)
  PSTake(id, offers, full ~= false)
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
  if PS.running then PSEnd(("Berufsscan abgebrochen (Auktionshaus zu): %d von %d gelesen."):format(PS.total - #PS.queue, PS.total)) end
end)

ns.On("COMMODITY_PRICE_UPDATED", function(_, _, total)
  if B.state ~= "quote" or not B.plan then return end
  total = ns.Num(total)
  if total and total <= B.plan.total then
    ns.Call(ns.AH.ConfirmCommoditiesPurchase, B.id, B.plan.qty)
    waiting = { id = B.id, qty = B.plan.qty, cost = total, kind = B.kind, commodity = true, t = GetTime(), money = ns.Num(ns.Call(GetMoney)) }
    waiting.method = Announce(B.kind, total, B.plan.qty)
    B.msg = ("Kauf gesendet: %d für %s"):format(B.plan.qty, ns.Money(total))
    Signal(B.id, "sent", B.plan.qty, total)
    B.plan, B.state = nil, "idle"
    ns.After(0.8, function() if B.entry then ns.Select(B.entry, B.kind) end end)
  else
    ns.Call(ns.AH.CancelCommoditiesPurchase)
    B.state, B.msg = "idle", "Preis gestiegen (" .. ns.Money(total or 0) .. "), neu suchen."
    Signal(B.id, "fail", B.plan.qty, B.plan.total)
    ns.After(0.5, function() if B.entry then ns.Select(B.entry, B.kind) end end)
  end
  notify()
end)
ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
  if B.state ~= "quote" then return end
  if B.plan then Signal(B.id, "fail", B.plan.qty, B.plan.total) end
  B.state, B.msg, B.plan = "idle", "Angebot weg.", nil
  notify()
end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, auctionID)
  local older = ns.Num(auctionID) and waitMore[ns.Num(auctionID)]
  if older then
    waitMore[ns.Num(auctionID)] = nil
    ns.RecordBuy(older.id, older.qty, older.cost, older.kind)
    Signal(older.id, "ok", older.qty, older.cost)
    notify()
    return
  end
  if waiting and not waiting.commodity and (ns.Num(auctionID) == nil or ns.Num(auctionID) == waiting.auctionID) then
    ns.RecordBuy(waiting.id, waiting.qty, waiting.cost, waiting.kind)
    Signal(waiting.id, "ok", waiting.qty, waiting.cost)
    B.msg, waiting = "Gekauft: " .. ns.Money(waiting.cost), nil
    notify()
  end
end)
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
  if waiting and waiting.commodity then
    ns.RecordBuy(waiting.id, waiting.qty, waiting.cost, waiting.kind)
    Signal(waiting.id, "ok", waiting.qty, waiting.cost)
    B.msg, waiting = ("Gekauft: %d für %s"):format(waiting.qty, ns.Money(waiting.cost)), nil
    notify()
  end
end)
ns.On("COMMODITY_PURCHASE_FAILED", function()
  if waiting and waiting.commodity then Failed(waiting) Signal(waiting.id, "fail", waiting.qty, waiting.cost) waiting, B.msg = nil, "Kauf fehlgeschlagen." notify() end
end)
-- (Daniel 16.11.2026, Bild: "Kauf fehlgeschlagen: 1x Bright Sphere, nichts abgebucht", darunter "You won an auction for
-- Bright Sphere": "ich habs aber gekauft") an AH error while a purchase waits is not its answer: the new search sent 0.6 s
-- after the click can raise one too, and the purchase still went through. The error only marks it; 3 s later it counts as
-- failed unless the purchase was answered meanwhile or the gold went down by its price (then it was bought).
ns.BUY_ERR_SEC = 3
local function Settled(w)
  local now = ns.Num(ns.Call(GetMoney))
  if w.money and now and w.money - now >= (w.cost or 0) - 1 then
    ns.RecordBuy(w.id, w.qty, w.cost, w.kind)
    Signal(w.id, "ok", w.qty, w.cost)
    B.msg = "Gekauft: " .. ns.Money(w.cost or 0)
  else
    Failed(w)
    Signal(w.id, "fail", w.qty, w.cost)
    B.msg = "Kauf fehlgeschlagen."
  end
  notify()
end
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(_, err)
  local w = waiting
  if not w then return end
  ns.Fact("ahError", tostring(err) .. " beim Warten auf einen Kauf")
  if w.errAt then return end
  w.errAt = GetTime()
  ns.After(ns.BUY_ERR_SEC, function()
    if waiting ~= w then return end -- answered meanwhile
    waiting = nil
    Settled(w)
  end)
end)
ns.On("AUCTION_HOUSE_CLOSED", function() B.state, B.plan, B.entry, waiting = "idle", nil, nil, nil waitMore = {} ns.boughtSum = {} end)

-- the browse answer: the variants of the chosen item (same item ID), each with its cheapest price
local function OnBrowse()
  if B.state ~= "browsing" or not B.entry then return end
  local list = ns.Call(ns.AH.GetBrowseResults)
  if type(list) ~= "table" then return end
  local keys = {}
  for _, r in ipairs(list) do
    local k = type(r) == "table" and r.itemKey
    if type(k) == "table" and ns.Num(k.itemID) == B.id then keys[#keys + 1] = { key = k, min = ns.Num(r.minPrice) or 0, qty = ns.Num(r.totalQuantity) } end
  end
  table.sort(keys, function(a, b) return a.min < b.min end)
  -- (Durchsicht 15.11.2026) the browse row's minPrice is not kept as the fresh price any more: it can be a bid without a
  -- buyout, one's own offer, or another variant of the ID. The detail search writes it (KeepBook, PlanItem, PlanPost).
  if B.kind == "post" then
    -- selling: the detail search of the cheapest variant tells the cheapest offer of others
    local e = B.entry
    if e.gear then
      -- (07.11.2026) gear: only the variant with the same suffix; none of it: the scan's median of all variants (the cheapest
      -- variant may be a worse suffix)
      -- (09.11.2026) by name first: Forever's links carry the variant as a bonus ID, the key's itemSuffix is another number
      local same, own = nil, ns.LinkName(e.link)
      for _, k in ipairs(keys) do
        local info = own and ns.Call(ns.AH.GetItemKeyInfo, k.key)
        if type(info) == "table" and info.itemName == own then same = k break end
      end
      if not same and (e.suffix or 0) > 0 then
        for _, k in ipairs(keys) do if math.abs(ns.Num(k.key.itemSuffix) or 0) == e.suffix then same = k break end end
      end
      if not same and #keys > 0 then
        local seen = {}
        for i = 1, math.min(#keys, 4) do
          local info = ns.Call(ns.AH.GetItemKeyInfo, keys[i].key)
          seen[i] = tostring(ns.Num(keys[i].key.itemSuffix)) .. "=" .. tostring(type(info) == "table" and info.itemName)
        end
        ns.Fact("postVariant", tostring(own) .. " / " .. tostring(e.suffix) .. " | " .. table.concat(seen, ", "))
      end
      if same then Detail(same.key)
      else
        local _, med = ns.Prices.AH(e.id)
        if med then e.unit = med end
        B.state = "ready"
        ns.PlanPost(nil)
      end
    elseif keys[1] then Detail(keys[1].key)
    else
      B.state = "ready"
      ns.PlanPost(nil)
    end
    notify()
    return
  end
  local limit = MaxUnit(B.kind, B.id, B.entry)
  if B.want then limit = math.huge end -- a typed amount is bought at whatever it costs (the bar shows the average)
  local pick
  for _, k in ipairs(keys) do if limit and k.min > 0 and k.min <= limit then pick = k break end end
  if pick then Detail(pick.key) notify() return end
  B.state, B.plan = "idle", nil
  if not keys[1] then B.msg = "Keine Angebote mehr im AH."
  else B.msg = ("Billigstes jetzt %s, über dem Grenzpreis %s."):format(ns.Money(keys[1].min), ns.Money(math.floor(limit or 0))) end
  -- no detail search follows here: the browse price stands as the fresh one. It is at most the cheapest buyout (a bid is
  -- never over its buyout), so "over the limit" holds either way.
  if keys[1] and keys[1].min > 0 then ns.fresh[B.id] = { p = keys[1].min, t = time() } ns.SellDirty() end
  local msg = B.msg
  Gone()
  if B.msg == "Weg. Das war die letzte Zeile." then B.msg = msg end
  notify()
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)
