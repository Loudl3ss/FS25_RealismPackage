-- luacheck: globals RealismWorkshopActionEvent Class Event InitEventClass NetworkUtil
-- luacheck: globals streamReadFloat32 streamWriteFloat32 g_server g_currentMission MoneyType

RealismWorkshopActionEvent = {}
local RealismWorkshopActionEvent_mt = Class(RealismWorkshopActionEvent, Event)
InitEventClass(RealismWorkshopActionEvent, "RealismWorkshopActionEvent")

RealismWorkshopActionEvent.ACTION_FULL_SERVICE = 1
RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER = 2

local function isValidActionType(actionType)
    return actionType == RealismWorkshopActionEvent.ACTION_FULL_SERVICE
        or actionType == RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER
end

local function getConnectionFarmId(connection)
    if connection ~= nil and connection.getFarmId ~= nil then
        local farmId = connection:getFarmId()

        if type(farmId) == "number" then
            return farmId
        end
    end

    return nil
end

function RealismWorkshopActionEvent.emptyNew()
    return Event.new(RealismWorkshopActionEvent_mt)
end

function RealismWorkshopActionEvent.new(vehicle, actionType)
    local self = RealismWorkshopActionEvent.emptyNew()
    self.vehicle = vehicle
    self.actionType = actionType or 0
    return self
end

function RealismWorkshopActionEvent.readStream(self, streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.actionType = math.floor(streamReadFloat32(streamId) or 0)

    self:run(connection)
end

function RealismWorkshopActionEvent.writeStream(self, streamId, _connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteFloat32(streamId, self.actionType)
end

function RealismWorkshopActionEvent.run(self, connection)
    local isServerSide = g_server ~= nil

    if isServerSide and self.vehicle ~= nil then
        if not isValidActionType(self.actionType) then
            return
        end

        local actionCost = 0

        if self.vehicle.getWorkshopActionCost ~= nil then
            actionCost = math.max(0, self.vehicle:getWorkshopActionCost(self.actionType) or 0)
        end

        local farmId = self.vehicle.getOwnerFarmId ~= nil and self.vehicle:getOwnerFarmId() or 0
        local senderFarmId = getConnectionFarmId(connection)

        if senderFarmId ~= nil and senderFarmId ~= 0 and farmId ~= 0 and senderFarmId ~= farmId then
            return
        end

        local availableMoney = 0

        if g_currentMission ~= nil and g_currentMission.getMoney ~= nil then
            local byFarm = g_currentMission:getMoney(farmId)

            if type(byFarm) == "number" then
                availableMoney = byFarm
            else
                availableMoney = g_currentMission:getMoney() or 0
            end
        end

        if availableMoney >= actionCost then
            if self.actionType == RealismWorkshopActionEvent.ACTION_FULL_SERVICE then
                if self.vehicle.fullService ~= nil then
                    self.vehicle:fullService()
                end
            elseif self.actionType == RealismWorkshopActionEvent.ACTION_CLEAN_AIR_FILTER then
                if self.vehicle.cleanAirFilter ~= nil then
                    self.vehicle:cleanAirFilter()
                end
            end

            if g_currentMission ~= nil and g_currentMission.addMoney ~= nil and actionCost > 0 then
                g_currentMission:addMoney(-actionCost, farmId, MoneyType.VEHICLE_REPAIR, true, true)
            end
        end
    end

    if connection ~= nil and not connection:getIsServer() and g_server ~= nil then
        g_server:broadcastEvent(self)
    end
end
