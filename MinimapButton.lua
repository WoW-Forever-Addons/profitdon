local _, ns = ...

---------------------------------------------------------------------------
-- Profitdon's minimap button (DonCore MinimapButton minor 4, as every Don addon: gold ring, switch in the options).
-- Left click: the window, right click: menu, drag: move. Angle ProfitdonDB.minimapAngle, 300 degrees beside Golddon's 275.
---------------------------------------------------------------------------
local function Try(fn, ...) if ns.Try then return ns.Try(fn, ...) end return fn(...) end
local function Window(where) return function() if ns.ToggleWindow then Try(ns.ToggleWindow, true, where) end end end

local function Lines()
  local out = {}
  local L = ns.lists
  if L and L.t then
    out[#out + 1] = { "Unter Händlerpreis", tostring(#(L.vendor or {})) }
    out[#out + 1] = { "Zum Entzaubern im AH", tostring(#(L.de or {})) }
  end
  return out
end

LibStub("DonCore-1.0"):Get("MinimapButton", 4):Attach(ns, {
  name = "ProfitdonMinimapButton", addon = "Profitdon",
  icon = "Interface\\AddOns\\Profitdon\\Media\\minimap",
  angleKey = "minimapAngle", defaultAngle = 300,
  enabled = function() return ns.Opt("minimapButton") ~= false end,
  setEnabled = function(v) if ns.db and ns.db.opt then ns.db.opt.minimapButton = v and true or false end end,
  title = ns.NAME,
  lines = Lines,
  hint = "Linksklick: Fenster. Rechtsklick: Menü. Ziehen: verschieben.",
  onLeft = function() if ns.ToggleWindow then Try(ns.ToggleWindow) end end,
  menu = { name = "ProfitdonMinimapMenu", width = 230, items = function()
    return {
      { text = "Herstellen", onClick = Window("craft") },
      { text = "Entzaubern", onClick = Window("deah") },
      { text = "Unter Händlerpreis", onClick = Window("vendor") },
      { text = "Mats verkaufen", onClick = Window("sell") },
      { text = "Auswertung", onClick = Window("report") },
      { line = true },
      { text = "Alle Optionen", onClick = function() if ns.OpenOptions then Try(ns.OpenOptions) end end },
    }
  end },
})

ns.OnInit(function() ns.RefreshMinimapButton() end)
