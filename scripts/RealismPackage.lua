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

local function cloneDefaultSettings()
    return {
        wearEnabled = RP.DEFAULT_SETTINGS.wearEnabled,
        damageEnabled = RP.DEFAULT_SETTINGS.damageEnabled,
        airFilterEnabled = RP.DEFAULT_SETTINGS.airFilterEnabled,
        difficulty = RP.DEFAULT_SETTINGS.difficulty
    }
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
    if DamageLogic ~= nil and DamageLogic.init ~= nil then
        DamageLogic.init()
    end
end

addModEventListener(RP)