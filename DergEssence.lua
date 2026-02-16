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
local INNATE_MAGIC_TALENT_NAME = "Innate Magic"  -- Talent name for essence regen bonus
local INNATE_MAGIC_BONUS_PER_RANK = 0.05  -- 5% bonus per rank (5% for 1 point, 10% for 2 points)

-- Frame for event handling
local frame = CreateFrame("Frame")

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
    
    print("|cFF00FF00DergEssence|r v" .. self.version .. " loaded. Type /dergessence for options.")
end

-- Enable the addon
function DergEssence:OnEnable()
    if not DergEssenceDB.enabled then
        return
    end
    
    -- Register events for essence tracking
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
    frame:UnregisterEvent("TRAIT_CONFIG_UPDATED")
    frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    
    -- Hide the essence display if it exists
    if self.mainFrame then
        self.mainFrame:Hide()
        -- Stop OnUpdate to save performance
        self.mainFrame:SetScript("OnUpdate", nil)
    end
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
    local rank = GetTalentRankByName(INNATE_MAGIC_TALENT_NAME)
    -- Only update if we got a valid result (talent API may not be ready yet)
    if rank then
        self.cachedInnateMagicRank = rank
    end
end

-- Create the essence bar display
function DergEssence:CreateEssenceDisplay()
    -- Create main container frame
    if not self.mainFrame then
        self.mainFrame = CreateFrame("Frame", "DergEssenceMainFrame", UIParent)
        self.mainFrame:SetSize(500, 20)  -- Container size
        self.mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)  -- Centered on screen
        
        -- Create essence bars
        self.essenceBars = {}
        local barWidth = 100
        local barHeight = 15
        local barGap = 2  -- Gap between bars
        
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
            bar.background:SetColorTexture(0, 0, 0, 1)  -- Black
            
            -- Create border frame using four edge textures
            -- Top border
            bar.borderTop = bar:CreateTexture(nil, "BORDER")
            bar.borderTop:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bar.borderTop:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            bar.borderTop:SetHeight(1)
            bar.borderTop:SetColorTexture(0.5, 0.5, 0.5, 1)
            
            -- Bottom border
            bar.borderBottom = bar:CreateTexture(nil, "BORDER")
            bar.borderBottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar.borderBottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            bar.borderBottom:SetHeight(1)
            bar.borderBottom:SetColorTexture(0.5, 0.5, 0.5, 1)
            
            -- Left border
            bar.borderLeft = bar:CreateTexture(nil, "BORDER")
            bar.borderLeft:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bar.borderLeft:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar.borderLeft:SetWidth(1)
            bar.borderLeft:SetColorTexture(0.5, 0.5, 0.5, 1)
            
            -- Right border
            bar.borderRight = bar:CreateTexture(nil, "BORDER")
            bar.borderRight:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            bar.borderRight:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            bar.borderRight:SetWidth(1)
            bar.borderRight:SetColorTexture(0.5, 0.5, 0.5, 1)
            
            -- Create fill texture (light blue when essence available)
            bar.fill = bar:CreateTexture(nil, "ARTWORK")
            bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
            bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
            bar.fill:SetColorTexture(ESSENCE_COLOR.r, ESSENCE_COLOR.g, ESSENCE_COLOR.b, ESSENCE_COLOR.a)
            bar.fill:Hide()  -- Initially hidden
            
            -- Create partial fill texture for recharging essence
            bar.partialFill = bar:CreateTexture(nil, "ARTWORK")
            bar.partialFill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
            bar.partialFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
            bar.partialFill:SetWidth(0)  -- Initially zero width
            bar.partialFill:SetColorTexture(ESSENCE_COLOR.r, ESSENCE_COLOR.g, ESSENCE_COLOR.b, ESSENCE_COLOR.a)
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
    
    -- Track essence count changes and handle progress carryover
    if not self.lastEssenceCount or self.lastEssenceCount ~= currentEssence then
        local essenceChanged = self.lastEssenceCount ~= nil
        local essenceSpent = essenceChanged and currentEssence < self.lastEssenceCount
        
        -- If essence was spent and we have a timer, carry over the partial progress
        if essenceSpent and self.lastEssenceTime then
            -- Calculate current progress before the change
            local currentTime = GetTime()
            local timeSinceLastEssence = currentTime - self.lastEssenceTime
            
            -- Calculate actual recharge time (same logic as UpdateRechargeProgress)
            local haste = UnitSpellHaste("player")
            local actualRechargeTime = BASE_RECHARGE_TIME / (1 + haste / 100)
            
            -- Apply Innate Magic talent bonus
            if self.cachedInnateMagicRank > 0 then
                local talentBonus = self.cachedInnateMagicRank * INNATE_MAGIC_BONUS_PER_RANK
                actualRechargeTime = actualRechargeTime / (1 + talentBonus)
            end
            
            -- Carry over progress: adjust the timer back by the time already elapsed
            -- This maintains the partial progress for the new actively charging essence
            self.lastEssenceTime = currentTime - timeSinceLastEssence
        else
            -- Essence gained or first initialization - reset timer
            self.lastEssenceTime = GetTime()
        end
        
        self.lastEssenceCount = currentEssence
    end
    
    -- Update each essence bar
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

-- Update recharge progress animation
function DergEssence:UpdateRechargeProgress()
    if not self.essenceBars then
        return
    end
    
    local currentEssence = UnitPower("player", ESSENCE_POWER_TYPE)
    local maxEssence = UnitPowerMax("player", ESSENCE_POWER_TYPE)
    
    -- Check if we should show recharging essence
    local showRecharging = currentEssence < maxEssence
    
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
        local rechargingProgress = math.min(1, timeSinceLastEssence / actualRechargeTime)
        
        -- Show partial fill on the next essence to recharge
        local rechargingIndex = currentEssence + 1
        
        -- Hide previous recharging bar if index changed
        if self.lastRechargingIndex and self.lastRechargingIndex ~= rechargingIndex 
            and self.lastRechargingIndex <= #self.essenceBars then
            self.essenceBars[self.lastRechargingIndex].partialFill:Hide()
        end
        
        if rechargingIndex <= maxEssence then
            local bar = self.essenceBars[rechargingIndex]
            local fillWidth = (bar:GetWidth() - 2) * rechargingProgress  -- Account for border
            bar.partialFill:SetWidth(fillWidth)
            bar.partialFill:Show()
            self.lastRechargingIndex = rechargingIndex
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
local function GetTalentRankByName(talentName)
    local configId = C_ClassTalents.GetActiveConfigID()
    if not configId then return 0 end

    local configInfo = C_Traits.GetConfigInfo(configId)
    if not configInfo then return 0 end

    for _, treeId in ipairs(configInfo.treeIDs) do
        for _, nodeId in ipairs(C_Traits.GetTreeNodes(treeId)) do
            local nodeInfo = C_Traits.GetNodeInfo(configId, nodeId)

            if nodeInfo and nodeInfo.activeEntry then
                local entryInfo = C_Traits.GetEntryInfo(configId, nodeInfo.activeEntry)
                if entryInfo and entryInfo.definitionID then
                    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)

                    if defInfo and defInfo.spellID then
                        local name = GetSpellInfo(defInfo.spellID)
                        if name == talentName then
                            -- Return the current rank (number of points invested)
                            return nodeInfo.currentRank or 0
                        end
                    end
                end
            end
        end
    end

    return 0
end

local function IsTalentTakenByName(talentName)
    return GetTalentRankByName(talentName) > 0
end

-- Slash command handler
SLASH_DERGESSENCE1 = "/dergessence"
SLASH_DERGESSENCE2 = "/de"
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
        print("|cFF00FF00DergEssence|r v" .. DergEssence.version)
        print("Commands:")
        print("  /dergessence toggle - Toggle addon on/off")
    end
end

-- Register events
frame:SetScript("OnEvent", OnEvent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
