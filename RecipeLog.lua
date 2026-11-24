local _, ns = ...

---------------------------------------------------------------------------
-- (Daniel 16.11.2026: "kannst du gucken was das tasty omelett nach einkauf gebracht hat?"; the report booked only a sum a
-- day and method; chosen "Ja, einbauen") what each product brought, written down as it happens:
--   * a mat bought (AH or vendor) goes into ProfitdonDB.basis[item] = { q, c, t }: units there and what they cost
--     together. What was farmed or lay in the bags before costs nothing.
--   * a craft takes its mats out of the basis at their average price; that is the craft's cost. What it makes goes into
--     the basis of the product with that cost, so a reagent made on the way (powder for dynamite) carries its cost on.
--   * a product sold (vendor, AH invoice) takes its units out of the basis: the cost of what was sold.
-- Per day and product: ProfitdonDB.rlog[day][item] = { casts, units, cost, sold, revenue, cost of the sold }.
-- Account wide (mats bought by one character and made by another count), days older than 400 go.
---------------------------------------------------------------------------
local RL = {}
ns.RecipeLog = RL
RL.BASIS_DAYS = 30 -- a basis not touched for so long is forgotten (the units went another way)

local function Day() return ns.Report and ns.Report.Day and ns.Report.Day() or math.floor(time() / 86400) end

local function Basis(id, make)
  if not ns.db then return nil end
  ns.db.basis = type(ns.db.basis) == "table" and ns.db.basis or {}
  local b = ns.db.basis[id]
  if type(b) == "table" and time() - (b.t or 0) > RL.BASIS_DAYS * 86400 then b = nil ns.db.basis[id] = nil end
  if type(b) ~= "table" and make then b = { q = 0, c = 0, t = time() } ns.db.basis[id] = b end
  return type(b) == "table" and b or nil
end

local function Row(item)
  ns.db.rlog = type(ns.db.rlog) == "table" and ns.db.rlog or {}
  local d = Day()
  local day = ns.db.rlog[d]
  if type(day) ~= "table" then
    day = {}
    ns.db.rlog[d] = day
    for old in pairs(ns.db.rlog) do if d - old > 400 then ns.db.rlog[old] = nil end end
  end
  local r = day[item]
  if type(r) ~= "table" then r = { 0, 0, 0, 0, 0, 0 } day[item] = r end
  return r
end

-- n units out of the basis at their average price: what they cost
local function Take(id, n)
  local b = Basis(id)
  if not b or b.q <= 0 or n <= 0 then return 0 end
  local take = math.min(n, b.q)
  local cost = b.c * take / b.q
  b.q, b.c, b.t = b.q - take, b.c - cost, time()
  if b.q <= 0 then ns.db.basis[id] = nil end
  return cost
end

-- is the item part of a recipe in the data (a mat or a product)? Only those are kept.
local parts
local function IsPart(id)
  if not parts then
    parts = {}
    local Cr = ns.Crafts
    for spell in pairs(ns.CRAFTS or {}) do
      local r = Cr and Cr.Recipe(spell)
      if r then
        if r.item and r.item > 0 then parts[r.item] = true end
        for _, g in ipairs(r.reag or {}) do parts[g[1]] = true end
      end
    end
  end
  return parts[id] or false
end

function RL.Bought(id, qty, cost)
  id, qty, cost = ns.Num(id), ns.Num(qty), ns.Num(cost)
  if not (ns.db and id and qty and cost and qty > 0 and cost >= 0 and IsPart(id)) then return end
  local b = Basis(id, true)
  b.q, b.c, b.t = b.q + qty, b.c + cost, time()
end

-- (24.11.2026, Merchant.lua TakeBack) a purchase counted that the vendor did not carry out
function RL.Unbought(id, qty, cost)
  id, qty, cost = ns.Num(id), ns.Num(qty), ns.Num(cost)
  if not (ns.db and id and qty and cost and qty > 0 and IsPart(id)) then return end
  local b = Basis(id, true)
  b.q, b.c = math.max(0, b.q - qty), math.max(0, b.c - cost)
end

local pending, lastCast = {}, {}
function RL._Reset() parts, pending, lastCast = nil, {}, {} end -- (tests)
function RL.Cast(spell)
  local r = ns.Crafts and ns.Crafts.Recipe(spell)
  if not (ns.db and r and r.item and r.item > 0 and #r.reag > 0) then return end
  local cost = 0
  for _, g in ipairs(r.reag) do cost = cost + Take(g[1], g[2]) end
  local row = Row(r.item)
  row[1], row[3] = row[1] + 1, row[3] + cost
  pending[r.item] = (pending[r.item] or 0) + cost
  lastCast[r.item] = GetTime()
end
-- the game's "You create" line of a craft just cast: the units, with the craft's cost into the product's basis
function RL.Created(item, n)
  item, n = ns.Num(item), ns.Num(n)
  if not (ns.db and item and n and n > 0 and lastCast[item] and GetTime() - lastCast[item] < 10) then return end
  local row = Row(item)
  row[2] = row[2] + n
  local b = Basis(item, true)
  b.q, b.c, b.t = b.q + n, b.c + (pending[item] or 0), time()
  pending[item] = nil
end

-- a product sold (qty < 0: bought back at the vendor)
function RL.Sold(id, qty, revenue)
  id, qty, revenue = ns.Num(id), tonumber(qty), tonumber(revenue) -- both below zero for a buyback
  if not (ns.db and id and qty and revenue and qty == qty and revenue == revenue and qty ~= 0 and IsPart(id)) then return end
  local row = Row(id)
  if qty > 0 then
    row[4], row[5], row[6] = row[4] + qty, row[5] + revenue, row[6] + Take(id, qty)
  else
    -- back in the bags: at the average cost of what was sold today
    local each = row[4] > 0 and row[6] / row[4] or 0
    local n = -qty
    row[4], row[5], row[6] = row[4] - n, row[5] + revenue, row[6] - each * n
    local b = Basis(id, true)
    b.q, b.c, b.t = b.q + n, b.c + each * n, time()
  end
end

-- per product over the last "days" days (nil: all, 0: today), the best profit first:
-- { id, casts, units, cost, sold, rev, cogs, profit (of the sold), left (made and not sold), leftCost }
function RL.Rows(days)
  local out, by = {}, {}
  local today = Day()
  for d, day in pairs(ns.db and type(ns.db.rlog) == "table" and ns.db.rlog or {}) do
    if type(day) == "table" and (not days or today - d <= days) then
      for id, r in pairs(day) do
        local e = by[id]
        if not e then e = { id = id, casts = 0, units = 0, cost = 0, sold = 0, rev = 0, cogs = 0 } by[id] = e out[#out + 1] = e end
        e.casts, e.units, e.cost = e.casts + (r[1] or 0), e.units + (r[2] or 0), e.cost + (r[3] or 0)
        e.sold, e.rev, e.cogs = e.sold + (r[4] or 0), e.rev + (r[5] or 0), e.cogs + (r[6] or 0)
      end
    end
  end
  for _, e in ipairs(out) do
    e.cost, e.cogs = math.floor(e.cost + 0.5), math.floor(e.cogs + 0.5)
    e.profit = e.rev - e.cogs
    e.left = math.max(0, e.units - e.sold)
    e.leftCost = math.max(0, e.cost - e.cogs)
  end
  table.sort(out, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return a.id < b.id end)
  return out
end

-- one line of text per product
function RL.Text(e)
  local name = ns.ItemInfo(e.id) or ("Item " .. e.id)
  local t = name .. ": "
  if e.casts > 0 then t = t .. ("%d× hergestellt (%d Stück), Mats %s"):format(e.casts, e.units, ns.Money(e.cost)) end
  if e.sold > 0 then
    t = t .. (e.casts > 0 and "; " or "") .. ("verkauft %d für %s, Gewinn %s%s"):format(e.sold, ns.Money(e.rev), e.profit >= 0 and "+" or "-", ns.Money(math.abs(e.profit)))
  end
  if e.casts > 0 and e.left > 0 then t = t .. ("; %d noch nicht verkauft"):format(e.left) end
  return t
end
