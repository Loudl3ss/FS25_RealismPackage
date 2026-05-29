-- luacheck: globals RealismPackage g_currentModName g_currentModDirectory
-- luacheck: globals g_specializationManager TypeManager Logging Utils
-- luacheck: globals DamageLogic RealismMenu addModEventListener g_currentMission
-- luacheck: globals MessageType nextMessageTypeId

RealismPackage = RealismPackage or {}
local RP = RealismPackage
RP.modName = g_currentModName or "RealismPackage"
RP.directory = g_currentModDirectory or ""
RP.customNamespace = RP.modName
RP.DEFAULT_SETTINGS = {
    wearEnabled = true,
    damageEnabled = true,
    airFilterEnabled = true,
    difficulty = 2
}

local SETTINGS_XML_ROOT = "realismPackage.settings"
local SETTINGS_XML_FILENAME = "modSettings/RealismPackage.xml"

local function cloneDefaultSettings()
    return {
        wearEnabled = RP.DEFAULT_SETTINGS.wearEnabled,
        damageEnabled = RP.DEFAULT_SETTINGS.damageEnabled,
        airFilterEnabled = RP.DEFAULT_SETTINGS.airFilterEnabled,
        difficulty = RP.DEFAULT_SETTINGS.difficulty
    }
end

local function getSettingsFilePath()
    if type(getUserProfileAppPath) ~= "function" then
        return nil
    end

    local userProfilePath = getUserProfileAppPath()

    if type(userProfilePath) ~= "string" or userProfilePath == "" then
        return nil
    end

    return userProfilePath .. SETTINGS_XML_FILENAME
end

local function ensureSettingsDirectoryExists(settingsFilePath)
    if type(settingsFilePath) ~= "string" or settingsFilePath == "" or type(createFolder) ~= "function" then
        return
    end

    local settingsDir = string.match(settingsFilePath, "^(.*)/[^/]+$")

    if settingsDir ~= nil and settingsDir ~= "" then
        createFolder(settingsDir)
    end
end

function RP:ensureSettings()
    if type(self.settings) ~= "table" then
        self.settings = cloneDefaultSettings()
        return
    end

    if self.settings.wearEnabled == nil then self.settings.wearEnabled = RP.DEFAULT_SETTINGS.wearEnabled end
    if self.settings.damageEnabled == nil then self.settings.damageEnabled = RP.DEFAULT_SETTINGS.damageEnabled end
    if self.settings.airFilterEnabled == nil then self.settings.airFilterEnabled = RP.DEFAULT_SETTINGS.airFilterEnabled end
    if self.settings.difficulty == nil then self.settings.difficulty = RP.DEFAULT_SETTINGS.difficulty end
end

function RP:markSettingsDirty()
    self.settingsDirty = true
end

function RP:applySettings(profileName, wearEnabled, damageEnabled, airFilterEnabled)
    self:ensureSettings()

    if type(wearEnabled) == "boolean" then
        self.settings.wearEnabled = wearEnabled
    end

    if type(damageEnabled) == "boolean" then
        self.settings.damageEnabled = damageEnabled
    end

    if type(airFilterEnabled) == "boolean" then
        self.settings.airFilterEnabled = airFilterEnabled
    end

    if type(profileName) == "string" and DamageLogic ~= nil and DamageLogic.setProfile ~= nil then
        DamageLogic.setProfile(DamageLogic, profileName)
    end

    self:markSettingsDirty()
end

function RP:loadSettingsFromDisk()
    local settingsFilePath = getSettingsFilePath()

    if settingsFilePath == nil or type(loadXMLFile) ~= "function" then
        return false
    end

    local xmlFile = loadXMLFile("realismPackageSettings", settingsFilePath)

    if xmlFile == nil then
        return false
    end

    local loadedWearEnabled = self.DEFAULT_SETTINGS.wearEnabled
    local loadedDamageEnabled = self.DEFAULT_SETTINGS.damageEnabled
    local loadedAirFilterEnabled = self.DEFAULT_SETTINGS.airFilterEnabled
    local loadedDifficulty = self.DEFAULT_SETTINGS.difficulty

    if type(hasXMLProperty) == "function" and hasXMLProperty(xmlFile, SETTINGS_XML_ROOT .. "#wearEnabled") then
        loadedWearEnabled = getXMLBool(xmlFile, SETTINGS_XML_ROOT .. "#wearEnabled") ~= false
    end

    if type(hasXMLProperty) == "function" and hasXMLProperty(xmlFile, SETTINGS_XML_ROOT .. "#damageEnabled") then
        loadedDamageEnabled = getXMLBool(xmlFile, SETTINGS_XML_ROOT .. "#damageEnabled") ~= false
    end

    if type(hasXMLProperty) == "function" and hasXMLProperty(xmlFile, SETTINGS_XML_ROOT .. "#airFilterEnabled") then
        loadedAirFilterEnabled = getXMLBool(xmlFile, SETTINGS_XML_ROOT .. "#airFilterEnabled") ~= false
    end

    if type(hasXMLProperty) == "function" and hasXMLProperty(xmlFile, SETTINGS_XML_ROOT .. "#difficulty") then
        loadedDifficulty = math.max(1, math.min(3, getXMLInt(xmlFile, SETTINGS_XML_ROOT .. "#difficulty") or self.DEFAULT_SETTINGS.difficulty))
    end

    if type(delete) == "function" then
        delete(xmlFile)
    end

    self:ensureSettings()
    self.settings.wearEnabled = loadedWearEnabled
    self.settings.damageEnabled = loadedDamageEnabled
    self.settings.airFilterEnabled = loadedAirFilterEnabled
    self.settings.difficulty = loadedDifficulty

    local profileByDifficulty = { "FS25", "NORMAL", "REAL_LIFE" }
    local profileName = profileByDifficulty[self.settings.difficulty] or "NORMAL"

    if DamageLogic ~= nil and DamageLogic.setProfile ~= nil then
        DamageLogic.setProfile(DamageLogic, profileName)
    end

    self.settingsDirty = false
    return true
end

function RP:saveSettingsToDisk(force)
    if not force and self.settingsDirty ~= true then
        return false
    end

    local settingsFilePath = getSettingsFilePath()

    if settingsFilePath == nil
        or type(createXMLFile) ~= "function"
        or type(saveXMLFile) ~= "function"
        or type(setXMLBool) ~= "function"
        or type(setXMLInt) ~= "function" then
        return false
    end

    ensureSettingsDirectoryExists(settingsFilePath)
    self:ensureSettings()

    local xmlFile = createXMLFile("realismPackageSettings", settingsFilePath, SETTINGS_XML_ROOT)

    if xmlFile == nil then
        return false
    end

    setXMLBool(xmlFile, SETTINGS_XML_ROOT .. "#wearEnabled", self.settings.wearEnabled ~= false)
    setXMLBool(xmlFile, SETTINGS_XML_ROOT .. "#damageEnabled", self.settings.damageEnabled ~= false)
    setXMLBool(xmlFile, SETTINGS_XML_ROOT .. "#airFilterEnabled", self.settings.airFilterEnabled ~= false)
    setXMLInt(xmlFile, SETTINGS_XML_ROOT .. "#difficulty", math.max(1, math.min(3, self.settings.difficulty or self.DEFAULT_SETTINGS.difficulty)))

    saveXMLFile(xmlFile)

    if type(delete) == "function" then
        delete(xmlFile)
    end

    self.settingsDirty = false
    return true
end

local function initSpecialization(manager)

    if manager ~= nil and manager.typeName == "vehicle" then
        local specName = "DamageLogic"
        local specKey = RP.modName .. "." .. specName


        if g_specializationManager:getSpecializationByName(specKey) == nil then
            g_specializationManager:addSpecialization(specName, "DamageLogic", Utils.getFilename("scripts/DamageLogic.lua", RP.directory), nil)
        end

        local attachedCount = 0
        local types = manager:getTypes()
        
        -- 2. Injekcija prieš tipų validaciją
        for typeName, typeEntry in pairs(types) do
            if typeEntry ~= nil then
                local isMotorized = false
                local hasDamageLogic = false

                if typeEntry.specializationsByName ~= nil then
                    isMotorized = typeEntry.specializationsByName["motorized"] ~= nil
                    hasDamageLogic = typeEntry.specializationsByName[specKey] ~= nil
                elseif typeEntry.specializationNames ~= nil then
                    for _, name in ipairs(typeEntry.specializationNames) do
                        local ln = string.lower(name)
                        if ln == "motorized" then isMotorized = true end
                        if ln == string.lower(specKey) then hasDamageLogic = true end
                    end
                end

                if isMotorized and not hasDamageLogic then
                    manager:addSpecialization(typeName, specKey)
                    attachedCount = attachedCount + 1
                end
            end
        end
        Logging.info("[%s] Injected DamageLogic into %d motorized vehicle types before validation.", RP.modName, attachedCount)
    end
end


if TypeManager ~= nil and TypeManager.validateTypes ~= nil and Utils.prependedFunction ~= nil then
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, initSpecialization)
else
    Logging.error("[%s] ERROR: TypeManager.validateTypes hook could not be installed!", RP.modName)
end

function RP:loadMap(_mapFilename)
    self:ensureSettings()
    self:loadSettingsFromDisk()

    if DamageLogic ~= nil and DamageLogic.init ~= nil then
        DamageLogic.init()
    end
end

function RP:deleteMap()
    self:saveSettingsToDisk(false)
end

addModEventListener(RP)