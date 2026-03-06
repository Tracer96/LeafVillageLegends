-- LeafVE_FullWipe.lua
-- Versioned full-wipe system for Leaf Village Legends (WoW 1.12 / Lua 5.0)

-- ACCEPTANCE TESTS:
-- [Admin wipe]
--   1. LeafVE_AdminDoFullWipe() is called by an admin.
--   2. LeafVE_GlobalDB.fullWipeVersion increments by 1.
--   3. leaderboardAllTime/Weekly/Seasonal have 0 entries.
--   4. Current character: points={L=0,G=0,S=0}, pointHistory={}, badges={}, lastWipeApplied == fullWipeVersion.
-- [Offline character login]
--   5. Character logs in with lastWipeApplied < fullWipeVersion.
--   6. ApplyPendingFullWipeIfNeeded() detects pv < gv and wipes the character's data.
--   7. lastWipeApplied is set to fullWipeVersion.
-- [UI settings preserved]
--   8. LeafVE_DB.options is NOT cleared during any wipe.

-- ---------------------------------------------------------------------------
-- A) Helper: clear a table in-place (Lua 5.0 compatible; no table.wipe)
-- ---------------------------------------------------------------------------
local function ClearTableInPlace(t)
    if type(t) ~= "table" then return end
    for k in pairs(t) do
        t[k] = nil
    end
end

-- ---------------------------------------------------------------------------
-- B) Quarantine helpers
-- After a full wipe, incoming SYNC_POINTS messages from clients that haven't
-- received the wipe broadcast yet are dropped for QUARANTINE_DURATION seconds.
-- ---------------------------------------------------------------------------
local QUARANTINE_DURATION = 30  -- seconds to block stale sync messages
local quarantineExpiry = 0      -- GetTime() value when quarantine ends

function LeafVE_ActivateWipeQuarantine()
    quarantineExpiry = GetTime() + QUARANTINE_DURATION
end

function LeafVE_IsQuarantineActive()
    return GetTime() < quarantineExpiry
end

-- ---------------------------------------------------------------------------
-- C) EnsureDBDefaults()
-- Called on ADDON_LOADED / VARIABLES_LOADED to initialise saved-variable tables.
-- Uses `or {}` so existing data is never overwritten.
-- ---------------------------------------------------------------------------
function EnsureDBDefaults()
    LeafVE_DB = LeafVE_DB or {}
    LeafVE_GlobalDB = LeafVE_GlobalDB or {}

    -- Per-character defaults
    LeafVE_DB.points        = LeafVE_DB.points        or { L = 0, G = 0, S = 0 }
    LeafVE_DB.pointHistory  = LeafVE_DB.pointHistory  or {}
    LeafVE_DB.activityLog   = LeafVE_DB.activityLog   or {}
    LeafVE_DB.badges        = LeafVE_DB.badges        or {}
    LeafVE_DB.cooldowns     = LeafVE_DB.cooldowns     or {}
    LeafVE_DB.lastAwardTimes = LeafVE_DB.lastAwardTimes or {}
    LeafVE_DB.altLinks      = LeafVE_DB.altLinks      or {}
    LeafVE_DB.syncCache     = LeafVE_DB.syncCache     or {}
    LeafVE_DB.options       = LeafVE_DB.options       or {}  -- UI settings; never wiped
    LeafVE_DB.lastWipeApplied = LeafVE_DB.lastWipeApplied or 0

    -- Global defaults
    LeafVE_GlobalDB.leaderboardAllTime  = LeafVE_GlobalDB.leaderboardAllTime  or {}
    LeafVE_GlobalDB.leaderboardWeekly   = LeafVE_GlobalDB.leaderboardWeekly   or {}
    LeafVE_GlobalDB.leaderboardSeasonal = LeafVE_GlobalDB.leaderboardSeasonal or {}
    LeafVE_GlobalDB.mergedMemberData    = LeafVE_GlobalDB.mergedMemberData    or {}
    LeafVE_GlobalDB.syncCache           = LeafVE_GlobalDB.syncCache           or {}
    LeafVE_GlobalDB.fullWipeVersion     = LeafVE_GlobalDB.fullWipeVersion     or 0
    LeafVE_GlobalDB.lastWipeTimestamp   = LeafVE_GlobalDB.lastWipeTimestamp   or 0
    LeafVE_GlobalDB.wipeProtocolVersion = LeafVE_GlobalDB.wipeProtocolVersion or 0
end

-- ---------------------------------------------------------------------------
-- D) ApplyPendingFullWipeIfNeeded()
-- On login, compares this character's lastWipeApplied against the global
-- fullWipeVersion.  If behind, wipes all point-related data in-place.
-- ---------------------------------------------------------------------------
function ApplyPendingFullWipeIfNeeded()
    local gv = LeafVE_GlobalDB.fullWipeVersion or 0
    local pv = LeafVE_DB.lastWipeApplied       or 0

    if pv < gv then
        -- Wipe point-related data in-place (never reassign the table references)
        ClearTableInPlace(LeafVE_DB.points)
        LeafVE_DB.points.L = 0
        LeafVE_DB.points.G = 0
        LeafVE_DB.points.S = 0

        ClearTableInPlace(LeafVE_DB.pointHistory)
        ClearTableInPlace(LeafVE_DB.activityLog)
        ClearTableInPlace(LeafVE_DB.badges)
        ClearTableInPlace(LeafVE_DB.cooldowns)
        ClearTableInPlace(LeafVE_DB.lastAwardTimes)
        ClearTableInPlace(LeafVE_DB.altLinks)
        ClearTableInPlace(LeafVE_DB.syncCache)

        -- Stamp this character as up-to-date
        LeafVE_DB.lastWipeApplied = gv

        -- DO NOT touch LeafVE_DB.options (UI settings preserved)

        -- Refresh UI + local leaderboard view if the functions exist
        if LeafVE_RefreshUI then
            LeafVE_RefreshUI()
        end
        if LeafVE_RebuildLeaderboard then
            LeafVE_RebuildLeaderboard()
        end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff00[LeafVE]|r Full wipe applied (v" .. gv .. "). Points/history/badges cleared."
        )
    end
end

-- ---------------------------------------------------------------------------
-- E) LeafVE_AdminDoFullWipe()
-- Admin action: increment the global wipe version, clear global tables in-place,
-- apply the wipe to the current character, then broadcast to online members.
-- ---------------------------------------------------------------------------
function LeafVE_AdminDoFullWipe()
    -- 1. Increment the global wipe version
    LeafVE_GlobalDB.fullWipeVersion = (LeafVE_GlobalDB.fullWipeVersion or 0) + 1
    local newVersion = LeafVE_GlobalDB.fullWipeVersion

    -- 2. Clear GlobalDB synced data in-place
    ClearTableInPlace(LeafVE_GlobalDB.leaderboardAllTime)
    ClearTableInPlace(LeafVE_GlobalDB.leaderboardWeekly)
    ClearTableInPlace(LeafVE_GlobalDB.leaderboardSeasonal)
    ClearTableInPlace(LeafVE_GlobalDB.mergedMemberData)
    ClearTableInPlace(LeafVE_GlobalDB.syncCache)

    -- 3. Apply the wipe immediately to the current character
    ApplyPendingFullWipeIfNeeded()

    -- 4. Record wipe metadata and activate quarantine
    -- NOTE: WoW 1.12 / Lua 5.0 does not have time(); use GetTime() for uptime seconds.
    LeafVE_GlobalDB.lastWipeTimestamp   = GetTime()
    LeafVE_GlobalDB.wipeProtocolVersion = 1  -- static protocol version for this wipe system
    LeafVE_ActivateWipeQuarantine()

    -- 5. Broadcast to online guild/raid/party members
    local msg = "FULL_WIPE_VERSION:" .. tostring(newVersion)
    local channel = nil
    if IsInGuild and IsInGuild() then
        channel = "GUILD"
    elseif GetNumRaidMembers and GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        channel = "PARTY"
    end
    if channel then
        SendAddonMessage("LeafVE", msg, channel)
    end

    -- 6. Confirmation output
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff8000[LeafVE ADMIN]|r Full wipe executed. fullWipeVersion=" .. newVersion
    )
    local lbCount = 0
    for _ in pairs(LeafVE_GlobalDB.leaderboardAllTime) do lbCount = lbCount + 1 end
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff8000[LeafVE DEBUG]|r leaderboardAllTime entries after wipe: " .. lbCount
    )
end

-- ---------------------------------------------------------------------------
-- F) LeafVE_OnAddonMessage(prefix, msg, channel, sender)
-- Handles incoming CHAT_MSG_ADDON events so online members wipe immediately
-- when an admin broadcasts a new wipe version.
-- ---------------------------------------------------------------------------
function LeafVE_OnAddonMessage(prefix, msg, channel, sender)
    -- Simple prefix-based parse: "FULL_WIPE_VERSION:<n>"
    if string.sub(msg, 1, 19) == "FULL_WIPE_VERSION:" then
        local newVersion = tonumber(string.sub(msg, 20))
        if newVersion and newVersion > (LeafVE_GlobalDB.fullWipeVersion or 0) then
            LeafVE_GlobalDB.fullWipeVersion = newVersion
            LeafVE_ActivateWipeQuarantine()
            ApplyPendingFullWipeIfNeeded()
        end
        return
    end

    -- Quarantine gate: drop SYNC_POINTS from stale clients shortly after a wipe
    if string.sub(msg, 1, 11) == "SYNC_POINTS" then
        if LeafVE_IsQuarantineActive() then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff8000[LeafVE]|r Quarantine: ignoring SYNC_POINTS from " .. (sender or "unknown")
            )
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- G) Event frame wiring (WoW 1.12 / Lua 5.0 style: global event + arg1..arg4)
-- ---------------------------------------------------------------------------
local LeafVE_WipeFrame = CreateFrame("Frame", "LeafVE_WipeFrame")
LeafVE_WipeFrame:RegisterEvent("VARIABLES_LOADED")
LeafVE_WipeFrame:RegisterEvent("CHAT_MSG_ADDON")

LeafVE_WipeFrame:SetScript("OnEvent", function()
    -- In WoW 1.12 Lua 5.0 event args are globals: event, arg1, arg2, arg3, arg4
    if event == "VARIABLES_LOADED" then
        EnsureDBDefaults()
        ApplyPendingFullWipeIfNeeded()
    elseif event == "CHAT_MSG_ADDON" then
        -- arg1=prefix, arg2=message, arg3=channel, arg4=sender
        if arg1 == "LeafVE" then
            LeafVE_OnAddonMessage(arg1, arg2, arg3, arg4)
        end
    end
end)