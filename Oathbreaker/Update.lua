-- Update notice: addons cannot reach the internet, so everyone running Oathbreaker
-- tells the others which version they have, through addon messages (guild, group and
-- a hidden channel). Whoever hears a newer version than their own gets a window with
-- the download link. Whoever hears an older one answers with their version.
local ADDON, ns = ...

local PREFIX, CHANNEL = "Oathbreaker", "OathbreakerSync"
local RELEASE_URL = "https://github.com/Zmash/Oathbreaker/releases/latest"
local JOIN_DELAY, ANNOUNCE_DELAY, RESEND_SECONDS = 10, 5, 60

local mine, window
local shownFor, pendingVersion
local repliedTo, lastSent = {}, 0

-------------------------------------------------------------------------------
-- Versions
-------------------------------------------------------------------------------
local function parse(version)
    local a, b, c = tostring(version or ""):match("^(%d+)%.(%d+)%.?(%d*)$")
    if a then return { tonumber(a), tonumber(b), tonumber(c) or 0 } end
end

local function isNewer(a, b)
    local x, y = parse(a), parse(b)
    if not (x and y) then return false end
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

local function ownVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return get and get(ADDON, "Version") or nil
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local function createWindow()
    local f = ns.panel("OathbreakerUpdate", 440, 190, "DIALOG")
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f.icon:SetSize(34, 34)
    f.icon:SetPoint("TOPLEFT", 16, -16)
    f.heading = ns.font(f, 16)
    f.heading:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -1)
    f.heading:SetText("New Oathbreaker version")
    f.summary = ns.font(f, 11, 0.5)
    f.summary:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 12, 2)
    f.note = ns.font(f, 12, 0.8)
    f.note:SetPoint("TOPLEFT", 16, -64)
    f.note:SetWidth(408)
    f.note:SetJustifyH("LEFT")
    f.note:SetText("Copy the link (Ctrl+C), open it in your browser and download the ZIP. Extract it into your AddOns folder, then /reload.")

    f.link = CreateFrame("EditBox", nil, f)
    f.link:SetSize(408, 24)
    f.link:SetPoint("TOPLEFT", 16, -114)
    f.link:SetAutoFocus(false)
    f.link:SetFontObject(ChatFontNormal)
    f.link:SetTextInsets(8, 8, 0, 0)
    local bg = f.link:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.04, 0.8)
    f.link:SetText(RELEASE_URL)
    f.link:SetScript("OnTextChanged", function(self) if self:GetText() ~= RELEASE_URL then self:SetText(RELEASE_URL) end end)
    f.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f.skip = ns.actionButton(f, "Skip this version", 140)
    f.skip:SetPoint("BOTTOMRIGHT", -16, 14)
    f.later = ns.actionButton(f, "Later", 90, true)
    f.later:SetPoint("RIGHT", f.skip, "LEFT", -8, 0)
    local function dismiss() f:Hide() end
    f.later:SetScript("OnClick", dismiss)
    f.closeButton:SetScript("OnClick", dismiss)
    f.skip:SetScript("OnClick", function()
        ns.GetDB().updateIgnored = f.version
        f:Hide()
    end)
    f:Hide()
    return f
end

local function show(version)
    window = window or createWindow()
    window.version = version
    window.summary:SetText(("Version %s is out, you have %s"):format(version, mine))
    ns.paintAccent(window)
    window.later.Repaint()
    window.skip.Repaint()
    window:Show()
    window.link:SetFocus()
    window.link:HighlightText()
end

local function notify(version)
    local db = ns.GetDB()
    if not db.updateNotice or db.updateIgnored == version or shownFor == version then return end
    if InCombatLockdown() then
        pendingVersion = version
        return
    end
    shownFor, pendingVersion = version, nil
    show(version)
end

-------------------------------------------------------------------------------
-- Messages
-------------------------------------------------------------------------------
local function send(text, channel, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel, target)
    end
end

local function broadcast(force)
    if not mine or not ns.GetDB().updateNotice then return end
    local now = GetTime()
    if not force and now - lastSent < RESEND_SECONDS then return end
    lastSent = now
    local text = "V:" .. mine
    if IsInGuild() then send(text, "GUILD") end
    if IsInRaid() then
        send(text, "RAID")
    elseif IsInGroup() then
        send(text, IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY")
    end
    local id = GetChannelName and GetChannelName(CHANNEL)
    if id and id > 0 then send(text, "CHANNEL", id) end
end

local function onMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or not mine then return end
    local theirs = tostring(text):match("^V:([%d%.]+)$")
    if not theirs then return end
    local name = Ambiguate and Ambiguate(sender, "none") or sender
    if name == UnitName("player") then return end
    if isNewer(theirs, mine) then
        notify(theirs)
    elseif isNewer(mine, theirs) and not repliedTo[name] then
        repliedTo[name] = true
        send("V:" .. mine, "WHISPER", sender)
    end
end

-------------------------------------------------------------------------------
-- Hidden channel: joined quietly and kept out of every chat window
-------------------------------------------------------------------------------
local function joinChannel()
    if not (ns.GetDB().updateNotice and JoinTemporaryChannel) then return end
    pcall(JoinTemporaryChannel, CHANNEL)
    if ChatFrame_RemoveChannel then
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            local chatFrame = _G["ChatFrame" .. i]
            if chatFrame then pcall(ChatFrame_RemoveChannel, chatFrame, CHANNEL) end
        end
    end
end

local function leaveChannel()
    if LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", function(_, _, _, _, _, channelName)
        return type(channelName) == "string" and channelName:find(CHANNEL, 1, true) ~= nil
    end)
end

-- Called when the setting is switched
function ns.UpdateNoticeChanged(on)
    if on then
        joinChannel()
        C_Timer.After(ANNOUNCE_DELAY, function() broadcast(true) end)
    else
        leaveChannel()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        mine = ownVersion()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        C_Timer.After(JOIN_DELAY, function()
            joinChannel()
            C_Timer.After(ANNOUNCE_DELAY, function() broadcast(true) end)
        end)
    elseif event == "CHAT_MSG_ADDON" then
        ns.guarded("update notice", onMessage, ...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        broadcast()
    elseif event == "PLAYER_REGEN_ENABLED" and pendingVersion then
        notify(pendingVersion)
    end
end)

ns.Update = { Url = RELEASE_URL, IsNewer = isNewer, OnMessage = onMessage, Broadcast = broadcast, SetOwnVersion = function(v) mine = v end }
