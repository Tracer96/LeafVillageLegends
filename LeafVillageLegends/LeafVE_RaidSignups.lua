LeafVE = LeafVE or {}
LeafVE.UI = LeafVE.UI or { activeTab = "me" }

local RAID_SIGNUP_ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
local RAID_ROLE_ORDER = { "tank", "healer", "melee", "ranged", "flex" }
local RAID_STATUS_ORDER = { "going", "tentative", "late", "unavailable" }
local RAID_EVENT_ROW_COUNT = 7
local RAID_ROSTER_ROW_COUNT = 8
local RAID_SECONDS_PER_DAY = 86400
local RAID_SECONDS_PER_HOUR = 3600
local RAID_CLASS_COLORS = {
  WARRIOR = { 0.78, 0.61, 0.43 },
  PALADIN = { 0.96, 0.55, 0.73 },
  HUNTER = { 0.67, 0.83, 0.45 },
  ROGUE = { 1.00, 0.96, 0.41 },
  PRIEST = { 1.00, 1.00, 1.00 },
  SHAMAN = { 0.00, 0.44, 0.87 },
  MAGE = { 0.25, 0.78, 0.92 },
  WARLOCK = { 0.53, 0.53, 0.93 },
  DRUID = { 1.00, 0.49, 0.04 },
}

local function RaidNow()
  return time()
end

local function RaidTrim(text)
  return (string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1"))
end

local function RaidLower(text)
  return string.lower(tostring(text or ""))
end

local function RaidShortName(name)
  local text = tostring(name or "")
  local dash = string.find(text, "-")
  if dash then
    return string.sub(text, 1, dash - 1)
  end
  return text
end

local function RaidClampNumber(value, minValue, maxValue, fallback)
  local number = tonumber(value)
  if not number then
    number = tonumber(fallback) or 0
  end
  if number < minValue then
    number = minValue
  end
  if number > maxValue then
    number = maxValue
  end
  return number
end

local function RaidFormatEventStatus(status)
  status = NormalizeRaidEventStatus(status)
  if status == "locked" then
    return "|cFFFFD700Locked|r"
  elseif status == "completed" then
    return "|cFF88CCFFCompleted|r"
  elseif status == "cancelled" then
    return "|cFFFF6666Cancelled|r"
  elseif status == "archived" then
    return "|cFF888888Archived|r"
  end
  return "|cFF88FF88Open|r"
end

local function RaidFormatSignupStatus(status)
  status = NormalizeRaidSignupStatus(status)
  if status == "tentative" then
    return "|cFFFFD700Tentative|r"
  elseif status == "late" then
    return "|cFFFFAA55Late|r"
  elseif status == "unavailable" then
    return "|cFFFF6666Can't Make It|r"
  end
  return "|cFF88FF88Going|r"
end

local function RaidFormatRosterStatus(status)
  status = NormalizeRaidRosterStatus(status)
  if status == "confirmed" then
    return "|cFF88FF88Confirmed|r"
  elseif status == "bench" then
    return "|cFFFFD700Bench|r"
  elseif status == "declined" then
    return "|cFFFF6666Declined|r"
  end
  return "|cFFBBBBBBSigned|r"
end

local function RaidGetClassColor(classTag)
  return RAID_CLASS_COLORS[string.upper(classTag or "UNKNOWN")] or { 1, 1, 1 }
end

local function RaidCreateInset(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
  frame:SetBackdropBorderColor(0.30, 0.30, 0.35, 1)
  return frame
end

local function RaidCreateEditBox(parent, width, height)
  local bg = RaidCreateInset(parent)
  bg:SetWidth(width)
  bg:SetHeight(height)

  local input = CreateFrame("EditBox", nil, bg)
  input:SetPoint("TOPLEFT", bg, "TOPLEFT", 5, -3)
  input:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -5, 3)
  input:SetAutoFocus(false)
  input:SetFontObject(GameFontHighlightSmall)
  input:SetJustifyH("LEFT")
  input:SetText("")
  input:SetScript("OnEscapePressed", function()
    this:ClearFocus()
  end)

  return bg, input
end

local function RaidApplyPanelButtonColor(button, enabled)
  if not button then
    return
  end
  if enabled then
    button:Enable()
    button:SetAlpha(1)
  else
    button:Disable()
    button:SetAlpha(0.45)
  end
end

local function RaidApplyRoleButtonState(button, isActive)
  if button and UpdateWorkOrderModeButtonVisual then
    UpdateWorkOrderModeButtonVisual(button, isActive and 1 or nil)
  end
end

local function RaidFormatTime(timestamp)
  timestamp = tonumber(timestamp) or 0
  if timestamp <= 0 then
    return "Not scheduled"
  end
  return date("%a %m/%d %H:%M", timestamp)
end

local function RaidFormatCountdown(timestamp)
  timestamp = tonumber(timestamp) or 0
  if timestamp <= 0 then
    return "No start time set."
  end

  local remaining = timestamp - RaidNow()
  local prefix = "Starts in "
  if remaining < 0 then
    remaining = math.abs(remaining)
    prefix = "Started "
  end

  local days = math.floor(remaining / RAID_SECONDS_PER_DAY)
  local hours = math.floor((remaining - (days * RAID_SECONDS_PER_DAY)) / RAID_SECONDS_PER_HOUR)
  local minutes = math.floor((remaining - (days * RAID_SECONDS_PER_DAY) - (hours * RAID_SECONDS_PER_HOUR)) / 60)
  return prefix .. tostring(days) .. "d " .. tostring(hours) .. "h " .. tostring(minutes) .. "m"
end

local function RaidParseTimestamp(dateText, timeText)
  local year, month, day = string.match(RaidTrim(dateText), "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  local hour, minute = string.match(RaidTrim(timeText), "^(%d%d?)%:(%d%d)$")
  if not year or not month or not day then
    return nil, "Use date format YYYY-MM-DD."
  end
  if not hour or not minute then
    return nil, "Use time format HH:MM."
  end

  local parsedTime = time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(minute),
    sec = 0,
  })
  if not parsedTime then
    return nil, "Date or time is invalid."
  end

  local parts = date("*t", parsedTime)
  if not parts
    or parts.year ~= tonumber(year)
    or parts.month ~= tonumber(month)
    or parts.day ~= tonumber(day)
    or parts.hour ~= tonumber(hour)
    or parts.min ~= tonumber(minute) then
    return nil, "Date or time is invalid."
  end

  return parsedTime
end

local function RaidFindEventById(eventRows, eventId)
  if not eventId then
    return nil
  end
  for _, eventRecord in ipairs(eventRows or {}) do
    if type(eventRecord) == "table" and tostring(eventRecord.id or "") == tostring(eventId or "") then
      return eventRecord
    end
  end
  return nil
end

local function RaidSelectEvent(panel, eventId)
  if not panel then
    return
  end
  panel.selectedEventId = eventId
  panel.selectedRosterPlayer = nil
  panel.lastDetailEventId = nil
end

local function RaidSelectRosterPlayer(panel, playerName)
  if not panel then
    return
  end
  panel.selectedRosterPlayer = playerName
end

local function RaidSamePlayerName(a, b)
  return RaidLower(RaidShortName(a)) == RaidLower(RaidShortName(b))
end

local function RaidSeedAdminDefaults(panel)
  if not panel then
    return
  end

  if not panel.createRaidKey then
    local _, order = LeafVE:GetRaidCatalog()
    if table.getn(order) > 0 then
      panel.createRaidKey = order[1].key
      panel.createRaidIndex = 1
    end
  end

  if panel.adminDefaultsSeeded then
    return
  end

  local tomorrow = date("*t", RaidNow() + RAID_SECONDS_PER_DAY)
  local defaultDate = string.format("%04d-%02d-%02d", tomorrow.year, tomorrow.month, tomorrow.day)
  if panel.dateInput then panel.dateInput:SetText(defaultDate) end
  if panel.startTimeInput then panel.startTimeInput:SetText("20:00") end
  if panel.closeTimeInput then panel.closeTimeInput:SetText("19:30") end
  panel.adminDefaultsSeeded = true
end

local function RaidApplyCatalogSelection(panel, direction)
  local _, order = LeafVE:GetRaidCatalog()
  if table.getn(order) == 0 then
    panel.createRaidKey = nil
    panel.createRaidIndex = nil
    return
  end

  local index = tonumber(panel.createRaidIndex) or 1
  if direction and direction ~= 0 then
    index = index + direction
    if index < 1 then
      index = table.getn(order)
    elseif index > table.getn(order) then
      index = 1
    end
  else
    local found = false
    if panel.createRaidKey then
      for i = 1, table.getn(order) do
        if order[i].key == panel.createRaidKey then
          index = i
          found = true
          break
        end
      end
    end
    if not found then
      index = 1
    end
  end

  local entry = order[index]
  if not entry then
    return
  end

  panel.createRaidIndex = index
  panel.createRaidKey = entry.key

  if panel.selectedRaidNameText then
    panel.selectedRaidNameText:SetText(entry.name or "")
  end
  if panel.eventTitleInput then
    panel.eventTitleInput:SetText(entry.name or "")
  end
  if panel.raidSizeInput then
    panel.raidSizeInput:SetText(tostring(tonumber(entry.raidSize) or 20))
  end
  if panel.notesInput then
    panel.notesInput:SetText("")
  end
  if panel.roleTargetInputs then
    for _, role in ipairs(RAID_ROLE_ORDER) do
      local input = panel.roleTargetInputs[role]
      if input then
        input:SetText(tostring(tonumber(entry.roleTargets and entry.roleTargets[role]) or 0))
      end
    end
  end
end

local function RaidCreateEventRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(64)
  row:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  row:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
  row:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.8)

  row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
  row.titleText:SetPoint("RIGHT", row, "RIGHT", -68, 0)
  row.titleText:SetJustifyH("LEFT")

  row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.statusText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
  row.statusText:SetWidth(60)
  row.statusText:SetJustifyH("RIGHT")

  row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.metaText:SetPoint("TOPLEFT", row.titleText, "BOTTOMLEFT", 0, -4)
  row.metaText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.metaText:SetJustifyH("LEFT")

  row.needText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.needText:SetPoint("TOPLEFT", row.metaText, "BOTTOMLEFT", 0, -4)
  row.needText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.needText:SetJustifyH("LEFT")

  row:SetScript("OnEnter", function()
    if not this.isSelected then
      this:SetBackdropBorderColor(1, 0.82, 0.08, 0.95)
    end
  end)
  row:SetScript("OnLeave", function()
    if this.isSelected then
      this:SetBackdropBorderColor(1, 0.82, 0.08, 0.95)
    else
      this:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.8)
    end
  end)
  row:SetScript("OnClick", function()
    if not this.ownerPanel or not this.eventRecord then
      return
    end
    RaidSelectEvent(this.ownerPanel, this.eventRecord.id)
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  return row
end

local function RaidCreateRosterRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(52)
  row:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  row:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
  row:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.8)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
  row.icon:SetWidth(18)
  row.icon:SetHeight(18)
  row.icon:SetTexture(RAID_SIGNUP_ICON)

  row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.nameText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.nameText:SetJustifyH("LEFT")

  row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.metaText:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -4)
  row.metaText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.metaText:SetJustifyH("LEFT")

  row:SetScript("OnEnter", function()
    if not this.isSelected then
      this:SetBackdropBorderColor(1, 0.82, 0.08, 0.95)
    end
  end)
  row:SetScript("OnLeave", function()
    if this.isSelected then
      this:SetBackdropBorderColor(1, 0.82, 0.08, 0.95)
    else
      this:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.8)
    end
  end)
  row:SetScript("OnClick", function()
    if not this.ownerPanel or not this.signupRecord then
      return
    end
    RaidSelectRosterPlayer(this.ownerPanel, this.signupRecord.player)
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  return row
end

local function RaidBuildModeButtons(panel)
  panel.modeUpcomingBtn = CreateWorkOrderModeButton(panel, "Upcoming")
  panel.modeUpcomingBtn:SetWidth(96)
  panel.modeUpcomingBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
  panel.modeUpcomingBtn.ownerPanel = panel
  panel.modeUpcomingBtn:SetScript("OnClick", function()
    this.ownerPanel.mode = "upcoming"
    this.ownerPanel.eventOffset = 0
    this.ownerPanel.lastDetailEventId = nil
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.modeMineBtn = CreateWorkOrderModeButton(panel, "My Sign-Ups")
  panel.modeMineBtn:SetWidth(100)
  panel.modeMineBtn:SetPoint("LEFT", panel.modeUpcomingBtn, "RIGHT", 8, 0)
  panel.modeMineBtn.ownerPanel = panel
  panel.modeMineBtn:SetScript("OnClick", function()
    this.ownerPanel.mode = "mine"
    this.ownerPanel.eventOffset = 0
    this.ownerPanel.lastDetailEventId = nil
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.modeAdminBtn = CreateWorkOrderModeButton(panel, "Admin")
  panel.modeAdminBtn:SetWidth(82)
  panel.modeAdminBtn:SetPoint("LEFT", panel.modeMineBtn, "RIGHT", 8, 0)
  panel.modeAdminBtn.ownerPanel = panel
  panel.modeAdminBtn:SetScript("OnClick", function()
    this.ownerPanel.mode = "admin"
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.summaryText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.summaryText:SetPoint("TOPLEFT", panel.modeUpcomingBtn, "BOTTOMLEFT", 0, -10)
  panel.summaryText:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
  panel.summaryText:SetJustifyH("LEFT")
end

local function RaidBuildEventPane(panel)
  panel.eventsPane = RaidCreateInset(panel)
  panel.eventsPane:SetPoint("TOPLEFT", panel.summaryText, "BOTTOMLEFT", 0, -8)
  panel.eventsPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
  panel.eventsPane:SetWidth(254)

  panel.eventsTitle = panel.eventsPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.eventsTitle:SetPoint("TOPLEFT", panel.eventsPane, "TOPLEFT", 10, -10)
  panel.eventsTitle:SetText("|cFFFFD700Upcoming Raids|r")

  panel.eventsHint = panel.eventsPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.eventsHint:SetPoint("TOPLEFT", panel.eventsTitle, "BOTTOMLEFT", 0, -5)
  panel.eventsHint:SetPoint("RIGHT", panel.eventsPane, "RIGHT", -10, 0)
  panel.eventsHint:SetJustifyH("LEFT")
  panel.eventsHint:SetJustifyV("TOP")
  panel.eventsHint:SetText("|cFFAAAAAAClick a raid to review the boss list, role targets, and sign-ups.|r")

  panel.eventListFrame = CreateFrame("Frame", nil, panel.eventsPane)
  panel.eventListFrame:SetPoint("TOPLEFT", panel.eventsHint, "BOTTOMLEFT", 0, -8)
  panel.eventListFrame:SetPoint("BOTTOMRIGHT", panel.eventsPane, "BOTTOMRIGHT", -28, 10)
  panel.eventListFrame:EnableMouse(true)
  panel.eventListFrame:EnableMouseWheel(true)
  panel.eventListFrame.ownerPanel = panel
  panel.eventListFrame:SetScript("OnMouseWheel", function()
    local owner = this.ownerPanel
    local totalRows = table.getn(owner.visibleEvents or {})
    local maxOffset = math.max(0, totalRows - (owner.eventVisibleRows or 1))
    local nextOffset = (owner.eventOffset or 0) - (arg1 or 0)
    if nextOffset < 0 then nextOffset = 0 end
    if nextOffset > maxOffset then nextOffset = maxOffset end
    if nextOffset ~= (owner.eventOffset or 0) then
      owner.eventOffset = nextOffset
      LeafVE.UI:RefreshRaidSignupPanel(true)
    end
  end)

  panel.eventScrollBar = CreateFrame("Slider", nil, panel.eventsPane)
  panel.eventScrollBar:SetPoint("TOPRIGHT", panel.eventListFrame, "TOPRIGHT", 20, 0)
  panel.eventScrollBar:SetPoint("BOTTOMRIGHT", panel.eventsPane, "BOTTOMRIGHT", -8, 10)
  panel.eventScrollBar:SetWidth(16)
  panel.eventScrollBar:SetOrientation("VERTICAL")
  panel.eventScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  panel.eventScrollBar:SetMinMaxValues(0, 0)
  panel.eventScrollBar:SetValue(0)
  panel.eventScrollBar:SetValueStep(1)
  panel.eventScrollBar.ownerPanel = panel
  panel.eventScrollBar:SetScript("OnValueChanged", function()
    if this.ignoreUpdate then
      return
    end
    local value = math.floor((this:GetValue() or 0) + 0.5)
    if value < 0 then value = 0 end
    if value ~= (this.ownerPanel.eventOffset or 0) then
      this.ownerPanel.eventOffset = value
      LeafVE.UI:RefreshRaidSignupPanel(true)
    end
  end)
  local eventThumb = panel.eventScrollBar:GetThumbTexture()
  if eventThumb then
    eventThumb:SetWidth(16)
    eventThumb:SetHeight(24)
  end

  panel.noEventsText = panel.eventListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.noEventsText:SetPoint("TOPLEFT", panel.eventListFrame, "TOPLEFT", 8, -8)
  panel.noEventsText:SetPoint("RIGHT", panel.eventListFrame, "RIGHT", -8, 0)
  panel.noEventsText:SetJustifyH("LEFT")
  panel.noEventsText:SetJustifyV("TOP")
  panel.noEventsText:SetText("|cFF888888No raid events are cached yet.|r")

  panel.eventRows = {}
  panel.eventVisibleRows = RAID_EVENT_ROW_COUNT
  local lastRow = nil
  local index = 1
  while index <= RAID_EVENT_ROW_COUNT do
    panel.eventRows[index] = RaidCreateEventRow(panel.eventListFrame)
    panel.eventRows[index]:SetPoint("TOPLEFT", lastRow or panel.eventListFrame, lastRow and "BOTTOMLEFT" or "TOPLEFT", 0, lastRow and -6 or 0)
    panel.eventRows[index]:SetPoint("TOPRIGHT", lastRow or panel.eventListFrame, lastRow and "BOTTOMRIGHT" or "TOPRIGHT", 0, lastRow and -6 or 0)
    panel.eventRows[index].ownerPanel = panel
    lastRow = panel.eventRows[index]
    index = index + 1
  end
end

local function RaidBuildDetailPane(panel)
  panel.detailPane = RaidCreateInset(panel)
  panel.detailPane:SetPoint("TOPLEFT", panel.eventsPane, "TOPRIGHT", 10, 0)
  panel.detailPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 276, 12)
  panel.detailPane:SetWidth(338)

  panel.detailTitle = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.detailTitle:SetPoint("TOPLEFT", panel.detailPane, "TOPLEFT", 10, -10)
  panel.detailTitle:SetPoint("RIGHT", panel.detailPane, "RIGHT", -10, 0)
  panel.detailTitle:SetJustifyH("LEFT")
  panel.detailTitle:SetText("|cFFFFD700Raid Details|r")

  panel.detailMeta = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.detailMeta:SetPoint("TOPLEFT", panel.detailTitle, "BOTTOMLEFT", 0, -5)
  panel.detailMeta:SetPoint("RIGHT", panel.detailPane, "RIGHT", -10, 0)
  panel.detailMeta:SetJustifyH("LEFT")
  panel.detailMeta:SetJustifyV("TOP")
  panel.detailMeta:SetText("|cFF888888Select a raid event from the left list.|r")

  panel.detailNeed = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.detailNeed:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -5)
  panel.detailNeed:SetPoint("RIGHT", panel.detailPane, "RIGHT", -10, 0)
  panel.detailNeed:SetJustifyH("LEFT")
  panel.detailNeed:SetJustifyV("TOP")
  panel.detailNeed:SetText("")

  panel.managerOpenBtn = CreateFrame("Button", nil, panel.detailPane, "UIPanelButtonTemplate")
  panel.managerOpenBtn:SetWidth(58)
  panel.managerOpenBtn:SetHeight(20)
  panel.managerOpenBtn:SetPoint("TOPLEFT", panel.detailNeed, "BOTTOMLEFT", 0, -8)
  panel.managerOpenBtn:SetText("Open")
  panel.managerOpenBtn.ownerPanel = panel
  panel.managerOpenBtn.actionStatus = "open"
  panel.managerOpenBtn:SetScript("OnClick", function()
    local eventRecord = this.ownerPanel and this.ownerPanel.selectedEvent
    if not eventRecord then
      return
    end
    local stored, err = LeafVE:SetRaidEventStatus(eventRecord.id, this.actionStatus)
    if not stored then
      this.ownerPanel.detailFeedbackText:SetText("|cFFFF6666" .. tostring(err or "Unable to update raid status.") .. "|r")
      return
    end
    this.ownerPanel.detailFeedbackText:SetText("|cFF88FF88Raid event is now " .. GetRaidEventStatusLabel(stored.status) .. ".|r")
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.managerLockBtn = CreateFrame("Button", nil, panel.detailPane, "UIPanelButtonTemplate")
  panel.managerLockBtn:SetWidth(58)
  panel.managerLockBtn:SetHeight(20)
  panel.managerLockBtn:SetPoint("LEFT", panel.managerOpenBtn, "RIGHT", 6, 0)
  panel.managerLockBtn:SetText("Lock")
  panel.managerLockBtn.ownerPanel = panel
  panel.managerLockBtn.actionStatus = "locked"
  panel.managerLockBtn:SetScript("OnClick", panel.managerOpenBtn:GetScript("OnClick"))

  panel.managerCompleteBtn = CreateFrame("Button", nil, panel.detailPane, "UIPanelButtonTemplate")
  panel.managerCompleteBtn:SetWidth(66)
  panel.managerCompleteBtn:SetHeight(20)
  panel.managerCompleteBtn:SetPoint("LEFT", panel.managerLockBtn, "RIGHT", 6, 0)
  panel.managerCompleteBtn:SetText("Complete")
  panel.managerCompleteBtn.ownerPanel = panel
  panel.managerCompleteBtn.actionStatus = "completed"
  panel.managerCompleteBtn:SetScript("OnClick", panel.managerOpenBtn:GetScript("OnClick"))

  panel.managerCancelBtn = CreateFrame("Button", nil, panel.detailPane, "UIPanelButtonTemplate")
  panel.managerCancelBtn:SetWidth(60)
  panel.managerCancelBtn:SetHeight(20)
  panel.managerCancelBtn:SetPoint("LEFT", panel.managerCompleteBtn, "RIGHT", 6, 0)
  panel.managerCancelBtn:SetText("Cancel")
  panel.managerCancelBtn.ownerPanel = panel
  panel.managerCancelBtn.actionStatus = "cancelled"
  panel.managerCancelBtn:SetScript("OnClick", panel.managerOpenBtn:GetScript("OnClick"))

  panel.notesLabel = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.notesLabel:SetPoint("TOPLEFT", panel.managerOpenBtn, "BOTTOMLEFT", 0, -10)
  panel.notesLabel:SetText("|cFFFFD700Raid Notes|r")

  panel.notesText = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.notesText:SetPoint("TOPLEFT", panel.notesLabel, "BOTTOMLEFT", 0, -4)
  panel.notesText:SetPoint("RIGHT", panel.detailPane, "RIGHT", -10, 0)
  panel.notesText:SetHeight(44)
  panel.notesText:SetJustifyH("LEFT")
  panel.notesText:SetJustifyV("TOP")
  panel.notesText:SetText("|cFF888888No raid notes yet.|r")

  panel.bossesLabel = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.bossesLabel:SetPoint("TOPLEFT", panel.notesText, "BOTTOMLEFT", 0, -10)
  panel.bossesLabel:SetText("|cFFFFD700Boss Checklist|r")

  panel.bossesText = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.bossesText:SetPoint("TOPLEFT", panel.bossesLabel, "BOTTOMLEFT", 0, -4)
  panel.bossesText:SetPoint("RIGHT", panel.detailPane, "RIGHT", -10, 0)
  panel.bossesText:SetHeight(150)
  panel.bossesText:SetJustifyH("LEFT")
  panel.bossesText:SetJustifyV("TOP")
  panel.bossesText:SetText("|cFF888888No boss list loaded.|r")

  panel.signupHeader = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.signupHeader:SetPoint("TOPLEFT", panel.bossesText, "BOTTOMLEFT", 0, -10)
  panel.signupHeader:SetText("|cFFFFD700Your Signup|r")

  panel.signupStateText = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.signupStateText:SetPoint("TOPLEFT", panel.signupHeader, "BOTTOMLEFT", 0, -4)
  panel.signupStateText:SetPoint("RIGHT", panel.detailPane, "RIGHT", -10, 0)
  panel.signupStateText:SetJustifyH("LEFT")
  panel.signupStateText:SetJustifyV("TOP")
  panel.signupStateText:SetText("|cFF888888No signup saved for this raid yet.|r")

  panel.roleButtons = {}
  local lastRoleButton = nil
  for _, role in ipairs(RAID_ROLE_ORDER) do
    panel.roleButtons[role] = CreateWorkOrderModeButton(panel.detailPane, GetRaidRoleLabel(role))
    panel.roleButtons[role]:SetWidth(58)
    if lastRoleButton then
      panel.roleButtons[role]:SetPoint("LEFT", lastRoleButton, "RIGHT", 4, 0)
    else
      panel.roleButtons[role]:SetPoint("TOPLEFT", panel.signupStateText, "BOTTOMLEFT", 0, -6)
    end
    panel.roleButtons[role].ownerPanel = panel
    panel.roleButtons[role].roleValue = role
    panel.roleButtons[role]:SetScript("OnClick", function()
      this.ownerPanel.selectedRole = NormalizeRaidRole(this.roleValue)
      LeafVE.UI:RefreshRaidSignupPanel(true)
    end)
    lastRoleButton = panel.roleButtons[role]
  end

  panel.statusButtons = {}
  local lastStatusButton = nil
  for _, signupStatus in ipairs(RAID_STATUS_ORDER) do
    panel.statusButtons[signupStatus] = CreateWorkOrderModeButton(panel.detailPane, GetRaidSignupStatusLabel(signupStatus))
    if signupStatus == "unavailable" then
      panel.statusButtons[signupStatus]:SetWidth(88)
    else
      panel.statusButtons[signupStatus]:SetWidth(76)
    end
    if lastStatusButton then
      panel.statusButtons[signupStatus]:SetPoint("LEFT", lastStatusButton, "RIGHT", 4, 0)
    else
      panel.statusButtons[signupStatus]:SetPoint("TOPLEFT", lastRoleButton, "BOTTOMLEFT", -238, -6)
    end
    panel.statusButtons[signupStatus].ownerPanel = panel
    panel.statusButtons[signupStatus].signupValue = signupStatus
    panel.statusButtons[signupStatus]:SetScript("OnClick", function()
      this.ownerPanel.selectedSignupStatus = NormalizeRaidSignupStatus(this.signupValue)
      LeafVE.UI:RefreshRaidSignupPanel(true)
    end)
    lastStatusButton = panel.statusButtons[signupStatus]
  end

  panel.signupNoteLabel = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.signupNoteLabel:SetPoint("TOPLEFT", lastStatusButton, "BOTTOMLEFT", -246, -8)
  panel.signupNoteLabel:SetText("Signup Note")

  panel.signupNoteBG, panel.signupNoteInput = RaidCreateEditBox(panel.detailPane, 230, 22)
  panel.signupNoteBG:SetPoint("TOPLEFT", panel.signupNoteLabel, "BOTTOMLEFT", 0, -4)
  panel.signupNoteInput:SetMaxLetters(60)
  panel.signupNoteInput:SetScript("OnEnterPressed", function()
    this:ClearFocus()
    if panel.saveSignupBtn and panel.saveSignupBtn:IsEnabled() then
      panel.saveSignupBtn:Click()
    end
  end)

  panel.detailFeedbackText = panel.detailPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.detailFeedbackText:SetPoint("TOPLEFT", panel.signupNoteBG, "BOTTOMLEFT", 0, -6)
  panel.detailFeedbackText:SetPoint("RIGHT", panel.detailPane, "RIGHT", -10, 0)
  panel.detailFeedbackText:SetHeight(28)
  panel.detailFeedbackText:SetJustifyH("LEFT")
  panel.detailFeedbackText:SetJustifyV("TOP")
  panel.detailFeedbackText:SetText("")

  panel.withdrawBtn = CreateFrame("Button", nil, panel.detailPane, "UIPanelButtonTemplate")
  panel.withdrawBtn:SetWidth(72)
  panel.withdrawBtn:SetHeight(22)
  panel.withdrawBtn:SetPoint("BOTTOMRIGHT", panel.detailPane, "BOTTOMRIGHT", -108, 10)
  panel.withdrawBtn:SetText("Withdraw")
  panel.withdrawBtn.ownerPanel = panel
  panel.withdrawBtn:SetScript("OnClick", function()
    local owner = this.ownerPanel
    local eventRecord = owner and owner.selectedEvent
    if not eventRecord then
      return
    end
    local stored, err = LeafVE:SubmitRaidSignup(eventRecord.id, "unavailable", owner.selectedRole, owner.signupNoteInput and owner.signupNoteInput:GetText() or "")
    if not stored then
      owner.detailFeedbackText:SetText("|cFFFF6666" .. tostring(err or "Unable to withdraw raid signup.") .. "|r")
      return
    end
    owner.detailFeedbackText:SetText("|cFF88FF88Raid signup updated to Can't Make It.|r")
    owner.lastDetailEventId = nil
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.saveSignupBtn = CreateFrame("Button", nil, panel.detailPane, "UIPanelButtonTemplate")
  panel.saveSignupBtn:SetWidth(94)
  panel.saveSignupBtn:SetHeight(22)
  panel.saveSignupBtn:SetPoint("LEFT", panel.withdrawBtn, "RIGHT", 8, 0)
  panel.saveSignupBtn:SetText("Save Signup")
  panel.saveSignupBtn.ownerPanel = panel
  panel.saveSignupBtn:SetScript("OnClick", function()
    local owner = this.ownerPanel
    local eventRecord = owner and owner.selectedEvent
    if not eventRecord then
      return
    end
    local stored, err = LeafVE:SubmitRaidSignup(
      eventRecord.id,
      owner.selectedSignupStatus or "going",
      owner.selectedRole or "flex",
      owner.signupNoteInput and owner.signupNoteInput:GetText() or ""
    )
    if not stored then
      owner.detailFeedbackText:SetText("|cFFFF6666" .. tostring(err or "Unable to save raid signup.") .. "|r")
      return
    end
    owner.detailFeedbackText:SetText("|cFF88FF88Raid signup saved and broadcast.|r")
    owner.lastDetailEventId = nil
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)
end

local function RaidBuildRosterPane(panel)
  panel.rosterPane = RaidCreateInset(panel)
  panel.rosterPane:SetPoint("TOPLEFT", panel.detailPane, "TOPRIGHT", 10, 0)
  panel.rosterPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)

  panel.rosterTitle = panel.rosterPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.rosterTitle:SetPoint("TOPLEFT", panel.rosterPane, "TOPLEFT", 10, -10)
  panel.rosterTitle:SetText("|cFFFFD700Roster|r")

  panel.rosterSummaryText = panel.rosterPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.rosterSummaryText:SetPoint("TOPLEFT", panel.rosterTitle, "BOTTOMLEFT", 0, -5)
  panel.rosterSummaryText:SetPoint("RIGHT", panel.rosterPane, "RIGHT", -10, 0)
  panel.rosterSummaryText:SetJustifyH("LEFT")
  panel.rosterSummaryText:SetJustifyV("TOP")
  panel.rosterSummaryText:SetText("|cFF888888Select a raid event to view signups.|r")

  panel.selectedRosterText = panel.rosterPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.selectedRosterText:SetPoint("TOPLEFT", panel.rosterSummaryText, "BOTTOMLEFT", 0, -5)
  panel.selectedRosterText:SetPoint("RIGHT", panel.rosterPane, "RIGHT", -10, 0)
  panel.selectedRosterText:SetJustifyH("LEFT")
  panel.selectedRosterText:SetJustifyV("TOP")
  panel.selectedRosterText:SetText("")

  panel.rosterConfirmBtn = CreateFrame("Button", nil, panel.rosterPane, "UIPanelButtonTemplate")
  panel.rosterConfirmBtn:SetWidth(62)
  panel.rosterConfirmBtn:SetHeight(20)
  panel.rosterConfirmBtn:SetPoint("TOPLEFT", panel.selectedRosterText, "BOTTOMLEFT", 0, -6)
  panel.rosterConfirmBtn:SetText("Confirm")
  panel.rosterConfirmBtn.ownerPanel = panel
  panel.rosterConfirmBtn.rosterStatus = "confirmed"
  panel.rosterConfirmBtn:SetScript("OnClick", function()
    local owner = this.ownerPanel
    local eventRecord = owner and owner.selectedEvent
    local playerName = owner and owner.selectedRosterPlayer
    if not eventRecord or not playerName then
      return
    end
    local stored, err = LeafVE:SetRaidRosterStatus(eventRecord.id, playerName, this.rosterStatus)
    if not stored then
      owner.rosterFeedbackText:SetText("|cFFFF6666" .. tostring(err or "Unable to update roster status.") .. "|r")
      return
    end
    owner.rosterFeedbackText:SetText("|cFF88FF88" .. tostring(playerName) .. " is now " .. GetRaidRosterStatusLabel(stored.rosterStatus) .. ".|r")
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.rosterBenchBtn = CreateFrame("Button", nil, panel.rosterPane, "UIPanelButtonTemplate")
  panel.rosterBenchBtn:SetWidth(54)
  panel.rosterBenchBtn:SetHeight(20)
  panel.rosterBenchBtn:SetPoint("LEFT", panel.rosterConfirmBtn, "RIGHT", 6, 0)
  panel.rosterBenchBtn:SetText("Bench")
  panel.rosterBenchBtn.ownerPanel = panel
  panel.rosterBenchBtn.rosterStatus = "bench"
  panel.rosterBenchBtn:SetScript("OnClick", panel.rosterConfirmBtn:GetScript("OnClick"))

  panel.rosterResetBtn = CreateFrame("Button", nil, panel.rosterPane, "UIPanelButtonTemplate")
  panel.rosterResetBtn:SetWidth(52)
  panel.rosterResetBtn:SetHeight(20)
  panel.rosterResetBtn:SetPoint("LEFT", panel.rosterBenchBtn, "RIGHT", 6, 0)
  panel.rosterResetBtn:SetText("Reset")
  panel.rosterResetBtn.ownerPanel = panel
  panel.rosterResetBtn.rosterStatus = "signed"
  panel.rosterResetBtn:SetScript("OnClick", panel.rosterConfirmBtn:GetScript("OnClick"))

  panel.rosterFeedbackText = panel.rosterPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.rosterFeedbackText:SetPoint("TOPLEFT", panel.rosterConfirmBtn, "BOTTOMLEFT", 0, -6)
  panel.rosterFeedbackText:SetPoint("RIGHT", panel.rosterPane, "RIGHT", -10, 0)
  panel.rosterFeedbackText:SetHeight(28)
  panel.rosterFeedbackText:SetJustifyH("LEFT")
  panel.rosterFeedbackText:SetJustifyV("TOP")
  panel.rosterFeedbackText:SetText("")

  panel.rosterListFrame = CreateFrame("Frame", nil, panel.rosterPane)
  panel.rosterListFrame:SetPoint("TOPLEFT", panel.rosterFeedbackText, "BOTTOMLEFT", 0, -6)
  panel.rosterListFrame:SetPoint("BOTTOMRIGHT", panel.rosterPane, "BOTTOMRIGHT", -28, 10)
  panel.rosterListFrame:EnableMouse(true)
  panel.rosterListFrame:EnableMouseWheel(true)
  panel.rosterListFrame.ownerPanel = panel
  panel.rosterListFrame:SetScript("OnMouseWheel", function()
    local owner = this.ownerPanel
    local totalRows = table.getn(owner.visibleRosterRows or {})
    local maxOffset = math.max(0, totalRows - (owner.rosterVisibleRows or 1))
    local nextOffset = (owner.rosterOffset or 0) - (arg1 or 0)
    if nextOffset < 0 then nextOffset = 0 end
    if nextOffset > maxOffset then nextOffset = maxOffset end
    if nextOffset ~= (owner.rosterOffset or 0) then
      owner.rosterOffset = nextOffset
      LeafVE.UI:RefreshRaidSignupPanel(true)
    end
  end)

  panel.rosterScrollBar = CreateFrame("Slider", nil, panel.rosterPane)
  panel.rosterScrollBar:SetPoint("TOPRIGHT", panel.rosterListFrame, "TOPRIGHT", 20, 0)
  panel.rosterScrollBar:SetPoint("BOTTOMRIGHT", panel.rosterPane, "BOTTOMRIGHT", -8, 10)
  panel.rosterScrollBar:SetWidth(16)
  panel.rosterScrollBar:SetOrientation("VERTICAL")
  panel.rosterScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  panel.rosterScrollBar:SetMinMaxValues(0, 0)
  panel.rosterScrollBar:SetValue(0)
  panel.rosterScrollBar:SetValueStep(1)
  panel.rosterScrollBar.ownerPanel = panel
  panel.rosterScrollBar:SetScript("OnValueChanged", function()
    if this.ignoreUpdate then
      return
    end
    local value = math.floor((this:GetValue() or 0) + 0.5)
    if value < 0 then value = 0 end
    if value ~= (this.ownerPanel.rosterOffset or 0) then
      this.ownerPanel.rosterOffset = value
      LeafVE.UI:RefreshRaidSignupPanel(true)
    end
  end)
  local rosterThumb = panel.rosterScrollBar:GetThumbTexture()
  if rosterThumb then
    rosterThumb:SetWidth(16)
    rosterThumb:SetHeight(24)
  end

  panel.noRosterText = panel.rosterListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.noRosterText:SetPoint("TOPLEFT", panel.rosterListFrame, "TOPLEFT", 8, -8)
  panel.noRosterText:SetPoint("RIGHT", panel.rosterListFrame, "RIGHT", -8, 0)
  panel.noRosterText:SetJustifyH("LEFT")
  panel.noRosterText:SetJustifyV("TOP")
  panel.noRosterText:SetText("|cFF888888No sign-ups recorded for this raid yet.|r")

  panel.rosterRows = {}
  panel.rosterVisibleRows = RAID_ROSTER_ROW_COUNT
  local lastRow = nil
  local index = 1
  while index <= RAID_ROSTER_ROW_COUNT do
    panel.rosterRows[index] = RaidCreateRosterRow(panel.rosterListFrame)
    panel.rosterRows[index]:SetPoint("TOPLEFT", lastRow or panel.rosterListFrame, lastRow and "BOTTOMLEFT" or "TOPLEFT", 0, lastRow and -6 or 0)
    panel.rosterRows[index]:SetPoint("TOPRIGHT", lastRow or panel.rosterListFrame, lastRow and "BOTTOMRIGHT" or "TOPRIGHT", 0, lastRow and -6 or 0)
    panel.rosterRows[index].ownerPanel = panel
    lastRow = panel.rosterRows[index]
    index = index + 1
  end
end

local function RaidBuildAdminPane(panel)
  panel.adminPane = RaidCreateInset(panel)
  panel.adminPane:SetPoint("TOPLEFT", panel.summaryText, "BOTTOMLEFT", 0, -8)
  panel.adminPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
  panel.adminPane:Hide()

  panel.adminTitle = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.adminTitle:SetPoint("TOPLEFT", panel.adminPane, "TOPLEFT", 12, -12)
  panel.adminTitle:SetText("|cFFFFD700Create Raid Event|r")

  panel.adminHintText = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.adminHintText:SetPoint("TOPLEFT", panel.adminTitle, "BOTTOMLEFT", 0, -4)
  panel.adminHintText:SetPoint("RIGHT", panel.adminPane, "RIGHT", -12, 0)
  panel.adminHintText:SetJustifyH("LEFT")
  panel.adminHintText:SetJustifyV("TOP")
  panel.adminHintText:SetText("|cFFAAAAAAChoose a raid from the catalog, set the schedule, tune the role targets, then post it for the guild.|r")

  panel.adminPermissionText = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.adminPermissionText:SetPoint("TOPLEFT", panel.adminHintText, "BOTTOMLEFT", 0, -6)
  panel.adminPermissionText:SetPoint("RIGHT", panel.adminPane, "RIGHT", -12, 0)
  panel.adminPermissionText:SetJustifyH("LEFT")
  panel.adminPermissionText:SetJustifyV("TOP")
  panel.adminPermissionText:SetText("")

  panel.raidLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.raidLabel:SetPoint("TOPLEFT", panel.adminPermissionText, "BOTTOMLEFT", 0, -12)
  panel.raidLabel:SetText("Raid")

  panel.raidPrevBtn = CreateFrame("Button", nil, panel.adminPane, "UIPanelButtonTemplate")
  panel.raidPrevBtn:SetWidth(24)
  panel.raidPrevBtn:SetHeight(20)
  panel.raidPrevBtn:SetPoint("TOPLEFT", panel.raidLabel, "BOTTOMLEFT", 0, -4)
  panel.raidPrevBtn:SetText("<")
  panel.raidPrevBtn.ownerPanel = panel
  panel.raidPrevBtn:SetScript("OnClick", function()
    RaidApplyCatalogSelection(this.ownerPanel, -1)
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.selectedRaidNameText = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.selectedRaidNameText:SetPoint("LEFT", panel.raidPrevBtn, "RIGHT", 8, 0)
  panel.selectedRaidNameText:SetWidth(220)
  panel.selectedRaidNameText:SetJustifyH("LEFT")

  panel.raidNextBtn = CreateFrame("Button", nil, panel.adminPane, "UIPanelButtonTemplate")
  panel.raidNextBtn:SetWidth(24)
  panel.raidNextBtn:SetHeight(20)
  panel.raidNextBtn:SetPoint("LEFT", panel.selectedRaidNameText, "RIGHT", 8, 0)
  panel.raidNextBtn:SetText(">")
  panel.raidNextBtn.ownerPanel = panel
  panel.raidNextBtn:SetScript("OnClick", function()
    RaidApplyCatalogSelection(this.ownerPanel, 1)
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  panel.eventTitleLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.eventTitleLabel:SetPoint("TOPLEFT", panel.raidPrevBtn, "BOTTOMLEFT", 0, -12)
  panel.eventTitleLabel:SetText("Event Title")

  panel.eventTitleBG, panel.eventTitleInput = RaidCreateEditBox(panel.adminPane, 260, 22)
  panel.eventTitleBG:SetPoint("TOPLEFT", panel.eventTitleLabel, "BOTTOMLEFT", 0, -4)
  panel.eventTitleInput:SetMaxLetters(40)

  panel.dateLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.dateLabel:SetPoint("TOPLEFT", panel.eventTitleBG, "BOTTOMLEFT", 0, -10)
  panel.dateLabel:SetText("Date")

  panel.dateBG, panel.dateInput = RaidCreateEditBox(panel.adminPane, 98, 22)
  panel.dateBG:SetPoint("TOPLEFT", panel.dateLabel, "BOTTOMLEFT", 0, -4)
  panel.dateInput:SetMaxLetters(10)

  panel.startLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.startLabel:SetPoint("LEFT", panel.dateBG, "RIGHT", 12, 18)
  panel.startLabel:SetText("Start")

  panel.startTimeBG, panel.startTimeInput = RaidCreateEditBox(panel.adminPane, 54, 22)
  panel.startTimeBG:SetPoint("TOPLEFT", panel.startLabel, "BOTTOMLEFT", 0, -4)
  panel.startTimeInput:SetMaxLetters(5)

  panel.closeLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.closeLabel:SetPoint("LEFT", panel.startTimeBG, "RIGHT", 12, 18)
  panel.closeLabel:SetText("Signup Close")

  panel.closeTimeBG, panel.closeTimeInput = RaidCreateEditBox(panel.adminPane, 66, 22)
  panel.closeTimeBG:SetPoint("TOPLEFT", panel.closeLabel, "BOTTOMLEFT", 0, -4)
  panel.closeTimeInput:SetMaxLetters(5)

  panel.sizeLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.sizeLabel:SetPoint("TOPLEFT", panel.dateBG, "BOTTOMLEFT", 0, -10)
  panel.sizeLabel:SetText("Raid Size")

  panel.raidSizeBG, panel.raidSizeInput = RaidCreateEditBox(panel.adminPane, 52, 22)
  panel.raidSizeBG:SetPoint("TOPLEFT", panel.sizeLabel, "BOTTOMLEFT", 0, -4)
  panel.raidSizeInput:SetMaxLetters(2)

  panel.targetHeader = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.targetHeader:SetPoint("TOPLEFT", panel.raidSizeBG, "BOTTOMLEFT", 0, -10)
  panel.targetHeader:SetText("Role Targets")

  panel.roleTargetInputs = {}
  local lastTargetBox = nil
  for _, role in ipairs(RAID_ROLE_ORDER) do
    local label = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if lastTargetBox then
      label:SetPoint("LEFT", lastTargetBox, "RIGHT", 10, 0)
    else
      label:SetPoint("TOPLEFT", panel.targetHeader, "BOTTOMLEFT", 0, -4)
    end
    label:SetText(GetRaidRoleLabel(role))

    local bg, input = RaidCreateEditBox(panel.adminPane, 36, 20)
    bg:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    input:SetJustifyH("CENTER")
    input:SetMaxLetters(2)
    panel.roleTargetInputs[role] = input
    lastTargetBox = bg
  end

  panel.notesInputLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.notesInputLabel:SetPoint("TOPLEFT", panel.targetHeader, "BOTTOMLEFT", 0, -52)
  panel.notesInputLabel:SetText("Notes")

  panel.notesInputBG, panel.notesInput = RaidCreateEditBox(panel.adminPane, 300, 22)
  panel.notesInputBG:SetPoint("TOPLEFT", panel.notesInputLabel, "BOTTOMLEFT", 0, -4)
  panel.notesInput:SetMaxLetters(70)

  panel.bossPreviewLabel = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.bossPreviewLabel:SetPoint("TOPLEFT", panel.raidPrevBtn, "BOTTOMLEFT", 360, 0)
  panel.bossPreviewLabel:SetText("|cFFFFD700Boss Preview|r")

  panel.bossPreviewText = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.bossPreviewText:SetPoint("TOPLEFT", panel.bossPreviewLabel, "BOTTOMLEFT", 0, -6)
  panel.bossPreviewText:SetPoint("RIGHT", panel.adminPane, "RIGHT", -14, 0)
  panel.bossPreviewText:SetHeight(292)
  panel.bossPreviewText:SetJustifyH("LEFT")
  panel.bossPreviewText:SetJustifyV("TOP")

  panel.adminFeedbackText = panel.adminPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.adminFeedbackText:SetPoint("BOTTOMLEFT", panel.adminPane, "BOTTOMLEFT", 12, 16)
  panel.adminFeedbackText:SetPoint("RIGHT", panel.adminPane, "RIGHT", -124, 0)
  panel.adminFeedbackText:SetHeight(32)
  panel.adminFeedbackText:SetJustifyH("LEFT")
  panel.adminFeedbackText:SetJustifyV("BOTTOM")
  panel.adminFeedbackText:SetText("")

  panel.createEventBtn = CreateFrame("Button", nil, panel.adminPane, "UIPanelButtonTemplate")
  panel.createEventBtn:SetWidth(96)
  panel.createEventBtn:SetHeight(22)
  panel.createEventBtn:SetPoint("BOTTOMRIGHT", panel.adminPane, "BOTTOMRIGHT", -12, 12)
  panel.createEventBtn:SetText("Post Raid")
  panel.createEventBtn.ownerPanel = panel
  panel.createEventBtn:SetScript("OnClick", function()
    local owner = this.ownerPanel
    local raidKey = owner.createRaidKey
    if not raidKey or raidKey == "" then
      owner.adminFeedbackText:SetText("|cFFFF6666No raid is selected.|r")
      return
    end

    local startAt, startErr = RaidParseTimestamp(owner.dateInput:GetText() or "", owner.startTimeInput:GetText() or "")
    if not startAt then
      owner.adminFeedbackText:SetText("|cFFFF6666" .. tostring(startErr or "Invalid start time.") .. "|r")
      return
    end

    local closeAt, closeErr = RaidParseTimestamp(owner.dateInput:GetText() or "", owner.closeTimeInput:GetText() or "")
    if not closeAt then
      owner.adminFeedbackText:SetText("|cFFFF6666" .. tostring(closeErr or "Invalid signup close time.") .. "|r")
      return
    end
    if closeAt > startAt then
      closeAt = startAt
    end

    local raidSize = RaidClampNumber(owner.raidSizeInput:GetText() or "", 5, 40, 20)
    owner.raidSizeInput:SetText(tostring(raidSize))

    local roleTargets = {}
    for _, role in ipairs(RAID_ROLE_ORDER) do
      local input = owner.roleTargetInputs and owner.roleTargetInputs[role]
      local value = RaidClampNumber(input and input:GetText() or "", 0, 40, 0)
      roleTargets[role] = value
      if input then
        input:SetText(tostring(value))
      end
    end

    local stored, err = LeafVE:CreateRaidEvent(
      raidKey,
      owner.eventTitleInput:GetText() or "",
      startAt,
      closeAt,
      raidSize,
      roleTargets,
      owner.notesInput and owner.notesInput:GetText() or ""
    )
    if not stored then
      owner.adminFeedbackText:SetText("|cFFFF6666" .. tostring(err or "Unable to create raid event.") .. "|r")
      return
    end

    owner.adminFeedbackText:SetText("|cFF88FF88Raid event posted and synced to the guild.|r")
    owner.mode = "upcoming"
    owner.selectedEventId = stored.id
    owner.selectedRosterPlayer = nil
    owner.lastDetailEventId = nil
    LeafVE.UI:RefreshRaidSignupPanel(true)
  end)

  RaidSeedAdminDefaults(panel)
  RaidApplyCatalogSelection(panel, 0)
end

function BuildRaidSignupPanel(panel)
  if not panel or panel.isBuilt then
    return
  end

  panel.isBuilt = true
  panel.mode = "upcoming"
  panel.eventOffset = 0
  panel.rosterOffset = 0
  panel.visibleEvents = {}
  panel.visibleRosterRows = {}

  RaidBuildModeButtons(panel)
  RaidBuildEventPane(panel)
  RaidBuildDetailPane(panel)
  RaidBuildRosterPane(panel)
  RaidBuildAdminPane(panel)

  panel:SetScript("OnShow", function()
    LeafVE.UI:RefreshRaidSignupPanel()
  end)
end

function LeafVE.UI:RefreshRaidSignupEventList(panel, eventRows)
  panel.visibleEvents = eventRows or {}

  local totalRows = table.getn(panel.visibleEvents)
  local visibleRows = panel.eventVisibleRows or RAID_EVENT_ROW_COUNT
  local maxOffset = math.max(0, totalRows - visibleRows)
  if (panel.eventOffset or 0) > maxOffset then
    panel.eventOffset = maxOffset
  end

  panel.eventScrollBar.ignoreUpdate = true
  panel.eventScrollBar:SetMinMaxValues(0, maxOffset)
  panel.eventScrollBar:SetValue(panel.eventOffset or 0)
  panel.eventScrollBar.ignoreUpdate = nil

  panel.noEventsText:SetText(totalRows == 0 and "|cFF888888No raid events are cached yet.|r" or "")

  local index = 1
  while index <= table.getn(panel.eventRows or {}) do
    local row = panel.eventRows[index]
    local eventRecord = panel.visibleEvents[(panel.eventOffset or 0) + index]
    if row and eventRecord then
      local counts = LeafVE:GetRaidRosterCounts(eventRecord.id)
      row.eventRecord = eventRecord
      row.isSelected = tostring(eventRecord.id or "") == tostring(panel.selectedEventId or "")
      row.titleText:SetText("|cFFFFD700" .. tostring(eventRecord.title or eventRecord.raidName or "Raid Event") .. "|r")
      row.statusText:SetText(RaidFormatEventStatus(eventRecord.status))
      row.metaText:SetText(
        tostring(eventRecord.raidName or "Raid")
          .. "  "
          .. RaidFormatTime(eventRecord.startAt)
          .. "  "
          .. tostring(counts.total or 0)
          .. "/"
          .. tostring(tonumber(eventRecord.raidSize) or 20)
      )
      row.needText:SetText(LeafVE:GetRaidNeedSummary(eventRecord))
      if row.isSelected then
        row:SetBackdropBorderColor(1, 0.82, 0.08, 0.95)
      else
        row:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.8)
      end
      row:Show()
    elseif row then
      row.eventRecord = nil
      row.isSelected = nil
      row:Hide()
    end
    index = index + 1
  end
end

function LeafVE.UI:RefreshRaidSignupDetails(panel, eventRecord)
  if not eventRecord then
    panel.detailTitle:SetText("|cFFFFD700Raid Details|r")
    panel.detailMeta:SetText("|cFF888888Select a raid event from the left list.|r")
    panel.detailNeed:SetText("")
    panel.notesText:SetText("|cFF888888No raid notes yet.|r")
    panel.bossesText:SetText("|cFF888888No boss list loaded.|r")
    panel.signupStateText:SetText("|cFF888888No signup saved for this raid yet.|r")
    panel.detailFeedbackText:SetText("")
    if panel.signupNoteInput then
      panel.signupNoteInput:SetText("")
    end
    RaidApplyPanelButtonColor(panel.managerOpenBtn, false)
    RaidApplyPanelButtonColor(panel.managerLockBtn, false)
    RaidApplyPanelButtonColor(panel.managerCompleteBtn, false)
    RaidApplyPanelButtonColor(panel.managerCancelBtn, false)
    RaidApplyPanelButtonColor(panel.withdrawBtn, false)
    RaidApplyPanelButtonColor(panel.saveSignupBtn, false)
    for _, role in ipairs(RAID_ROLE_ORDER) do
      RaidApplyRoleButtonState(panel.roleButtons and panel.roleButtons[role], false)
    end
    for _, signupStatus in ipairs(RAID_STATUS_ORDER) do
      RaidApplyRoleButtonState(panel.statusButtons and panel.statusButtons[signupStatus], false)
    end
    return
  end

  local me = RaidShortName(UnitName("player"))
  local mySignup = me and LeafVE:FindRaidSignupRecord(eventRecord.id, me) or nil
  local canManage = LeafVE:CanManageRaidEvent(eventRecord, me)
  local eventStatus = NormalizeRaidEventStatus(eventRecord.status)
  local isClosed = eventStatus == "completed" or eventStatus == "cancelled" or eventStatus == "archived"

  if panel.lastDetailEventId ~= eventRecord.id then
    panel.selectedRole = NormalizeRaidRole(mySignup and mySignup.preferredRole or LeafVE:GetSuggestedRaidRoleForPlayer(me))
    panel.selectedSignupStatus = NormalizeRaidSignupStatus(mySignup and mySignup.signupStatus or "going")
    if panel.signupNoteInput then
      panel.signupNoteInput:SetText(mySignup and (mySignup.note or "") or "")
    end
    panel.lastDetailEventId = eventRecord.id
  end

  panel.detailTitle:SetText("|cFFFFD700" .. tostring(eventRecord.title or eventRecord.raidName or "Raid Details") .. "|r")
  panel.detailMeta:SetText(
    tostring(eventRecord.raidName or "Raid")
      .. "  "
      .. RaidFormatEventStatus(eventStatus)
      .. "\nLead: "
      .. tostring(eventRecord.postedBy or "")
      .. "  Start: "
      .. RaidFormatTime(eventRecord.startAt)
      .. "  Close: "
      .. RaidFormatTime(eventRecord.signupCloseAt)
      .. "\n"
      .. RaidFormatCountdown(eventRecord.startAt)
  )
  panel.detailNeed:SetText(LeafVE:GetRaidNeedSummary(eventRecord))
  panel.notesText:SetText((eventRecord.notes and eventRecord.notes ~= "") and tostring(eventRecord.notes) or "|cFF888888No raid notes yet.|r")
  panel.bossesText:SetText(LeafVE:GetRaidBossListText(eventRecord.raidKey))

  if mySignup then
    panel.signupStateText:SetText(
      tostring(mySignup.specName or mySignup.classTag or "")
        .. "  "
        .. RaidFormatSignupStatus(mySignup.signupStatus)
        .. "  "
        .. RaidFormatRosterStatus(mySignup.rosterStatus)
    )
  else
    panel.signupStateText:SetText("|cFF888888No signup saved for this raid yet.|r")
  end

  RaidApplyPanelButtonColor(panel.managerOpenBtn, canManage)
  RaidApplyPanelButtonColor(panel.managerLockBtn, canManage)
  RaidApplyPanelButtonColor(panel.managerCompleteBtn, canManage)
  RaidApplyPanelButtonColor(panel.managerCancelBtn, canManage)
  RaidApplyPanelButtonColor(panel.withdrawBtn, not isClosed)
  RaidApplyPanelButtonColor(panel.saveSignupBtn, not isClosed)

  for _, role in ipairs(RAID_ROLE_ORDER) do
    RaidApplyRoleButtonState(panel.roleButtons and panel.roleButtons[role], NormalizeRaidRole(panel.selectedRole) == role)
  end
  for _, signupStatus in ipairs(RAID_STATUS_ORDER) do
    RaidApplyRoleButtonState(panel.statusButtons and panel.statusButtons[signupStatus], NormalizeRaidSignupStatus(panel.selectedSignupStatus) == signupStatus)
  end
end

function LeafVE.UI:RefreshRaidSignupRoster(panel, eventRecord)
  local canManage = eventRecord and LeafVE:CanManageRaidEvent(eventRecord) or false

  if not eventRecord then
    panel.visibleRosterRows = {}
    panel.rosterSummaryText:SetText("|cFF888888Select a raid event to view signups.|r")
    panel.selectedRosterText:SetText("")
    panel.rosterFeedbackText:SetText("")
    panel.noRosterText:SetText("|cFF888888No sign-ups recorded for this raid yet.|r")
    RaidApplyPanelButtonColor(panel.rosterConfirmBtn, false)
    RaidApplyPanelButtonColor(panel.rosterBenchBtn, false)
    RaidApplyPanelButtonColor(panel.rosterResetBtn, false)
    for _, row in ipairs(panel.rosterRows or {}) do
      row:Hide()
    end
    return
  end

  panel.visibleRosterRows = LeafVE:GetRaidSignupsForEvent(eventRecord.id, true)
  local counts = LeafVE:GetRaidRosterCounts(eventRecord.id)
  panel.rosterSummaryText:SetText(
    string.format(
      "Total %d/%d  Confirmed %d  Bench %d\nTank %d  Healer %d  Melee %d  Ranged %d  Flex %d",
      counts.total or 0,
      tonumber(eventRecord.raidSize) or 20,
      counts.confirmed or 0,
      counts.bench or 0,
      counts.tank or 0,
      counts.healer or 0,
      counts.melee or 0,
      counts.ranged or 0,
      counts.flex or 0
    )
  )

  local selectedRecord = nil
  if panel.selectedRosterPlayer then
    for _, signup in ipairs(panel.visibleRosterRows) do
      if RaidSamePlayerName(signup.player, panel.selectedRosterPlayer) then
        selectedRecord = signup
        break
      end
    end
  end
  if not selectedRecord and table.getn(panel.visibleRosterRows) > 0 then
    selectedRecord = panel.visibleRosterRows[1]
    panel.selectedRosterPlayer = selectedRecord.player
  end

  if selectedRecord then
    panel.selectedRosterText:SetText(
      tostring(selectedRecord.player or "")
        .. "  "
        .. GetRaidRoleLabel(selectedRecord.preferredRole)
        .. "  "
        .. RaidFormatSignupStatus(selectedRecord.signupStatus)
        .. "  "
        .. RaidFormatRosterStatus(selectedRecord.rosterStatus)
    )
  else
    panel.selectedRosterText:SetText("|cFF888888No signup selected.|r")
  end

  RaidApplyPanelButtonColor(panel.rosterConfirmBtn, canManage and selectedRecord ~= nil)
  RaidApplyPanelButtonColor(panel.rosterBenchBtn, canManage and selectedRecord ~= nil)
  RaidApplyPanelButtonColor(panel.rosterResetBtn, canManage and selectedRecord ~= nil)

  local totalRows = table.getn(panel.visibleRosterRows)
  local visibleRows = panel.rosterVisibleRows or RAID_ROSTER_ROW_COUNT
  local maxOffset = math.max(0, totalRows - visibleRows)
  if (panel.rosterOffset or 0) > maxOffset then
    panel.rosterOffset = maxOffset
  end

  panel.rosterScrollBar.ignoreUpdate = true
  panel.rosterScrollBar:SetMinMaxValues(0, maxOffset)
  panel.rosterScrollBar:SetValue(panel.rosterOffset or 0)
  panel.rosterScrollBar.ignoreUpdate = nil

  panel.noRosterText:SetText(totalRows == 0 and "|cFF888888No sign-ups recorded for this raid yet.|r" or "")

  local index = 1
  while index <= table.getn(panel.rosterRows or {}) do
    local row = panel.rosterRows[index]
    local signup = panel.visibleRosterRows[(panel.rosterOffset or 0) + index]
    if row and signup then
      local classColor = RaidGetClassColor(signup.classTag)
      row.signupRecord = signup
      row.isSelected = selectedRecord and RaidSamePlayerName(signup.player, selectedRecord.player) or false
      row.nameText:SetText(
        "|cff"
          .. string.format("%02x%02x%02x", math.floor(classColor[1] * 255), math.floor(classColor[2] * 255), math.floor(classColor[3] * 255))
          .. tostring(signup.player or "")
          .. "|r"
      )
      row.metaText:SetText(
        tostring(signup.specName or signup.classTag or "")
          .. "  "
          .. GetRaidRoleLabel(signup.preferredRole)
          .. "  "
          .. RaidFormatSignupStatus(signup.signupStatus)
          .. "  "
          .. RaidFormatRosterStatus(signup.rosterStatus)
          .. ((signup.note and signup.note ~= "") and ("\n" .. tostring(signup.note)) or "")
      )
      if row.isSelected then
        row:SetBackdropBorderColor(1, 0.82, 0.08, 0.95)
      else
        row:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.8)
      end
      row:Show()
    elseif row then
      row.signupRecord = nil
      row.isSelected = nil
      row:Hide()
    end
    index = index + 1
  end
end

function LeafVE.UI:RefreshRaidSignupAdminForm(panel)
  RaidSeedAdminDefaults(panel)
  RaidApplyCatalogSelection(panel, 0)

  local canCreate = LeafVE:IsRaidOrganizerRank()
  if canCreate then
    panel.adminPermissionText:SetText("|cFF88FF88Jonin, Anbu, Sannin, and Hokage can post guild raid events here.|r")
  else
    panel.adminPermissionText:SetText("|cFFFF6666Only Jonin, Anbu, Sannin, and Hokage can post raid events. Everyone else can still use Upcoming and My Sign-Ups.|r")
  end

  local catalogEntry = LeafVE:GetRaidCatalogEntry(panel.createRaidKey)
  panel.selectedRaidNameText:SetText(catalogEntry and catalogEntry.name or "No raids loaded")
  panel.bossPreviewText:SetText(catalogEntry and LeafVE:GetRaidBossListText(catalogEntry.key) or "|cFF888888No raid catalog available.|r")

  RaidApplyPanelButtonColor(panel.raidPrevBtn, canCreate)
  RaidApplyPanelButtonColor(panel.raidNextBtn, canCreate)
  RaidApplyPanelButtonColor(panel.createEventBtn, canCreate)

  if panel.eventTitleInput then
    panel.eventTitleInput:EnableKeyboard(canCreate)
    panel.eventTitleInput:SetTextColor(canCreate and 1 or 0.6, canCreate and 1 or 0.6, canCreate and 1 or 0.6)
  end
  if panel.dateInput then
    panel.dateInput:EnableKeyboard(canCreate)
    panel.dateInput:SetTextColor(canCreate and 1 or 0.6, canCreate and 1 or 0.6, canCreate and 1 or 0.6)
  end
  if panel.startTimeInput then
    panel.startTimeInput:EnableKeyboard(canCreate)
    panel.startTimeInput:SetTextColor(canCreate and 1 or 0.6, canCreate and 1 or 0.6, canCreate and 1 or 0.6)
  end
  if panel.closeTimeInput then
    panel.closeTimeInput:EnableKeyboard(canCreate)
    panel.closeTimeInput:SetTextColor(canCreate and 1 or 0.6, canCreate and 1 or 0.6, canCreate and 1 or 0.6)
  end
  if panel.raidSizeInput then
    panel.raidSizeInput:EnableKeyboard(canCreate)
    panel.raidSizeInput:SetTextColor(canCreate and 1 or 0.6, canCreate and 1 or 0.6, canCreate and 1 or 0.6)
  end
  if panel.notesInput then
    panel.notesInput:EnableKeyboard(canCreate)
    panel.notesInput:SetTextColor(canCreate and 1 or 0.6, canCreate and 1 or 0.6, canCreate and 1 or 0.6)
  end
  if panel.roleTargetInputs then
    for _, role in ipairs(RAID_ROLE_ORDER) do
      local input = panel.roleTargetInputs[role]
      if input then
        input:EnableKeyboard(canCreate)
        input:SetTextColor(canCreate and 1 or 0.6, canCreate and 1 or 0.6, canCreate and 1 or 0.6)
      end
    end
  end
end

function LeafVE.UI:RefreshRaidSignupPanel(skipRequest)
  local panel = self.panels and self.panels.raidSignups
  if not panel then
    return
  end

  if not skipRequest then
    LeafVE:RequestRaidSignupSync(false)
  end

  RaidApplyRoleButtonState(panel.modeUpcomingBtn, panel.mode == "upcoming")
  RaidApplyRoleButtonState(panel.modeMineBtn, panel.mode == "mine")
  RaidApplyRoleButtonState(panel.modeAdminBtn, panel.mode == "admin")

  if panel.mode == "admin" then
    panel.eventsPane:Hide()
    panel.detailPane:Hide()
    panel.rosterPane:Hide()
    panel.adminPane:Show()
    panel.summaryText:SetText("|cFF88CCFFRaid Sign-Ups|r lets Jonin+ post guild raid events and lets the whole guild sign up against live roster targets.")
    self:RefreshRaidSignupAdminForm(panel)
    return
  end

  panel.eventsPane:Show()
  panel.detailPane:Show()
  panel.rosterPane:Show()
  panel.adminPane:Hide()

  local eventRows = LeafVE:GetVisibleRaidEvents(panel.mode == "mine" and "mine" or "all")
  if panel.mode == "mine" then
    panel.summaryText:SetText("|cFF88CCFFMy Sign-Ups|r  " .. tostring(table.getn(eventRows)) .. " active raids with your signup saved.")
    panel.eventsTitle:SetText("|cFFFFD700My Raid Events|r")
  else
    panel.summaryText:SetText("|cFF88CCFFUpcoming Raids|r  " .. tostring(table.getn(eventRows)) .. " events cached across the guild.")
    panel.eventsTitle:SetText("|cFFFFD700Upcoming Raids|r")
  end

  if panel.selectedEventId and not RaidFindEventById(eventRows, panel.selectedEventId) then
    panel.selectedEventId = nil
    panel.selectedRosterPlayer = nil
    panel.lastDetailEventId = nil
  end
  if not panel.selectedEventId and table.getn(eventRows) > 0 then
    panel.selectedEventId = eventRows[1].id
  end

  panel.selectedEvent = RaidFindEventById(eventRows, panel.selectedEventId)

  self:RefreshRaidSignupEventList(panel, eventRows)
  self:RefreshRaidSignupDetails(panel, panel.selectedEvent)
  self:RefreshRaidSignupRoster(panel, panel.selectedEvent)
end
