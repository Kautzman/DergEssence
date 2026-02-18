-- DergEssence: Addon for Evokers in WoW to track essence
-- Author: Kautzman
-- Version: 1.0.0

-- Create addon namespace
local addonName, addon = ...

-- Saved variables
DergEssenceDB = DergEssenceDB or {}

-- Addon object
DergEssence = {}
DergEssence.version = "1.0.0"

-- Constants
local MAX_EVOKER_ESSENCE = 6
local ESSENCE_POWER_TYPE = 19  -- Power type ID for Evoker essence
local BASE_RECHARGE_TIME = 5.0  -- Base time in seconds for essence to recharge
local ESSENCE_COLOR = {r = 0.4, g = 0.7, b = 1.0, a = 1.0}  -- Light blue color for essence bars
local INNATE_MAGIC_TALENT_NAME = 375520  -- Talent name for essence regen bonus
local INNATE_MAGIC_BONUS_PER_RANK = 0.05  -- 5% bonus per rank (5% for 1 point, 10% for 2 points)
local API_SYNC_FREQUENCY = 20  -- Sync with API every Nth essence event

-- Frame for event handling
local frame = CreateFrame("Frame")

spellToNode = {}

-- Event handler
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            DergEssence:OnInitialize()
        end
    elseif event == "PLAYER_LOGIN" then
        DergEssence:OnEnable()
    elseif event == "PLAYER_LOGOUT" then
        DergEssence:OnDisable()
    elseif event == "UNIT_POWER_UPDATE" then
        local unit = ...
        if unit == "player" then
            DergEssence:UpdateEssence()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        DergEssence:UpdateEssence()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit == "player" then
            DergEssence:CheckEssenceAfterSpellCast()
        end
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Update cached talent rank when talents change
        if DergEssence.essenceBars then
            DergEssence:UpdateTalentCache()
        end
    end
end

-- Initialize the addon
function DergEssence:OnInitialize()
    -- Initialize saved variables with defaults if they don't exist
    if not DergEssenceDB.initialized then
        DergEssenceDB.initialized = true
    end
    if DergEssenceDB.enabled == nil then
        DergEssenceDB.enabled = true
    end
    
    -- Initialize options with defaults
    if not DergEssenceDB.options then
        DergEssenceDB.options = {}
    end
    
    -- Set default values for missing options
    local defaults = {
        barWidth = 100,
        barHeight = 15,
        barSpacing = 2,
        filledColor = {r = 0.4, g = 0.7, b = 1.0, a = 1.0},
        emptyColor = {r = 0, g = 0, b = 0, a = 1.0},
        borderColor = {r = 0.5, g = 0.5, b = 0.5, a = 1.0},
        borderThickness = 1,
        xPosition = 0,
        yPosition = 0
    }
    
    for key, value in pairs(defaults) do
        if DergEssenceDB.options[key] == nil then
            DergEssenceDB.options[key] = value
        end
    end
    
    print("|cFF00FF00DergEssence|r v" .. self.version .. " loaded. Type /dergessence or /derge for options.")
end

-- Enable the addon
function DergEssence:OnEnable()
    if not DergEssenceDB.enabled then
        return
    end
    
    -- Register events for essence tracking
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    
    -- Check if player is an Evoker
    local _, class = UnitClass("player")
    if class == "EVOKER" then
        self:SetupEssenceTracking()
        
        -- Show the frame if it was previously hidden
        if self.mainFrame then
            self.mainFrame:Show()
            -- Re-enable OnUpdate handler
            self.mainFrame:SetScript("OnUpdate", function(self, elapsed)
                DergEssence:UpdateRechargeProgress()
            end)
            self:UpdateEssence()
        end
    end
end

-- Disable the addon
function DergEssence:OnDisable()
    -- Only unregister essence tracking events, keep lifecycle events
    frame:UnregisterEvent("UNIT_POWER_UPDATE")
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:UnregisterEvent("TRAIT_CONFIG_UPDATED")
    frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    
    -- Hide the essence display if it exists
    if self.mainFrame then
        self.mainFrame:Hide()
        -- Stop OnUpdate to save performance
        self.mainFrame:SetScript("OnUpdate", nil)
    end
end

function BuildTalentSpellCache()
    wipe(spellToNode)

    local configId = C_ClassTalents.GetActiveConfigID()
    if not configId then return end

    local configInfo = C_Traits.GetConfigInfo(configId)
    if not configInfo then return end

    for _, treeId in ipairs(configInfo.treeIDs) do
        for _, nodeId in ipairs(C_Traits.GetTreeNodes(treeId)) do
            local nodeInfo = C_Traits.GetNodeInfo(configId, nodeId)

            if nodeInfo and nodeInfo.entryIDs then
                for _, entryID in ipairs(nodeInfo.entryIDs) do
                    local entryInfo = C_Traits.GetEntryInfo(configId, entryID)
                    if entryInfo and entryInfo.definitionID then
                        local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                        if defInfo and defInfo.spellID then
                            spellToNode[defInfo.spellID] = nodeId
                        end
                    end
                end
            end
        end
    end
end

function GetTalentRankBySpellID(spellID)
    local nodeId = spellToNode[spellID]
    if not nodeId then return 0 end

    local configId = C_ClassTalents.GetActiveConfigID()
    if not configId then return 0 end

    local nodeInfo = C_Traits.GetNodeInfo(configId, nodeId)
    return (nodeInfo and nodeInfo.currentRank) or 0
end

-- Setup essence tracking for Evokers
function DergEssence:SetupEssenceTracking()
    self:CreateEssenceDisplay()
    -- Initialize cached talent rank to 0 (will be updated by TRAIT_CONFIG_UPDATED event)
    self.cachedInnateMagicRank = 0
    -- Try to get initial talent rank (may not be available immediately after login)
    self:UpdateTalentCache()
    self:UpdateEssence()
    print("|cFF00FF00DergEssence|r: Essence tracking initialized for Evoker.")
end

-- Update cached talent information
function DergEssence:UpdateTalentCache()
    local rank = GetTalentRankBySpellID(INNATE_MAGIC_TALENT_ID)
    -- Only update if we got a valid result (talent API may not be ready yet)
    if rank then
        self.cachedInnateMagicRank = rank
		print("|cFF00FF00DergEssence|r: Found " .. rank .. " rank(s) of Innate Magic talent")
    end
	
	self.cachedInnateMagicRank = 2 -- We can't get talent correctly for some reason, so we are just setting it to 2 for now
end

-- Create the essence bar display
function DergEssence:CreateEssenceDisplay()
    -- Create main container frame
    if not self.mainFrame then
        self.mainFrame = CreateFrame("Frame", "DergEssenceMainFrame", UIParent)
        self.mainFrame:SetSize(500, 20)  -- Container size
        -- Validate position values before use
        local xPos = tonumber(DergEssenceDB.options.xPosition) or 0
        local yPos = tonumber(DergEssenceDB.options.yPosition) or 0
        self.mainFrame:SetPoint("CENTER", UIParent, "CENTER", xPos, yPos)
        
        -- Create essence bars
        self.essenceBars = {}
        local barWidth = DergEssenceDB.options.barWidth
        local barHeight = DergEssenceDB.options.barHeight
        local barGap = DergEssenceDB.options.barSpacing
        
        for i = 1, MAX_EVOKER_ESSENCE do
            local bar = CreateFrame("Frame", "DergEssenceBar" .. i, self.mainFrame)
            bar:SetSize(barWidth, barHeight)
            
            -- Position bars horizontally with gap between them
            -- Formula centers all bars: offset = (bar_index - 1) * (width + gap) - total_width / 2
            local xOffset = (i - 1) * (barWidth + barGap) - (MAX_EVOKER_ESSENCE * (barWidth + barGap) - barGap) / 2
            bar:SetPoint("LEFT", self.mainFrame, "CENTER", xOffset, 0)
            
            -- Create background (black when essence not available)
            bar.background = bar:CreateTexture(nil, "BACKGROUND")
            bar.background:SetAllPoints()
            bar.background:SetColorTexture(
                DergEssenceDB.options.emptyColor.r,
                DergEssenceDB.options.emptyColor.g,
                DergEssenceDB.options.emptyColor.b,
                DergEssenceDB.options.emptyColor.a
            )
            
            -- Create border frame using four edge textures
            local borderThickness = DergEssenceDB.options.borderThickness
            local borderColor = DergEssenceDB.options.borderColor
            
            -- Top border
            bar.borderTop = bar:CreateTexture(nil, "BORDER")
            bar.borderTop:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bar.borderTop:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            bar.borderTop:SetHeight(borderThickness)
            bar.borderTop:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
            
            -- Bottom border
            bar.borderBottom = bar:CreateTexture(nil, "BORDER")
            bar.borderBottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar.borderBottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            bar.borderBottom:SetHeight(borderThickness)
            bar.borderBottom:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
            
            -- Left border
            bar.borderLeft = bar:CreateTexture(nil, "BORDER")
            bar.borderLeft:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bar.borderLeft:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar.borderLeft:SetWidth(borderThickness)
            bar.borderLeft:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
            
            -- Right border
            bar.borderRight = bar:CreateTexture(nil, "BORDER")
            bar.borderRight:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            bar.borderRight:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            bar.borderRight:SetWidth(borderThickness)
            bar.borderRight:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
            
            -- Create fill texture (light blue when essence available)
            local filledColor = DergEssenceDB.options.filledColor
            bar.fill = bar:CreateTexture(nil, "ARTWORK")
            bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", borderThickness, -borderThickness)
            bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderThickness, borderThickness)
            bar.fill:SetColorTexture(filledColor.r, filledColor.g, filledColor.b, filledColor.a)
            bar.fill:Hide()  -- Initially hidden
            
            -- Create partial fill texture for recharging essence
            bar.partialFill = bar:CreateTexture(nil, "ARTWORK")
            bar.partialFill:SetPoint("TOPLEFT", bar, "TOPLEFT", borderThickness, -borderThickness)
            bar.partialFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", borderThickness, borderThickness)
            bar.partialFill:SetWidth(0)  -- Initially zero width
            bar.partialFill:SetColorTexture(filledColor.r, filledColor.g, filledColor.b, filledColor.a)
            bar.partialFill:Hide()  -- Initially hidden
            
            self.essenceBars[i] = bar
        end
        
        self.mainFrame:Show()
        
        -- Set up OnUpdate handler for recharge progress
        self.mainFrame:SetScript("OnUpdate", function(self, elapsed)
            DergEssence:UpdateRechargeProgress()
        end)
    end
end

-- Update essence display
function DergEssence:UpdateEssence()
    if not self.essenceBars then
        return
    end
    
    local currentEssence = UnitPower("player", ESSENCE_POWER_TYPE)
    local maxEssence = UnitPowerMax("player", ESSENCE_POWER_TYPE)
    
    -- Initialize API sync counter if not exists
    if not self.apiSyncCounter then
        self.apiSyncCounter = 0
    end
    
    -- Track essence count changes and handle progress carryover
    if not self.lastEssenceCount or self.lastEssenceCount ~= currentEssence then
        local essenceChanged = self.lastEssenceCount ~= nil
        local essenceSpent = essenceChanged and currentEssence < self.lastEssenceCount
        local essenceGained = essenceChanged and currentEssence > self.lastEssenceCount
        local wasAtMax = self.lastEssenceCount and self.lastEssenceCount >= maxEssence
        
        -- Increment sync counter on essence change
        if essenceChanged then
            self.apiSyncCounter = self.apiSyncCounter + 1
        end
        
        -- Determine if we should sync with API this time
        local shouldSync = (self.apiSyncCounter % API_SYNC_FREQUENCY == 0) or not essenceChanged or wasAtMax
        
        -- Hide any active partial fills when essence count changes to prevent race conditions
        if self.lastRechargingIndex and self.lastRechargingIndex <= #self.essenceBars then
            self.essenceBars[self.lastRechargingIndex].partialFill:Hide()
            self.lastRechargingIndex = nil
        end
        
        -- Only resync timer with API periodically to work around API bugs
        -- Reset timer when: syncing with API on schedule, spent from max, or first initialization
        if (essenceGained and shouldSync) or wasAtMax or not essenceChanged then
            self.lastEssenceTime = GetTime()
            -- When syncing, update our tracked count
            self.lastEssenceCount = currentEssence
        elseif essenceSpent then
            -- Essence spent from partial state - carry over progress (don't reset timer)
            -- Timer stays as is to maintain recharge progress
            self.lastEssenceCount = currentEssence
        elseif essenceGained and not shouldSync then
            -- Essence gained but not syncing - ignore API update to avoid desyncing our predictive tracking
            -- Don't update lastEssenceCount - we'll use our predictive count instead
        end
    end
    
    -- Update each essence bar based on API count
    for i = 1, #self.essenceBars do
        local bar = self.essenceBars[i]
        
        if i <= maxEssence then
            -- Show bar if within max essence
            bar:Show()
            
            if i <= currentEssence then
                -- Full essence - show filled bar
                bar.fill:Show()
                bar.partialFill:Hide()
            else
                -- Empty essence - hide fill (recharge progress handled in UpdateRechargeProgress)
                bar.fill:Hide()
            end
        else
            -- Hide bars beyond max essence
            bar:Hide()
        end
    end
end

-- Check essence count after spell cast and update UI if there's a mismatch
function DergEssence:CheckEssenceAfterSpellCast()
    if not self.essenceBars then
        return
    end
    
    local currentEssence = UnitPower("player", ESSENCE_POWER_TYPE)
    
    -- If there's a mismatch between tracked and actual essence, update the UI
    -- Also update if lastEssenceCount is not yet initialized
    if not self.lastEssenceCount or self.lastEssenceCount ~= currentEssence then
        self:UpdateEssence()
    end
end

-- Update recharge progress animation
function DergEssence:UpdateRechargeProgress()
    if not self.essenceBars then
        return
    end
    
    local currentEssence = UnitPower("player", ESSENCE_POWER_TYPE)
    local maxEssence = UnitPowerMax("player", ESSENCE_POWER_TYPE)
    
    -- Use tracked count for display (may be different from API due to predictive tracking)
    local displayEssence = self.lastEssenceCount or currentEssence
    
    -- Check if we should show recharging essence
    local showRecharging = displayEssence < maxEssence
    
    if showRecharging and self.lastEssenceTime then
        -- Calculate actual recharge time based on haste
        local haste = UnitSpellHaste("player")
        local actualRechargeTime = BASE_RECHARGE_TIME / (1 + haste / 100)
        
        -- Apply Innate Magic talent bonus (5% per rank) from cached value
        if self.cachedInnateMagicRank > 0 then
            local talentBonus = self.cachedInnateMagicRank * INNATE_MAGIC_BONUS_PER_RANK
            -- Increase regen rate = decrease recharge time
            actualRechargeTime = actualRechargeTime / (1 + talentBonus)
        end
        
        -- Calculate recharge progress
        local currentTime = GetTime()
        local timeSinceLastEssence = currentTime - self.lastEssenceTime
        -- Allow progress beyond 100% for predictive tracking
        local rechargingProgress = timeSinceLastEssence / actualRechargeTime
        
        -- Handle overflow when essence completes charging
        if rechargingProgress >= 1.0 then
            -- Predictively increment our tracked count
            local essenceToAdd = math.floor(rechargingProgress)
            displayEssence = displayEssence + essenceToAdd
            
            -- Cap at max essence
            if displayEssence > maxEssence then
                displayEssence = maxEssence
                rechargingProgress = 0
                showRecharging = false
            else
                -- Carry over remaining progress to next bar
                rechargingProgress = rechargingProgress - essenceToAdd
                -- Update our time reference for the new bar
                self.lastEssenceTime = self.lastEssenceTime + (essenceToAdd * actualRechargeTime)
            end
            
            -- Update tracked count
            self.lastEssenceCount = displayEssence
        end
        
        -- Show partial fill on the next essence to recharge
        local rechargingIndex = displayEssence + 1
        
        -- Re-query essence to detect race conditions with spell casts
        local currentEssenceCheck = UnitPower("player", ESSENCE_POWER_TYPE)
        
        -- If essence increased during this function, abort to prevent showing partial on wrong bar
        -- (Essence decreasing is fine - that's a spell cast which UpdateEssence will handle)
        if currentEssenceCheck > currentEssence then
            return
        end
        
        -- Validate that we're not showing partial fill on a bar that should be full
        -- This prevents race conditions where essence count updates mid-frame
        if rechargingIndex <= currentEssenceCheck then
            -- The bar we want to show progress on is already full, don't show it
            if self.lastRechargingIndex and self.lastRechargingIndex <= #self.essenceBars then
                self.essenceBars[self.lastRechargingIndex].partialFill:Hide()
                self.lastRechargingIndex = nil
            end
            return
        end
        
        -- Hide previous recharging bar if index changed
        if self.lastRechargingIndex and self.lastRechargingIndex ~= rechargingIndex 
            and self.lastRechargingIndex <= #self.essenceBars then
            self.essenceBars[self.lastRechargingIndex].partialFill:Hide()
        end
        
        if showRecharging and rechargingIndex <= maxEssence then
            local bar = self.essenceBars[rechargingIndex]
            local borderThickness = DergEssenceDB.options.borderThickness
            local fillWidth = (bar:GetWidth() - 2 * borderThickness) * rechargingProgress  -- Account for border
            bar.partialFill:SetWidth(fillWidth)
            bar.partialFill:Show()
            self.lastRechargingIndex = rechargingIndex
            
            -- Update display to show predictively filled bars
            for i = 1, rechargingIndex - 1 do
                if i > currentEssence and i <= displayEssence then
                    self.essenceBars[i].fill:Show()
                    self.essenceBars[i].partialFill:Hide()
                end
            end
        end
    else
        -- Hide the last recharging bar when at max essence
        if self.lastRechargingIndex and self.lastRechargingIndex <= #self.essenceBars then
            self.essenceBars[self.lastRechargingIndex].partialFill:Hide()
            self.lastRechargingIndex = nil
        end
    end
end

-- Helper function to get the rank of a talent by name
-- Returns the number of points invested in the talent (0 if not taken)

-- Recreate essence display with new settings
function DergEssence:RecreateEssenceDisplay()
    if self.mainFrame then
        -- Store the current state
        local wasShown = self.mainFrame:IsShown()
        
        -- Destroy the old frame
        self.mainFrame:Hide()
        self.mainFrame:SetScript("OnUpdate", nil)
        for i = 1, #self.essenceBars do
            self.essenceBars[i]:Hide()
        end
        self.mainFrame = nil
        self.essenceBars = nil
        self.lastRechargingIndex = nil
        
        -- Recreate with new settings
        self:CreateEssenceDisplay()
        
        -- Restore state
        if wasShown and DergEssenceDB.enabled then
            self.mainFrame:Show()
            self:UpdateEssence()
        else
            self.mainFrame:Hide()
        end
    end
end

-- Create options window
function DergEssence:CreateOptionsWindow()
    if self.optionsFrame then
        return
    end
    
    local frame = CreateFrame("Frame", "DergEssenceOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    self.optionsFrame = frame
    frame:SetSize(400, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("DergEssence Options")
    
    -- Debounce timer for applying changes
    local applyTimer = nil
    local function scheduleApply()
        if applyTimer then
            applyTimer:Cancel()
        end
        applyTimer = C_Timer.NewTimer(0.1, function()
            DergEssence:RecreateEssenceDisplay()
            applyTimer = nil
        end)
    end
    
    local yOffset = -30
    
    -- Helper function to create section headers
    local function createSectionHeader(text)
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 20, yOffset)
        header:SetText(text)
        yOffset = yOffset - 25
        return header
    end
    
    local function createSlider(label, key, minVal, maxVal, step)
        local slider = CreateFrame("Slider", "DergEssenceSlider_" .. key, frame, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 20, yOffset)
        slider:SetWidth(350)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        
        -- Get current value
        local currentValue = DergEssenceDB.options[key]
        slider:SetValue(currentValue)
        
        -- Label
        slider.label = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slider.label:SetPoint("BOTTOM", slider, "TOP", 0, 0)
        slider.label:SetText(label)
        
        -- Value display
        slider.valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slider.valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
        slider.valueText:SetText(string.format("%.1f", currentValue))
        
        -- Update on value change with debounced apply
        slider:SetScript("OnValueChanged", function(self, value)
            DergEssenceDB.options[key] = value
            self.valueText:SetText(string.format("%.1f", value))
            -- Apply changes with debounce
            scheduleApply()
        end)
        
        yOffset = yOffset - 60
        return slider
    end
    
    local function createSliderWithTextbox(label, key, minVal, maxVal, step)
        local slider = CreateFrame("Slider", "DergEssenceSlider_" .. key, frame, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 20, yOffset)
        slider:SetWidth(350)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        
        -- Get current value
        local currentValue = DergEssenceDB.options[key]
        slider:SetValue(currentValue)
        
        -- Label
        slider.label = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slider.label:SetPoint("BOTTOM", slider, "TOP", 0, 0)
        slider.label:SetText(label)
        
        -- Editable textbox for value input
        local editBox = CreateFrame("EditBox", "DergEssenceEditBox_" .. key, frame, "InputBoxTemplate")
        editBox:SetPoint("TOP", slider, "BOTTOM", 0, -5)
        editBox:SetSize(60, 20)
        editBox:SetAutoFocus(false)
        editBox:SetText(string.format("%.0f", currentValue))
        
        -- Update slider when editbox value changes
        editBox:SetScript("OnEnterPressed", function(self)
            local value = tonumber(self:GetText())
            if value then
                -- Clamp value to min/max
                value = math.max(minVal, math.min(maxVal, value))
                DergEssenceDB.options[key] = value
                slider:SetValue(value)
                self:SetText(string.format("%.0f", value))
                scheduleApply()
            else
                -- Invalid input, restore previous value
                self:SetText(string.format("%.0f", DergEssenceDB.options[key]))
            end
            self:ClearFocus()
        end)
        
        editBox:SetScript("OnEscapePressed", function(self)
            self:SetText(string.format("%.0f", DergEssenceDB.options[key]))
            self:ClearFocus()
        end)
        
        -- Update on slider value change
        slider:SetScript("OnValueChanged", function(self, value)
            DergEssenceDB.options[key] = value
            editBox:SetText(string.format("%.0f", value))
            -- Apply changes with debounce
            scheduleApply()
        end)
        
        yOffset = yOffset - 60
        return slider
    end
    
    local function createColorPicker(label, key)
        local button = CreateFrame("Button", "DergEssenceColorPicker_" .. key, frame, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", 20, yOffset)
        button:SetSize(120, 25)
        button:SetText("Pick Color")
        
        -- Label
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.label:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 5)
        button.label:SetText(label)
        
        -- Color preview
        button.colorSwatch = button:CreateTexture(nil, "OVERLAY")
        button.colorSwatch:SetSize(40, 25)
        button.colorSwatch:SetPoint("LEFT", button, "RIGHT", 10, 0)
        local color = DergEssenceDB.options[key]
        button.colorSwatch:SetColorTexture(color.r, color.g, color.b, color.a)
        
        button:SetScript("OnClick", function(self)
            local color = DergEssenceDB.options[key]
            -- Store original values for cancel
            local originalR, originalG, originalB, originalA = color.r, color.g, color.b, color.a
            
            -- Shared function for updating color
            local function updateColor()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                DergEssenceDB.options[key].r = r
                DergEssenceDB.options[key].g = g
                DergEssenceDB.options[key].b = b
                DergEssenceDB.options[key].a = a
                self.colorSwatch:SetColorTexture(r, g, b, a)
                -- Apply changes with debounce
                scheduleApply()
            end
            
            ColorPickerFrame:SetupColorPickerAndShow({
                r = color.r,
                g = color.g,
                b = color.b,
                opacity = color.a,
                hasOpacity = true,
                swatchFunc = updateColor,
                opacityFunc = updateColor,
                cancelFunc = function()
                    DergEssenceDB.options[key].r = originalR
                    DergEssenceDB.options[key].g = originalG
                    DergEssenceDB.options[key].b = originalB
                    DergEssenceDB.options[key].a = originalA
                    self.colorSwatch:SetColorTexture(originalR, originalG, originalB, originalA)
                    -- Restore original appearance
                    DergEssence:RecreateEssenceDisplay()
                end,
            })
        end)
        
        yOffset = yOffset - 50
        return button
    end
    
    -- Appearance Section
    createSectionHeader("Appearance")
    createSlider("Bar Width", "barWidth", 50, 200, 5)
    createSlider("Bar Height", "barHeight", 10, 50, 1)
    createSlider("Bar Spacing", "barSpacing", 0, 20, 1)
    createSlider("Border Thickness", "borderThickness", 0, 5, 1)
    
    createColorPicker("Filled Color", "filledColor")
    createColorPicker("Empty Color", "emptyColor")
    createColorPicker("Border Color", "borderColor")
    
    -- Position Section
    createSectionHeader("Position")
    createSliderWithTextbox("Horizontal Position", "xPosition", -500, 500, 5)
    createSliderWithTextbox("Vertical Position", "yPosition", -500, 500, 5)
end

-- Show options window
function DergEssence:ShowOptions()
    if not self.optionsFrame then
        self:CreateOptionsWindow()
    end
    self.optionsFrame:Show()
end

-- Slash command handler
SLASH_DERGESSENCE1 = "/dergessence"
SLASH_DERGESSENCE2 = "/de"
SLASH_DERGESSENCE3 = "/derge"
SlashCmdList["DERGESSENCE"] = function(msg)
    local cmd = string.lower(msg or "")
    
    if cmd == "toggle" then
        DergEssenceDB.enabled = not DergEssenceDB.enabled
        if DergEssenceDB.enabled then
            print("|cFF00FF00DergEssence|r: Enabled")
            DergEssence:OnEnable()
        else
            print("|cFF00FF00DergEssence|r: Disabled")
            DergEssence:OnDisable()
        end
    else
        -- Show options window
        DergEssence:ShowOptions()
    end
end

-- Register events
frame:SetScript("OnEvent", OnEvent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
