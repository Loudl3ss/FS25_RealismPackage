-- luacheck: globals WearSystem g_currentMission

WearSystem = WearSystem or {}
local wearSystem = WearSystem

local function getProfiles(context)
    if context ~= nil and context.getProfiles ~= nil then
        local profiles = context.getProfiles()

        if type(profiles) == "table" then
            return profiles
        end
    end

    return {}
end

function wearSystem.getDamageProfileName(context)
    local profiles = getProfiles(context)
    local configuredProfile = nil

    if context ~= nil and context.getConfiguredProfileName ~= nil then
        configuredProfile = context.getConfiguredProfileName()
    end

    if type(configuredProfile) == "string" then
        local profile = string.upper(configuredProfile)

        if profiles[profile] ~= nil then
            return profile
        end
    end

    if context ~= nil and context.getDefaultProfileName ~= nil then
        return context.getDefaultProfileName()
    end

    return "NORMAL"
end

function wearSystem.getActiveProfile(context)
    local profiles = getProfiles(context)
    local profileName = wearSystem.getDamageProfileName(context)

    return profiles[profileName] or profiles.NORMAL or profiles.FS25 or profiles.REAL_LIFE or {}
end

function wearSystem.isTractorVehicle(vehicle)
    if vehicle == nil or vehicle.spec_motorized == nil then
        return false
    end

    if vehicle.spec_combine ~= nil or vehicle.spec_attacherJoints ~= nil then
        return true
    end

    if type(vehicle.typeName) == "string" then
        local name = string.lower(vehicle.typeName)

        if string.find(name, "tractor", 1, true)
            or string.find(name, "combine", 1, true)
            or string.find(name, "harvester", 1, true) then
            return true
        end
    end

    return false
end

function wearSystem.isTruckVehicle(vehicle)
    if vehicle == nil then
        return false
    end

    if type(vehicle.typeName) == "string" and string.find(string.lower(vehicle.typeName), "truck", 1, true) then
        return true
    end

    if type(vehicle.category) == "string" and string.find(string.lower(vehicle.category), "truck", 1, true) then
        return true
    end

    return false
end

function wearSystem.getVehicleType(vehicle)
    if wearSystem.isTractorVehicle(vehicle) then
        return "TRACTOR"
    end

    if wearSystem.isTruckVehicle(vehicle) then
        return "TRUCK"
    end

    return "CAR"
end

function wearSystem.getCurrentDayOfYear()
    if g_currentMission ~= nil
        and g_currentMission.environment ~= nil
        and type(g_currentMission.environment.dayOfYear) == "number" then
        return g_currentMission.environment.dayOfYear
    end

    return nil
end

function wearSystem.updateElapsedServiceDays(state)
    local currentDayOfYear = wearSystem.getCurrentDayOfYear()

    if currentDayOfYear == nil then
        return
    end

    if type(state.lastObservedDay) ~= "number" then
        state.lastObservedDay = currentDayOfYear
        return
    end

    local deltaDays = currentDayOfYear - state.lastObservedDay

    if deltaDays < 0 then
        deltaDays = deltaDays + 365
    end

    if deltaDays > 0 then
        state.serviceElapsedDays = math.max(0, state.serviceElapsedDays + deltaDays)
        state.lastObservedDay = currentDayOfYear
    end
end

function wearSystem.applyAnnualServiceCheck(vehicle, state, context)
    local profile = wearSystem.getActiveProfile(context)
    local vehicleType = wearSystem.getVehicleType(vehicle)

    if vehicleType ~= "TRACTOR" and vehicleType ~= "TRUCK" and vehicleType ~= "CAR" then
        return false
    end

    local annualDayLimit = profile.annualServiceDays or 365

    if state.serviceElapsedDays > annualDayLimit and state.customServiceCondition > 0 then
        state.customServiceCondition = 0
        vehicle.customServiceCondition = 0

        if context ~= nil and context.notifyServiceRequired ~= nil then
            context.notifyServiceRequired(state)
        end

        return true
    end

    return false
end

function wearSystem.process(vehicle, state, context)
    if context ~= nil
        and context.getModSettings ~= nil
        and context.getModSettings().wearEnabled == false then
        return false
    end

    local profile = wearSystem.getActiveProfile(context)
    local vehicleType = wearSystem.getVehicleType(vehicle)
    local reduction = 0
    local previousCondition = state.customServiceCondition
    local previousElapsedDays = state.serviceElapsedDays
    local previousObservedDay = state.lastObservedDay

    if vehicleType == "TRACTOR" then
        local currentOperatingTime = math.max(0, vehicle.operatingTime or state.lastOperatingTime)
        local operatingDeltaMs = math.max(0, currentOperatingTime - state.lastOperatingTime)

        state.lastOperatingTime = currentOperatingTime

        local intervalMs = math.max(0, profile.operatingHoursInterval or 0) * 3600 * 1000

        if intervalMs > 0 then
            reduction = operatingDeltaMs / intervalMs
        end
    else
        local movedDistance = math.max(0, vehicle.lastMovedDistance or state.lastMovedDistance)
        local deltaDistance = math.max(0, movedDistance - state.lastMovedDistance)

        state.lastMovedDistance = movedDistance

        local serviceInterval = profile.serviceIntervals ~= nil
            and (profile.serviceIntervals[vehicleType] or profile.serviceIntervals.CAR or 0)
            or 0

        if serviceInterval > 0 then
            reduction = (deltaDistance / 1000) / serviceInterval
        end
    end

    state.customServiceCondition = math.max(0, math.min(1, state.customServiceCondition - reduction))
    vehicle.customServiceCondition = state.customServiceCondition

    wearSystem.updateElapsedServiceDays(state)
    vehicle.serviceElapsedDays = state.serviceElapsedDays

    local annualServiceTriggered = wearSystem.applyAnnualServiceCheck(vehicle, state, context)

    if state.customServiceCondition <= 0
        and context ~= nil
        and context.notifyServiceRequired ~= nil then
        context.notifyServiceRequired(state)
    end

    return annualServiceTriggered
        or math.abs(state.customServiceCondition - previousCondition) > 0.0001
        or math.abs(state.serviceElapsedDays - previousElapsedDays) > 0.0001
        or math.abs(state.lastObservedDay - previousObservedDay) > 0.0001
end

function wearSystem.fullService(vehicle, state)
    local currentDay = wearSystem.getCurrentDayOfYear() or state.lastObservedDay or state.lastServiceDay
    local previousCondition = state.customServiceCondition
    local previousElapsedDays = state.serviceElapsedDays
    local previousLastServiceDay = state.lastServiceDay
    local previousObservedDay = state.lastObservedDay

    state.customServiceCondition = 1
    state.lastServiceDay = currentDay
    state.lastObservedDay = currentDay
    state.serviceElapsedDays = 0
    state.lastMovedDistance = math.max(0, vehicle.lastMovedDistance or state.lastMovedDistance)
    state.serviceRequiredNotified = false

    vehicle.customServiceCondition = 1
    vehicle.lastServiceDay = state.lastServiceDay
    vehicle.serviceElapsedDays = state.serviceElapsedDays

    return math.abs(previousCondition - state.customServiceCondition) > 0.0001
        or math.abs(previousElapsedDays - state.serviceElapsedDays) > 0.0001
        or math.abs(previousLastServiceDay - state.lastServiceDay) > 0.0001
        or math.abs(previousObservedDay - state.lastObservedDay) > 0.0001
end

function wearSystem.getServiceStatus(vehicle, state, context)
    local profile = wearSystem.getActiveProfile(context)
    local vehicleType = wearSystem.getVehicleType(vehicle)
    local condition = math.max(0, math.min(1, state.customServiceCondition or 1))

    if vehicleType == "TRACTOR" then
        local remainingValue = condition * (profile.operatingHoursInterval or 0)
        return condition, string.format("Remaining: %.1f h", remainingValue)
    end

    local serviceInterval = profile.serviceIntervals ~= nil
        and (profile.serviceIntervals[vehicleType] or profile.serviceIntervals.CAR or 0)
        or 0
    local remainingValue = condition * serviceInterval

    return condition, string.format("Remaining: %d km", math.max(0, math.floor(remainingValue + 0.5)))
end
