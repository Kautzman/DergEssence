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
    
    -- Check if player is an Evoker
    local _, class = UnitClass("player")
    if class == "EVOKER" then
        self:SetupEssenceTracking()
        
        -- Show the frame if it was previously hidden
        if self.mainFrame then
            self.mainFrame:Show()
            self:UpdateEssence()
        end
    end
end

-- Disable the addon
function DergEssence:OnDisable()
    -- Only unregister essence tracking events, keep lifecycle events
    frame:UnregisterEvent("UNIT_POWER_UPDATE")
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    
    -- Hide the essence display if it exists
    if self.mainFrame then
        self.mainFrame:Hide()
    end
end

-- Setup essence tracking for Evokers
function DergEssence:SetupEssenceTracking()
    -- Essence is power type 19 for Evokers
    self:CreateEssenceDisplay()
    self:UpdateEssence()
    print("|cFF00FF00DergEssence|r: Essence tracking initialized for Evoker.")
end

-- Create the essence bar display
function DergEssence:CreateEssenceDisplay()
    -- Create main container frame
    if not self.mainFrame then
        self.mainFrame = CreateFrame("Frame", "DergEssenceMainFrame", UIParent)
        self.mainFrame:SetSize(500, 20)  -- Container size
        self.mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)  -- Centered on screen
        
        -- Create essence bars (max 6 for Evoker)
        self.essenceBars = {}
        local barWidth = 100
        local barHeight = 15
        local maxEssence = 6
        
        for i = 1, maxEssence do
            local bar = CreateFrame("Frame", "DergEssenceBar" .. i, self.mainFrame)
            bar:SetSize(barWidth, barHeight)
            
            -- Position bars horizontally with small gap
            local xOffset = (i - 1) * (barWidth + 2) - (maxEssence * (barWidth + 2) - 2) / 2
            bar:SetPoint("LEFT", self.mainFrame, "CENTER", xOffset, 0)
            
            -- Create background (black when essence not available)
            bar.background = bar:CreateTexture(nil, "BACKGROUND")
            bar.background:SetAllPoints()
            bar.background:SetColorTexture(0, 0, 0, 1)  -- Black
            
            -- Create border
            bar.border = bar:CreateTexture(nil, "BORDER")
            bar.border:SetAllPoints()
            bar.border:SetColorTexture(0.3, 0.3, 0.3, 1)  -- Dark gray border
            
            -- Create fill texture (light blue when essence available)
            bar.fill = bar:CreateTexture(nil, "ARTWORK")
            bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
            bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
            bar.fill:SetWidth(barWidth - 2)  -- Account for border
            bar.fill:SetColorTexture(0.4, 0.7, 1, 1)  -- Light blue
            bar.fill:Hide()  -- Initially hidden
            
            -- Create partial fill for progress
            bar.partialFill = bar:CreateTexture(nil, "ARTWORK")
            bar.partialFill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
            bar.partialFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
            bar.partialFill:SetColorTexture(0.4, 0.7, 1, 1)  -- Light blue
            bar.partialFill:Hide()  -- Initially hidden
            
            self.essenceBars[i] = bar
        end
        
        self.mainFrame:Show()
    end
end

-- Update essence display
function DergEssence:UpdateEssence()
    if not self.essenceBars then
        return
    end
    
    -- Essence is power type 19 for Evokers
    local ESSENCE_POWER_TYPE = 19
    local currentEssence = UnitPower("player", ESSENCE_POWER_TYPE)
    local maxEssence = UnitPowerMax("player", ESSENCE_POWER_TYPE)
    
    -- Get partial essence (for charging essence)
    local partialEssence = currentEssence % 1
    local fullEssence = math.floor(currentEssence)
    
    -- Update each essence bar
    for i = 1, #self.essenceBars do
        local bar = self.essenceBars[i]
        
        if i <= maxEssence then
            -- Show bar if within max essence
            bar:Show()
            
            if i <= fullEssence then
                -- Full essence - show filled bar
                bar.fill:Show()
                bar.partialFill:Hide()
            elseif i == fullEssence + 1 and partialEssence > 0 then
                -- Partial essence - show progress fill
                bar.fill:Hide()
                bar.partialFill:Show()
                local fillWidth = (bar:GetWidth() - 2) * partialEssence
                bar.partialFill:SetWidth(fillWidth)
            else
                -- Empty essence - hide fills
                bar.fill:Hide()
                bar.partialFill:Hide()
            end
        else
            -- Hide bars beyond max essence
            bar:Hide()
        end
    end
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
