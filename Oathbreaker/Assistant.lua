-- Assistant: offers dungeon quest guides at the right level and points out dungeon
-- quest givers and undiscovered flight points close to you.
local ADDON, ns = ...

local EUI = EllesmereUI
local START_DELAY, SCAN_SECONDS, OFFER_EVERY_SCANS = 15, 2, 5
local QUEST_YARDS, FLIGHT_YARDS, FLIGHT_YARDS_LONG_TRIP, LONG_TRIP_YARDS = 120, 250, 500, 1000
local STATUS_CACHE_SECONDS = 30
local CLOSE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
local CLASS_NAMES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }

local dungeons
local askLater = {}
local nodeWorld = {}
local dialog, toast
local scanCount = 0

-------------------------------------------------------------------------------
-- Dungeon quest data, read from Zygor's "<Dungeon> Quests" guides
-------------------------------------------------------------------------------
local function classAllowed(line)
    local condition = line:match("|only if (.+)")
    if not condition or condition:find("not ", 1, true) then return true end
    local _, token = UnitClass("player")
    local named = false
    for _, class in ipairs(CLASS_NAMES) do
        if condition:find(class, 1, true) then
            if class:upper() == token then return true end
            named = true
        end
    end
    return not named
end

local function parseQuestGuide(raw)
    local quests, pending, npc, spot, blocked = {}, {}, nil, nil, false
    local function flush()
        if not blocked then
            for _, quest in ipairs(pending) do
                quest.spot = quest.spot or spot
                quests[#quests + 1] = quest
            end
        end
        pending, npc, spot, blocked = {}, nil, nil, false
    end
    for line in raw:gmatch("[^\n]+") do
        if line:match("^%s*step%s*$") then
            flush()
        else
            npc = line:match("^%s*talk (.-)##") or npc
            local lineSpot = line:match("|goto ([^|]+)")
            if line:match("^%s*|only if") and not classAllowed(line) then blocked = true end
            local title, id = line:match("^%s*accept (.-)##(%d+)")
            if title then
                if classAllowed(line) then
                    pending[#pending + 1] = { id = tonumber(id), title = title, npc = npc, spot = lineSpot }
                end
            elseif lineSpot then
                spot = lineSpot
            end
        end
    end
    flush()
    return quests
end

local function levelRange(zgv, name)
    local prefix = "DUNGEONS\\" .. name .. " ("
    for _, guide in ipairs(zgv.registeredguides) do
        if guide.title and guide.title:sub(1, #prefix) == prefix then
            return guide.title:match("%((%d+%-%d+)%)")
        end
    end
end

local function loadDungeons(zgv)
    if dungeons then return dungeons end
    if not (zgv.registeredguides and zgv.registeredguides[1]) then return {} end
    dungeons = {}
    for _, guide in ipairs(zgv.registeredguides) do
        local name = guide.title and guide.title:match("^DUNGEONS\\(.+) Quests$")
        if name and type(guide.rawdata) == "string" then
            dungeons[#dungeons + 1] = {
                name = name, guide = guide, quests = parseQuestGuide(guide.rawdata), range = levelRange(zgv, name),
            }
        end
    end
    return dungeons
end

local function questState(zgv, id)
    if C_QuestLog.IsQuestFlaggedCompleted(id) then return "done" end
    local index = C_QuestLog.GetLogIndexForQuestID(id)
    if index and index > 0 then return "log" end
    local questDB = zgv.QuestDB
    if questDB and questDB:IsQuestPossible(id) ~= questDB.VALID_NOW then return "locked" end
    return "open"
end

local function isSuggested(entry)
    local now = GetTime()
    if not entry.checkedAt or now - entry.checkedAt > STATUS_CACHE_SECONDS then
        local ok, status = pcall(entry.guide.GetStatus, entry.guide)
        entry.suggested = ok and status == "SUGGESTED"
        entry.checkedAt = now
    end
    return entry.suggested
end

local function isOpenInTab(zgv, guide)
    for _, open in ipairs(ns.openGuides(zgv)) do
        if open == guide then return true end
    end
    return false
end

local function resolve(zgv, item)
    if item.resolved ~= nil then return item.resolved end
    item.resolved = false
    if not item.spot then return false end
    local ok, map, _, x, y = pcall(zgv.Parser.ParseMapXYDist, item.spot)
    if not (ok and map and x) then return false end
    local wx, wy, instance = zgv.HBD:GetWorldCoordinatesFromZone(x, y, map)
    if not wx then return false end
    item.map, item.x, item.y, item.wx, item.wy, item.instance = map, x, y, wx, wy, instance
    item.resolved = true
    return true
end

-------------------------------------------------------------------------------
-- Shared widgets
-------------------------------------------------------------------------------
local function panel(name, width, height, strata)
    local f = CreateFrame("Button", name, UIParent)
    f:SetSize(width, height)
    f:SetFrameStrata(strata)
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
    EUI.MakeBorder(f, 1, 1, 1, 0.15)
    f.topLine = f:CreateTexture(nil, "ARTWORK")
    f.topLine:SetHeight(2)
    f.topLine:SetPoint("TOPLEFT", 1, -1)
    f.topLine:SetPoint("TOPRIGHT", -1, -1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture(ns.ICON)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(12, 12)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetHitRectInsets(-8, -8, -8, -8)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture(CLOSE_ICON)
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function(self) self.icon:SetAlpha(1) end)
    close:SetScript("OnLeave", function(self) self.icon:SetAlpha(0.7) end)
    f.closeButton = close
    return f
end

local function paintAccent(f)
    local r, g, b = ns.accent()
    f.topLine:SetColorTexture(r, g, b, 0.85)
end

local function actionButton(parent, text, width, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.089, 0.080, 0.072, 0.6)
    b.border = EUI.MakeBorder(b, 1, 1, 1, 0.3)
    b.label = ns.font(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    local function paint(hover)
        local r, g, b2 = 1, 1, 1
        if primary then r, g, b2 = ns.accent() end
        local strong = primary or hover
        b.label:SetTextColor(r, g, b2, hover and 1 or (strong and 0.9 or 0.55))
        if b.border and b.border.SetColor then b.border:SetColor(r, g, b2, hover and 1 or (primary and 0.55 or 0.3)) end
    end
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b.Repaint = function() paint(false) end
    paint(false)
    return b
end

-------------------------------------------------------------------------------
-- Dungeon offer
-------------------------------------------------------------------------------
local function openQuestTab(zgv, entry)
    local tab = zgv.Tabs:GetTabFromPool()
    tab:AssignGuide(entry.guide.title, 1, false, "guidechange")
    ns.say(entry.name .. " quests added as a Zygor tab.")
end

local function createDialog()
    local d = panel("OathbreakerDungeonOffer", 430, 142, "DIALOG")
    d:SetPoint("TOP", UIParent, "TOP", 0, -180)
    d.icon:SetSize(34, 34)
    d.icon:SetPoint("TOPLEFT", 16, -16)
    d.heading = ns.font(d, 16)
    d.heading:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -1)
    d.summary = ns.font(d, 11, 0.5)
    d.summary:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMRIGHT", 12, 2)
    d.question = ns.font(d, 12, 0.8)
    d.question:SetPoint("TOPLEFT", 16, -64)
    d.question:SetWidth(398)
    d.question:SetJustifyH("LEFT")

    d.collect = actionButton(d, "Collect", 130, true)
    d.collect:SetPoint("BOTTOMRIGHT", -16, 14)
    d.later = actionButton(d, "Later", 90)
    d.later:SetPoint("RIGHT", d.collect, "LEFT", -8, 0)
    d.never = actionButton(d, "Never", 90)
    d.never:SetPoint("RIGHT", d.later, "LEFT", -8, 0)

    d.collect:SetScript("OnClick", function()
        local db = ns.GetDB()
        if not db.sideQuests then
            openQuestTab(_G.ZGV, d.entry)
        elseif ns.AddSideGuide(d.entry.guide.title) then
            ns.say(d.entry.name .. " quests added as a side guide.")
        else
            -- Both slots taken: the dialog stays open until one is free
            ns.ShowSidePicker()
            return
        end
        db.dungeons[d.entry.name] = "yes"
        d:Hide()
    end)
    local function later()
        askLater[d.entry.name] = true
        d:Hide()
    end
    d.later:SetScript("OnClick", later)
    d.closeButton:SetScript("OnClick", later)
    d.never:SetScript("OnClick", function()
        ns.GetDB().dungeons[d.entry.name] = "no"
        d:Hide()
    end)
    d:Hide()
    return d
end

local function offerDungeon(zgv)
    local db = ns.GetDB()
    if dialog and dialog:IsShown() then return end
    for _, entry in ipairs(loadDungeons(zgv)) do
        if not db.dungeons[entry.name] and not askLater[entry.name]
            and isSuggested(entry) and not isOpenInTab(zgv, entry.guide) and not db.sideGuides[entry.guide.title] then
            local open, inLog = 0, 0
            for _, quest in ipairs(entry.quests) do
                local state = questState(zgv, quest.id)
                if state == "open" then open = open + 1 elseif state == "log" then inLog = inLog + 1 end
            end
            if open > 0 then
                dialog = dialog or createDialog()
                dialog.entry = entry
                dialog.question:SetText(db.sideQuests
                    and "Collect these quests along the way? You get a hint when one is close by."
                    or "Collect these quests along the way? They open as an extra Zygor tab.")
                dialog.heading:SetText(entry.range and ("%s  (%s)"):format(entry.name, entry.range) or entry.name)
                dialog.summary:SetText(("%d %s to pick up, %d already in your log"):format(open, open == 1 and "quest" or "quests", inLog))
                paintAccent(dialog)
                dialog.collect.Repaint()
                dialog:Show()
                return
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Nearby hints
-------------------------------------------------------------------------------
local function createToast()
    local db = ns.GetDB()
    local t = panel("OathbreakerHint", 360, 58, "MEDIUM")
    if db.toastPos then
        t:SetPoint(db.toastPos[1], UIParent, db.toastPos[2], db.toastPos[3], db.toastPos[4])
    else
        t:SetPoint("TOP", UIParent, "TOP", 0, -230)
    end
    t.icon:SetSize(30, 30)
    t.icon:SetPoint("LEFT", 12, 0)
    t.heading = ns.font(t, 13)
    t.heading:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 1)
    t.heading:SetPoint("RIGHT", t, "RIGHT", -30, 0)
    t.heading:SetJustifyH("LEFT")
    t.detail = ns.font(t, 11, 0.55)
    t.detail:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 10, 1)
    t.detail:SetPoint("RIGHT", t, "RIGHT", -14, 0)
    t.detail:SetJustifyH("LEFT")
    t.detail:SetWordWrap(false)

    t:SetMovable(true)
    t:RegisterForDrag("LeftButton")
    t:SetScript("OnDragStart", t.StartMoving)
    t:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        db.toastPos = { point, relative, x, y }
    end)
    t:SetScript("OnClick", function(self)
        local hint, pointer = self.hint, _G.ZGV.Pointer
        pointer:SetWaypoint(hint.map, hint.x, hint.y, {
            title = hint.waypoint, type = "manual", cleartype = true, icon = pointer.Icons.greendotbig,
            onminimap = "always", overworld = true, showonedge = true,
        })
        if hint.onClick then hint.onClick(hint) end
    end)
    t.closeButton:SetScript("OnClick", function()
        local hint = t.hint
        for _, key in ipairs(hint.keys or { hint.key }) do db.hinted[key] = true end
        if hint.onDismiss then hint.onDismiss(hint) end
        t:Hide()
    end)
    t:Hide()
    return t
end

local function showHint(hint)
    toast = toast or createToast()
    toast.hint = hint
    toast.heading:SetText(hint.heading)
    toast.detail:SetText(hint.detail)
    paintAccent(toast)
    toast:Show()
end

local function hideHint()
    if toast then toast:Hide() end
end

local function isLongTrip(zgv, px, py, instance)
    local way = zgv.Pointer and zgv.Pointer.DestinationWaypoint
    if not (way and way.m and way.x) then return false end
    local wx, wy, wayInstance = zgv.HBD:GetWorldCoordinatesFromZone(way.x, way.y, way.m)
    if not wx or wayInstance ~= instance then return true end
    local distance = zgv.HBD:GetWorldDistance(instance, px, py, wx, wy)
    return distance and distance > LONG_TRIP_YARDS or false
end

local function flightWorld(zgv, node)
    local world = nodeWorld[node]
    if world == nil then
        world = false
        if node.m and node.x then
            local x, y = node.x > 1 and node.x / 100 or node.x, node.y > 1 and node.y / 100 or node.y
            local wx, wy, instance = zgv.HBD:GetWorldCoordinatesFromZone(x, y, node.m)
            if wx then world = { wx = wx, wy = wy, instance = instance, x = x, y = y } end
        end
        nodeWorld[node] = world
    end
    return world
end

local function nearestFlightPoint(zgv, px, py, instance)
    local db = ns.GetDB()
    local taxi = zgv.LibTaxi
    if not (taxi and taxi.taxipoints) then return end
    local _, token = UnitClass("player")
    local limit = isLongTrip(zgv, px, py, instance) and FLIGHT_YARDS_LONG_TRIP or FLIGHT_YARDS
    local best, bestDistance, bestWorld
    for _, continent in pairs(taxi.taxipoints) do
        for _, zone in pairs(continent) do
            for _, node in ipairs(zone) do
                local usable = node.known ~= true and node.taxioperator ~= "blackcat" and (not node.class or node.class == token)
                if usable and not db.hinted["fp:" .. node.name] then
                    local world = flightWorld(zgv, node)
                    if world and world.instance == instance then
                        local distance = zgv.HBD:GetWorldDistance(instance, px, py, world.wx, world.wy)
                        if distance and distance <= limit and (not bestDistance or distance < bestDistance) then
                            best, bestDistance, bestWorld = node, distance, world
                        end
                    end
                end
            end
        end
    end
    if best then
        return {
            key = "fp:" .. best.name, map = best.m, x = bestWorld.x, y = bestWorld.y,
            heading = "New flight point nearby: " .. best.name,
            detail = ("%s, %d yd. Discover it so Zygor can fly from here."):format(best.npc or "Flight master", math.floor(bestDistance + 0.5)),
            waypoint = "Discover flight point: " .. best.name,
        }
    end
end

local function nearestDungeonQuest(zgv, px, py, instance)
    local db = ns.GetDB()
    local needed
    local best, bestEntry, bestDistance
    local extra = 0
    for _, entry in ipairs(loadDungeons(zgv)) do
        if db.dungeons[entry.name] ~= "no" and not (db.sideQuests and db.sideGuides[entry.guide.title]) then
            for _, quest in ipairs(entry.quests) do
                if not db.hinted["q:" .. quest.id] and resolve(zgv, quest) and quest.instance == instance then
                    local distance = zgv.HBD:GetWorldDistance(instance, px, py, quest.wx, quest.wy)
                    if distance and distance <= QUEST_YARDS and isSuggested(entry) and questState(zgv, quest.id) == "open" then
                        needed = needed or ns.neededLevelingQuests(zgv)
                        if not needed[quest.id] then
                            if not bestDistance or distance < bestDistance then
                                if best then extra = extra + 1 end
                                best, bestEntry, bestDistance = quest, entry, distance
                            else
                                extra = extra + 1
                            end
                        end
                    end
                end
            end
        end
    end
    if best then
        local more = extra > 0 and ("  +%d more"):format(extra) or ""
        return {
            key = "q:" .. best.id, map = best.map, x = best.x, y = best.y,
            heading = ("%s quest nearby"):format(bestEntry.name),
            detail = ("%s%s, %d yd%s"):format(best.title, best.npc and (" from " .. best.npc) or "", math.floor(bestDistance + 0.5), more),
            waypoint = ("Accept %s"):format(best.title),
        }
    end
end

local function scan()
    local db = ns.GetDB()
    local zgv = _G.ZGV
    if not zgv or not zgv.HBD or InCombatLockdown() or UnitOnTaxi("player") then
        hideHint()
        return
    end
    scanCount = scanCount + 1
    if db.offerDungeons and scanCount % OFFER_EVERY_SCANS == 1 then offerDungeon(zgv) end
    if db.guideCheck then ns.CheckGuide(zgv) end

    local px, py, instance = zgv.HBD:GetPlayerWorldPosition()
    if not px then
        hideHint()
        return
    end
    ns.UpdateSideDetour(zgv, px, py, instance)
    local hint = (db.sideQuests and ns.NearestSideStop(zgv, px, py, instance))
        or (db.hintFlights and nearestFlightPoint(zgv, px, py, instance))
        or (db.hintQuests and nearestDungeonQuest(zgv, px, py, instance))
    if hint then showHint(hint) else hideHint() end
end

-------------------------------------------------------------------------------
-- Quest log guide finder
-------------------------------------------------------------------------------
local FINDER_ICON = "Interface\\AddOns\\ZygorGuidesViewerForever\\Skins\\findinzygor"
local MAX_GUIDES_LISTED = 10
local GUIDE_ROW_H = 24
local guideIndex
local finder, guideMenu
local FINDER_POLL_SECONDS = 0.25
local TURN_IN_LABEL = "|cffffd200Turn in|r  "
local MENU_WIDTH = 400

local function partsIn(index, id, guide)
    index[id] = index[id] or {}
    index[id][guide] = index[id][guide] or { objectives = {} }
    return index[id][guide]
end

-- One quest can be accepted, worked on and turned in across different guides,
-- so remember which guide holds which part.
local function indexRawGuide(index, guide)
    if type(guide.rawdata) ~= "string" then return end
    for line in guide.rawdata:gmatch("[^\n]+") do
        local verb = line:match("^%s*(%a+)")
        if verb == "accept" or verb == "turnin" then
            local id = line:match("##(%d+)")
            if id then partsIn(index, tonumber(id), guide)[verb] = true end
        else
            for id, objective in line:gmatch("|q (%d+)/?(%d*)") do
                local parts = partsIn(index, tonumber(id), guide)
                if objective == "" then
                    parts.helper = true
                else
                    parts.objectives[tonumber(objective)] = true
                end
            end
        end
    end
end

local function indexCachedGuide(index, zgv, guide)
    local accepted, turnedIn = {}, {}
    ns.addCachePacks(accepted, zgv.Quest_Cache_Accept, guide.title)
    ns.addCachePacks(turnedIn, zgv.Quest_Cache, guide.title)
    for id in pairs(accepted) do partsIn(index, id, guide).accept = true end
    for id in pairs(turnedIn) do partsIn(index, id, guide).turnin = true end
end

local function buildGuideIndex(zgv)
    if guideIndex then return guideIndex end
    if not (zgv.registeredguides and zgv.registeredguides[1]) then return {} end
    local index = {}
    for _, guide in ipairs(zgv.registeredguides) do
        local title = guide.title or ""
        if title:find("^LEVELING") or title:find("^DUNGEONS") then
            indexRawGuide(index, guide)
        else
            indexCachedGuide(index, zgv, guide)
        end
    end
    guideIndex = index
    return index
end

-- Zygor's "|q 123/2" uses the same numbering as the quest log objectives
local function openObjectives(questID)
    local open = {}
    for i, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        if not objective.finished then open[#open + 1] = i end
    end
    return open
end

ns.resolveSpot, ns.panel, ns.paintAccent, ns.actionButton = resolve, panel, paintAccent, actionButton

local function guideRank(zgv, guide)
    if isOpenInTab(zgv, guide) then return 1 end
    if (guide.title or ""):find("^LEVELING") then return 2 end
    return 3
end

local function holdsAny(parts, open)
    for _, objective in ipairs(open) do
        if parts.objectives[objective] then return true end
    end
    return false
end

-- Hides guides of other races and the like, same as Zygor's own guide menu
local function guideApplies(guide)
    local ok, status = pcall(guide.GetStatus, guide)
    if ok and status == "INVALID" then return false end
    if not guide.condition_visible then return true end
    local checked, visible = pcall(guide.condition_visible)
    return not checked or visible == true
end

ns.guideApplies = guideApplies

local function guidesWhere(byGuide, holds)
    local found = {}
    for guide, parts in pairs(byGuide) do
        if holds(parts) and guideApplies(guide) then found[#found + 1] = guide end
    end
    return found
end

-- How many guides further along the current guide's "next" chain, nil if not on it
local function guidesAhead(zgv, target)
    local guide, ahead, seen = zgv.CurrentGuide, 0, {}
    while guide and not seen[guide] do
        if guide == target then return ahead end
        seen[guide] = true
        ahead = ahead + 1
        guide = type(guide.next) == "string" and zgv:GetGuideByTitle(guide.next) or nil
    end
end

local function stageTargets(zgv, guides, stage)
    local targets = {}
    for _, guide in ipairs(guides) do
        targets[#targets + 1] = { guide = guide, stage = stage, ahead = guidesAhead(zgv, guide) }
    end
    table.sort(targets, function(a, b)
        local aheadA, aheadB = a.ahead or math.huge, b.ahead or math.huge
        if aheadA ~= aheadB then return aheadA < aheadB end
        local rankA, rankB = guideRank(zgv, a.guide), guideRank(zgv, b.guide)
        if rankA ~= rankB then return rankA < rankB end
        return a.guide.title < b.guide.title
    end)
    return targets
end

-- The quest's route from here: what is done is behind us, so it never shows up.
-- A guide already listed under "now" also covers the turn-in unless another one does.
local function questRoute(zgv, questID)
    local byGuide = buildGuideIndex(zgv)[questID] or {}
    local open = openObjectives(questID)
    local nowGuides = {}
    if open[1] then
        nowGuides = guidesWhere(byGuide, function(parts) return holdsAny(parts, open) end)
        if not nowGuides[1] then
            nowGuides = guidesWhere(byGuide, function(parts) return parts.helper end)
        end
    end
    local listed = {}
    for _, guide in ipairs(nowGuides) do listed[guide] = true end
    local turnins = {}
    for _, guide in ipairs(guidesWhere(byGuide, function(parts) return parts.turnin end)) do
        if not listed[guide] then turnins[#turnins + 1] = guide end
    end
    local route = stageTargets(zgv, nowGuides, "now")
    for _, target in ipairs(stageTargets(zgv, turnins, "turnin")) do route[#route + 1] = target end
    return route
end

local function findStep(guide, questID, matches)
    for i, step in ipairs(guide.steps or {}) do
        for _, goal in pairs(step.goals or {}) do
            if goal.questid == questID and matches(goal) then return i end
        end
    end
end

local function turninStep(guide, questID)
    return findStep(guide, questID, function(goal) return goal.action == "turnin" end)
end

local function questStep(guide, questID, stage)
    if stage == "turnin" then return turninStep(guide, questID) end
    if stage == "accept" then
        return findStep(guide, questID, function(goal) return goal.action == "accept" end)
    end
    local open, step = {}, nil
    for _, objective in ipairs(openObjectives(questID)) do open[objective] = true end
    if next(open) then
        step = findStep(guide, questID, function(goal) return open[tonumber(goal.objnum)] end)
            or findStep(guide, questID, function(goal)
                return not goal.objnum and goal.action ~= "accept" and goal.action ~= "turnin"
            end)
    end
    return step or turninStep(guide, questID)
end

local function shortGuideName(guide)
    return (guide.title:gsub("^[^\\]+\\", ""))
end

local function loadTarget(zgv, target, questID)
    local guide = target.guide
    local openTab
    for _, tab in pairs(zgv.Tabs.Pool) do
        if tab.guide == guide then openTab = tab end
    end
    if openTab then
        openTab:ActivateGuide()
    else
        zgv.Tabs:LoadGuideToTab(guide, 1)
    end
    if zgv.CurrentGuide == guide then
        local step = questStep(guide, questID, target.stage)
        if step then zgv:FocusStep(step, true) end
    end
    ns.say("Loaded " .. shortGuideName(guide))
end

ns.loadTarget = loadTarget

local function routeName(target)
    local name = shortGuideName(target.guide)
    return target.stage == "turnin" and (TURN_IN_LABEL .. name) or name
end

local function aheadText(target)
    local ahead = target.ahead
    if not ahead then return "" end
    if ahead == 0 then return "this guide" end
    if ahead == 1 then return "next guide" end
    return "in " .. ahead .. " guides"
end

local function hideGuideMenu()
    if guideMenu then guideMenu:Hide() end
end

local function showGuideMenu(anchor, targets, questID)
    if not guideMenu then
        guideMenu = CreateFrame("Frame", "OathbreakerGuideMenu", UIParent)
        guideMenu:SetFrameStrata("TOOLTIP")
        local bg = guideMenu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
        EUI.MakeBorder(guideMenu, 1, 1, 1, 0.15)
        guideMenu.rows = {}
        tinsert(UISpecialFrames, guideMenu:GetName())
    end
    local count = math.min(#targets, MAX_GUIDES_LISTED)
    for i = 1, count do
        local row = guideMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, guideMenu)
            row:SetHeight(GUIDE_ROW_H)
            row:SetPoint("TOPLEFT", 1, -(i - 1) * GUIDE_ROW_H - 1)
            row:SetPoint("TOPRIGHT", -1, -(i - 1) * GUIDE_ROW_H - 1)
            row.hover = row:CreateTexture(nil, "BACKGROUND")
            row.hover:SetAllPoints()
            row.hover:SetColorTexture(1, 1, 1, 0.06)
            row.hover:Hide()
            row.label = ns.font(row, 12, 0.85)
            row.label:SetPoint("LEFT", 10, 0)
            row.ahead = ns.font(row, 11, 0.55)
            row.ahead:SetPoint("RIGHT", -10, 0)
            row:SetScript("OnEnter", function(self) self.hover:Show() end)
            row:SetScript("OnLeave", function(self) self.hover:Hide() end)
            guideMenu.rows[i] = row
        end
        row.label:SetText(routeName(targets[i]))
        row.ahead:SetText(aheadText(targets[i]))
        row:SetScript("OnClick", function()
            guideMenu:Hide()
            loadTarget(_G.ZGV, targets[i], questID)
        end)
        row:Show()
    end
    for i = count + 1, #guideMenu.rows do guideMenu.rows[i]:Hide() end
    guideMenu:SetSize(MENU_WIDTH, count * GUIDE_ROW_H + 2)
    guideMenu:ClearAllPoints()
    guideMenu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    guideMenu:Show()
end

local function createFinder()
    local b = CreateFrame("Button", "OathbreakerGuideFinder", UIParent)
    b:SetSize(24, 24)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints()
    b.icon:SetTexture(FINDER_ICON)
    b.badge = ns.font(b, 12, 1)
    b.badge:SetDrawLayer("OVERLAY", 7)
    b.badge:SetPoint("BOTTOMRIGHT", 5, -3)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        if #self.targets == 0 then
            GameTooltip:AddLine("No next step in Zygor")
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine("Quest route")
        for i = 1, math.min(#self.targets, MAX_GUIDES_LISTED) do
            local target = self.targets[i]
            GameTooltip:AddDoubleLine(routeName(target), aheadText(target),
                1, 1, 1, 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(#self.targets == 1 and "Click to load it" or "Click to choose", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if #self.targets == 0 then return end
        if #self.targets == 1 then
            loadTarget(_G.ZGV, self.targets[1], self.questID)
        elseif guideMenu and guideMenu:IsShown() then
            hideGuideMenu()
        else
            showGuideMenu(self, self.targets, self.questID)
        end
    end)
    b:SetScript("OnHide", hideGuideMenu)
    b:Hide()
    return b
end

local function finderParent()
    -- Newer clients keep the details one level deeper, under QuestsFrame
    local map = _G.QuestMapFrame
    local details = map and (map.QuestsFrame and map.QuestsFrame.DetailsFrame or map.DetailsFrame)
    if details and details:IsVisible() then return details, -10, -10 end
    local popup = _G.QuestLogPopupDetailFrame
    if popup and popup:IsVisible() then return popup, -30, -30 end
end

local function showFinder(questID)
    local zgv = _G.ZGV
    if not (zgv and zgv.Tabs and questID) then return end
    finder = finder or createFinder()
    local parent, x, y = finderParent()
    hideGuideMenu()
    if not (parent and ns.GetDB().guideFinder) then
        finder:Hide()
        return
    end
    local targets = questRoute(zgv, questID)
    finder.targets, finder.questID = targets, questID
    finder.icon:SetDesaturated(not targets[1])
    finder.icon:SetAlpha(targets[1] and 1 or 0.4)
    -- "+2": the very next step is two guides ahead of the one you are on
    local nextAhead = targets[1] and targets[1].ahead
    finder.badge:SetText(nextAhead and nextAhead > 0 and ("+" .. nextAhead) or "")
    finder:SetParent(parent)
    finder:SetFrameLevel(parent:GetFrameLevel() + 20)
    finder:ClearAllPoints()
    finder:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, y)
    finder:Show()
end

-- Polled instead of hooked: map addons like OpenMap open the details on their own paths.
local shownQuest, shownParent, shownObjectives, shownGuide

local function selectedQuest(parent)
    if parent == _G.QuestLogPopupDetailFrame then return parent.questID end
    local id = C_QuestLog.GetSelectedQuest()
    return id and id > 0 and id or nil
end

local function syncFinder()
    local parent = finderParent()
    local id = parent and ns.GetDB().guideFinder and selectedQuest(parent) or nil
    -- Finishing an objective can move the next step to another guide
    local objectives = id and table.concat(openObjectives(id), ",")
    local current = _G.ZGV and _G.ZGV.CurrentGuide
    if id == shownQuest and parent == shownParent and objectives == shownObjectives and current == shownGuide then return end
    shownQuest, shownParent, shownObjectives, shownGuide = id, parent, objectives, current
    if id then
        showFinder(id)
    elseif finder then
        finder:Hide()
    end
end

function ns.StartAssistant()
    local poll = CreateFrame("Frame")
    local waited = 0
    poll:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < FINDER_POLL_SECONDS then return end
        waited = 0
        ns.guarded("Guide finder", syncFinder)
    end)
    C_Timer.After(START_DELAY, function()
        C_Timer.NewTicker(SCAN_SECONDS, function() ns.guarded("Assistant", scan) end)
    end)
end

function ns.ResetAssistant()
    local db = ns.GetDB()
    wipe(db.dungeons)
    wipe(db.hinted)
    ns.ResetGuideCheck()
    wipe(askLater)
end

ns.Assistant = { Scan = scan, ParseQuestGuide = parseQuestGuide, ShowFinder = showFinder, QuestRoute = questRoute, QuestStep = questStep, SyncFinder = syncFinder, Reset = function() dungeons = nil end }
