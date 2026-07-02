SoilWorkYieldBonus = {}

SoilWorkYieldBonus.MOD_NAME = g_currentModName or "FS25_SoilWorkYieldBonus"
SoilWorkYieldBonus.SAVE_FILENAME = "soilWorkYieldBonus.xml"
SoilWorkYieldBonus.SAVE_ROOT = "soilWorkYieldBonus"
SoilWorkYieldBonus.SAVE_VERSION = 2

SoilWorkYieldBonus.COVERAGE_THRESHOLD = 0.80
SoilWorkYieldBonus.SYNC_INTERVAL_MS = 1000

SoilWorkYieldBonus.BONUS_DISKING = 0.04
SoilWorkYieldBonus.BONUS_CULTIVATING = 0.06
SoilWorkYieldBonus.BONUS_MAX = 0.06

SoilWorkYieldBonus.DISC_KEYWORDS = {
    "disc",
    "disk",
    "harrow",
    "discharrow",
    "disc harrow",
    "scheiben",
    "catros",
    "joker",
    "terradisc",
    "heliodor",
    "rubin",
    "qualidisc",
    "optimer",
    "carrier",
    "maxicut",
    "диск",
    "борон"
}

SoilWorkYieldBonus.CULTIVATOR_KEYWORDS = {
    "cultiplow",
    "grubber",
    "subsoiler",
    "ripper",
    "chisel",
    "kultivator",
    "культив",
    "глубокорыхл"
}

local SoilWorkYieldBonus_mt = {
    __index = SoilWorkYieldBonus
}

SoilWorkYieldBonusSyncEvent = {}
local SoilWorkYieldBonusSyncEvent_mt = Class(SoilWorkYieldBonusSyncEvent, Event)

local function swybSyncEventEmptyNew()
    return Event.new(SoilWorkYieldBonusSyncEvent_mt)
end

local function swybSyncEventNew(fieldStates, isFullSync)
    local self = SoilWorkYieldBonusSyncEvent.emptyNew()
    self.fieldStates = fieldStates or {}
    self.isFullSync = isFullSync == true

    return self
end

local function swybSyncEventWriteStream(self, streamId, connection)
    streamWriteBool(streamId, self.isFullSync == true)

    if streamWriteUInt16 ~= nil then
        streamWriteUInt16(streamId, #self.fieldStates)
    else
        streamWriteUIntN(streamId, #self.fieldStates, 16)
    end

    for _, state in ipairs(self.fieldStates) do
        streamWriteInt32(streamId, state.fieldId or 0)
        streamWriteBool(streamId, state.delete == true)
        streamWriteFloat32(streamId, state.lockBonus or 0)

        if state.delete ~= true then
            streamWriteFloat32(streamId, state.diskingHa or 0)
            streamWriteFloat32(streamId, state.cultivatingHa or 0)
            streamWriteFloat32(streamId, state.harvestedHa or 0)
            streamWriteFloat32(streamId, state.fieldAreaHa or 0)
        end
    end
end

local function swybSyncEventReadStream(self, streamId, connection)
    self.isFullSync = streamReadBool(streamId)
    self.fieldStates = {}

    local count = 0
    if streamReadUInt16 ~= nil then
        count = streamReadUInt16(streamId)
    else
        count = streamReadUIntN(streamId, 16)
    end

    for _ = 1, count do
        local state = {
            fieldId = streamReadInt32(streamId),
            delete = streamReadBool(streamId)
        }

        state.lockBonus = streamReadFloat32(streamId)

        if state.delete ~= true then
            state.diskingHa = streamReadFloat32(streamId)
            state.cultivatingHa = streamReadFloat32(streamId)
            state.harvestedHa = streamReadFloat32(streamId)
            state.fieldAreaHa = streamReadFloat32(streamId)
        end

        table.insert(self.fieldStates, state)
    end

    self:run(connection)
end

local function swybSyncEventRun(self, connection)
    if connection ~= nil and connection.getIsServer ~= nil and not connection:getIsServer() then
        return
    end

    local instance = g_soilWorkYieldBonus
    if instance ~= nil then
        instance:applyNetworkFieldStates(self.fieldStates, self.isFullSync)
    end
end

SoilWorkYieldBonusSyncEvent.emptyNew = swybSyncEventEmptyNew
SoilWorkYieldBonusSyncEvent.new = swybSyncEventNew
SoilWorkYieldBonusSyncEvent.writeStream = swybSyncEventWriteStream
SoilWorkYieldBonusSyncEvent.readStream = swybSyncEventReadStream
SoilWorkYieldBonusSyncEvent.run = swybSyncEventRun
InitEventClass(SoilWorkYieldBonusSyncEvent, "SoilWorkYieldBonusSyncEvent")

function SoilWorkYieldBonus.registerNetworkEvent()
    return SoilWorkYieldBonusSyncEvent ~= nil
end

function SoilWorkYieldBonus.new(customMt)
    local self = setmetatable({}, customMt or SoilWorkYieldBonus_mt)

    self.fields = {}
    self.harvestLocks = {}
    self.cutterFieldIds = {}
    self.combineFieldIds = {}
    self.dirtyFieldIds = {}
    self.fieldAreaCache = {}
    self.syncTimer = 0
    self.savegamePath = nil

    return self
end

function SoilWorkYieldBonus:loadMap()
    self.fields = {}
    self.harvestLocks = {}
    self.cutterFieldIds = {}
    self.combineFieldIds = {}
    self.dirtyFieldIds = {}
    self.fieldAreaCache = {}
    self.syncTimer = 0
    self.savegamePath = self:getSavegamePath()
    SoilWorkYieldBonus.installSavegameHook()
    SoilWorkYieldBonus.installInitialClientStateHook()
    SoilWorkYieldBonus.registerNetworkEvent()

    if self:isServerSide() then
        self:loadFromSavegame()
    end
end

function SoilWorkYieldBonus:deleteMap()
    self.fields = {}
    self.harvestLocks = {}
    self.cutterFieldIds = {}
    self.combineFieldIds = {}
    self.dirtyFieldIds = {}
    self.fieldAreaCache = {}
    self.syncTimer = 0
    self.savegamePath = nil
end

function SoilWorkYieldBonus:update(dt)
    if not self:isServerSide() or next(self.dirtyFieldIds) == nil then
        return
    end

    self.syncTimer = (self.syncTimer or 0) + (dt or 0)

    if self.syncTimer >= SoilWorkYieldBonus.SYNC_INTERVAL_MS then
        self.syncTimer = 0
        self:sendDirtyFieldStates()
    end
end

function SoilWorkYieldBonus:saveSavegame()
    if self:isServerSide() then
        self:saveToSavegame()
    end
end

function SoilWorkYieldBonus:isServerSide()
    if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil then
        return g_currentMission:getIsServer()
    end

    return g_server ~= nil
end

function SoilWorkYieldBonus:getSavegamePath()
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil

    if missionInfo ~= nil then
        if missionInfo.savegameDirectory ~= nil then
            return missionInfo.savegameDirectory .. "/" .. SoilWorkYieldBonus.SAVE_FILENAME
        end

        if missionInfo.savegameIndex ~= nil and getUserProfileAppPath ~= nil then
            return getUserProfileAppPath() .. "savegame" .. tostring(missionInfo.savegameIndex) .. "/" .. SoilWorkYieldBonus.SAVE_FILENAME
        end
    end

    return nil
end

function SoilWorkYieldBonus:loadFromSavegame()
    if self.savegamePath == nil or XMLFile == nil or XMLFile.loadIfExists == nil then
        return
    end

    local xmlFile = XMLFile.loadIfExists("SoilWorkYieldBonusXML", self.savegamePath)
    if xmlFile == nil then
        return
    end

    xmlFile:iterate(SoilWorkYieldBonus.SAVE_ROOT .. ".field", function(_, key)
        local fieldId = xmlFile:getInt(key .. "#id")

        if fieldId ~= nil then
            local state = self:getOrCreateFieldState(fieldId)
            state.diskingHa = xmlFile:getFloat(key .. "#diskingHa", 0)
            state.cultivatingHa = xmlFile:getFloat(key .. "#cultivatingHa", 0)
            state.harvestedHa = xmlFile:getFloat(key .. "#harvestedHa", 0)
            state.fieldAreaHa = xmlFile:getFloat(key .. "#fieldAreaHa")
        end
    end)

    xmlFile:iterate(SoilWorkYieldBonus.SAVE_ROOT .. ".harvestLock", function(_, key)
        local fieldId = xmlFile:getInt(key .. "#id")
        local bonus = xmlFile:getFloat(key .. "#bonus", 0) or 0

        if fieldId ~= nil and bonus > 0 then
            self.harvestLocks[fieldId] = {
                bonus = bonus,
                harvestedHa = xmlFile:getFloat(key .. "#harvestedHa", 0),
                fieldAreaHa = xmlFile:getFloat(key .. "#fieldAreaHa")
            }
        end
    end)

    xmlFile:delete()
end

function SoilWorkYieldBonus:saveToSavegame()
    self.savegamePath = self:getSavegamePath() or self.savegamePath

    if self.savegamePath == nil or XMLFile == nil or XMLFile.create == nil then
        return
    end

    local xmlFile = XMLFile.create("SoilWorkYieldBonusXML", self.savegamePath, SoilWorkYieldBonus.SAVE_ROOT)
    if xmlFile == nil then
        return
    end

    xmlFile:setInt(SoilWorkYieldBonus.SAVE_ROOT .. "#version", SoilWorkYieldBonus.SAVE_VERSION)

    local index = 0
    for fieldId, state in pairs(self.fields) do
        if self:hasPersistentState(state) then
            local key = string.format("%s.field(%d)", SoilWorkYieldBonus.SAVE_ROOT, index)

            xmlFile:setInt(key .. "#id", fieldId)
            xmlFile:setFloat(key .. "#diskingHa", state.diskingHa or 0)
            xmlFile:setFloat(key .. "#cultivatingHa", state.cultivatingHa or 0)
            xmlFile:setFloat(key .. "#harvestedHa", state.harvestedHa or 0)

            if state.fieldAreaHa ~= nil and state.fieldAreaHa > 0 then
                xmlFile:setFloat(key .. "#fieldAreaHa", state.fieldAreaHa)
            end

            index = index + 1
        end
    end

    local lockIndex = 0
    for fieldId, lock in pairs(self.harvestLocks) do
        if lock ~= nil and (lock.bonus or 0) > 0 then
            local key = string.format("%s.harvestLock(%d)", SoilWorkYieldBonus.SAVE_ROOT, lockIndex)

            xmlFile:setInt(key .. "#id", fieldId)
            xmlFile:setFloat(key .. "#bonus", lock.bonus)
            xmlFile:setFloat(key .. "#harvestedHa", lock.harvestedHa or 0)

            if lock.fieldAreaHa ~= nil and lock.fieldAreaHa > 0 then
                xmlFile:setFloat(key .. "#fieldAreaHa", lock.fieldAreaHa)
            end

            lockIndex = lockIndex + 1
        end
    end

    xmlFile:save()
    xmlFile:delete()
end

function SoilWorkYieldBonus:hasPersistentState(state)
    return state ~= nil and (
        (state.diskingHa or 0) > 0 or
        (state.cultivatingHa or 0) > 0 or
        (state.harvestedHa or 0) > 0
    )
end

function SoilWorkYieldBonus:getOrCreateFieldState(fieldId)
    local state = self.fields[fieldId]

    if state == nil then
        state = {
            diskingHa = 0,
            cultivatingHa = 0,
            harvestedHa = 0,
            fieldAreaHa = nil
        }

        self.fields[fieldId] = state
    end

    return state
end

function SoilWorkYieldBonus:resetFieldState(fieldId)
    self.fields[fieldId] = nil
    self:markFieldDirty(fieldId, true)
end

function SoilWorkYieldBonus:markFieldDirty(fieldId, delete)
    if not self:isServerSide() or fieldId == nil then
        return
    end

    self.dirtyFieldIds[fieldId] = delete == true and "delete" or "update"
end

function SoilWorkYieldBonus:getNetworkFieldState(fieldId, delete)
    if fieldId == nil then
        return nil
    end

    local lockBonus = self:getLockedHarvestBonus(fieldId)

    if delete == true then
        return {
            fieldId = fieldId,
            delete = true,
            lockBonus = lockBonus
        }
    end

    local state = self.fields[fieldId]
    if state == nil then
        return nil
    end

    return {
        fieldId = fieldId,
        delete = false,
        lockBonus = lockBonus,
        diskingHa = state.diskingHa or 0,
        cultivatingHa = state.cultivatingHa or 0,
        harvestedHa = state.harvestedHa or 0,
        fieldAreaHa = state.fieldAreaHa or 0
    }
end

function SoilWorkYieldBonus:getAllNetworkFieldStates()
    local fieldStates = {}

    for fieldId, state in pairs(self.fields) do
        if self:hasPersistentState(state) then
            local networkState = self:getNetworkFieldState(fieldId, false)
            if networkState ~= nil then
                table.insert(fieldStates, networkState)
            end
        end
    end

    for fieldId, lock in pairs(self.harvestLocks) do
        if self.fields[fieldId] == nil and lock ~= nil and (lock.bonus or 0) > 0 then
            table.insert(fieldStates, {
                fieldId = fieldId,
                delete = true,
                lockBonus = lock.bonus
            })
        end
    end

    return fieldStates
end

function SoilWorkYieldBonus:sendDirtyFieldStates()
    if not self:isServerSide() or g_server == nil or not SoilWorkYieldBonus.registerNetworkEvent() then
        self.dirtyFieldIds = {}
        return
    end

    local fieldStates = {}

    for fieldId, stateType in pairs(self.dirtyFieldIds) do
        local networkState = self:getNetworkFieldState(fieldId, stateType == "delete")
        if networkState ~= nil then
            table.insert(fieldStates, networkState)
        end
    end

    self.dirtyFieldIds = {}

    if #fieldStates > 0 then
        g_server:broadcastEvent(SoilWorkYieldBonusSyncEvent.new(fieldStates, false))
    end
end

function SoilWorkYieldBonus:sendFullSync(connection)
    if not self:isServerSide() or not SoilWorkYieldBonus.registerNetworkEvent() then
        return
    end

    local event = SoilWorkYieldBonusSyncEvent.new(self:getAllNetworkFieldStates(), true)

    if connection ~= nil and connection.sendEvent ~= nil then
        connection:sendEvent(event)
    elseif g_server ~= nil then
        g_server:broadcastEvent(event)
    end
end

function SoilWorkYieldBonus:applyNetworkFieldStates(fieldStates, isFullSync)
    if isFullSync then
        self.fields = {}
        self.harvestLocks = {}
    end

    for _, networkState in ipairs(fieldStates or {}) do
        local fieldId = networkState.fieldId

        if fieldId ~= nil then
            if networkState.delete == true then
                self.fields[fieldId] = nil
            else
                local state = self:getOrCreateFieldState(fieldId)
                state.diskingHa = networkState.diskingHa or 0
                state.cultivatingHa = networkState.cultivatingHa or 0
                state.harvestedHa = networkState.harvestedHa or 0
                state.fieldAreaHa = (networkState.fieldAreaHa or 0) > 0 and networkState.fieldAreaHa or nil
            end

            self.harvestLocks[fieldId] = (networkState.lockBonus or 0) > 0 and { bonus = networkState.lockBonus } or nil
        end
    end
end

function SoilWorkYieldBonus:getHaFromDensityArea(area)
    if area == nil or area <= 0 then
        return 0
    end

    local pixelsToSqm = 1
    if g_currentMission ~= nil and g_currentMission.getFruitPixelsToSqm ~= nil then
        pixelsToSqm = g_currentMission:getFruitPixelsToSqm()
    end

    if MathUtil ~= nil and MathUtil.areaToHa ~= nil then
        return MathUtil.areaToHa(area, pixelsToSqm)
    end

    return area * pixelsToSqm / 10000
end

function SoilWorkYieldBonus:getAreaHaFromValue(value)
    if value == nil or value <= 0 then
        return nil
    end

    if value > 1000 then
        return value / 10000
    end

    return value
end

function SoilWorkYieldBonus:getWorkAreaCenter(workArea)
    if workArea == nil or workArea.start == nil or workArea.width == nil or workArea.height == nil then
        return nil, nil
    end

    local x2, _, z2 = getWorldTranslation(workArea.width)
    local x3, _, z3 = getWorldTranslation(workArea.height)

    return (x2 + x3) / 2, (z2 + z3) / 2
end

function SoilWorkYieldBonus:getFieldIdAtWorldPosition(x, z)
    if x == nil or z == nil then
        return nil
    end

    local farmland = nil
    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandAtWorldPosition ~= nil then
        farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
    end

    if farmland == nil then
        return nil
    end

    return self:getFieldIdByFarmlandId(farmland)
end

function SoilWorkYieldBonus:getFieldIdFromWorkArea(workArea)
    local x, z = self:getWorkAreaCenter(workArea)
    return self:getFieldIdAtWorldPosition(x, z)
end

function SoilWorkYieldBonus:getFieldIdFromVehicle(vehicle)
    if vehicle == nil then
        return nil
    end

    local spec = vehicle.spec_cultivator or nil
    local node = spec ~= nil and spec.directionNode or nil

    if node ~= nil then
        local x, _, z = getWorldTranslation(node)
        local fieldId = self:getFieldIdAtWorldPosition(x, z)

        if fieldId ~= nil then
            return fieldId
        end
    end

    local x, z = self:getVehiclePositionXZ(vehicle)
    return self:getFieldIdAtWorldPosition(x, z)
end

function SoilWorkYieldBonus:rememberHarvestField(cutter, fieldId)
    if cutter == nil or fieldId == nil then
        return
    end

    self.cutterFieldIds[cutter] = fieldId

    if cutter.spec_cutter ~= nil then
        cutter.spec_cutter.soilWorkYieldBonusFieldId = fieldId

        local parameters = cutter.spec_cutter.workAreaParameters
        local combine = parameters ~= nil and parameters.combineVehicle or nil
        if combine ~= nil then
            self.combineFieldIds[combine] = fieldId
        end
    end
end

function SoilWorkYieldBonus:getFieldIdFromCombine(combine)
    if combine == nil then
        return nil
    end

    local x, z = self:getVehiclePositionXZ(combine)
    local fieldId = self:getFieldIdAtWorldPosition(x, z)

    if fieldId ~= nil then
        self.combineFieldIds[combine] = fieldId
        return fieldId
    end

    fieldId = self.combineFieldIds[combine]
    if fieldId ~= nil then
        return fieldId
    end

    local spec = combine.spec_combine
    if spec ~= nil and spec.attachedCutters ~= nil then
        for key, value in pairs(spec.attachedCutters) do
            local cutter = nil

            if type(key) == "table" then
                cutter = key
            elseif type(value) == "table" then
                cutter = value
            end

            if cutter ~= nil then
                fieldId = self.cutterFieldIds[cutter]

                if fieldId == nil and cutter.spec_cutter ~= nil then
                    fieldId = cutter.spec_cutter.soilWorkYieldBonusFieldId
                end

                if fieldId ~= nil then
                    self.combineFieldIds[combine] = fieldId
                    return fieldId
                end
            end
        end
    end

    return nil
end

function SoilWorkYieldBonus:getFieldIdByFarmlandId(farmlandId)
    if farmlandId == nil then
        return nil
    end

    local farmland = nil
    if type(farmlandId) == "table" then
        farmland = farmlandId
        farmlandId = self:getFarmlandIdFromValue(farmland)
    end

    if farmlandId == nil then
        return nil
    end

    local field = nil
    if g_fieldManager ~= nil and g_fieldManager.farmlandIdFieldMapping ~= nil then
        field = g_fieldManager.farmlandIdFieldMapping[farmlandId]
    end

    local fieldId = self:getFieldIdFromFieldValue(field)
    if fieldId ~= nil then
        return fieldId
    end

    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandById ~= nil then
        farmland = farmland or g_farmlandManager:getFarmlandById(farmlandId)

        if farmland ~= nil then
            fieldId = self:getFieldIdFromFieldValue(farmland.field)
            if fieldId ~= nil then
                return fieldId
            end
        end
    end

    return farmlandId
end

function SoilWorkYieldBonus:getFarmlandIdFromValue(farmland)
    if farmland == nil then
        return nil
    end

    if type(farmland) == "number" then
        return farmland
    end

    if type(farmland) ~= "table" then
        return nil
    end

    return farmland.id or farmland.farmlandId
end

function SoilWorkYieldBonus:getFieldIdFromFieldValue(field)
    if field == nil then
        return nil
    end

    if type(field) == "number" then
        return field
    end

    if type(field) ~= "table" then
        return nil
    end

    if field.getId ~= nil then
        local ok, fieldId = pcall(field.getId, field)

        if ok and fieldId ~= nil then
            return fieldId
        end
    end

    if field.fieldId ~= nil then
        return field.fieldId
    end

    if field.id ~= nil then
        return field.id
    end

    for _, value in pairs(field) do
        if type(value) == "table" then
            local fieldId = value.fieldId or value.id
            if fieldId ~= nil then
                return fieldId
            end
        end
    end

    return nil
end

function SoilWorkYieldBonus:getFieldIdFromFieldInfoData(data)
    if data == nil then
        return nil
    end

    if data.fieldId ~= nil then
        return data.fieldId
    end

    local fieldId = self:getFieldIdFromFieldValue(data.field)
    if fieldId ~= nil then
        return fieldId
    end

    fieldId = self:getFieldIdFromFieldValue(data.fieldData)
    if fieldId ~= nil then
        return fieldId
    end

    if data.farmland ~= nil then
        fieldId = self:getFieldIdFromFieldValue(data.farmland.field)
        if fieldId ~= nil then
            return fieldId
        end

        fieldId = self:getFieldIdByFarmlandId(data.farmland)
        if fieldId ~= nil then
            return fieldId
        end

        if data.farmland.id ~= nil then
            fieldId = self:getFieldIdByFarmlandId(data.farmland.id)
            if fieldId ~= nil then
                return fieldId
            end
        end
    end

    if data.farmlandId ~= nil then
        fieldId = self:getFieldIdByFarmlandId(data.farmlandId)
        if fieldId ~= nil then
            return fieldId
        end
    end

    return nil
end

function SoilWorkYieldBonus:getFieldAreaHa(fieldId)
    if fieldId == nil then
        return nil
    end

    local cachedAreaHa = self.fieldAreaCache[fieldId]
    if cachedAreaHa ~= nil then
        return cachedAreaHa
    end

    local areaHa = self:computeFieldAreaHa(fieldId)

    if areaHa ~= nil and areaHa > 0 then
        self.fieldAreaCache[fieldId] = areaHa
    end

    return areaHa
end

function SoilWorkYieldBonus:computeFieldAreaHa(fieldId)
    local field = self:getFieldById(fieldId)
    if field ~= nil then
        local areaHa = self:getAreaHaFromValue(field.areaHa)

        if areaHa ~= nil then
            return areaHa
        end

        areaHa = self:getAreaHaFromValue(field.fieldArea)

        if areaHa ~= nil then
            return areaHa
        end

        if field.getArea ~= nil then
            local ok, area = pcall(field.getArea, field)

            if ok then
                areaHa = self:getAreaHaFromValue(area)

                if areaHa ~= nil then
                    return areaHa
                end
            end
        end

        if field.farmland ~= nil then
            areaHa = self:getFieldAreaHaFromFarmland(field.farmland)

            if areaHa ~= nil then
                return areaHa
            end
        end
    end

    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandById ~= nil then
        local farmland = g_farmlandManager:getFarmlandById(fieldId)
        local areaHa = self:getFieldAreaHaFromFarmland(farmland)

        if areaHa ~= nil then
            return areaHa
        end
    end

    return nil
end

function SoilWorkYieldBonus:getFieldAreaHaFromFarmland(farmland)
    if farmland == nil then
        return nil
    end

    if farmland.field ~= nil then
        local areaHa = self:getAreaHaFromValue(farmland.field.areaHa)

        if areaHa ~= nil then
            return areaHa
        end

        areaHa = self:getAreaHaFromValue(farmland.field.fieldArea)

        if areaHa ~= nil then
            return areaHa
        end
    end

    local areaHa = self:getAreaHaFromValue(farmland.areaInHa)

    if areaHa ~= nil then
        return areaHa
    end

    areaHa = self:getAreaHaFromValue(farmland.totalFieldArea)

    if areaHa ~= nil then
        return areaHa
    end

    return self:getAreaHaFromValue(farmland.fieldArea)
end

function SoilWorkYieldBonus:getFieldById(fieldId)
    if fieldId == nil or g_fieldManager == nil then
        return nil
    end

    if g_fieldManager.getFieldById ~= nil then
        local ok, field = pcall(g_fieldManager.getFieldById, g_fieldManager, fieldId)

        if ok and field ~= nil then
            return field
        end
    end

    if g_fieldManager.fieldMapping ~= nil and g_fieldManager.fieldMapping[fieldId] ~= nil then
        return g_fieldManager.fieldMapping[fieldId]
    end

    if g_fieldManager.fields ~= nil then
        for id, field in pairs(g_fieldManager.fields) do
            local mappedFieldId = self:getFieldIdFromFieldValue(field)

            if id == fieldId or mappedFieldId == fieldId then
                return field
            end
        end
    end

    if g_fieldManager.farmlandIdFieldMapping ~= nil then
        for _, field in pairs(g_fieldManager.farmlandIdFieldMapping) do
            if type(field) == "table" then
                if self:getFieldIdFromFieldValue(field) == fieldId then
                    return field
                end

                for _, value in pairs(field) do
                    if type(value) == "table" and self:getFieldIdFromFieldValue(value) == fieldId then
                        return value
                    end
                end
            end
        end
    end

    return nil
end

function SoilWorkYieldBonus:getCoverage(fieldId, operationKey)
    local state = self.fields[fieldId]
    if state == nil then
        return 0
    end

    local areaHa = self:getFieldAreaHa(fieldId)
    if (areaHa == nil or areaHa <= 0) and state.fieldAreaHa ~= nil then
        areaHa = state.fieldAreaHa
    end

    if areaHa == nil or areaHa <= 0 then
        return 0
    end

    local operationHa = state[operationKey] or 0
    return math.min(operationHa / areaHa, 1)
end

function SoilWorkYieldBonus:getCoverageThresholdForField(fieldId)
    local areaHa = self:getFieldAreaHa(fieldId)
    local state = self.fields[fieldId]

    if (areaHa == nil or areaHa <= 0) and state ~= nil and state.fieldAreaHa ~= nil then
        areaHa = state.fieldAreaHa
    end

    if areaHa == nil or areaHa <= 5 then
        return SoilWorkYieldBonus.COVERAGE_THRESHOLD
    end

    return math.min(0.95, SoilWorkYieldBonus.COVERAGE_THRESHOLD + math.max(0, areaHa - 5) * 0.01)
end

function SoilWorkYieldBonus:getOperationBonus(fieldId, operationKey, bonus)
    if self:getCoverage(fieldId, operationKey) >= self:getCoverageThresholdForField(fieldId) then
        return bonus
    end

    return 0
end

function SoilWorkYieldBonus:getFieldYieldBonus(fieldId)
    local diskingBonus = self:getOperationBonus(fieldId, "diskingHa", SoilWorkYieldBonus.BONUS_DISKING)
    local cultivatingBonus = self:getOperationBonus(fieldId, "cultivatingHa", SoilWorkYieldBonus.BONUS_CULTIVATING)

    return math.min(math.max(diskingBonus, cultivatingBonus), SoilWorkYieldBonus.BONUS_MAX)
end

function SoilWorkYieldBonus:getLockedHarvestBonus(fieldId)
    local lock = self.harvestLocks[fieldId]

    if lock ~= nil and lock.bonus ~= nil then
        return lock.bonus
    end

    return 0
end

function SoilWorkYieldBonus:getPotentialFieldYieldBonus(fieldId)
    local state = self.fields[fieldId]
    if state == nil then
        return 0
    end

    local diskingBonus = (state.diskingHa or 0) > 0 and SoilWorkYieldBonus.BONUS_DISKING or 0
    local cultivatingBonus = (state.cultivatingHa or 0) > 0 and SoilWorkYieldBonus.BONUS_CULTIVATING or 0

    return math.min(math.max(diskingBonus, cultivatingBonus), SoilWorkYieldBonus.BONUS_MAX)
end

function SoilWorkYieldBonus:getMinimumCoverage(coverages)
    local minimumCoverage = nil

    for _, coverage in ipairs(coverages) do
        if coverage ~= nil then
            if minimumCoverage == nil or coverage < minimumCoverage then
                minimumCoverage = coverage
            end
        end
    end

    return minimumCoverage or 0
end

function SoilWorkYieldBonus:getCoveragePercent(coverage)
    coverage = math.max(0, math.min(coverage or 0, 1))
    return math.floor(coverage * 100 + 0.5)
end

function SoilWorkYieldBonus:getCoveragePercentText(coverage)
    coverage = math.max(0, math.min(coverage or 0, 1))

    local percent = coverage * 100
    if percent > 0 and percent < 10 then
        return string.format("%.1f", percent)
    end

    return tostring(math.floor(percent + 0.5))
end

function SoilWorkYieldBonus:getFieldBonusDisplayInfo(fieldId)
    local state = self.fields[fieldId]
    if state == nil then
        local lockedBonus = self:getLockedHarvestBonus(fieldId)

        if lockedBonus > 0 then
            return math.min(lockedBonus, SoilWorkYieldBonus.BONUS_MAX), nil, true
        end

        return 0, 0, false
    end

    local diskingCoverage = self:getCoverage(fieldId, "diskingHa")
    local cultivatingCoverage = self:getCoverage(fieldId, "cultivatingHa")
    local coverageThreshold = self:getCoverageThresholdForField(fieldId)

    local activeDiskingBonus = diskingCoverage >= coverageThreshold and SoilWorkYieldBonus.BONUS_DISKING or 0
    local activeCultivatingBonus = cultivatingCoverage >= coverageThreshold and SoilWorkYieldBonus.BONUS_CULTIVATING or 0

    local activeCoverages = {}
    local activeBonus = 0

    if activeCultivatingBonus >= activeDiskingBonus and activeCultivatingBonus > 0 then
        activeBonus = activeCultivatingBonus
        table.insert(activeCoverages, cultivatingCoverage)
    elseif activeDiskingBonus > 0 then
        activeBonus = activeDiskingBonus
        table.insert(activeCoverages, diskingCoverage)
    end

    if activeBonus > 0 then
        return math.min(activeBonus, SoilWorkYieldBonus.BONUS_MAX), self:getMinimumCoverage(activeCoverages), true
    end

    local pendingDiskingBonus = (state.diskingHa or 0) > 0 and SoilWorkYieldBonus.BONUS_DISKING or 0
    local pendingCultivatingBonus = (state.cultivatingHa or 0) > 0 and SoilWorkYieldBonus.BONUS_CULTIVATING or 0

    local pendingCoverages = {}
    local pendingBonus = 0

    if pendingCultivatingBonus >= pendingDiskingBonus and pendingCultivatingBonus > 0 then
        pendingBonus = pendingCultivatingBonus
        table.insert(pendingCoverages, cultivatingCoverage)
    elseif pendingDiskingBonus > 0 then
        pendingBonus = pendingDiskingBonus
        table.insert(pendingCoverages, diskingCoverage)
    end

    if pendingBonus > 0 then
        return math.min(pendingBonus, SoilWorkYieldBonus.BONUS_MAX), self:getMinimumCoverage(pendingCoverages), false
    end

    return 0, 0, false
end

function SoilWorkYieldBonus:recordOperation(workArea, densityArea, operationKey)
    if not self:isServerSide() or densityArea == nil or densityArea <= 0 then
        return
    end

    local fieldId = self:getFieldIdFromWorkArea(workArea)
    if fieldId == nil then
        return
    end

    self:recordOperationForField(fieldId, densityArea, operationKey)
end

function SoilWorkYieldBonus:recordOperationForField(fieldId, densityArea, operationKey)
    if not self:isServerSide() or fieldId == nil or densityArea == nil or densityArea <= 0 then
        return
    end

    local state = self:getOrCreateFieldState(fieldId)
    local areaHa = self:getHaFromDensityArea(densityArea)
    local fieldAreaHa = self:getFieldAreaHa(fieldId)
    self.harvestLocks[fieldId] = nil

    if fieldAreaHa ~= nil and fieldAreaHa > 0 then
        state.fieldAreaHa = fieldAreaHa
    end

    if areaHa > 0 then
        state[operationKey] = (state[operationKey] or 0) + areaHa
        state.harvestedHa = 0
        self:markFieldDirty(fieldId, false)
    end
end

function SoilWorkYieldBonus:recordHarvestForField(fieldId, densityArea)
    if not self:isServerSide() or fieldId == nil or densityArea == nil or densityArea <= 0 then
        return
    end

    if fieldId == nil then
        return
    end

    local state = self.fields[fieldId]
    local lock = self.harvestLocks[fieldId]
    if state == nil and lock == nil then
        return
    end

    local areaHa = self:getHaFromDensityArea(densityArea)
    local fieldAreaHa = self:getFieldAreaHa(fieldId)

    if (fieldAreaHa == nil or fieldAreaHa <= 0) and state ~= nil then
        fieldAreaHa = state.fieldAreaHa
    end

    if (fieldAreaHa == nil or fieldAreaHa <= 0) and lock ~= nil then
        fieldAreaHa = lock.fieldAreaHa
    end

    if state ~= nil then
        local bonus = self:getFieldYieldBonus(fieldId)

        if bonus > 0 and lock == nil then
            lock = {
                bonus = bonus,
                harvestedHa = state.harvestedHa or 0,
                fieldAreaHa = fieldAreaHa
            }
            self.harvestLocks[fieldId] = lock
            self:markFieldDirty(fieldId, false)
        end

        state.harvestedHa = (state.harvestedHa or 0) + areaHa

        if fieldAreaHa ~= nil and fieldAreaHa > 0 and state.harvestedHa / fieldAreaHa >= self:getCoverageThresholdForField(fieldId) then
            self:resetFieldState(fieldId)
        end
    end

    if lock ~= nil then
        lock.harvestedHa = (lock.harvestedHa or 0) + areaHa

        if fieldAreaHa ~= nil and fieldAreaHa > 0 then
            lock.fieldAreaHa = fieldAreaHa
        end

        if lock.fieldAreaHa ~= nil and lock.fieldAreaHa > 0 and lock.harvestedHa / lock.fieldAreaHa >= 0.995 then
            self.harvestLocks[fieldId] = nil
            self:markFieldDirty(fieldId, self.fields[fieldId] == nil)
        end
    end
end

function SoilWorkYieldBonus:getHarvestBonusForField(fieldId)
    if fieldId == nil then
        return 0
    end

    local bonus = self:getLockedHarvestBonus(fieldId)

    if bonus <= 0 then
        bonus = self:getFieldYieldBonus(fieldId)
    end

    return bonus
end

function SoilWorkYieldBonus:applyCombineHarvestBonus(combine, area, liters)
    if not self:isServerSide() or combine == nil or area == nil or area <= 0 or liters == nil or liters <= 0 then
        return liters, nil, 0
    end

    local fieldId = self:getFieldIdFromCombine(combine)
    local bonus = self:getHarvestBonusForField(fieldId)

    if bonus > 0 then
        return liters * (1 + bonus), fieldId, bonus
    end

    return liters, fieldId, 0
end

function SoilWorkYieldBonus:formatFieldInfoValue(fieldId)
    if fieldId == nil then
        return self:getText("swyb_fieldInfoBonusNone", "0%")
    end

    local bonus, coverage, isActive = self:getFieldBonusDisplayInfo(fieldId)

    if bonus <= 0 then
        return self:getText("swyb_fieldInfoBonusNone", "0%")
    end

    local bonusPercent = math.floor(bonus * 100 + 0.5)

    if coverage == nil then
        return string.format("+%d%%", bonusPercent)
    end

    local coverageText = self:getCoveragePercentText(coverage)
    local thresholdPercent = self:getCoveragePercent(self:getCoverageThresholdForField(fieldId))

    if isActive then
        return string.format("+%d%% %s%%", bonusPercent, coverageText)
    end

    return string.format("+%d%% %s/%d%%", bonusPercent, coverageText, thresholdPercent)
end

function SoilWorkYieldBonus:textContainsAny(text, keywords)
    if text == nil then
        return false
    end

    local lowerText = string.lower(text)

    for _, keyword in ipairs(keywords) do
        if string.find(lowerText, string.lower(keyword), 1, true) ~= nil then
            return true
        end
    end

    return false
end

function SoilWorkYieldBonus:getVehicleClassifierText(vehicle)
    local parts = {}

    if vehicle == nil then
        return ""
    end

    if vehicle.configFileName ~= nil then
        table.insert(parts, vehicle.configFileName)
    end

    if vehicle.typeName ~= nil then
        table.insert(parts, vehicle.typeName)
    end

    if vehicle.getName ~= nil then
        local ok, name = pcall(vehicle.getName, vehicle)
        if ok and name ~= nil then
            table.insert(parts, name)
        end
    end

    if vehicle.configFileName ~= nil and g_storeManager ~= nil and g_storeManager.getItemByXMLFilename ~= nil then
        local ok, item = pcall(g_storeManager.getItemByXMLFilename, g_storeManager, vehicle.configFileName)

        if ok and item ~= nil then
            if item.categoryName ~= nil then
                table.insert(parts, item.categoryName)
            end

            if item.name ~= nil then
                table.insert(parts, item.name)
            end

            if item.title ~= nil then
                table.insert(parts, item.title)
            end

            if item.xmlFilename ~= nil then
                table.insert(parts, item.xmlFilename)
            end
        end
    end

    return table.concat(parts, " ")
end

function SoilWorkYieldBonus:getCultivatorOperationKey(cultivator)
    local spec = cultivator ~= nil and cultivator.spec_cultivator or nil

    if spec ~= nil and spec.soilWorkYieldBonusOperationKey ~= nil then
        return spec.soilWorkYieldBonusOperationKey
    end

    local classifierText = self:getVehicleClassifierText(cultivator)
    local looksLikeDisc = self:textContainsAny(classifierText, SoilWorkYieldBonus.DISC_KEYWORDS)
    local looksLikeCultivator = self:textContainsAny(classifierText, SoilWorkYieldBonus.CULTIVATOR_KEYWORDS)

    local operationKey = "diskingHa"

    if looksLikeDisc then
        operationKey = "diskingHa"
    elseif spec ~= nil and (spec.useDeepMode == true or spec.isSubsoiler == true) then
        operationKey = "cultivatingHa"
    elseif looksLikeCultivator then
        operationKey = "cultivatingHa"
    end

    if spec ~= nil then
        spec.soilWorkYieldBonusOperationKey = operationKey
    end

    return operationKey
end

function SoilWorkYieldBonus:getVehiclePositionXZ(vehicle)
    if vehicle == nil then
        return nil, nil
    end

    local node = vehicle.rootNode

    if node == nil and vehicle.components ~= nil and vehicle.components[1] ~= nil then
        node = vehicle.components[1].node
    end

    if node == nil then
        return nil, nil
    end

    local x, _, z = getWorldTranslation(node)
    return x, z
end

function SoilWorkYieldBonus:getPlayerPositionXZ()
    if g_currentMission == nil then
        return nil, nil
    end

    local player = g_localPlayer
    local vehicle = nil

    if player ~= nil and player.getCurrentVehicle ~= nil then
        local ok, currentVehicle = pcall(player.getCurrentVehicle, player)

        if ok and currentVehicle ~= nil then
            vehicle = currentVehicle
        end
    end

    if vehicle == nil then
        vehicle = g_currentMission.controlledVehicle
    end

    if vehicle ~= nil then
        local x, z = self:getVehiclePositionXZ(vehicle)
        if x ~= nil then
            return x, z
        end
    end

    if player ~= nil and player.rootNode ~= nil then
        local x, _, z = getWorldTranslation(player.rootNode)
        return x, z
    end

    return nil, nil
end

function SoilWorkYieldBonus:getText(key, fallback)
    if key == "swyb_fieldInfoBonusShort" then
        fallback = "Yield bonus"
    end

    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local text = g_i18n:getText(key)

        if text ~= nil and text ~= "" and text ~= key and string.sub(text, 1, 7) ~= "Missing" then
            return text
        end
    end

    return fallback
end

function SoilWorkYieldBonus.onEndCultivatorWorkAreaProcessing(cultivator, dt)
    local instance = g_soilWorkYieldBonus

    if instance == nil or cultivator == nil or cultivator.spec_cultivator == nil then
        return
    end

    local parameters = cultivator.spec_cultivator.workAreaParameters
    local densityArea = parameters ~= nil and (parameters.lastStatsArea or parameters.lastArea) or nil

    if densityArea == nil or densityArea <= 0 then
        return
    end

    local fieldId = instance:getFieldIdFromVehicle(cultivator)
    instance:recordOperationForField(fieldId, densityArea, instance:getCultivatorOperationKey(cultivator))
end

function SoilWorkYieldBonus.processCutterArea(cutter, superFunc, workArea, dt)
    local previousArea = 0

    if cutter ~= nil and cutter.spec_cutter ~= nil and cutter.spec_cutter.workAreaParameters ~= nil then
        previousArea = cutter.spec_cutter.workAreaParameters.lastArea or 0
    end

    local results = { superFunc(cutter, workArea, dt) }
    local instance = g_soilWorkYieldBonus

    if instance ~= nil then
        local currentArea = results[1]

        if (currentArea == nil or currentArea <= 0) and cutter.spec_cutter ~= nil and cutter.spec_cutter.workAreaParameters ~= nil then
            currentArea = cutter.spec_cutter.workAreaParameters.lastArea
        end

        local deltaArea = (currentArea or 0) - previousArea
        if deltaArea > 0 then
            instance:rememberHarvestField(cutter, instance:getFieldIdFromWorkArea(workArea))
        end
    end

    return unpack(results)
end

function SoilWorkYieldBonus.addCutterArea(combine, superFunc, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)
    local instance = g_soilWorkYieldBonus
    local fieldId = nil

    if instance ~= nil then
        liters, fieldId = instance:applyCombineHarvestBonus(combine, area, liters)
    end

    local appliedDelta = superFunc(combine, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)

    if instance ~= nil and fieldId ~= nil and area ~= nil and area > 0 and appliedDelta ~= nil and appliedDelta > 0 then
        instance:recordHarvestForField(fieldId, area)
    end

    return appliedDelta
end

function SoilWorkYieldBonus.onMissionSaveSavegame(mission)
    local instance = g_soilWorkYieldBonus

    if instance == nil or not instance:isServerSide() then
        return
    end

    if mission ~= nil and g_currentMission ~= nil and mission ~= g_currentMission then
        return
    end

    instance:saveToSavegame()
end

function SoilWorkYieldBonus.onSendInitialClientState(mission, connection, user, farm)
    local instance = g_soilWorkYieldBonus
    if instance == nil or not instance:isServerSide() then
        return
    end

    if mission ~= nil and g_currentMission ~= nil and mission ~= g_currentMission then
        return
    end

    instance:sendFullSync(connection)
end

function SoilWorkYieldBonus.fieldAddFarmland(hudUpdater, data, box)
    local instance = g_soilWorkYieldBonus

    pcall(function()
        if instance == nil or box == nil or box.addLine == nil then
            return
        end

        local fieldId = nil
        local x, z = instance:getPlayerPositionXZ()

        if x ~= nil then
            fieldId = instance:getFieldIdAtWorldPosition(x, z)
        end

        if fieldId == nil then
            fieldId = instance:getFieldIdFromFieldInfoData(data)
        end

        if fieldId == nil then
            return
        end

        box:addLine(
            instance:getText("swyb_fieldInfoBonusShort", "Yield bonus"),
            instance:formatFieldInfoValue(fieldId)
        )
    end)
end

function SoilWorkYieldBonus.installFieldInfoHook()
    if PlayerHUDUpdater ~= nil and PlayerHUDUpdater.fieldAddFarmland ~= nil then
        PlayerHUDUpdater.fieldAddFarmland = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFarmland, SoilWorkYieldBonus.fieldAddFarmland)
    end
end

function SoilWorkYieldBonus.installSavegameHook()
    if SoilWorkYieldBonus.saveHookInstalled then
        return
    end

    if Mission00 ~= nil and Mission00.saveSavegame ~= nil then
        Mission00.saveSavegame = Utils.appendedFunction(Mission00.saveSavegame, SoilWorkYieldBonus.onMissionSaveSavegame)
        SoilWorkYieldBonus.saveHookInstalled = true
        return
    end

    if FSBaseMission ~= nil and FSBaseMission.saveSavegame ~= nil then
        FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, SoilWorkYieldBonus.onMissionSaveSavegame)
        SoilWorkYieldBonus.saveHookInstalled = true
    end
end

function SoilWorkYieldBonus.installInitialClientStateHook()
    if SoilWorkYieldBonus.initialClientStateHookInstalled then
        return
    end

    if FSBaseMission ~= nil and FSBaseMission.sendInitialClientState ~= nil then
        FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, SoilWorkYieldBonus.onSendInitialClientState)
        SoilWorkYieldBonus.initialClientStateHookInstalled = true
    end
end

g_soilWorkYieldBonus = SoilWorkYieldBonus.new()
addModEventListener(g_soilWorkYieldBonus)

if Cultivator ~= nil and Cultivator.onEndWorkAreaProcessing ~= nil then
    Cultivator.onEndWorkAreaProcessing = Utils.appendedFunction(Cultivator.onEndWorkAreaProcessing, SoilWorkYieldBonus.onEndCultivatorWorkAreaProcessing)
end

if Cutter ~= nil and Cutter.processCutterArea ~= nil then
    Cutter.processCutterArea = Utils.overwrittenFunction(Cutter.processCutterArea, SoilWorkYieldBonus.processCutterArea)
end

if Combine ~= nil and Combine.addCutterArea ~= nil then
    Combine.addCutterArea = Utils.overwrittenFunction(Combine.addCutterArea, SoilWorkYieldBonus.addCutterArea)
end

SoilWorkYieldBonus.installFieldInfoHook()
SoilWorkYieldBonus.installSavegameHook()
SoilWorkYieldBonus.installInitialClientStateHook()
