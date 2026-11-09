-- Side quests: up to two extra guides you take along next to your main guide.
-- They never drive Zygor. A hint only appears when one of their quests can be
-- accepted or turned in right now and costs little extra walking.
local ADDON, ns = ...

local EUI = EllesmereUI
local MAX_SIDE_GUIDES = 2
-- One radius in the settings drives all three limits (they used to be 350, 200 and 120)
local DEFAULT_RADIUS, MIN_RADIUS, MAX_RADIUS, RADIUS_STEP = 450, 150, 1000, 50
function ns.SideRadius()
    local radius = tonumber(ns.GetDB().sideRadius) or DEFAULT_RADIUS
    return math.max(MIN_RADIUS, math.min(MAX_RADIUS, radius))
end
function ns.ChangeSideRadius(direction)
    local db = ns.GetDB()
    db.sideRadius = math.max(MIN_RADIUS, math.min(MAX_RADIUS, ns.SideRadius() + direction * RADIUS_STEP))
    return db.sideRadius
end
local SAME_NPC_YARDS, LEFT_BEHIND_YARDS = 15, 700
local PICKER_WIDTH, PICKER_HEIGHT, PICKER_TOP, PICKER_ROW_H = 420, 480, 64, 32

local stopsByGuide = {}
local detour
local picker

-------------------------------------------------------------------------------
-- Reading a guide
-------------------------------------------------------------------------------
local function compileOnly(zgv, text)
    text = text:match("^%s*(.-)%s*$")
    local condition = text:match("^if%s+(.+)$")
    if condition then
        local ok, check = pcall(zgv.Parser.MakeCondition, condition, true)
        return ok and check or function() return false end
    end
    local names = {}
    for name in text:gmatch("[^,]+") do names[#names + 1] = name:match("^%s*(.-)%s*$") end
    local ok, matches = pcall(zgv.RaceClassMatch, zgv, names)
    local allowed = ok and matches and true or false
    return function() return allowed end
end

-- Quest conditions like completedq() change as you play; class and race do not
local function isCharacterRule(only)
    return not only:find("q(", 1, true)
end

local function parseStops(zgv, raw)
    local stops, minLevel = {}, 0
    local step = { conditions = {}, characterConditions = {}, turnins = {} }
    for line in raw:gmatch("[^\n]+") do
        if line:match("^%s*step%s*$") then
            step = { conditions = {}, characterConditions = {}, turnins = {} }
        else
            minLevel = math.max(minLevel, tonumber(line:match("|ding (%d+)")) or 0)
            step.npc = line:match("^%s*talk (.-)##") or step.npc
            local spot = line:match("|goto ([^|]+)") or line:match("^%s*goto ([^|]+)")
            local only = line:match("|only%s+([^|]+)") or line:match("^%s*only%s+([^|]+)")
            local condition = only and compileOnly(zgv, only)
            local verb, title, id = line:match("^%s*(%a+) (.-)##(%d+)")
            if (verb == "accept" or verb == "turnin") and not line:find("|instant", 1, true) then
                id = tonumber(id)
                local stop = {
                    key = "side:" .. verb .. ":" .. id, verb = verb, id = id, title = title,
                    spot = spot, condition = condition, step = step, minLevel = minLevel, after = {},
                    characterCondition = condition and isCharacterRule(only) and condition or nil,
                }
                -- "turnin A, accept B" in one step: B unlocks with A
                if verb == "accept" then
                    for _, turnin in ipairs(step.turnins) do stop.after[#stop.after + 1] = turnin end
                elseif not condition then
                    step.turnins[#step.turnins + 1] = id
                end
                stops[#stops + 1] = stop
            else
                if condition and line:match("^%s*|?only") then
                    step.conditions[#step.conditions + 1] = condition
                    if isCharacterRule(only) then step.characterConditions[#step.characterConditions + 1] = condition end
                end
                step.spot = spot or step.spot
            end
        end
    end
    for _, stop in ipairs(stops) do
        stop.spot = stop.spot or stop.step.spot
        stop.npc = stop.step.npc
    end
    return stops
end

local function stopsOf(zgv, guide)
    if not stopsByGuide[guide] then
        stopsByGuide[guide] = type(guide.rawdata) == "string" and parseStops(zgv, guide.rawdata) or {}
    end
    return stopsByGuide[guide]
end

-------------------------------------------------------------------------------
-- Can this be done right now?
-------------------------------------------------------------------------------
local function passes(condition)
    local ok, result = pcall(condition)
    return ok and result and true or false
end

local function canTurnIn(id)
    local index = C_QuestLog.GetLogIndexForQuestID(id)
    if not (index and index > 0) then return false end
    return (C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id)) and true or false
end

local function canAccept(zgv, stop)
    if C_QuestLog.IsQuestFlaggedCompleted(stop.id) then return false end
    local index = C_QuestLog.GetLogIndexForQuestID(stop.id)
    if index and index > 0 then return false end
    for _, turnin in ipairs(stop.after) do
        if not C_QuestLog.IsQuestFlaggedCompleted(turnin) then return false end
    end
    return ns.isQuestAvailable(zgv, stop.id)
end

local function isDoable(zgv, stop)
    if UnitLevel("player") < stop.minLevel then return false end
    if stop.condition and not passes(stop.condition) then return false end
    for _, condition in ipairs(stop.step.conditions) do
        if not passes(condition) then return false end
    end
    if stop.verb == "turnin" then return canTurnIn(stop.id) end
    return canAccept(zgv, stop)
end

function ns.StopFitsCharacter(stop)
    if stop.characterCondition and not passes(stop.characterCondition) then return false end
    for _, condition in ipairs(stop.step.characterConditions) do
        if not passes(condition) then return false end
    end
    return true
end

ns.StopsOf = stopsOf

-- The main guide is about to do this anyway
local function inCurrentStep(zgv, id)
    local step = zgv.CurrentStep
    for _, goal in pairs(step and step.goals or {}) do
        if goal.questid == id then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- Picking the hint
-------------------------------------------------------------------------------
local function arrowTarget(zgv, instance)
    local way = zgv.Pointer and zgv.Pointer.DestinationWaypoint
    if not (way and way.m and way.x) then return end
    local wx, wy, wayInstance = zgv.HBD:GetWorldCoordinatesFromZone(way.x, way.y, way.m)
    if wx and wayInstance == instance then return wx, wy end
end

local function markedGuides(zgv)
    local guides = {}
    for title in pairs(ns.GetDB().sideGuides) do
        local guide = zgv:GetGuideByTitle(title)
        if guide and guide ~= zgv.CurrentGuide then guides[#guides + 1] = guide end
    end
    return guides
end

local function findNearby(zgv, px, py, instance)
    local db, hbd = ns.GetDB(), zgv.HBD
    local STOP_YARDS = ns.SideRadius()
    local DETOUR_YARDS, NO_TARGET_YARDS = STOP_YARDS * 4 / 7, STOP_YARDS * 12 / 35
    local targetX, targetY = arrowTarget(zgv, instance)
    local direct = targetX and hbd:GetWorldDistance(instance, px, py, targetX, targetY)
    local found, seen = {}, {}
    for _, guide in ipairs(markedGuides(zgv)) do
        for _, stop in ipairs(stopsOf(zgv, guide)) do
            if not seen[stop.key] and not db.hinted[stop.key] and ns.resolveSpot(zgv, stop) and stop.instance == instance then
                local distance = hbd:GetWorldDistance(instance, px, py, stop.wx, stop.wy)
                if distance and distance <= STOP_YARDS then
                    local onward = direct and hbd:GetWorldDistance(instance, stop.wx, stop.wy, targetX, targetY)
                    local extra = onward and math.max(0, distance + onward - direct)
                    local worthIt = extra and extra <= DETOUR_YARDS or (not extra and distance <= NO_TARGET_YARDS)
                    if worthIt and isDoable(zgv, stop) and not inCurrentStep(zgv, stop.id) then
                        seen[stop.key] = true
                        found[#found + 1] = { stop = stop, distance = distance, extra = extra }
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b)
        local extraA, extraB = a.extra or a.distance, b.extra or b.distance
        if extraA ~= extraB then return extraA < extraB end
        return a.distance < b.distance
    end)
    return found
end

local function walkText(best)
    if not best.extra then return ("%d yd away"):format(math.floor(best.distance + 0.5)) end
    local extra = math.floor(best.extra + 0.5)
    return extra < 10 and "on your way" or ("%d yd detour"):format(extra)
end

local function countVerbs(stops)
    local accepts, turnins = 0, 0
    for _, stop in ipairs(stops) do
        if stop.verb == "accept" then accepts = accepts + 1 else turnins = turnins + 1 end
    end
    local parts = {}
    if accepts > 0 then parts[#parts + 1] = "accept " .. accepts end
    if turnins > 0 then parts[#parts + 1] = "turn in " .. turnins end
    return table.concat(parts, ", ")
end

local function verbWord(stop)
    return stop.verb == "accept" and "Accept" or "Turn in"
end

local function buildHint(zgv, found, instance)
    local best = found[1]
    local stops, keys = {}, {}
    for _, candidate in ipairs(found) do
        local apart = zgv.HBD:GetWorldDistance(instance, best.stop.wx, best.stop.wy, candidate.stop.wx, candidate.stop.wy)
        if apart and apart <= SAME_NPC_YARDS then
            stops[#stops + 1] = candidate.stop
            keys[#keys + 1] = candidate.stop.key
        end
    end
    local first = best.stop
    local more = #found - #stops
    local suffix = more > 0 and ("  +%d more"):format(more) or ""
    local hint = {
        key = first.key, keys = keys, stops = stops, map = first.map, x = first.x, y = first.y,
        onClick = ns.StartSideDetour, onDismiss = ns.EndSideDetour,
        atlas = first.verb == "accept" and "QuestNormal" or "QuestTurnin",
    }
    if #stops == 1 then
        hint.heading = "Side quest: " .. first.title
        hint.detail = ("%s%s, %s%s"):format(verbWord(first), first.npc and (" at " .. first.npc) or "", walkText(best), suffix)
        hint.waypoint = verbWord(first) .. " " .. first.title
    else
        local place = first.npc or "same spot"
        hint.heading = ("%d side quests: %s"):format(#stops, place)
        hint.detail = ("%s, %s%s"):format(countVerbs(stops):gsub("^%l", string.upper), walkText(best), suffix)
        hint.waypoint = "Side quests: " .. place
        -- One clickable line per quest, so you see which ones are meant
        hint.rows = {}
        for _, stop in ipairs(stops) do
            hint.rows[#hint.rows + 1] = {
                verb = verbWord(stop), title = stop.title,
                map = stop.map, x = stop.x, y = stop.y, waypoint = verbWord(stop) .. " " .. stop.title,
            }
        end
    end
    return hint
end

function ns.NearestSideStop(zgv, px, py, instance)
    local found = findNearby(zgv, px, py, instance)
    if found[1] then return buildHint(zgv, found, instance) end
end

-------------------------------------------------------------------------------
-- Detour: Zygor's arrow goes back to the guide once the stop is dealt with
-------------------------------------------------------------------------------
function ns.StartSideDetour(hint)
    detour = hint
end

function ns.EndSideDetour()
    local zgv = _G.ZGV
    if not detour then return end
    detour = nil
    zgv.Pointer:ClearWaypoints("manual")
    zgv:ShowWaypoints()
end

function ns.UpdateSideDetour(zgv, px, py, instance)
    if not detour then return end
    local first = detour.stops[1]
    local distance = first.instance == instance and zgv.HBD:GetWorldDistance(instance, px, py, first.wx, first.wy)
    local leftBehind = not distance or distance > LEFT_BEHIND_YARDS
    local stillOpen = false
    for _, stop in ipairs(detour.stops) do
        if isDoable(zgv, stop) then stillOpen = true end
    end
    if leftBehind or not stillOpen then ns.EndSideDetour() end
end

-------------------------------------------------------------------------------
-- Picker
-------------------------------------------------------------------------------
local function shortName(guide)
    return (guide.title:gsub("^[^\\]+\\", ""))
end

local function isSuggested(guide)
    local ok, status = pcall(guide.GetStatus, guide)
    return ok and status == "SUGGESTED"
end

local function pickableGuides(zgv)
    local list = {}
    for order, guide in ipairs(zgv.registeredguides or {}) do
        local title = guide.title or ""
        local isQuestGuide = title:find("^LEVELING") or title:find("^DUNGEONS\\.+ Quests$")
        if isQuestGuide and type(guide.rawdata) == "string" and guide.rawdata:find("accept ", 1, true)
            and ns.guideApplies(guide) then
            list[#list + 1] = { guide = guide, order = order, suggested = isSuggested(guide) }
        end
    end
    table.sort(list, function(a, b)
        if a.suggested ~= b.suggested then return a.suggested end
        return a.order < b.order
    end)
    return list
end

function ns.SideGuideCount()
    local zgv, count = _G.ZGV, 0
    if not zgv then return 0, MAX_SIDE_GUIDES end
    for title in pairs(ns.GetDB().sideGuides) do
        if zgv:GetGuideByTitle(title) then count = count + 1 end
    end
    return count, MAX_SIDE_GUIDES
end

local function createPickerRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PICKER_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * PICKER_ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * PICKER_ROW_H)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.04)
    row.hover:Hide()
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
    row.title = ns.font(row, 13)
    row.title:SetPoint("LEFT", row.box, "RIGHT", 12, 0)
    row.fits = ns.font(row, 10, 0.45)
    row.fits:SetPoint("RIGHT", -18, 0)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self) ns.ToggleSideGuide(self.guide.title) end)
    return row
end

local function refreshPicker()
    local zgv = _G.ZGV
    if not (picker and zgv) then return end
    local list, db = pickableGuides(zgv), ns.GetDB()
    local r, g, b = ns.accent()
    for index, entry in ipairs(list) do
        picker.rows[index] = picker.rows[index] or createPickerRow(picker.child, index)
        local row = picker.rows[index]
        row.guide = entry.guide
        row.title:SetText(shortName(entry.guide))
        row.fits:SetText(entry.suggested and "fits your level" or "")
        row.check:SetColorTexture(r, g, b)
        row.check:SetShown(db.sideGuides[entry.guide.title] and true or false)
        row:Show()
    end
    for index = #list + 1, #picker.rows do picker.rows[index]:Hide() end
    picker.child:SetHeight(math.max(1, #list * PICKER_ROW_H))
    local count, limit = ns.SideGuideCount()
    picker.summary:SetText(("%d of %d guides taken along"):format(count, limit))
    if picker.updateScrollbar then picker.updateScrollbar() end
    if ns.settingsFrame then ns.settingsFrame.Refresh() end
end

function ns.AddSideGuide(title)
    local db = ns.GetDB()
    if not db.sideGuides[title] and ns.SideGuideCount() >= MAX_SIDE_GUIDES then
        ns.say(("You can take along %d guides at most. Untick one first."):format(MAX_SIDE_GUIDES))
        return false
    end
    db.sideGuides[title] = true
    refreshPicker()
    return true
end

function ns.ToggleSideGuide(title)
    local db = ns.GetDB()
    if db.sideGuides[title] then
        db.sideGuides[title] = nil
        refreshPicker()
    else
        ns.AddSideGuide(title)
    end
end

local function createPicker()
    local f = ns.panel("OathbreakerSidePicker", PICKER_WIDTH, PICKER_HEIGHT, "DIALOG")
    f:SetPoint("CENTER", 40, 20)
    f:SetFrameLevel(60)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, f:GetName())
    f.icon:SetSize(36, 36)
    f.icon:SetPoint("TOPLEFT", 18, -14)
    local heading = ns.font(f, 18)
    heading:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -1)
    heading:SetText("Side guides")
    f.summary = ns.font(f, 11, 0.5)
    f.summary:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 12, 2)
    f.closeButton:SetScript("OnClick", function() f:Hide() end)
    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.scroll:SetPoint("TOPLEFT", 1, -PICKER_TOP)
    f.scroll:SetPoint("BOTTOMRIGHT", -1, 10)
    f.child = CreateFrame("Frame", nil, f.scroll)
    f.child:SetWidth(PICKER_WIDTH - 2)
    f.child:SetHeight(1)
    f.scroll:SetScrollChild(f.child)
    f.updateScrollbar = EUI.AttachSmoothScrollbar and EUI.AttachSmoothScrollbar(f.scroll, { child = f.child, step = PICKER_ROW_H })
    f.rows = {}
    ns.paintAccent(f)
    f:Hide()
    return f
end

function ns.ShowSidePicker()
    picker = picker or createPicker()
    refreshPicker()
    picker:Show()
end

function ns.ToggleSidePicker()
    if picker and picker:IsShown() then
        picker:Hide()
    else
        ns.ShowSidePicker()
    end
end

ns.SideQuests = { ParseStops = parseStops, IsDoable = isDoable, Refresh = refreshPicker, Pickable = pickableGuides, Reset = function() detour = nil; wipe(stopsByGuide) end }
