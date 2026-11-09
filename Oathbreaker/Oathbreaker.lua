-- Oathbreaker: replaces Zygor's "Abandon all" with a list you can tick quest by quest.
-- It only suggests old, unfinished quests that no upcoming guide needs.
local ADDON, ns = ...

local ICON = "Interface\\AddOns\\Oathbreaker\\Media\\oathbreaker.tga"
local DEFAULT_GAP = 4
local ROW_H, MAX_ROWS, WIDTH = 42, 9, 500
local HEADER_H, TOOLBAR_H, FOOTER_H = 64, 42, 54
local CONFIRM_SECONDS = 4
local GROUP_TAGS = { [1] = true, [41] = true, [62] = true, [81] = true, [85] = true, [88] = true, [89] = true }

local db
local window
local minimapIcon
local guideCache = {}

local function say(msg)
    print("|cff5fd38dOathbreaker:|r " .. msg)
end

-------------------------------------------------------------------------------
-- Which quests does Zygor still need?
-------------------------------------------------------------------------------
local function addCachePacks(ids, cache, title)
    for _, pack in pairs(cache and cache[title] or {}) do
        if type(pack) == "table" and type(pack.ids) == "table" then
            for id in pairs(pack.ids) do ids[tonumber(id)] = true end
        elseif type(pack) == "table" and type(pack.ids) == "string" then
            -- Zygor unpacks these lists a little after login
            for id in pack.ids:gmatch("%d+") do ids[tonumber(id)] = true end
        end
    end
end

-- Raw text covers guides that are not loaded yet, Zygor's cache covers included sections.
local function questsOfGuide(zgv, guide)
    local ids = guideCache[guide.title]
    if ids then return ids end
    ids = {}
    if type(guide.rawdata) == "string" then
        for line in guide.rawdata:gmatch("[^\n]+") do
            local verb = line:match("^%s*(%a+)")
            if verb == "accept" or verb == "turnin" then
                local id = line:match("##(%d+)")
                if id then ids[tonumber(id)] = true end
            end
            for id in line:gmatch("|q (%d+)") do ids[tonumber(id)] = true end
        end
    end
    addCachePacks(ids, zgv.Quest_Cache_Accept, guide.title)
    addCachePacks(ids, zgv.Quest_Cache, guide.title)
    guideCache[guide.title] = ids
    return ids
end

-- Every open tab counts, not just the active one
local function openGuides(zgv)
    local guides = {}
    if zgv.CurrentGuide then guides[1] = zgv.CurrentGuide end
    for _, tab in pairs(zgv.Tabs and zgv.Tabs.Pool or {}) do
        local guide = tab.guide
        if type(guide) == "string" then guide = zgv:GetGuideByTitle(guide) end
        if guide then guides[#guides + 1] = guide end
    end
    return guides
end

local function neededQuests(zgv, guides, levelingOnly)
    local needed, seen = {}, {}
    local function add(guide)
        for id in pairs(questsOfGuide(zgv, guide)) do needed[id] = true end
    end

    for _, start in ipairs(guides) do
        local guide = start
        while guide and not seen[guide.title] do
            seen[guide.title] = true
            add(guide)
            guide = guide.next and zgv:GetGuideByTitle(guide.next)
        end
    end
    if levelingOnly then return needed end
    for _, other in ipairs(zgv.registeredguides or {}) do
        local title = other.title or ""
        if title:find("^DUNGEONS") or title:find("Class Quests", 1, true) then add(other) end
    end
    return needed
end

local function isGroupQuest(info)
    if info.suggestedGroup and info.suggestedGroup > 0 then return true end
    local tag = C_QuestLog.GetQuestTagInfo(info.questID)
    return tag and GROUP_TAGS[tag.tagID] or false
end

local function describe(id, zone)
    local parts = { zone }
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
        if not objective.finished and objective.text and objective.text ~= "" then
            parts[#parts + 1] = objective.text
            break
        end
    end
    return table.concat(parts, "  |cff666666/|r  ")
end

local function candidates()
    local zgv = _G.ZGV
    local guides = zgv and openGuides(zgv)
    if not (guides and guides[1]) then return nil end

    local needed = neededQuests(zgv, guides)
    local maxLevel = UnitLevel("player") - db.gap
    local list, protected, zone = {}, 0, nil
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and info.isHeader then zone = info.title end
        if info and not info.isHeader and not info.isHidden and info.questID then
            local id = info.questID
            local repeatable = info.frequency and info.frequency ~= 0
            local done = C_QuestLog.IsComplete(id) or C_QuestLog.ReadyForTurnIn(id)
            local isOld = info.level and info.level > 0 and info.level <= maxLevel
            if isOld and not repeatable and not done and not needed[id] and not isGroupQuest(info) then
                list[#list + 1] = { id = id, title = info.title, level = info.level, detail = describe(id, zone) }
            else
                protected = protected + 1
            end
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list, protected
end

local function abandon(id)
    C_QuestLog.SetSelectedQuest(id)
    C_QuestLog.SetAbandonQuest()
    C_QuestLog.AbandonQuest()
end

-------------------------------------------------------------------------------
-- Window in EllesmereUI style
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local CLOSE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"

local function accent()
    if EUI.GetAccentColor then return EUI.GetAccentColor() end
    local color = EUI.ELLESMERE_GREEN
    return color.r, color.g, color.b
end

local function font(parent, size, a)
    return EUI.MakeFont(parent, size, nil, 1, 1, 1, a or 1)
end

local function hairline(parent, anchorA, anchorB, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint(anchorA, 0, y)
    line:SetPoint(anchorB, 0, y)
    line:SetColorTexture(1, 1, 1, 0.07)
    return line
end

local function stepButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.089, 0.080, 0.072, 0.6)
    EUI.MakeBorder(b, 1, 1, 1, 0.2)
    b.label = font(b, 13, 0.6)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(accent()) end)
    b:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1, 0.6) end)
    return b
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_H)

    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.04)
    row.hover:Hide()
    hairline(row, "BOTTOMLEFT", "BOTTOMRIGHT", 0):SetAlpha(0.5)

    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(16, 16)
    row.box:SetPoint("LEFT", 18, 0)
    local boxBg = row.box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints()
    boxBg:SetColorTexture(0.112, 0.105, 0.098, 1)
    EUI.MakeBorder(row.box, 1, 1, 1, 0.18)
    row.check = row.box:CreateTexture(nil, "ARTWORK")
    row.check:SetPoint("TOPLEFT", 4, -4)
    row.check:SetPoint("BOTTOMRIGHT", -4, 4)

    row.level = font(row, 13)
    row.level:SetPoint("TOPLEFT", row.box, "TOPRIGHT", 12, 5)
    row.title = font(row, 13)
    row.title:SetPoint("LEFT", row.level, "RIGHT", 7, 0)
    row.title:SetPoint("RIGHT", row, "RIGHT", -64, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = font(row, 11, 0.45)
    row.detail:SetPoint("TOPLEFT", row.level, "BOTTOMLEFT", 0, -3)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.keep = font(row, 10, 0.4)
    row.keep:SetPoint("RIGHT", row, "RIGHT", -18, 7)
    row.keep:SetText("KEEP")

    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self)
        db.keep[self.questID] = not db.keep[self.questID] or nil
        window.Refresh()
    end)
    return row
end

local function selected(list)
    local chosen = {}
    for _, entry in ipairs(list) do
        if not db.keep[entry.id] then chosen[#chosen + 1] = entry end
    end
    return chosen
end

local function paintRow(row, entry)
    local kept = db.keep[entry.id] and true or false
    local color = GetQuestDifficultyColor and GetQuestDifficultyColor(entry.level)
    row.questID = entry.id
    row.level:SetText(("[%d]"):format(entry.level))
    if color then row.level:SetTextColor(color.r, color.g, color.b, kept and 0.4 or 1) end
    row.title:SetText(entry.title)
    row.title:SetTextColor(1, 1, 1, kept and 0.4 or 0.95)
    row.detail:SetText(entry.detail)
    row.check:SetColorTexture(accent())
    row.check:SetShown(not kept)
    row.keep:SetShown(kept)
    row:Show()
end

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------
local settings

local SETTINGS = {
    { key = "smartSkip", title = "Smart skip", text = "Skip Zygor steps when a prerequisite quest is missing" },
    { key = "offerDungeons", title = "Dungeon offers", text = "Ask when a dungeon fits your level" },
    { key = "hintQuests", title = "Nearby dungeon quests", text = "Show a hint when a dungeon quest giver is close" },
    { key = "hintFlights", title = "Flight point hints", text = "Show a hint when an undiscovered flight point is close" },
    { key = "guideFinder", title = "Quest log guide finder", text = "Show which Zygor guides contain the selected quest" },
    { key = "guideCheck", title = "Guide check", text = "Suggest the next leveling guide once you have outleveled yours" },
    { key = "sideQuests", title = "Side quests", text = "Hint at nearby quests from the guides you take along" },
    { key = "markLowLevel", title = "Mark low-level quests", text = "Add (low level) to grey quests in Zygor's steps and in hints" },
    { key = "updateNotice", title = "Update notice", text = "Tell me when someone I play with runs a newer Oathbreaker" },
    { key = "showMinimap", title = "Minimap button", text = "Show the Oathbreaker button on the minimap" },
}

local function settingValue(key)
    if key == "showMinimap" then return not db.minimap.hide end
    return db[key]
end

local function setSetting(key, value)
    if key == "showMinimap" then
        db.minimap.hide = not value
        if minimapIcon then
            if value then minimapIcon:Show(ADDON) else minimapIcon:Hide(ADDON) end
        end
        return
    end
    db[key] = value
    if key == "updateNotice" and ns.UpdateNoticeChanged then ns.UpdateNoticeChanged(value) end
    if key == "smartSkip" and _G.ZGV and _G.ZGV.UpdateFrame then _G.ZGV:UpdateFrame() end
end

local function createToggle(parent, row)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetAllPoints(row)
    local track = row:CreateTexture(nil, "ARTWORK")
    track:SetSize(34, 16)
    track:SetPoint("RIGHT", -18, 0)
    local knob = row:CreateTexture(nil, "OVERLAY")
    knob:SetSize(12, 12)
    function toggle.Paint(on)
        local r, g, b = accent()
        if on then
            track:SetColorTexture(r, g, b, 0.75)
            knob:SetColorTexture(1, 1, 1, 1)
        else
            track:SetColorTexture(0.267, 0.267, 0.267, 0.65)
            knob:SetColorTexture(1, 1, 1, 0.5)
        end
        knob:ClearAllPoints()
        knob:SetPoint(on and "RIGHT" or "LEFT", track, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    end
    return toggle
end

local function createSettings()
    local rowHeight, top = 46, HEADER_H
    local f = CreateFrame("Frame", "OathbreakerSettings", UIParent)
    f:SetSize(420, top + #SETTINGS * rowHeight + 134)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(50)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, f:GetName())

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
    EUI.MakeBorder(f, 1, 1, 1, 0.15)
    f.topLine = f:CreateTexture(nil, "ARTWORK")
    f.topLine:SetHeight(2)
    f.topLine:SetPoint("TOPLEFT", 1, -1)
    f.topLine:SetPoint("TOPRIGHT", -1, -1)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 18, -14)
    icon:SetTexture(ICON)
    local heading = font(f, 18)
    heading:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -1)
    heading:SetText("Oathbreaker")
    local subtitle = font(f, 11, 0.5)
    subtitle:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 12, 2)
    subtitle:SetText("Settings")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(12, 12)
    close:SetPoint("TOPRIGHT", -16, -16)
    close:SetHitRectInsets(-8, -8, -8, -8)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture(CLOSE_ICON)
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function(self) self.icon:SetAlpha(1) end)
    close:SetScript("OnLeave", function(self) self.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() f:Hide() end)
    hairline(f, "TOPLEFT", "TOPRIGHT", -top)

    f.toggles = {}
    for index, setting in ipairs(SETTINGS) do
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 1, -(top + (index - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", -1, -(top + (index - 1) * rowHeight))
        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.04)
        hover:Hide()
        hairline(row, "BOTTOMLEFT", "BOTTOMRIGHT", 0):SetAlpha(0.5)
        local title = font(row, 13)
        title:SetPoint("TOPLEFT", 18, -8)
        title:SetText(setting.title)
        local text = font(row, 11, 0.45)
        text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        text:SetPoint("RIGHT", row, "RIGHT", -64, 0)
        text:SetJustifyH("LEFT")
        text:SetText(setting.text)

        local toggle = createToggle(f, row)
        toggle:SetScript("OnEnter", function() hover:Show() end)
        toggle:SetScript("OnLeave", function() hover:Hide() end)
        toggle:SetScript("OnClick", function(self)
            setSetting(setting.key, not settingValue(setting.key))
            self.Paint(settingValue(setting.key))
        end)
        f.toggles[setting.key] = toggle
    end

    f.reset = CreateFrame("Button", nil, f)
    f.reset:SetSize(230, 28)
    f.reset:SetPoint("BOTTOMRIGHT", -18, 14)
    local resetBg = f.reset:CreateTexture(nil, "BACKGROUND")
    resetBg:SetAllPoints()
    resetBg:SetColorTexture(0.089, 0.080, 0.072, 0.6)
    EUI.MakeBorder(f.reset, 1, 1, 1, 0.3)
    f.reset.label = font(f.reset, 12, 0.6)
    f.reset.label:SetPoint("CENTER")
    f.reset.label:SetText("Reset dungeon answers and hints")
    f.reset:SetScript("OnEnter", function(self) self.label:SetTextColor(accent()) end)
    f.reset:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1, 0.6) end)
    f.reset:SetScript("OnClick", function()
        ns.ResetAssistant()
        say("Dungeon answers and dismissed hints cleared.")
    end)

    f.sideGuides = CreateFrame("Button", nil, f)
    f.sideGuides:SetSize(150, 28)
    f.sideGuides:SetPoint("BOTTOMLEFT", 18, 14)
    local sideBg = f.sideGuides:CreateTexture(nil, "BACKGROUND")
    sideBg:SetAllPoints()
    sideBg:SetColorTexture(0.089, 0.080, 0.072, 0.6)
    EUI.MakeBorder(f.sideGuides, 1, 1, 1, 0.3)
    f.sideGuides.label = font(f.sideGuides, 12, 0.6)
    f.sideGuides.label:SetPoint("CENTER")
    f.sideGuides:SetScript("OnEnter", function(self) self.label:SetTextColor(accent()) end)
    f.sideGuides:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1, 0.6) end)
    f.sideGuides:SetScript("OnClick", function() ns.ToggleSidePicker() end)

    f.check = CreateFrame("Button", nil, f)
    f.check:SetSize(150, 28)
    f.check:SetPoint("BOTTOMLEFT", 18, 50)
    local checkBg = f.check:CreateTexture(nil, "BACKGROUND")
    checkBg:SetAllPoints()
    checkBg:SetColorTexture(0.089, 0.080, 0.072, 0.6)
    EUI.MakeBorder(f.check, 1, 1, 1, 0.3)
    f.check.label = font(f.check, 12, 0.6)
    f.check.label:SetPoint("CENTER")
    f.check.label:SetText("Check guide now")
    f.check:SetScript("OnEnter", function(self) self.label:SetTextColor(accent()) end)
    f.check:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1, 0.6) end)
    f.check:SetScript("OnClick", function() ns.guarded("guide check", ns.CheckGuideNow, _G.ZGV) end)

    f.radiusLabel = font(f, 12, 0.8)
    f.radiusLabel:SetPoint("BOTTOMLEFT", 18, 94)
    f.radiusLabel:SetText("Side quest radius")
    f.radiusLess = stepButton(f, "-")
    f.radiusLess:SetPoint("LEFT", f.radiusLabel, "RIGHT", 10, 0)
    f.radiusValue = font(f, 12, 0.9)
    f.radiusValue:SetWidth(64)
    f.radiusValue:SetPoint("LEFT", f.radiusLess, "RIGHT", 0, 0)
    f.radiusMore = stepButton(f, "+")
    f.radiusMore:SetPoint("LEFT", f.radiusValue, "RIGHT", 0, 0)
    local function showRadius() f.radiusValue:SetText(("%d yd"):format(ns.SideRadius())) end
    f.radiusLess:SetScript("OnClick", function() ns.ChangeSideRadius(-1); showRadius() end)
    f.radiusMore:SetScript("OnClick", function() ns.ChangeSideRadius(1); showRadius() end)

    function f.Refresh()
        local r, g, b = accent()
        f.topLine:SetColorTexture(r, g, b, 0.85)
        showRadius()
        for key, toggle in pairs(f.toggles) do toggle.Paint(settingValue(key)) end
        local count, limit = ns.SideGuideCount()
        f.sideGuides.label:SetText(("Side guides (%d/%d)"):format(count, limit))
    end
    f:Hide()
    return f
end

local function toggleSettings()
    settings = settings or createSettings()
    ns.settingsFrame = settings
    if settings:IsShown() then
        settings:Hide()
    else
        settings.Refresh()
        settings:Show()
    end
end
ns.ToggleSettings = toggleSettings

local function createWindow()
    local f = CreateFrame("Frame", "OathbreakerFrame", UIParent)
    f:SetSize(WIDTH, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, f:GetName())

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
    EUI.MakeBorder(f, 1, 1, 1, 0.15)

    f.topLine = f:CreateTexture(nil, "ARTWORK")
    f.topLine:SetHeight(2)
    f.topLine:SetPoint("TOPLEFT", 1, -1)
    f.topLine:SetPoint("TOPRIGHT", -1, -1)

    -- Header
    local iconFrame = CreateFrame("Frame", nil, f)
    iconFrame:SetSize(36, 36)
    iconFrame:SetPoint("TOPLEFT", 18, -14)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON)

    f.heading = font(f, 18)
    f.heading:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 12, -1)
    f.heading:SetText("Oathbreaker")
    f.subtitle = font(f, 11, 0.5)
    f.subtitle:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 12, 2)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(12, 12)
    close:SetPoint("TOPRIGHT", -16, -16)
    close:SetHitRectInsets(-8, -8, -8, -8)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture(CLOSE_ICON)
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function(self) self.icon:SetAlpha(1) end)
    close:SetScript("OnLeave", function(self) self.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton = close

    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(14, 14)
    gear:SetPoint("RIGHT", close, "LEFT", -12, 0)
    gear:SetHitRectInsets(-6, -6, -6, -6)
    gear.icon = gear:CreateTexture(nil, "OVERLAY")
    gear.icon:SetAllPoints()
    gear.icon:SetTexture(EUI.COGS_ICON)
    gear.icon:SetAlpha(0.7)
    gear:SetScript("OnEnter", function(self) self.icon:SetAlpha(1) end)
    gear:SetScript("OnLeave", function(self) self.icon:SetAlpha(0.7) end)
    gear:SetScript("OnClick", toggleSettings)
    f.gearButton = gear
    hairline(f, "TOPLEFT", "TOPRIGHT", -HEADER_H)

    -- Toolbar
    f.gapPrefix = font(f, 11, 0.5)
    f.gapPrefix:SetPoint("TOPLEFT", 18, -(HEADER_H + 12))
    f.gapPrefix:SetText("Show quests at least")
    f.less = stepButton(f, "-")
    f.less:SetPoint("LEFT", f.gapPrefix, "RIGHT", 8, 0)
    f.gapValue = font(f, 13)
    f.gapValue:SetPoint("LEFT", f.less, "RIGHT", 0, 0)
    f.gapValue:SetWidth(28)
    f.more = stepButton(f, "+")
    f.more:SetPoint("LEFT", f.gapValue, "RIGHT", 0, 0)
    f.gapSuffix = font(f, 11, 0.5)
    f.gapSuffix:SetPoint("LEFT", f.more, "RIGHT", 8, 0)
    f.gapSuffix:SetText("levels below you")

    f.selectAll = CreateFrame("Button", nil, f)
    f.selectAll:SetSize(80, 20)
    f.selectAll:SetPoint("TOPRIGHT", -18, -(HEADER_H + 9))
    f.selectAll.label = font(f.selectAll, 11, 0.55)
    f.selectAll.label:SetPoint("RIGHT")
    f.selectAll:SetScript("OnEnter", function(self) self.label:SetTextColor(accent()) end)
    f.selectAll:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1, 0.55) end)
    hairline(f, "TOPLEFT", "TOPRIGHT", -(HEADER_H + TOOLBAR_H))

    -- List
    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.scroll:SetPoint("TOPLEFT", 1, -(HEADER_H + TOOLBAR_H + 1))
    f.scroll:SetPoint("TOPRIGHT", -1, -(HEADER_H + TOOLBAR_H + 1))
    f.child = CreateFrame("Frame", nil, f.scroll)
    f.child:SetWidth(WIDTH - 2)
    f.child:SetHeight(1)
    f.scroll:SetScrollChild(f.child)
    local updateScrollbar = EUI.AttachSmoothScrollbar and EUI.AttachSmoothScrollbar(f.scroll, { child = f.child, step = ROW_H })

    f.empty = font(f, 13, 0.5)
    f.empty:SetPoint("TOP", f.scroll, "TOP", 0, -32)
    f.empty:SetWidth(WIDTH - 60)

    -- Footer
    f.footerLine = hairline(f, "BOTTOMLEFT", "BOTTOMRIGHT", FOOTER_H)
    f.status = font(f, 10, 0.4)
    f.status:SetPoint("BOTTOMLEFT", 18, 13)
    f.status:SetWidth(WIDTH - 230)
    f.status:SetJustifyH("LEFT")

    f.action = CreateFrame("Button", nil, f)
    f.action:SetSize(176, 30)
    f.action:SetPoint("BOTTOMRIGHT", -18, 12)
    local actionBg = f.action:CreateTexture(nil, "BACKGROUND")
    actionBg:SetAllPoints()
    f.actionBorder = EUI.MakeBorder(f.action, 1, 1, 1, 0.3)
    f.action.label = font(f.action, 13)
    f.action.label:SetPoint("CENTER")

    f.rows = {}
    local armed, armToken, hovering = false, 0, false
    local current = {}

    local function paintAction()
        local count = #selected(current)
        local r, g, b = accent()
        if armed then r, g, b = 1, 0.32, 0.32 end
        local enabled = count > 0
        if armed then
            f.action.label:SetText(("Really abandon %d?"):format(count))
        else
            f.action.label:SetText(("Abandon %d %s"):format(count, count == 1 and "quest" or "quests"))
        end
        f.action.label:SetTextColor(r, g, b, enabled and 1 or 0.35)
        actionBg:SetColorTexture(r, g, b, armed and 0.16 or (hovering and enabled and 0.1 or 0.04))
        if f.actionBorder and f.actionBorder.SetColor then
            f.actionBorder:SetColor(r, g, b, enabled and ((armed or hovering) and 1 or 0.55) or 0.2)
        end
    end

    function f.Refresh()
        armed = false
        armToken = armToken + 1
        local list, protected = candidates()
        current = list or {}
        for i, entry in ipairs(current) do
            f.rows[i] = f.rows[i] or createRow(f.child, i)
            paintRow(f.rows[i], entry)
        end
        for i = #current + 1, #f.rows do f.rows[i]:Hide() end

        local r, g, b = accent()
        f.topLine:SetColorTexture(r, g, b, 0.85)

        local listHeight = math.max(ROW_H * 2, math.min(#current, MAX_ROWS) * ROW_H)
        f.child:SetHeight(math.max(1, #current * ROW_H))
        f.scroll:SetHeight(listHeight)
        f.scroll:SetVerticalScroll(0)
        f:SetHeight(HEADER_H + TOOLBAR_H + listHeight + FOOTER_H + 2)
        if updateScrollbar then updateScrollbar() end

        f.gapValue:SetText(db.gap)
        local chosen = #selected(current)
        f.selectAll.label:SetText(chosen == #current and "Select none" or "Select all")
        f.selectAll:SetShown(#current > 0)
        if not list then
            f.subtitle:SetText("Waiting for a Zygor guide")
            f.empty:SetText("Load a Zygor guide first, so I know which quests you still need.")
            f.status:SetText("")
        else
            f.subtitle:SetText(("%d of %d selected"):format(chosen, #current))
            f.empty:SetText("Your quest log is clean.")
            f.status:SetText(("%d quests protected by your guides,\nturn-ins and dungeons"):format(protected))
        end
        f.empty:SetShown(#current == 0)
        paintAction()
    end

    local function setGap(gap)
        db.gap = math.max(1, math.min(30, gap))
        f.Refresh()
    end
    f.less:SetScript("OnClick", function() setGap(db.gap - 1) end)
    f.more:SetScript("OnClick", function() setGap(db.gap + 1) end)

    f.selectAll:SetScript("OnClick", function()
        local keepAll = #selected(current) == #current
        for _, entry in ipairs(current) do db.keep[entry.id] = keepAll or nil end
        f.Refresh()
    end)

    f.action:SetScript("OnEnter", function() hovering = true; paintAction() end)
    f.action:SetScript("OnLeave", function() hovering = false; paintAction() end)
    f.action:SetScript("OnClick", function()
        local chosen = selected(current)
        if #chosen == 0 then return end
        if not armed then
            armed = true
            armToken = armToken + 1
            local token = armToken
            paintAction()
            C_Timer.After(CONFIRM_SECONDS, function()
                if token == armToken then
                    armed = false
                    paintAction()
                end
            end)
            return
        end
        for _, entry in ipairs(chosen) do abandon(entry.id) end
        say(("Abandoned %d %s."):format(#chosen, #chosen == 1 and "quest" or "quests"))
        f:Hide()
    end)

    f:Hide()
    return f
end

local function open()
    window = window or createWindow()
    window:Show()
    window.Refresh()
end

local function toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        open()
    end
end

_G.Oathbreaker = { Open = open, Toggle = toggle, Candidates = candidates }

-------------------------------------------------------------------------------
-- Minimap button
-------------------------------------------------------------------------------
local function fillTooltip(tooltip)
    local list = candidates()
    tooltip:AddLine(ADDON)
    if list then
        tooltip:AddLine(("%d %s to clear out"):format(#list, #list == 1 and "quest" or "quests"), 1, 1, 1)
    end
    tooltip:AddLine("Left-click: quest list", 0.7, 0.7, 0.7)
    tooltip:AddLine("Right-click: settings", 0.7, 0.7, 0.7)
end

local function createMinimapButton()
    local broker = LibStub and LibStub("LibDataBroker-1.1", true)
    minimapIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (broker and minimapIcon) then return end

    local launcher = broker:NewDataObject(ADDON, {
        type = "launcher",
        text = ADDON,
        icon = ICON,
        OnClick = function(_, mouseButton)
            if mouseButton == "RightButton" then toggleSettings() else toggle() end
        end,
        OnTooltipShow = fillTooltip,
    })
    minimapIcon:Register(ADDON, launcher, db.minimap)
end

-------------------------------------------------------------------------------
-- Button in Zygor's title bar, left of its report and close buttons
-------------------------------------------------------------------------------
local function createZygorButton()
    local frame = _G.ZGV and _G.ZGV.Frame
    local controls = frame and frame.Controls
    local close = controls and controls.CloseButton
    if not close then return false end

    local b = CreateFrame("Button", "OathbreakerZygorButton", close:GetParent())
    b:SetSize(20, 20)
    b:SetFrameLevel(close:GetFrameLevel() + 1)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ICON)
    b.icon:SetAlpha(0.85)

    local report = controls.ReportButton
    local function place()
        b:ClearAllPoints()
        b:SetPoint("RIGHT", report and report:IsShown() and report or close, "LEFT", -6, 0)
    end
    place()
    if report then
        report:HookScript("OnShow", place)
        report:HookScript("OnHide", place)
    end

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then toggleSettings() else toggle() end
    end)
    b:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        fillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.85)
        GameTooltip:Hide()
    end)
    return true
end

-------------------------------------------------------------------------------
-- Smart skip: Zygor already knows quest prerequisites, but only checks them during
-- its Quest Catchup. Running that check all the time lets it skip steps you cannot do.
-------------------------------------------------------------------------------
-- Optional second source: QuestieDB also knows prerequisites of new Forever quests.
-- Without it, only Zygor's own chains count.
local QUESTIE_CONTRACT = 3
local questiePrereqs = {}

local function questieQuests()
    local lib = rawget(_G, "LibQuestieDB")
    if lib and lib.Quest and lib.RequireContract and lib.RequireContract(QUESTIE_CONTRACT) then return lib.Quest end
end

local function prereqList(values, skip)
    local list = {}
    for _, id in ipairs(values or {}) do
        if type(id) == "number" and id > 0 and not skip[id] then list[#list + 1] = id end
    end
    return list
end

local function readQuestiePrereqs(quests, questID)
    if not quests.Exists(questID) then return false end
    local skip = { [questID] = true }
    for _, key in ipairs({ "exclusiveTo", "breadcrumbs" }) do
        for _, id in ipairs(quests.Get(questID, key) or {}) do skip[id] = true end
    end
    local all = prereqList(quests.Get(questID, "preQuestGroup"), skip)
    local any = prereqList(quests.Get(questID, "preQuestSingle"), skip)
    if not all[1] and not any[1] then return false end
    return { all = all, any = any }
end

local function isPrereqDone(zgv, questID)
    if C_QuestLog.IsQuestFlaggedCompleted(questID) then return true end
    local quest = zgv.questsbyid and zgv.questsbyid[questID]
    if not (quest and quest.inlog and zgv.CurrentStep and zgv.CurrentStep.goals) then return false end
    for _, goal in pairs(zgv.CurrentStep.goals) do
        if goal.action == "turnin" and goal.questid == questID then return true end
    end
    return false
end

local function questiePrereqData(questID)
    local cached = questiePrereqs[questID]
    if cached == nil then
        local quests = questieQuests()
        if not quests then return false end
        local ok, result = pcall(readQuestiePrereqs, quests, questID)
        cached = ok and result or false
        questiePrereqs[questID] = cached
    end
    return cached
end
ns.questiePrereqData = questiePrereqData

local function questiePrereqsMet(zgv, questID)
    local cached = questiePrereqData(questID)
    if not cached then return true end
    for _, id in ipairs(cached.all) do
        if not isPrereqDone(zgv, id) then return false end
    end
    if cached.any[1] then
        for _, id in ipairs(cached.any) do
            if isPrereqDone(zgv, id) then return true end
        end
        return false
    end
    return true
end

local zygorIsQuestPossible

-- Zygor only runs its chain check during Quest Catchup unless told it has started.
-- On WoW Forever it also never creates the "use quest chains" option, so the profile
-- value stays nil and every quest counts as possible: switch it on for the call.
local function possibleWithChains(zgv, questID)
    local char, profile = zgv.db.char, zgv.db.profile or {}
    local started, chains = char.SISstarted, profile.beta_use_chains
    char.SISstarted, profile.beta_use_chains = true, true
    local ok, state, comment = pcall(zygorIsQuestPossible, zgv.QuestDB, questID)
    char.SISstarted, profile.beta_use_chains = started, chains
    if not ok then error(state, 0) end
    return state, comment
end

local function installSmartSkip()
    local zgv = _G.ZGV
    local questDB = zgv and zgv.QuestDB
    if not (questDB and questDB.IsQuestPossible) then return end

    zygorIsQuestPossible = questDB.IsQuestPossible
    questDB.IsQuestPossible = function(self, questID)
        local char = zgv.db and zgv.db.char
        if not (db.smartSkip and char) then return zygorIsQuestPossible(self, questID) end
        local state, comment = possibleWithChains(zgv, questID)
        local noZygorChain = not (zgv.Chains and zgv.Chains[questID])
        if state == questDB.VALID_NOW and noZygorChain and not questiePrereqsMet(zgv, questID) then
            return questDB.VALID_FUTURE, "questie: prerequisite missing"
        end
        return state, comment
    end
end

-- Zygor only skips a step whose quest goals are all impossible while it is already
-- fast-forwarding, and a "talk to" goal in the same step can keep it open. Skip such
-- steps ourselves, but only moving forward (going back stays possible).
local SKIPPABLE_ACTIONS = { talk = true, ["goto"] = true, gossip = true, text = true, accept = true, turnin = true }
local lastGuide, lastNum, movingForward

function ns.SkipImpossibleStep(zgv)
    local step = zgv.CurrentStep
    if not (db.smartSkip and step and step.goals and not zgv.pause) then return end
    local guide, num = zgv.CurrentGuide, step.num
    if guide ~= lastGuide or num ~= lastNum then
        movingForward = lastGuide == nil or (guide == lastGuide and num > lastNum)
        lastGuide, lastNum = guide, num
    end
    if not movingForward then return end
    local questGoals = 0
    for _, goal in ipairs(step.goals) do
        local action = goal.action
        if action then
            if not SKIPPABLE_ACTIONS[action] then return end
            if action == "accept" or action == "turnin" then
                questGoals = questGoals + 1
                local complete, possible = goal:IsComplete()
                if complete or possible then return end
            end
        end
    end
    if questGoals > 0 then zgv:SkipStep(true) end
end

local function installStepSkipper(zgv)
    local original = zgv and zgv.TryToCompleteStep
    if not original or zgv.oathbreakerStepSkipper then return end
    zgv.oathbreakerStepSkipper = true
    local last = 0
    zgv.TryToCompleteStep = function(self, ...)
        original(self, ...)
        local now = GetTime()
        if now - last < 0.5 or (self.Frame and not self.Frame:IsVisible()) then return end
        last = now
        ns.guarded("step skip", ns.SkipImpossibleStep, self)
    end
end

local function questieLevelMet(questID)
    local quests = questieQuests()
    if not quests then return true end
    local ok, required = pcall(function()
        return quests.Exists(questID) and quests.Get(questID, "requiredLevel")
    end)
    return not (ok and type(required) == "number" and required > UnitLevel("player"))
end

-- Grey ("trivial") quests: worth little XP, easy to overlook in Zygor's step list.
-- Needs QuestieDB for the quest level; without it nothing gets marked.
ns.LOW_LEVEL_TAG = "|cff9d9d9d(low level)|r"
local lowLevelCache, lowLevelFor = {}, nil

function ns.isLowLevelQuest(questID)
    local level = UnitLevel("player")
    if lowLevelFor ~= level then lowLevelCache, lowLevelFor = {}, level end
    local cached = lowLevelCache[questID]
    if cached ~= nil then return cached end
    local result = false
    local quests = questieQuests()
    if quests then
        local ok, questLevel = pcall(function()
            return quests.Exists(questID) and quests.Get(questID, "questLevel")
        end)
        if ok and type(questLevel) == "number" and questLevel > 0 then
            local range = GetQuestGreenRange and GetQuestGreenRange() or 8
            result = questLevel < level - range
        end
    end
    lowLevelCache[questID] = result
    return result
end

local MARKED_ACTIONS = { accept = true, turnin = true }

local function markGoalText(goal, text, ...)
    if db.markLowLevel and type(text) == "string" and text ~= "" and MARKED_ACTIONS[goal.action]
        and goal.questid and ns.isLowLevelQuest(goal.questid) then
        text = text .. " " .. ns.LOW_LEVEL_TAG
    end
    return text, ...
end

function ns.InstallLowLevelMarker(zgv)
    local proto = zgv and zgv.GoalProto
    if not (proto and proto.GetText) or proto.oathbreakerMarked then return end
    local original = proto.GetText
    proto.oathbreakerMarked = true
    proto.GetText = function(self, showcompleteness, brief, showtotals, nocolor)
        if nocolor then return original(self, showcompleteness, brief, showtotals, nocolor) end
        return markGoalText(self, original(self, showcompleteness, brief, showtotals, nocolor))
    end
end

-- True when Questie knows the quest and no race of your faction may take it (Neutral: never)
function ns.isOtherFactionQuest(questID)
    local faction = UnitFactionGroup("player")
    local quests, lib = questieQuests(), rawget(_G, "LibQuestieDB")
    local masks = lib and lib.Enum and lib.Enum.factionRaceMasks
    local mine = masks and masks[faction]
    if not (quests and mine) then return false end
    local ok, races = pcall(function() return quests.Exists(questID) and quests.Get(questID, "requiredRaces") end)
    if not (ok and type(races) == "number" and races > 0) then return false end
    return bit.band(races, mine) == 0
end

-- Same answer whether Smart skip is on or off
function ns.isQuestAvailable(zgv, questID)
    if ns.isOtherFactionQuest(questID) then return false end
    if zygorIsQuestPossible and zgv.db and zgv.db.char
        and possibleWithChains(zgv, questID) ~= zgv.QuestDB.VALID_NOW then
        return false
    end
    local hasZygorChain = zgv.Chains and zgv.Chains[questID]
    if not hasZygorChain and not questiePrereqsMet(zgv, questID) then return false end
    return questieLevelMet(questID)
end

-- Shared with Assistant.lua
ns.ICON, ns.say, ns.font, ns.accent, ns.openGuides = ICON, say, font, accent, openGuides
ns.questsOfGuide, ns.addCachePacks = questsOfGuide, addCachePacks
function ns.GetDB() return db end

function ns.guarded(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return end
    local message = label .. ": " .. tostring(err)
    if message ~= ns.lastError then
        ns.lastError = message
        say("|cffff5555Error|r in " .. message)
    end
end

function ns.neededLevelingQuests(zgv)
    local leveling = {}
    for _, guide in ipairs(openGuides(zgv)) do
        if not guide.title:find("^DUNGEONS") then leveling[#leveling + 1] = guide end
    end
    return neededQuests(zgv, leveling, true)
end

-- Zygor builds its title bar some time after login
local function installZygorButton()
    if createZygorButton() then return end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        tries = tries + 1
        if createZygorButton() or tries >= 30 then ticker:Cancel() end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        OathbreakerDB = OathbreakerDB or {}
        db = OathbreakerDB
        db.gap = db.gap or DEFAULT_GAP
        db.keep = db.keep or {}
        db.minimap = db.minimap or {}
        if db.smartSkip == nil then db.smartSkip = true end
        if db.guideFinder == nil then db.guideFinder = true end
        if db.sideQuests == nil then db.sideQuests = true end
        if db.guideCheck == nil then db.guideCheck = true end
        if db.updateNotice == nil then db.updateNotice = true end
        if db.markLowLevel == nil then db.markLowLevel = true end
        db.guideCheckStay = db.guideCheckStay or {}
        for _, key in ipairs({ "offerDungeons", "hintQuests", "hintFlights" }) do
            if db[key] == nil then db[key] = db.hints ~= false end
        end
        db.hints = nil
        db.dungeons = db.dungeons or {}
        db.hinted = db.hinted or {}
        db.sideGuides = db.sideGuides or {}
        createMinimapButton()
    elseif event == "PLAYER_LOGIN" and _G.ZGV then
        -- Zygor's cleanup buttons in its menu and the Smart Injection System now open this window.
        _G.ZGV.ShowQuestCleanup = function() open() end
        installSmartSkip()
        ns.InstallLowLevelMarker(_G.ZGV)
        installStepSkipper(_G.ZGV)
        ns.StartAssistant()
        installZygorButton()
    end
end)

SLASH_OATHBREAKER1 = "/oathbreaker"
SlashCmdList.OATHBREAKER = function() toggle() end
