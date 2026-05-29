
-- ...existing code...

local RP = RealismPackage

if RP == nil then
    print("[RealismPackage] RealismPackage table is missing before DamageLogic initialization")
    return
end

DamageLogic = DamageLogic or RP.damageLogic or RP.damageSystem or {}
RP.damageLogic = DamageLogic
RP.damageSystem = DamageLogic
local damageLogic = RP.damageLogic

local damageByVehicle = setmetatable({}, { __mode = "k" })
local isConsoleCommandRegistered = false
local isVehicleShowInfoHookInstalled = false
local isVehicleShowInfoHookWarningLogged = false

damageLogic.PROFILES = {
    REAL_LIFE = {
        serviceIntervals = { CAR = 10000, TRUCK = 30000 },
        operatingHoursInterval = 500,
        annualServiceDays = 365,
        damageScale = 1.0
    },
    NORMAL = {
        serviceIntervals = { CAR = 5000, TRUCK = 15000 },
        operatingHoursInterval = 250,
        annualServiceDays = 182.5,
        damageScale = 0.5
    },
    FS25 = {
        serviceIntervals = { CAR = 1000, TRUCK = 3000 },
        operatingHoursInterval = 50,
        annualServiceDays = 36.5,
        damageScale = 0.1
    }
}
damageLogic.DEFAULT_PROFILE = "NORMAL"
damageLogic.currentProfile = damageLogic.DEFAULT_PROFILE
damageLogic.AIR_FILTER_INTERVAL_HOURS_NORMAL = 100
damageLogic.AIR_FILTER_INTERVAL_HOURS_DUSTY = 30
damageLogic.COLLISION_DAMAGE = {
    SPEED_THRESHOLD_KMH = 20,
    SPEED_INTENSITY_STEP_KMH = 10,
    INTENSITY_TO_DAMAGE = 0.02,
    MIN_IMPACT_INTENSITY = 0.25,
    MAX_DAMAGE_PER_HIT = 0.35,
    DEBUG_LOG_COLLISIONS = false,
    ENABLE_SPEED_DROP_FALLBACK = true,
    MIN_SPEED_FOR_FALLBACK_KMH = 10,
    MIN_DECEL_PER_SEC_FOR_FALLBACK = 120
}
damageLogic.DAMAGE_ENGINE_IMPACT = {
    START_AT_DAMAGE = 0.15,
    FULL_DAMAGE_TARGET_SPEED_KMH = 5,
    REFERENCE_TOP_SPEED_KMH = 100,
    MIN_POWER_MULTIPLIER_FLOOR = 0.03
}
damageLogic.WORKSHOP_COST = {
    FULL_SERVICE_BASE = 1500,
    FULL_SERVICE_WEAR_FACTOR = 4500,
    FULL_SERVICE_FILTER_FACTOR = 400,
    FILTER_CLEAN_BASE = 300,
    FILTER_CLEAN_WEAR_FACTOR = 1800
}

local function getModSettings()
    if RP ~= nil and type(RP.settings) == "table" then
        return RP.settings
    end

    return { wearEnabled = true, damageEnabled = true, airFilterEnabled = true, difficulty = 2 }
end

local function getDamageProfileName()
    if WearSystem ~= nil and WearSystem.getDamageProfileName ~= nil then
        return WearSystem.getDamageProfileName({
            getProfiles = function()
                return damageLogic.PROFILES
            end,
            getConfiguredProfileName = function()
                return damageLogic.currentProfile or RP.damageProfile
            end,
            getDefaultProfileName = function()
                return damageLogic.DEFAULT_PROFILE
            end
        })
    end

    return damageLogic.DEFAULT_PROFILE
end

local function createSystemContext()
    return {
        getModSettings = getModSettings,
        getProfiles = function()
            return damageLogic.PROFILES
        end,
        getConfiguredProfileName = function()
            return damageLogic.currentProfile or RP.damageProfile
        end,
        getDefaultProfileName = function()
            return damageLogic.DEFAULT_PROFILE
        end,
        getDamageProfileName = getDamageProfileName,
        notifyServiceRequired = function(vehicleState)
            if vehicleState.serviceRequiredNotified then
                return
            end

            vehicleState.serviceRequiredNotified = true

            if g_currentMission ~= nil and g_currentMission.showHelpLineText ~= nil then
                g_currentMission:showHelpLineText("Service Required")
            end
        end,
        airFilterIntervalHoursNormal = damageLogic.AIR_FILTER_INTERVAL_HOURS_NORMAL,
        airFilterIntervalHoursDusty = damageLogic.AIR_FILTER_INTERVAL_HOURS_DUSTY,
        damageEngineImpact = damageLogic.DAMAGE_ENGINE_IMPACT
    }
end

local function getVehicleDamageState(vehicle)
    local state = damageByVehicle[vehicle]

    if state == nil then
        local startingDamage = vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount() or 0
        local startingServiceCondition = type(vehicle.customServiceCondition) == "number"
            and vehicle.customServiceCondition
            or 1
        local startingOperatingTime = type(vehicle.operatingTime) == "number" and vehicle.operatingTime or 0

        local currentDay = 1

        if g_currentMission ~= nil
            and g_currentMission.environment ~= nil
            and type(g_currentMission.environment.dayOfYear) == "number" then
            currentDay = g_currentMission.environment.dayOfYear
        end

        local startingLastServiceDay = type(vehicle.lastServiceDay) == "number" and vehicle.lastServiceDay or currentDay
        local startingAirFilterCondition = type(vehicle.airFilterCondition) == "number" and vehicle.airFilterCondition or 1
        local startingLastMovedDistance = type(vehicle.lastMovedDistance) == "number" and vehicle.lastMovedDistance or 0
        local startingServiceElapsedDays = type(vehicle.serviceElapsedDays) == "number" and vehicle.serviceElapsedDays or 0

        state = {
            totalDamage = math.max(0, math.min(1, startingDamage)),
            engineDisabled = false,
            customServiceCondition = math.max(0, math.min(1, startingServiceCondition)),
            lastOperatingTime = math.max(0, startingOperatingTime),
            lastServiceDay = math.max(1, startingLastServiceDay),
            lastObservedDay = math.max(1, currentDay),
            serviceElapsedDays = math.max(0, startingServiceElapsedDays),
            lastMovedDistance = math.max(0, startingLastMovedDistance),
            airFilterCondition = math.max(0, math.min(1, startingAirFilterCondition)),
            lastAirFilterOperatingTime = math.max(0, startingOperatingTime),
            airFilterPowerPenaltyApplied = false,
            airFilterPreviousPowerMultiplier = 1,
            dirtyFlag = vehicle.getNextDirtyFlag ~= nil and vehicle:getNextDirtyFlag() or nil,
            lastSentServiceCondition = -1,
            lastSentLastServiceDay = -1,
            lastSentLastOperatingTime = -1,
            lastSentAirFilterCondition = -1,
            lastSentLastAirFilterOperatingTime = -1,
            lastSentServiceElapsedDays = -1,
            lastSentLastObservedDay = -1,
            serviceHudTimerMs = 0,
            serviceRequiredNotified = startingServiceCondition <= 0,
            lastSpeedKmh = math.max(0, (type(vehicle.lastSpeed) == "number" and vehicle.lastSpeed or 0) * 3600)
        }

        damageByVehicle[vehicle] = state
        vehicle.customServiceCondition = state.customServiceCondition
        vehicle.lastServiceDay = state.lastServiceDay
        vehicle.serviceElapsedDays = state.serviceElapsedDays
        vehicle.airFilterCondition = state.airFilterCondition
    end

    return state
end

local function markVehicleStateDirty(vehicle, state)
    if vehicle == nil or state == nil or state.dirtyFlag == nil or vehicle.raiseDirtyFlags == nil then
        return
    end

    vehicle:raiseDirtyFlags(state.dirtyFlag)
end


local function getActiveProfile()
    local context = createSystemContext()

    if WearSystem ~= nil and WearSystem.getActiveProfile ~= nil then
        return WearSystem.getActiveProfile(context)
    end

    return damageLogic.PROFILES[damageLogic.DEFAULT_PROFILE]
end

local function getVehicleType(vehicle)
    if WearSystem ~= nil and WearSystem.getVehicleType ~= nil then
        return WearSystem.getVehicleType(vehicle)
    end

    return "CAR"
end

local function forceStopEngine(vehicle)
    if vehicle.setMotorTurnedOn ~= nil then
        vehicle:setMotorTurnedOn(false, true)
    elseif vehicle.stopMotor ~= nil then
        vehicle:stopMotor()
    end
end

local function installVehicleShowInfoHook()
    if Utils ~= nil and type(Utils.appendedFunction) == "function" and DamageLogic and type(DamageLogic.injVehicleShowInfo) == "function" then
        if Vehicle ~= nil and type(Vehicle.showInfo) == "function" and not Vehicle._rpShowInfoHooked then
            Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, DamageLogic.injVehicleShowInfo)
            Vehicle._rpShowInfoHooked = true
        end

        isVehicleShowInfoHookInstalled = Vehicle ~= nil and Vehicle._rpShowInfoHooked == true
        return isVehicleShowInfoHookInstalled
    end

    isVehicleShowInfoHookInstalled = false
    return false
end

local function restoreCriticalDamageOverrides(vehicle)
    local brokenState = vehicle ~= nil and vehicle._rpBrokenState or nil

    if brokenState == nil then
        return false
    end

    local drivable = vehicle.spec_drivable
    if drivable ~= nil and brokenState.speedLimit ~= nil then
        drivable.speedLimit = brokenState.speedLimit
    end

    if vehicle.setPowerMultiplier ~= nil then
        vehicle:setPowerMultiplier(1, true)
    end

    local motor = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil
    if motor ~= nil then
        if brokenState.peakMotorTorque ~= nil then
            motor.peakMotorTorque = brokenState.peakMotorTorque
        end

        if brokenState.maxForwardSpeed ~= nil then
            motor.maxForwardSpeed = brokenState.maxForwardSpeed
        end
    end

    local powerConsumer = vehicle.spec_powerConsumer
    if powerConsumer ~= nil and brokenState.requiredPower ~= nil then
        powerConsumer.requiredPower = brokenState.requiredPower
    end

    vehicle._rpBrokenState = nil
    return true
end

local function getVehicleSpeedKmh(vehicle)
    local speedMps = 0

    if vehicle ~= nil and type(vehicle.lastSpeed) == "number" then
        speedMps = math.max(0, vehicle.lastSpeed)
    end

    return speedMps * 3600
end

local function processCollisionDamage(vehicle, impactIntensity)
    if getModSettings().damageEnabled == false or impactIntensity == nil then return 0, nil, nil end

    local tuning = damageLogic.COLLISION_DAMAGE
    local sanitizedIntensity = math.max(0, impactIntensity)

    if sanitizedIntensity < tuning.MIN_IMPACT_INTENSITY then
        local damageState = getVehicleDamageState(vehicle)
        local currentDamage = vehicle.getDamageAmount ~= nil and (vehicle:getDamageAmount() or 0) or damageState.totalDamage
        return 0, currentDamage, currentDamage
    end

    local profile = getActiveProfile()
    local profileScale = math.max(0, profile.damageScale or 0)
    local instantDamage = sanitizedIntensity * profileScale * tuning.INTENSITY_TO_DAMAGE

    if instantDamage > tuning.MAX_DAMAGE_PER_HIT then
        instantDamage = tuning.MAX_DAMAGE_PER_HIT
    end

    if instantDamage <= 0 then
        local damageState = getVehicleDamageState(vehicle)
        local currentDamage = vehicle.getDamageAmount ~= nil and (vehicle:getDamageAmount() or 0) or damageState.totalDamage
        return 0, currentDamage, currentDamage
    end

    local damageState = getVehicleDamageState(vehicle)
    local currentDamage = vehicle.getDamageAmount ~= nil and (vehicle:getDamageAmount() or 0) or damageState.totalDamage
    local newDamage = math.max(0, math.min(1, currentDamage + instantDamage))

    damageState.totalDamage = newDamage
    if vehicle.setDamageAmount ~= nil then
        vehicle:setDamageAmount(newDamage)
    end

    if newDamage >= 1 and not damageState.engineDisabled then
        damageState.engineDisabled = true
        if g_currentMission ~= nil and g_currentMission.showHelpLineText ~= nil then
            g_currentMission:showHelpLineText("Vehicle critically damaged: limp mode active")
        end
    end

    return instantDamage, currentDamage, newDamage
end

local function processFallbackSpeedImpact(vehicle, state, dt)
    local tuning = damageLogic.COLLISION_DAMAGE

    if not tuning.ENABLE_SPEED_DROP_FALLBACK then
        return
    end

    local dtMs = math.max(0, dt or 0)

    if dtMs <= 0 then
        return
    end

    local currentSpeedKmh = getVehicleSpeedKmh(vehicle)
    local previousSpeedKmh = math.max(0, state.lastSpeedKmh or currentSpeedKmh)
    state.lastSpeedKmh = currentSpeedKmh

    if previousSpeedKmh < tuning.MIN_SPEED_FOR_FALLBACK_KMH then
        return
    end

    local speedDrop = previousSpeedKmh - currentSpeedKmh

    if speedDrop <= 0 then
        return
    end

    local decelPerSecond = speedDrop / (dtMs / 1000)

    if decelPerSecond < tuning.MIN_DECEL_PER_SEC_FOR_FALLBACK then
        return
    end

    local decelIntensity = (decelPerSecond - tuning.MIN_DECEL_PER_SEC_FOR_FALLBACK) / tuning.MIN_DECEL_PER_SEC_FOR_FALLBACK
    local speedIntensity = (previousSpeedKmh - tuning.MIN_SPEED_FOR_FALLBACK_KMH) / 40
    local impactIntensity = math.max(tuning.MIN_IMPACT_INTENSITY, decelIntensity + speedIntensity)

    processCollisionDamage(vehicle, impactIntensity)
end

function damageLogic.init()
    if not isConsoleCommandRegistered then
        if type(addConsoleCommand) == "function" then
            addConsoleCommand("rpCheckVehicle", "Print the current vehicle service type, wear and remaining life", "consoleCommandCheckVehicle", damageLogic)
            isConsoleCommandRegistered = true
        else
            print("[RealismPackage] addConsoleCommand unavailable in this environment")
            isConsoleCommandRegistered = false
        end
    end

    if type(installVehicleShowInfoHook) == "function" then
        installVehicleShowInfoHook()
    else
        isVehicleShowInfoHookInstalled = false
    end

    if not isVehicleShowInfoHookInstalled and not isVehicleShowInfoHookWarningLogged then
        isVehicleShowInfoHookWarningLogged = true
        print("[RealismPackage] Vehicle.showInfo hook was not installed.")
    end
end


function DamageLogic.prerequisitesPresent(specializations)
    return true
end

function DamageLogic.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "clearActionEvents", DamageLogic.clearActionEvents)
    SpecializationUtil.registerFunction(vehicleType, "getVehicleType", DamageLogic.getVehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getServiceStatus", DamageLogic.getServiceStatus)
    SpecializationUtil.registerFunction(vehicleType, "getWorkshopActionCost", DamageLogic.getWorkshopActionCost)
    SpecializationUtil.registerFunction(vehicleType, "getVehicleStatusInfoText", DamageLogic.getVehicleStatusInfoText)
    SpecializationUtil.registerFunction(vehicleType, "cleanAirFilter", DamageLogic.cleanAirFilter)
    SpecializationUtil.registerFunction(vehicleType, "fullService", DamageLogic.fullService)
    SpecializationUtil.registerFunction(vehicleType, "setProfile", DamageLogic.setProfile)
end

function DamageLogic:getAdditionalSchemaTexts(superFunc, ...)
    local text = ""

    if type(superFunc) == "function" then
        text = superFunc(self, ...) or ""
    end

    return text
end


function DamageLogic.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", DamageLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", DamageLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", DamageLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onCollision", DamageLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", DamageLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", DamageLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", DamageLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", DamageLogic)
end

function DamageLogic.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "loadFromXMLFile", DamageLogic.loadFromXMLFile)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "saveToXMLFile", DamageLogic.saveToXMLFile)
    -- Do NOT register the additional schema text/value overwrites.
    -- Leaving those unregistered prevents adding the extra "Status" column to the vehicle schema UI.
end

function DamageLogic.registerSavegameXMLPaths(schema, basePath)
    if schema == nil or basePath == nil then
        return
    end

    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#customServiceCondition", "Custom service condition")
    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#lastServiceDay", "Last service day")
    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#lastOperatingTime", "Last operating time")
    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#serviceElapsedDays", "Service elapsed days")
    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#lastObservedDay", "Last observed day")
    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#lastMovedDistance", "Last moved distance")
    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#airFilterCondition", "Air filter condition")
    schema:register(XMLValueType.FLOAT, basePath .. ".realismPackage#lastAirFilterOperatingTime", "Last air filter operating time")
end

function DamageLogic:onLoad(_savegame)
    if type(installVehicleShowInfoHook) == "function" then
        installVehicleShowInfoHook()
    end

   
    self.spec_damageLogic = {
        actionEvents = {}
    }

    local state = getVehicleDamageState(self)
    state.lastMovedDistance = math.max(0, self.lastMovedDistance or state.lastMovedDistance)
    state.lastOperatingTime = math.max(0, self.operatingTime or state.lastOperatingTime)
    state.lastAirFilterOperatingTime = math.max(0, self.operatingTime or state.lastAirFilterOperatingTime)
end

function DamageLogic:onDelete()
    local state = damageByVehicle[self]

    if state ~= nil then
        if AirFilterSystem ~= nil and AirFilterSystem.resetEngineImpact ~= nil then
            AirFilterSystem.resetEngineImpact(self, state, createSystemContext())
        end

        damageByVehicle[self] = nil
    end

    restoreCriticalDamageOverrides(self)
end

function DamageLogic:onCollision(...)
    if self.isServer == false then
        return
    end

    local strongestCollisionValue = 0
    local collisionArgs = { ... }

    for argIndex = 1, #collisionArgs do
        local value = collisionArgs[argIndex]

        if type(value) == "number" then
            strongestCollisionValue = math.max(strongestCollisionValue, math.abs(value))
        end
    end

    local tuning = damageLogic.COLLISION_DAMAGE
    local speedKmh = getVehicleSpeedKmh(self)
    local speedIntensity = 0

    if speedKmh > tuning.SPEED_THRESHOLD_KMH then
        speedIntensity = (speedKmh - tuning.SPEED_THRESHOLD_KMH) / tuning.SPEED_INTENSITY_STEP_KMH
    end

    local impactIntensity = math.max(strongestCollisionValue, speedIntensity)

    processCollisionDamage(self, impactIntensity)
end

function DamageLogic:onUpdate(dt)
    if type(installVehicleShowInfoHook) == "function" then
        installVehicleShowInfoHook() -- silently retry until success
    end

    local damageState = getVehicleDamageState(self)
    local context = createSystemContext()

    if self.isServer then
        processFallbackSpeedImpact(self, damageState, dt)

        -- Hard-limit speed and torque when fully damaged; restore when repaired
        local drivable = self.spec_drivable
        local gameDamage = self.getDamageAmount ~= nil and (self:getDamageAmount() or 0) or 0

        if damageState.totalDamage >= 1 or gameDamage >= 1 then

            -- Save original values once
            if self._rpBrokenState == nil then
                self._rpBrokenState = {
                    speedLimit = drivable and drivable.speedLimit or nil,
                    requiredPower = self.spec_powerConsumer ~= nil and self.spec_powerConsumer.requiredPower or nil,
                    peakMotorTorque = self.spec_motorized ~= nil and self.spec_motorized.motor ~= nil and self.spec_motorized.motor.peakMotorTorque or nil,
                    maxForwardSpeed = self.spec_motorized ~= nil and self.spec_motorized.motor ~= nil and self.spec_motorized.motor.maxForwardSpeed or nil
                }
                print("[RealismPackage] Vehicle entered critical damage state")
            end

            -- Hard speed limit
            if drivable ~= nil then
                drivable.speedLimit = 5
            end

            -- Kill engine torque/power (no-op if API unavailable, harmless)
            if self.setPowerMultiplier ~= nil then
                self:setPowerMultiplier(0.01, true)
            end

            -- Force low speed via motor fields
            if self.spec_motorized ~= nil and self.spec_motorized.motor ~= nil then
                local motor = self.spec_motorized.motor

                if motor.peakMotorTorque ~= nil then
                    motor.peakMotorTorque = 5
                end

                if type(motor.maxForwardSpeed) == "number" then
                    -- maxForwardSpeed is in m/s; 5 km/h = 1.39 m/s
                    motor.maxForwardSpeed = 5 / 3.6
                end
            end

            -- Stop PTO / heavy attached tools
            if self.spec_powerConsumer ~= nil then
                self.spec_powerConsumer.requiredPower = 999999
            end

        else

            -- Restore vehicle to normal when damage drops below 100%
            if self._rpBrokenState ~= nil then
                print("[RealismPackage] Vehicle restored from critical damage")
                restoreCriticalDamageOverrides(self)
            end

            -- Graduated penalty (< 100% damage) is handled by AirFilterSystem.applyEngineImpact below
        end

        local stateChanged = false
        if WearSystem ~= nil and WearSystem.process ~= nil and WearSystem.process(self, damageState, context) then
            stateChanged = true
        end
        if AirFilterSystem ~= nil and AirFilterSystem.process ~= nil and AirFilterSystem.process(self, damageState, context) then
            stateChanged = true
        end
        if stateChanged then markVehicleStateDirty(self, damageState) end
    else
        if AirFilterSystem ~= nil and AirFilterSystem.applyEngineImpact ~= nil then
            AirFilterSystem.applyEngineImpact(self, damageState, context)
        end
    end

end

function DamageLogic:clearActionEvents()
    local spec = self.spec_damageLogic
    if spec ~= nil and spec.actionEvents ~= nil and g_inputBinding ~= nil then
        for _, actionEventId in pairs(spec.actionEvents) do
            g_inputBinding:removeActionEvent(actionEventId)
        end
        spec.actionEvents = {}
    end
end

-- Diagnostic dashboard and RealismMenu GUI logic removed

function DamageLogic:getVehicleType()
    return getVehicleType(self)
end

function DamageLogic:cleanAirFilter()
    local state = getVehicleDamageState(self)
    local changed = false

    if AirFilterSystem ~= nil and AirFilterSystem.clean ~= nil then
        changed = AirFilterSystem.clean(self, state, createSystemContext())
    end

    if self.isServer and changed then
        markVehicleStateDirty(self, state)
    end

    return true
end

function DamageLogic:fullService()
    local state = getVehicleDamageState(self)
    local stateChanged = false

    if WearSystem ~= nil and WearSystem.fullService ~= nil then
        stateChanged = WearSystem.fullService(self, state) or stateChanged
    end

    if AirFilterSystem ~= nil and AirFilterSystem.clean ~= nil then
        stateChanged = AirFilterSystem.clean(self, state, createSystemContext()) or stateChanged
    end

    if self.isServer and stateChanged then
        markVehicleStateDirty(self, state)
    end

    return true
end

function DamageLogic:setProfile(profileName)
    if type(profileName) ~= "string" then return false end
    local normalized = string.upper(profileName)
    if damageLogic.PROFILES[normalized] == nil then return false end

    damageLogic.currentProfile = normalized
    if RP ~= nil and type(RP.settings) == "table" then
        local difficultyByProfile = { FS25 = 1, NORMAL = 2, REAL_LIFE = 3 }
        RP.settings.difficulty = difficultyByProfile[normalized] or 2
        if RP.markSettingsDirty ~= nil then RP:markSettingsDirty() end
    end
    return true
end

function DamageLogic:getServiceStatus()
    local state = getVehicleDamageState(self)

    if WearSystem ~= nil and WearSystem.getServiceStatus ~= nil then
        return WearSystem.getServiceStatus(self, state, createSystemContext())
    end

    return 1, "Remaining: 0 km"
end

function DamageLogic:getWorkshopActionCost(actionType)
    local state = getVehicleDamageState(self)
    local serviceWear = math.max(0, math.min(1, 1 - (state.customServiceCondition or 1)))
    local filterWear = math.max(0, math.min(1, 1 - (state.airFilterCondition or 1)))
    local price = 0

    if actionType == 1 then
        local cost = damageLogic.WORKSHOP_COST
        price = cost.FULL_SERVICE_BASE
            + (serviceWear * cost.FULL_SERVICE_WEAR_FACTOR)
            + (filterWear * cost.FULL_SERVICE_FILTER_FACTOR)
    elseif actionType == 2 then
        local cost = damageLogic.WORKSHOP_COST
        price = cost.FILTER_CLEAN_BASE + (filterWear * cost.FILTER_CLEAN_WEAR_FACTOR)
    end

    return math.max(0, math.floor(price + 0.5))
end

function DamageLogic:getVehicleStatusInfoText()
    local condition, remainingText = self:getServiceStatus()
    local statusPercent = math.max(0, math.min(100, math.floor((condition or 0) * 100 + 0.5)))

    if type(remainingText) ~= "string" then
        remainingText = "n/a"
    end

    if string.find(remainingText, "Remaining:", 1, true) == 1 then
        remainingText = string.gsub(remainingText, "Remaining:", "", 1)
        remainingText = string.gsub(remainingText, "^%s+", "")
    end

    return string.format("%d%% (%s)", statusPercent, remainingText)
end

function DamageLogic:getAdditionalSchemaValues(superFunc, ...)
    local values = nil

    if superFunc ~= nil then
        values = superFunc(self, ...)
    end

    if type(values) ~= "table" then
        values = {}
    end

    table.insert(values, self:getVehicleStatusInfoText())
    return values
end

function DamageLogic:getAdditionalSchemaText(superFunc, ...)
    local text = ""

    if superFunc ~= nil then
        text = superFunc(self, ...) or ""
    end

    if text == "" then
        return "Status"
    end

    return string.format("%s|Status", text)
end

function DamageLogic:getAdditionalSchemaValue(superFunc, ...)
    local value = ""

    if superFunc ~= nil then
        value = superFunc(self, ...) or ""
    end

    local statusText = self:getVehicleStatusInfoText()

    if value == "" then
        return statusText
    end

    return string.format("%s|%s", value, statusText)
end

function damageLogic:consoleCommandCheckVehicle()
    local mission = g_currentMission
    if mission == nil or mission.controlledVehicle == nil then
        print(string.format("[%s] rpCheckVehicle: no controlled vehicle", RP.modName))
        return
    end

    local vehicle = mission.controlledVehicle
    if vehicle.getVehicleType == nil then
        print(string.format("[%s] rpCheckVehicle: vehicle does not have RealismPackage specialization", RP.modName))
        return
    end

    local vehicleType = vehicle:getVehicleType()
    local condition, remainingText = vehicle:getServiceStatus()
    local accumulatedWear = 1 - condition

    print(string.format("[%s] rpCheckVehicle -> type=%s, wear=%.3f, %s", RP.modName, vehicleType, accumulatedWear, remainingText))
end

function damageLogic.delete()
    if damageLogic.clearActionEvents ~= nil then
        damageLogic:clearActionEvents()
    end
    if isConsoleCommandRegistered then
        removeConsoleCommand("rpCheckVehicle")
        isConsoleCommandRegistered = false
    end
    damageByVehicle = setmetatable({}, { __mode = "k" })
end

local function resolveXmlArgs(superFunc, xmlFile, key)
    local resolvedXmlFile = nil
    local resolvedKey = nil

    if type(superFunc) == "table" and type(xmlFile) == "string" then
        resolvedXmlFile = superFunc
        resolvedKey = xmlFile
    else
        resolvedXmlFile = xmlFile
        resolvedKey = key
    end

    if type(resolvedXmlFile) ~= "table" or type(resolvedKey) ~= "string" then
        return nil, nil
    end

    return resolvedXmlFile, resolvedKey
end

function DamageLogic:loadFromXMLFile(superFunc, xmlFile, key)
    if type(superFunc) == "function" then
        superFunc(self, xmlFile, key)
    end

    local resolvedXmlFile, resolvedKey = resolveXmlArgs(superFunc, xmlFile, key)

    if resolvedXmlFile == nil or resolvedKey == nil then
        return
    end

    local damageState = getVehicleDamageState(self)

    damageState.customServiceCondition = math.max(0, math.min(1, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#customServiceCondition", 1)))
    damageState.lastServiceDay = math.max(1, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#lastServiceDay", damageState.lastServiceDay))
    damageState.lastOperatingTime = math.max(0, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#lastOperatingTime", self.operatingTime or 0))
    damageState.serviceElapsedDays = math.max(0, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#serviceElapsedDays", damageState.serviceElapsedDays))
    damageState.lastObservedDay = math.max(1, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#lastObservedDay", damageState.lastObservedDay))
    damageState.lastMovedDistance = math.max(0, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#lastMovedDistance", self.lastMovedDistance or 0))
    damageState.airFilterCondition = math.max(0, math.min(1, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#airFilterCondition", 1)))
    damageState.lastAirFilterOperatingTime = math.max(0, resolvedXmlFile:getValue(resolvedKey .. ".realismPackage#lastAirFilterOperatingTime", self.operatingTime or damageState.lastOperatingTime))
    damageState.serviceRequiredNotified = damageState.customServiceCondition <= 0

    self.customServiceCondition = damageState.customServiceCondition
    self.lastServiceDay = damageState.lastServiceDay
    self.serviceElapsedDays = damageState.serviceElapsedDays
    self.airFilterCondition = damageState.airFilterCondition
end

function DamageLogic:saveToXMLFile(superFunc, xmlFile, key)
    if type(superFunc) == "function" then
        superFunc(self, xmlFile, key)
    end

    local resolvedXmlFile, resolvedKey = resolveXmlArgs(superFunc, xmlFile, key)

    if resolvedXmlFile == nil or resolvedKey == nil then
        return
    end

    local damageState = getVehicleDamageState(self)

    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#customServiceCondition", damageState.customServiceCondition)
    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#lastServiceDay", damageState.lastServiceDay)
    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#lastOperatingTime", damageState.lastOperatingTime)
    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#serviceElapsedDays", damageState.serviceElapsedDays)
    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#lastObservedDay", damageState.lastObservedDay)
    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#lastMovedDistance", damageState.lastMovedDistance)
    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#airFilterCondition", damageState.airFilterCondition)
    resolvedXmlFile:setValue(resolvedKey .. ".realismPackage#lastAirFilterOperatingTime", damageState.lastAirFilterOperatingTime)
end

function DamageLogic:onReadStream(streamId, _connection)
    local damageState = getVehicleDamageState(self)
    damageState.customServiceCondition = math.max(0, math.min(1, streamReadFloat32(streamId)))
    damageState.lastServiceDay = math.max(1, streamReadFloat32(streamId))
    damageState.lastOperatingTime = math.max(0, streamReadFloat32(streamId))
    damageState.serviceElapsedDays = math.max(0, streamReadFloat32(streamId))
    damageState.lastObservedDay = math.max(1, streamReadFloat32(streamId))
    damageState.lastMovedDistance = math.max(0, streamReadFloat32(streamId))
    damageState.airFilterCondition = math.max(0, math.min(1, streamReadFloat32(streamId)))
    damageState.lastAirFilterOperatingTime = math.max(0, streamReadFloat32(streamId))
    damageState.serviceRequiredNotified = damageState.customServiceCondition <= 0

    self.customServiceCondition = damageState.customServiceCondition
    self.lastServiceDay = damageState.lastServiceDay
    self.serviceElapsedDays = damageState.serviceElapsedDays
    self.airFilterCondition = damageState.airFilterCondition
end

function DamageLogic:onWriteStream(streamId, _connection)
    local damageState = getVehicleDamageState(self)
    streamWriteFloat32(streamId, damageState.customServiceCondition)
    streamWriteFloat32(streamId, damageState.lastServiceDay)
    streamWriteFloat32(streamId, damageState.lastOperatingTime)
    streamWriteFloat32(streamId, damageState.serviceElapsedDays)
    streamWriteFloat32(streamId, damageState.lastObservedDay)
    streamWriteFloat32(streamId, damageState.lastMovedDistance)
    streamWriteFloat32(streamId, damageState.airFilterCondition)
    streamWriteFloat32(streamId, damageState.lastAirFilterOperatingTime)
end

function DamageLogic:onReadUpdateStream(streamId, _timestamp, _connection)
    local damageState = getVehicleDamageState(self)
    local hasChanges = streamReadBool(streamId)
    if not hasChanges then return end

    damageState.customServiceCondition = math.max(0, math.min(1, streamReadFloat32(streamId)))
    damageState.lastServiceDay = math.max(1, streamReadFloat32(streamId))
    damageState.lastOperatingTime = math.max(0, streamReadFloat32(streamId))
    damageState.serviceElapsedDays = math.max(0, streamReadFloat32(streamId))
    damageState.lastObservedDay = math.max(1, streamReadFloat32(streamId))
    damageState.lastMovedDistance = math.max(0, streamReadFloat32(streamId))
    damageState.airFilterCondition = math.max(0, math.min(1, streamReadFloat32(streamId)))
    damageState.lastAirFilterOperatingTime = math.max(0, streamReadFloat32(streamId))
    damageState.serviceRequiredNotified = damageState.customServiceCondition <= 0

    self.customServiceCondition = damageState.customServiceCondition
    self.lastServiceDay = damageState.lastServiceDay
    self.serviceElapsedDays = damageState.serviceElapsedDays
    self.airFilterCondition = damageState.airFilterCondition
end

function DamageLogic:onWriteUpdateStream(streamId, _connection, _dirtyMask)
    local damageState = getVehicleDamageState(self)
    local hasChanges = false

    if math.abs(damageState.customServiceCondition - damageState.lastSentServiceCondition) > 0.0001
        or math.abs(damageState.lastServiceDay - damageState.lastSentLastServiceDay) > 0.0001
        or math.abs(damageState.lastOperatingTime - damageState.lastSentLastOperatingTime) > 0.0001
        or math.abs(damageState.airFilterCondition - damageState.lastSentAirFilterCondition) > 0.0001
        or math.abs(damageState.lastAirFilterOperatingTime - damageState.lastSentLastAirFilterOperatingTime) > 0.0001
        or math.abs(damageState.serviceElapsedDays - damageState.lastSentServiceElapsedDays) > 0.0001
        or math.abs(damageState.lastObservedDay - damageState.lastSentLastObservedDay) > 0.0001 then
        hasChanges = true
    end

    streamWriteBool(streamId, hasChanges)
    if not hasChanges then return end

    streamWriteFloat32(streamId, damageState.customServiceCondition)
    streamWriteFloat32(streamId, damageState.lastServiceDay)
    streamWriteFloat32(streamId, damageState.lastOperatingTime)
    streamWriteFloat32(streamId, damageState.serviceElapsedDays)
    streamWriteFloat32(streamId, damageState.lastObservedDay)
    streamWriteFloat32(streamId, damageState.lastMovedDistance)
    streamWriteFloat32(streamId, damageState.airFilterCondition)
    streamWriteFloat32(streamId, damageState.lastAirFilterOperatingTime)

    damageState.lastSentServiceCondition = damageState.customServiceCondition
    damageState.lastSentLastServiceDay = damageState.lastServiceDay
    damageState.lastSentLastOperatingTime = damageState.lastOperatingTime
    damageState.lastSentAirFilterCondition = damageState.airFilterCondition
    damageState.lastSentLastAirFilterOperatingTime = damageState.lastAirFilterOperatingTime
    damageState.lastSentServiceElapsedDays = damageState.serviceElapsedDays
    damageState.lastSentLastObservedDay = damageState.lastObservedDay
end

-- Vehicle info preview injection
function DamageLogic.injVehicleShowInfo(vehicle, infoBox)
    if vehicle == nil or infoBox == nil or type(infoBox.addLine) ~= "function" then
        print("[RealismPackage] injVehicleShowInfo: no infoBox or addLine method")
        return
    end

    local state = getVehicleDamageState(vehicle)
    if state == nil then
        print("[RealismPackage] injVehicleShowInfo: no damage state for vehicle")
        return
    end
    -- Wear and Air Filter as percent
    local labelWear = "Wear"
    local labelAir = "Air Filter"
    if g_i18n ~= nil and type(g_i18n.getText) == "function" then
        labelWear = g_i18n:getText("infohud_rpWear") or labelWear
        labelAir = g_i18n:getText("infohud_rpAirFilter") or labelAir
    end

    local serviceCond = state.customServiceCondition or vehicle.customServiceCondition or 1
    local wearPercent = math.floor((1 - math.max(0, math.min(1, serviceCond))) * 100 + 0.5)
    local airFilterPercent = math.floor((state.airFilterCondition or vehicle.airFilterCondition or 1) * 100 + 0.5)

    infoBox:addLine(labelWear, string.format("%d %%", wearPercent))
    infoBox:addLine(labelAir, string.format("%d %%", airFilterPercent))

    -- Intentionally avoid per-frame logging here to keep log noise low.
end