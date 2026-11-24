---------------------------------------------------------------------------
-- Profitdon: the Herstellfenster beside the profession window
-- (Daniel 15.11.2026: "Alle herstellen aus dem Hauptfenster raus", "Neues Herstellfenster: öffnet mit dem Berufsfenster,
-- daneben angedockt, verschiebbar, Größe änderbar; zeigt, was über die Einkaufsliste gekauft wurde: Hauptprodukt als Kopf
-- ohne Knopf, darunter eingerückt die Schritte mit alle herstellen, zuletzt das Hauptprodukt mit Knopf; abgesetzt
-- darunter, was sich sonst aus den Taschen herstellen lässt")
--   Rows (the model, ns.CraftWinRows): a section line, per job Crafts.JobRows (head, steps, mats, the product), a second
--   section with Crafts.Others of the open profession. The view below draws them; the look can change without the model.
--   One click on a button is one craft queue of the game (Crafts.CraftRow, at most 28 minutes); the key "nächster Klick"
--   presses the next button of the jobs while the window is open (ns.CraftClick).
---------------------------------------------------------------------------
local _, ns = ...
local Cr = ns.Crafts

local panel
local msg, msgAt -- the last answer of a click, shown in the foot line for MSG_SEC seconds
local MSG_SEC = 8
local HINT = "Ein Klick stellt einen Schritt her; die Taste \"nächster Klick\" nimmt den nächsten."

-- the game's profession window (Forever: checked at run time, not assumed) and the profession it shows
local function ProfFrame()
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    local f = rawget(_G, name)
    if type(f) == "table" and f.IsShown and ns.Call(f.IsShown, f) then return f, name end
  end
end
local function OpenProf()
  local T = C_TradeSkillUI
  local info = T and T.GetBaseProfessionInfo and ns.Call(T.GetBaseProfessionInfo)
  return type(info) == "table" and ns.Num(info.professionID) or nil
end

---------------------------------------------------------------------------
-- The model
---------------------------------------------------------------------------
local function Rows()
  local out, skip = {}, {}
  local jobs = Cr.Jobs()
  out[#out + 1] = { section = true, text = "Eingekauft über die Einkaufsliste" }
  if #jobs == 0 then
    -- (Daniel 18.11.2026, Bild: "abgehackt") short enough for the window's width, the row has one line
    out[#out + 1] = { note = true, text = "Nichts offen. Käufe der Einkaufsliste stehen hier." }
  end
  for _, job in ipairs(jobs) do
    skip[job.spell] = true
    for _, row in ipairs(Cr.JobRows(job)) do
      if row.step then skip[row.r.spell] = true end
      out[#out + 1] = row
    end
  end
  local prof = OpenProf()
  out[#out + 1] = { section = true, gap = true, text = prof and ("Sonst aus den Taschen herstellbar: " .. Cr.ProfName(prof)) or "Sonst aus den Taschen herstellbar" }
  local others = Cr.Others(prof, skip)
  for _, row in ipairs(others) do out[#out + 1] = row end
  if #others == 0 then out[#out + 1] = { note = true, text = "Für nichts Weiteres liegen die Mats in den Taschen." } end
  return out
end
ns.CraftWinRows = Rows

-- (Daniel 16.11.2026, gewählt "Zahlenfeld je Zeile") how many of a recipe to make, typed in the row's box; nil: all
-- the bags allow. Kept per recipe until its button is clicked.
local want = {}
local function Want(spell) return spell and want[spell] or nil end
function ns.CraftWinSetWant(spell, n)
  n = tonumber(n)
  want[spell] = n and n >= 1 and math.floor(n) or nil
end

-- (Daniel 17.11.2026, Bild "Requires: Cooking Fire": "soll es in unserem fenster auch angezeigt werden ... auch wenn wir in
-- der nähe sind, dass es dann grün ist") what a recipe needs besides mats (a fire, an anvil, a totem): the game's own
-- list with "met" (C_TradeSkillUI.GetRecipeRequirements, as the profession window shows it). Returns the names joined and
-- whether all are met; nil when it needs nothing. reqState: the met flags of the rows shown, checked once a second.
local reqState
local function Reqs(spell)
  local T = rawget(_G, "C_TradeSkillUI")
  local list = spell and type(T) == "table" and ns.Call(T.GetRecipeRequirements, spell)
  if type(list) ~= "table" or #list == 0 then return nil end
  -- (Daniel 24.11.2026, Bild Gnomish Universal Remote: "hammer und spanner werden erst weiß, wenn ich am amboss stehe")
  -- each need in its own colour as the game shows it: the hammer in the bags is white while the anvil is still red.
  -- Third value: the names with colour codes; fourth: the met flags in a row ("011"), for the poll
  local names, met, rich, flags = {}, true, {}, {}
  for _, q in ipairs(list) do
    if type(q) == "table" and q.name then
      names[#names + 1] = q.name
      rich[#rich + 1] = (q.met and "|cffffffff" or "|cffff1a1a") .. q.name .. "|r"
      flags[#flags + 1] = q.met and "1" or "0"
      if not q.met then met = false end
    end
  end
  if #names == 0 then return nil end
  return table.concat(names, ", "), met, table.concat(rich, "|cffffffff, |r"), table.concat(flags)
end
ns.CraftWinReqs = Reqs -- (tests)

-- what a row says: title, the short text on the right, its colour key, the button text (nil: no button), disabled
local function Describe(row)
  local a, b, c, d, e = ns.DescribeRaw(row)
  local r = not (row.section or row.note or row.head or row.mat) and row.r
  local need, met = Reqs(r and r.spell)
  if not need then return a, b, c, d, e end
  -- (Daniel 17.11.2026: "Bei wow wird cooking fire anstatt rot dann weiß") as the game: unmet the button waits. The
  -- words stand in a line of their own under the recipe (Daniel 17.11.2026, Bild: "das braucht ... vielleicht drunter
  -- nicht in der gleichen zeile"), see NeedRow
  if not met then return a, b, c, d, true end
  return a, b, c, d, e
end

-- the line under a recipe with needs: "Braucht Anvil, Blacksmith Hammer", each name red while unmet, white once met;
-- "Braucht" itself red while one is missing (need), plain: the words without colour codes
local function NeedRow(row)
  local r = not (row.section or row.note or row.head or row.mat) and row.r
  local need, met, rich = Reqs(r and r.spell)
  if not need then return nil end
  return { note = true, need = met and "white" or "red", text = "Braucht " .. rich, plain = "Braucht " .. need,
    depth = row.depth, pad = row.id and true or nil }
end
ns.CraftWinNeedRow = NeedRow -- (tests)

local function DescribeRaw(row)
  local name = row.id and (ns.ItemInfo(row.id) or ("Item " .. row.id)) or row.text or ""
  if row.section or row.note then return row.text end
  if row.head then return name, ("%d× herstellen"):format(row.runs), "muted" end
  if row.mat then
    local lack = row.want - row.have
    return ("%d× %s"):format(row.want, name), lack > 0 and ("fehlt %d"):format(lack) or "da", lack > 0 and "red" or "green"
  end
  local btn = ("Alle herstellen (%d)"):format(row.n or 0)
  -- (Daniel 16.11.2026: "mehr mats wären da, aber ich möchte nur 5 herstellen") a number typed in the row's box
  local typed = row.r and Want(row.r.spell)
  if typed and typed < (row.n or 0) then btn = ("Herstellen (%d)"):format(typed) end
  -- (Daniel 16.11.2026: "ich müsste doch mehr als 100 herstellen können?") when the bags' room limits, not the mats, the
  -- line says so: "Platz für 103 (Mats für 300, 6 freie Plätze)"; the game needs room for what a craft makes
  local function Limit(want)
    local n = row.n or 0
    if n >= want then return nil end
    if row.roomFree and (row.mats or 0) > n then
      return ("Platz für %d (Mats für %d, %d freie Plätze)"):format(n, math.min(row.mats, want), row.roomFree)
    end
    return want and ("Mats für %d"):format(n)
  end
  if row.step then
    if (row.n or 0) <= 0 and (row.mats or 0) > 0 and row.roomFree then
      return ("%d× %s"):format(row.crafts, name), "Taschen voll: 2 Plätze frei machen", "red", btn, true
    end
    return ("%d× %s"):format(row.crafts, name), Limit(row.crafts), "muted", btn, (row.n or 0) <= 0
  end
  if row.final then
    local n = row.n or 0
    if row.noRoom then
      return name, ("Taschen voll: 2 Plätze frei machen (Mats für %d)"):format(row.mats or 0), "red", btn, true
    end
    local t = n < row.runs and ("Mats für %d von %d"):format(n, row.runs) or nil
    if t and row.stepsLeft then t = ("jetzt %d von %d, der Rest nach den Schritten oben"):format(n, row.runs) end
    -- (Daniel 16.11.2026) the product goes as far as the mats; room only said
    if row.roomN then
      t = ("Platz für etwa %d (%d frei)"):format(row.roomN, row.roomFree or 0) -- (Daniel 16.11.2026: "bisschen übertrieben geschrieben")
    end
    return name, t, row.roomN and "yellow" or "muted", btn, n <= 0
  end
  return name, nil, nil, btn, (row.n or 0) <= 0
end
ns.DescribeRaw = DescribeRaw
ns.CraftWinDescribe = Describe

-- (Daniel 16.11.2026, Bild: "Sobald ich auf alle herstellen klicke, gerne irgendwo die insgesamte craftzeit anzeigen, die
-- darf auch gerne runterzählen ... oder kostet sekundliches runterzählen nicht so viel?") the foot line says how long the
-- crafts sent still take: "Noch 7:58 für 160× Heavy Blasting Powder". Every second one text is set, nothing worked out;
-- every finished craft sets the end anew from the crafts left (the measured cast time, Cr.CastTime). It ends with the
-- last craft, or when nothing is cast any more (stopped by hand, out of room).
local run, ticking
local function Clock(s)
  s = math.max(0, math.floor(s + 0.5))
  if s >= 3600 then return ("%d:%02d:%02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60) end
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end
local function RunText()
  if not run then return nil end
  return ("Noch %s für %d× %s"):format(Clock(run.endAt - GetTime()), run.left, run.name)
end
ns.CraftWinRunText = RunText -- (tests)
local function Foot()
  if not (panel and panel.foot) then return end
  if msg and GetTime() - (msgAt or 0) > MSG_SEC then msg = nil end
  panel.foot:SetText(RunText() or msg or HINT)
end
local function Tick()
  ticking = false
  if not run then return end
  if not ns.Busy() and GetTime() - run.lastAt > 3 then run = nil Foot() return end
  Foot()
  if panel and panel:IsShown() then ticking = true ns.After(1, Tick) end
end
local function StartRun(r, n)
  if not (r and n and n > 0) then return end
  local per = Cr.CastTime(r.spell)
  if not per or per <= 0 then per = 3 end
  local now = GetTime()
  run = { spell = r.spell, name = ns.ItemInfo(r.item) or ("Item " .. r.item), left = n, per = per, endAt = now + n * per, lastAt = now }
  if not ticking then ticking = true ns.After(1, Tick) end
  Foot()
end

local Draw
local function Click(row)
  -- a typed number makes that many (at most what the bags allow), and is used up by the click
  local typed = row and row.r and Want(row.r.spell)
  if typed and typed < (row.n or 0) then
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    copy.n = typed
    row = copy
  end
  if row and row.r then want[row.r.spell] = nil end
  local ok, text, sent = Cr.CraftRow(row)
  if ok then StartRun(row.r, sent) end
  msg, msgAt = text, GetTime()
  -- (Daniel 15.11.2026, Bild: "Stelle 320× ..." stood there while the button said 287) the answer goes after a while
  ns.After(MSG_SEC + 0.2, function() if ns.CraftWinRefresh then ns.CraftWinRefresh() end end)
  if ok and text then ns.Print(text) end
  if Draw then Draw() end
  return ok
end
ns.CraftWinClick = Click -- (tests)

-- (Daniel 11.11.2026, gewählt: "Taste stellt auch her"; 15.11.2026: here, not in the main window) the key binding presses
-- the next button of the jobs: the deepest step that can be made first, the product last
function ns.CraftClick()
  if not (panel and panel:IsShown()) then return false end
  local best
  for _, row in ipairs(Rows()) do
    if row.head and best then break end -- one job after the other
    if (row.step or row.final) and (row.n or 0) > 0 then
      if not best or (row.step and (best.final or row.depth > best.depth)) then best = row end
    end
  end
  if not best then return false end
  Click(best)
  return true
end

-- (Daniel 16.11.2026, Bild Kochen, Profitdon "Seasoned Wolf Kabob 203× herstellen", das Spiel zeigt Basic Campfire:
-- "möglich das es im berufefenster da hin springt, was ich bauen will? also beim öffnen erstmal zu dem, was ich zum schluss
-- bauen will ... bei klick in der einkaufsliste dann zu dem rezept, was ich gerade angeklickt habe") the game's window
-- shows a recipe: C_TradeSkillUI.OpenRecipe (the client has it, API documentation of 1.60.1). On opening the first
-- product of the list made in this profession, a click on a row its recipe. /profit diag line recipeJump says how it went.
local jumpAt
local function RowRecipe(row) return row and (row.r or (row.job and row.job.r)) or nil end
local function OpenProf()
  local T = C_TradeSkillUI
  local info = T and ns.Call(T.GetBaseProfessionInfo)
  return type(info) == "table" and ns.Num(info.professionID) or nil
end
-- (Daniel 16.11.2026, diag "recipeJump: OpenRecipe 6418", "springt nicht") OpenRecipe goes through without an error, but
-- the open window stays where it is. Within the open profession the recipe is chosen in the game's own list
-- (ProfessionsFrame.CraftingPage.RecipeList: SelectRecipe, else its selection by predicate, scrolled to it); OpenRecipe only
-- for another profession, and as the last try.
local function SelectInFrame(spell)
  local pf = rawget(_G, "ProfessionsFrame")
  local page = type(pf) == "table" and pf.CraftingPage
  local list = type(page) == "table" and page.RecipeList
  if type(list) ~= "table" then return false, "keine RecipeList" end
  local T = C_TradeSkillUI
  local info = T and T.GetRecipeInfo and ns.Call(T.GetRecipeInfo, spell)
  if type(list.SelectRecipe) == "function" and type(info) == "table" then
    local ok, el = pcall(list.SelectRecipe, list, info, true)
    if ok and el ~= nil then return true, "SelectRecipe" end
  end
  local sb = list.selectionBehavior
  if type(sb) == "table" and type(sb.SelectElementDataByPredicate) == "function" then
    local function pred(node)
      local d = type(node) == "table" and node.GetData and node:GetData() or node
      return type(d) == "table" and type(d.recipeInfo) == "table" and d.recipeInfo.recipeID == spell
    end
    local ok, el = pcall(sb.SelectElementDataByPredicate, sb, pred)
    if ok and el then
      local box = list.ScrollBox
      if type(box) == "table" and box.ScrollToElementData then pcall(box.ScrollToElementData, box, el) end
      return true, "Auswahl"
    end
  end
  return false, ("nicht gefunden (SelectRecipe %s, Auswahl %s, Rezeptinfo %s)"):format(type(list.SelectRecipe) == "function" and "da" or "fehlt",
    type(sb) == "table" and "da" or "fehlt", type(info) == "table" and "da" or "fehlt")
end
ns.CraftWinSelectInFrame = SelectInFrame -- (tests)
local function Jump(r)
  local T = C_TradeSkillUI
  if not (r and r.spell and T) then return false end
  local how
  if r.prof == OpenProf() then
    local ok, text = SelectInFrame(r.spell)
    if ok then ns.Fact("recipeJump", text .. " " .. r.spell) return true end
    how = text
  end
  if type(T.OpenRecipe) ~= "function" then ns.Fact("recipeJump", (how or "") .. ", kein OpenRecipe") return false end
  jumpAt = GetTime()
  local ok, err = pcall(T.OpenRecipe, r.spell)
  ns.Fact("recipeJump", (how and (how .. ", dann ") or "") .. (ok and ("OpenRecipe " .. r.spell) or ("Fehler: " .. tostring(err))))
  return ok
end
ns.CraftWinJump = function(row) return Jump(RowRecipe(row)) end -- (tests, and the rows' click)
-- on opening: the first product of the list in the open profession, else its first step there
-- (Daniel 16.11.2026: "beim 2. mal öffnen ist er gesprungen") at the first opening the game's list is not ready yet or
-- chooses its last recipe after it: the opening tries again later, then only in the list (listOnly)
local function JumpFirst(rows, listOnly)
  -- the window opened by the jump itself (another profession) does not jump again
  if jumpAt and GetTime() - jumpAt < 2 then return end
  local prof = OpenProf()
  if not prof then return end
  local first, step
  for _, row in ipairs(rows or {}) do
    local r = RowRecipe(row)
    if r and r.prof == prof and not row.mat then
      if row.final then first = r break end
      step = step or r
    end
  end
  first = first or step
  if not first then return end
  if listOnly then
    local ok, text = SelectInFrame(first.spell)
    if ok then ns.Fact("recipeJump", text .. " " .. first.spell .. " (später)") end
  else Jump(first) end
end

---------------------------------------------------------------------------
-- The view (DonCore kit: Kit.Window, a Kit.List with a row kind of its own)
---------------------------------------------------------------------------
local ROW_H, INDENT = 28, 16
local function MakeRow(list)
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
  local C = Kit.C
  local r = CreateFrame("Frame", nil, list)
  r:SetHeight(ROW_H)
  r.bg = Kit.Fill(r, C.row)
  r.line = Kit.Tex(r, "ARTWORK", C.gold)
  r.line:SetPoint("BOTTOMLEFT") r.line:SetPoint("BOTTOMRIGHT") r.line:SetHeight(1)
  r.icon = Kit.ItemIcon(r, 20)
  r.title = Kit.Text(r, "row", C.body)
  r.info = Kit.Text(r, "sub", C.muted, "RIGHT")
  r.btn = Kit.Button(r, "", { small = true, kind = "primary", onClick = function() if r.item and r.item.row then ns.Try(Click, r.item.row) end end })
  r.x = Kit.Button(r, "x", { small = true, onClick = function()
    local row = r.item and r.item.row
    if row and row.job then Cr.JobRemove(row.job.spell) msg = nil if Draw then Draw() end end
  end })
  if r.x.SetTooltip then r.x:SetTooltip("Aus dem Herstellfenster nehmen", { "Die Mats bleiben in den Taschen." }) end
  local function commit(box)
    local row = r.item and r.item.row
    if not (row and row.r) then return end
    local n = box:GetValue()
    local before = Want(row.r.spell)
    ns.CraftWinSetWant(row.r.spell, n and n < (row.n or 0) and n or nil)
    if Want(row.r.spell) ~= before and Draw then Draw() end
  end
  r.num = Kit.EditBox(r, { numeric = true, min = 1, width = 44, onEnter = commit, onLeave = commit })
  if r.num.SetTooltip then r.num:SetTooltip("Wie viele herstellen (Enter oder Tab)") end
  r:EnableMouse(true)
  r:SetScript("OnMouseUp", function(self) if self.item and self.item.row then ns.Try(ns.CraftWinJump, self.item.row) end end)
  function r:SetItem(it)
    self.item = it
    local row = it.row
    local title, info, color, btn, off = Describe(row)
    local plain = row.section or row.note
    Kit.SetColor(self.bg, (row.section or row.head) and C.card or C.row)
    self.line:SetShown(row.section and true or false)
    if row.id and not plain then
      local _, _, q = ns.ItemInfo(row.id)
      self.icon:SetItem(row.id, nil, q)
      self.icon:Show()
      Kit.TextColor(self.title, (row.mat and C.muted) or (q and Kit.QualityColor(q)) or C.body)
    else
      self.icon:Hide()
      Kit.TextColor(self.title, row.section and C.txGold or row.need == "red" and C.red or row.need and C.hero or C.quiet)
    end
    self.title:SetText(title or "")
    self.info:SetText(info or "")
    Kit.TextColor(self.info, color == "red" and C.red or color == "green" and C.green or color == "yellow" and (C.yellow or C.gold)
      or color == "white" and C.hero or C.muted)
    if btn then
      self.btn:SetText(btn)
      self.btn:SetDisabled(off and true or false)
      self.btn:Show()
    else self.btn:Hide() end
    local box = btn and not off and (row.n or 0) > 1
    if box and not self.num._focus then self.num:SetValue(math.min(Want(row.r.spell) or row.n, row.n)) end
    self.num:SetShown(box and true or false)
    self.x:SetShown(row.head and true or false)
    self:Layout(self._w or self:GetWidth())
  end
  function r:Layout(w)
    w = tonumber(w) or 0
    self._w = w
    local it = self.item
    local row = it and it.row
    if not row then return end
    local x = 8 + (row.depth or 0) * INDENT
    self.icon:ClearAllPoints() self.icon:SetPoint("LEFT", x, 0)
    if self.icon:IsShown() or row.pad then x = x + 20 + 6 end
    local right = 8
    if self.btn:IsShown() then
      self.btn:ClearAllPoints() self.btn:SetPoint("RIGHT", -right, 0)
      right = right + (self.btn:GetWidth() or 120) + 6
    end
    if self.num:IsShown() then
      self.num:ClearAllPoints() self.num:SetPoint("RIGHT", -right, 0)
      right = right + 44 + 6
    end
    if self.x:IsShown() then
      self.x:ClearAllPoints() self.x:SetPoint("RIGHT", -right, 0)
      right = right + (self.x:GetWidth() or 20) + 6
    end
    self.info:ClearAllPoints() self.info:SetPoint("RIGHT", -right, 0)
    local iw = (self.info:GetText() or "") ~= "" and math.min(Kit.TextWidth(self.info) or 60, 140) + 6 or 0
    self.title:ClearAllPoints() self.title:SetPoint("LEFT", x, 0)
    Kit.Fit(self.title, math.max(20, w - x - right - iw))
  end
  return r
end

---------------------------------------------------------------------------
-- The view from Blizzard's templates (DonCore module Blizz, before 16.11. Blizz.lua; Daniel 15.11.2026: "1 zu 1 wie Blizzards Fenster"): the frame of the
-- profession window, the game's list and scroll bar, red buttons, the game's fonts. A section is a gold line of text, a
-- head the product in gold, the rows below in white with the item's quality colour
---------------------------------------------------------------------------
local function BzRow(r, row)
  local Bz = ns.Blizz
  if not r.built then
    r.built = true
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.hl:SetBlendMode("ADD")
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetColorTexture(1, 0.82, 0, 0.35)
    r.rule:SetHeight(1)
    r.rule:SetPoint("BOTTOMLEFT", 2, 1) r.rule:SetPoint("BOTTOMRIGHT", -2, 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.title = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.info = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.info:SetJustifyH("RIGHT")
    r.btn = Bz.Button(r, "", function() if r.row then Click(r.row) end end)
    r.x = Bz.Button(r, "x", function()
      if r.row and r.row.job then Cr.JobRemove(r.row.job.spell) msg = nil if Draw then Draw() end end
    end)
    r.x:SetWidth(22)
    r.x.tooltipText = "Aus dem Herstellfenster nehmen (die Mats bleiben in den Taschen)"
    local function commit(box)
      local cur = r.row
      if not (cur and cur.r) then return end
      local n = box:GetValue()
      local before = Want(cur.r.spell)
      ns.CraftWinSetWant(cur.r.spell, n and n < (cur.n or 0) and n or nil)
      if Want(cur.r.spell) ~= before and Draw then Draw() end
    end
    r.num = Bz.kit.EditBox(r, { numeric = true, width = 44, onEnter = commit, onLeave = commit })
    r.num:SetTooltip("Wie viele herstellen (Enter oder Tab)")
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      local id = self.row and not (self.row.section or self.row.note) and self.row.id
      if not (id and GameTooltip and GameTooltip.SetItemByID) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      ns.Blizz.NoCompare(GameTooltip)
      ns.Call(GameTooltip.SetItemByID, GameTooltip, id)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnMouseUp", function(self) if self.row then ns.Try(ns.CraftWinJump, self.row) end end)
  end
  r.row = row
  local title, info, color, btn, off = Describe(row)
  local plain = row.section or row.note
  r.rule:SetShown(row.section and true or false)
  r.hl:SetShown(not plain)
  if row.id and not plain then
    local _, _, q = ns.ItemInfo(row.id)
    r.icon:SetTexture(ns.Icon(row.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:Show()
    if row.head then r.title:SetTextColor(1, 0.82, 0)
    elseif row.mat then r.title:SetTextColor(0.8, 0.8, 0.8)
    else r.title:SetTextColor(Bz.QualityRGB(q)) end
  else
    r.icon:Hide()
    if row.section then r.title:SetTextColor(1, 0.82, 0)
    elseif row.need == "red" then r.title:SetTextColor(1, 0.1, 0.1)
    elseif row.need then r.title:SetTextColor(1, 1, 1)
    else r.title:SetTextColor(0.5, 0.5, 0.5) end
  end
  r.title:SetText(title or "")
  r.info:SetText(info or "")
  if color == "red" then r.info:SetTextColor(1, 0.1, 0.1) elseif color == "green" then r.info:SetTextColor(0.1, 1, 0.1)
  elseif color == "yellow" then r.info:SetTextColor(1, 0.82, 0) elseif color == "white" then r.info:SetTextColor(1, 1, 1)
  else r.info:SetTextColor(0.5, 0.5, 0.5) end
  if btn then
    r.btn:Label(btn)
    r.btn:SetEnabled(not off)
    r.btn:Show()
  else r.btn:Hide() end
  r.x:SetShown(row.head and true or false)
  local box = btn and not off and (row.n or 0) > 1
  if box and not r.num._focus then r.num:SetValue(math.min(Want(row.r.spell) or row.n, row.n)) end
  r.num:SetShown(box and true or false)
  local x = 4 + (row.depth or 0) * INDENT
  r.icon:ClearAllPoints() r.icon:SetPoint("LEFT", x, 0)
  if (row.id and not plain) or row.pad then x = x + 18 + 5 end
  local right = 4
  r.btn:ClearAllPoints() r.btn:SetPoint("RIGHT", -right, 0)
  if btn then right = right + (r.btn:GetWidth() or 120) + 6 end
  if box then
    r.num:ClearAllPoints() r.num:SetPoint("RIGHT", -right, 0)
    right = right + 44 + 8
  end
  r.x:ClearAllPoints() r.x:SetPoint("RIGHT", -right, 0)
  if row.head then right = right + 22 + 6 end
  r.info:ClearAllPoints() r.info:SetPoint("RIGHT", -right, 0)
  r.title:ClearAllPoints()
  r.title:SetPoint("LEFT", x, 0)
  r.title:SetPoint("RIGHT", r.info, "LEFT", -6, 0)
end
ns.CraftWinBzRow = BzRow -- (tests)

local function ReqSig(rows)
  local sig = {}
  for _, row in ipairs(rows) do
    local r = not (row.section or row.note or row.head or row.mat) and row.r
    local need, _, _, flags = Reqs(r and r.spell)
    if need then sig[#sig + 1] = flags end
  end
  return #sig > 0 and table.concat(sig, ";") or nil
end
-- walking to a fire or away: no event says so; once a second the flags of the rows shown, a redraw when one changed
local reqPolling
local function ReqPoll()
  reqPolling = nil
  if not (panel and panel:IsShown() and reqState) then return end
  local sig = ReqSig(panel.rows or {})
  if sig ~= reqState then ns.CraftWinRefresh() return end
  reqPolling = true
  ns.After(1, ReqPoll)
end
function Draw()
  if not (panel and panel:IsShown()) then return end
  local rows = Rows()
  panel.rows = rows
  reqState = ReqSig(rows)
  if reqState and not reqPolling then reqPolling = true ns.After(1, ReqPoll) end
  if panel.blizz then
    -- the list has rows of one height: the second section stands off by an empty row
    local out = {}
    for _, row in ipairs(rows) do
      if row.gap then out[#out + 1] = { note = true, text = "" } end
      out[#out + 1] = row
      out[#out + 1] = NeedRow(row)
    end
    panel.items = out
    panel.list:SetRows(out)
    Foot()
    if run and not ticking then ticking = true ns.After(1, Tick) end
    return
  end
  local items = {}
  for _, row in ipairs(rows) do
    items[#items + 1] = { kind = "pcraft", row = row, h = row.gap and ROW_H + 10 or nil }
    local need = NeedRow(row)
    if need then items[#items + 1] = { kind = "pcraft", row = need, h = 18 } end
  end
  panel.items = items
  panel.list:SetItems(items)
  Foot()
  if run and not ticking then ticking = true ns.After(1, Tick) end
end
ns.CraftWinRefresh = function() if panel and panel:IsShown() then ns.Perf("Herstellfenster", ns.Try, Draw) end end

-- (Daniel 15.11.2026, Bild: "beim öffnen verschwindet es noch hinter der berufeliste") the profession window carries
-- the tabs of the other professions outside its right edge: how far its shown children reach over that edge (at most
-- MAX_HANG, so a stray wide child cannot push the window away)
local MAX_HANG = 120
local function Overhang(f)
  local right = ns.Num(ns.Call(f.GetRight, f))
  if not right or type(f.GetChildren) ~= "function" then return 0 end
  local over = 0
  -- the tabs may sit in a holder frame without a size of its own: children and their children
  local function look(p, depth)
    if type(p.GetChildren) ~= "function" then return end
    for _, c in ipairs({ p:GetChildren() }) do
      if type(c) == "table" and c.IsShown and ns.Call(c.IsShown, c) then
        local l, r = ns.Num(ns.Call(c.GetLeft, c)), ns.Num(ns.Call(c.GetRight, c))
        -- a tab stands at the edge: it starts near it and ends beyond it
        if l and r and l >= right - 30 and r > right and r - right <= MAX_HANG then over = math.max(over, r - right) end
        if depth < 2 then look(c, depth + 1) end
      end
    end
  end
  look(f, 1)
  if over > 0 then return over end
  -- (Daniel 15.11.2026, second picture: "hängt immer noch hinter") the tabs are no children of the window: any visible
  -- frame on screen that starts at its right edge, ends beyond it and lies within its height counts, measured in
  -- screen pixels (frames have scales of their own); the Herstellfenster and its parts do not
  local next_ = rawget(_G, "EnumerateFrames")
  if type(next_) ~= "function" then return 0 end
  local fs = ns.Num(ns.Call(f.GetEffectiveScale, f)) or 1
  local top, bottom = ns.Num(ns.Call(f.GetTop, f)), ns.Num(ns.Call(f.GetBottom, f))
  if not (top and bottom) then return 0 end
  local R, T, B = right * fs, top * fs, bottom * fs
  local function mine(c)
    for _ = 1, 8 do
      if c == panel then return true end
      c = type(c) == "table" and c.GetParent and c:GetParent() or nil
      if not c then return false end
    end
    return false
  end
  local c = next_()
  local guard = 0
  while c and guard < 20000 do
    guard = guard + 1
    if c ~= f and type(c.IsVisible) == "function" and c:IsVisible() and not (c.IsForbidden and c:IsForbidden()) then
      local s = ns.Num(ns.Call(c.GetEffectiveScale, c)) or 1
      local l, r, t, b = ns.Num(ns.Call(c.GetLeft, c)), ns.Num(ns.Call(c.GetRight, c)), ns.Num(ns.Call(c.GetTop, c)), ns.Num(ns.Call(c.GetBottom, c))
      if l and r and t and b then
        l, r, t, b = l * s, r * s, t * s, b * s
        local hang = r - R
        if l >= R - 30 * fs and l <= R + 12 * fs and hang > 4 and hang <= MAX_HANG * fs and t <= T + 10 and b >= B - 10 and not mine(c) then
          over = math.max(over, hang / fs)
        end
      end
    end
    c = next_(c)
  end
  return over
end
ns.CraftWinOverhang = Overhang -- (tests)

local function Place()
  if not panel then return end
  local st = ns.db.craftWin
  if panel.blizz then
    if panel:Restore() then return end -- moved by hand: stays there
  elseif st and st.point then return end
  local f = ProfFrame()
  panel:ClearAllPoints()
  if f then panel:SetPoint("TOPLEFT", f, "TOPRIGHT", 8 + Overhang(f), 0) else panel:SetPoint("CENTER", 200, 60) end
end

local function BuildBlizz()
  local Bz = ns.Blizz
  local win = Bz.Window("ProfitdonCraftFrame", { title = "Profitdon", icon = "Interface\\AddOns\\Profitdon\\Media\\portrait", store = ns.db.craftWin,
    width = 384, height = 460, min = { 300, 240 }, max = { 800, 1000 } })
  win.blizz = true
  win.list = Bz.List(win.inset, { init = BzRow })
  win.list:Place(win.inset, 6, 6, 24, 24)
  win.foot = win.inset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  win.foot:SetJustifyH("LEFT")
  win.foot:SetWordWrap(false)
  win.foot:SetPoint("BOTTOMLEFT", win.inset, "BOTTOMLEFT", 8, 7)
  win.foot:SetPoint("BOTTOMRIGHT", win.inset, "BOTTOMRIGHT", -22, 7)
  win:Hide()
  return win
end

local function Build()
  ns.db.craftWin = type(ns.db.craftWin) == "table" and ns.db.craftWin or {}
  -- (Daniel 15.11.2026) Blizzard's own templates when the client has them all, else the kit's window as before
  if ns.BlizzReady() then
    local ok, win = pcall(BuildBlizz)
    if ok and win then panel = win return end
    ns.Fact("blizzLook", "Fehler: " .. tostring(win))
    ns.SayLook()
    local broken = rawget(_G, "ProfitdonCraftFrame")
    if type(broken) == "table" and broken.Hide then pcall(broken.Hide, broken) end
  end
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
  panel = Kit.Window("ProfitdonCraftFrame", { title = "Profitdon herstellen", compact = true, store = ns.db.craftWin, width = 420,
    height = 440, min = { 320, 220 }, max = { 800, 1000 },
    onLayout = function(win, w, h)
      if not (win.list and win.foot) then return end
      win.list:ClearAllPoints() win.list:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, 0)
      win.list:Resize(w, math.max(40, h - 22))
      win.foot:ClearAllPoints() win.foot:SetPoint("BOTTOMLEFT", win.body, "BOTTOMLEFT", 8, 4)
      Kit.Fit(win.foot, math.max(40, w - 16))
    end })
  panel.list = Kit.List(panel.body, { zebra = false, kinds = { pcraft = { make = MakeRow, h = ROW_H } } })
  panel.foot = Kit.Text(panel.body, "sub", Kit.C.muted)
  panel:Layout()
  panel:Hide()
end

local openN = 0
local function Open()
  if not ns.db then return end
  if not panel then ns.Try(Build) end
  if not panel then return end
  ns.Try(Place)
  -- the tabs at the edge come a moment after the window
  ns.After(0.3, function() if panel and panel:IsShown() then ns.Try(Place) end end)
  msg = nil
  panel:Show()
  ns.Try(Draw)
  -- the game's list comes a moment after the window (and at the first opening chooses its last recipe after that)
  openN = openN + 1
  local mine = openN
  local function later(listOnly)
    if mine ~= openN or not (panel and panel:IsShown() and panel.items) then return end
    local rows = {}
    for _, it in ipairs(panel.items) do rows[#rows + 1] = it.row or it end
    ns.Try(JumpFirst, rows, listOnly)
  end
  -- (the recipe is of the open profession: OpenRecipe does not move the open window, only the list does)
  ns.After(0.5, function() later(true) end)
  ns.After(1.5, function() later(true) end)
  ns.After(3, function() later(true) end)
  -- once the tabs are there: which window it docks to and how far they hang over (for /profit diag)
  ns.After(0.4, function()
    local pf, name = ProfFrame()
    ns.Fact("craftWinDock", name and ("%s, Reiter stehen %d px über%s"):format(name, pf and Overhang(pf) or 0,
      panel and panel.blizz and panel.bz and panel.bz.point and ", von Hand verschoben" or "") or "kein Berufsfenster gefunden")
  end)
end
ns.CraftWinPanel = function() return panel end -- (tests)
ns.CraftWinReset = function() if panel then panel:Hide() end panel = nil end -- (tests: build the window anew)

ns.On("TRADE_SKILL_SHOW", Open)
ns.On("TRADE_SKILL_CLOSE", function() if panel then panel:Hide() end end)
-- (Daniel 16.11.2026: "taschenplätze für alle herstellen - da reicht es doch zu schauen, wenn man nicht mehr castet und
-- nicht in der warteschleife ist und dann neu craften will") the counts are worked out once the crafting stops
local function RefreshSoon()
  if not (panel and panel:IsShown()) then return end
  ns.WhenIdle("Herstellfenster", ns.CraftWinRefresh, 0.3)
end
-- (Daniel 16.11.2026, Bild "Alle herstellen (69)" while the cast bar ran: "hier runter zählen darf er aber schon bitte",
-- "das kann ja nicht viel kosten") every finished craft counts its rows down by one on what is shown, nothing worked out
-- anew: the step or product of that recipe (its button and count), and the job's head. The full count follows once idle.
function ns.CraftWinTick(spell)
  spell = ns.Num(spell)
  if run and spell == run.spell then
    local now = GetTime()
    run.left, run.lastAt = run.left - 1, now
    run.endAt = now + run.left * run.per
    if run.left <= 0 then run = nil end
    Foot()
  end
  if not (spell and panel and panel:IsShown() and panel.items) then return end
  local hit = false
  local function down(k, row) if row[k] then row[k] = math.max(0, row[k] - 1) end end
  for _, it in ipairs(panel.items) do
    local row = it.row or it
    if row.r and row.r.spell == spell and (row.step or row.final or row.other) then
      down("n", row)
      if row.step then down("crafts", row) end
      if row.final then down("runs", row) end
      hit = true
    elseif row.head and row.job and row.job.spell == spell then
      down("runs", row)
      hit = true
    end
  end
  if not hit then return end
  if panel.blizz then panel.list:SetRows(panel.items) else panel.list:SetItems(panel.items) end
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spell) if unit == "player" then ns.Try(ns.CraftWinTick, spell) end end)
ns.On("TRADE_SKILL_LIST_UPDATE", RefreshSoon)
-- (Daniel 16.11.2026: "unten dürfte sich auch mitändern und muss nicht stehen bleiben") while a step is being made, the
-- product's count follows the bags at once (its mats only, the room keeps its last word); the full count once idle
function ns.CraftWinLive()
  if not (panel and panel:IsShown() and panel.items) then return end
  local hit = false
  for _, it in ipairs(panel.items) do
    local row = it.row or it
    if row.final and row.r and not row.noRoom then
      local m = Cr.MatsNow(row.r)
      local n = math.min(row.runs or 0, m, row.roomN or math.huge)
      if n ~= row.n then row.n, row.mats, hit = n, m, true end
    end
  end
  if hit then
    if panel.blizz then panel.list:SetRows(panel.items) else panel.list:SetItems(panel.items) end
  end
end
ns.On("BAG_UPDATE_DELAYED", function()
  if panel and panel:IsShown() then ns.Try(ns.CraftWinLive) end
  RefreshSoon()
end)
ns.On("GET_ITEM_INFO_RECEIVED", RefreshSoon)
