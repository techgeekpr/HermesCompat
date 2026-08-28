--[[ Hermes Compat -- API shim for a 1.14 client bridged to a 1.12 server.

Fixes a modern WeakAura pack (LWA) that assumes newer game/WeakAuras API than
this setup provides:

  1. Vehicle API (UnitHasVehicleUI, HasVehicleActionBar, ...) -- added in Wrath,
     missing on a 1.12 server. We stub them to "no vehicle".

  2. The aurabar region method  region:SetStatusBarTextureLSM(name)  -- newer
     WeakAuras aurabar regions have it; this ported WeakAuras does not. We add it
     to every aurabar region, resolving the LibSharedMedia texture name and
     applying it to the region's bar.

Only fills in things that are MISSING; never overrides what already exists.
]]

-- =========================================================================
--  0a) C_Spell.IsSpellInRange -- modern range API (Retail/Cata) that some
--      WeakAuras (e.g. "Predictive Melee Weave") call. This client's C_Spell
--      lacks it. Map to the classic global IsSpellInRange, which takes a spell
--      NAME (not id), so convert numeric spell ids via GetSpellInfo. Returns a
--      boolean like the modern API (classic returns 1/0/nil).
-- =========================================================================
if C_Spell and not C_Spell.IsSpellInRange and IsSpellInRange then
	function C_Spell.IsSpellInRange(spell, unit)
		local name = spell
		if type(spell) == "number" then
			name = GetSpellInfo(spell)
		end
		if not name then return nil end
		local r = IsSpellInRange(name, unit)
		if r == nil then return nil end
		return r == 1 or r == true
	end
end

-- =========================================================================
--  0) UIPanelScrollFrame_OnLoad -- FrameXML helper missing on this client that
--     some addons' scroll templates (e.g. NovaWorldBuffs) reference in XML OnLoad.
-- =========================================================================
if not UIPanelScrollFrame_OnLoad then
	function UIPanelScrollFrame_OnLoad(self)
		local name = self.GetName and self:GetName()
		local scrollbar = self.ScrollBar or (name and _G[name .. "ScrollBar"])
		if scrollbar then
			self.ScrollBar = scrollbar
			local sbname = scrollbar.GetName and scrollbar:GetName()
			scrollbar.ScrollUpButton = scrollbar.ScrollUpButton or (sbname and _G[sbname .. "ScrollUpButton"])
			scrollbar.ScrollDownButton = scrollbar.ScrollDownButton or (sbname and _G[sbname .. "ScrollDownButton"])
			scrollbar:SetMinMaxValues(0, 0)
			scrollbar:SetValue(0)
		end
		self.offset = 0
	end
end

-- =========================================================================
--  0b) C_Container namespace -- modern container API missing on this client.
--      Map each function to its classic global equivalent. GetContainerItemInfo
--      needs special handling: classic returns multiple values, modern a table.
-- =========================================================================
if not C_Container then
	-- The modern C_Container functions have the SAME names as the classic globals
	-- (Blizzard just moved them into a namespace), so any C_Container.X can auto-map to
	-- the global X. Two of them return a table in modern (vs multiple values classic),
	-- so those get explicit conversion wrappers.
	local function itemInfo(bag, slot)
		local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID, isBound = GetContainerItemInfo(bag, slot)
		if icon == nil and link == nil and itemID == nil then return nil end
		return {
			iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
			isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = filtered,
			hasNoValue = noValue, itemID = itemID, isBound = isBound,
		}
	end
	local function questInfo(bag, slot)
		local g = _G.GetContainerItemQuestInfo
		if g then
			local isQuestItem, questID, isActive = g(bag, slot)
			return { isQuestItem = isQuestItem, questID = questID, isActive = isActive }
		end
		return { isQuestItem = false } -- no classic equivalent; treat as non-quest
	end
	local special = {
		GetContainerItemInfo = GetContainerItemInfo and itemInfo or nil,
		GetContainerItemQuestInfo = questInfo,
	}
	C_Container = setmetatable({}, {
		__index = function(t, key)
			local fn = special[key]
			if fn == nil then fn = _G[key] end -- same-named classic global
			if fn ~= nil then rawset(t, key, fn) end
			return fn
		end,
	})
end

-- =========================================================================
--  1) Vehicle API stubs (return "no vehicle", correct for a 1.12 server).
-- =========================================================================
local function retFalse() return false end
local function retNil() return nil end
local function retZero() return 0 end
local function noop() end

UnitHasVehicleUI            = UnitHasVehicleUI            or retFalse
UnitHasVehiclePlayerFrameUI = UnitHasVehiclePlayerFrameUI or retFalse
UnitInVehicle               = UnitInVehicle               or retFalse
UnitControllingVehicle      = UnitControllingVehicle      or retFalse
UnitInVehicleControlSeat    = UnitInVehicleControlSeat    or retFalse
UnitTargetsVehicleInRaidUI  = UnitTargetsVehicleInRaidUI  or retFalse
CanExitVehicle              = CanExitVehicle              or retFalse
CanSwitchVehicleSeats       = CanSwitchVehicleSeats       or retFalse
UnitVehicleSkin             = UnitVehicleSkin             or retNil
UnitVehicleSeatCount        = UnitVehicleSeatCount        or retZero
HasVehicleActionBar         = HasVehicleActionBar         or retFalse
HasOverrideActionBar        = HasOverrideActionBar        or retFalse
HasTempShapeshiftActionBar  = HasTempShapeshiftActionBar  or retFalse
GetVehicleBarIndex          = GetVehicleBarIndex          or retNil
GetOverrideBarIndex         = GetOverrideBarIndex         or retNil
GetTempShapeshiftBarIndex   = GetTempShapeshiftBarIndex   or retNil
VehicleExit                 = VehicleExit                 or noop
UnitSwitchToVehicleSeat     = UnitSwitchToVehicleSeat     or noop

-- =========================================================================
--  2) WeakAuras aurabar region:SetStatusBarTextureLSM(name)
-- =========================================================================
local function fetchLSM(mediatype, name, default)
	if type(name) ~= "string" then return name or default end
	if name:find("[\\/]") then return name end          -- already a real path
	local LibStub = _G.LibStub
	if LibStub then
		local LSM = LibStub("LibSharedMedia-3.0", true)
		if LSM then return LSM:Fetch(mediatype, name) or default end
	end
	return default
end

-- The method the pack expects on an aurabar region. Resolves the LSM texture
-- name and applies it to the region's bar (aurabar bars use :SetTexture).
local function region_SetStatusBarTextureLSM(self, name)
	local path = fetchLSM("statusbar", name, "Interface\\TargetingFrame\\UI-StatusBar")
	local bar = self.bar
	if bar then
		if bar.SetTexture then
			bar:SetTexture(path)
		elseif bar.SetStatusBarTexture then
			bar:SetStatusBarTexture(path)
		end
	end
end

local function attach(region)
	if type(region) == "table" and region.bar and region.SetStatusBarTextureLSM == nil then
		region.SetStatusBarTextureLSM = region_SetStatusBarTextureLSM
		return true
	end
	return false
end

-- Try to patch WeakAuras: wrap aurabar region creation (covers future regions,
-- including on-demand dynamic-group clones) and sweep any existing regions.
local wrappedCreate, sweptRegions = false, 0
local function PatchWeakAuras()
	local WA = _G.WeakAuras
	if not WA then return false, "no WeakAuras" end

	local rt = WA.regionTypes
	local found = type(rt) == "table" and rt.aurabar or nil

	-- Wrap the aurabar create function so every new region gets the method.
	if found and not rt.aurabar.__hermesWrapped and type(rt.aurabar.create) == "function" then
		rt.aurabar.__hermesWrapped = true
		local origCreate = rt.aurabar.create
		rt.aurabar.create = function(...)
			local region = origCreate(...)
			attach(region)
			return region
		end
		wrappedCreate = true
	end

	-- Sweep regions that already exist (main auras).
	if type(WA.regions) == "table" then
		for _, d in pairs(WA.regions) do
			if type(d) == "table" and attach(d.region) then sweptRegions = sweptRegions + 1 end
		end
	end
	-- Sweep clones (dynamic-group children).
	if type(WA.clones) == "table" then
		for _, grp in pairs(WA.clones) do
			if type(grp) == "table" then
				for _, r in pairs(grp) do
					if attach(r) then sweptRegions = sweptRegions + 1 end
				end
			end
		end
	end

	return true, (found and "aurabar region type found" or "aurabar region type NOT found (regionTypes not public)")
end

-- =========================================================================
--  Drive the patch: when WeakAuras loads, at login, and a couple retries for
--  lazily-created clones.
-- =========================================================================
local status = "pending"
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, addon)
	if event == "ADDON_LOADED" and addon == "WeakAuras" then
		local ok, msg = PatchWeakAuras()
		status = msg or status
	elseif event == "PLAYER_LOGIN" then
		local ok, msg = PatchWeakAuras()
		status = msg or status
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cff55ccffHermes Compat v1.3|r: " .. tostring(status)
				.. " | wrappedCreate=" .. tostring(wrappedCreate)
				.. " | regionsPatched=" .. tostring(sweptRegions))
		end
		-- Retry sweeps so late-created clones also get the method.
		if C_Timer and C_Timer.After then
			C_Timer.After(2, PatchWeakAuras)
			C_Timer.After(5, PatchWeakAuras)
		end
	end
end)
