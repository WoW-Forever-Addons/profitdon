local _, ns = ...

---------------------------------------------------------------------------
-- Item tooltips (Daniel 06.11.2026: "kriegen wir da noch einen AH price mit unter im tooltip?", then: "den Tooltip direkt unter
-- Sell Price. Den Händlerpreis braucht Profit dann ja nicht mehr mit ausgeben ... AH, Doppelpunkt, wie viel ... so wie den Sell
-- Price aussehen lassen", with the coin symbols):
--   "AH: 2s 80c"  right under the game's "Sell Price", drawn like it (SetTooltipMoney: gold, silver, copper coins), for the
--                 price of one unit (Shift: "AH (34):" for all in the bags); AH =the cheapest real offer: a search just now, else the last scan, else TSM
--   a green hint only where one is clearly better, or for gear what disenchanting brings ("Entzaubern etwa 45c")
-- Shift: AH after the cut, where the price comes from, the mats of a disenchant with chance and count, the vendor that sells it.
-- Under "Sell Price": TooltipDataProcessor.AddLinePostCall on that line (runs while the tooltip is built, before the item
-- post calls of other addons such as Syndicator's "Inventory"); items without a sell price get the line from the item post call.
-- No hooks. Switch: option "tooltip".
---------------------------------------------------------------------------
local function StackCount(tip, id)
  local owner = tip.GetOwner and tip:GetOwner()
  if type(owner) == "table" and owner.GetBagID and owner.GetID then
    local bag, slot = ns.Call(owner.GetBagID, owner), ns.Call(owner.GetID, owner)
    local info = bag and slot and C_Container and ns.Call(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" and (not id or ns.Num(info.itemID) == id) then return ns.Num(info.stackCount) end
  end
end

-- the AH price of one unit and where it comes from
function ns.AHPrice(id)
  local f = ns.FreshLow and ns.FreshLow(id)
  if f then return f, "Suche eben" end
  local P = ns.Prices
  local st = P.Store()
  if P.Row(nil, id) then
    return P.Low(id), ("Scan vor %d min"):format(math.floor((time() - (st and st.t or time())) / 60))
  end
  local t = P.TSM(id, "DBMinBuyout") or P.TSM(id, "DBMarket")
  if t then return t, "TSM" end
end

-- a money line like the game's "Sell Price": one text line with coin textures, built the way the client builds its own
-- (GameTooltip_OnTooltipAddMoney: MoneyFormatterUtil.FormatMoney with GameTooltipMoneyFormat). Not SetTooltipMoney
-- (Daniel 06.11.2026, screenshot "AH4 0" plus a second "AH: 4s" line and "AddOns are experiencing a large number of errors"
-- on every item hover): the legacy money frame breaks in the Forever client's tooltip.
local function CoinText(copper)
  local U = MoneyFormatterUtil
  if U and U.FormatMoney and GameTooltipMoneyFormat then
    local s = ns.Call(U.FormatMoney, copper, GameTooltipMoneyFormat)
    if type(s) == "string" and s ~= "" then return s end
  end
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  local s = f and ns.Call(f, copper)
  if type(s) == "string" and s ~= "" then return s end
  return ns.Money(copper, true)
end
local function MoneyLine(tip, label, copper)
  tip:AddLine(label .. " " .. CoinText(copper), 1, 1, 1)
end

local function Lines(tip, id)
  if not ns.Opt("tooltip") or (tip ~= GameTooltip and tip ~= ItemRefTooltip) or not id then return end
  local P, D = ns.Prices, ns.Deals
  local sell = P.Sell(id)
  local ah, src = ns.AHPrice(id)
  local g = ns.DE and ns.DE.Group(id)
  -- (21.11.2026, Ruckler) kept per group (Disenchant.lua DE.TipValue), as kept median and trend (History.lua H.Info)
  local de
  if g then if ns.DE.TipValue then de = ns.DE.TipValue(g) else de = ns.DE.Value(g) end end
  -- (Daniel 21.11.2026, Auswahl "Nur anzeigen, nicht rechnen") the median of the price history (own days and the
  -- shipped seed of all our scans) as a grey line, also for an item missing from the newest scan; no sum uses it
  local H = ns.History
  local med, mdays, tr = nil, 0, ""
  if H and H.Info then med, mdays, tr = H.Info(id) end
  -- (Daniel 21.11.2026, Recipe: Potion of Demonslaying without any line, chosen "graue Hinweiszeile") no price from any
  -- source: say so, so it is clear Profitdon runs and only the price is missing
  -- (Daniel 21.11.2026: "bei soulbound den tooltip weg") not for an item that binds when picked up or is a quest item:
  -- it never reaches the AH (GetItemInfo's 14th value, bindType 1 or 4)
  if not ah and not de and not med then
    local GI = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local bind = select(14, ns.Call(GI, id))
    if bind ~= 1 and bind ~= 4 then tip:AddLine("|cff8a8f96AH: keine Angebote bekannt|r") end
    return
  end
  local cut = P.Cut()
  -- (Daniel 06.11.2026, 284 Rough Dynamite in Baganator, chosen "Alles in den Taschen") the AH line counts everything of the
  -- item in the bags ("AH (284):"), an item outside the bags the stack under the mouse; "Sell Price" stays the game's stack
  -- (Daniel 07.11.2026: "standardweise den einzelpreis ... mit shift soll es dann wechseln, dass ich sehe wieviele alle
  -- gegenstände davon, die ich habe wert sind") without Shift every line is for one unit, Shift switches to the whole count
  local shift = IsShiftKeyDown and IsShiftKeyDown()
  local count = 1
  if shift then
    count = (ns.BagCountKept or ns.BagCount)(id)
    if count == 0 then count = StackCount(tip, id) or 1 end
  end
  local label = count > 1 and (" (" .. count .. ")") or ""
  if ah then MoneyLine(tip, "AH" .. label .. ":", ah * count) end
  if med then
    tip:AddLine("|cff8a8f96Median " .. mdays .. (mdays == 1 and " Tag" or " Tage") .. label .. ": " .. ns.Money(med * count, true)
      .. (tr ~= "" and (" (" .. tr .. ")") or "") .. (ah and "" or ", nicht im letzten Scan") .. "|r")
  end
  local net = ah and D.AfterCut(ah, cut)
  -- (Daniel 06.11.2026: "besser im AH weglassen, sondern in grün nur AH und dann in Klammern das, was da steht")
  if de and de > math.max(sell or 0, net or 0) then
    tip:AddLine(("|cff4fd16bEntzaubern etwa %s|r"):format(ns.Money(de * count)))
  elseif net and sell and sell > 0 and net > sell then
    tip:AddLine("|cff4fd16bAH (+" .. ns.Money((net - sell) * count) .. " nach Gebühr)|r")
  elseif net and sell and sell > net then
    tip:AddLine("|cff4fd16bHändler (+" .. ns.Money((sell - net) * count) .. ")|r")
  end
  if not shift then return end
  local G = "|cff8a8f96"
  if sell and sell > 0 then MoneyLine(tip, "Händler" .. label .. ":", sell * count) end
  if net then tip:AddDoubleLine(G .. "AH nach " .. cut .. " % Gebühr" .. label .. "|r", ns.Money(net * count, true) .. " " .. G .. "(" .. (src or "?") .. ")|r") end
  if g then
    for _, l in ipairs(ns.DE.TipLines(g, nil, id)) do
      if type(l) == "table" then tip:AddDoubleLine(G .. l[1] .. "|r", l[2]) else tip:AddLine(G .. l .. "|r") end
    end
  end
  local vp, vs, limited, vname = P.VendorBuy(id)
  if vp then tip:AddDoubleLine(G .. "Beim Händler kaufbar" .. (limited and " (begrenzt)" or "") .. "|r", ns.Money(vp, true) .. ((vs or 1) > 1 and (" / " .. vs) or "") .. " " .. G .. (vname or "") .. "|r") end
end

local function ItemOf(tip, data)
  local id = type(data) == "table" and ns.Num(data.id)
  if id then return id end
  local _, link = ns.Call(tip.GetItem, tip)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- right after the "Sell Price" line; the item post call that follows then leaves it
local function OnSellLine(tip)
  local id = ItemOf(tip)
  if not id then return end
  tip._profitdonDone = id
  Lines(tip, id)
end
local function OnItem(tip, data)
  local id = ItemOf(tip, data)
  local done = tip._profitdonDone
  tip._profitdonDone = nil
  if done and done == id then return end
  Lines(tip, id)
end
ns.ProfitdonTooltip = function(tip, data) tip._profitdonDone = nil OnItem(tip, data) end -- (tests)
ns.ProfitdonSellLine = OnSellLine -- (tests)

ns.OnInit(function()
  local T = TooltipDataProcessor
  if not (T and Enum and Enum.TooltipDataType) then return end
  local L = Enum.TooltipDataLineType
  if T.AddLinePostCall and L and L.SellPrice then
    ns.Call(T.AddLinePostCall, L.SellPrice, function(tip) ns.Try(OnSellLine, tip) end)
    ns.Fact("tooltip", "unter Sell Price (AddLinePostCall)")
  end
  if T.AddTooltipPostCall then
    ns.Call(T.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tip, data) ns.Try(OnItem, tip, data) end)
  end
end)
