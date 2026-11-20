local _, ns = ...

---------------------------------------------------------------------------
-- Selling mats (Daniel 06.11.2026: "genau der Preis des billigsten Angebots, nicht darunter", "neuere Sachen werden dann
-- zuerst verkauft"): disenchant mats and what the own recipes make, from the bags, posted at exactly the price of the
-- cheapest offer of others now (a click searches first; cheap single outliers far under the rest are passed over as in
-- Golddon). Only items whose AH price after the cut beats the vendor. All units of the bags in one listing (commodity) or
-- as one auction each (items). Run time from the option postDur (step 1 to 3).
---------------------------------------------------------------------------
-- (Daniel 06.11.2026: "auf 8 Stunden eingestellt") Forever's run times are not 12/24/48: they come from the client's own texts
-- AUCTION_DURATION_ONE to THREE, as TSM reads them (LibTSMWoW/Source/API/AuctionHouse.lua); 12/24/48 only without them
local function Hours(s, d)
  local n = type(s) == "string" and tonumber(s:match("(%d+)"))
  return n or d
end
local HOURS = { Hours(rawget(_G, "AUCTION_DURATION_ONE"), 12), Hours(rawget(_G, "AUCTION_DURATION_TWO"), 24), Hours(rawget(_G, "AUCTION_DURATION_THREE"), 48) }
ns.POST_HOURS = HOURS
-- (Daniel 06.11.2026: TSM shows 2/8/24 hours, a player said 12/24/48) the option is the step itself: 1 short, 2 middle
-- (default, as before), 3 long, named with the client's own texts
function ns.PostDurIndex()
  local d = math.floor(tonumber(ns.Opt("postDur")) or 2)
  return math.max(1, math.min(3, d))
end

-- the items Profitdon sells: every mat of the disenchant table and every product of the character's recipes
local function Wanted()
  local w = {}
  for _, list in pairs(ns.DE.groups or {}) do for k = 1, #list, 4 do w[list[k]] = true end end
  if ns.Crafts then for id in pairs(ns.Crafts.Products()) do w[id] = true end end
  return w
end
ns.SellWanted = Wanted

-- the random suffix of an item link ("of the Bear"): item:id:enchant:gem1:gem2:gem3:gem4:suffix; 0 without one.
-- (Daniel 09.11.2026, Willow Belt of the Sorcerer offered at the 9s of all variants) Forever leaves the suffix field empty
-- and names the variant by a bonus ID (item:6267::::::::10:1482:::1:12745): then the first bonus ID tells the variants apart
function ns.LinkSuffix(link)
  local body = type(link) == "string" and link:match("item:([^|]+)")
  if not body then return 0 end
  local f = {}
  for v in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
  local s = tonumber(f[7] or "")
  if s and s ~= 0 then return math.abs(s) end
  local nb = tonumber(f[13] or "") or 0
  return nb > 0 and math.abs(tonumber(f[14] or "") or 0) or 0
end
function ns.LinkName(link) return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil end

---------------------------------------------------------------------------
-- (Daniel 17.11.2026, Bild Auctionator Selling, PROFITDON_PLAN.md "Verkaufen-Seite neu") the bags in sections:
--   made    products of the own recipes the AH pays more for than the vendor
--   ah      everything else tradable the AH pays more for after the cut: disenchant mats, gear the bag button keeps for
--           the AH (DE.KeepForAH, one row per piece and variant), and since 17.11. any other ware with a scan price
--   vendor  the vendor pays more (or the gain is under the options sellMinGain / sellMinPct): shown dimmed, a right click
--           puts it on the sell list at the merchant
--   noprice mats and products without a scan price yet: the click searches live
-- Left out: bound, locked, quest items, grey ones except armour and weapons, what is sold by a vendor without limit.
-- (Daniel 17.11.2026: "Graues Rüstungen und Waffen könnten eventuell für Transmog später interessant sein"; chosen: in
-- Verkaufen and kept from the merchant button) grey armour and weapons with a price count as other ware: Forever's
-- transmog gives a grey piece's look to whoever loots it, and the AH trades them, often over the vendor price.
-- Hidden (ProfitdonDB.sellHide[id]): 1 = while only one is in the bags, true = always, false = shown although a default
-- hides it; the profession tools come with 1 (Daniel 17.11.2026). Hidden rows go to their own list (ns.SellHidden).
-- The list is kept until the bags, the options, the scan or a searched price change (ns.SellDirty): the window asked for
-- it several times per redraw, each a walk over all bags.
---------------------------------------------------------------------------
ns.SELL_SECTIONS = { "made", "ah", "vendor", "noprice" }
ns.SELL_SECTION_NAME = { made = "Hergestellt", ah = "AH lohnt", vendor = "Händler zahlt mehr", noprice = "Ohne Preis", hidden = "Ausgeblendet" }
local SECTION_OPT = { made = "sellMade", ah = "sellAH", vendor = "sellVendorRows", noprice = "sellNoPrice" }
ns.SELL_SECTION_OPT = SECTION_OPT
-- Mining Pick, Blacksmith Hammer, Arclight Spanner, Skinning Knife, the fishing poles, Gyromatic Micro-Adjustor, Flint
-- and Tinder, Philosopher's Stone, the runed rods (CMaNGOS item_template). The bound ones never show under Verkaufen, but
-- the sell window at the merchant offered them too (Daniel 17.11.2026, Bild: "auch hier nicht zum Verkauf anbieten")
ns.SELL_TOOLS = { [2901] = 1, [5956] = 1, [6219] = 1, [7005] = 1, [6256] = 1, [6365] = 1, [6366] = 1, [6367] = 1, [12221] = 1,
  [10498] = 1, [4471] = 1, [9149] = 1, [6218] = 1, [6339] = 1, [11130] = 1, [11145] = 1, [16207] = 1 }
-- hidden by sellHide with this many in the bags (Verkaufen and the merchant's sell window)
function ns.SellHiddenAt(id, count)
  local h = ns.SellHideMode(id)
  return h == true or (h == 1 and (count or 0) <= 1)
end

function ns.SellHideMode(id)
  -- (Daniel 17.11.2026, Bild: a tool under Hergestellt) without the table "and" gave false, not nil: the default was lost
  local h
  if ns.db and type(ns.db.sellHide) == "table" then h = ns.db.sellHide[id] end
  if h == nil then h = ns.SELL_TOOLS[id] end
  return h or nil
end
-- mode: 1 (while only one), true (always), nil (shown again)
function ns.SetSellHide(id, mode)
  ns.db.sellHide = type(ns.db.sellHide) == "table" and ns.db.sellHide or {}
  if mode then ns.db.sellHide[id] = mode
  elseif ns.SELL_TOOLS[id] then ns.db.sellHide[id] = false
  else ns.db.sellHide[id] = nil end
  ns.SellDirty()
end

local cache
function ns.SellDirty() cache = nil end
ns.On("BAG_UPDATE_DELAYED", ns.SellDirty)
ns.On("ITEM_LOCK_CHANGED", ns.SellDirty)
ns.On("GET_ITEM_INFO_RECEIVED", ns.SellDirty)

-- grey armour or weapon (class 2 or 4)
function ns.GreyGear(id)
  local class = ns.ItemClass(id)
  return class == 2 or class == 4
end

local function MinGain(e)
  local a = math.max(0, tonumber(ns.Opt("sellMinGain")) or 0)
  local pct = math.max(0, tonumber(ns.Opt("sellMinPct")) or 0)
  return math.max(a, math.floor((e.sell or 0) * e.count * pct / 100 + 0.5))
end

-- (17.11.2026) the merchant button leaves grey armour and weapons in the bags while the AH pays more after the cut than
-- the vendor (the same rule as the section "AH lohnt": over the minimum gain); count: the pieces of the stack
function ns.GreyKeep(id, count, sell)
  if not ns.GreyGear(id) then return false end
  local unit = ns.FreshLow and ns.FreshLow(id) or ns.Prices.Low(id)
  if not unit then return false end
  local e = { count = count or 1, sell = sell or ns.Prices.Sell(id) or 0 }
  local profit = ns.Deals.AfterCut(unit * e.count, ns.Prices.Cut()) - e.sell * e.count
  return profit > 0 and profit >= MinGain(e)
end

local function Build()
  local P, D, DE = ns.Prices, ns.Deals, ns.DE
  local cut = P.Cut()
  local want, products = Wanted(), ns.Crafts and ns.Crafts.Products() or {}
  local byId, all = {}, {}
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id and not info.isLocked and not info.isBound then
        local q = ns.Num(info.quality) or select(3, ns.ItemInfo(id))
        -- gear the bag button could disenchant: only what DE.KeepForAH keeps for the AH, the rest is the button's
        local gearDE, why
        if DE and not want[id] and DE.QualityOK(q) then gearDE, why = DE.Group(id) end
        if why == "wait" then -- the game does not know the item yet: GET_ITEM_INFO_RECEIVED builds the list again
        elseif gearDE then
          -- (Daniel 07.11.2026: green BoE gear the bag button kept for the AH was offered nowhere) each such piece is its own
          -- row (variants differ by suffix), posted one at a time; the search takes the offers of the same suffix only
          local keep, value = DE.KeepForAH(id, nil, nil, info.hyperlink)
          if keep then
            local suffix = ns.LinkSuffix(info.hyperlink)
            local fk = suffix > 0 and (id .. ":" .. suffix) or id
            all[#all + 1] = { id = id, count = 1, bag = bag, slot = slot, sell = P.Sell(id) or 0, gear = true, suffix = suffix,
              link = info.hyperlink, freshKey = fk, deValue = value, quality = q, unit = ns.FreshLow and ns.FreshLow(fk) or P.Low(id) }
          end
        elseif want[id] or (q and q >= 1) or (q == 0 and ns.GreyGear(id)) then
          local e = byId[id]
          if not e then
            local unit = ns.FreshLow and ns.FreshLow(id) or P.Low(id)
            local _, _, _, _, _, _, class = ns.ItemInfo(id)
            -- other ware: only with a price, never quest items or what a vendor sells without limit
            local other = not want[id]
            local ok = not other or (unit and ns.Num(class) ~= 12 and not (P.VendorBuy and P.VendorBuy(id, true)))
            if ok then
              e = { id = id, count = 0, bag = bag, slot = slot, sell = P.Sell(id) or 0, unit = unit, quality = q,
                made = products[id] and true or nil, other = other or nil }
              all[#all + 1] = e
            else e = false end
            byId[id] = e
          end
          if e then e.count = e.count + (ns.Num(info.stackCount) or 1) end
        end
      end
    end
  end
  local out, hidden, counts = {}, {}, { made = 0, ah = 0, vendor = 0, noprice = 0, hidden = 0 }
  for _, e in ipairs(all) do
    if e.unit then
      e.ret = D.AfterCut(e.unit * e.count, cut)
      e.cost = e.unit * e.count
      e.profit = e.ret - e.sell * e.count
      e.section = (e.profit <= 0 or e.profit < MinGain(e)) and "vendor" or (e.made and "made" or "ah")
    else
      e.ret, e.profit, e.cost = nil, nil, nil
      e.section = "noprice" -- no scan price yet: the click searches
    end
    local h = not e.gear and ns.SellHideMode(e.id)
    local key = SECTION_OPT[e.section]
    if h == true or (h == 1 and e.count <= 1) then
      e.hidden = true
      hidden[#hidden + 1] = e
      counts.hidden = counts.hidden + 1
    elseif ns.Opt(key) ~= false then
      e.hidden = nil
      out[#out + 1] = e
      counts[e.section] = counts[e.section] + 1
    end
  end
  local order = { made = 1, ah = 2, vendor = 3, noprice = 4 }
  local function sorter(a, b)
    if order[a.section] ~= order[b.section] then return order[a.section] < order[b.section] end
    if (a.ret or 0) ~= (b.ret or 0) then return (a.ret or 0) > (b.ret or 0) end
    if a.id ~= b.id then return a.id < b.id end
    return (a.slot or 0) + (a.bag or 0) * 1000 < (b.slot or 0) + (b.bag or 0) * 1000
  end
  table.sort(out, sorter)
  table.sort(hidden, sorter)
  return { list = out, hidden = hidden, counts = counts }
end

local function Get()
  local st = ns.Prices.Store()
  local stT = st and st.t or 0
  if not ns.bagCacheOff and cache and cache.ver == ns.dataVer and cache.st == stT then return cache end
  cache = Build()
  cache.ver, cache.st = ns.dataVer, stT
  return cache
end
-- every row Verkaufen shows, in section order (made, ah, vendor, noprice), each with e.section
function ns.SellList() return Get().list end
function ns.SellHidden() return Get().hidden end
function ns.SellCounts() return Get().counts end
-- what waits for the AH: rows of the sections made, ah and noprice (the tab's mark, the chip's count)
function ns.SellWaiting()
  local c = Get().counts
  return c.made + c.ah + c.noprice
end

local function Location(bag, slot)
  if ItemLocation and ItemLocation.CreateFromBagAndSlot then return ns.Call(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot) end
end

-- the cheapest real offer of others right now (after the search); nil when there is none
function ns.CheapestOther(id, key, commodity)
  local list = {}
  if commodity then
    local n = ns.Num(ns.Call(ns.AH.GetNumCommoditySearchResults, id)) or 0
    for i = 1, math.min(n, 50) do
      local r = ns.Call(ns.AH.GetCommoditySearchResultInfo, id, i)
      local q = type(r) == "table" and (ns.Num(r.quantity) or 0) - (r.containsOwnerItem and (ns.Num(r.numOwnerItems) or 0) or 0)
      if q and q > 0 and ns.Num(r.unitPrice) then list[#list + 1] = { r.unitPrice, q } end
    end
  else
    local n = ns.Num(ns.Call(ns.AH.GetNumItemSearchResults, key)) or 0
    for i = 1, math.min(n, 50) do
      local r = ns.Call(ns.AH.GetItemSearchResultInfo, key, i)
      local bo = type(r) == "table" and not r.containsOwnerItem and ns.Num(r.buyoutAmount)
      -- (Daniel 15.11.2026, Salt Shaker: 13 like offers at 3g48 each read as 26s77 a piece, "der Händler zahlt mehr",
      -- the row went) an item offer is one piece at buyoutAmount; quantity counts the like offers the game groups
      if bo then list[#list + 1] = { bo, ns.Num(r.quantity) or 1 } end
    end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  return math.floor(ns.Deals.LowOffer(list) + 0.5)
end

-- (17.11.2026, Verkaufen-Seite) the offers of the search for the list on the right: { unit, qty, own }, cheapest first,
-- own ones marked (commodities: the own part of a row as a row of its own)
function ns.OfferList(id, key, commodity)
  local out = {}
  if commodity then
    local n = ns.Num(ns.Call(ns.AH.GetNumCommoditySearchResults, id)) or 0
    for i = 1, math.min(n, 50) do
      local r = ns.Call(ns.AH.GetCommoditySearchResultInfo, id, i)
      local up = type(r) == "table" and ns.Num(r.unitPrice)
      if up then
        local q, own = ns.Num(r.quantity) or 0, r.containsOwnerItem and (ns.Num(r.numOwnerItems) or 0) or 0
        if own > 0 then out[#out + 1] = { up, own, true } end
        if q - own > 0 then out[#out + 1] = { up, q - own } end
      end
    end
  else
    local n = ns.Num(ns.Call(ns.AH.GetNumItemSearchResults, key)) or 0
    for i = 1, math.min(n, 50) do
      local r = ns.Call(ns.AH.GetItemSearchResultInfo, key, i)
      local bo = type(r) == "table" and ns.Num(r.buyoutAmount)
      if bo then out[#out + 1] = { bo, ns.Num(r.quantity) or 1, r.containsOwnerItem and true or nil } end
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- (17.11.2026) the plan's deposit, return and gain over the vendor for its amount, price and run time
local function Recalc(p, e)
  local cut = ns.Prices.Cut()
  p.dur = ns.PostDurIndex()
  if p.commodity then p.deposit = ns.Num(ns.Call(ns.AH.CalculateCommodityDeposit, p.id, p.dur, p.qty))
  else p.deposit = ns.Num(ns.Call(ns.AH.CalculateItemDeposit, p.loc, p.dur, p.qty)) end
  p.ret = ns.Deals.AfterCut(p.unit * p.qty, cut)
  p.overVendor = p.ret - (e and e.sell or 0) * p.qty - (p.deposit or 0)
end
-- (Daniel 17.11.2026, Bild Auctionator: Menge mit "Max", Preis je Stück änderbar, Laufzeit) the head of the page changes
-- the plan: qty (1 .. what the bags hold) and unit (copper) stay for this item until another row is picked
-- (ns.BuyState.postQty / postUnit, cleared by ns.Select); nil leaves a value as it is
function ns.PostAdjust(qty, unit)
  local B = ns.BuyState
  if qty ~= nil then B.postQty = math.max(1, math.floor(tonumber(qty) or 1)) end
  if unit ~= nil then B.postUnit = math.max(1, math.floor(tonumber(unit) or 1)) end
  local p = B.plan
  if not (p and p.post) then return end
  if B.postQty then p.qty = math.min(B.postQty, p.have) end
  if B.postUnit then p.unit = B.postUnit end
  Recalc(p, B.entry)
  local sell = B.entry and B.entry.sell or 0
  -- under the vendor after the cut: a second click before it goes in
  if ns.Deals.AfterCut(p.unit, ns.Prices.Cut()) <= sell then
    p.confirm = ("Preis %s: der Händler zahlt mehr (%s)."):format(ns.Money(p.unit), ns.Money(sell))
  elseif p.confirm and p.confirm:find("Händler zahlt mehr", 1, true) then p.confirm = p.noLive end
  if ns.Refresh then ns.Refresh() end
end

-- (Daniel 14.11.2026, block 5: "dass man immer einen Teil davon verkauft") how many of `have` to post now: with demand
-- numbers (Market.Demand) what sells in demDays days, at least one; "kaum": one piece to try; without numbers all. The
-- rest stays in the bags and shows again under Verkaufen. Second value: the line for the message, nil when all go.
function ns.PostPortion(id, have)
  if not ns.Opt("postPortion") or have <= 1 then return have end
  local d = ns.Market and ns.Market.Demand and ns.Market.Demand(id)
  if not d then return have end
  local n = d.label == "poor" and 1 or math.max(1, math.ceil(d.perDay * ns.Opt("demDays")))
  if n >= have then return have end
  return n, ("Absatz %s: %d von %d einstellen, der Rest bleibt in der Tasche."):format(ns.Market.LABEL[d.label], n, have)
end

-- after the search: the plan with the price of the cheapest offer now
function ns.PlanPost(commodity)
  local B = ns.BuyState
  local e = B.entry
  if not e then return end
  local lowest = commodity ~= nil and ns.CheapestOther(e.id, B.key, commodity) or nil
  B.offers = commodity ~= nil and ns.OfferList(e.id, B.key, commodity) or {}
  if lowest then
    ns.fresh[e.freshKey or e.id] = { p = lowest, t = time() } -- (Daniel 06.11.2026: the row said 71c, the search 60c) the row shows it
    ns.SellDirty()
    e.unit = lowest
  end
  local unit = lowest or e.unit
  B.plan = nil
  if not unit then B.msg = "Kein Angebot und kein Scanpreis: Preis unbekannt." return end
  local cut = ns.Prices.Cut()
  if ns.Deals.AfterCut(unit, cut) <= (e.sell or 0) then
    B.msg = ("Billigstes Angebot %s: der Händler zahlt mehr (%s)."):format(ns.Money(unit), ns.Money(e.sell or 0))
    return
  end
  local loc = Location(e.bag, e.slot)
  if not loc then B.msg = "Kein Platz in der Tasche gefunden." return end
  -- no other offer at all (the browse found nothing): the game says whether it is a commodity
  if commodity == nil then
    local status = ns.Call(ns.AH.GetItemCommodityStatus, loc)
    commodity = status == ((Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity) or 2)
  end
  local have = e.gear and 1 or ns.BagCount(e.id) -- gear: just this piece (other pieces of the ID may have another suffix)
  local dur = ns.PostDurIndex()
  local qty, portion = ns.PostPortion(e.id, math.max(1, have))
  local p = { post = true, commodity = commodity, loc = loc, id = e.id, qty = qty, unit = unit, dur = dur, have = have, portion = portion,
    link = e.gear and e.link or nil }
  if commodity then p.deposit = ns.Num(ns.Call(ns.AH.CalculateCommodityDeposit, e.id, dur, p.qty))
  else p.deposit = ns.Num(ns.Call(ns.AH.CalculateItemDeposit, loc, dur, p.qty)) end
  p.total = 0 -- posting costs no purchase confirmation
  p.ret = ns.Deals.AfterCut(unit * p.qty, cut)
  -- (Durchsicht 11.11.2026) no offer of others seen now: the price is the last scan's, a second click before it goes in
  if not lowest then p.confirm = ("Kein Live-Angebot, Preis aus dem letzten Scan (%s je Stück)."):format(ns.Money(unit)) end
  p.noLive = p.confirm
  p.lowest = lowest
  B.plan = p
  Recalc(p, e)
  if B.postQty or B.postUnit then ns.PostAdjust() end
  B.msg = lowest and ("Billigstes Angebot jetzt %s je Stück: genau dazu einstellen."):format(ns.Money(unit))
    or (e.gear and ("Kein Angebot dieser Variante: Preis aus dem letzten Scan, Mittel aller Varianten (%s)."):format(ns.Money(unit)))
    or ("Kein anderes Angebot: Preis aus dem letzten Scan (%s)."):format(ns.Money(unit))
  if portion then B.msg = B.msg .. " " .. portion end
end

-- (Durchsicht 15.11.2026) the plan keeps the bag slot from the moment the list was built; bags sorted or used up since:
-- something else lies there and would be posted at this plan's price. Checked right before the posting: the slot still
-- holds the planned item (gear: the same link, another piece of the ID may be another variant).
local function StillThere(p)
  local CI = C_Item
  if not (type(CI) == "table" and CI.DoesItemExist and CI.GetItemID) then return true end
  if not ns.Call(CI.DoesItemExist, p.loc) then return false end
  if ns.Num(ns.Call(CI.GetItemID, p.loc)) ~= p.id then return false end
  if p.link and CI.GetItemLink then
    local l = ns.Call(CI.GetItemLink, p.loc)
    if type(l) == "string" and l ~= p.link then return false end
  end
  return true
end
ns.PostStillThere = StillThere -- (tests)

local sent
function ns.PostNow(p)
  if not StillThere(p) then
    ns.Print("Nicht eingestellt: an dem Taschenplatz liegt etwas anderes als geplant. Zeile nochmal anklicken.")
    return false
  end
  local ok, needs
  if p.commodity then
    ok, needs = pcall(ns.AH.PostCommodity, p.loc, p.dur, p.qty, p.unit)
    if ok and needs then ok, needs = pcall(ns.AH.ConfirmPostCommodity, p.loc, p.dur, p.qty, p.unit) end
  else
    ok, needs = pcall(ns.AH.PostItem, p.loc, p.dur, p.qty, nil, p.unit)
    if ok and needs then ok, needs = pcall(ns.AH.ConfirmPostItem, p.loc, p.dur, p.qty, nil, p.unit) end
  end
  if ok then
    sent = { id = p.id, qty = p.qty, unit = p.unit, hours = HOURS[p.dur], deposit = p.deposit }
    -- the deposit: booked by Ledger.lua when the gold goes out
    if (p.deposit or 0) > 0 and ns.Ledger then ns.Ledger.Expect("fee", -p.deposit, 1) end
  else ns.Fact("postError", tostring(needs)) ns.Print("Einstellen abgelehnt: " .. tostring(needs)) end
  return ok
end
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function()
  if not sent then return end
  if ns.Report then
    ns.Report.Posted(sent.id, sent.qty, sent.unit, sent.hours)
  end
  -- the deposit the game named for this posting: a measurement for the estimate (Deals.lua D.NoteDeposit)
  ns.Deals.NoteDeposit(ns.Prices.Sell(sent.id), sent.qty, sent.hours or 24, sent.deposit)
  local share, n, scaled = ns.Deals.DepositSeen(sent.hours or 24)
  if share then ns.Fact("deposit", ("%d h: %.1f %% vom Händlerpreis aus %d Einstellungen%s"):format(sent.hours or 24, share * 100, n, scaled and " (umgerechnet)" or "")) end
  ns.Print(("Eingestellt: %d× %s zu je %s (%d h)"):format(sent.qty, ns.ItemInfo(sent.id) or sent.id, ns.Money(sent.unit), sent.hours or 24))
  sent = nil
end)
ns.On("AUCTION_HOUSE_POST_ERROR", function() if sent then ns.Print("Einstellen fehlgeschlagen.") sent = nil end end)
