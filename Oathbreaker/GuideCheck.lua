-- Guide check: when you have outleveled your leveling guide, compares what you would
-- skip with what the following guides still need from it.
local ADDON, ns = ...

local LEVELS_OVER = 2
local LOOKAHEAD_GUIDES = 3
local MAX_TODO = 5
local MAX_QUESTS_PER_UNLOCK = 3
local CHECK_EVERY_SCANS = 30
local WINDOW_WIDTH, WINDOW_BASE_H, ROW_H = 470, 142, 24
local ACTION_COLORS = {
    ["Accept"] = "|cff5fd38d", ["Do"] = "|cff5fd38d", ["Finish"] = "|cffffd200", ["Turn in"] = "|cffffd200",
}

local window
local scans, lastKey = 0, nil
local later, toldToFinish = {}, {}

-------------------------------------------------------------------------------
-- Which guides are involved?
-------------------------------------------------------------------------------
local function endLevel(guide)
    return tonumber((guide.title or ""):match("%(%d+%-(%d+)%)"))
end

local function isOutleveled(guide, level)
    local last = endLevel(guide)
    return last and level >= last + LEVELS_OVER or false
end

local function shortName(guide)
    return (guide.title:gsub("^[^\\]+\\", ""))
end

local function nextGuide(zgv, guide)
    return type(guide.next) == "string" and zgv:GetGuideByTitle(guide.next) or nil
end

-- Target: the first guide of the chain you have not outleveled yet
local function planRoute(zgv, level)
    local current = zgv.CurrentGuide
    local skipped, future, seen = { current }, {}, { [current] = true }
    local guide = nextGuide(zgv, current)
    while guide and not seen[guide] and isOutleveled(guide, level) do
        seen[guide] = true
        skipped[#skipped + 1] = guide
        guide = nextGuide(zgv, guide)
    end
    local target = guide
    while guide and not seen[guide] and #future < LOOKAHEAD_GUIDES do
        seen[guide] = true
        future[#future + 1] = guide
        guide = nextGuide(zgv, guide)
    end
    if target and endLevel(target) then return target, skipped, future end
end

-------------------------------------------------------------------------------
-- Quest facts
-------------------------------------------------------------------------------
local function isDone(id)
    return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
end

local function inLog(id)
    local index = C_QuestLog.GetLogIndexForQuestID(id)
    return index and index > 0 or false
end

local function isReady(id)
    return inLog(id) and (C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id)) and true or false
end

local function collectStops(zgv, guides)
    local accepts, turnins, list = {}, {}, {}
    for guideOrder, guide in ipairs(guides) do
        for stopOrder, stop in ipairs(ns.StopsOf(zgv, guide)) do
            if ns.StopFitsCharacter(stop) then
                local map = stop.verb == "accept" and accepts or turnins
                if not map[stop.id] then
                    map[stop.id] = { stop = stop, guide = guide, order = guideOrder * 100000 + stopOrder }
                    if stop.verb == "accept" then list[#list + 1] = stop.id end
                end
            end
        end
    end
    return accepts, turnins, list
end

-- QuestieDB says exactly which prerequisites are all-of and which any-of, so it goes
-- first. Zygor's own chains are the fallback for people without it.
local function prerequisites(zgv, id, stop)
    local all, any = {}, {}
    local questie = ns.questiePrereqData(id)
    if questie then
        for _, prereq in ipairs(questie.all) do all[#all + 1] = prereq end
        for _, prereq in ipairs(questie.any) do any[#any + 1] = prereq end
    else
        local chain = zgv.Chains and zgv.Chains[id]
        local crumbs = zgv.ChainsBreadcrumbs or {}
        if type(chain) == "number" and not crumbs[chain] then
            all[#all + 1] = chain
        elseif type(chain) == "table" then
            -- Zygor's format: { "AND", id, id } needs all, anything else needs one
            local needsAll = chain[1] == "AND"
            for _, value in pairs(chain) do
                local prereq = tonumber(value)
                if prereq and not (needsAll and crumbs[prereq]) then
                    local list = needsAll and all or any
                    list[#list + 1] = prereq
                end
            end
        end
    end
    for _, prereq in ipairs(stop and stop.after or {}) do all[#all + 1] = prereq end
    return all, any
end

-------------------------------------------------------------------------------
-- What would be lost?
-------------------------------------------------------------------------------
local function walkPrereqs(zgv, facts, id, chain, seen)
    if seen[id] or isDone(id) then return end
    seen[id] = true
    local skippedEntry = facts.isSkippedOnly(id) and facts.skippedAccepts[id]
    if skippedEntry then chain[#chain + 1] = id end
    if inLog(id) then return end
    local entry = skippedEntry or facts.futureAccepts[id]
    if not entry then return end
    local all, any = prerequisites(zgv, id, entry.stop)
    for _, prereq in ipairs(all) do walkPrereqs(zgv, facts, prereq, chain, seen) end
    local satisfied = not any[1]
    for _, prereq in ipairs(any) do
        if isDone(prereq) or inLog(prereq) then satisfied = true end
    end
    if not satisfied then
        for _, prereq in ipairs(any) do
            if facts.isSkippedOnly(prereq) and not (zgv.ChainsBreadcrumbs or {})[prereq] then
                walkPrereqs(zgv, facts, prereq, chain, seen)
                break
            end
        end
    end
end

local function chainCost(chain)
    local cost = 0
    for _, id in ipairs(chain) do
        if not isReady(id) then cost = cost + 1 end
    end
    return cost
end

local function bestReach(chain, neededBy)
    local reach = 1
    for _, id in ipairs(chain) do reach = math.max(reach, neededBy[id].count) end
    return reach
end

local function noteNeed(neededBy, chain, questID)
    for _, id in ipairs(chain) do
        neededBy[id] = neededBy[id] or { count = 0, quests = {} }
        if not neededBy[id].quests[questID] then
            neededBy[id].quests[questID] = true
            neededBy[id].count = neededBy[id].count + 1
        end
    end
end

local function actionFor(id, isLaterTurnin, facts)
    if isReady(id) then return "Turn in", "turnin" end
    if inLog(id) then return "Finish", "now" end
    if isLaterTurnin and facts.neededAsPrereq[id] == nil then return "Accept", "accept" end
    return "Do", "accept"
end

local function analyze(zgv, skipped, future)
    local skippedAccepts = collectStops(zgv, skipped)
    local futureAccepts, futureTurnins, futureList = collectStops(zgv, future)
    local facts = { skippedAccepts = skippedAccepts, futureAccepts = futureAccepts, neededAsPrereq = {} }
    function facts.isSkippedOnly(id)
        return skippedAccepts[id] ~= nil and futureAccepts[id] == nil
    end

    local chains, neededBy, laterTurnins = {}, {}, {}
    for _, questID in ipairs(futureList) do
        if not isDone(questID) and not inLog(questID) then
            local chain = {}
            walkPrereqs(zgv, facts, questID, chain, {})
            if chain[1] then
                chains[#chains + 1] = chain
                noteNeed(neededBy, chain, questID)
                for _, id in ipairs(chain) do facts.neededAsPrereq[id] = true end
            end
        end
    end
    -- Accepted in a skipped guide, turned in further on
    for id in pairs(futureTurnins) do
        if facts.isSkippedOnly(id) and not isDone(id) and not inLog(id) then
            local chain = {}
            walkPrereqs(zgv, facts, id, chain, {})
            if chain[1] then
                laterTurnins[id] = true
                chains[#chains + 1] = chain
                noteNeed(neededBy, chain, id)
            end
        end
    end

    local kept, dropped = {}, 0
    for _, chain in ipairs(chains) do
        if chainCost(chain) <= MAX_QUESTS_PER_UNLOCK * bestReach(chain, neededBy) then
            for _, id in ipairs(chain) do kept[id] = true end
        else
            dropped = dropped + 1
        end
    end

    local todo = {}
    for id in pairs(kept) do
        local entry = skippedAccepts[id]
        local action, stage = actionFor(id, laterTurnins[id], facts)
        todo[#todo + 1] = {
            id = id, title = entry.stop.title, guide = entry.guide, order = entry.order,
            action = action, stage = stage, count = neededBy[id].count,
            onlyLater = laterTurnins[id] and neededBy[id].count == 1,
        }
    end
    table.sort(todo, function(a, b) return a.order < b.order end)
    return todo, dropped
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local function usefulness(entry)
    if entry.onlyLater then return "turned in later" end
    return ("needed for %d %s"):format(entry.count, entry.count == 1 and "quest" or "quests")
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 1, -(62 + index * ROW_H))
    row:SetPoint("TOPRIGHT", -1, -(62 + index * ROW_H))
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.label = ns.font(row, 12, 0.9)
    row.label:SetPoint("LEFT", 16, 0)
    row.note = ns.font(row, 11, 0.5)
    row.note:SetPoint("RIGHT", -16, 0)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self)
        window:Hide()
        ns.loadTarget(_G.ZGV, { guide = self.entry.guide, stage = self.entry.stage }, self.entry.id)
    end)
    return row
end

local function createWindow()
    local f = ns.panel("OathbreakerGuideCheck", WINDOW_WIDTH, WINDOW_BASE_H, "DIALOG")
    f:SetPoint("CENTER", 0, 60)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.icon:SetSize(34, 34)
    f.icon:SetPoint("TOPLEFT", 16, -16)
    f.heading = ns.font(f, 16)
    f.heading:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -1)
    f.summary = ns.font(f, 11, 0.5)
    f.summary:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 12, 2)
    f.note = ns.font(f, 12, 0.8)
    f.note:SetPoint("TOPLEFT", 16, -64)
    f.note:SetWidth(WINDOW_WIDTH - 32)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    f.switch = ns.actionButton(f, "Switch guide", 130, true)
    f.switch:SetPoint("BOTTOMRIGHT", -16, 14)
    f.later = ns.actionButton(f, "Later", 90)
    f.later:SetPoint("RIGHT", f.switch, "LEFT", -8, 0)
    f.stay = ns.actionButton(f, "Stay here", 90)
    f.stay:SetPoint("RIGHT", f.later, "LEFT", -8, 0)
    f.switch:SetScript("OnClick", function()
        f:Hide()
        _G.ZGV.Tabs:LoadGuideToTab(f.target, 1)
        ns.say("Loaded " .. shortName(f.target))
    end)
    local function dismiss() f:Hide() end
    f.later:SetScript("OnClick", dismiss)
    f.closeButton:SetScript("OnClick", dismiss)
    f.stay:SetScript("OnClick", function()
        ns.GetDB().guideCheckStay[f.current.title] = true
        f:Hide()
    end)
    f:Hide()
    return f
end

local function noteText(todo, dropped)
    local text = todo[1] and "Do these first, the next guides depend on them. Click one to go there."
        or "Nothing you would skip is needed later."
    if dropped > 0 then
        text = text .. (" %d long %s skipped, not worth it."):format(dropped, dropped == 1 and "chain" or "chains")
    end
    return text
end

local function showWindow(zgv, level, target, todo, dropped, manual)
    window = window or createWindow()
    window.current, window.target = zgv.CurrentGuide, target
    window.heading:SetText(manual and "Guide check" or "You have outleveled this guide")
    window.summary:SetText(("Level %d in %s. %s: %s"):format(level, shortName(zgv.CurrentGuide), manual and "Next" or "Better", shortName(target)))
    window.note:SetText(noteText(todo, dropped))
    for index, entry in ipairs(todo) do
        window.rows[index] = window.rows[index] or createRow(window, index)
        local row = window.rows[index]
        row.entry = entry
        row.label:SetText(("%s%s|r  %s"):format(ACTION_COLORS[entry.action], entry.action, entry.title))
        row.note:SetText(usefulness(entry))
        row:Show()
    end
    for index = #todo + 1, #window.rows do window.rows[index]:Hide() end
    window:SetHeight(WINDOW_BASE_H + #todo * ROW_H)
    ns.paintAccent(window)
    window.switch.Repaint()
    window:Show()
end

-------------------------------------------------------------------------------
-- Check
-------------------------------------------------------------------------------
function ns.CheckGuide(zgv)
    local guide, level = zgv.CurrentGuide, UnitLevel("player")
    scans = scans + 1
    if not (guide and (guide.title or ""):find("^LEVELING") and isOutleveled(guide, level)) then return end
    if ns.GetDB().guideCheckStay[guide.title] or (window and window:IsShown()) then return end

    local key = guide.title .. ":" .. level
    if key == lastKey and scans % CHECK_EVERY_SCANS ~= 0 then return end
    lastKey = key

    local target, skipped, future = planRoute(zgv, level)
    if not target then return end
    local todo, dropped = analyze(zgv, skipped, future)
    if #todo > MAX_TODO then
        if not toldToFinish[guide.title] then
            toldToFinish[guide.title] = true
            ns.say(("Keep going with %s: %d of its quests are still needed by the next guides."):format(shortName(guide), #todo))
        end
        return
    end
    -- "Later" holds until you level up or finish everything on the list
    local answer = key .. ":" .. (todo[1] and "open" or "clear")
    if later[answer] then return end
    later[answer] = true
    showWindow(zgv, level, target, todo, dropped)
end

-- Button: same comparison, but whatever your level, "Stay here" or "Later", and always an answer
function ns.CheckGuideNow(zgv)
    local guide, level = zgv and zgv.CurrentGuide, UnitLevel("player")
    if not (guide and (guide.title or ""):find("^LEVELING")) then
        ns.say("Open a leveling guide first, then run the guide check.")
        return
    end
    local target, skipped, future = planRoute(zgv, level)
    if not target then
        ns.say("There is no following guide to compare with.")
        return
    end
    local todo, dropped = analyze(zgv, skipped, future)
    showWindow(zgv, level, target, todo, dropped, true)
end

function ns.ResetGuideCheck()
    wipe(ns.GetDB().guideCheckStay)
    wipe(later)
    wipe(toldToFinish)
    lastKey = nil
end

ns.GuideCheck = { PlanRoute = planRoute, Analyze = analyze }
