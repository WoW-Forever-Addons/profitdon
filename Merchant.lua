local _, ns = ...

---------------------------------------------------------------------------
-- At the merchant (from Golddon's Merchant.lua, lean):
--   * learn what this vendor sells and for how much (ProfitdonDB.buy[item] = { price, stack, limited, name, uiMap, x, y,
--     time }), the Forever prices beat the shipped data
--   * "Profitdon: verkaufen": grey items, what Profitdon bought at the AH for the vendor (ProfitdonDB.flips) and what it
--     crafted for the vendor (ProfitdonDB.made), up to 12 per click (the click is the hardware event)
--   * "Mats kaufen": the vendor mats of the chosen craft's shopping list that this vendor sells, up to 12 purchases a click
---------------------------------------------------------------------------
local MAX_PER_CLICK = 12
-- (Daniel 24.11.2026: "bitte bei der anzahl mit runter zählen") run: the purchase in rounds (MatsClick; up here since Label
-- read a global and never saw it); lastRun: the finished one, shown until the bags have caught up; visitGot[id]: what
-- of a list entry that buys its amount every time ("fixed") was bought at this vendor visit
local run, lastRun
local visitGot = {}

local function Here()
  local map = C_Map and ns.Call(C_Map.GetBestMapForUnit, "player")
  local pos = map and ns.Call(C_Map.GetPlayerMapPosition, map, "player")
  local x, y
  if pos and pos.GetXY then x, y = ns.Call(pos.GetXY, pos) end
  x, y = ns.Num(x), ns.Num(y)
  return map or 0, x and math.floor(x * 1000) / 10 or 0, y and math.floor(y * 1000) / 10 or 0
end

local function ItemAt(i)
  local link = ns.Call(GetMerchantItemLink, i)
  local id = link and tonumber(link:match("item:(%d+)"))
  local info = C_MerchantFrame and ns.Call(C_MerchantFrame.GetItemInfo, i)
  if type(info) ~= "table" and GetMerchantItemInfo then
    local _, _, price, stack, avail, _, _, ext = ns.Call(GetMerchantItemInfo, i)
    info = { price = price, stackCount = stack, numAvailable = avail, hasExtendedCost = ext }
  end
  return id, type(info) == "table" and info or nil
end

local function Learn()
  local n = ns.Num(ns.Call(GetMerchantNumItems)) or 0
  if n == 0 then return end
  ns.db.buy = ns.db.buy or {}
  local name = ns.Call(UnitName, "npc") or "?"
  local map, x, y = Here()
  local barter = ns.Prices.Barter()
  for i = 1, n do
    local id, info = ItemAt(i)
    if id and info and not info.hasExtendedCost then
      local price, stack = ns.Num(info.price), math.max(1, ns.Num(info.stackCount) or 1)
      if price and price > 0 then
        local old = ns.db.buy[id]
        if not old or price / stack <= old[1] / old[2] or old[4] == name then
          -- [9] (16.11.2026): the Bartering discount the price was seen with (Prices.lua P.VendorBuy)
          local lim = (info.numAvailable or -1) >= 0 and 1 or 0
          -- (21.11.2026, Ruckler: MERCHANT_UPDATE comes after every purchase and stock tick) an entry that says the same
          -- only gets the new time, no new table
          if old and old[1] == price and old[2] == stack and old[3] == lim and old[4] == name and old[5] == map
            and old[6] == x and old[7] == y and old[9] == barter then
            old[8] = time()
          else
            ns.db.buy[id] = { price, stack, lim, name, map, x, y, time(), barter }
          end
        end
      end
    end
  end
end

-- what the sell button would sell: { bag, slot, id, count, value, why }
local function Plan()
  local out, flips, made = {}, ns.db.flips or {}, ns.db.made or {}
  -- (Durchsicht 15.11.2026) "bought for the vendor" does not hold for ever (the piece went another way: posted,
  -- disenchanted; 30 days, flips with a date only), and a flip does not go with the suggestion while the AH pays more
  -- after the cut than the vendor: the row stays in the list with its hint, sold by its own click. What was made for
  -- the vendor goes as before (Daniel chose the vendor when he made it).
  local left = {}
  local now, cut = time(), ns.Prices.Cut()
  for id, f in pairs(flips) do if not f.t or now - f.t < 30 * 86400 then left[id] = f.q end end
  local function AhMore(id, sell)
    local ah = ns.AHPrice and ns.AHPrice(id)
    return ah and ns.Deals.AfterCut(ah, cut) > sell or false
  end
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id and not info.isLocked and not info.hasNoValue then
        local count = ns.Num(info.stackCount) or 1
        local sell = ns.Prices.Sell(id)
        local why
        if sell and sell > 0 then
          if ns.Opt("sellVendor") and (left[id] or 0) >= count then
            left[id] = left[id] - count
            if not AhMore(id, sell) then why = "flip" end
          elseif ns.Opt("sellVendor") and made[id] == "vendor" then why = "made"
          -- (Daniel 17.11.2026, transmog) grey armour and weapons the AH pays more for stay for Verkaufen
          elseif ns.Opt("sellGrey") and info.quality == 0 and not (ns.GreyKeep and ns.GreyKeep(id, count, sell)) then why = "grey" end
        end
        if why then out[#out + 1] = { bag = bag, slot = slot, id = id, count = count, value = sell * count, why = why } end
      end
    end
  end
  return out
end

-- what "Mats kaufen" buys here: { index, id, buys (purchases), units, cost }
local MatsJobs, MatsFixed
local function MatsPlan()
  -- (Daniel 16.11.2026, Bild: Seasoned Wolf Kabob über Skillen auf der Liste, "Mild Spices beim Händler (Knopf Mats
  -- kaufen)", the button was not there: "wieso will er mir keine mild spices vorschlagen?") the whole shopping list counts,
  -- not only the chosen recipe: the plan of "Skillen", the Favor crates, the tracked recipes
  local need, jobs, fixed = {}, {}, {}
  -- (Daniel 16.11.2026) mats already bought for it and crafts made since: only what the crafts still open lack, not the
  -- whole number again (the bags are emptier because the mats went into the crafts)
  local Cr = ns.Crafts
  local entries = {}
  for _, en in ipairs((ns.ShopLists and ns.ShopLists.ActiveEntries()) or Cr.ShopEntries()) do
    local left = en.r and Cr.JobLeft and Cr.JobLeft(en.r.spell)
    local runs = left and math.min(left, en.runs or 1) or en.runs
    if not left or runs > 0 then
      local c = {}
      for k, x in pairs(en) do c[k] = x end
      c.runs = runs
      entries[#entries + 1] = c
    end
  end
  for _, e in ipairs(Cr.ShoppingList(entries, true)) do
    if not e.head and not e.alt and e.src == "vendor" and e.need > 0 then
      need[e.id] = (need[e.id] or 0) + e.need
      if e.fixed then fixed[e.id] = (fixed[e.id] or 0) + e.need end
      -- the recipes the purchase is for: jobs of the Herstellfenster
      if e.forSpell then jobs[#jobs + 1] = { e.forSpell, e.forRuns } end
    end
  end
  MatsJobs = jobs
  -- a fixed entry asks for its amount whatever the bags hold: what this visit bought of it is taken off, else the row
  -- stood at the full count again after the purchase
  for id, f in pairs(fixed) do
    local off = math.min(f, visitGot[id] or 0)
    fixed[id], need[id] = f - off, need[id] - off
    if need[id] <= 0 then need[id] = nil end
  end
  MatsFixed = fixed
  local out = {}
  local n = ns.Num(ns.Call(GetMerchantNumItems)) or 0
  for i = 1, n do
    local id, info = ItemAt(i)
    if id and need[id] and info and not info.hasExtendedCost and ns.Num(info.price) then
      local stack = math.max(1, ns.Num(info.stackCount) or 1)
      local buys = math.ceil(need[id] / stack)
      -- (Durchsicht 15.11.2026) a limited stock: not more purchases than the vendor has
      local avail = ns.Num(info.numAvailable)
      if avail and avail >= 0 then buys = math.min(buys, avail) end
      -- one call buys at most the item's stack (BuyMerchantItem refuses more): the calls it takes
      local maxStack = math.max(1, ns.Num(ns.Call(GetMerchantItemMaxStack, i)) or 20)
      if buys > 0 then
        out[#out + 1] = { index = i, id = id, stack = stack, buys = buys, units = buys * stack, cost = buys * info.price,
          price = info.price, maxStack = maxStack }
      end
      need[id] = nil
    end
  end
  return out
end
ns.MerchantMatsPlan = MatsPlan

-- (Daniel 18.11.2026: "manchmal, dass irgendwie zu viel Fleisch oder Eier eingekauft worden sind und es fehlen mir dann
-- nochmal 150 Spices ... einen Vorschlag ... der anhand meines Inventars und das, was ich vorher gecraftet habe oder craften
-- könnte, die Spices vorschlägt ... für jeden Beruf ... den einen Platz frei ... das Feld vorgefüllt ... mit einem Klick
-- alles markiere und überschreiben kann"; gewählt "Zuletzt gemacht, sonst lohnend" und die Skizze mit Einkaufen oben)
-- what the bags call for: every recipe of this character that takes a mat this vendor sells and other mats besides; the
-- other mats in the bags say how many crafts they make, the vendor mats for those crafts are suggested. Recipes made in the
-- last 7 days first (the latest first), then those with a profit (vendor or AH, the better); a mat in the bags goes to one
-- recipe only. Returns [id] = { units, parts = { { item, n, mat, recent } } } (what the bags lack of the vendor mat).
local RECENT_DAYS = 7
local function Recent()
  local out = {}
  local today = ns.Report and ns.Report.Day and ns.Report.Day() or math.floor(time() / 86400)
  for day, items in pairs(type(ns.db.rlog) == "table" and ns.db.rlog or {}) do
    if type(day) == "number" and today - day < RECENT_DAYS and type(items) == "table" then
      for item, e in pairs(items) do
        if type(e) == "table" and (e[1] or 0) > 0 and (not out[item] or out[item] < day) then out[item] = day end
      end
    end
  end
  return out
end
local function BagNeed(here)
  local Cr = ns.Crafts
  local me = type(ns.db.crafts) == "table" and ns.db.crafts[ns.Me()]
  local bags = ns.Bags()
  local recent = Recent()
  local cands = {}
  for spell in pairs(me and type(me.known) == "table" and me.known or {}) do
    local r = Cr.Recipe(spell)
    if r and r.item and r.reag and #r.reag > 0 and not Cr.HasCooldown(spell) then
      local hasV, hasB = false, false
      for _, g in ipairs(r.reag) do if here[g[1]] then hasV = true else hasB = true end end
      if hasV and hasB then
        local day, gain = recent[r.item], nil
        if not day then
          local v = Cr.Value(r)
          gain = v and math.max(v.profit or -1e15, v.ahExpProfit or v.ahProfit or -1e15) or nil
        end
        if day or (gain and gain > 0) then cands[#cands + 1] = { r = r, day = day or -1, gain = gain or 0 } end
      end
    end
  end
  table.sort(cands, function(a, b)
    if a.day ~= b.day then return a.day > b.day end
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.r.spell < b.r.spell
  end)
  local avail, need = {}, {}
  for id, n in pairs(bags) do avail[id] = n end
  for _, c in ipairs(cands) do
    local n, mat = math.huge, nil
    for _, g in ipairs(c.r.reag) do
      if not here[g[1]] then
        local k = math.floor((avail[g[1]] or 0) / g[2])
        if k < n then n = k end
        mat = mat or g[1]
      end
    end
    if n ~= math.huge and n > 0 then
      for _, g in ipairs(c.r.reag) do
        if here[g[1]] then
          local e = need[g[1]] or { units = 0, parts = {} }
          need[g[1]] = e
          e.units = e.units + n * g[2]
          e.parts[#e.parts + 1] = { item = c.r.item, n = n, mat = mat, recent = c.day >= 0 }
        else avail[g[1]] = avail[g[1]] - n * g[2] end
      end
    end
  end
  for id, e in pairs(need) do e.units = math.max(0, e.units - (bags[id] or 0)) end
  return need
end

-- what Einkaufen offers: the shopping list (MatsPlan) and the bags, the larger of both per mat; a count typed into the row's
-- field wins (buyWant, until the vendor closes). only: a set of ids (one row's "Kaufen") or nil for all.
-- Entries as MatsPlan's, plus why (the line under the name) and suggested (Profitdon's count).
local buyWant = {}
local function BuyPlan(only)
  local list = {}
  for _, e in ipairs(MatsPlan()) do list[e.id] = e end
  local here = {}
  local n = ns.Num(ns.Call(GetMerchantNumItems)) or 0
  for i = 1, n do
    local id, info = ItemAt(i)
    if id and info and not info.hasExtendedCost and ns.Num(info.price) and not here[id] then here[id] = { index = i, info = info } end
  end
  local ok, bag = pcall(BagNeed, here)
  if not ok then ns.Try(error, bag, 0) bag = {} end
  local ids, seen = {}, {}
  for id in pairs(list) do if not seen[id] then seen[id] = true ids[#ids + 1] = id end end
  for id, e in pairs(bag) do if e.units > 0 and not seen[id] then seen[id] = true ids[#ids + 1] = id end end
  for id in pairs(buyWant) do if here[id] and not seen[id] then seen[id] = true ids[#ids + 1] = id end end
  local out = {}
  for _, id in ipairs(ids) do
    local h = here[id]
    if h and (not only or only[id]) then
      local info = h.info
      local stack = math.max(1, ns.Num(info.stackCount) or 1)
      local l, b = list[id], bag[id]
      local fromBags = b and b.units > (l and l.units or 0)
      local units = fromBags and b.units or (l and l.units or 0)
      local why
      if fromBags then
        local parts = {}
        for k, p in ipairs(b.parts) do
          if k > 2 then parts[#parts] = parts[#parts] .. " und mehr" break end
          parts[#parts + 1] = ("%d× %s"):format(p.n, ns.ItemInfo(p.item) or ("Item " .. p.item))
        end
        local p1 = b.parts[1]
        why = "für " .. table.concat(parts, ", ") .. (p1 and (p1.recent and " (zuletzt hergestellt)"
          or (" (" .. (ns.ItemInfo(p1.mat) or "Mats") .. " in den Taschen)")) or "")
      else why = "für die Einkaufsliste" end
      local suggested = math.ceil(units / stack) * stack
      local typed = buyWant[id]
      local want = typed and math.ceil(typed / stack) * stack or suggested
      local buys = math.ceil(want / stack)
      local avail = ns.Num(info.numAvailable)
      if avail and avail >= 0 then buys = math.min(buys, avail) end
      local maxStack = math.max(1, ns.Num(ns.Call(GetMerchantItemMaxStack, h.index)) or 20)
      if buys > 0 or typed then
        out[#out + 1] = { index = h.index, id = id, stack = stack, buys = buys, units = buys * stack, cost = buys * info.price,
          price = info.price, maxStack = maxStack, why = why, suggested = suggested, typed = typed ~= nil }
      end
    end
  end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end
ns.MerchantBuyPlan = BuyPlan -- (tests)
ns.MerchantBuyWant = function(id, n) buyWant[id] = n lastRun = nil end -- (tests)

-- what of the plan fits the bags (one normal slot stays free for the crafts, as when buying): [id] = units that fit
local function Fit(plan)
  local freeN, freeR = ns.FreeSplit()
  freeN = math.max(0, freeN - 1)
  local out = {}
  for _, e in ipairs(plan) do
    local stack = ns.Stack(e.id) or 20
    local have = ns.Bags()[e.id] or 0
    local part = have % stack > 0 and (stack - have % stack) or 0
    local fitsR = ns.FitsReagentBag(e.id)
    local free = freeN + (fitsR and freeR or 0)
    local fit = math.min(e.units, math.floor((free * stack + part) / e.stack) * e.stack)
    out[e.id] = fit
    local used = math.ceil(math.max(0, fit - part) / stack)
    if fitsR then local r = math.min(freeR, used) freeR, used = freeR - r, used - r end
    freeN = math.max(0, freeN - used)
  end
  return out
end
ns.MerchantFit = Fit -- (tests)

---------------------------------------------------------------------------
-- (Daniel 08.11.2026, Bild beim Händler: "verkaufen button rechts neben dem verkaufsfenster. auch hergestellte ware anbieten
-- mit feld vorausgefüllt mit anzahl in bags und itemname vll noch ein hinweis, xx mehr im ah pro stück"; "feld anzahl
-- anklickbar dann wenn klick komplett markiert"; "drauf achten, dass es sich nicht mit den andren addons überlappt")
-- A small Kit window right of the merchant (no installed addon sits there: Auctionator, Baganator, Syndicator, TSM,
-- KeepOrToss, Questie checked; moved by hand it stays where it was put, ProfitdonDB.sellWin): one row per item Profitdon
-- would sell (grey, bought for the vendor, made for it) and per product of the own recipes in the bags, the count to sell
-- (Kit number box: preset with what the bags hold, a click selects the number), the vendor value and, where the AH pays
-- more after the cut, "im AH +x je Stück". A row picked: "Verkaufen" sells that count (whole stacks, up to 12 a click; a
-- rest is split off into a free slot and sold with the next click); "Vorschlag" the grey, bought and made ones (as the old
-- button); "Mats kaufen" as before.
---------------------------------------------------------------------------
local panel, sel
local SellClick, MatsClick -- defined below, used by the panel buttons
local want = {} -- [id] = count still to sell (typed, or left from the last click); nil: all in the bags
local WHY = { flip = "für den Händler gekauft", made = "für den Händler hergestellt", grey = "grau", product = "selbst herstellbar", rest = "Rest vom letzten Klick",
  list = "aus Verkaufen: Händler zahlt mehr" }

local function Stacks(id)
  local out, total = {}, 0
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      if type(info) == "table" and ns.Num(info.itemID) == id and not info.isLocked then
        local n = ns.Num(info.stackCount) or 1
        out[#out + 1] = { bag = bag, slot = slot, count = n }
        total = total + n
      end
    end
  end
  return out, total
end

local function FreeSlot()
  for bag = 0, 4 do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      if ns.Call(C_Container.GetContainerItemInfo, bag, slot) == nil then return bag, slot end
    end
  end
end

-- the rows: { id, have, why }
local function Offer()
  local out, byId = {}, {}
  local function add(id, n, why)
    local e = byId[id]
    if not e then e = { id = id, have = 0, why = why } byId[id] = e out[#out + 1] = e end
    e.have = e.have + n
  end
  for _, e in ipairs(Plan()) do add(e.id, e.count, e.why) end
  local products = ns.Crafts and ns.Crafts.Products() or {}
  -- (22.11.2026, Ruckler, DonMonitor report: MERCHANT_SHOW Merchant.lua:719 avg 79 ms) the hide rule asked ns.BagCount for
  -- every slot with a product: a walk through all bags per slot. The counts of all items once (ns.Bags), when first needed
  local counts
  local function Have(id) counts = counts or ns.Bags() return counts[id] or 0 end
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      -- (Daniel 17.11.2026, Bild: Gyromatic Micro-Adjustor, Arclight Spanner, Philosopher's Stone offered) the tools stay:
      -- the same hide rule as Verkaufen (ProfitdonDB.sellHide, tools while only one is in the bags)
      if id and products[id] and not info.hasNoValue and (byId[id] == nil or byId[id].why == "product")
        and not (ns.SellHiddenAt and ns.SellHiddenAt(id, Have(id))) then
        local sell = ns.Prices.Sell(id)
        if sell and sell > 0 then add(id, ns.Num(info.stackCount) or 1, "product") end
      end
    end
  end
  -- (Daniel 17.11.2026, PROFITDON_PLAN.md "Verkaufen-Seite neu") what a right click under Verkaufen > "Händler zahlt
  -- mehr" put on the list (ProfitdonDB.vendorList[id]); off the list once the bags hold none
  if type(ns.db.vendorList) == "table" then
    for id in pairs(ns.db.vendorList) do
      local _, total = Stacks(id)
      local sell = ns.Prices.Sell(id)
      if total > 0 and sell and sell > 0 then
        if not byId[id] then add(id, total, "list") end
      elseif total == 0 then ns.db.vendorList[id] = nil end
    end
  end
  -- (Daniel 11.11.2026, Bild beim Händler: "240× Heavy Dynamite verkauft, noch 357, nochmal klicken", the row was gone)
  -- a rest still to sell and the picked row stay in the list while the bags hold the item, whatever offered it first
  local keep = {}
  for id, n in pairs(want) do if (n or 0) > 0 then keep[id] = true end end
  if sel then keep[sel] = true end
  for id in pairs(keep) do
    if not byId[id] then
      local _, total = Stacks(id)
      local sell = ns.Prices.Sell(id)
      if total > 0 and sell and sell > 0 then add(id, total, "rest") end
    end
  end
  return out
end
ns.MerchantOffer = Offer -- (tests)

-- sells the picked count of one item: whole stacks first, a rest split off for the next click
-- (Durchsicht 15.11.2026) limit: the count the row shows. Without it a row "bought for the vendor: 20" sold every stack of
-- the ID in the bags (60), the own ones too.
local function SellItem(id, limit)
  local stacks, total = Stacks(id)
  local n = math.min(want[id] or tonumber(limit) or total, total)
  if n <= 0 then return 0, 0 end
  table.sort(stacks, function(a, b) return a.count > b.count end)
  local done, sold = 0, 0
  for _, s in ipairs(stacks) do
    if done >= MAX_PER_CLICK or sold >= n then break end
    if s.count <= n - sold then
      ns.Prices.Tried(s.bag, s.slot, id, s.count)
      ns.Call(C_Container.UseContainerItem, s.bag, s.slot)
      s.used, done, sold = true, done + 1, sold + s.count
    end
  end
  local rest, how = n - sold, ""
  if rest > 0 and done < MAX_PER_CLICK then
    how = " (kein freier Platz zum Abteilen)"
    for _, s in ipairs(stacks) do
      if not s.used and s.count > rest then
        local eb, es = FreeSlot()
        if eb then
          ns.Call(C_Container.SplitContainerItem, s.bag, s.slot, rest)
          ns.Call(C_Container.PickupContainerItem, eb, es)
          how = " (abgeteilt)"
        end
        break
      end
    end
  end
  want[id] = rest > 0 and rest or nil
  local name = ns.ItemInfo(id) or ("Item " .. id)
  ns.Print(("%d× %s verkauft%s"):format(sold, name, rest > 0 and (", noch " .. rest .. how .. ", nochmal klicken.") or "."))
  return sold, rest
end
ns.MerchantSellItem = function(id, limit)
  local ok, a, b = pcall(SellItem, id, limit)
  if not ok then ns.Try(error, a, 0) return 0, 0 end
  return a, b
end
ns.MerchantWant = function(id, n) want[id] = n end -- (tests)

local selBuy -- the picked row of Einkaufen (an item id)
local function Label()
  if not (panel and panel:IsShown()) then return end
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
  local C = Kit.C
  local cut, items, pick = ns.Prices.Cut(), {}, nil
  -- (Daniel 18.11.2026, Skizze) Einkaufen on top: one row per vendor mat, the count in a field (Profitdon's suggestion,
  -- a click selects it to type over), the cost; a line on the room; Verkaufen below
  local bp, buyPick = BuyPlan(), nil
  -- (Daniel 24.11.2026, Bild: 720 Hot Spices gekauft, die Zeile stand weiter auf 720: "bitte bei der anzahl mit runter
  -- zählen") while a purchase runs the rows show what of it is still to come (the bags lag behind the calls)
  local shown = run or (lastRun and GetTime() - lastRun.t < 1.5 and lastRun) or nil
  if shown and shown.target then
    for _, e in ipairs(bp) do
      local cap = shown.target[e.id]
      if cap then
        e.units = math.min(e.units, math.max(0, cap - (shown.got[e.id] or 0)))
        e.buys = math.ceil(e.units / e.stack)
        e.cost = e.buys * (e.price or 0)
      end
    end
  end
  local fit = Fit(bp)
  local short = {}
  if #bp > 0 then
    items[#items + 1] = { kind = "group", static = true, text = "Einkaufen" }
    for _, e in ipairs(bp) do
      local name, _, quality = ns.ItemInfo(e.id)
      local sub = e.why
      if e.typed and e.units ~= e.suggested then sub = sub .. (" (Vorschlag %d)"):format(e.suggested) end
      local it = { kind = "trow", itemID = e.id, quality = quality, title = name or ("Item " .. e.id), sub = sub, id = e.id, buy = e,
        active = selBuy == e.id, cells = { value = Kit.Money(e.cost) },
        edit = { key = "n", value = e.units, tip = "Wie viele kaufen (Klick markiert die Zahl)",
          onCommit = function(row, v) buyWant[row.id] = math.max(0, math.floor(tonumber(v) or 0)) lastRun = nil selBuy, sel = row.id, nil Label() end } }
      items[#items + 1] = it
      if it.active then buyPick = it end
      if (fit[e.id] or 0) < e.units then short[#short + 1] = ("%d von %d %s"):format(fit[e.id] or 0, e.units, name or ("Item " .. e.id)) end
    end
    items[#items + 1] = { kind = "note", text = #short == 0 and "Platz: passt alles, 1 Platz bleibt für die Crafts frei"
      or ("Platz reicht für %s (1 Platz bleibt für die Crafts frei)"):format(table.concat(short, ", ")) }
  end
  local sells = {}
  for _, e in ipairs(Offer()) do
    local name, _, quality = ns.ItemInfo(e.id)
    local sell = ns.Prices.Sell(e.id) or 0
    local n = math.min(want[e.id] or e.have, e.have)
    local ah = ns.AHPrice and ns.AHPrice(e.id)
    local net = ah and ns.Deals.AfterCut(ah, cut)
    local sub, color = WHY[e.why] or "", nil
    if net and net > sell then sub, color = sub .. ", im AH +" .. ns.Money(net - sell) .. " je Stück", C.goldBright end
    local it = { kind = "trow", itemID = e.id, quality = quality, title = name or ("Item " .. e.id),
      -- (Durchsicht 11.11.2026, Daniels Bilder beim Händler: the line was cut off) the count in the bags only when it differs
      -- from the count in the field
      sub = sub .. (n ~= e.have and (" (" .. e.have .. " in den Taschen)") or ""), subColor = color, id = e.id, have = e.have, n = n, sell = sell,
      active = sel == e.id and not selBuy, cells = { value = Kit.Money(sell * n) },
      edit = { key = "n", value = n, tip = "Wie viele verkaufen (Klick markiert die Zahl)",
        onCommit = function(row, v) want[row.id] = math.min(v, row.have) sel, selBuy = row.id, nil Label() end } }
    sells[#sells + 1] = it
    if it.active then pick = it end
  end
  -- (Daniel 24.11.2026, Bild beim Händler, "Zeile wählen": "das erste bereits auswählen, dass ich nur noch verkaufen
  -- klicken muss") nothing picked: the first row to sell is, also the next one once the picked row is sold out
  if not pick and not selBuy and sells[1] then
    pick, sel = sells[1], sells[1].id
    pick.active = true
  end
  if #sells > 0 then
    if #bp > 0 then items[#items + 1] = { kind = "group", static = true, text = "Verkaufen" } end
    for _, it in ipairs(sells) do items[#items + 1] = it end
  end
  panel.tbl:SetItems(items)
  local acts = {}
  if buyPick then
    local e = buyPick.buy
    panel.bar:SetData({ itemID = e.id, quality = buyPick.quality, title = buyPick.title,
      sub = ("%d Stück beim Händler für %s"):format(e.units, ns.Money(e.cost)) })
    if e.units > 0 then
      acts[#acts + 1] = { text = ("Kaufen (%d)"):format(e.units), kind = "primary", onClick = function() ns.Try(MatsClick, { [e.id] = true }) end }
    end
  elseif pick then
    panel.bar:SetData({ itemID = pick.id, quality = pick.quality, title = pick.title,
      sub = ("%d Stück beim Händler %s"):format(pick.n, ns.Money(pick.sell * pick.n)) })
    acts[#acts + 1] = { text = ("Verkaufen (%d)"):format(pick.n), kind = "primary",
      onClick = function() ns.MerchantSellItem(pick.id, pick.n) ns.After(0.8, Label) end }
  else
    panel.bar:SetData({ title = #items > 0 and "Zeile wählen" or "Nichts zu kaufen oder verkaufen",
      sub = #items > 0 and "Anzahl im Feld ändern, dann Kaufen oder Verkaufen" or "" })
  end
  -- (Daniel 16.11.2026: "Und man sieht auch nicht so richtig, was man kauft") the mats: in the bar while no row is picked,
  -- all of them in the button's tooltip, the price on the button
  -- (Daniel 16.11.2026, Bild Knopf "Vorschlag": "vorschlag bitte weg das irritiert") the button that sold all suggested
  -- rows at once is gone; a row is picked and sold
  local mp, cost = bp, 0
  local names, lines = {}, {}
  for _, e in ipairs(mp) do
    cost = cost + e.cost
    local name = ns.ItemInfo(e.id) or ("Item " .. e.id)
    if e.units > 0 or not run then names[#names + 1] = ("%d× %s"):format(e.units, name) end
    lines[#lines + 1] = { ("%d× %s"):format(e.units, name), ns.Money(e.cost) }
  end
  -- what it is for: the one recipe of the list by name, else the list
  local ents = (ns.ShopLists and ns.ShopLists.ActiveEntries()) or ns.Crafts.ShopEntries()
  local one = #ents == 1 and ents[1].r and ents[1] or nil
  local forWhat = one and (ns.ItemInfo(one.r.item) or "das Rezept") or "die Einkaufsliste"
  lines[#lines + 1] = "Die Zahlen aus den Feldern, ein Platz bleibt frei."
  local tip = { "Alle kaufen", lines, "Ein Klick kauft alles; mehr als 12 Käufe laufen von selbst in Runden weiter." }
  if run then
    panel.bar:SetData({ title = "Kaufen läuft ...", sub = names[1] and ("noch " .. table.concat(names, ", ")) or "" })
  elseif #mp > 0 and cost > 0 then
    if not pick and not buyPick then
      panel.bar:SetData({ itemID = #mp == 1 and mp[1].id or nil, title = "Einkaufen: " .. table.concat(names, ", "),
        sub = ("zusammen %s"):format(ns.Money(cost)) })
    end
    acts[#acts + 1] = { text = ("Alle kaufen (%s)"):format(ns.Money(cost)), onClick = function() ns.Try(MatsClick) end,
      tooltip = tip }
  end
  panel.bar:SetActions(acts)
end

local function Place()
  if not panel then return end
  local st = ns.db.sellWin
  if panel.blizz then
    if panel:Restore() then return end -- moved by hand: stays there
  elseif st and st.point then return end
  panel:ClearAllPoints()
  if MerchantFrame then panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, 0) else panel:SetPoint("CENTER", 0, 100) end
end

function SellClick()
  local plan = Plan()
  local done, sum = 0, 0
  for _, e in ipairs(plan) do
    if done >= MAX_PER_CLICK then break end
    local now = ns.Call(C_Container.GetContainerItemInfo, e.bag, e.slot)
    if type(now) ~= "table" or now.itemID ~= e.id or now.stackCount ~= e.count or now.isLocked then break end
    ns.Prices.Tried(e.bag, e.slot, e.id, e.count)
    ns.Call(C_Container.UseContainerItem, e.bag, e.slot)
    done, sum = done + 1, sum + e.value -- booked by Ledger.lua like a sale by right click
  end
  if done > 0 then ns.Print(("%d Gegenstände verkauft, %s."):format(done, ns.Money(sum, true))) end
  ns.After(0.8, Label)
end

-- (Durchsicht 15.11.2026) the need is counted from the bags, which show a purchase some 100 ms later: a second click in
-- that time bought everything again (a vendor takes nothing back at the price). 1.5 s between two clicks.
-- (Daniel 16.11.2026, Bild beim Händler, 12 Käufe Mild Spices zu je 5: "Wie funktioniert Mats kaufen? ich musste jetzt ein
-- paar Mal klicken") one click buys all: a call takes several bundles of an item sold in fives (the count of items, a
-- multiple of the bundle, up to GetMerchantItemMaxStack, as Blizzard's own split dialog does), and when 12 calls are not
-- enough, the rest follows on its own in rounds 1.5 s apart (the bags show what came first). At the end one line says
-- what was bought. The run stops when the vendor window closes, when nothing is left, or when a round brought nothing.
local matsAt
local ROUND_SEC, MAX_ROUNDS = 1.5, 20
local function Bought()
  if not run then return end
  local parts = {}
  for _, id in ipairs(run.order) do
    parts[#parts + 1] = ("%d× %s"):format(run.got[id], ns.ItemInfo(id) or ("Item " .. id))
  end
  if #parts > 0 then ns.Print(("Beim Händler gekauft: %s (%s)."):format(table.concat(parts, ", "), ns.Money(run.cost))) end
  if run.full then ns.Print("|cffe0524aTaschen voll:|r nicht alles gekauft. Erst herstellen, dann den Rest kaufen.") end
  -- (Daniel 24.11.2026: "bei der anzahl mit runter zählen") a typed count keeps what of it is left; the rows stay at
  -- the rest until the bags show the purchase (lastRun)
  for id, got in pairs(run.got) do
    local f = run.fixed and run.fixed[id]
    if f then visitGot[id] = (visitGot[id] or 0) + math.min(f, got) end
    if buyWant[id] then
      local left = buyWant[id] - got
      buyWant[id] = left > 0 and left or nil
    end
  end
  lastRun = { target = run.target, got = run.got, t = GetTime() }
  ns.After(1.6, Label)
  run = nil
end
-- (Daniel 16.11.2026, "Inventory is full") what the bags take of an item: the free slots (shared by all items of a round)
-- times its stack, and what its part stacks still take
local function Space(id, free)
  local stack = ns.Stack(id) or 20
  local have = ns.Bags()[id] or 0
  local part = have % stack > 0 and (stack - have % stack) or 0
  return free * stack + part, stack
end
local function Round()
  local done, units = 0, 0
  -- (Daniel 16.11.2026, 620 Hot Spices wanted, 480 fitted: the free slots of the reagent bag were counted for them) the
  -- normal bags (one slot of air) and the reagent bag apart; the reagent bag only for what the game calls a reagent
  local freeN, freeR = ns.FreeSplit()
  freeN = math.max(0, freeN - 1)
  -- (Daniel 17.11.2026, 480 Hot Spices bought, 10 slots still free: "ich hätte locker die fehlenden 110 spices kaufen
  -- können") "full" is the state of this round only: a round that hit the 12 purchases while not all fitted stopped the
  -- run, though the free slots took 9 stacks more. The run goes on; the next round counts the bags again and stops when
  -- nothing more fits.
  if run then run.full = false end
  for _, e in ipairs(BuyPlan(run and run.only)) do
    -- (Daniel 17.11.2026, Bild: 400 Mild Spices on the list, 540 bought, "wollte noch mehr") the bags lag behind the
    -- purchases: a later round read the list as if nothing was bought yet. The run keeps what the first round planned
    -- (run.target) and buys only what of it is still missing; an item that came up later is left for the next click.
    if run and run.target then
      local cap = run.target[e.id]
      e.units = cap and math.max(0, math.min(e.units, cap - (run.got[e.id] or 0))) or 0
      e.buys = math.ceil(e.units / e.stack)
    end
    if e.units > 0 then
    local per = math.max(e.stack, math.floor((e.maxStack or e.stack) / e.stack) * e.stack) -- items a call
    local fitsR = ns.FitsReagentBag(e.id)
    local free = freeN + (fitsR and freeR or 0)
    local space, istack = Space(e.id, free)
    local leftU = math.min(e.units, math.floor(space / e.stack) * e.stack)
    if leftU < e.units and run then
      run.full = true
      ns.Fact("matsFull", ("%s: %d von %d, frei normal %d, Reagenzientasche %d (%s)"):format(ns.ItemInfo(e.id) or e.id, leftU, e.units,
        freeN, freeR, fitsR and "passt hinein" or "passt nicht hinein"))
    end
    local used = math.ceil(math.max(0, leftU - (space - free * istack)) / istack)
    if fitsR then local r = math.min(freeR, used) freeR, used = freeR - r, used - r end
    freeN = math.max(0, freeN - used)
    while leftU > 0 and done < MAX_PER_CLICK do
      local n = math.min(leftU, per)
      if e.stack == 1 or n ~= e.stack then ns.Call(BuyMerchantItem, e.index, n) else ns.Call(BuyMerchantItem, e.index) end
      local cost = math.floor((e.price or 0) * n / e.stack + 0.5)
      if ns.Ledger then ns.Ledger.Expect("craft", -cost, n) end
      if ns.RecipeLog then ns.RecipeLog.Bought(e.id, n, cost) end -- (16.11.2026) the mat's price for what it goes into
      done, units, leftU = done + 1, units + n, leftU - n
      if run then
        if not run.got[e.id] then run.got[e.id] = 0 run.order[#run.order + 1] = e.id end
        run.got[e.id], run.cost = run.got[e.id] + n, run.cost + cost
        run.calls = run.calls or {}
        run.calls[e.id] = run.calls[e.id] or {}
        table.insert(run.calls[e.id], { n, cost })
      end
    end
    end
  end
  return done, units
end
-- (Daniel 24.11.2026, Bild Chat: "er schreibt er hätte 760 gekauft, hatte aber nur 640 und dann habe ich noch 120
-- nachkaufen müssen") the run counted its calls, and the vendor does not carry out every call of a round. After the last
-- round the gold says what was really paid (the bags lag, the gold of a purchase not carried out never goes): once it
-- stands still over two looks ROUND_SEC apart and less went than the calls cost, the calls not carried out are taken
-- back (per item what the bags lack of it, never more than the gold kept) and bought again, at most MAX_RETRY times.
-- The line in the chat names what was paid for.
local MAX_RETRY = 3
local Next
local function Money() return ns.Num(ns.Call(GetMoney)) or 0 end
local function TakeBack()
  local short = run.cost - (run.gold0 - Money())
  local bags, any = ns.Bags(), false
  for _, id in ipairs(run.order) do
    local miss = (run.got[id] or 0) - math.max(0, (bags[id] or 0) - (run.have0[id] or 0))
    local calls = run.calls and run.calls[id] or {}
    while miss > 0 and #calls > 0 and calls[#calls][1] <= miss and calls[#calls][2] <= short do
      local c = table.remove(calls)
      miss, short = miss - c[1], short - c[2]
      run.got[id], run.cost = run.got[id] - c[1], run.cost - c[2]
      if ns.Ledger then ns.Ledger.Unexpect("craft", -c[2]) end
      if ns.RecipeLog and ns.RecipeLog.Unbought then ns.RecipeLog.Unbought(id, c[1], c[2]) end
      any = true
    end
  end
  return any
end
local function Verify()
  if not run then return end
  if not (panel and panel:IsShown()) then Bought() return end
  local short = run.cost - (run.gold0 - Money())
  if short <= 0 then Bought() return end
  run.looks = (run.looks or 0) + 1
  if run.short ~= short and run.looks < 4 then run.short = short ns.After(ROUND_SEC, Verify) return end
  run.short, run.looks = nil, nil
  local back = TakeBack()
  ns.Fact("matsShort", ("%s fehlten nach %d Runden, %s"):format(ns.Money(short), run.rounds, back and "nachgekauft" or "nicht zuzuordnen"))
  run.retry = (run.retry or 0) + 1
  if back and run.retry <= MAX_RETRY and run.rounds < MAX_ROUNDS then Next() else Bought() end
end
local function Settled()
  if run and run.gold0 and run.cost > 0 then ns.After(ROUND_SEC, Verify) else Bought() end
end
function Next()
  if not run then return end
  if not (panel and panel:IsShown()) then Bought() return end
  run.rounds = run.rounds + 1
  local done = Round()
  matsAt = GetTime()
  if done >= MAX_PER_CLICK and run.rounds < MAX_ROUNDS then ns.After(ROUND_SEC, Next) else Settled() end
  Label()
end
-- only: a set of ids (the picked row's "Kaufen"), nil: all rows ("Alle kaufen"); the counts of the fields
function MatsClick(only)
  local now = GetTime()
  if run or (matsAt and now - matsAt < ROUND_SEC) then return end
  matsAt = now
  run = { got = {}, order = {}, cost = 0, rounds = 1, target = {}, only = only }
  for _, e in ipairs(BuyPlan(only)) do run.target[e.id] = e.units end
  run.gold0, run.have0 = Money(), {}
  for id, n in pairs(ns.Bags()) do if run.target[id] then run.have0[id] = n end end
  run.fixed = MatsFixed
  local jobsNow = MatsJobs or {}
  local done = Round()
  if done > 0 then
    -- (Daniel 15.11.2026) mats bought for the chosen recipe: a job of the Herstellfenster (once a run)
    local v, Cr = ns.Crafts.sel, ns.Crafts
    -- (16.11.2026) a job there already: this purchase only filled up what its open crafts lacked
    for _, j in ipairs(jobsNow) do
      if Cr.JobAdd and not (Cr.JobLeft and Cr.JobLeft(j[1])) then Cr.JobAdd(j[1], j[2], v and v.r.spell == j[1] and v.mode or nil) end
    end
  end
  if done >= MAX_PER_CLICK then ns.After(ROUND_SEC, Next) else Settled() end
  Label()
  ns.After(0.8, Label)
end
ns.MerchantRun = function() return run end -- (tests)

local function BuildWith(Kit)
  ns.db.sellWin = type(ns.db.sellWin) == "table" and ns.db.sellWin or {}
  panel = Kit.Window("ProfitdonSellFrame", { title = "Profitdon verkaufen", compact = true, store = ns.db.sellWin, width = 400,
    height = 360, min = { 320, 220 }, max = { 800, 900 }, logo = "Interface\\AddOns\\Profitdon\\Media\\portrait",
    onLayout = function(win, w, h)
      if not (win.tbl and win.bar) then return end
      local bh = win.bar:GetHeight() or 40
      win.tbl:ClearAllPoints() win.tbl:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, 0)
      win.tbl:Layout(w, math.max(40, h - bh))
      win.bar:ClearAllPoints() win.bar:SetPoint("BOTTOMLEFT", win.body, "BOTTOMLEFT", 0, 0)
      win.bar:Layout(w)
    end })
  panel.tbl = Kit.Table(panel.body, { columns = { { key = "title", title = "Gegenstand" }, { key = "n", title = "Anzahl", width = 64 },
    { key = "value", title = "Preis", width = 84 } },
    onClick = function(it) if it.buy then selBuy, sel = it.id, nil elseif it.id then sel, selBuy = it.id, nil end Label() end,
    empty = "Nichts zu kaufen oder verkaufen." })
  panel.bar = Kit.ActionBar(panel.body)
  -- (Daniel 08.11.2026: "kein dynamit angezeigt") Kit.Window lays its body out once when it is made, before the table
  -- existed: without this the table kept no size and showed nothing
  panel:Layout()
  panel:Hide()
end

-- (Daniel 15.11.2026, Blizzard-Optik) from Blizzard's templates when the client has them (DonCore Blizz), else the kit
local function Build()
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
  local BK, blizz = ns.LookKit("blizzMain")
  if blizz then
    local ok, err = pcall(BuildWith, BK)
    if ok then return end
    ns.Fact("blizzSell", "Fehler: " .. tostring(err))
    ns.SayLook()
    if panel and panel.Hide then pcall(panel.Hide, panel) end
    panel = nil
  end
  BuildWith(Kit)
end
ns.MerchantReset = function() if panel then panel:Hide() end panel = nil end -- (tests)

ns.MerchantPlan, ns.MerchantSell, ns.MerchantBuyMats = Plan, function() ns.Try(SellClick) end, function() ns.Try(MatsClick) end -- (tests)
ns.MerchantPanel = function() return panel end -- (tests)
ns.MerchantPick = function(id) sel, selBuy = id, nil Label() end -- (tests)
ns.MerchantPickBuy = function(id) selBuy, sel = id, nil Label() end -- (tests)
ns.MerchantBuyRow = function(id) ns.Try(MatsClick, { [id] = true }) end -- (tests)

ns.On("MERCHANT_SHOW", function()
  ns.Try(Learn)
  if not panel then ns.Try(Build) end
  if not panel then return end
  ns.Try(Place)
  panel:Show()
  ns.Try(Label)
end)
ns.On("MERCHANT_UPDATE", function() ns.Try(Learn) end)
ns.On("BAG_UPDATE_DELAYED", function() if panel and panel:IsShown() then ns.WhenIdle("Verkaufsfenster", Label, 0.1) end end)
ns.On("MERCHANT_CLOSED", function() if panel then panel:Hide() end sel, selBuy = nil, nil buyWant = {} visitGot, lastRun = {}, nil end)
