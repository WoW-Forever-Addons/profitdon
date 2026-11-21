local _, ns = ...

---------------------------------------------------------------------------
-- Disenchanting (PROFITDON_PLAN.md "Entzauberungsdaten", Daniel 06.11.2026: "Wichtig ist, dass wir wissen, was raus kommt
-- bei der Entzauberung"):
--   * the group of an item: CMaNGOS item_template.DisenchantID (Data/Disenchant.lua), for items CMaNGOS lacks (new Forever
--     items) the rule by quality, weapon or armour and item level from GetItemInfo (DE.rule, bands of 5 levels)
--   * the mats of a group with chance and count (CMaNGOS, a chance 0 is the rest of the roll), mixed with the own rolls
--     of the group: the table counts like "deMinRolls" own rolls (15.11.2026, before: replaced at that number)
--   * expected value of one disenchant = sum of chance x mean count x what the mat brings at the AH after the cut
--   * every own disenchant through Profitdon's bag button is written down: the item's group, then the loot
--   * the bag button: a secure action button (Blizzard rule: one click per item) with "/cast Disenchant" "/use bag slot"
-- Saved: ProfitdonDB.deStats[group] = { n = disenchants, m = { [mat] = { hits, units, min, max } } }
---------------------------------------------------------------------------
local DE = ns.DE or {}
ns.DE = DE
local SPELL = 13262 -- Disenchant
DE.SPELL = SPELL

-- (Faustregel, im Spiel prüfen) enchanting skill an item of the group needs: classic bands of 5 item levels
local SKILL = {}
do
  local g = { 1, 1, 25, 50, 75, 100, 125, 150, 175, 200, 225 }
  for i, s in ipairs(g) do SKILL[i] = s SKILL[20 + i] = s end
  local b = { 25, 50, 75, 100, 125, 150, 175, 200, 225, 275 }
  for i, s in ipairs(b) do SKILL[40 + i] = s end
  local e = { 225, 225, 250, 275, 300 }
  for i, s in ipairs(e) do SKILL[60 + i] = s end
end
function DE.Skill(group) return group and SKILL[group] end

-- group of an item, and where it comes from ("data", "rule"); nil when it gives nothing or is not known yet
function DE.Group(id)
  if not id then return nil end
  local g = DE.items and DE.items[id]
  if g then if g > 0 then return g, "data" end return nil, "none" end
  local _, _, quality, _, _, _, class, level = ns.ItemInfo(id)
  if not quality then return nil, "wait" end
  if class == nil then class = ns.ItemClass(id) end
  if not (quality >= 2 and quality <= 4 and (class == 2 or class == 4) and level) then return nil, "none" end
  local r = DE.rule and DE.rule[quality .. (class == 2 and "W" or "A")]
  if not r then return nil, "none" end
  for k = 1, #r, 2 do if level <= r[k] then return r[k + 1], "rule" end end
  return r[#r], "rule"
end

local function Stats(group)
  local s = ns.db and ns.db.deStats and ns.db.deStats[group]
  return type(s) == "table" and s or nil
end

-- the mats of a group: { { id, chance (percent), min, max, avg } }, source text, measured flag
-- (Daniel 15.11.2026, Durchsicht der Rechnungen: "Mischen") the table and the own rolls are mixed, no hard change at a
-- number of rolls any more (at 20 rolls a shard of 5 % was missing in a third of the cases and counted double in a
-- quarter). The table counts like K own rolls (option deMinRolls, 50): chance = (table chance x K + hits x 100) /
-- (K + n), the units of a roll the same way; a mat only the own rolls know starts from 0, one the rolls never gave
-- fades. The chances still add up to 100. After some hundred rolls the own rates stand nearly alone.
-- (Daniel 16.11.2026, Bild: Bright Sphere mit 75 % Greater Astral Essence angesagt, 17 eigene Würfe alle Soul Dust, "kam am
-- ende ganz was anderes raus ... das kostet natürlich jetzt echt geld") how badly the own rolls contradict a table: the
-- G statistic of the rolls against the table's chances (a mat the table lacks counts as 0.5 %). About 2 x the log of how
-- many times likelier the own rates are than the table's.
local function Misfit(raw, s)
  local n = s and (s.n or 0) or 0
  if n <= 0 or not raw then return 0 end
  local p = {}
  for k = 1, #raw, 4 do p[raw[k]] = raw[k + 1] / 100 end
  local g = 0
  for id, m in pairs(s.m or {}) do
    local h = m[1] or 0
    if h > 0 then g = g + 2 * h * math.log(h / (n * math.max(p[id] or 0, 0.005))) end
  end
  return g
end
DE.Misfit = Misfit -- (tests)
-- above this the table is taken as wrong for the group: the own rolls alone count (the table like 2 rolls, so a mat not
-- rolled yet does not vanish at once). 20: odds of about 1 to 20000 that the table is right.
DE.MISFIT = 20

function DE.Mats(group)
  local raw = DE.groups and DE.groups[group]
  if not raw then return {}, nil end
  local s = Stats(group)
  local n = s and (s.n or 0) or 0
  local K = math.max(1, tonumber(ns.Opt("deMinRolls")) or 50)
  local wrong = n >= 5 and Misfit(raw, s) > DE.MISFIT
  if wrong then K = 2 end
  local out = {}
  if n > 0 then
    local t, order = {}, {}
    for k = 1, #raw, 4 do t[raw[k]] = { c = raw[k + 1], mn = raw[k + 2], mx = raw[k + 3] } order[#order + 1] = raw[k] end
    for id in pairs(s.m or {}) do if not t[id] then t[id] = { c = 0 } order[#order + 1] = id end end
    for _, id in ipairs(order) do
      local x, m = t[id], s.m and s.m[id]
      local hits, units = m and m[1] or 0, m and m[2] or 0
      local tavg = x.mn and (x.mn + x.mx) / 2 or 0
      local chance = (x.c * K + hits * 100) / (K + n)
      local per = (x.c / 100 * tavg * K + units) / (K + n) -- units of this mat a roll
      if chance > 0 then
        local mn = math.min(x.mn or (m and m[3]) or 1, m and m[3] or x.mn or 1)
        local mx = math.max(x.mx or (m and m[4]) or 1, m and m[4] or x.mx or 1)
        out[#out + 1] = { id = id, chance = chance, min = mn, max = mx, avg = per / (chance / 100) }
      end
    end
    table.sort(out, function(a, b) if a.chance ~= b.chance then return a.chance > b.chance end return a.id < b.id end)
    if wrong then return out, ("deine %d Würfe (CMaNGOS-Tabelle passt nicht dazu)"):format(n), true end
    return out, ("CMaNGOS mit %d eigenen Würfen gemischt (Tabelle zählt wie %d)"):format(n, K), true
  end
  for k = 1, #raw, 4 do
    local mn, mx = raw[k + 2], raw[k + 3]
    out[#out + 1] = { id = raw[k], chance = raw[k + 1], min = mn, max = mx, avg = (mn + mx) / 2 }
  end
  table.sort(out, function(a, b) if a.chance ~= b.chance then return a.chance > b.chance end return a.id < b.id end)
  return out, "CMaNGOS", false
end

-- (16.11.2026) shields and off-hands were in the weapon groups 21-31 (CMaNGOS); the data now puts them in the armour group
-- (group - 20). Rolls written before sit under the weapon group: where they fit the armour table far better than the
-- weapon table (odds above 1000 to 1), they move there, once.
function DE.MoveRolls()
  local db = ns.db
  if not db or db.deMoved1116 then return end
  db.deMoved1116 = true
  local moved = {}
  for _, where in ipairs({ "deStats", "deStatsBuff" }) do
    local t = db[where]
    if type(t) == "table" then
      for g = 21, 31 do
        local s = t[g]
        if type(s) == "table" and (s.n or 0) > 0 and DE.groups[g] and DE.groups[g - 20]
          and Misfit(DE.groups[g], s) - Misfit(DE.groups[g - 20], s) > 2 * math.log(1000) then
          local d = t[g - 20]
          if type(d) ~= "table" then d = { n = 0, m = {} } t[g - 20] = d end
          d.n, d.m = (d.n or 0) + s.n, d.m or {}
          for id, m in pairs(s.m or {}) do
            local x = d.m[id]
            if x then x[1], x[2], x[3], x[4] = x[1] + m[1], x[2] + m[2], math.min(x[3], m[3]), math.max(x[4], m[4])
            else d.m[id] = { m[1], m[2], m[3], m[4] } end
          end
          t[g] = nil
          moved[#moved + 1] = ("Gruppe %d nach %d (%d Würfe)"):format(g, g - 20, s.n)
        end
      end
    end
  end
  if #moved > 0 then
    ns.Fact("deMoved", table.concat(moved, ", "))
    ns.Print("Entzaubern: Schilde und Nebenhand-Gegenstände rechnen jetzt mit der Rüstungstabelle (Staub statt Essenz). Deine Würfe umgezogen: " .. table.concat(moved, ", ") .. ".")
  end
end
ns.On("PLAYER_LOGIN", function() DE.MoveRolls() end)

function DE.MatName(id)
  local name = ns.ItemInfo(id)
  return name or (DE.names and DE.names[id]) or ("Item " .. id)
end

local function Pct(c)
  if c >= 10 or c == math.floor(c) then return ("%d %%"):format(math.floor(c + 0.5)) end
  return ("%.1f %%"):format(c)
end
local function Range(m)
  if m.min == m.max then return m.min > 1 and (m.min .. " ") or "" end
  return ("%d-%d "):format(m.min, m.max)
end

-- "75 % 1-2 Lesser Astral Essence, 15 % 4-6 Strange Dust, 10 % Small Glimmering Shard"
function DE.Text(group)
  local mats = DE.Mats(group)
  local parts = {}
  for _, m in ipairs(mats) do parts[#parts + 1] = Pct(m.chance) .. " " .. Range(m) .. DE.MatName(m.id) end
  return table.concat(parts, ", ")
end

-- expected value of one disenchant after the cut, the mats with their values, whether a mat price is missing
-- (Daniel 15.11.2026: "lagerfeuerbuff mit 10% mehr mats aus disenchant ... wenn man den mit reinrechnen könnte, als
-- optionaler schalter") the option deBonus: so many percent more mats per disenchant, counted into every value here.
-- The buff itself is not in our Forever facts, so its size is Daniel's to set (0 = off).
-- (Daniel 15.11.2026: "When dropping an Arcane Salvager at Enchanting Skill 225 you get the Buff Boosted Disenchanting",
-- spell 1283701) the buff is seen on the character itself (option deBuff, on): while it runs its bonus counts without a
-- hand-set number. Its size is read from the aura (the first effect value between 1 and 100), else Daniel's "10 % mehr
-- mats" (DE.BUFF_PCT); /profit diag line deBuff says what the game gave. The hand-set option counts always; the larger wins.
DE.BUFF_SPELL, DE.BUFF_PCT = 1283701, 10
local buffPct -- nil: not asked yet, 0: not active
local lastFact, lastName, lastPct
local function ReadBuff()
  local A = rawget(_G, "C_UnitAuras")
  local get = type(A) == "table" and A.GetPlayerAuraBySpellID
  if type(get) ~= "function" then return 0 end
  local ok, aura = pcall(get, DE.BUFF_SPELL)
  if not ok or type(aura) ~= "table" then return 0 end
  local pct
  for _, v in ipairs(type(aura.points) == "table" and aura.points or {}) do
    v = tonumber(v)
    if v and v >= 1 and v <= 100 then pct = v break end
  end
  -- (16.11.2026) the player's auras change often in a fight: the line is written when it says something new
  -- (21.11.2026, Ruckler) and only then formatted: the same name and value as the last line written is nothing new
  local f = ns.db and ns.db.facts and ns.db.facts.deBuff
  if not (f and f == lastFact and aura.name == lastName and pct == lastPct) then
    local line = ("%s aktiv, Wert aus dem Spiel %s, gerechnet %d %%"):format(tostring(aura.name or DE.BUFF_SPELL), tostring(pct or "keiner"), pct or DE.BUFF_PCT)
    if not (f and f.v == line) then ns.Fact("deBuff", line) end
    lastFact, lastName, lastPct = ns.db and ns.db.facts and ns.db.facts.deBuff, aura.name, pct
  end
  return pct or DE.BUFF_PCT
end
function DE.BuffPct()
  if ns.Opt("deBuff") == false then return 0 end
  if buffPct == nil then buffPct = ReadBuff() end
  return buffPct
end
function DE.Bonus() return 1 + math.max(0, tonumber(ns.Opt("deBonus")) or 0, DE.BuffPct()) / 100 end
-- the buff came or went: every disenchant value changes, the lists are worked out again
ns.On("UNIT_AURA", function(_, unit)
  if unit ~= "player" or not ns.db or ns.Opt("deBuff") == false then return end
  local now = ReadBuff()
  if now == buffPct then return end
  local first = buffPct == nil
  buffPct = now
  DE.ver = (DE.ver or 0) + 1
  if first and now == 0 then return end
  ns.Print(now > 0 and ("Boosted Disenchanting aktiv: Entzauberwerte mit %d %% mehr Mats gerechnet."):format(now)
    or "Boosted Disenchanting vorbei: Entzauberwerte wieder ohne Bonus.")
  if ns.OptionChanged then ns.OptionChanged() end
end)
ns.On("PLAYER_ENTERING_WORLD", function() buffPct = nil DE.ver = (DE.ver or 0) + 1 end)
-- what the own disenchants say about the buff: mats per disenchant with and without it over the groups measured in
-- both ways; nil until both have rolls. Returns the measured bonus in percent, rolls with, rolls without
function DE.BuffMeasured()
  local on, off = ns.db and ns.db.deStatsBuff, ns.db and ns.db.deStats
  if type(on) ~= "table" or type(off) ~= "table" then return nil end
  local function units(s) local u = 0 for _, m in pairs(s.m or {}) do u = u + (m[2] or 0) end return u end
  local nOn, nOff, ratio, weight = 0, 0, 0, 0
  for g, a in pairs(on) do
    local b = off[g]
    if type(a) == "table" and type(b) == "table" and (a.n or 0) > 0 and (b.n or 0) > 0 and units(b) > 0 then
      ratio = ratio + (units(a) / a.n) / (units(b) / b.n) * a.n
      weight = weight + a.n
      nOn, nOff = nOn + a.n, nOff + b.n
    end
  end
  if weight == 0 then return nil end
  return (ratio / weight - 1) * 100, nOn, nOff
end
function DE.Value(group, key)
  local mats, src, measured = DE.Mats(group)
  if #mats == 0 then return nil end
  local sum, missing, parts = 0, false, {}
  local bonus = DE.Bonus()
  for _, m in ipairs(mats) do
    local net, unit, psrc = ns.Prices.MatNet(m.id, key)
    local v = net and (m.chance / 100) * m.avg * net * bonus or nil
    if v then sum = sum + v else missing = true end
    parts[#parts + 1] = { m = m, net = net, unit = unit, src = psrc, value = v }
  end
  return math.floor(sum + 0.5), parts, missing, src, measured
end

-- (21.11.2026, Ruckler: every tooltip build worked out the disenchant value anew, Blizzard builds a bag tooltip about 5
-- times a second) DE.Value(group) for the tooltip, kept per group while nothing it comes from changed: the scan rows
-- (Prices P.ver, the store and its time), the auction house and its cut (StoreKey, the options cutOwn and cutNeutral),
-- the own rolls of the group (deStats, the table and its count), the options deMinRolls, deBonus, deBuff and tsm, the
-- buff's bonus and DE.ver (a roll written down, an option changed, the buff came or went). With TSM in use at most
-- TIP_TTL seconds, TSM's own values may change meanwhile.
DE.ver = 0
DE.TIP_TTL = 30
local tipVal, tipStamp = {}, {}
function DE.TipValue(group)
  if not group then return nil end
  local P, O = ns.Prices, ns.db and ns.db.opt or {}
  local key = P.StoreKey()
  local st = P.Store(key)
  local tsm = P.TSMReady()
  local s, now = tipStamp, ns.Call(GetTime) or 0
  if s.de ~= DE.ver or s.p ~= P.ver or s.key ~= key or s.st ~= st or s.t ~= (st and st.t) or s.cutOwn ~= O.cutOwn
    or s.cutNeutral ~= O.cutNeutral or s.rolls ~= O.deMinRolls or s.bonus ~= O.deBonus or s.buffOpt ~= O.deBuff
    or s.tsm ~= tsm or s.buff ~= DE.BuffPct() or s.stats ~= (ns.db and ns.db.deStats) or (tsm and now - (s.at or 0) > DE.TIP_TTL) then
    tipStamp = { de = DE.ver, p = P.ver, key = key, st = st, t = st and st.t, cutOwn = O.cutOwn, cutNeutral = O.cutNeutral,
      rolls = O.deMinRolls, bonus = O.deBonus, buffOpt = O.deBuff, tsm = tsm, buff = DE.BuffPct(), stats = ns.db and ns.db.deStats, at = now }
    tipVal = {}
  end
  local own = Stats(group)
  local e = tipVal[group]
  if not e or e.own ~= own or e.n ~= (own and own.n) then
    e = { own = own, n = own and own.n, v = DE.Value(group) }
    tipVal[group] = e
  end
  return e.v
end

-- (Daniel 15.11.2026: "irreführend mit dem gewinn ... man müsste ja etliche kaufen um die prozentuale dropchance zu
-- kriegen für die guten sachen") how far one disenchant strays from its average: the standard deviation of its value.
-- One disenchant gives exactly one of the mats (the chances add up to 100), in a count spread evenly from min to max.
function DE.Spread(group, key)
  local mats = DE.Mats(group)
  if #mats == 0 then return nil end
  local bonus = DE.Bonus()
  local e1, e2 = 0, 0
  for _, m in ipairs(mats) do
    local net = ns.Prices.MatNet(m.id, key)
    if net then
      local p = m.chance / 100
      local span = (m.max or 1) - (m.min or 1) + 1
      local var = (span * span - 1) / 12 -- of a whole number drawn evenly from min..max
      local unit = net * bonus
      e1 = e1 + p * m.avg * unit
      e2 = e2 + p * (m.avg * m.avg + var) * unit * unit
    end
  end
  return math.sqrt(math.max(0, e2 - e1 * e1)), e1
end
-- "sicher ab": how many pieces bought at price and disenchanted until a profit is likely (the average profit of n
-- pieces lies one standard deviation above zero, about 84 %): n = (spread / profit per piece)^2. nil without a profit.
DE.SURE_MAX = 999
function DE.SureAt(group, price, key)
  local sd, mean = DE.Spread(group, key)
  if not (sd and mean and price) then return nil end
  local gain = mean - price
  if gain <= 0 then return nil end
  return math.max(1, math.min(DE.SURE_MAX, math.ceil((sd / gain) ^ 2)))
end

-- (Durchsicht der Rechnungen 15.11.2026) "sicher ab" counted every piece at the cheapest offer; n pieces cost the n
-- cheapest offers. prices: the paying offers of the item, cheapest first. The smallest n whose profit together
-- (n times the average value less what the n cheapest cost) lies one standard deviation of n disenchants above zero;
-- nil when no n of the offers there reaches that (luck).
function DE.SureAtOffers(group, prices, key)
  local sd, mean = DE.Spread(group, key)
  if not (sd and mean and type(prices) == "table" and prices[1]) then return nil end
  local sum = 0
  for n = 1, math.min(#prices, DE.SURE_MAX) do
    sum = sum + prices[n]
    local gain = n * mean - sum
    if gain > 0 and gain >= sd * math.sqrt(n) then return n end
  end
  return nil
end

-- (Daniel 16.11.2026: "TSM hat doch bestimmt auch Entzauberungswerte? Die könnten wir doch auch nutzen"; gewählt "TSM-Wert
-- als Prüfung") TSM's own value of disenchanting an item (its price source "Destroy", with a table of its own for
-- Forever), only read at run time through TSM_API, nothing of it copied. After the same cut as ours; off: more than
-- DE.TSM_OFF percent apart. Returns TSM's value after the cut, off, or nil without TSM.
DE.TSM_OFF = 25
function DE.TSMCheck(id, group)
  local P = ns.Prices
  local tsm = id and P.TSM and P.TSM(id, "Destroy")
  if not tsm then return nil end
  local net = ns.Deals.AfterCut(tsm, P.Cut())
  local ours = group and DE.Value(group)
  local off = ours and ours > 0 and math.abs(net - ours) * 100 > DE.TSM_OFF * math.max(net, ours) or false
  return net, off
end

-- tooltip lines of a group: one per mat (chance, count, name, value), the source of the rates and the skill
-- (16.11.2026) id: the item, for TSM's value beside ours
function DE.TipLines(group, key, id)
  local value, parts, missing, src = DE.Value(group, key)
  local lines = {}
  for _, p in ipairs(parts or {}) do
    local m = p.m
    lines[#lines + 1] = { Pct(m.chance) .. "  " .. Range(m) .. DE.MatName(m.id),
      p.net and (ns.Money(p.net) .. " je Stück") or "kein Preis" }
  end
  if value then lines[#lines + 1] = { "Erwartet je Entzauberung" .. (missing and " (ohne Mats ohne Preis)" or ""), ns.Money(value) } end
  if DE.Bonus() > 1 then
    lines[#lines + 1] = ("Mit %d %% Bonus auf die Mats gerechnet (%s)."):format(math.floor((DE.Bonus() - 1) * 100 + 0.5),
      DE.BuffPct() > 0 and "Boosted Disenchanting läuft" or "Option")
  end
  lines[#lines + 1] = "Raten: " .. (src or "?") .. ". Stufe: etwa Verzauberkunst " .. (DE.Skill(group) or "?") .. " (Faustregel)."
  local tsm, off = DE.TSMCheck(id, group)
  if tsm then
    lines[#lines + 1] = { (off and "|cffe6b422" or "") .. "TSM sagt (nach Gebühr)" .. (off and ", weicht stark ab|r" or ""), ns.Money(tsm) }
  end
  return lines
end

---------------------------------------------------------------------------
-- Writing down the own disenchants
---------------------------------------------------------------------------
local pending, armed
function DE.Expect(id, group) pending = { id = id, group = group, t = GetTime() } end

-- (Daniel 15.11.2026, the buff's own words: "chance of bonus disenchanting output is increased", no number) a
-- disenchant made with Boosted Disenchanting running is kept apart (ProfitdonDB.deStatsBuff, the same shape): the
-- measured rates stay those without the buff (else the bonus would count twice), and the two tables side by side
-- show in time what the buff really gives (/profit de)
-- (Durchsicht 15.11.2026) the buff on the character decides, not the option: with deBuff off the boosted rolls went into
-- the plain rates
local function BuffRuns()
  local A = rawget(_G, "C_UnitAuras")
  local get = type(A) == "table" and A.GetPlayerAuraBySpellID
  if type(get) ~= "function" then return false end
  local ok, aura = pcall(get, DE.BUFF_SPELL)
  return ok and type(aura) == "table"
end
function DE.Record(group, loot)
  local where = (DE.BuffPct() > 0 or BuffRuns()) and "deStatsBuff" or "deStats"
  ns.db[where] = ns.db[where] or {}
  local s = ns.db[where][group]
  if type(s) ~= "table" then s = { n = 0, m = {} } ns.db[where][group] = s end
  s.n = (s.n or 0) + 1
  DE.ver = (DE.ver or 0) + 1
  s.m = s.m or {}
  for id, q in pairs(loot) do
    local m = s.m[id] or { 0, 0, q, q }
    m[1], m[2] = m[1] + 1, m[2] + q
    m[3], m[4] = math.min(m[3] or q, q), math.max(m[4] or q, q)
    s.m[id] = m
  end
  return s
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if unit ~= "player" or ns.Num(spellID) ~= SPELL then return end
  if pending and GetTime() - pending.t < 15 then armed, pending = pending, nil armed.t = GetTime() end
end)
local function ReadLoot()
  if not armed or GetTime() - armed.t > 10 then return end
  local n = ns.Num(ns.Call(GetNumLootItems)) or 0
  local loot, any = {}, false
  for i = 1, n do
    local link = ns.Call(GetLootSlotLink, i)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    local _, _, q = ns.Call(GetLootSlotInfo, i)
    if id then loot[id] = (loot[id] or 0) + (ns.Num(q) or 1) any = true end
  end
  if not any then return end
  local g, used = armed.group, armed.id
  armed = nil
  local s = DE.Record(g, loot)
  -- (Durchsicht 15.11.2026) deBuys only ever grew: one piece bought to disenchant, and every later piece of the ID was
  -- disenchanted whatever the AH paid. The disenchant uses the purchase up.
  local buys = ns.db.deBuys
  if used and type(buys) == "table" and buys[used] then
    buys[used] = buys[used] - 1
    if buys[used] <= 0 then buys[used] = nil end
  end
  ns.Fact("deLast", ("Gruppe %d, %d Würfe"):format(g, s.n))
  if ns.Refresh then ns.Refresh() end
end
ns.On("LOOT_READY", ReadLoot)
ns.On("LOOT_OPENED", ReadLoot)

function ns.DEReport()
  local out, keys = {}, {}
  for g in pairs(ns.db.deStats or {}) do keys[#keys + 1] = g end
  table.sort(keys)
  if #keys == 0 then return { "Noch keine eigenen Entzauberungen mitgeschrieben (nur über Profitdons Taschenknopf)." } end
  for _, g in ipairs(keys) do
    local s = ns.db.deStats[g]
    local parts = {}
    for id, m in pairs(s.m or {}) do parts[#parts + 1] = ("%s %d×, %d Stück"):format(DE.MatName(id), m[1], m[2]) end
    table.sort(parts)
    out[#out + 1] = ("Gruppe %d: %d Würfe. %s"):format(g, s.n or 0, table.concat(parts, "; "))
  end
  -- (15.11.2026) what the buff Boosted Disenchanting gave so far against the rolls without it
  local pct, nOn, nOff = DE.BuffMeasured()
  out[#out + 1] = pct and ("Boosted Disenchanting gemessen: %+.0f %% Mats je Wurf (%d Würfe mit, %d ohne Buff). Gerechnet wird mit %d %%."):format(pct, nOn, nOff, DE.BUFF_PCT)
    or ("Boosted Disenchanting: noch nicht messbar (braucht Würfe mit und ohne Buff in derselben Gruppe). Gerechnet wird mit %d %%."):format(DE.BUFF_PCT)
  return out
end

---------------------------------------------------------------------------
-- The bag button
---------------------------------------------------------------------------
-- the qualities the bag button takes: green, blue and epic by option
function DE.QualityOK(q) return q == 2 or (q == 3 and ns.Opt("deBlue")) or (q == 4 and ns.Opt("deEpic")) or false end

-- (Daniel 07.11.2026: green BoE gear stayed in the bags, the button said "nicht entzaubern", the sell tab did not list it)
-- one rule for both: gear the AH pays more for after the cut than its mats stays for the AH (the sell tab offers it), unless
-- bought to disenchant or the option deAlways is on. Returns keep, mats value.
-- (Durchsicht 15.11.2026) link: the piece itself. A piece with a random suffix was measured against the cheapest offer of
-- any suffix of the ID ("of the Monkey" at 5g against the cheapest "of Spirit" at 20s: disenchanted). It counts with its
-- own variant's price once a search found it (the sell tab's click), until then with the middle of all variants: the
-- piece stays for the sell tab, whose search settles it.
function DE.KeepForAH(id, group, value, link)
  group = group or DE.Group(id)
  if not group then return false end
  if value == nil then value = DE.Value(group) end
  if ns.Opt("deAlways") or (ns.db.deBuys and ns.db.deBuys[id]) then return false, value end
  local ah
  local suffix = type(link) == "string" and ns.LinkSuffix and ns.LinkSuffix(link) or 0
  if suffix > 0 then
    ah = ns.FreshLow and ns.FreshLow(id .. ":" .. suffix)
    if not ah then
      local low, med = ns.Prices.AH(id)
      ah = med or low
    end
  else ah = ns.Prices.Low(id) end
  local ahNet = ah and ns.Deals.AfterCut(ah, ns.Prices.Cut())
  return (value and ahNet and ahNet > value) and true or false, value
end

-- what the bag button would disenchant: { bag, slot, id, group, value, quality }, best value first; items the AH pays more
-- for than their mats (after the cut) are left out and counted in "kept"
-- (Durchsicht 15.11.2026) third value: pieces the vendor pays more for than the mats are worth (the tooltip said "Händler",
-- the button disenchanted them all the same); they stay unless bought to disenchant or deAlways is on. A soulbound piece
-- cannot go to the AH: it is not kept for it.
function DE.BagList()
  local out, kept, vend = {}, 0, 0
  for bag = 0, ns.LASTBAG do
    local slots = ns.Num(ns.Call(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, slots do
      local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      local q = id and (ns.Num(info.quality) or select(3, ns.ItemInfo(id)))
      if id and DE.QualityOK(q) and not info.isLocked then
        local g = DE.Group(id)
        if g then
          local v = DE.Value(g)
          local forced = ns.Opt("deAlways") or (ns.db.deBuys and ns.db.deBuys[id])
          local sell = ns.Prices.Sell(id) or 0
          if not forced and v and sell > v then vend = vend + 1
          elseif not info.isBound and DE.KeepForAH(id, g, v, info.hyperlink) then kept = kept + 1
          else out[#out + 1] = { bag = bag, slot = slot, id = id, group = g, value = v, quality = q } end
        end
      end
    end
  end
  table.sort(out, function(a, b) if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
    if a.bag ~= b.bag then return a.bag < b.bag end return a.slot < b.slot end)
  return out, kept, vend
end

local function SpellName()
  if C_Spell and C_Spell.GetSpellInfo then
    local i = ns.Call(C_Spell.GetSpellInfo, SPELL)
    if type(i) == "table" and i.name then return i.name end
  end
  return ns.Call(GetSpellInfo, SPELL) or "Disenchant"
end

local btn
-- the secure button, styled with the kit's helpers (Kit.Button is not a secure template)
function DE.Button(parent)
  if btn then return btn end
  -- (Durchsicht 11.11.2026, Kit 23) the kit's protected button in the Don look (it was styled here by hand)
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 23)
  -- (16.11.2026, DonCore Blizz 5) with the Blizzard look the game's red button (secure template); a build that fails
  -- there gives the kit's button
  local UI, blizz = ns.LookKit()
  if blizz then
    local ok, b = pcall(UI.SecureButton, "ProfitdonDEButton", parent, { width = 200, height = 24 })
    if ok and b then btn = b else ns.Fact("blizzDE", "Fehler: " .. tostring(b)) ns.SayLook() end
  end
  btn = btn or Kit.SecureButton("ProfitdonDEButton", parent, { width = 200, height = 24 })
  btn:SetAttribute("type", "macro")
  -- (own button: PreClick is the button's own script, not a hook) the item about to be disenchanted, for the measurement
  btn:SetScript("PreClick", function(self) if self.next then DE.Expect(self.next.id, self.next.group) end end)
  btn:SetScript("OnEnter", function(self)
    local n = self.next
    if not n then Kit.Tooltip(self, "Entzaubern", { "Nichts zu entzaubern in den Taschen." }) return end
    local lines = DE.TipLines(n.group, nil, n.id)
    table.insert(lines, 1, ("Nächstes: %s (Tasche %d, Platz %d)"):format(ns.ItemInfo(n.id) or ("Item " .. n.id), n.bag, n.slot))
    Kit.Tooltip(self, "Entzaubern", lines, "Ein Klick entzaubert ein Stück (Blizzard-Regel).")
  end)
  btn:SetScript("OnLeave", function(self) Kit.HideTooltip(self) end)
  DE.UpdateButton()
  return btn
end

function DE.UpdateButton()
  -- (16.11.2026) a hidden button needs no next item: every bag change went through all bags and disenchant values
  if not btn or ns.Call(InCombatLockdown) then return end
  if btn.IsShown and not btn:IsShown() then return end
  local list, kept, vend = DE.BagList()
  local n = list[1]
  btn.next = n
  if n then
    btn:SetAttribute("macrotext", ("/cast %s\n/use %d %d"):format(SpellName(), n.bag, n.slot))
    btn:SetLabel(("Entzaubern: %s (%d)"):format(ns.ItemInfo(n.id) or ("Item " .. n.id), #list))
    -- (16.11.2026) the tooltip was written once on entering; with the mouse kept on the button it showed the old rates
  else
    btn:SetAttribute("macrotext", "")
    btn:SetLabel(kept > 0 and ("Nichts zu entzaubern (%d im AH mehr wert, siehe Verkaufen)"):format(kept)
      or (vend or 0) > 0 and ("Nichts zu entzaubern (%d beim Händler mehr wert)"):format(vend) or "Nichts zu entzaubern")
  end
  if btn.IsMouseOver and btn:IsMouseOver() then
    local enter = btn:GetScript("OnEnter")
    if enter then enter(btn) end
  end
end

DE.ButtonReset = function(keep) btn = keep end -- (tests: build the button anew, then put the old one back)

ns.On("BAG_UPDATE_DELAYED", function() ns.WhenIdle("Entzaubern-Knopf", DE.UpdateButton) end)
ns.On("PLAYER_REGEN_ENABLED", function() DE.UpdateButton() end)
