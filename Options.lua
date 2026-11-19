-- Orcish Spyglass - settings panel, ignore list page and /spyglass commands.

local addonName, ns = ...

local settingsCategory
local settingObjects = {} -- db key -> Settings setting, so /spyglass keeps the panel in sync

-- Change a db value through the Settings object when there is one,
-- so an open settings panel shows the new value.
local function SetOption(key, value)
    local setting = settingObjects[key]
    if setting then
        setting:SetValue(value)
    else
        ns.db[key] = value
    end
end

local function OnOff(value)
    return value and "|cff00ff00on|r" or "|cffff0000off|r"
end

-- Your target's name, or else the name of the latest alert.
local function DefaultIgnoreName()
    if UnitExists("target") then
        local name = UnitName("target")
        if name and not ns.IsSecret(name) then return name end
    end
    return ns.lastAlert and ns.lastAlert.name
end

-----------------------------
-- Main settings page (Esc > Options > AddOns > Orcish Spyglass)
-----------------------------
local CHECKBOXES = {
    { key = "rares",       name = "Rares",
      tooltip = "Alert when a rare creature shows up on the minimap." },
    { key = "treasures",   name = "Treasures",
      tooltip = "Alert when a treasure shows up on the minimap." },
    { key = "others",      name = "Other minimap icons",
      tooltip = "Alert for other minimap icons, such as events and special NPCs." },
    { key = "deaths",      name = "Rares killed by others",
      tooltip = "Tell me when someone outside my group kills a rare I could have had." },
    { key = "nameplates",  name = "Scan nameplates for rares",
      tooltip = "Also alert when a rare or rare elite nameplate comes into view. Needs enemy nameplates turned on." },
    { key = "pin",         name = "Pin alerts on the map",
      tooltip = "Put a map pin and navigation arrow on whatever was spotted. Won't replace a pin you placed yourself." },
    { key = "sound",       name = "Play sound",
      tooltip = "Play the raid warning sound when something is spotted." },
    { key = "raidWarning", name = "Show on-screen warning",
      tooltip = "Show the big raid warning text in the middle of the screen." },
    { key = "chat",        name = "Print to chat",
      tooltip = "Also print a line in the chat window." },
}

-----------------------------
-- Ignore list page
-----------------------------
local ROW_HEIGHT = 24

local function CreateIgnorePanel()
    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Ignore list")

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    help:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    help:SetJustifyH("LEFT")
    help:SetText("No alerts for these names. Not case sensitive. Use * as a wildcard: *Chest* ignores every chest.")

    local input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    input:SetSize(260, 20)
    input:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 6, -14)
    input:SetAutoFocus(false)
    input:SetMaxLetters(100)

    local function AddFromInput()
        local name = strtrim(input:GetText() or "")
        if name ~= "" then ns.AddIgnore(name) end
        input:SetText("")
        input:ClearFocus()
    end
    input:SetScript("OnEnterPressed", AddFromInput)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetSize(80, 22)
    addButton:SetPoint("LEFT", input, "RIGHT", 8, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", AddFromInput)

    local targetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    targetButton:SetSize(150, 22)
    targetButton:SetPoint("LEFT", addButton, "RIGHT", 6, 0)
    targetButton:SetText("Add target / last alert")
    targetButton:SetScript("OnClick", function()
        local name = DefaultIgnoreName()
        if name then ns.AddIgnore(name) end
    end)

    local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -14)
    scrollBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -36, 16)

    local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 0)

    local empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 4, -6)
    empty:SetText("Nothing ignored. Every rare and treasure will be announced.")

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", function(row, name)
        if not row.label then
            row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.label:SetPoint("LEFT", 4, 0)
            row.label:SetPoint("RIGHT", -90, 0)
            row.label:SetJustifyH("LEFT")

            row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.remove:SetSize(80, 20)
            row.remove:SetPoint("RIGHT", -4, 0)
            row.remove:SetText("Remove")
            row.remove:SetScript("OnClick", function() ns.RemoveIgnore(row.ignoreName) end)
        end
        row.ignoreName = name
        row.label:SetText(name)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    function panel:Refresh()
        local list = ns.GetIgnoreList()
        scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
        empty:SetShown(#list == 0)
    end

    -- Called by the Settings panel.
    panel.OnRefresh = panel.Refresh

    panel:SetScript("OnShow", panel.Refresh)
    return panel
end

-----------------------------
-- Register both pages
-----------------------------
function ns.SetupOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

    local category = Settings.RegisterVerticalLayoutCategory("Orcish Spyglass")
    for _, box in ipairs(CHECKBOXES) do
        local setting = Settings.RegisterAddOnSetting(category, "OrcishSpyglass_" .. box.key, box.key,
            ns.db, type(ns.DEFAULTS[box.key]), box.name, ns.DEFAULTS[box.key])
        Settings.CreateCheckbox(category, setting, box.tooltip)
        settingObjects[box.key] = setting
    end

    local ignorePanel = CreateIgnorePanel()
    Settings.RegisterCanvasLayoutSubcategory(category, ignorePanel, "Ignore list")
    ns.OnIgnoreChanged = function()
        if ignorePanel:IsVisible() then ignorePanel:Refresh() end
    end

    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
end

-----------------------------
-- Slash commands
-----------------------------
local function PrintHelp()
    ns.Print("commands:")
    print("  /spyglass (or /osg) - open settings")
    print("  /spyglass sound [on|off] - toggle the alert sound")
    print("  /spyglass rares | treasures | others | deaths | pins [on|off] - toggle an alert type")
    print("  /spyglass ignore [name] - stop alerts for a name (default: your target, or the last alert)")
    print("  /spyglass unignore <name> - start alerting for a name again")
    print("  /spyglass list - show the ignore list")
    print("  /spyglass pin - pin the last alert on the map, replacing any pin")
    print("  /spyglass test - fire a test alert")
    print("  Use * as a wildcard, e.g. /spyglass ignore *Cache")
end

local function ParseOnOff(arg, current)
    if arg == "on" then return true end
    if arg == "off" then return false end
    return not current
end

local commands = {}

-- Simple on/off switches: command -> { db key, label }
local TOGGLES = {
    sound     = { "sound", "sound" },
    rares     = { "rares", "rare alerts" },
    treasures = { "treasures", "treasure alerts" },
    others    = { "others", "other alerts" },
    deaths    = { "deaths", "rares killed by others" },
    pins      = { "pin", "map pins" },
}
for command, toggle in pairs(TOGGLES) do
    local key, label = toggle[1], toggle[2]
    commands[command] = function(arg)
        SetOption(key, ParseOnOff(arg:lower(), ns.db[key]))
        ns.Print(label, OnOff(ns.db[key]))
    end
end

function commands.ignore(arg)
    local name = arg ~= "" and arg or DefaultIgnoreName()
    if not name or name == "" then
        ns.Print("nothing to ignore. Use /spyglass ignore <name>.")
        return
    end
    if ns.AddIgnore(name) then
        ns.Print("ignoring", name)
    else
        ns.Print(name, "is already ignored")
    end
end

function commands.unignore(arg)
    if arg == "" then
        ns.Print("usage: /spyglass unignore <name>")
        return
    end
    local removed = ns.RemoveIgnore(arg)
    if removed then
        ns.Print("no longer ignoring", removed)
    else
        ns.Print(arg, "isn't on the ignore list. See /spyglass list.")
    end
end

function commands.list()
    local list = ns.GetIgnoreList()
    if #list == 0 then
        ns.Print("the ignore list is empty")
        return
    end
    ns.Print("ignoring " .. #list .. ":")
    for _, name in ipairs(list) do print("  " .. name) end
end

function commands.pin()
    local alert = ns.lastAlert
    if not alert or not alert.vignetteGUID then
        ns.Print("nothing to pin. Nameplate-only rares have no map position.")
        return
    end
    local link = ns.PinVignette(alert.vignetteGUID, alert.key, true)
    if link then
        ns.Print("pinned", alert.name, link)
    else
        ns.Print("couldn't pin", alert.name .. ". It may be out of range or on another map.")
    end
end

function commands.test()
    ns.Alert("", "Orcish Spyglass test")
end

commands.help = PrintHelp

SLASH_ORCISHSPYGLASS1 = "/spyglass"
SLASH_ORCISHSPYGLASS2 = "/osg"
SlashCmdList.ORCISHSPYGLASS = function(input)
    local command, arg = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "" then
        if settingsCategory then
            Settings.OpenToCategory(settingsCategory:GetID())
        else
            PrintHelp()
        end
        return
    end

    local handler = commands[command]
    if handler then
        handler(arg)
    else
        PrintHelp()
    end
end
