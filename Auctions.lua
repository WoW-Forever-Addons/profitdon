local _, ns = ...
---------------------------------------------------------------------------
-- (Daniel 24.11.2026, Bild Kaufen Raptor Egg: "meine eigenen auktionen fehlen mir irgendwie noch"; gewählt "Eigene Liste
-- aller Auktionen" als eigener Reiter "Auktionen", unterboten = ein fremdes Angebot ist billiger) the character's own
-- auctions as the game lists them (C_AuctionHouse.QueryOwnedAuctions, OWNED_AUCTIONS_UPDATED): item, count, price a
-- piece, time left, the cheapest offer of others (a search newer than the scan, else the last full scan, which leaves
-- the own auctions out) and cancelling with a second click. The list is kept per character (ProfitdonDB.myAuc), so the
-- tab shows the last state away from the auction house too.
---------------------------------------------------------------------------
local A = {}
ns.MyAuctions = A
A.CONFIRM_SEC = 5
-- the game's rough time left when it gives no seconds (Enum.AuctionHouseTimeLeftBand)
local BAND = { [0] = 1800, [1] = 7200, [2] = 43200, [3] = 172800 }

local function Store()
  ns.db.myAuc = ns.db.myAuc or {}
  local me = ns.Me()
  local s = ns.db.myAuc[me]
  if type(s) ~= "table" then s = { list = {} } ns.db.myAuc[me] = s end
  s.list = type(s.list) == "table" and s.list or {}
  return s
end
function A.List() return Store().list end
function A.ReadAt() return Store().t end

-- the auctions read from the game; o as C_AuctionHouse.GetOwnedAuctionInfo gives it
function A.FromInfo(o)
  if type(o) ~= "table" or type(o.itemKey) ~= "table" then return nil end
  local id = ns.Num(o.itemKey.itemID)
  if not id then return nil end
  local left = ns.Num(o.timeLeftSeconds) or BAND[ns.Num(o.timeLeft) or -1]
  return { auc = ns.Num(o.auctionID), id = id, link = type(o.itemLink) == "string" and o.itemLink or nil,
    qty = math.max(1, ns.Num(o.quantity) or 1), unit = ns.Num(o.buyoutAmount), bid = ns.Num(o.bidAmount), left = left,
    sold = (ns.Num(o.status) or 0) ~= 0 or nil }
end

function A.Read()
  local AH = ns.AH
  if not (type(AH) == "table" and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then return false end
  if AH.HasFullOwnedAuctionResults and ns.Call(AH.HasFullOwnedAuctionResults) == false then return false end
  local n = ns.Num(ns.Call(AH.GetNumOwnedAuctions)) or 0
  local out = {}
  for i = 1, n do
    local e = A.FromInfo(ns.Call(AH.GetOwnedAuctionInfo, i))
    if e then out[#out + 1] = e end
  end
  local s = Store()
  s.list, s.t = out, time()
  if A.sel and not A.Find(A.sel) then A.sel, A.armed = nil, nil end
  return true
end

-- ask the game for the list (the AH must be open); not more than once in 2 seconds
local lastAsk = 0
function A.Query(force)
  if not (ns.ScanState and ns.ScanState.open) then return false end
  if not force and GetTime() - lastAsk < 2 then return false end
  local AH = ns.AH
  if not (type(AH) == "table" and AH.QueryOwnedAuctions) then return false end
  lastAsk = GetTime()
  ns.Call(AH.QueryOwnedAuctions, {})
  return true
end

function A.Find(auc)
  for _, e in ipairs(A.List()) do if e.auc == auc then return e end end
  return nil
end

-- seconds left now (the time read counted off)
function A.Left(e)
  if not e.left then return nil end
  return math.max(0, e.left - (time() - (A.ReadAt() or time())))
end
function A.LeftText(e)
  if e.sold then return "verkauft" end
  local s = A.Left(e)
  if not s then return "?" end
  if s < 1800 then return "< 30 min" end
  if s < 7200 then return ("%d min"):format(math.floor(s / 60)) end
  if s < 86400 then return ("%d h"):format(math.floor(s / 3600)) end
  return ("%d T %d h"):format(math.floor(s / 86400), math.floor((s % 86400) / 3600))
end

-- the cheapest offer of others: a search newer than the scan (ns.fresh, the own ones left out there), else the scan
function A.Other(id)
  local P = ns.Prices
  local f = ns.fresh and ns.fresh[id]
  local st = P.Store()
  if f and f.p and (not st or (f.t or 0) >= (P.RowTime(id) or st.t or 0)) then return f.p end
  if P.Row(nil, id) then return P.Low(id) end
  return nil
end
-- "under": an offer of others is cheaper; "same": as cheap; nil: the own one is the cheapest or nothing known
function A.State(e)
  if e.sold or not e.unit then return nil end
  local o = A.Other(e.id)
  if not o then return nil end
  if o < e.unit then return "under", o end
  if o == e.unit then return "same", o end
  return nil, o
end

-- the cancel button: the first click arms, the second within A.CONFIRM_SEC cancels
function A.Cost(e)
  local AH = ns.AH
  if not (e and e.auc and type(AH) == "table" and AH.GetCancelCost) then return nil end
  return ns.Num(ns.Call(AH.GetCancelCost, e.auc))
end
function A.Armed(e) return A.armed and e and A.armed.auc == e.auc and GetTime() - A.armed.t < A.CONFIRM_SEC end
function A.CancelClick(e)
  if not (e and e.auc and not e.sold) then return false end
  if not (ns.ScanState and ns.ScanState.open) then ns.Print("Zum Abbrechen das Auktionshaus öffnen.") return false end
  if not A.Armed(e) then
    A.armed = { auc = e.auc, t = GetTime() }
    ns.After(A.CONFIRM_SEC + 0.1, function() if A.armed and A.armed.auc == e.auc and not A.Armed(e) then A.armed = nil ns.Refresh() end end)
    return false
  end
  A.armed = nil
  local ok = pcall(ns.AH.CancelAuction, e.auc)
  if not ok then ns.Print("Abbrechen ging nicht.") return false end
  A.cancelled = e.auc
  return true
end

ns.On("OWNED_AUCTIONS_UPDATED", function()
  local ok, read = ns.Try(A.Read)
  if ok and read and ns.WindowTab and ns.WindowTab() == "own" then ns.Refresh() end
end)
ns.On("AUCTION_CANCELED", function()
  A.Query(true)
end)
ns.On("AUCTION_HOUSE_SHOW", function()
  if ns.WindowTab and ns.WindowTab() == "own" then ns.After(0.5, function() A.Query(true) end) end
end)
