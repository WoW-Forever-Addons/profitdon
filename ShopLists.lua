-- Profitdon: own shopping lists (Daniel 19.11.2026: "dass man die auch wirklich eigene Listen pflegen kann ... meine
-- Route mit den Writs ... damit man die immer wieder kaufen kann", "wenn ich später Barfood haben will", "Listen
-- erstellen mit Namen, die ich mir ausdenke")
-- ProfitdonDB.shopLists = { { id, name, items = { { item = id | writ = quest, n, fixed } } } }, ProfitdonDB.shopListNext
-- An entry is a recipe of its own for Crafts.ShoppingList (as the Favor crates and the writs on the main list):
--   item: spell "list:<id>:i<item>", result and only reagent the item, so the item is bought or (cheaper) made
--   writ: Writs.Recipe (the writ item and its ware)
-- n is a stock to hold (the bags are taken off) or, fixed, the amount bought every time whatever the bags hold
-- (Daniel: "Beides je Eintrag"). A list stays as it is after buying; it is bought again the next time.
-- (Daniel: "Wenn ich es selber herstellen kann oder einer meiner Chars, soll das Endergebnis und ggf. die einzelnen Mats,
-- wenn es günstiger ist") the list counts the recipes of all characters of the realm (Crafts.anyChar).
local _, ns = ...
local SL = {}
ns.ShopLists = SL

local function Store()
  ns.db.shopLists = type(ns.db.shopLists) == "table" and ns.db.shopLists or {}
  return ns.db.shopLists
end
function SL.All() return Store() end
function SL.Get(id)
  for i, l in ipairs(Store()) do if l.id == id then return l, i end end
end
function SL.New(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  local id = math.max(1, math.floor(tonumber(ns.db.shopListNext) or 1))
  for _, l in ipairs(Store()) do if (l.id or 0) >= id then id = l.id + 1 end end
  ns.db.shopListNext = id + 1
  local l = { id = id, name = name, items = {} }
  table.insert(Store(), l)
  return l
end
function SL.Rename(id, name)
  local l = SL.Get(id)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if l and name ~= "" then l.name = name return true end
end
function SL.Delete(id)
  local _, i = SL.Get(id)
  if i then table.remove(Store(), i) return true end
end

local function Same(a, kind, key) return (kind == "writ" and a.writ == key) or (kind == "item" and a.item == key) end
-- the entry of an item or writ in a list, and its place
function SL.Find(id, kind, key)
  local l = SL.Get(id)
  for i, e in ipairs(l and l.items or {}) do if Same(e, kind, key) then return e, i end end
end
-- adds (or, already there, keeps) an item or a writ; n defaults to 1, a new entry holds a stock
function SL.Add(id, kind, key, n, fixed)
  local l = SL.Get(id)
  key = tonumber(key)
  if not (l and key and (kind == "item" or kind == "writ")) then return nil end
  local e = SL.Find(id, kind, key)
  if e then
    if n then e.n = math.max(1, math.floor(tonumber(n) or 1)) end
    return e, true
  end
  e = { n = math.max(1, math.floor(tonumber(n) or 1)), fixed = fixed and true or nil }
  e[kind] = key
  table.insert(l.items, e)
  return e
end
function SL.Remove(id, kind, key)
  local l = SL.Get(id)
  local _, i = SL.Find(id, kind, key)
  if l and i then table.remove(l.items, i) return true end
end
function SL.SetN(id, kind, key, n)
  local e = SL.Find(id, kind, key)
  n = tonumber(n)
  if e and n and n >= 1 then e.n = math.floor(n) return true end
end
function SL.SetFixed(id, kind, key, fixed)
  local e = SL.Find(id, kind, key)
  if e then e.fixed = fixed and true or nil return true end
end

-- the recipe of an item entry: the item is its own reagent, so Crafts.ShoppingList buys it or makes it, whichever is cheaper
function SL.ItemRecipe(lid, item)
  return { spell = ("list:%d:i%d"):format(lid, item), item = item, reag = { { item, 1 } }, count = 1, listItem = item }
end
-- the entries for Crafts.ShoppingList: { r, runs, list, kind, key, fixed, anyChar }
function SL.Entries(id)
  local l = SL.Get(id)
  local out = {}
  for _, e in ipairs(l and l.items or {}) do
    local r, kind, key
    if e.writ then
      r = ns.Writs and ns.Writs.Recipe(e.writ)
      if r then
        local c = {}
        for k, v in pairs(r) do c[k] = v end
        c.spell = ("list:%d:w%d"):format(id, e.writ)
        r = c
      end
      kind, key = "writ", e.writ
    elseif e.item then
      r, kind, key = SL.ItemRecipe(id, e.item), "item", e.item
    end
    if r then
      out[#out + 1] = { r = r, runs = math.max(1, e.n or 1), list = id, kind = kind, key = key, fixed = e.fixed or nil, anyChar = true,
        writ = kind == "writ" and key or nil }
    end
  end
  return out
end

-- the list shown last in the window: the merchant's "Mats kaufen" buys for it (nil: the main list)
function SL.SetActive(id) SL.active = id end
function SL.ActiveEntries()
  local id = SL.active
  if id and SL.Get(id) then return SL.Entries(id) end
end
