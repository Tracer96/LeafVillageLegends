local LeafAlliance = {}
_G.LeafAlliance = LeafAlliance

LeafAlliance.version = "1.0.1"
LeafAlliance.channelName = "Leaf"
LeafAlliance.channelPassword = "Leafbiz"
LeafAlliance.displayLabel = "Leaf Alliance"
LeafAlliance.channelColor = { 0.45, 0.80, 1.00 }
LeafAlliance.hiddenPrefix = "~LVA1~"
LeafAlliance.protocolFieldSep = "^"
LeafAlliance.guildRosterCacheDuration = 20
LeafAlliance.guildRosterRequestCooldown = 10
LeafAlliance.syncChunkSize = 180
LeafAlliance.syncBroadcastCooldown = 12
LeafAlliance.syncHeartbeatInterval = 60
LeafAlliance.syncRequestCooldown = 20
LeafAlliance.remoteGuildTimeout = 180
LeafAlliance.autoJoinRetryInterval = 15

LeafAlliance.guildRosterCache = {}
LeafAlliance.guildRosterCacheTime = 0
LeafAlliance.guildRosterRequestAt = 0
LeafAlliance.remoteGuilds = {}
LeafAlliance.pendingChunks = {}
LeafAlliance.scheduledTasks = {}
LeafAlliance.lastBroadcastAt = 0
LeafAlliance.lastHeartbeatAt = 0
LeafAlliance.lastSyncRequestAt = 0
LeafAlliance.panelRows = {}

local function Now()
  if type(GetTime) == "function" then
    return GetTime()
  end
  return 0
end

local function Lower(text)
  if text == nil then
    return ""
  end
  return string.lower(tostring(text))
end

local function Trim(text)
  text = tostring(text or "")
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  return text
end

local function ShortName(name)
  name = Trim(name)
  if name == "" then
    return nil
  end
  local dash = string.find(name, "-", 1, true)
  if dash and dash > 1 then
    return string.sub(name, 1, dash - 1)
  end
  return name
end

local function Split(text, delimiter)
  local parts = {}
  local startPos = 1
  local delimLength = string.len(delimiter)
  if delimiter == "" then
    table.insert(parts, text)
    return parts
  end
  while true do
    local delimPos = string.find(text, delimiter, startPos, true)
    if not delimPos then
      table.insert(parts, string.sub(text, startPos))
      break
    end
    table.insert(parts, string.sub(text, startPos, delimPos - 1))
    startPos = delimPos + delimLength
  end
  return parts
end

local function EscapeField(text)
  text = tostring(text or "")
  text = string.gsub(text, "%%", "%%25")
  text = string.gsub(text, "%^", "%%5E")
  text = string.gsub(text, ";", "%%3B")
  text = string.gsub(text, ",", "%%2C")
  return text
end

local function UnescapeField(text)
  text = tostring(text or "")
  return string.gsub(text, "%%(%x%x)", function(hex)
    local value = tonumber(hex, 16)
    if not value then
      return ""
    end
    return string.char(value)
  end)
end

local function SamePlayerName(a, b)
  local left = ShortName(a)
  local right = ShortName(b)
  if not left or not right then
    return false
  end
  return Lower(left) == Lower(right)
end

local function Atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end
  if x == 0 then
    if y > 0 then
      return math.pi / 2
    end
    if y < 0 then
      return -(math.pi / 2)
    end
    return 0
  end
  local angle = math.atan(y / x)
  if x < 0 then
    angle = angle + math.pi
  end
  return angle
end

function LeafAlliance:Print(message)
  local text = "|cFF73C8FF[LeafAlliance]|r " .. tostring(message or "")
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(text)
  end
end

function LeafAlliance:EnsureDB()
  if type(LeafAllianceDB) ~= "table" then
    LeafAllianceDB = {}
  end
  if type(LeafAllianceDB.options) ~= "table" then
    LeafAllianceDB.options = {}
  end
  if LeafAllianceDB.options.autoJoin == nil then
    LeafAllianceDB.options.autoJoin = true
  end
  if type(LeafAllianceDB.minimap) ~= "table" then
    LeafAllianceDB.minimap = {}
  end
  if LeafAllianceDB.minimap.angle == nil then
    LeafAllianceDB.minimap.angle = 225
  end
end

function LeafAlliance:Schedule(key, delay, callback)
  if not key or type(callback) ~= "function" then
    return
  end
  self.scheduledTasks[key] = {
    remaining = tonumber(delay) or 0,
    callback = callback
  }
end

function LeafAlliance:RunScheduledTasks(elapsed)
  local readyKeys = {}
  for key, task in pairs(self.scheduledTasks) do
    task.remaining = (task.remaining or 0) - elapsed
    if task.remaining <= 0 then
      table.insert(readyKeys, key)
    end
  end
  for i = 1, table.getn(readyKeys) do
    local key = readyKeys[i]
    local task = self.scheduledTasks[key]
    self.scheduledTasks[key] = nil
    if task and type(task.callback) == "function" then
      local ok, err = pcall(task.callback)
      if not ok then
        self:Print("Task failed: " .. tostring(err))
      end
    end
  end
end

function LeafAlliance:GetChannelName()
  return tostring(self.channelName or "Leaf")
end

function LeafAlliance:GetDisplayLabel()
  return tostring(self.displayLabel or "Alliance")
end

function LeafAlliance:GetChannelPassword()
  return tostring(self.channelPassword or "")
end

function LeafAlliance:GetChannelId()
  local channelId = 0
  if type(GetChannelName) == "function" then
    local lookupId = GetChannelName(self:GetChannelName())
    channelId = tonumber(lookupId) or 0
  end
  if channelId > 0 then
    self.channelId = channelId
  end
  return channelId
end

function LeafAlliance:IsJoined()
  return self:GetChannelId() > 0
end

function LeafAlliance:IsAllianceMessageChannel(channelString, channelName, channelNumber)
  local desiredName = Lower(self:GetChannelName())
  local normalizedString = Lower(Trim(channelString or ""))
  local normalizedName = Lower(Trim(channelName or ""))
  local activeChannelId = self:GetChannelId()

  if normalizedName ~= "" then
    if normalizedName == desiredName then
      return true
    end
    if string.find(normalizedName, desiredName, 1, true) then
      return true
    end
  end

  if normalizedString ~= "" and string.find(normalizedString, desiredName, 1, true) then
    return true
  end

  if activeChannelId > 0 and tonumber(channelNumber) == activeChannelId then
    return true
  end

  return false
end

function LeafAlliance:IsAllianceOutgoingChannel(channelTarget)
  local activeChannelId = self:GetChannelId()
  local desiredName = Lower(self:GetChannelName())
  local normalizedTarget = Lower(Trim(tostring(channelTarget or "")))

  if normalizedTarget == "" then
    return false
  end
  if normalizedTarget == desiredName then
    return true
  end
  if string.find(normalizedTarget, desiredName, 1, true) then
    return true
  end
  if activeChannelId > 0 and tonumber(channelTarget) == activeChannelId then
    return true
  end

  return false
end

function LeafAlliance:BuildOutgoingPrefix()
  return "|cFF73C8FF[" .. self:GetDisplayLabel() .. "]|r |cFFFFD10D"
end

function LeafAlliance:BuildPlainOutgoingPrefix()
  return "[" .. self:GetDisplayLabel() .. "] "
end

function LeafAlliance:BuildFormattedLine(author, message)
  local displayAuthor = ShortName(author) or Trim(author or "")
  local displayMessage = tostring(message or "")
  local colorPrefix = self:BuildOutgoingPrefix()
  local plainPrefix = self:BuildPlainOutgoingPrefix()
  local legacyPlainPrefix = "[Alliance] "
  if displayAuthor == nil or displayAuthor == "" then
    displayAuthor = "Unknown"
  end

  if string.sub(displayMessage, 1, string.len(colorPrefix)) == colorPrefix then
    displayMessage = string.sub(displayMessage, string.len(colorPrefix) + 1)
    if string.sub(displayMessage, -2) == "|r" then
      displayMessage = string.sub(displayMessage, 1, -3)
    end
  end
  if string.sub(displayMessage, 1, string.len(plainPrefix)) == plainPrefix then
    displayMessage = string.sub(displayMessage, string.len(plainPrefix) + 1)
  end
  if string.sub(displayMessage, 1, string.len(legacyPlainPrefix)) == legacyPlainPrefix then
    displayMessage = string.sub(displayMessage, string.len(legacyPlainPrefix) + 1)
  end
  displayMessage = string.gsub(displayMessage, "^%[" .. self:GetDisplayLabel() .. "%]%s*", "")
  displayMessage = string.gsub(displayMessage, "^%[Alliance%]%s*", "")

  return "|cFF73C8FF[" .. self:GetDisplayLabel() .. "]|r " .. displayAuthor .. ": |cFFFFD10D" .. displayMessage .. "|r"
end

function LeafAlliance:IsHiddenProtocolMessage(message)
  if type(message) ~= "string" then
    return false
  end
  return string.sub(message, 1, string.len(self.hiddenPrefix)) == self.hiddenPrefix
end

function LeafAlliance:ShouldSuppressSystemMessage(message)
  local text = Lower(Trim(message or ""))
  local desiredName = Lower(self:GetChannelName())
  if text == "" or desiredName == "" then
    return false
  end
  if string.find(text, desiredName, 1, true) == nil then
    return false
  end
  return string.find(text, "owner changed to", 1, true) ~= nil
    or string.find(text, "changed owner to", 1, true) ~= nil
    or string.find(text, "joined channel", 1, true) ~= nil
    or string.find(text, "left channel", 1, true) ~= nil
end

function LeafAlliance:ShouldSuppressRenderedText(text)
  if self:IsHiddenProtocolMessage(tostring(text or "")) then
    return true
  end
  return self:ShouldSuppressSystemMessage(text)
end

function LeafAlliance:WrapChatFrame(frame)
  if not frame or type(frame.AddMessage) ~= "function" or frame.leafAllianceWrapped then
    return false
  end
  frame.leafAllianceOriginalAddMessage = frame.AddMessage
  frame.AddMessage = function(selfFrame, text, r, g, b, chatTypeID, holdTime, accessID, lineID)
    if LeafAlliance and LeafAlliance.ShouldSuppressRenderedText and LeafAlliance:ShouldSuppressRenderedText(text) then
      return
    end
    return selfFrame.leafAllianceOriginalAddMessage(selfFrame, text, r, g, b, chatTypeID, holdTime, accessID, lineID)
  end
  frame.leafAllianceWrapped = true
  return true
end

function LeafAlliance:InstallRenderedMessageSuppression()
  if self.renderedSuppressionInstalled then
    return
  end
  self.renderedSuppressionInstalled = true

  local totalFrames = tonumber(NUM_CHAT_WINDOWS) or 7
  for i = 1, totalFrames do
    self:WrapChatFrame(_G["ChatFrame" .. tostring(i)])
  end
  self:WrapChatFrame(DEFAULT_CHAT_FRAME)
  self:WrapChatFrame(SELECTED_CHAT_FRAME)
end

function LeafAlliance:HandleAllianceChatFrameMessage(chatFrame, eventName, message, author, languageName, channelString, target, flags, unknown1, channelNumber, channelName, unknown2, counter)
  if eventName == "CHAT_MSG_CHANNEL_NOTICE" or eventName == "CHAT_MSG_CHANNEL_NOTICE_USER" then
    if self:ShouldSuppressSystemMessage(message) then
      return true
    end
  end

  if eventName == "CHAT_MSG_SYSTEM" and self:ShouldSuppressSystemMessage(message) then
    return true
  end

  if eventName == "CHAT_MSG_CHANNEL" and self:IsAllianceMessageChannel(channelString, channelName, channelNumber) then
    if self:IsHiddenProtocolMessage(message) then
      self:HandleIncomingProtocolMessage(message, author)
      return true
    end

    local formatted = self:BuildFormattedLine(author, message)
    if chatFrame and chatFrame.AddMessage then
      chatFrame:AddMessage(formatted)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
      DEFAULT_CHAT_FRAME:AddMessage(formatted)
    end
    return true
  end

  return false
end

function LeafAlliance:InstallChatHandler()
  if self.chatHandlerInstalled then
    return
  end
  self.chatHandlerInstalled = true
  self:InstallRenderedMessageSuppression()

  if type(ChatFrame_MessageEventHandler) ~= "function" then
    return
  end

  self.originalMessageEventHandler = ChatFrame_MessageEventHandler
  ChatFrame_MessageEventHandler = function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13)
    local chatFrame
    local eventName
    local message
    local author
    local languageName
    local channelString
    local target
    local flags
    local unknown1
    local channelNumber
    local channelName
    local unknown2
    local counter

    if type(a1) == "table" and a1.AddMessage then
      chatFrame = a1
      eventName = a2
      message = a3
      author = a4
      languageName = a5
      channelString = a6
      target = a7
      flags = a8
      unknown1 = a9
      channelNumber = a10
      channelName = a11
      unknown2 = a12
      counter = a13
    else
      chatFrame = (type(this) == "table" and this.AddMessage and this) or DEFAULT_CHAT_FRAME
      eventName = a1
      message = a2
      author = a3
      languageName = a4
      channelString = a5
      target = a6
      flags = a7
      unknown1 = a8
      channelNumber = a9
      channelName = a10
      unknown2 = a11
      counter = a12
    end

    if LeafAlliance and LeafAlliance.HandleAllianceChatFrameMessage then
      local ok, handled = pcall(
        LeafAlliance.HandleAllianceChatFrameMessage,
        LeafAlliance,
        chatFrame,
        eventName,
        message,
        author,
        languageName,
        channelString,
        target,
        flags,
        unknown1,
        channelNumber,
        channelName,
        unknown2,
        counter
      )
      if ok and handled then
        return
      end
      if not ok then
        LeafAlliance:Print("Chat handler error: " .. tostring(handled))
      end
    end

    return LeafAlliance.originalMessageEventHandler(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13)
  end
end

function LeafAlliance:InstallSendHook()
  if self.sendHookInstalled and SendChatMessage == self.wrappedSendChatMessage then
    return
  end
  self.sendHookInstalled = true

  if type(SendChatMessage) ~= "function" then
    return
  end

  self.originalSendChatMessage = SendChatMessage
  self.wrappedSendChatMessage = function(msg, chatType, language, channel)
    local outgoing = msg
    if LeafAlliance and chatType == "CHANNEL" and type(msg) == "string" and msg ~= "" and string.sub(msg, 1, 1) ~= "/" then
      if LeafAlliance:IsAllianceOutgoingChannel(channel) and not LeafAlliance:IsHiddenProtocolMessage(msg) then
        local cleanMessage = tostring(msg or "")
        local colorPrefix = LeafAlliance:BuildOutgoingPrefix()
        local plainPrefix = LeafAlliance:BuildPlainOutgoingPrefix()
        if string.sub(cleanMessage, 1, string.len(colorPrefix)) == colorPrefix then
          cleanMessage = string.sub(cleanMessage, string.len(colorPrefix) + 1)
          if string.sub(cleanMessage, -2) == "|r" then
            cleanMessage = string.sub(cleanMessage, 1, -3)
          end
        end
        if string.sub(cleanMessage, 1, string.len(plainPrefix)) == plainPrefix then
          cleanMessage = string.sub(cleanMessage, string.len(plainPrefix) + 1)
        end
        cleanMessage = string.gsub(cleanMessage, "^%[" .. LeafAlliance:GetDisplayLabel() .. "%]%s*", "")
        outgoing = plainPrefix .. cleanMessage
      end
    end
    return LeafAlliance.originalSendChatMessage(outgoing, chatType, language, channel)
  end
  SendChatMessage = self.wrappedSendChatMessage
end

function LeafAlliance:InstallChatSupport()
  self:InstallChatHandler()
end

function LeafAlliance:ApplyChannelColor(channelId)
  channelId = tonumber(channelId) or self:GetChannelId()
  if channelId <= 0 then
    return false
  end

  local channelKey = "CHANNEL" .. tostring(channelId)
  local color = self.channelColor or { 1.00, 0.82, 0.05 }

  if ChatTypeInfo and ChatTypeInfo[channelKey] then
    ChatTypeInfo[channelKey].r = color[1]
    ChatTypeInfo[channelKey].g = color[2]
    ChatTypeInfo[channelKey].b = color[3]
  end

  if type(ChangeChatColor) == "function" then
    pcall(ChangeChatColor, channelKey, color[1], color[2], color[3])
  end
  if type(ChangeChatColorByID) == "function" then
    pcall(ChangeChatColorByID, channelId, color[1], color[2], color[3])
  end

  return true
end

function LeafAlliance:EnsureChannelVisible(channelName)
  channelName = channelName or self:GetChannelName()
  if type(ChatFrame_AddChannel) == "function" then
    if DEFAULT_CHAT_FRAME then
      pcall(ChatFrame_AddChannel, DEFAULT_CHAT_FRAME, channelName)
    end
    if SELECTED_CHAT_FRAME and SELECTED_CHAT_FRAME ~= DEFAULT_CHAT_FRAME then
      pcall(ChatFrame_AddChannel, SELECTED_CHAT_FRAME, channelName)
    end
  end
end

function LeafAlliance:OpenChatInput()
  local channelId = self:GetChannelId()
  if channelId <= 0 then
    return false
  end
  if type(ChatFrame_OpenChat) == "function" then
    ChatFrame_OpenChat("/" .. tostring(channelId) .. " ")
    return true
  end
  return false
end

function LeafAlliance:FinalizeJoin(channelId, alreadyJoined, openInput)
  channelId = tonumber(channelId) or self:GetChannelId()
  if channelId <= 0 then
    return false
  end

  self.channelId = channelId
  self.lastAutoJoinAttemptAt = Now()
  self:EnsureChannelVisible(self:GetChannelName())
  self:ApplyChannelColor(channelId)
  self:InstallChatSupport()

  if alreadyJoined then
    self:Print("Alliance chat ready: [" .. self:GetChannelName() .. "]")
  else
    self:Print("Joined alliance chat: [" .. self:GetChannelName() .. "]")
  end

  if openInput then
    self:OpenChatInput()
  end

  self:RefreshUI()

  return true
end

function LeafAlliance:JoinChannel(openInput)
  self:EnsureDB()
  self:InstallChatSupport()

  local channelName = self:GetChannelName()
  local channelId = self:GetChannelId()
  if channelId > 0 then
    return self:FinalizeJoin(channelId, true, openInput)
  end

  if type(JoinChannelByName) == "function" then
    JoinChannelByName(channelName, self:GetChannelPassword() ~= "" and self:GetChannelPassword() or nil)
  end

  self.pendingOpenInput = openInput and true or false
  self:Print("Joining alliance chat [" .. channelName .. "]...")
  self:Schedule("join_retry", 0.7, function()
    local retryChannelId = LeafAlliance:GetChannelId()
    local shouldOpenInput = LeafAlliance.pendingOpenInput and true or false
    LeafAlliance.pendingOpenInput = nil
    if retryChannelId > 0 then
      LeafAlliance:FinalizeJoin(retryChannelId, false, shouldOpenInput)
    else
      LeafAlliance:Print("Unable to join alliance chat [" .. channelName .. "].")
      LeafAlliance:RefreshUI()
    end
  end)

  return true
end

function LeafAlliance:MaybeAutoJoin(force)
  self:EnsureDB()
  if LeafAllianceDB.options.autoJoin ~= true then
    return false
  end

  local now = Now()
  if self:IsJoined() then
    self.channelId = self:GetChannelId()
    self.lastAutoJoinAttemptAt = now
    self:EnsureChannelVisible(self:GetChannelName())
    self:ApplyChannelColor(self.channelId)
    self:InstallChatSupport()
    self:RefreshUI()
    return true
  end

  self.lastAutoJoinAttemptAt = tonumber(self.lastAutoJoinAttemptAt) or 0
  if not force and (now - self.lastAutoJoinAttemptAt) < (tonumber(self.autoJoinRetryInterval) or 15) then
    return false
  end

  self.lastAutoJoinAttemptAt = now
  return self:JoinChannel(false)
end

function LeafAlliance:UpdateGuildRosterCache(force)
  local now = Now()
  if not force and (now - self.guildRosterCacheTime) < self.guildRosterCacheDuration then
    return
  end

  self.guildRosterCache = {}

  if type(GuildRoster) == "function" and (now - self.guildRosterRequestAt) >= self.guildRosterRequestCooldown then
    GuildRoster()
    self.guildRosterRequestAt = now
  end

  if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
    return
  end

  local totalMembers = tonumber(GetNumGuildMembers(true)) or 0
  if totalMembers <= 0 then
    return
  end

  local guildName = GetGuildInfo and GetGuildInfo("player") or nil
  local sawMembers = false

  for i = 1, totalMembers do
    local name, rank, rankIndex, level, class, zone, note, officerNote, online, status = GetGuildRosterInfo(i)
    name = ShortName(name)
    if name and name ~= "" then
      sawMembers = true
      self.guildRosterCache[Lower(name)] = {
        name = name,
        rank = tostring(rank or ""),
        rankIndex = tonumber(rankIndex) or 0,
        level = tonumber(level) or 0,
        class = tostring(class or ""),
        zone = tostring(zone or ""),
        online = online and true or false,
        guild = tostring(guildName or "")
      }
    end
  end

  if sawMembers then
    self.guildRosterCacheTime = now
  end
end

function LeafAlliance:BuildLocalGuildSnapshot(force)
  local now = Now()
  self:UpdateGuildRosterCache(force)

  local guildName = GetGuildInfo and GetGuildInfo("player") or nil
  guildName = Trim(guildName or "")
  if guildName == "" then
    return nil
  end

  local members = {}
  for _, member in pairs(self.guildRosterCache) do
    if member.online then
      table.insert(members, {
        name = member.name,
        class = member.class,
        level = member.level,
        rank = member.rank
      })
    end
  end

  table.sort(members, function(a, b)
    return Lower(a.name) < Lower(b.name)
  end)

  return {
    guild = guildName,
    updatedAt = math.floor(now),
    sender = ShortName(UnitName and UnitName("player") or ""),
    members = members,
    receivedAt = now,
    isLocal = true
  }
end

function LeafAlliance:SerializeRosterMembers(members)
  local entries = {}
  for i = 1, table.getn(members) do
    local member = members[i]
    entries[i] = table.concat({
      EscapeField(member.name),
      EscapeField(member.class),
      tostring(tonumber(member.level) or 0),
      EscapeField(member.rank)
    }, ",")
  end
  local payload = table.concat(entries, ";")
  if payload == "" then
    payload = "_"
  end
  return payload
end

function LeafAlliance:DeserializeRosterMembers(payload)
  local members = {}
  local seen = {}
  payload = tostring(payload or "")
  if payload == "" or payload == "_" then
    return members
  end

  local entries = Split(payload, ";")
  for i = 1, table.getn(entries) do
    local entry = entries[i]
    if entry ~= "" then
      local fields = Split(entry, ",")
      local name = ShortName(UnescapeField(fields[1] or ""))
      if name and seen[Lower(name)] == nil then
        seen[Lower(name)] = true
        table.insert(members, {
          name = name,
          class = UnescapeField(fields[2] or ""),
          level = tonumber(fields[3]) or 0,
          rank = UnescapeField(fields[4] or "")
        })
      end
    end
  end

  table.sort(members, function(a, b)
    return Lower(a.name) < Lower(b.name)
  end)

  return members
end

function LeafAlliance:SendHiddenMessage(body)
  return false
end

function LeafAlliance:IngestSnapshot(snapshot, sender)
  if type(snapshot) ~= "table" then
    return
  end

  local guildName = Trim(snapshot.guild or "")
  if guildName == "" then
    return
  end

  snapshot.guild = guildName
  snapshot.sender = ShortName(sender or snapshot.sender or "")
  snapshot.updatedAt = tonumber(snapshot.updatedAt) or math.floor(Now())
  snapshot.receivedAt = Now()

  local key = Lower(guildName)
  local existing = self.remoteGuilds[key]
  if existing and tonumber(existing.updatedAt) and tonumber(existing.updatedAt) > snapshot.updatedAt then
    return
  end

  self.remoteGuilds[key] = snapshot
  self:RefreshUI()
end

function LeafAlliance:BroadcastRosterSnapshot(force)
  return false
end

function LeafAlliance:RequestSync(force)
  return false
end

function LeafAlliance:HandleSyncRequest(sender)
  if sender and SamePlayerName(sender, UnitName and UnitName("player") or "") then
    return
  end
end

function LeafAlliance:HandleRosterChunk(messageBody, sender)
  return
end

function LeafAlliance:HandleIncomingProtocolMessage(message, sender)
  if not self:IsHiddenProtocolMessage(message) then
    return false
  end

  return true
end

function LeafAlliance:QueueBroadcast(delay)
  return
end

function LeafAlliance:RefreshLocalSnapshot(force)
  return
end

function LeafAlliance:PruneStaleRemoteGuilds()
  local now = Now()
  local localGuildName = Lower(GetGuildInfo and GetGuildInfo("player") or "")

  for key, snapshot in pairs(self.remoteGuilds) do
    if key ~= localGuildName then
      if (now - (snapshot.receivedAt or 0)) > self.remoteGuildTimeout then
        self.remoteGuilds[key] = nil
      end
    end
  end

  for key, pending in pairs(self.pendingChunks) do
    if (pending.expiresAt or 0) <= now then
      self.pendingChunks[key] = nil
    end
  end
end

function LeafAlliance:BuildDisplayRows()
  return {}, 0, 0
end

function LeafAlliance:UpdateMinimapButtonPosition()
  if not self.minimapButton or not Minimap then
    return
  end

  self:EnsureDB()

  local angle = tonumber(LeafAllianceDB.minimap.angle) or 225
  local radians = math.rad(angle)
  local radius = 78
  local x = math.cos(radians) * radius
  local y = math.sin(radians) * radius

  self.minimapButton:ClearAllPoints()
  self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function LeafAlliance:RefreshMinimapButton()
  if not self.minimapButton then
    return
  end

  if self:IsJoined() then
    self.minimapButton.icon:SetVertexColor(1, 1, 1)
    self.minimapButton.border:SetVertexColor(0.20, 1.00, 0.20)
  else
    self.minimapButton.icon:SetVertexColor(0.85, 0.85, 0.85)
    self.minimapButton.border:SetVertexColor(1.00, 0.82, 0.05)
  end
end

function LeafAlliance:CreateMinimapButton()
  if self.minimapButton or not Minimap then
    return self.minimapButton
  end

  self:EnsureDB()

  local button = CreateFrame("Button", "LeafAllianceMinimapButton", Minimap)
  button:SetWidth(32)
  button:SetHeight(32)
  button:SetFrameStrata("MEDIUM")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetWidth(18)
  icon:SetHeight(18)
  icon:SetPoint("CENTER", button, "CENTER", 0, 0)
  icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetAllPoints(button)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  button.border = border

  button:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      if LeafAlliance:IsJoined() then
        LeafAlliance:OpenChatInput()
      else
        LeafAlliance:JoinChannel(true)
      end
      return
    end
    LeafAlliance:TogglePanel()
  end)

  button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("Leaf Alliance")
    if LeafAlliance:IsJoined() then
      GameTooltip:AddLine("Left-click: Open panel", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Right-click: Open alliance chat", 0.8, 0.8, 0.8)
    else
      GameTooltip:AddLine("Left-click: Open panel", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Right-click: Join alliance chat", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Drag: Move button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)

  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  button:SetScript("OnDragStart", function()
    this.isMoving = true
    this:SetScript("OnUpdate", function()
      local cursorX, cursorY = GetCursorPosition()
      local scale = UIParent and UIParent:GetScale() or 1
      cursorX = cursorX / scale
      cursorY = cursorY / scale

      local centerX, centerY = Minimap:GetCenter()
      if not centerX or not centerY then
        return
      end

      local angle = math.deg(Atan2(cursorY - centerY, cursorX - centerX))
      if angle < 0 then
        angle = angle + 360
      end
      LeafAllianceDB.minimap.angle = angle
      LeafAlliance:UpdateMinimapButtonPosition()
    end)
  end)

  button:SetScript("OnDragStop", function()
    this.isMoving = nil
    this:SetScript("OnUpdate", nil)
    LeafAlliance:UpdateMinimapButtonPosition()
  end)

  self.minimapButton = button
  self:UpdateMinimapButtonPosition()
  self:RefreshMinimapButton()

  return button
end

function LeafAlliance:CreatePanel()
  if self.panel then
    return self.panel
  end

  local panel = CreateFrame("Frame", "LeafAllianceMainPanel", UIParent)
  panel:SetWidth(470)
  panel:SetHeight(540)
  panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  panel:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
  panel:SetBackdropBorderColor(0.70, 0.56, 0.18, 1)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetClampedToScreen(true)
  panel:Hide()

  panel:SetScript("OnDragStart", function()
    this:StartMoving()
  end)
  panel:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
  end)
  panel:SetScript("OnShow", function()
    LeafAlliance:RefreshPanel()
  end)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
  title:SetText("|cFFFFD700Leaf Alliance|r")

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  subtitle:SetWidth(425)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("|cFFB8B8B8Joins the shared alliance channel with auto-join, quiet notices, and alliance chat formatting.|r")

  local closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

  local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -58)
  statusText:SetWidth(425)
  statusText:SetJustifyH("LEFT")
  panel.statusText = statusText

  local summaryText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summaryText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6)
  summaryText:SetWidth(425)
  summaryText:SetJustifyH("LEFT")
  panel.summaryText = summaryText

  local joinButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  joinButton:SetWidth(155)
  joinButton:SetHeight(22)
  joinButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -105)
  joinButton:SetScript("OnClick", function()
    if LeafAlliance:IsJoined() then
      LeafAlliance:OpenChatInput()
    else
      LeafAlliance:JoinChannel(true)
    end
  end)
  panel.joinButton = joinButton

  local refreshButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  refreshButton:SetWidth(110)
  refreshButton:SetHeight(22)
  refreshButton:SetPoint("LEFT", joinButton, "RIGHT", 8, 0)
  refreshButton:SetText("Refresh UI")
  refreshButton:SetScript("OnClick", function()
    LeafAlliance:RefreshPanel()
  end)

  local autoJoin = CreateFrame("CheckButton", "LeafAllianceAutoJoinCheck", panel, "UICheckButtonTemplate")
  autoJoin:SetPoint("LEFT", refreshButton, "RIGHT", 12, 0)
  autoJoin:SetScript("OnClick", function()
    LeafAlliance:EnsureDB()
    LeafAllianceDB.options.autoJoin = this:GetChecked() and true or false
    LeafAlliance:RefreshPanel()
  end)
  panel.autoJoinCheck = autoJoin

  local autoJoinLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  autoJoinLabel:SetPoint("LEFT", autoJoin, "RIGHT", 2, 0)
  autoJoinLabel:SetText("Auto-Join")

  local divider = panel:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -138)
  divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -138)
  divider:SetHeight(1)
  divider:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  divider:SetVertexColor(0.70, 0.56, 0.18, 0.45)

  local listTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  listTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -154)
  listTitle:SetText("|cFFFFD700Alliance Channel|r")

  local noteText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  noteText:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -4)
  noteText:SetWidth(425)
  noteText:SetJustifyH("LEFT")
  noteText:SetText("|cFF888888Roster syncing is disabled in this build. This addon only manages alliance chat.|r")

  local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -198)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 16)
  scrollFrame:EnableMouseWheel(true)

  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(395)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  panel.scrollFrame = scrollFrame
  panel.scrollChild = scrollChild

  scrollFrame:SetScript("OnMouseWheel", function()
    local current = this:GetVerticalScroll()
    local maxScroll = this:GetVerticalScrollRange()
    local newScroll = current - (arg1 * 36)
    if newScroll < 0 then
      newScroll = 0
    end
    if newScroll > maxScroll then
      newScroll = maxScroll
    end
    this:SetVerticalScroll(newScroll)
  end)

  local scrollBar = CreateFrame("Slider", nil, panel)
  scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -198)
  scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  scrollBar:SetBackdropColor(0, 0, 0, 0.35)
  scrollBar:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
  scrollBar:SetMinMaxValues(0, 100)
  scrollBar:SetValue(0)
  scrollBar:SetScript("OnValueChanged", function()
    local maxScroll = panel.scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      panel.scrollFrame:SetVerticalScroll((this:GetValue() / 100) * maxScroll)
    else
      panel.scrollFrame:SetVerticalScroll(0)
    end
  end)
  panel.scrollBar = scrollBar

  scrollFrame:SetScript("OnVerticalScroll", function()
    local maxScroll = panel.scrollFrame:GetVerticalScrollRange()
    if maxScroll > 0 then
      panel.scrollBar:SetValue((panel.scrollFrame:GetVerticalScroll() / maxScroll) * 100)
    else
      panel.scrollBar:SetValue(0)
    end
  end)

  self.panel = panel
  self:RefreshPanel()

  return panel
end

function LeafAlliance:RefreshPanel()
  local panel = self:CreatePanel()
  if not panel then
    return
  end

  self:EnsureDB()

  if self:IsJoined() then
    panel.statusText:SetText("|cFF00FF00Status: Joined|r  Channel: |cFFFFD10D" .. self:GetChannelName() .. "|r (#" .. tostring(self:GetChannelId()) .. ")")
    panel.joinButton:SetText("Open Chat")
  else
    panel.statusText:SetText("|cFFFF6666Status: Not Joined|r  Click Join to connect to |cFFFFD10D" .. self:GetChannelName() .. "|r.")
    panel.joinButton:SetText("Join Channel")
  end

  panel.autoJoinCheck:SetChecked(LeafAllianceDB.options.autoJoin == true)

  local rows, guildCount, memberCount = self:BuildDisplayRows()
  panel.summaryText:SetText("|cFFB8B8B8Roster sync:|r disabled   |cFFB8B8B8Channel:|r " .. tostring(self:GetChannelName()))

  for i = 1, table.getn(self.panelRows) do
    self.panelRows[i]:Hide()
  end
  if panel.emptyFrame then
    panel.emptyFrame:Hide()
  end

  local yOffset = -4
  local rowHeight = 22

  if table.getn(rows) == 0 then
    local emptyFrame = panel.emptyFrame
    if not emptyFrame then
      emptyFrame = CreateFrame("Frame", nil, panel.scrollChild)
      emptyFrame:SetWidth(390)
      emptyFrame:SetHeight(40)
      emptyFrame.text = emptyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      emptyFrame.text:SetPoint("TOPLEFT", emptyFrame, "TOPLEFT", 0, -4)
      emptyFrame.text:SetWidth(380)
      emptyFrame.text:SetJustifyH("LEFT")
      panel.emptyFrame = emptyFrame
    end
    emptyFrame:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, yOffset)
    emptyFrame.text:SetText("|cFF888888Alliance roster syncing is disabled. Use this addon only for joining and chatting in the shared alliance channel.|r")
    emptyFrame:Show()
    yOffset = yOffset - 44
  else
    for i = 1, table.getn(rows) do
      local rowData = rows[i]
      local row = self.panelRows[i]
      if not row then
        row = CreateFrame("Button", nil, panel.scrollChild)
        row:SetWidth(390)
        row:SetHeight(rowHeight)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.text:SetWidth(378)
        row.text:SetJustifyH("LEFT")

        self.panelRows[i] = row
      end

      row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, yOffset)

      if rowData.rowType == "guild" then
        row.bg:SetVertexColor(0.18, 0.16, 0.08, 0.85)
        row.text:SetFontObject(GameFontNormal)
        row.text:SetText("|cFFFFD700" .. tostring(rowData.guild) .. "|r  |cFFAAAAAA(" .. tostring(rowData.count) .. " online)|r")
      else
        row.bg:SetVertexColor(0.08, 0.08, 0.10, 0.55)
        row.text:SetFontObject(GameFontHighlightSmall)
        local details = tostring(rowData.name)
        if tonumber(rowData.level) and tonumber(rowData.level) > 0 then
          details = details .. "  |cFFAAAAAALvl " .. tostring(rowData.level) .. "|r"
        end
        if Trim(rowData.class or "") ~= "" then
          details = details .. "  |cFF8FD3FF" .. tostring(rowData.class) .. "|r"
        end
        if Trim(rowData.rank or "") ~= "" then
          details = details .. "  |cFF7F7F7F- " .. tostring(rowData.rank) .. "|r"
        end
        row.text:SetText("  " .. details)
      end

      row:Show()
      yOffset = yOffset - rowHeight - 3
    end
  end

  panel.scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 14))

  local scrollRange = panel.scrollFrame:GetVerticalScrollRange()
  if scrollRange > 0 then
    panel.scrollBar:Show()
  else
    panel.scrollBar:Hide()
  end
end

function LeafAlliance:RefreshUI()
  if self.panel then
    self:RefreshPanel()
  end
  self:RefreshMinimapButton()
end

function LeafAlliance:TogglePanel()
  local panel = self:CreatePanel()
  if panel:IsVisible() then
    panel:Hide()
  else
    panel:Show()
  end
end

function LeafAlliance:PeriodicTick()
  self:PruneStaleRemoteGuilds()
  if not self:IsJoined() then
    self:MaybeAutoJoin(false)
  end

  if self.panel then
    self:RefreshPanel()
  end
end

function LeafAlliance:HandleSlashCommand(message)
  message = Lower(Trim(message or ""))
  if message == "" then
    self:TogglePanel()
    return
  end

  if message == "join" then
    self:JoinChannel(true)
    return
  end

  if message == "refresh" then
    self:RefreshUI()
    return
  end

  if message == "show" then
    self:CreatePanel():Show()
    return
  end

  if message == "hide" then
    if self.panel then
      self.panel:Hide()
    end
    return
  end

  self:Print("Commands: /la, /la join, /la refresh, /la show, /la hide")
end

function LeafAlliance:OnEvent(event)
  if event == "VARIABLES_LOADED" then
    self:EnsureDB()
    return
  end

  if event == "PLAYER_LOGIN" then
    self:EnsureDB()
    self:InstallChatSupport()
    self:CreatePanel()
    self:CreateMinimapButton()
    self:Schedule("login_auto_join", 6, function()
      LeafAlliance:MaybeAutoJoin(true)
    end)
    self:Schedule("login_auto_join_retry", 14, function()
      LeafAlliance:MaybeAutoJoin(true)
    end)
    return
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "CHANNEL_UI_UPDATE" then
    self:MaybeAutoJoin(false)
    self:RefreshUI()
    return
  end

  if event == "GUILD_ROSTER_UPDATE" then
    self:RefreshUI()
    return
  end
end

LeafAlliance.eventFrame = CreateFrame("Frame", "LeafAllianceEventFrame")
LeafAlliance.eventFrame:RegisterEvent("VARIABLES_LOADED")
LeafAlliance.eventFrame:RegisterEvent("PLAYER_LOGIN")
LeafAlliance.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
LeafAlliance.eventFrame:RegisterEvent("CHANNEL_UI_UPDATE")
LeafAlliance.eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
LeafAlliance.eventFrame:SetScript("OnEvent", function()
  LeafAlliance:OnEvent(event)
end)
LeafAlliance.eventFrame:SetScript("OnUpdate", function()
  local elapsed = arg1 or 0
  LeafAlliance:RunScheduledTasks(elapsed)
  LeafAlliance._tickElapsed = (LeafAlliance._tickElapsed or 0) + elapsed
  if LeafAlliance._tickElapsed >= 1 then
    LeafAlliance._tickElapsed = 0
    LeafAlliance:PeriodicTick()
  end
end)

SLASH_LEAFALLIANCE1 = "/leafalliance"
SLASH_LEAFALLIANCE2 = "/la"
SlashCmdList["LEAFALLIANCE"] = function(msg)
  LeafAlliance:HandleSlashCommand(msg)
end
