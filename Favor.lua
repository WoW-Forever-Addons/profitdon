local _, ns = ...

---------------------------------------------------------------------------
-- Merchant's Favor (08.11.2026, Daniel: "die merchant favor kisten, die droppen random und können im ah gekauft werden";
-- chosen: gold per Favor, crates to buy, Favor measured in the game)
--   a Waylaid Crate (G.crates in Data/Vendor.lua, ForeverDB: crate, level, bundles that fill it) filled with one bundle becomes
--   a sealed crate (Data/Favor.lua, ATT), handed in for Merchant's Favor: ATT's quest reward, or what Profitdon measured
--   (ProfitdonDB.favorSeen[sealed] = { turn-ins, Favor }), the measurement wins
--   per crate: the crate in the AH (ns.AHPrice) plus the cheapest bundle (each mat at its unit price as for crafting:
--   vendor, own craft or AH), divided by the Favor: gold per Favor; the best crate gives the gold value of one Favor, which
--   Skillen uses for recipes at the Favor vendors
--   measuring: a sealed crate leaves the bags and the currency 3402 rises within 5 s (either order)
---------------------------------------------------------------------------
local F = {}
ns.Favor = F
local SEALED_LO, SEALED_HI = 248765, 248779   -- every sealed crate item (ATT: rare and elite ones without a known source)

local function Data() return ns.FAVOR or { sealed = {}, gain = {} } end

-- Favor of a crate: measured average or ATT, and where it comes from ("gemessen", "ATT"); nil when unknown
function F.Gain(crate)
  local sealed = Data().sealed[crate] or crate
  local seen = type(ns.db.favorSeen) == "table" and ns.db.favorSeen[sealed]
  if type(seen) == "table" and (seen[1] or 0) > 0 then return math.floor(seen[2] / seen[1] + 0.5), "gemessen" end
  local g = Data().gain[sealed]
  if g then return g, "ATT" end
end

-- (Daniel 22.11.2026: "und es gibt pro abgabe noch 5s zurück") the turn-in pays money besides the Favor: measured
-- average (ProfitdonDB.favorMoney[sealed] = { turn-ins, copper }, read with GetRewardMoney on the reward page), else
-- 50c per Favor (Daniel's chat, one crate of each kind: 5 Favor 2s 50c, 10 Favor 5s, 15 Favor 7s 50c, 20 Favor 10s)
F.MONEY_PER_FAVOR = 50
F.QUEST_SEALED = { [91899] = 248765, [91900] = 248766, [91901] = 248767, [91904] = 248770, [91905] = 248771, [91906] = 248772 }
function F.Money(crate)
  local sealed = Data().sealed[crate] or crate
  local seen = type(ns.db.favorMoney) == "table" and ns.db.favorMoney[sealed]
  if type(seen) == "table" and (seen[1] or 0) > 0 then return math.floor(seen[2] / seen[1] + 0.5), "gemessen" end
  local g = F.Gain(crate)
  return (g or 0) * F.MONEY_PER_FAVOR, "50c je Gunst"
end

function F.Held()
  local c = C_CurrencyInfo and ns.Call(C_CurrencyInfo.GetCurrencyInfo, Data().currency or 3402)
  return type(c) == "table" and ns.Num(c.quantity) or nil
end

-- the cheapest bundle of a crate: cost, item, count, where the mats come from
function F.Bundle(bundles)
  local best
  for i = 1, #bundles, 2 do
    local unit, src = ns.Crafts.ReagentUnit(bundles[i])
    if unit then
      local cost = unit * bundles[i + 1]
      if not best or cost < best[1] then best = { cost, bundles[i], bundles[i + 1], src } end
    end
  end
  if best then return best[1], best[2], best[3], best[4] end
end

-- one entry per crate: { id, level, crate (AH), crateSrc, bundle (cost), bid, bn, bsrc, total, gain, gainSrc, per,
-- maxUnit (buying: 125 % of the AH price, at least 2c more) }; cheapest Favor first, crates without a price or Favor last
function F.Rows()
  local out = {}
  local Cr = ns.Crafts
  local outer = Cr.cache   -- Skillen asks inside its own cached pass: keep that cache
  Cr.cache = outer or {}
  local ok, err = pcall(function()
    for _, c in ipairs(ns.G and ns.G.crates or {}) do
      local e = { id = c[1], level = c[2] }
      e.crate, e.crateSrc = ns.AHPrice(c[1])
      e.bundle, e.bid, e.bn, e.bsrc = F.Bundle(c[3] or {})
      e.gain, e.gainSrc = F.Gain(c[1])
      if e.crate and e.bundle then e.total = e.crate + e.bundle end
      e.money, e.moneySrc = F.Money(c[1])
      if e.total and e.gain and e.gain > 0 then e.per = math.max(0, e.total - e.money) / e.gain end
      if e.crate then e.maxUnit = math.max(e.crate + 2, math.floor(e.crate * 1.25)) end
      out[#out + 1] = e
    end
  end)
  Cr.cache = outer
  if not ok then error(err, 0) end
  table.sort(out, function(a, b)
    if (a.per == nil) ~= (b.per == nil) then return a.per ~= nil end
    if a.per and a.per ~= b.per then return a.per < b.per end
    if (a.bundle == nil) ~= (b.bundle == nil) then return a.bundle ~= nil end
    return a.id < b.id
  end)
  return out
end

---------------------------------------------------------------------------
-- (Daniel 13.11.2026: "wäre es hier nicht sinnvoll auch auf die einkaufsliste zu packen? also einmal die crate dann die mats
-- dazu, entweder fertige mats oder zum herstellen, je nachdem was günstiger ist") a crate on the shopping list: a recipe
-- of its own for Crafts.ShoppingList, the sealed crate made of the Waylaid Crate and its cheapest bundle (that bundle's
-- item comes made or bought, whichever is cheaper, as every mat of the list). ProfitdonDB.favorPlan = { { crate, n } }
---------------------------------------------------------------------------
local function FavorPlan()
  ns.db.favorPlan = type(ns.db.favorPlan) == "table" and ns.db.favorPlan or {}
  return ns.db.favorPlan
end
function F.InPlan(crate)
  for i, p in ipairs(FavorPlan()) do if p[1] == crate then return p, i end end
end
function F.Add(crate, n)
  n = math.max(1, math.floor(tonumber(n) or 1))
  local p = F.InPlan(crate)
  if p then p[2] = n else table.insert(FavorPlan(), { crate, n }) end
end
function F.Remove(crate)
  local _, i = F.InPlan(crate)
  if i then table.remove(FavorPlan(), i) end
end
-- the recipe of a crate: spell "favor:<crate>", item the sealed crate, reagents the crate and its cheapest bundle
function F.Recipe(crate)
  for _, c in ipairs(ns.G and ns.G.crates or {}) do
    if c[1] == crate then
      local _, bid, bn = F.Bundle(c[3] or {})
      if not bid and c[3] and c[3][1] then bid, bn = c[3][1], c[3][2] end
      local reag = { { crate, 1 } }
      if bid then reag[2] = { bid, bn } end
      return { spell = "favor:" .. crate, item = Data().sealed[crate] or crate, reag = reag, count = 1, favor = crate }
    end
  end
end
-- the entries for Crafts.ShoppingList: { r, runs, favor }
function F.PlanEntries()
  local out = {}
  for _, p in ipairs(FavorPlan()) do
    local r = F.Recipe(p[1])
    if r then out[#out + 1] = { r = r, runs = p[2], favor = p[1] } end
  end
  return out
end

-- gold for one Favor: the cheapest crate with an AH price, nil without one
local memo
function F.GoldPerFavor()
  local t = GetTime()
  if memo and t - memo.t < 5 then return memo.v, memo.best end
  local best
  for _, e in ipairs(F.Rows()) do if e.per and (not best or e.per < best.per) then best = e end end
  memo = { t = t, v = best and math.floor(best.per + 0.5) or nil, best = best }
  return memo.v, memo.best
end
function F.Forget() memo = nil end

---------------------------------------------------------------------------
-- Measuring the Favor of a turn-in
---------------------------------------------------------------------------
local held, lost, gained = nil, {}, nil

-- (22.11.2026, Ruckler, DonMonitor report: BAG_UPDATE_DELAYED Favor.lua:185 avg 32 ms, max 52 ms, with every loot and
-- every craft) the sealed crates were counted with ns.BagCount once per crate ID: 15 walks through all bag slots on each
-- bag change. One walk now, only the slot's item ID is looked at (GetContainerItemID where the client has it, no table
-- per slot); the slot's count is read for a sealed crate only.
local function Count()
  local t = {}
  local C = C_Container
  if not C then return t end
  local idAt = C.GetContainerItemID
  for bag = 0, ns.LASTBAG or 4 do
    local slots = ns.Num(ns.Call(C.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local id, info
      if idAt then id = ns.Num(ns.Call(idAt, bag, slot))
      else
        info = ns.Call(C.GetContainerItemInfo, bag, slot)
        id = type(info) == "table" and ns.Num(info.itemID) or nil
      end
      if id and id >= SEALED_LO and id <= SEALED_HI then
        info = info or ns.Call(C.GetContainerItemInfo, bag, slot)
        t[id] = (t[id] or 0) + (type(info) == "table" and ns.Num(info.stackCount) or 1)
      end
    end
  end
  return t
end
F._Count = Count -- (tests)

local function Match()
  if not gained or #lost == 0 then return end
  local now = GetTime()
  for i, l in ipairs(lost) do
    if math.abs(l.t - gained.t) <= 5 then
      ns.db.favorSeen = type(ns.db.favorSeen) == "table" and ns.db.favorSeen or {}
      local s = ns.db.favorSeen[l.id] or { 0, 0 }
      s[1], s[2] = s[1] + 1, s[2] + gained.n
      ns.db.favorSeen[l.id] = s
      ns.Fact("favorLast", ("%d Gunst für %d"):format(gained.n, l.id))
      table.remove(lost, i)
      gained = nil
      return
    end
  end
  if now - gained.t > 5 then gained = nil end
end

-- (22.11.2026, Ruckler) in a fight the bags are not counted (loot changes them all the time, no crate is handed in
-- there): once after it (PLAYER_REGEN_ENABLED). While a Favor gain waits for its crate the count runs all the same.
local waiting
function F.OnBags()
  if gained and GetTime() - gained.t > 5 then gained = nil end -- too old for any crate that leaves from now on (Match: 5 s)
  if not gained and ns.Call(InCombatLockdown) then waiting = true return end
  waiting = nil
  local now = Count()
  if held then
    for id, n in pairs(held) do
      if (now[id] or 0) < n then lost[#lost + 1] = { id = id, t = GetTime() } end
    end
  end
  held = now
  while lost[1] and GetTime() - lost[1].t > 10 do table.remove(lost, 1) end
  Match()
end

function F.OnCurrency(id, change)
  if ns.Num(id) ~= (Data().currency or 3402) or (ns.Num(change) or 0) <= 0 then return end
  gained = { n = ns.Num(change), t = GetTime() }
  Match()
  if gained then ns.After(1, F.OnBags) end
end

-- (22.11.2026) the handlers run inside ns.Try already (Core.lua): a second ns.Try around them put every slow call into
-- the slow-call log twice, the second time without a place ("call ?")
ns.On("PLAYER_LOGIN", function() ns.After(5, function() held = Count() end) end)
ns.On("BAG_UPDATE_DELAYED", function() F.OnBags() end)
ns.On("PLAYER_REGEN_ENABLED", function() if waiting then F.OnBags() end end)
ns.On("CURRENCY_DISPLAY_UPDATE", function(_, id, _, change) F.OnCurrency(id, change) end)

---------------------------------------------------------------------------
-- (Daniel 22.11.2026, Bild Marcy Baker <Inventory Intake>: "crates abgeben derzeit muss ich quest npc anklicken dann das
-- im bild, um eine kiste abzugeben, können wir das für die crates automatisieren?") the crate turn-ins go by themselves:
-- the NPC's list (gossip or quest greeting) picks a completable crate quest, the progress page completes it, the reward
-- page takes the reward. Shift held: nothing happens. Option autoCrate. One right-click on the NPC per crate stays: the
-- game closes the window after each turn-in and opening it again is protected (InteractUnit).
--   quests (ATT, waylaid crates.lua): A Sealed Crate 91899-91901 and 91904-91906, Crate Return 93862,
--   Shipping Label 98247 (A) and 98248 (H)
---------------------------------------------------------------------------
F.TURNIN = { [91899] = true, [91900] = true, [91901] = true, [91904] = true, [91905] = true, [91906] = true,
  [93862] = true, [98247] = true, [98248] = true }
F.TITLES = { ["A Sealed Crate"] = true, ["Crate Return"] = true, ["Shipping Label"] = true }

local function AutoOn()
  if ns.Opt("autoCrate") == false then return false end
  return not (IsShiftKeyDown and ns.Call(IsShiftKeyDown))
end

-- (22.11.2026, Daniel: "scheint nicht zu funktionieren"; in his picture "A Sealed Crate" carries a yellow "!") the crate
-- quest is offered (available), not in the log: it is accepted at the NPC and completes at once. So the lists take an
-- offered crate quest as well as a completable one, QUEST_DETAIL accepts it, and every step also knows the quest by its
-- title (in case Forever's IDs differ from ATT's). What it saw goes to /profit diag (crateAuto).
local function IsCrate(id, title)
  return (id and F.TURNIN[id]) or (title and F.TITLES[title]) or false
end
local function Note(v) ns.Fact("crateAuto", v) end

-- the NPC's gossip list: a completable or an offered crate quest
function F.OnGossip()
  if not AutoOn() then return end
  local G = C_GossipInfo
  if not G then return end
  local act = G.GetActiveQuests and ns.Call(G.GetActiveQuests)
  for _, q in ipairs(type(act) == "table" and act or {}) do
    local id = ns.Num(q.questID)
    if IsCrate(id, q.title) and q.isComplete then
      Note("Gossip: abgeben " .. tostring(id or q.title))
      ns.Call(G.SelectActiveQuest, id)
      return id
    end
  end
  local av = G.GetAvailableQuests and ns.Call(G.GetAvailableQuests)
  for _, q in ipairs(type(av) == "table" and av or {}) do
    local id = ns.Num(q.questID)
    if IsCrate(id, q.title) then
      Note("Gossip: annehmen " .. tostring(id or q.title))
      ns.Call(G.SelectAvailableQuest, id)
      return id
    end
  end
  Note(("Gossip: keine Kistenquest (%d laufend, %d angeboten)"):format(type(act) == "table" and #act or 0, type(av) == "table" and #av or 0))
end

-- the quest greeting (the window in Daniel's picture): a completable or an offered crate quest
function F.OnGreeting()
  if not AutoOn() then return end
  local n = GetNumActiveQuests and ns.Num(ns.Call(GetNumActiveQuests)) or 0
  for i = 1, n do
    local id = GetActiveQuestID and ns.Num(ns.Call(GetActiveQuestID, i))
    local title, done = nil, nil
    if GetActiveTitle then title, done = ns.Call(GetActiveTitle, i) end
    if IsCrate(id, title) and done then
      Note("Gruß: abgeben " .. tostring(id or title))
      ns.Call(SelectActiveQuest, i)
      return id or title
    end
  end
  local m = GetNumAvailableQuests and ns.Num(ns.Call(GetNumAvailableQuests)) or 0
  for i = 1, m do
    local id = GetAvailableQuestInfo and ns.Num(select(5, ns.Call(GetAvailableQuestInfo, i)))
    local title = GetAvailableTitle and ns.Call(GetAvailableTitle, i)
    if IsCrate(id, title) then
      Note("Gruß: annehmen " .. tostring(id or title))
      ns.Call(SelectAvailableQuest, i)
      return id or title
    end
  end
  Note(("Gruß: keine Kistenquest (%d laufend, %d angeboten)"):format(n, m))
end

local function ThisQuest()
  local id = GetQuestID and ns.Num(ns.Call(GetQuestID))
  local title = GetTitleText and ns.Call(GetTitleText)
  if id and F.TURNIN[id] then return id end
  if title and F.TITLES[title] then return title end
end

-- the offer of a crate quest: accept it
function F.OnDetail()
  if not AutoOn() then return end
  local id = ThisQuest()
  if not id then return end
  Note("annehmen " .. tostring(id))
  ns.Call(AcceptQuest)
  return id
end

function F.OnProgress()
  if not AutoOn() then return end
  local id = ThisQuest()
  if id and IsQuestCompletable and ns.Call(IsQuestCompletable) then
    Note("abschließen " .. tostring(id))
    ns.Call(CompleteQuest)
    return id
  end
end

-- the reward: only without a choice between items (the crates give Merchant's Favor)
function F.OnReward()
  if not AutoOn() then return end
  local id = ThisQuest()
  if not id then return end
  local choices = GetNumQuestChoices and ns.Num(ns.Call(GetNumQuestChoices)) or 0
  if choices > 1 then return end
  Note("Belohnung " .. tostring(id))
  local sealed = type(id) == "number" and F.QUEST_SEALED[id]
  local money = sealed and GetRewardMoney and ns.Num(ns.Call(GetRewardMoney))
  if money then
    ns.db.favorMoney = type(ns.db.favorMoney) == "table" and ns.db.favorMoney or {}
    local m = ns.db.favorMoney[sealed] or { 0, 0 }
    m[1], m[2] = m[1] + 1, m[2] + money
    ns.db.favorMoney[sealed] = m
  end
  ns.Call(GetQuestReward, choices == 1 and 1 or nil)
  return id
end

ns.On("GOSSIP_SHOW", function() F.OnGossip() end)
ns.On("QUEST_GREETING", function() F.OnGreeting() end)
ns.On("QUEST_DETAIL", function() F.OnDetail() end)
ns.On("QUEST_PROGRESS", function() F.OnProgress() end)
ns.On("QUEST_COMPLETE", function() F.OnReward() end)
