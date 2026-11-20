local _, ns = ...

---------------------------------------------------------------------------
-- The page Verkaufen (Daniel 17.11.2026, Bild Auctionator "Selling", PROFITDON_PLAN.md "Verkaufen-Seite neu"):
--   head:  symbol and name of the picked item, what posting brings (deposit, after the cut, over the vendor), the
--          search's message; amount with "Max", price a piece (g/s/c, preset with the cheapest offer of others), run
--          time 2/8/24 h (Forever's hours, the option postDur), "Einstellen" (ns.BuyNow: one click, one posting)
--   left:  the bags as symbols (DonCore ItemGrid) in sections with a head and a count (Post.lua ns.SellList: Hergestellt,
--          AH lohnt, Händler zahlt mehr dimmed, Ohne Preis; Ausgeblendet at the end), heads fold (ProfitdonDB.ui.sellFold)
--   right: the offers of the picked item now (own ones marked), Verlauf (scan, market, own sales), Eigene (own postings)
-- A click on a symbol searches it (ns.Select, kind "post"); a right click opens a menu: hide while only one is in the
-- bags, hide always, show again, and under "Händler zahlt mehr" onto the sell list at the merchant (Merchant.lua).
-- Built with the window's kit (Blizzard look or Don kit), the same calls for both.
---------------------------------------------------------------------------
local Kit = LibStub("DonCore-1.0"):Get("Kit", 23)
local C, S = Kit.C, Kit.SIZE
local floor, max, min = math.floor, math.max, math.min
local ICON, GAP = 36, 4

local function M(c) return c and Kit.Money(c) or "" end

-- the same piece stays picked when the list is built again: gear by its bag slot, all else by item
function ns.SellKey(e)
  if not e then return nil end
  if e.gear then return "g" .. tostring(e.bag) .. ":" .. tostring(e.slot) end
  return e.id
end

function ns.SellToVendor(id)
  ns.db.vendorList = type(ns.db.vendorList) == "table" and ns.db.vendorList or {}
  ns.db.vendorList[id] = true
  ns.Print(("%s steht auf der Verkaufsliste beim Händler."):format(ns.ItemInfo(id) or id))
end

local function Name(e)
  if e.gear and type(e.link) == "string" then
    local n = e.link:match("%[(.-)%]")
    if n and n ~= "" then return n end
  end
  return ns.ItemInfo(e.id) or ("Item " .. e.id)
end

local function TipLines(e)
  local cut = ns.Prices.Cut()
  local l = {}
  if e.section == "noprice" then
    l[#l + 1] = "Noch kein Scanpreis: Klick sucht live."
  else
    local each = ns.Deals.AfterCut(e.unit or 0, cut)
    if e.section == "vendor" then
      l[#l + 1] = ("Händler %s, AH nach Gebühr %s je Stück"):format(M(e.sell), M(each))
      l[#l + 1] = "Rechtsklick: auf die Verkaufsliste beim Händler"
    else
      l[#l + 1] = ("AH nach Gebühr %s je Stück, Händler %s"):format(M(each), M(e.sell))
      if e.profit then l[#l + 1] = ("Alle %d: %s mehr als beim Händler"):format(e.count, M(e.profit)) end
    end
  end
  if e.gear then l[#l + 1] = ("Ausrüstung, AH mehr als Entzaubern (%s)"):format(M(e.deValue)) end
  if e.quality == 0 then l[#l + 1] = "Grau: im AH für Transmog gehandelt (die eigene Optik gab es schon beim Looten)" end
  if e.hidden then l[#l + 1] = "Ausgeblendet. Rechtsklick: wieder zeigen" end
  return l
end

-- the left list as List items: a head per section, under it one row holding the symbols
local function ListItems(p, gridW)
  ns.db.ui = ns.db.ui or {}
  local fold = type(ns.db.ui.sellFold) == "table" and ns.db.ui.sellFold or {}
  ns.db.ui.sellFold = fold
  local by = {}
  for _, e in ipairs(ns.SellList()) do
    by[e.section] = by[e.section] or {}
    table.insert(by[e.section], e)
  end
  by.hidden = ns.SellHidden()
  local cols = max(1, floor((gridW + GAP) / (ICON + GAP)))
  local out = {}
  local secs = {}
  for _, s in ipairs(ns.SELL_SECTIONS) do secs[#secs + 1] = s end
  secs[#secs + 1] = "hidden"
  for _, sec in ipairs(secs) do
    local list = by[sec]
    if list and #list > 0 then
      local collapsed = fold[sec]
      if collapsed == nil and sec == "hidden" then collapsed = true end
      out[#out + 1] = { kind = "group", text = ns.SELL_SECTION_NAME[sec], count = #list, collapsed = collapsed, key = sec,
        plainCase = true }
      if not collapsed then
        local entries = {}
        for _, e in ipairs(list) do
          entries[#entries + 1] = { itemID = e.gear and e.link or e.id, count = e.count, quality = e.quality, entry = e,
            dim = (sec == "vendor" or sec == "hidden") or nil, selected = (p.selKey ~= nil and ns.SellKey(e) == p.selKey) or nil,
            tipLines = TipLines(e) }
        end
        local rows = math.ceil(#entries / cols)
        out[#out + 1] = { kind = "sellgrid", entries = entries, gridW = gridW, h = rows * (ICON + GAP) - GAP + 10, key = sec .. ":grid" }
      end
    end
  end
  return out
end

local function Menu(p, e, UI)
  local items = {}
  if e.hidden then
    items[#items + 1] = { text = "Wieder zeigen", onClick = function() ns.SetSellHide(e.id, nil) ns.Refresh() end }
  elseif not e.gear then
    items[#items + 1] = { text = "Ausblenden, solange nur 1 in den Taschen", onClick = function() ns.SetSellHide(e.id, 1) ns.Refresh() end }
    items[#items + 1] = { text = "Immer ausblenden", onClick = function() ns.SetSellHide(e.id, true) ns.Refresh() end }
  end
  if e.section == "vendor" then
    items[#items + 1] = { text = "Beim Händler verkaufen (Verkaufsliste)", onClick = function() ns.SellToVendor(e.id) end }
  end
  -- (Daniel 19.11.2026: "Rechtsklick überall") on an own shopping list
  if ns.ListAddItems and e.id then for _, x in ipairs(ns.ListAddItems("item", e.id)) do items[#items + 1] = x end end
  if #items == 0 then return end
  local menu = UI.Menu or Kit.Menu
  menu(Name(e), items)
  p.menuFor = e -- (tests)
  p.menuItems = items
end

-- the right side: the offers now, the history, the own postings
local VIEWS = { { "cur", "Aktuell" }, { "hist", "Verlauf" }, { "own", "Eigene" } }
local COLS = {
  cur = { { key = "title", title = "Preis je Stück" }, { key = "count", title = "Anzahl", width = 70 } },
  hist = { { key = "title", title = "Angabe" }, { key = "val", title = "Wert", width = 110 } },
  own = { { key = "title", title = "Preis je Stück" }, { key = "count", title = "Anzahl", width = 60 }, { key = "left", title = "Rest", width = 56 } },
}
local function Trow(title, cells, sub, extra)
  local it = { kind = "trow", title = title, cells = cells or {}, sub = sub or "" }
  for k, v in pairs(extra or {}) do it[k] = v end
  return it
end
local function RightItems(p, e)
  local B = ns.BuyState
  local out = {}
  if not e then return out, "Links einen Gegenstand wählen." end
  if p.view == "cur" then
    if B.state == "browsing" or B.state == "searching" then return out, "Suche läuft..." end
    for _, o in ipairs(B.offers or {}) do
      -- (Daniel 19.11.2026: "Wenn ich da in der Liste raufklicke ... dass genau der Preis dann bei meinen übernommen wird")
      out[#out + 1] = Trow(M(o[1]), { count = tostring(o[2]) }, o[3] and "eigenes Angebot" or nil,
        { markColor = o[3] and C.green or nil, unit = o[1], clickable = true })
    end
    if not ns.ScanState.open then return out, "Am Auktionshaus stehen hier die Angebote." end
    return out, B.offers and "Keine Angebote im AH." or "Klick auf den Gegenstand sucht die Angebote."
  elseif p.view == "hist" then
    local P = ns.Prices
    local low, med, qty, n, age, src = P.AH(e.id)
    if low then
      out[#out + 1] = Trow(src == "tsm" and "Billigstes (TSM)" or "Billigstes im Scan", { val = M(low) })
      out[#out + 1] = Trow(src == "tsm" and "Marktwert (TSM)" or "Mittel im Scan", { val = M(med) })
      if qty then out[#out + 1] = Trow("Stück im Scan", { val = tostring(qty) }) end
      if age then out[#out + 1] = Trow("Scan vor", { val = ("%d min"):format(floor(age / 60)) }) end
    end
    local per, avg, rate
    if ns.Market and ns.Market.Stats then per, avg, rate = ns.Market.Stats(e.id) end
    if per then
      out[#out + 1] = Trow("Markt: verkauft am Tag", { val = ("%.1f"):format(per):gsub("%.", ",") })
      if avg then out[#out + 1] = Trow("Markt: Schnittpreis", { val = M(floor(avg + 0.5)) }) end
      out[#out + 1] = Trow("Markt: Verkaufsquote", { val = ("%d %%"):format(floor((rate or 0) * 100 + 0.5)) })
    end
    local s = ns.db and type(ns.db.sold) == "table" and ns.db.sold[e.id]
    if type(s) == "table" then
      out[#out + 1] = Trow("Eigene: eingestellt", { val = tostring(s[1] or 0) })
      out[#out + 1] = Trow("Eigene: verkauft", { val = tostring(s[2] or 0) })
      if (s[3] or 0) > 0 then out[#out + 1] = Trow("Eigene: Erlös", { val = M(s[3]) }) end
    end
    out[#out + 1] = Trow("Händler", { val = M(e.sell) })
    return out, ""
  end
  local r = ns.Report and ns.Report.Store and ns.Report.Store()
  local now = time()
  for _, o in ipairs(r and r.posted or {}) do
    if o[1] == e.id then
      local left = max(0, (o[5] or 24) * 3600 - (now - (o[4] or now)))
      out[#out + 1] = Trow(M(o[3]), { count = tostring(o[2]), left = ("%d h"):format(math.ceil(left / 3600)) })
    end
  end
  return out, "Keine eigenen Auktionen davon (die Liste kommt mit dem Reiter Auktionen des Spiels)."
end

function ns.SellPage(parent, UI)
  UI = UI or Kit
  local p = CreateFrame("Frame", nil, parent)
  p.UI, p.view = UI, "cur"
  local B = ns.BuyState
  -- head
  p.head = CreateFrame("Frame", nil, p)
  p.icon = UI.ItemIcon(p.head, 40)
  p.name = UI.Text(p.head, "row", C.hero)
  p.info = UI.Text(p.head, "sub", C.muted)
  p.msg = UI.Text(p.head, "sub", C.body)
  p.qtyL = UI.Text(p.head, "sub", C.muted) p.qtyL:SetText("Menge")
  p.qty = UI.EditBox(p.head, { numeric = true, min = 1, placeholder = "Menge",
    onChange = function(t) local n = tonumber(t) if n and n >= 1 then ns.PostAdjust(n, nil) end end })
  p.max = UI.Button(p.head, "Max", { small = true, onClick = function()
      local e = B.kind == "post" and B.entry
      local have = (B.plan and B.plan.have) or (e and e.count)
      if have then ns.PostAdjust(have, nil) p.filled = nil ns.Refresh() end
    end, tooltip = "Max", tooltipLines = { "Alles aus den Taschen einstellen." } })
  p.priceL = UI.Text(p.head, "sub", C.muted) p.priceL:SetText("Preis je Stück")
  p.price = UI.CoinBox(p.head, { onChange = function(c) if c and c > 0 then ns.PostAdjust(nil, c) end end })
  p.durL = UI.Text(p.head, "sub", C.muted) p.durL:SetText("Laufzeit")
  local durs = {}
  for i = 1, 3 do durs[i] = { value = i, text = ((ns.POST_HOURS and ns.POST_HOURS[i]) or "?") .. " h" } end
  p.dur = UI.Segmented(p.head, { items = durs, get = function() return ns.PostDurIndex() end,
    set = function(v) ns.db.opt.postDur = v ns.Touch() ns.PostAdjust() if ns.Refresh then ns.Refresh() end end })
  p.go = UI.Button(p.head, "Einstellen", { kind = "primary", onClick = function() ns.BuyNow() end,
    tooltip = "Einstellen", tooltipLines = { "Stellt die Menge zum Preis je Stück ein (ein Klick, eine Auktion).", "Tastenkürzel \"Profitdon: nächster Klick\" geht auch." } })
  p.opts = UI.Button(p.head, "Optionen", { small = true, onClick = function() if ns.OpenOptions then ns.OpenOptions() end end,
    tooltip = "Optionen", tooltipLines = { "Abschnitte, Mindestgewinn gegenüber Händler, Laufzeit, Teil nach Absatz." } })
  -- left: the sections
  p.list = UI.List(p, {
    kinds = { sellgrid = { h = ICON + 10, make = function()
      local f = CreateFrame("Frame", nil, p)
      f.grid = UI.ItemGrid(f, { size = ICON, gap = GAP, onClick = function(icon, button, en)
        if en and en.entry then p:Click(en.entry, button) end
      end })
      f.grid:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -5)
      function f:SetItem(it)
        self.item = it
        self.grid:SetItems(it.entries or {})
        self.grid:Layout(it.gridW or ((self._w or 300) - 16))
      end
      function f:Layout() end
      return f
    end } },
    onToggle = function(it) p.Toggle(it) end })
  function p.Toggle(it)
    ns.db.ui.sellFold = ns.db.ui.sellFold or {}
    ns.db.ui.sellFold[it.key] = it.collapsed and true or false
    p:Fill()
  end
  -- right: offers, history, own
  local segItems = {}
  for _, v in ipairs(VIEWS) do segItems[#segItems + 1] = { value = v[1], text = v[2] } end
  p.views = UI.Segmented(p, { items = segItems, get = function() return p.view end, set = function(v) p.view = v p:Fill() end })
  -- a click on an offer takes its price per piece into the price box (the plan keeps its object, so the box is set here)
  function p.PickOffer(it)
    if not (it and it.unit and p.view == "cur") then return end
    local plan = B.plan
    if not (plan and plan.post) then return end
    p.price:SetValue(it.unit)
    ns.PostAdjust(nil, it.unit)
  end
  p.offers = UI.Table(p, { onClick = function(it) p.PickOffer(it) end })

  function p:Click(e, button)
    if button == "RightButton" then Menu(self, e, UI) return end
    self.selKey = ns.SellKey(e)
    self.filled = nil
    ns.Select(e, "post")
    ns.Refresh()
  end

  function p:Fill()
    local e = B.kind == "post" and B.entry or nil
    if not e then self.selKey = nil end
    -- head
    if e then
      self.icon:SetItem(e.gear and e.link or e.id, e.count, e.quality)
      self.icon:Show()
      self.name:SetText(Name(e))
    else
      self.icon:Hide()
      self.name:SetText("Verkaufen")
    end
    local plan = B.plan and B.plan.post and B.plan or nil
    if plan then
      self.info:SetText(("Einzahlung %s  ·  nach Gebühr %s  ·  %s %s gegenüber Händler"):format(M(plan.deposit or 0), M(plan.ret),
        (plan.overVendor or 0) >= 0 and "+" or "-", M(math.abs(plan.overVendor or 0))))
    elseif e then
      self.info:SetText(e.unit and ("Letzter Preis %s je Stück, Händler %s"):format(M(e.unit), M(e.sell)) or ("Händler " .. M(e.sell)))
    else
      self.info:SetText("Links einen Gegenstand anklicken: er wird gesucht, Menge und Preis stehen dann hier.")
    end
    self.msg:SetText(e and (B.msg or "") or "")
    -- the boxes take the plan's values once per plan (typing changes the same plan, the boxes stay as typed)
    if self.filled ~= (plan or e or false) then
      self.filled = plan or e or false
      self.qty:SetValue(plan and plan.qty or (e and e.count) or nil)
      self.price:SetValue(plan and plan.unit or (e and e.unit) or nil)
    end
    self.dur:Update(ns.PostDurIndex())
    local ready = plan and B.state == "ready"
    self.go:SetText(ready and ("Einstellen: %d zu %s"):format(plan.qty, M(plan.unit)) or "Einstellen")
    if self.go.SetDisabled then self.go:SetDisabled(not ready) end
    if self.max.SetDisabled then self.max:SetDisabled(not plan) end
    -- left
    local lw = self.lw or 300
    self.listItems = ListItems(self, lw - 40)
    self.list:SetItems(self.listItems)
    local c = ns.SellCounts()
    self.list:SetEmpty((c.hidden or 0) > 0 and "Alles in den Taschen ist ausgeblendet." or ns.EmptyText("sell"))
    -- right
    self.views:Update(self.view)
    local items, empty = RightItems(self, e)
    self.rightItems = items
    self.offers:SetColumns(COLS[self.view])
    self.offers:SetItems(items)
    self.offers:SetEmpty(empty or "")
    self:Layout(self.w or 700, self.h or 400)
  end

  function p:Layout(w, h)
    self.w, self.h = w, h
    self:SetSize(w, h)
    local pad = S.pad or 8
    -- (Daniel 17.11.2026, Bild: "Auf kleinen Bildschirmen passt das nicht", Einstellen lag über der Laufzeit) the controls
    -- flow in groups (amount, price, run time, Einstellen) and wrap to a new line when the width runs out; the head grows
    local y0, lineH = -62, 30
    local groups = { { w = 152, kind = "qty" }, { w = 234, kind = "price" }, { w = 194, kind = "dur" } }
    local line, x = 0, pad
    for _, g in ipairs(groups) do
      if x > pad and x + g.w > w - pad then line, x = line + 1, pad end
      g.x, g.line = x, line
      x = x + g.w + 14
    end
    -- Einstellen: the rest of the last line when 150 px are left, else a line of its own
    local goW, goLine = min(220, w - x - pad), line
    if goW < 150 then goLine, goW = line + 1, min(260, w - 2 * pad) end
    local headH = 52 + (goLine + 1) * lineH + 4
    self.headH = headH
    self.head:ClearAllPoints()
    self.head:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.head:SetSize(w, headH)
    -- first line: symbol, name, what it brings, options
    self.icon:ClearAllPoints() self.icon:SetPoint("TOPLEFT", self.head, "TOPLEFT", pad, -4)
    self.opts:ClearAllPoints() self.opts:SetPoint("TOPRIGHT", self.head, "TOPRIGHT", -pad, -4) self.opts:Layout(80)
    local tx = pad + 40 + 8
    local tw = max(60, w - tx - 80 - 2 * pad)
    self.name:ClearAllPoints() self.name:SetPoint("TOPLEFT", self.head, "TOPLEFT", tx, -4)
    self.info:ClearAllPoints() self.info:SetPoint("TOPLEFT", self.head, "TOPLEFT", tx, -20)
    self.msg:ClearAllPoints() self.msg:SetPoint("TOPLEFT", self.head, "TOPLEFT", tx, -34)
    UI.Fit(self.name, tw) UI.Fit(self.info, tw) UI.Fit(self.msg, tw)
    local function at(f, gx, gl, cw)
      f:ClearAllPoints() f:SetPoint("LEFT", self.head, "TOPLEFT", gx, y0 - gl * lineH)
      if cw then f:Layout(cw) end
    end
    for _, g in ipairs(groups) do
      if g.kind == "qty" then
        at(self.qtyL, g.x, g.line) at(self.qty, g.x + 46, g.line, 56) at(self.max, g.x + 108, g.line, 44)
      elseif g.kind == "price" then
        at(self.priceL, g.x, g.line) at(self.price, g.x + 84, g.line, 150)
      else
        at(self.durL, g.x, g.line) at(self.dur, g.x + 54, g.line, 140)
      end
    end
    self.go:ClearAllPoints() self.go:SetPoint("RIGHT", self.head, "TOPRIGHT", -pad, y0 - goLine * lineH) self.go:Layout(goW)
    self.goLine = goLine -- (tests)
    -- body: left the sections, right the offers
    local bodyH = max(40, h - headH)
    local lw = max(200, floor(w * 0.55))
    if self.lw ~= lw then
      self.lw = lw
      -- the symbols per row follow the width: the sections again
      if self.listItems then self.listItems = ListItems(self, lw - 40) self.list:SetItems(self.listItems) end
    end
    self.list:ClearAllPoints() self.list:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -headH)
    self.list:Resize(lw, bodyH)
    local rx = lw + 8
    local rw = max(120, w - rx)
    self.views:ClearAllPoints() self.views:SetPoint("TOPLEFT", self, "TOPLEFT", rx, -headH) self.views:Layout(rw)
    self.offers:ClearAllPoints() self.offers:SetPoint("TOPLEFT", self, "TOPLEFT", rx, -headH - 32)
    self.offers:Layout(rw, max(40, bodyH - 32))
  end
  return p
end
