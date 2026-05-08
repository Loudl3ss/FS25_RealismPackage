-- luacheck: globals RealismSettings InGameMenuSettingsFrame g_i18n g_gui FocusManager
-- luacheck: globals TextElement BitmapElement MultiTextOptionElement Utils GuiSoundPlayer
-- luacheck: globals RealismPackage DamageLogic RealismSettingsEvent g_server g_client

RealismSettings = RealismSettings or {}

RealismSettings.profileValues = { "FS25", "NORMAL", "REAL_LIFE" }

local function getOnOffTexts()
    return {
        g_i18n:getText("rp_settings_option_off"),
        g_i18n:getText("rp_settings_option_on")
    }
end

local function getProfileTexts()
    return {
        g_i18n:getText("rp_settings_profile_fs25"),
        g_i18n:getText("rp_settings_profile_normal"),
        g_i18n:getText("rp_settings_profile_real_life")
    }
end

local function getProfileIndex(profileName)
    local normalized = string.upper(profileName or "NORMAL")

    for index, value in ipairs(RealismSettings.profileValues) do
        if value == normalized then
            return index
        end
    end

    return 2
end

local function getCurrentProfileName()
    if DamageLogic ~= nil and type(DamageLogic.currentProfile) == "string" then
        return DamageLogic.currentProfile
    end

    return "NORMAL"
end

local function getCurrentSettings()
    if RealismPackage ~= nil and RealismPackage.ensureSettings ~= nil then
        RealismPackage:ensureSettings()
        return RealismPackage.settings
    end

    return {
        wearEnabled = true,
        damageEnabled = true,
        airFilterEnabled = true
    }
end

local function sendSettings(profileIndex, wearEnabled, damageEnabled, airFilterEnabled)
    local event = RealismSettingsEvent.new(profileIndex, wearEnabled, damageEnabled, airFilterEnabled)

    if g_server ~= nil then
        event:run(nil)
        g_server:broadcastEvent(event)
    elseif g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(event)
    end
end

function RealismSettings:onFrameOpen()
    if self.rpSettingsDone then
        return
    end

    RealismSettings.cachedFrame = self

    RealismSettings:addTitle(self)
    RealismSettings.profileOption = RealismSettings:addMultiTextOption(
        self,
        "onProfileValueChanged",
        getProfileTexts(),
        g_i18n:getText("rp_settings_profile_title"),
        g_i18n:getText("rp_settings_profile_desc")
    )

    local onOffTexts = getOnOffTexts()

    RealismSettings.wearOption = RealismSettings:addMultiTextOption(
        self,
        "onWearEnabledValueChanged",
        onOffTexts,
        g_i18n:getText("rp_settings_wear_enabled_title"),
        g_i18n:getText("rp_settings_wear_enabled_desc")
    )

    RealismSettings.damageOption = RealismSettings:addMultiTextOption(
        self,
        "onDamageEnabledValueChanged",
        onOffTexts,
        g_i18n:getText("rp_settings_damage_enabled_title"),
        g_i18n:getText("rp_settings_damage_enabled_desc")
    )

    RealismSettings.filterOption = RealismSettings:addMultiTextOption(
        self,
        "onFilterEnabledValueChanged",
        onOffTexts,
        g_i18n:getText("rp_settings_air_filter_enabled_title"),
        g_i18n:getText("rp_settings_air_filter_enabled_desc")
    )

    self.gameSettingsLayout:invalidateLayout()
    self:updateAlternatingElements(self.gameSettingsLayout)
    self:updateGeneralSettings(self.gameSettingsLayout)

    self.rpSettingsDone = true
    RealismSettings.updateSettings()
end

function RealismSettings:addTitle(inGameMenuSettingsFrame)
    local textElement = TextElement.new()
    local profile = g_gui:getProfile("fs25_settingsSectionHeader")

    textElement.name = "sectionHeader"
    textElement:loadProfile(profile, true)
    textElement:setText(g_i18n:getText("rp_settings_title"))

    inGameMenuSettingsFrame.gameSettingsLayout:addElement(textElement)
    textElement:onGuiSetupFinished()
    textElement.focusId = FocusManager:serveAutoFocusId()
end

function RealismSettings:addMultiTextOption(inGameMenuSettingsFrame, callbackName, texts, title, tooltip)
    local container = BitmapElement.new()
    container:loadProfile(g_gui:getProfile("fs25_multiTextOptionContainer"), true)
    container.focusId = FocusManager:serveAutoFocusId()

    local multiOption = MultiTextOptionElement.new()
    multiOption:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOption"), true)
    multiOption.target = RealismSettings
    RealismSettings.name = inGameMenuSettingsFrame.name
    multiOption:setCallback("onClickCallback", callbackName)
    multiOption:setTexts(texts)
    multiOption.focusId = FocusManager:serveAutoFocusId()

    local titleElement = TextElement.new()
    titleElement:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOptionTitle"), true)
    titleElement:setText(title)
    titleElement.focusId = FocusManager:serveAutoFocusId()

    local tooltipElement = TextElement.new()
    tooltipElement.name = "ignore"
    tooltipElement:loadProfile(g_gui:getProfile("fs25_multiTextOptionTooltip"), true)
    tooltipElement:setText(tooltip)
    tooltipElement.focusId = FocusManager:serveAutoFocusId()

    multiOption:addElement(tooltipElement)
    container:addElement(multiOption)
    container:addElement(titleElement)

    FocusManager:loadElementFromCustomValues(container, nil, nil, false, false)
    FocusManager:loadElementFromCustomValues(multiOption, nil, nil, false, false)
    FocusManager:loadElementFromCustomValues(titleElement, nil, nil, false, false)

    multiOption:onGuiSetupFinished()
    titleElement:onGuiSetupFinished()
    tooltipElement:onGuiSetupFinished()

    inGameMenuSettingsFrame.gameSettingsLayout:addElement(container)
    container:onGuiSetupFinished()

    return multiOption
end

function RealismSettings.updateSettings()
    local settings = getCurrentSettings()
    local profileIndex = getProfileIndex(getCurrentProfileName())

    if RealismSettings.profileOption ~= nil then
        RealismSettings.profileOption:setState(profileIndex)
    end

    if RealismSettings.wearOption ~= nil then
        RealismSettings.wearOption:setState(settings.wearEnabled and 2 or 1)
    end

    if RealismSettings.damageOption ~= nil then
        RealismSettings.damageOption:setState(settings.damageEnabled and 2 or 1)
    end

    if RealismSettings.filterOption ~= nil then
        RealismSettings.filterOption:setState(settings.airFilterEnabled and 2 or 1)
    end
end

local function getPendingValues(profileState, wearState, damageState, filterState)
    local settings = getCurrentSettings()

    local profileIndex = profileState or (RealismSettings.profileOption ~= nil and RealismSettings.profileOption:getState() or getProfileIndex(getCurrentProfileName()))
    local wearEnabled = (wearState or (RealismSettings.wearOption ~= nil and RealismSettings.wearOption:getState() or 2)) == 2
    local damageEnabled = (damageState or (RealismSettings.damageOption ~= nil and RealismSettings.damageOption:getState() or 2)) == 2
    local filterEnabled = (filterState or (RealismSettings.filterOption ~= nil and RealismSettings.filterOption:getState() or 2)) == 2

    if settings ~= nil then
        if wearState == nil then wearEnabled = settings.wearEnabled ~= false end
        if damageState == nil then damageEnabled = settings.damageEnabled ~= false end
        if filterState == nil then filterEnabled = settings.airFilterEnabled ~= false end
    end

    return profileIndex, wearEnabled, damageEnabled, filterEnabled
end

function RealismSettings:onProfileValueChanged(state)
    local profileIndex, wearEnabled, damageEnabled, filterEnabled = getPendingValues(state, nil, nil, nil)
    sendSettings(profileIndex, wearEnabled, damageEnabled, filterEnabled)

    if RealismSettings.cachedFrame ~= nil then
        RealismSettings.cachedFrame:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end
end

function RealismSettings:onWearEnabledValueChanged(state)
    local profileIndex, wearEnabled, damageEnabled, filterEnabled = getPendingValues(nil, state, nil, nil)
    sendSettings(profileIndex, wearEnabled, damageEnabled, filterEnabled)

    if RealismSettings.cachedFrame ~= nil then
        RealismSettings.cachedFrame:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end
end

function RealismSettings:onDamageEnabledValueChanged(state)
    local profileIndex, wearEnabled, damageEnabled, filterEnabled = getPendingValues(nil, nil, state, nil)
    sendSettings(profileIndex, wearEnabled, damageEnabled, filterEnabled)

    if RealismSettings.cachedFrame ~= nil then
        RealismSettings.cachedFrame:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end
end

function RealismSettings:onFilterEnabledValueChanged(state)
    local profileIndex, wearEnabled, damageEnabled, filterEnabled = getPendingValues(nil, nil, nil, state)
    sendSettings(profileIndex, wearEnabled, damageEnabled, filterEnabled)

    if RealismSettings.cachedFrame ~= nil then
        RealismSettings.cachedFrame:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
    end
end

InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, RealismSettings.onFrameOpen)
