-- ChatFilter Addon for WoW 3.3.5a
-- Filters channel messages and provides GUI interface

local addonName = "ChatFilter"
local ChatFilter = {}
ChatFilter.version = "1.0"

-- Saved variables
ChatFilter_DB = ChatFilter_DB or {
    minimapPos = 45,
    filters = {},
    capturedMessages = {},
    maxMessages = 100
}

-- Local variables
local db = ChatFilter_DB
local mainFrame = nil
local minimapButton = nil
local currentChannel = nil
local channelList = {}
local activeFilter = ""

-- Initialize addon
local function Initialize()
    print("|cFF00FF00ChatFilter|r v" .. ChatFilter.version .. " loaded. Click minimap button to configure.")

    -- Create minimap button
    CreateMinimapButton()

    -- Register chat events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", OnChatEvent)
end

-- Event handler for chat messages
function OnChatEvent(self, event, ...)
    if event == "CHAT_MSG_CHANNEL" then
        local message, sender, _, _, _, _, _, channelNumber, channelName = ...

        -- Store the message
        local fullChannelName = channelNumber .. ". " .. channelName
        if not db.capturedMessages[fullChannelName] then
            db.capturedMessages[fullChannelName] = {}
        end

        local msgData = {
            message = message,
            sender = sender,
            time = date("%H:%M:%S"),
            timestamp = time()
        }

        table.insert(db.capturedMessages[fullChannelName], msgData)

        -- Keep only last maxMessages
        while #db.capturedMessages[fullChannelName] > db.maxMessages do
            table.remove(db.capturedMessages[fullChannelName], 1)
        end

        -- Refresh display if this channel is currently shown
        if mainFrame and mainFrame:IsShown() and currentChannel == fullChannelName then
            RefreshMessageList()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateChannelList()
    end
end

-- Create minimap button
function CreateMinimapButton()
    minimapButton = CreateFrame("Button", "ChatFilterMinimapButton", Minimap)
    minimapButton:SetWidth(31)
    minimapButton:SetHeight(31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Create icon texture
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("CENTER", 0, 1)
    minimapButton.icon = icon

    -- Create border
    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    -- Position on minimap
    UpdateMinimapButtonPosition()

    -- Click handler
    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            ToggleMainFrame()
        end
    end)

    -- Drag functionality
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", UpdateMinimapButtonPosition)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        UpdateMinimapButtonPosition()
    end)

    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cFF00FF00ChatFilter|r")
        GameTooltip:AddLine("Left-click to open", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

-- Update minimap button position
function UpdateMinimapButtonPosition()
    local angle = math.rad(db.minimapPos or 45)
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)

    -- Update angle based on mouse position when dragging
    if minimapButton:GetScript("OnUpdate") then
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        db.minimapPos = math.deg(math.atan2(py - my, px - mx))
    end
end

-- Toggle main frame
function ToggleMainFrame()
    if not mainFrame then
        CreateMainFrame()
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        UpdateChannelList()
        mainFrame:Show()
    end
end

-- Create main GUI frame
function CreateMainFrame()
    mainFrame = CreateFrame("Frame", "ChatFilterMainFrame", UIParent)
    mainFrame:SetWidth(700)
    mainFrame:SetHeight(450)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    mainFrame:SetBackdropColor(0, 0, 0, 0.95)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:Hide()

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFF00FF00Chat Filter|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Channel dropdown
    local channelLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelLabel:SetPoint("TOPLEFT", 20, -45)
    channelLabel:SetText("Select Channel:")

    local channelDropdown = CreateFrame("Frame", "ChatFilterChannelDropdown", mainFrame, "UIDropDownMenuTemplate")
    channelDropdown:SetPoint("TOPLEFT", 15, -60)
    UIDropDownMenu_SetWidth(channelDropdown, 200)
    UIDropDownMenu_SetText(channelDropdown, "Select a channel")

    UIDropDownMenu_Initialize(channelDropdown, function(self, level)
        for _, channelName in ipairs(channelList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = channelName
            info.func = function()
                currentChannel = channelName
                UIDropDownMenu_SetText(channelDropdown, channelName)
                RefreshMessageList()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    mainFrame.channelDropdown = channelDropdown

    -- Filter input
    local filterLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("TOPLEFT", 270, -45)
    filterLabel:SetText("Filter Text:")

    local filterBox = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
    filterBox:SetPoint("TOPLEFT", 270, -65)
    filterBox:SetWidth(200)
    filterBox:SetHeight(20)
    filterBox:SetAutoFocus(false)
    filterBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        activeFilter = self:GetText()
        RefreshMessageList()
    end)
    filterBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    mainFrame.filterBox = filterBox

    -- Apply filter button
    local applyBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    applyBtn:SetPoint("LEFT", filterBox, "RIGHT", 10, 0)
    applyBtn:SetWidth(80)
    applyBtn:SetHeight(22)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function()
        activeFilter = filterBox:GetText()
        RefreshMessageList()
    end)

    -- Clear filter button
    local clearBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    clearBtn:SetPoint("LEFT", applyBtn, "RIGHT", 5, 0)
    clearBtn:SetWidth(60)
    clearBtn:SetHeight(22)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        filterBox:SetText("")
        activeFilter = ""
        RefreshMessageList()
    end)

    -- Scrolling message list
    local scrollFrame = CreateFrame("ScrollFrame", "ChatFilterScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -100)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 20)

    local messageList = CreateFrame("Frame", nil, scrollFrame)
    messageList:SetWidth(scrollFrame:GetWidth())
    messageList:SetHeight(1)
    scrollFrame:SetScrollChild(messageList)
    mainFrame.messageList = messageList

    RefreshMessageList()
end

-- Update channel list
function UpdateChannelList()
    channelList = {}
    for channelName, _ in pairs(db.capturedMessages) do
        table.insert(channelList, channelName)
    end
    table.sort(channelList)

    -- Also add currently joined channels even if no messages yet
    for i = 1, 10 do
        local id, name = GetChannelName(i)
        if id > 0 then
            local fullName = id .. ". " .. name
            local found = false
            for _, existing in ipairs(channelList) do
                if existing == fullName then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(channelList, fullName)
                db.capturedMessages[fullName] = db.capturedMessages[fullName] or {}
            end
        end
    end
    table.sort(channelList)
end

-- Refresh message list
function RefreshMessageList()
    if not mainFrame or not mainFrame.messageList then return end

    -- Clear existing messages
    local messageList = mainFrame.messageList
    for _, child in ipairs({messageList:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    if not currentChannel or not db.capturedMessages[currentChannel] then
        return
    end

    local filterText = activeFilter
    if filterText then
        filterText = string.lower(filterText)
    end

    local messages = db.capturedMessages[currentChannel]
    local yOffset = 0
    local displayedCount = 0

    -- Display messages in reverse order (newest first)
    for i = #messages, 1, -1 do
        local msgData = messages[i]

        -- Apply filter
        if not filterText or filterText == "" or string.find(string.lower(msgData.message), filterText, 1, true) then
            local msgFrame = CreateFrame("Frame", nil, messageList)
            msgFrame:SetPoint("TOPLEFT", 5, -yOffset)
            msgFrame:SetWidth(messageList:GetWidth() - 10)
            msgFrame:SetHeight(40)

            -- Time and sender (clickable)
            local senderBtn = CreateFrame("Button", nil, msgFrame)
            senderBtn:SetPoint("TOPLEFT", 0, 0)
            senderBtn:SetHeight(15)
            
            local header = senderBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            header:SetPoint("TOPLEFT", 0, 0)
            header:SetText("|cFFFFFF00[" .. msgData.time .. "]|r |cFF00FFFF" .. msgData.sender .. "|r:")
            header:SetJustifyH("LEFT")
            
            senderBtn:SetWidth(header:GetStringWidth())
            senderBtn:RegisterForClicks("RightButtonUp")
            senderBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    ChatFrame_SendTell(msgData.sender)
                end
            end)
            senderBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText("Right-click to whisper " .. msgData.sender)
                GameTooltip:Show()
            end)
            senderBtn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)

            -- Message text
            local msgText = msgFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            msgText:SetPoint("TOPLEFT", 0, -15)
            msgText:SetPoint("RIGHT", -5, 0)
            msgText:SetJustifyH("LEFT")
            msgText:SetWordWrap(true)
            msgText:SetText(msgData.message)

            local textHeight = msgText:GetStringHeight()
            msgFrame:SetHeight(20 + textHeight)

            yOffset = yOffset + msgFrame:GetHeight() + 5
            displayedCount = displayedCount + 1
        end
    end

    messageList:SetHeight(math.max(yOffset, 1))

    -- Show count
    if displayedCount == 0 and filterText and filterText ~= "" then
        local noResults = messageList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noResults:SetPoint("TOP", 0, -20)
        noResults:SetText("|cFFFF0000No messages match the filter|r")
    end
end

-- Initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if addon == addonName then
        Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
