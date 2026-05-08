-- luacheck: globals RealismSettingsEvent Class Event InitEventClass
-- luacheck: globals streamReadFloat32 streamWriteFloat32 g_server RealismPackage DamageLogic RealismSettings

RealismSettingsEvent = {}
local RealismSettingsEvent_mt = Class(RealismSettingsEvent, Event)
InitEventClass(RealismSettingsEvent, "RealismSettingsEvent")

function RealismSettingsEvent.emptyNew()
    return Event.new(RealismSettingsEvent_mt)
end

function RealismSettingsEvent.new(profileIndex, wearEnabled, damageEnabled, airFilterEnabled)
    local self = RealismSettingsEvent.emptyNew()
    self.profileIndex = profileIndex or 2
    self.wearEnabled = wearEnabled and 1 or 0
    self.damageEnabled = damageEnabled and 1 or 0
    self.airFilterEnabled = airFilterEnabled and 1 or 0
    return self
end

function RealismSettingsEvent.readStream(self, streamId, connection)
    self.profileIndex = math.floor(streamReadFloat32(streamId) or 2)
    self.wearEnabled = streamReadFloat32(streamId) or 1
    self.damageEnabled = streamReadFloat32(streamId) or 1
    self.airFilterEnabled = streamReadFloat32(streamId) or 1

    self:run(connection)
end

function RealismSettingsEvent.writeStream(self, streamId, _connection)
    streamWriteFloat32(streamId, self.profileIndex)
    streamWriteFloat32(streamId, self.wearEnabled)
    streamWriteFloat32(streamId, self.damageEnabled)
    streamWriteFloat32(streamId, self.airFilterEnabled)
end

function RealismSettingsEvent.run(self, connection)
    local profileMap = { "FS25", "NORMAL", "REAL_LIFE" }
    local profileName = profileMap[self.profileIndex] or "NORMAL"

    if RealismPackage ~= nil and RealismPackage.applySettings ~= nil then
        RealismPackage:applySettings(profileName, self.wearEnabled > 0.5, self.damageEnabled > 0.5, self.airFilterEnabled > 0.5)
    elseif DamageLogic ~= nil and DamageLogic.setProfile ~= nil then
        DamageLogic.setProfile(DamageLogic, profileName)
    end

    if RealismSettings ~= nil and RealismSettings.updateSettings ~= nil then
        RealismSettings.updateSettings()
    end

    if connection ~= nil and not connection:getIsServer() and g_server ~= nil then
        g_server:broadcastEvent(self)
    end
end
