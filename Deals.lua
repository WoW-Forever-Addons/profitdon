local _, ns = ...

---------------------------------------------------------------------------
-- The arithmetic, pure functions (from Golddon's Deals.lua, only what Profitdon needs). All amounts in copper.
-- The buyer pays no fee; the seller loses the AH cut; the deposit comes back when the item sells; a vendor buys at the
-- item's sell price, any amount, no fee.
---------------------------------------------------------------------------
local D = {}
ns.Deals = D

local function opt(k, o) o = o or (ns.db and ns.db.opt) or ns.DEFAULTS return o[k] or ns.DEFAULTS[k] end

-- enough profit: at least minProfit copper and minProfitPct of the money spent
function D.Worth(profit, spent, o)
  if not profit or profit < opt("minProfit", o) then return false end
  if spent and spent > 0 and profit * 100 < spent * opt("minProfitPct", o) then return false end
  return true
end

function D.AfterCut(price, cutPct) return math.floor(price * (100 - cutPct) / 100) end

-- The deposit of a posting (FOREVER_FACTS.md "Auktionshaus").
--   share of the vendor price by run time, seen in the game 06.11.2026 (Daniel's pictures and invoice: 60 Rough Dynamite,
--     vendor 30c, 8 h, deposit 3s 60c): 5 % for 2 h, 20 % for 8 h, 60 % for 24 h, the classic steps. Another run time
--     falls back to depositPct per 12 hours.
--   floor: 1 copper (Daniel 14.11.2026: "Mindestbetrag von 1s soll laut patchnotes weg sein"; Blizzard's hotfix of
--     10.11.2026 lowered the minimum deposit from 1 silver to 1 copper)
--   measured (Daniel 14.11.2026: "Die einstellgebühren sollten doch schon längst in profitdon da sein"): the game names
--     the exact deposit of every posting (Post.lua, CalculateItemDeposit); each one is kept, ProfitdonDB.depSeen[hours] =
--     { deposits, vendor value, postings }. From D.DEP_MIN postings of a run time on, the measured share wins over the
--     steps; another run time is scaled by the steps.
D.DEP_STEP = { [2] = 5, [8] = 20, [24] = 60 }
D.DEP_MIN = 3
local function StepPct(hours, o) return D.DEP_STEP[hours] or opt("depositPct", o) * hours / 12 end
-- (Durchsicht der Rechnungen 15.11.2026) two things kept the measurement honest:
--   the floor: a posting whose deposit by the steps is under 20 copper is not measured (three single pieces of 1c vendor
--     price, deposit 1c each, made the share 100 % instead of 5 %, scaled to 24 h 1200 %)
--   the neutral auction house has its own measurements (key "N" .. hours): its deposit may differ, and its postings
--     no longer shift the share of the faction's houses
local function SeenKey(hours)
  local P = ns.Prices
  if P and P.AtNeutral and P.AtNeutral() then return "N" .. hours end
  return hours
end
function D.NoteDeposit(sell, qty, hours, deposit)
  if not (ns.db and sell and sell > 0 and qty and qty > 0 and hours and deposit and deposit > 0) then return end
  if sell * qty * StepPct(hours) / 100 < 20 then return end
  local s = ns.db.depSeen or {}
  ns.db.depSeen = s
  local k = SeenKey(hours)
  local e = s[k] or { 0, 0, 0 }
  s[k] = e
  e[1], e[2], e[3] = e[1] + deposit, e[2] + sell * qty, e[3] + 1
end
-- the measured share of the vendor price for a run time: share, postings behind it, true when scaled from another run time
function D.DepositSeen(hours)
  local s = ns.db and ns.db.depSeen
  if type(s) ~= "table" then return nil end
  local neutral = type(SeenKey(hours)) == "string"
  local e = s[SeenKey(hours)]
  if type(e) == "table" and e[3] >= D.DEP_MIN and e[2] > 0 then return e[1] / e[2], e[3], false end
  local best, bh
  for h, x in pairs(s) do
    local hh = h
    if neutral then hh = type(h) == "string" and tonumber(h:match("^N(%d+)$")) or nil
    elseif type(h) ~= "number" then hh = nil end
    if hh and type(x) == "table" and x[3] >= D.DEP_MIN and x[2] > 0 and (not best or x[3] > best[3]) then best, bh = x, hh end
  end
  if best then return best[1] / best[2] * (StepPct(hours) / StepPct(bh)), best[3], true end
end
function D.Deposit(sell, count, hours, o)
  hours = hours or 12
  local base = (sell or 0) * (count or 1)
  if base <= 0 then return 0 end
  local share = not o and D.DepositSeen(hours)
  return math.max(1, math.floor(base * (share or StepPct(hours, o) / 100) + 0.5))
end

-- return on investment in whole percent ("ROI"), nil without a cost
function D.ROI(profit, cost)
  if not (profit and cost and cost > 0) then return nil end
  return math.floor(profit * 100 / cost + 0.5)
end

-- buyout below what the vendor pays: buy, sell to the vendor
function D.VendorFlip(count, buyout, sell, o)
  if not (count and count > 0 and buyout and buyout > 0 and sell and sell > 0) then return nil end
  local ret = sell * count
  local profit = ret - buyout
  if not D.Worth(profit, buyout, o) then return nil end
  return { cost = buyout, ret = ret, profit = profit }
end

-- an item bought to disenchant: value = expected mats after the cut
function D.DEFlip(buyout, value, o)
  if not (buyout and buyout > 0 and value and value > 0) then return nil end
  local profit = value - buyout
  if not D.Worth(profit, buyout, o) then return nil end
  return { cost = buyout, ret = value, profit = profit }
end

-- the cheapest offer that is real: cheap single offers far under the next are passed over (Golddon 04.11.2026)
function D.LowOffer(sorted, total)
  if #sorted == 0 then return nil end
  total = total or 0
  if total <= 0 then for _, e in ipairs(sorted) do total = total + (e[2] or 1) end end
  local skipped, k = 0, 1
  while k < #sorted and k <= 3 do
    local e, nxt = sorted[k], sorted[k + 1]
    if e[1] * 2 < nxt[1] and (skipped + (e[2] or 1)) * 10 <= total then
      skipped = skipped + (e[2] or 1)
      k = k + 1
    else break end
  end
  return sorted[k][1]
end

function D.Median(list)
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local total = 0
  for _, e in ipairs(list) do total = total + e[2] end
  local half, run = total / 2, 0
  for _, e in ipairs(list) do
    run = run + e[2]
    if run >= half then return e[1] end
  end
  return list[#list][1]
end

-- commodity search results (ascending unit price): how many units can be bought at or under maxUnit, for how much
function D.CommodityTake(results, maxUnit, spendCap, qtyCap)
  local qty, total = 0, 0
  for _, r in ipairs(results) do
    if not (r.unitPrice and r.unitPrice <= maxUnit) then break end
    local n = r.quantity or 0
    if spendCap and total + n * r.unitPrice > spendCap then n = math.floor((spendCap - total) / r.unitPrice) end
    if qtyCap and qty + n > qtyCap then n = qtyCap - qty end
    if n <= 0 then break end
    qty, total = qty + n, total + n * r.unitPrice
  end
  return qty, total
end
