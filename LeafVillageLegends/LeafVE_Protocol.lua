-- LeafVE_Protocol.lua
-- Single source of truth for addon versioning and post-wipe quarantine logic.
-- Fully Lua 5.0 / WoW 1.12 compatible.

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local LEAFVE_ADDON_VERSION = "11.8"   -- must match ## Version in .toc
local LEAFVE_PROTOCOL      = 2        -- integer; bump when wire format changes
local LEAFVE_MIN_PROTOCOL  = 2        -- reject any incoming msg with protocol < this

-- Expose protocol number as a global so other addon files can reference it
-- without depending on the local above.
_G.LEAFVE_PROTOCOL = LEAFVE_PROTOCOL

-- ---------------------------------------------------------------------------
-- Post-wipe quarantine state
-- After a wipe, we ignore merged-point updates from old clients for 10 minutes
-- (or until the session ends). Stored as a wall-clock timestamp (GetTime()).
-- ---------------------------------------------------------------------------
LeafVE_WipeQuarantineUntil = 0   -- global so LeafVillageLegends.lua can read it

-- ---------------------------------------------------------------------------
-- LeafVE_BuildMessage(msgType, payload)
-- Wraps a payload string with protocol metadata.
-- Returns: "P:2|V:11.8|<msgType>:<payload>"
-- payload may be "" for messages with no body.
-- ---------------------------------------------------------------------------
function LeafVE_BuildMessage(msgType, payload)
    return "P:" .. LEAFVE_PROTOCOL .. "|V:" .. LEAFVE_ADDON_VERSION .. "|" .. msgType .. ":" .. payload
end

-- ---------------------------------------------------------------------------
-- LeafVE_ParseMessage(rawMsg, sender)
-- Parses a raw addon message string.
-- Returns nil if:
--   - The message does not start with "P:" (legacy/unversioned — protocol 0)
--   - The protocol field is < LEAFVE_MIN_PROTOCOL
-- Otherwise returns:
--   { protocol=<int>, version=<string>, msgType=<string>, payload=<string> }
-- ---------------------------------------------------------------------------
function LeafVE_ParseMessage(rawMsg, sender)
    if not rawMsg or string.sub(rawMsg, 1, 2) ~= "P:" then
        -- Legacy unversioned message — treat as protocol 0 and drop
        return nil
    end

    -- Find end of "P:<n>" field (next "|")
    local pipe1 = string.find(rawMsg, "|", 3)
    if not pipe1 then return nil end
    local protocol = tonumber(string.sub(rawMsg, 3, pipe1 - 1))
    if not protocol then return nil end

    -- Check minimum protocol
    if protocol < LEAFVE_MIN_PROTOCOL then
        local senderStr = sender or "unknown"
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff4444[LeafVE]|r Ignored message from " .. senderStr
            .. ": protocol " .. protocol .. " < minimum " .. LEAFVE_MIN_PROTOCOL
            .. ". Ask them to update."
        )
        return nil
    end

    -- Find end of "V:<version>" field (next "|")
    local vStart = pipe1 + 1
    if string.sub(rawMsg, vStart, vStart + 1) ~= "V:" then return nil end
    local pipe2 = string.find(rawMsg, "|", vStart + 2)
    if not pipe2 then return nil end
    local version = string.sub(rawMsg, vStart + 2, pipe2 - 1)

    -- Remainder is "<msgType>:<payload>"
    local rest = string.sub(rawMsg, pipe2 + 1)
    local colonPos = string.find(rest, ":")
    if not colonPos then return nil end
    local msgType = string.sub(rest, 1, colonPos - 1)
    local payload = string.sub(rest, colonPos + 1)

    return { protocol = protocol, version = version, msgType = msgType, payload = payload }
end

-- ---------------------------------------------------------------------------
-- LeafVE_IsQuarantineActive()
-- Returns true when the post-wipe quarantine window is still open.
-- ---------------------------------------------------------------------------
function LeafVE_IsQuarantineActive()
    return GetTime() < LeafVE_WipeQuarantineUntil
end

-- ---------------------------------------------------------------------------
-- LeafVE_ActivateWipeQuarantine()
-- Starts a 10-minute quarantine window during which stale point syncs are ignored.
-- ---------------------------------------------------------------------------
function LeafVE_ActivateWipeQuarantine()
    LeafVE_WipeQuarantineUntil = GetTime() + 600
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff8000[LeafVE]|r Wipe quarantine active for 10 minutes — old-client sync ignored."
    )
end
