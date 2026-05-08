-- luacheck: globals RealismWorkshopActions RealismWorkshopActionEvent WorkshopScreen Utils
-- luacheck: globals ButtonElement BitmapElement g_inputBinding g_i18n YesNoDialog GuiSoundPlayer
-- luacheck: globals g_client g_server g_currentMission InfoDialog

RealismWorkshopActions = RealismWorkshopActions or {}

local function hasRealismFunctions(vehicle)
    return vehicle ~= nil
        and vehicle.getServiceStatus ~= nil
        and vehicle.fullService ~= nil
        and vehicle.cleanAirFilter ~= nil
end

local function sendWorkshopAction(vehicle, actionType)
    if vehicle == nil then
        return
    end

    local event = RealismWorkshopActionEvent.new(vehicle, actionType)

    if g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(event)
    elseif g_server ~= nil then
        event:run(nil)
    end
end

local function getActionCost(vehicle, actionType)
    if vehicle ~= nil and vehicle.getWorkshopActionCost ~= nil then
        return math.max(0, vehicle:getWorkshopActionCost(actionType) or 0)
    end

    return 0
end

local function getActionLabel(actionType)
    if actionType == RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER then
        return g_i18n:getText("input_RP_WORKSHOP_CLEAN_FILTER")
    end

    return g_i18n:getText("input_RP_WORKSHOP_FULL_SERVICE")
end

local function formatActionText(actionType, cost)
    local label = getActionLabel(actionType)

    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        return string.format("%s (%s)", label, g_i18n:formatMoney(cost, 0, true, true))
    end

    return string.format("%s (%d)", label, cost)
end

local function getAvailableMoney(vehicle)
    if g_currentMission == nil or g_currentMission.getMoney == nil then
        return math.huge
    end

    local farmId = vehicle ~= nil and vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil

    if farmId ~= nil then
        local byFarm = g_currentMission:getMoney(farmId)

        if type(byFarm) == "number" then
            return byFarm
        end
    end

    local total = g_currentMission:getMoney()

    if type(total) == "number" then
        return total
    end

    return math.huge
end

function RealismWorkshopActions.onConfirmAction(screen, isYes)
    if not isYes or screen == nil then
        return
    end

    local vehicle = screen.vehicle

    if vehicle == nil then
        return
    end

    local actionType = screen.rpPendingActionType

    if actionType ~= nil then
        sendWorkshopAction(vehicle, actionType)
    end
end

function RealismWorkshopActions.openConfirmDialog(screen, actionType)
    if screen == nil or screen.vehicle == nil then
        return false
    end

    local vehicle = screen.vehicle
    local actionCost = getActionCost(vehicle, actionType)
    local availableMoney = getAvailableMoney(vehicle)

    if availableMoney < actionCost then
        if InfoDialog ~= nil and InfoDialog.show ~= nil then
            InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
        end
        return false
    end

    screen.rpPendingActionType = actionType
    screen.rpPendingActionCost = actionCost

    local textKey = "rp_workshop_confirm_full_service"

    if actionType == RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER then
        textKey = "rp_workshop_confirm_clean_filter"
    end

    local priceText = tostring(actionCost)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        priceText = g_i18n:formatMoney(actionCost, 0, true, true)
    end

    YesNoDialog.show(
        RealismWorkshopActions.onConfirmAction,
        screen,
        string.format(g_i18n:getText(textKey), priceText),
        nil,
        nil,
        nil,
        nil,
        GuiSoundPlayer.SOUND_SAMPLES.CONFIG_WRENCH
    )

    return true
end

function RealismWorkshopActions.onClickFullService(screen)
    return RealismWorkshopActions.openConfirmDialog(screen, RealismWorkshopActionEvent.ACTION_FULL_SERVICE)
end

function RealismWorkshopActions.onClickCleanFilter(screen)
    return RealismWorkshopActions.openConfirmDialog(screen, RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER)
end

function RealismWorkshopActions.injWorkshopScreenOnOpen(screen)
    if screen.rpWorkshopInit ~= true then
        local fullServiceBtn = ButtonElement.new(screen.buttonsBox)
        fullServiceBtn.name = "rpFullService"
        screen.buttonsBox:addElement(fullServiceBtn)
        fullServiceBtn:applyProfile("buttonActivate")
        fullServiceBtn:setInputAction("RP_WORKSHOP_FULL_SERVICE")
        fullServiceBtn.onClickCallback = function()
            RealismWorkshopActions.onClickFullService(screen)
        end
        fullServiceBtn:setText(g_i18n:getText("input_RP_WORKSHOP_FULL_SERVICE"))
        screen.rpFullServiceBtn = fullServiceBtn

        local sepA = BitmapElement.new(fullServiceBtn)
        sepA.name = "separator"
        fullServiceBtn:addElement(sepA)
        sepA:applyProfile("fs25_buttonBoxSeparator")

        local cleanFilterBtn = ButtonElement.new(screen.buttonsBox)
        cleanFilterBtn.name = "rpCleanFilter"
        screen.buttonsBox:addElement(cleanFilterBtn)
        cleanFilterBtn:applyProfile("buttonActivate")
        cleanFilterBtn:setInputAction("RP_WORKSHOP_CLEAN_FILTER")
        cleanFilterBtn.onClickCallback = function()
            RealismWorkshopActions.onClickCleanFilter(screen)
        end
        cleanFilterBtn:setText(g_i18n:getText("input_RP_WORKSHOP_CLEAN_FILTER"))
        screen.rpCleanFilterBtn = cleanFilterBtn

        local sepB = BitmapElement.new(cleanFilterBtn)
        sepB.name = "separator"
        cleanFilterBtn:addElement(sepB)
        sepB:applyProfile("fs25_buttonBoxSeparator")

        screen.rpWorkshopInit = true
    end

    local _, fullServiceEventId = g_inputBinding:registerActionEvent("RP_WORKSHOP_FULL_SERVICE", screen, RealismWorkshopActions.onClickFullService, false, true, false, true)
    screen.rpWorkshopFullServiceEventId = fullServiceEventId

    local _, cleanFilterEventId = g_inputBinding:registerActionEvent("RP_WORKSHOP_CLEAN_FILTER", screen, RealismWorkshopActions.onClickCleanFilter, false, true, false, true)
    screen.rpWorkshopCleanFilterEventId = cleanFilterEventId
end

function RealismWorkshopActions.injWorkshopScreenOnClose(screen)
    if screen.rpWorkshopFullServiceEventId ~= nil then
        g_inputBinding:removeActionEvent(screen.rpWorkshopFullServiceEventId)
        screen.rpWorkshopFullServiceEventId = nil
    end

    if screen.rpWorkshopCleanFilterEventId ~= nil then
        g_inputBinding:removeActionEvent(screen.rpWorkshopCleanFilterEventId)
        screen.rpWorkshopCleanFilterEventId = nil
    end

    screen.rpPendingActionType = nil
    screen.rpPendingActionCost = nil
end

function RealismWorkshopActions.injWorkshopScreenSetVehicle(screen, vehicle)
    local isSupported = hasRealismFunctions(vehicle)
    local fullServiceCost = isSupported and getActionCost(vehicle, RealismWorkshopActionEvent.ACTION_FULL_SERVICE) or 0
    local cleanFilterCost = isSupported and getActionCost(vehicle, RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER) or 0

    if screen.rpFullServiceBtn ~= nil then
        screen.rpFullServiceBtn:setVisible(isSupported)
        screen.rpFullServiceBtn:setDisabled(not isSupported)
        screen.rpFullServiceBtn:setText(formatActionText(RealismWorkshopActionEvent.ACTION_FULL_SERVICE, fullServiceCost))
    end

    if screen.rpCleanFilterBtn ~= nil then
        screen.rpCleanFilterBtn:setVisible(isSupported)
        screen.rpCleanFilterBtn:setDisabled(not isSupported)
        screen.rpCleanFilterBtn:setText(formatActionText(RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER, cleanFilterCost))
    end
end

if WorkshopScreen ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil then
    WorkshopScreen.onOpen = Utils.appendedFunction(WorkshopScreen.onOpen, RealismWorkshopActions.injWorkshopScreenOnOpen)
    WorkshopScreen.onClose = Utils.appendedFunction(WorkshopScreen.onClose, RealismWorkshopActions.injWorkshopScreenOnClose)
    WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle, RealismWorkshopActions.injWorkshopScreenSetVehicle)

    if WorkshopScreen.createFromExistingGui ~= nil and g_workshopScreen ~= nil then
        g_workshopScreen = WorkshopScreen.createFromExistingGui(g_workshopScreen, "WorkshopScreen")
    end
end
