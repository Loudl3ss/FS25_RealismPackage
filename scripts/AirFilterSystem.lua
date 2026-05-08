-- luacheck: globals AirFilterSystem

AirFilterSystem = AirFilterSystem or {}
local airFilterSystem = AirFilterSystem

local function getEstimatedTopSpeedKmh(vehicle, context)
    local topSpeedKmh = nil

    if vehicle ~= nil and vehicle.spec_motorized ~= nil then
        local spec = vehicle.spec_motorized

        if spec.motor ~= nil then
            if type(spec.motor.maxForwardSpeed) == "number" then
                topSpeedKmh = (spec.motor.maxForwardSpeed or 0) * 3.6
            elseif spec.motor.getMaximumForwardSpeed ~= nil then
                local value = spec.motor:getMaximumForwardSpeed()
                if type(value) == "number" then
                    topSpeedKmh = value * 3.6
                end
            end
        end

        if topSpeedKmh == nil and type(spec.maxForwardSpeed) == "number" then
            topSpeedKmh = (spec.maxForwardSpeed or 0) * 3.6
        end
    end

    if type(topSpeedKmh) ~= "number" or topSpeedKmh <= 0 then
        local impactConfig = context ~= nil and context.damageEngineImpact or nil
        topSpeedKmh = impactConfig ~= nil and impactConfig.REFERENCE_TOP_SPEED_KMH or 100
    end

    return math.max(1, topSpeedKmh)
end

local function getDamagePenaltyMultiplier(vehicle, context)
    local damageAmount = vehicle ~= nil and vehicle.getDamageAmount ~= nil and (vehicle:getDamageAmount() or 0) or 0
    local impactConfig = context ~= nil and context.damageEngineImpact or nil
    local startAtDamage = impactConfig ~= nil and impactConfig.START_AT_DAMAGE or 0.15

    if damageAmount <= startAtDamage then
        return 1
    end

    local normalizedDamage = (damageAmount - startAtDamage) / math.max(0.0001, 1 - startAtDamage)
    local targetSpeedKmh = impactConfig ~= nil and impactConfig.FULL_DAMAGE_TARGET_SPEED_KMH or 5
    local topSpeedKmh = getEstimatedTopSpeedKmh(vehicle, context)
    local minimumFloor = impactConfig ~= nil and impactConfig.MIN_POWER_MULTIPLIER_FLOOR or 0.03
    local minimumPowerMultiplier = math.max(minimumFloor, math.min(1, targetSpeedKmh / topSpeedKmh))

    return math.max(minimumPowerMultiplier, 1 - (normalizedDamage * (1 - minimumPowerMultiplier)))
end

function airFilterSystem.getProfileShorteningFactor(context)
    local profileName = "NORMAL"

    if context ~= nil and context.getDamageProfileName ~= nil then
        profileName = context.getDamageProfileName()
    end

    if profileName == "FS25" then
        return 3
    end

    if profileName == "NORMAL" then
        return 2
    end

    return 1
end

function airFilterSystem.isAttachedImplementActive(vehicle)
    if vehicle == nil or vehicle.getAttachedImplements == nil then
        return false
    end

    local attachedImplements = vehicle:getAttachedImplements()

    if type(attachedImplements) ~= "table" then
        return false
    end

    for _, implementData in pairs(attachedImplements) do
        local implement = type(implementData) == "table"
            and implementData.object ~= nil
            and implementData.object
            or implementData

        if implement ~= nil and implement.getIsLowered ~= nil then
            local isLowered = implement:getIsLowered()
            local isActivated = (implement.getIsActivated ~= nil and implement:getIsActivated())
                or (implement.getIsTurnedOn ~= nil and implement:getIsTurnedOn())
                or false

            if isLowered and isActivated then
                return true
            end
        end
    end

    return false
end

function airFilterSystem.isVehicleInDustyEnvironment(vehicle)
    local isInField = vehicle ~= nil and vehicle.getLastInField ~= nil and vehicle:getLastInField() == true

    return isInField or airFilterSystem.isAttachedImplementActive(vehicle)
end

function airFilterSystem.applyEngineImpact(vehicle, state, context)
    local settings = context ~= nil and context.getModSettings ~= nil and context.getModSettings() or {}
    local motorized = vehicle ~= nil and vehicle.getMotor ~= nil and vehicle:getMotor() or nil

    if motorized == nil or motorized.setPowerMultiplier == nil then
        return false
    end

    local shouldApplyPenalty = false
    local airFilterPenaltyMultiplier = 1
    local damagePenaltyMultiplier = 1

    if settings.airFilterEnabled ~= false and state.airFilterCondition < 0.2 then
        airFilterPenaltyMultiplier = 0.8
        shouldApplyPenalty = true
    end

    if settings.damageEnabled ~= false then
        damagePenaltyMultiplier = getDamagePenaltyMultiplier(vehicle, context)

        if damagePenaltyMultiplier < 0.9999 then
            shouldApplyPenalty = true
        end
    end

    if shouldApplyPenalty then
        if not state.airFilterPowerPenaltyApplied then
            state.airFilterPreviousPowerMultiplier = motorized.getPowerMultiplier ~= nil
                and (motorized:getPowerMultiplier() or 1)
                or 1
            state.airFilterPowerPenaltyApplied = true
        end

        local targetMultiplier = math.max(0, (state.airFilterPreviousPowerMultiplier or 1) * airFilterPenaltyMultiplier * damagePenaltyMultiplier)
        local currentMultiplier = motorized.getPowerMultiplier ~= nil and (motorized:getPowerMultiplier() or 1) or nil

        if currentMultiplier == nil or math.abs(currentMultiplier - targetMultiplier) > 0.0001 then
            motorized:setPowerMultiplier(targetMultiplier)
            return true
        end

        return false
    end

    if state.airFilterPowerPenaltyApplied then
        motorized:setPowerMultiplier(math.max(0, state.airFilterPreviousPowerMultiplier or 1))
        state.airFilterPowerPenaltyApplied = false
        state.airFilterPreviousPowerMultiplier = 1
        return true
    end

    return false
end

function airFilterSystem.process(vehicle, state, context)
    if context ~= nil
        and context.getModSettings ~= nil
        and context.getModSettings().airFilterEnabled == false then
        return airFilterSystem.applyEngineImpact(vehicle, state, context)
    end

    local previousCondition = state.airFilterCondition
    local currentOperatingTime = math.max(0, vehicle.operatingTime or state.lastAirFilterOperatingTime)
    local operatingDeltaMs = math.max(0, currentOperatingTime - state.lastAirFilterOperatingTime)

    state.lastAirFilterOperatingTime = currentOperatingTime

    local profileShorteningFactor = airFilterSystem.getProfileShorteningFactor(context)
    local baseIntervalHours = airFilterSystem.isVehicleInDustyEnvironment(vehicle)
        and (context ~= nil and context.airFilterIntervalHoursDusty or 30)
        or (context ~= nil and context.airFilterIntervalHoursNormal or 100)
    local intervalMs = math.max(0, baseIntervalHours / profileShorteningFactor) * 3600 * 1000
    local reduction = intervalMs > 0 and (operatingDeltaMs / intervalMs) or 0

    state.airFilterCondition = math.max(0, math.min(1, state.airFilterCondition - reduction))
    vehicle.airFilterCondition = state.airFilterCondition

    local impactChanged = airFilterSystem.applyEngineImpact(vehicle, state, context)

    return impactChanged or math.abs(state.airFilterCondition - previousCondition) > 0.0001
end

function airFilterSystem.clean(vehicle, state, context)
    local previousCondition = state.airFilterCondition

    state.airFilterCondition = 1
    state.lastAirFilterOperatingTime = math.max(0, vehicle.operatingTime or state.lastAirFilterOperatingTime)
    vehicle.airFilterCondition = 1

    local impactChanged = airFilterSystem.applyEngineImpact(vehicle, state, context)

    return impactChanged or math.abs(previousCondition - state.airFilterCondition) > 0.0001
end

function airFilterSystem.resetEngineImpact(vehicle, state, context)
    local resetState = {
        airFilterCondition = 1,
        airFilterPowerPenaltyApplied = state.airFilterPowerPenaltyApplied,
        airFilterPreviousPowerMultiplier = state.airFilterPreviousPowerMultiplier
    }

    airFilterSystem.applyEngineImpact(vehicle, resetState, context)
end
