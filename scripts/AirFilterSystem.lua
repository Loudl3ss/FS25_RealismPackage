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
    local motor = vehicle ~= nil and vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil

    -- motor.maxForwardSpeed (m/s) is the reliable Giants API field for capping vehicle speed
    if motor == nil or type(motor.maxForwardSpeed) ~= "number" then
        return false
    end

    -- Always derive the original speed from the saved value, never from the current
    -- motor.maxForwardSpeed which may already be reduced — this prevents a feedback spiral
    -- where each frame treats the already-penalised speed as the new baseline.
    local originalSpeedMs = state.airFilterPowerPenaltyApplied
        and type(state.airFilterPreviousPowerMultiplier) == "number"
        and state.airFilterPreviousPowerMultiplier
        or motor.maxForwardSpeed
    local originalTopSpeedKmh = math.max(1, originalSpeedMs * 3.6)

    -- Air filter penalty (kicks in below 20% condition)
    local airFilterPenaltyMultiplier = 1
    if settings.airFilterEnabled ~= false and state.airFilterCondition < 0.2 then
        airFilterPenaltyMultiplier = 0.8
    end

    -- Damage penalty computed against original top speed, not the current (possibly reduced) one
    local damagePenaltyMultiplier = 1
    if settings.damageEnabled ~= false then
        local impactConfig = context ~= nil and context.damageEngineImpact or nil
        local damageAmount = vehicle.getDamageAmount ~= nil and (vehicle:getDamageAmount() or 0) or 0
        local startAtDamage = impactConfig ~= nil and impactConfig.START_AT_DAMAGE or 0.15

        if damageAmount > startAtDamage then
            local targetSpeedKmh = impactConfig ~= nil and impactConfig.FULL_DAMAGE_TARGET_SPEED_KMH or 5
            local minimumFloor = impactConfig ~= nil and impactConfig.MIN_POWER_MULTIPLIER_FLOOR or 0.03
            local minimumPowerMultiplier = math.max(minimumFloor, math.min(1, targetSpeedKmh / originalTopSpeedKmh))
            local normalizedDamage = (damageAmount - startAtDamage) / math.max(0.0001, 1 - startAtDamage)
            damagePenaltyMultiplier = math.max(minimumPowerMultiplier, 1 - (normalizedDamage * (1 - minimumPowerMultiplier)))
        end
    end

    local speedMultiplier = airFilterPenaltyMultiplier * damagePenaltyMultiplier
    local shouldApplyPenalty = speedMultiplier < 0.9999

    if shouldApplyPenalty then
        if not state.airFilterPowerPenaltyApplied then
            state.airFilterPreviousPowerMultiplier = originalSpeedMs
            state.airFilterPowerPenaltyApplied = true
        end

        local targetSpeedMs = math.max(originalSpeedMs * speedMultiplier, 5 / 3.6)

        if math.abs(motor.maxForwardSpeed - targetSpeedMs) > 0.001 then
            motor.maxForwardSpeed = targetSpeedMs
            return true
        end

        return false
    end

    if state.airFilterPowerPenaltyApplied then
        motor.maxForwardSpeed = state.airFilterPreviousPowerMultiplier
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
    if not state.airFilterPowerPenaltyApplied then return end

    local motor = vehicle ~= nil and vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil

    if motor ~= nil and type(state.airFilterPreviousPowerMultiplier) == "number" then
        motor.maxForwardSpeed = state.airFilterPreviousPowerMultiplier
    end

    state.airFilterPowerPenaltyApplied = false
    state.airFilterPreviousPowerMultiplier = 1
end
