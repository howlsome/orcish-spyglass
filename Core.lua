-- Orcish Spyglass - Alerts you to nearby rares and treasures.
-- Based on rVignette by zork (2018), with a fix from Neav.
--
-- For WoW: Forever (interface 16001).

local addonName, ns = ...

ns.PREFIX = "|cffc41f3bOrcish Spyglass|r"

ns.DEFAULTS = {
    sound = true,       -- play the raid warning sound
    raidWarning = true, -- big text in the middle of the screen
    chat = true,        -- line in the chat window
    rares = true,       -- alert for rare creatures
    treasures = true,   -- alert for treasures
    others = true,      -- alert for other minimap vignettes (events, special NPCs)
    deaths = true,      -- say when someone else kills a rare
    nameplates = true,  -- also find rares by their nameplate
    pin = true,         -- put a map pin on alerts
}

-- Which db switch covers each kind of alert.
local KIND_SETTING = { rare = "rares", treasure = "treasures", other = "others" }

local RARE_CLASSIFICATIONS = { rare = true, rareelite = true }
local RARE_ATLAS = "VignetteKill"
local SOUND_THROTTLE = 2 -- seconds between alert sounds
local DEATH_DELAY = 1    -- seconds to wait for PARTY_KILL before blaming someone else

local db
local alerted = {}       -- key -> true once "spotted" was shown (this session)
local deathHandled = {}  -- creature GUID -> true once its death was handled
local ourKills = {}      -- creature GUID -> true when you or your group got the kill
local rareNames = {}     -- creature GUID -> name, for rares we've seen
local pinned             -- { key, mapID, x, y } for the waypoint we placed
local lastSound = -math.huge
ns.lastAlert = nil       -- { name, vignetteGUID, key } of the latest alert

-----------------------------
-- Helpers
-----------------------------
-- Forever can hand addons "secret" values
-- that error when compared or used as table keys.
local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end
ns.IsSecret = IsSecret

function ns.Print(...)
    print(ns.PREFIX .. ":", ...)
end

local function AtlasIcon(atlasName)
    if not atlasName or IsSecret(atlasName) then return "" end
    if not C_Texture.GetAtlasInfo(atlasName) then return "" end
    return CreateAtlasMarkup and CreateAtlasMarkup(atlasName, 16, 16)
        or ("|A:" .. atlasName .. ":16:16|a")
end

local function ShowRaidWarning(text)
    RaidWarningUtil.AddMessage(text, ChatTypeInfo["RAID_WARNING"])
end

local function PlayAlertSound()
    if not db.sound then return end
    local now = GetTime()
    if now - lastSound >= SOUND_THROTTLE then
        lastSound = now
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- Show a message through the channels the player has turned on.
local function Announce(text, chatSuffix)
    if db.raidWarning then ShowRaidWarning(text) end
    if db.chat then print(text .. (chatSuffix or "")) end
end

local function IsCreatureGUID(guid)
    return type(guid) == "string" and not IsSecret(guid)
        and (guid:find("^Creature%-") or guid:find("^Vehicle%-")) ~= nil
end

-----------------------------
-- Ignore list
-----------------------------
-- Stored as { [lowercase name] = name as typed }.
local patternCache = {}

local function ToPattern(entry)
    local pattern = patternCache[entry]
    if not pattern then
        -- Escape Lua pattern characters, then turn "*" into ".*".
        pattern = "^" .. entry:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
        patternCache[entry] = pattern
    end
    return pattern
end

local function IgnoreChanged()
    if ns.OnIgnoreChanged then ns.OnIgnoreChanged() end
end

function ns.IsIgnored(name)
    local lower = name:lower()
    if db.ignore[lower] then return true end
    for entry in pairs(db.ignore) do
        if entry:find("*", 1, true) and lower:find(ToPattern(entry)) then
            return true
        end
    end
    return false
end

-- Returns true if added, false if it was already there.
function ns.AddIgnore(name)
    name = strtrim(name)
    if name == "" then return false end
    local lower = name:lower()
    if db.ignore[lower] then return false end
    db.ignore[lower] = name
    IgnoreChanged()
    return true
end

-- Returns the stored name if removed, nil if it wasn't on the list.
function ns.RemoveIgnore(name)
    local lower = strtrim(name):lower()
    local stored = db.ignore[lower]
    if stored then
        db.ignore[lower] = nil
        IgnoreChanged()
    end
    return stored
end

function ns.GetIgnoreList()
    local list = {}
    for _, name in pairs(db.ignore) do list[#list + 1] = name end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

-----------------------------
-- Map pins
-----------------------------
local function OwnsWaypoint()
    if not pinned or not C_Map.HasUserWaypoint() then return false end
    local point = C_Map.GetUserWaypoint()
    if not point or point.uiMapID ~= pinned.mapID then return false end
    local x, y = point.position:GetXY()
    return math.abs(x - pinned.x) < 0.0001 and math.abs(y - pinned.y) < 0.0001
end

-- Pins a vignette's spot on the map. Unless forced, it won't replace a
-- waypoint the player placed themselves. Returns a chat link, or nil.
function ns.PinVignette(vignetteGUID, key, force)
    if not vignetteGUID or not C_Map.SetUserWaypoint then return nil end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or not C_Map.CanSetUserWaypointOnMap(mapID) then return nil end

    local position = C_VignetteInfo.GetVignettePosition(vignetteGUID, mapID)
    if not position then return nil end
    local x, y = position:GetXY()
    if IsSecret(x) or IsSecret(y) then return nil end

    if not force and C_Map.HasUserWaypoint() and not OwnsWaypoint() then return nil end

    if not C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y)) then return nil end
    pinned = { key = key, mapID = mapID, x = x, y = y }
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    return C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink() or nil
end

local function ClearPinFor(key)
    if pinned and pinned.key == key then
        if OwnsWaypoint() then C_Map.ClearUserWaypoint() end
        pinned = nil
    end
end

-----------------------------
-- Alerts
-----------------------------
function ns.Alert(icon, name, vignetteGUID, key)
    ns.lastAlert = { name = name, vignetteGUID = vignetteGUID, key = key }

    local link = db.pin and ns.PinVignette(vignetteGUID, key) or nil
    local text = (icon ~= "" and icon .. " " or "") .. name .. " spotted!"
    Announce(text, link and (" " .. link) or nil)
    PlayAlertSound()
end

local function AlertOnce(key, icon, name, vignetteGUID)
    if alerted[key] or ns.IsIgnored(name) then return end
    alerted[key] = true
    ns.Alert(icon, name, vignetteGUID, key)
end

-- A rare died. Wait a moment for PARTY_KILL, then if it wasn't you or your
-- group, say so.
local function RareDied(guid, name)
    if deathHandled[guid] then return end
    deathHandled[guid] = true
    alerted[guid] = true

    C_Timer.After(DEATH_DELAY, function()
        ClearPinFor(guid)
        if ourKills[guid] or not db.deaths or not db.rares or ns.IsIgnored(name) then return end
        Announce("Someone other than you just killed " .. name .. ".")
    end)
end

-----------------------------
-- Vignettes (minimap rare / treasure icons)
-----------------------------
local function Classify(info)
    if Enum and Enum.VignetteType and info.type == Enum.VignetteType.Treasure then
        return "treasure"
    end
    if IsCreatureGUID(info.objectGUID) or (info.objectiveType and info.objectiveType ~= 0) then
        return "rare"
    end
    local atlas = info.atlasName
    if atlas and not IsSecret(atlas) then
        local lower = atlas:lower()
        if lower:find("kill") then return "rare" end
        if lower:find("loot") or lower:find("treasure") or lower:find("chest") then return "treasure" end
    end
    return "other"
end
ns.Classify = Classify

local function CheckVignette(vignetteGUID)
    if not vignetteGUID or IsSecret(vignetteGUID) then return end

    local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
    if not info or not info.onMinimap then return end

    local name = info.name
    if not name or IsSecret(name) or name == "" then return end

    local kind = Classify(info)
    if not db[KIND_SETTING[kind]] then return end

    -- Key rares by the creature, so the vignette and nameplate don't both fire.
    local key = vignetteGUID
    if kind == "rare" and IsCreatureGUID(info.objectGUID) then
        key = info.objectGUID
        rareNames[key] = name
    end

    if info.isDead then
        if kind == "rare" then RareDied(key, name) end
        return
    end

    AlertOnce(key, AtlasIcon(info.atlasName), name, vignetteGUID)
end

local function ScanVignettes()
    for _, guid in ipairs(C_VignetteInfo.GetVignettes()) do
        CheckVignette(guid)
    end
end

-----------------------------
-- Nameplates (rares the game doesn't mark with a vignette)
-----------------------------
local function CheckNameplate(unit)
    if not db.nameplates or not db.rares or UnitIsPlayer(unit) then return end

    local classification = UnitClassification(unit)
    if IsSecret(classification) or not RARE_CLASSIFICATIONS[classification] then return end

    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    if not guid or not name or IsSecret(guid) or IsSecret(name) then return end
    rareNames[guid] = name

    if UnitIsDead(unit) then
        -- A corpse that isn't greyed out was tagged by you or your group.
        local tapDenied = UnitIsTapDenied(unit)
        if not IsSecret(tapDenied) and not tapDenied then ourKills[guid] = true end
        RareDied(guid, name)
        return
    end

    AlertOnce(guid, AtlasIcon(RARE_ATLAS), name, nil)
end

-----------------------------
-- Saved settings
-----------------------------
local function LoadDB()
    OrcishSpyglassDB = OrcishSpyglassDB or {}
    db = OrcishSpyglassDB
    ns.db = db
    for key, value in pairs(ns.DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    db.ignore = db.ignore or {}
end

-----------------------------
-- Init
-----------------------------
local eventHandler = CreateFrame("Frame")
eventHandler:RegisterEvent("ADDON_LOADED")
eventHandler:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        LoadDB()
        if ns.SetupOptions then ns.SetupOptions() end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
        self:RegisterEvent("VIGNETTES_UPDATED")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("PARTY_KILL")
        self:RegisterEvent("UNIT_DIED")
    elseif event == "VIGNETTE_MINIMAP_UPDATED" then
        local guid, onMinimap = ...
        if onMinimap then CheckVignette(guid) end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        CheckNameplate(...)
    elseif event == "PARTY_KILL" then
        local _, targetGUID = ...
        if targetGUID and not IsSecret(targetGUID) then ourKills[targetGUID] = true end
    elseif event == "UNIT_DIED" then
        local guid = ...
        if guid and not IsSecret(guid) and rareNames[guid] then RareDied(guid, rareNames[guid]) end
    else -- VIGNETTES_UPDATED, PLAYER_ENTERING_WORLD
        ScanVignettes()
    end
end)
