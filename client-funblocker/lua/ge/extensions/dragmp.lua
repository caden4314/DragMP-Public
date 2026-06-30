local M = {}

local VERSION = "0.4.42"
local HANDLER_SOURCE = "DragMPClient"
local DEBUG_LIGHTING_OPTIONS_ENABLED = false

local activeLane = nil
local lightsReady = false
local serverRaceState = "idle"
local stageTelemetryAccumulator = 0
local lastStageTelemetry = nil
local localStageReady = false
local localJumped = false
local activeSessionId = nil
local lightingUpdateAccumulator = 0
local lightingPrefabLoaded = false
local buildingLightingPrefabLoaded = false
local parkingLightingPrefabLoaded = false
local lightingEnabled = nil
local lightingMode = "auto"
local winLightsPrefabLoaded = false
local winnerSequence = {}
local winnerTreeSweep = {}
local dragNavState = {
  status = "WAITING",
  reactionTime = nil,
  elapsedTime = nil,
  quarterTime = nil,
  quarterMph = nil,
  bestTime = nil,
  won = false,
  racing = false
}
local dragNavGreenClock = nil
local dragNavPushAccumulator = 0
local dragNavIdleAt = nil
local DRAG_NAV_FINISH_IDLE_SECONDS = 60

local PRESTAGE_THRESHOLD = -0.178
local STAGE_THRESHOLD = 0
local STAGE_WINDOW = 0.178
local STAGE_EXIT = 0.4
local STAGE_LATERAL_TOLERANCE = 2.4
local LIGHTING_PREFAB_NAME = "DragMP_Hirochi_Lighting"
local LIGHTING_PREFAB_PATH = "/levels/hirochi_raceway/art/prefabs/DragMPLighting.prefab.json"
local BUILDING_LIGHTING_PREFAB_NAME = "DragMP_Hirochi_BuildingLighting"
local BUILDING_LIGHTING_PREFAB_PATH = "/levels/hirochi_raceway/art/prefabs/DragMPBuildingLighting.prefab.json"
local PARKING_LIGHTING_PREFAB_NAME = "DragMP_Hirochi_ParkingLighting"
local PARKING_LIGHTING_PREFAB_PATH = "/levels/hirochi_raceway/art/prefabs/DragMPParkingLighting.prefab.json"
local WIN_LIGHTS_PREFAB_NAME = "DragMP_Hirochi_WinLights"
local WIN_LIGHTS_PREFAB_PATH = "/levels/hirochi_raceway/art/prefabs/DragMPWinLights.prefab.json"
local LIGHTING_ON_START = 0.245
local LIGHTING_OFF_START = 0.8
local LIGHTING_ON_HOLD_START = 0.23
local LIGHTING_ON_HOLD_END = 0.8
local WIN_LIGHT_SEQUENCE_STEP_SECONDS = 0.16
local WIN_LIGHT_SEQUENCE_TAIL = 4
local WIN_LIGHT_SEQUENCE_RESTART_AFTER_TAIL = 8
local WINNER_TREE_FLASH_STEP_SECONDS = 0.35
local SETTINGS_PATH = "settings/DragMP/lighting.json"
local BEST_TIMES_PATH = "settings/DragMP/bestTimes.json"
local dragBestTimes = nil

local lightingNamePrefixes = {
  "MiddleLighting",
  "LeftSideLighting",
  "LeftSideLineLighting",
  "RightSideLighting",
  "RightSideLineLighting",
  "TreeLighting"
}

local buildingLightingObjectNames = {
  "PointLight_65",
  "PointLight_651",
  "PointLight_6511",
  "PointLight_65111",
  "PointLight_651111",
  "PointLight_652",
  "PointLight_66",
  "PointLight_67",
  "PointLight_68",
  "SpotLight_65",
  "SpotLight_651",
  "SpotLight_6511",
  "SpotLight_65111",
  "SpotLight_651111",
  "SpotLight_6511111",
  "SpotLight_6512",
  "SpotLight_652",
  "SpotLight_6521",
  "SpotLight_65211",
  "SpotLight_652111",
  "SpotLight_653"
}

local parkingLightingObjectNames = {
  "PointLight_69",
  "PointLight_691",
  "PointLight_6911",
  "PointLight_69111",
  "PointLight_691111",
  "PointLight_6911111",
  "PointLight_69111111",
  "PointLight_691111111",
  "PointLight_6911112",
  "PointLight_69111121",
  "SpotLight_66",
  "SpotLight_661",
  "SpotLight_6611",
  "SpotLight_662",
  "SpotLight_67",
  "SpotLight_671",
  "SpotLight_6711",
  "SpotLight_6712",
  "SpotLight_672",
  "SpotLight_673"
}

local defaultLightingSettings = {
  globalShadows = false,
  texSize = 512,
  shadowSoftness = 1,
  shadowDistance = 250,
  fadeStartDistance = 200,
  priority = 1,
  staticRefreshFreq = 250,
  dynamicRefreshFreq = 8,
  representedInLightmap = false,
  lastSplitTerrainOnly = false,
  shadowType = "DualParaboloidSinglePass",
  groups = {
    track = false,
    building = false,
    parking = false
  }
}

local lightingSettings = nil

local lightingShadowGroups = {
  { key = "track", label = "Main Strip", description = "Drag strip, lane, and tree lighting prefab." },
  { key = "building", label = "Building", description = "Grandstand and building lighting prefab." },
  { key = "parking", label = "Parking", description = "Parking lot lighting prefab." }
}

local FUN_STUFF_FILTER_NAME = "dragmpFunStuffBlockedActions"
local funStuffBlockedActions = {
  "funBreak",
  "funHinges",
  "funTires",
  "funRandomTire",
  "funFire",
  "funExtinguish",
  "funBoom",
  "forceField",
  "funFling",
  "funFlingDownward",
  "funBoost",
  "funBoostBackwards"
}

local laneSuffix = {
  [1] = "1",
  [2] = "2"
}

local boardSuffix = {
  [1] = "r",
  [2] = "l"
}

local winLightPrefix = {
  [1] = "Right",
  [2] = "Left"
}

local winLightSequence = {
  1, 2, 3, 4, 5, 6, 7, 8,
  9, 10, 11, 12, 13, 14, 15, 16, 17, 18
}

local treeObjects = {}
local boardObjects = {}
local winnerObjects = {}

local function decode(data)
  if type(data) == "table" then
    return data
  end
  if jsonDecode then
    local ok, result = pcall(jsonDecode, data, "DragMP")
    if ok and type(result) == "table" then
      return result
    end
  end
  if json and json.decode then
    local ok, result = pcall(json.decode, data)
    if ok and type(result) == "table" then
      return result
    end
  end
  log("E", "DragMP", "Could not decode event payload: " .. tostring(data))
  return {}
end

local function encode(data)
  if jsonEncode then
    local ok, result = pcall(jsonEncode, data)
    if ok and type(result) == "string" then
      return result
    end
  end
  if json and json.encode then
    local ok, result = pcall(json.encode, data)
    if ok and type(result) == "string" then
      return result
    end
  end
  return "{}"
end

local function notice(message)
  log("I", "DragMP", message)
  if ui_message then
    ui_message(message, 5, "dragmp")
  end
end

local function triggerUi(eventName, data)
  if guihooks and guihooks.trigger then
    guihooks.trigger(eventName, data)
  end
end

local function enableFunStuffBlocker()
  if not core_input_actionFilter or not core_input_actionFilter.setGroup or not core_input_actionFilter.addAction then
    log("W", "DragMP", "Fun stuff blocker unavailable: action filter API missing")
    return false
  end

  core_input_actionFilter.setGroup(FUN_STUFF_FILTER_NAME, funStuffBlockedActions)
  core_input_actionFilter.addAction(0, FUN_STUFF_FILTER_NAME, true)
  log("I", "DragMP", string.format("Fun stuff blocker enabled (%d actions)", #funStuffBlockedActions))
  return true
end

local function findObject(name)
  if scenetree and scenetree.findObject then
    return scenetree.findObject(name)
  end
  return nil
end

local function copyTable(value)
  if type(value) ~= "table" then
    return value
  end

  local result = {}
  for k, v in pairs(value) do
    result[k] = copyTable(v)
  end
  return result
end

local function mergeLightingSettings(base, override)
  local result = copyTable(base)
  if type(override) ~= "table" then
    return result
  end

  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = mergeLightingSettings(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

local function getLightingSettings()
  if not DEBUG_LIGHTING_OPTIONS_ENABLED then
    return copyTable(defaultLightingSettings)
  end

  if not lightingSettings then
    local loaded = nil
    if jsonReadFile then
      local ok, data = pcall(jsonReadFile, SETTINGS_PATH)
      if ok and type(data) == "table" then
        loaded = data
      end
    end
    lightingSettings = mergeLightingSettings(defaultLightingSettings, loaded)
  end
  return lightingSettings
end

local function saveLightingSettings()
  if not DEBUG_LIGHTING_OPTIONS_ENABLED then
    return
  end

  if jsonWriteFile then
    pcall(jsonWriteFile, SETTINGS_PATH, getLightingSettings(), true)
  end
end

local function setObjectField(obj, fieldName, value)
  if not obj or value == nil then
    return
  end

  pcall(function() obj[fieldName] = value end)
  if obj.setField then
    local serialized = tostring(value)
    if type(value) == "boolean" then
      serialized = value and "1" or "0"
    end
    pcall(function() obj:setField(fieldName, 0, serialized) end)
  end
end

local function getTrackLightingObjectNames()
  local names = {}
  for _, prefix in ipairs(lightingNamePrefixes) do
    for i = 1, 80 do
      table.insert(names, prefix .. tostring(i))
    end
  end
  table.insert(names, "TreeLighting")
  return names
end

local function getLightingGroupObjectNames(groupKey)
  if groupKey == "track" then
    return getTrackLightingObjectNames()
  end
  if groupKey == "building" then
    return buildingLightingObjectNames
  end
  if groupKey == "parking" then
    return parkingLightingObjectNames
  end
  return {}
end

local function applyLightShadowSettings(obj, shadowsEnabled, settingsData)
  if not obj or not obj.getClassName then
    return false
  end

  local className = obj:getClassName()
  if className ~= "PointLight" and className ~= "SpotLight" then
    return false
  end

  if obj.preApply then
    pcall(function() obj:preApply() end)
  end

  setObjectField(obj, "castShadows", shadowsEnabled and true or false)
  if shadowsEnabled then
    setObjectField(obj, "texSize", tonumber(settingsData.texSize) or defaultLightingSettings.texSize)
    setObjectField(obj, "shadowSoftness", tonumber(settingsData.shadowSoftness) or defaultLightingSettings.shadowSoftness)
    setObjectField(obj, "shadowDistance", tonumber(settingsData.shadowDistance) or defaultLightingSettings.shadowDistance)
    setObjectField(obj, "fadeStartDistance", tonumber(settingsData.fadeStartDistance) or defaultLightingSettings.fadeStartDistance)
    setObjectField(obj, "priority", tonumber(settingsData.priority) or defaultLightingSettings.priority)
    setObjectField(obj, "staticRefreshFreq", tonumber(settingsData.staticRefreshFreq) or defaultLightingSettings.staticRefreshFreq)
    setObjectField(obj, "dynamicRefreshFreq", tonumber(settingsData.dynamicRefreshFreq) or defaultLightingSettings.dynamicRefreshFreq)
    setObjectField(obj, "representedInLightmap", settingsData.representedInLightmap == true)
    setObjectField(obj, "lastSplitTerrainOnly", settingsData.lastSplitTerrainOnly == true)
    setObjectField(obj, "shadowType", tostring(settingsData.shadowType or defaultLightingSettings.shadowType))
  end

  if obj.postApply then
    pcall(function() obj:postApply() end)
  end
  return true
end

local function applyLightingSettings()
  if not DEBUG_LIGHTING_OPTIONS_ENABLED then
    return
  end

  local settingsData = getLightingSettings()
  local changed = 0
  for _, group in ipairs(lightingShadowGroups) do
    local groupEnabled = settingsData.globalShadows == true and settingsData.groups and settingsData.groups[group.key] == true
    for _, name in ipairs(getLightingGroupObjectNames(group.key)) do
      if applyLightShadowSettings(findObject(name), groupEnabled, settingsData) then
        changed = changed + 1
      end
    end
  end
  log("I", "DragMP", string.format("Applied DragMP lighting shadow settings to %d lights", changed))
end

local function getUiSettings()
  if not DEBUG_LIGHTING_OPTIONS_ENABLED then
    return {
      debugEnabled = false,
      version = VERSION,
      groups = {},
      settings = copyTable(defaultLightingSettings)
    }
  end

  return {
    debugEnabled = true,
    version = VERSION,
    groups = lightingShadowGroups,
    settings = getLightingSettings()
  }
end

local function setUiSettings(data)
  if not DEBUG_LIGHTING_OPTIONS_ENABLED then
    log("I", "DragMP", "DragMP lighting shadow settings ignored because debug lighting options are disabled")
    return getUiSettings()
  end

  lightingSettings = mergeLightingSettings(defaultLightingSettings, data or {})
  saveLightingSettings()
  applyLightingSettings()
  return getUiSettings()
end

local function setHidden(obj, hidden)
  if obj and obj.setHidden then
    obj:setHidden(hidden)
  end
end

local function setRenderVisible(obj, visible)
  if not obj then
    return
  end

  if obj.preApply then
    pcall(function() obj:preApply() end)
  end
  setHidden(obj, not visible)
  if obj.setField then
    pcall(function() obj:setField("isRenderEnabled", 0, visible and "1" or "0") end)
    pcall(function() obj:setField("hidden", 0, visible and "0" or "1") end)
  else
    pcall(function() obj.isRenderEnabled = visible and true or false end)
  end
  if obj.postApply then
    pcall(function() obj:postApply() end)
  end
end

local function setWinnerEntryVisible(entry, visible)
  if not entry then
    return
  end

  if type(entry) == "table" and not entry.setHidden and not entry.setField then
    for _, obj in pairs(entry) do
      setRenderVisible(obj, visible)
    end
    return
  end

  setRenderVisible(entry, visible)
end

local function isHirochiLevel()
  if getCurrentLevelIdentifier then
    return getCurrentLevelIdentifier() == "hirochi_raceway"
  end
  if getMissionFilename then
    local mission = tostring(getMissionFilename() or "")
    return string.find(mission, "hirochi_raceway", 1, true) ~= nil
  end
  return false
end

local function setLightObjectEnabled(obj, enabled)
  if not obj or not obj.getClassName then
    return false
  end

  local className = obj:getClassName()
  if className ~= "PointLight" and className ~= "SpotLight" then
    return false
  end

  obj.isEnabled = enabled and true or false
  return true
end

local function setDragLightingEnabled(enabled)
  local changed = 0
  for _, prefix in ipairs(lightingNamePrefixes) do
    for i = 1, 80 do
      local obj = findObject(prefix .. tostring(i))
      if setLightObjectEnabled(obj, enabled) then
        changed = changed + 1
      end
    end
  end

  if setLightObjectEnabled(findObject("TreeLighting"), enabled) then
    changed = changed + 1
  end
  for _, name in ipairs(buildingLightingObjectNames) do
    if setLightObjectEnabled(findObject(name), enabled) then
      changed = changed + 1
    end
  end
  for _, name in ipairs(parkingLightingObjectNames) do
    if setLightObjectEnabled(findObject(name), enabled) then
      changed = changed + 1
    end
  end

  lightingEnabled = enabled and true or false
  log("I", "DragMP", string.format("Hirochi drag lighting %s (%d lights)", lightingEnabled and "enabled" or "disabled", changed))
end

local function shouldDragLightingBeEnabled(timeOfDay)
  if lightingMode == "on" then
    return true
  end
  if lightingMode == "off" then
    return false
  end

  if not timeOfDay then
    return lightingEnabled == true
  end

  if lightingEnabled == true then
    return timeOfDay >= LIGHTING_ON_HOLD_START and timeOfDay <= LIGHTING_ON_HOLD_END
  end

  return timeOfDay >= LIGHTING_ON_START and timeOfDay < LIGHTING_OFF_START
end

local function updateDragLightingForTime(force)
  if not lightingPrefabLoaded then
    return
  end

  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay() or nil
  local nextEnabled = shouldDragLightingBeEnabled(tod and tod.time or nil)
  if force or nextEnabled ~= lightingEnabled then
    setDragLightingEnabled(nextEnabled)
  end
end

local function loadDragLightingPrefab(forceReload)
  if not isHirochiLevel() then
    return false
  end

  if forceReload and removePrefab then
    pcall(removePrefab, LIGHTING_PREFAB_NAME)
    lightingPrefabLoaded = false
  end

  if scenetree and scenetree.findObject and scenetree.findObject(LIGHTING_PREFAB_NAME) then
    lightingPrefabLoaded = true
    updateDragLightingForTime(true)
    applyLightingSettings()
    return true
  end

  if not spawnPrefab then
    log("E", "DragMP", "spawnPrefab API unavailable for Hirochi drag lighting")
    return false
  end

  local ok, prefab = pcall(spawnPrefab, LIGHTING_PREFAB_NAME, LIGHTING_PREFAB_PATH, "0 0 0", "0 0 1 0", "1 1 1")
  if ok and prefab then
    lightingPrefabLoaded = true
    updateDragLightingForTime(true)
    applyLightingSettings()
    log("I", "DragMP", "Hirochi drag lighting prefab loaded")
    return true
  end

  log("E", "DragMP", "Failed to load Hirochi drag lighting prefab")
  return false
end

local function loadBuildingLightingPrefab(forceReload)
  if not isHirochiLevel() then
    return false
  end

  if forceReload and removePrefab then
    pcall(removePrefab, BUILDING_LIGHTING_PREFAB_NAME)
    buildingLightingPrefabLoaded = false
  end

  if scenetree and scenetree.findObject and scenetree.findObject(BUILDING_LIGHTING_PREFAB_NAME) then
    buildingLightingPrefabLoaded = true
    applyLightingSettings()
    return true
  end

  if not spawnPrefab then
    log("E", "DragMP", "spawnPrefab API unavailable for Hirochi building lighting")
    return false
  end

  local ok, prefab = pcall(spawnPrefab, BUILDING_LIGHTING_PREFAB_NAME, BUILDING_LIGHTING_PREFAB_PATH, "0 0 0", "0 0 1 0", "1 1 1")
  if ok and prefab then
    buildingLightingPrefabLoaded = true
    applyLightingSettings()
    log("I", "DragMP", "Hirochi building lighting prefab loaded")
    return true
  end

  log("E", "DragMP", "Failed to load Hirochi building lighting prefab")
  return false
end

local function loadParkingLightingPrefab(forceReload)
  if not isHirochiLevel() then
    return false
  end

  if forceReload and removePrefab then
    pcall(removePrefab, PARKING_LIGHTING_PREFAB_NAME)
    parkingLightingPrefabLoaded = false
  end

  if scenetree and scenetree.findObject and scenetree.findObject(PARKING_LIGHTING_PREFAB_NAME) then
    parkingLightingPrefabLoaded = true
    applyLightingSettings()
    return true
  end

  if not spawnPrefab then
    log("E", "DragMP", "spawnPrefab API unavailable for Hirochi parking lighting")
    return false
  end

  local ok, prefab = pcall(spawnPrefab, PARKING_LIGHTING_PREFAB_NAME, PARKING_LIGHTING_PREFAB_PATH, "0 0 0", "0 0 1 0", "1 1 1")
  if ok and prefab then
    parkingLightingPrefabLoaded = true
    applyLightingSettings()
    log("I", "DragMP", "Hirochi parking lighting prefab loaded")
    return true
  end

  log("E", "DragMP", "Failed to load Hirochi parking lighting prefab")
  return false
end

local function loadWinLightsPrefab(forceReload)
  if not isHirochiLevel() then
    return false
  end

  if forceReload and removePrefab then
    pcall(removePrefab, WIN_LIGHTS_PREFAB_NAME)
    winLightsPrefabLoaded = false
  end

  if scenetree and scenetree.findObject and scenetree.findObject(WIN_LIGHTS_PREFAB_NAME) then
    winLightsPrefabLoaded = true
    return true
  end

  if not spawnPrefab then
    log("E", "DragMP", "spawnPrefab API unavailable for Hirochi win lights")
    return false
  end

  local ok, prefab = pcall(spawnPrefab, WIN_LIGHTS_PREFAB_NAME, WIN_LIGHTS_PREFAB_PATH, "0 0 0", "0 0 1 0", "1 1 1")
  if ok and prefab then
    winLightsPrefabLoaded = true
    log("I", "DragMP", "Hirochi win lights prefab loaded")
    return true
  end

  log("E", "DragMP", "Failed to load Hirochi win lights prefab")
  return false
end

local function findWinLightObject(prefix, index)
  local id = string.format("%02d", index)
  return findObject(prefix .. "_WinLight_Driver_" .. id)
    or findObject(prefix .. "_WinLight_Driver_" .. id .. " (WinLight_Driver.dae)")
end

local function onLightingCommand(data)
  local payload = decode(data)
  local mode = payload.mode or "auto"
  if mode == "reload" then
    loadDragLightingPrefab(true)
    loadBuildingLightingPrefab(true)
    loadParkingLightingPrefab(true)
    mode = payload.previousMode or lightingMode or "auto"
    lightingMode = mode
    if lightingMode == "on" then
      setDragLightingEnabled(true)
    elseif lightingMode == "off" then
      setDragLightingEnabled(false)
    else
      updateDragLightingForTime(true)
    end
  elseif mode == "on" then
    lightingMode = "on"
    loadDragLightingPrefab(false)
    loadBuildingLightingPrefab(false)
    loadParkingLightingPrefab(false)
    setDragLightingEnabled(true)
  elseif mode == "off" then
    lightingMode = "off"
    loadDragLightingPrefab(false)
    loadBuildingLightingPrefab(false)
    loadParkingLightingPrefab(false)
    setDragLightingEnabled(false)
  else
    lightingMode = "auto"
    loadDragLightingPrefab(false)
    loadBuildingLightingPrefab(false)
    loadParkingLightingPrefab(false)
    updateDragLightingForTime(true)
  end
end

local function initTreeObjects()
  treeObjects = {}
  local found = 0
  local expected = 0
  local lightFields = { "prestage", "stage", "amber1", "amber2", "amber3", "green", "red" }
  for laneId, suffix in pairs(laneSuffix) do
    treeObjects[laneId] = {
      prestage = findObject("Prestagelight_" .. suffix),
      stage = findObject("Stagelight_" .. suffix),
      amber1 = findObject("Amberlight1_" .. suffix),
      amber2 = findObject("Amberlight2_" .. suffix),
      amber3 = findObject("Amberlight3_" .. suffix),
      green = findObject("Greenlight_" .. suffix),
      red = findObject("Redlight_" .. suffix)
    }
    for _, key in ipairs(lightFields) do
      expected = expected + 1
      local obj = treeObjects[laneId][key]
      if obj then
        found = found + 1
      end
    end
  end
  lightsReady = true
  log("I", "DragMP", string.format("Hirochi tree object scan: %d/%d found", found, expected))
end

local function initWinnerObjects()
  loadWinLightsPrefab(false)
  winnerObjects = {}
  local found = 0
  for laneId, _ in pairs(laneSuffix) do
    winnerObjects[laneId] = {
      timeboard = findObject("WinLight_Timeboard_" .. tostring(laneId)),
      driver = findObject("WinLight_Driver_" .. tostring(laneId)),
      sequence = {}
    }
    if winnerObjects[laneId].timeboard then
      setRenderVisible(winnerObjects[laneId].timeboard, false)
      found = found + 1
    end
    if winnerObjects[laneId].driver then
      setRenderVisible(winnerObjects[laneId].driver, false)
      found = found + 1
    end
    if winnerObjects[laneId].driver or winnerObjects[laneId].timeboard then
      winnerObjects[laneId].sequence[9] = {
        winnerObjects[laneId].driver,
        winnerObjects[laneId].timeboard
      }
    end

    local prefix = winLightPrefix[laneId]
    if prefix then
      for _, index in ipairs(winLightSequence) do
        local obj = findWinLightObject(prefix, index)
        if obj then
          winnerObjects[laneId].sequence[index] = obj
          setRenderVisible(obj, false)
          found = found + 1
        end
      end
    end
  end
  log("I", "DragMP", string.format("Hirochi winner light scan: %d objects found", found))
end

local function hasTreeObjects()
  return treeObjects[1] and treeObjects[1].prestage and treeObjects[1].green
end

local function initBoardObjects()
  boardObjects = {}
  local found = 0
  local expected = 0
  for laneId, suffix in pairs(boardSuffix) do
    boardObjects[laneId] = {
      time = {},
      speed = {},
      timePeriod = findObject("display_time_period_" .. suffix),
      speedPeriod = findObject("display_speed_period_" .. suffix)
    }

    for i = 1, 5 do
      boardObjects[laneId].time[i] = findObject("display_time_" .. tostring(i) .. "_" .. suffix)
      boardObjects[laneId].speed[i] = findObject("display_speed_" .. tostring(i) .. "_" .. suffix)
      expected = expected + 2
      if boardObjects[laneId].time[i] then
        found = found + 1
      end
      if boardObjects[laneId].speed[i] then
        found = found + 1
      end
    end
    expected = expected + 2
    if boardObjects[laneId].timePeriod then
      found = found + 1
    end
    if boardObjects[laneId].speedPeriod then
      found = found + 1
    end
  end

  -- Hirochi has a second duplicated finish board on one side with l1 period names.
  if not boardObjects[1].timePeriod then
    boardObjects[1].timePeriod = findObject("display_time_period_l1")
  end
  if not boardObjects[1].speedPeriod then
    boardObjects[1].speedPeriod = findObject("display_speed_period_l1")
  end
  log("I", "DragMP", string.format("Hirochi board object scan: %d/%d found", found, expected))
end

local function ensureSceneObjects()
  if not lightsReady or not hasTreeObjects() then
    initTreeObjects()
    initBoardObjects()
    initWinnerObjects()
  elseif not winLightsPrefabLoaded or not winnerObjects[1] or not winnerObjects[1].sequence or not next(winnerObjects[1].sequence) then
    initWinnerObjects()
  end
end

local function resetTree()
  ensureSceneObjects()
  winnerTreeSweep = {}
  for _, laneLights in pairs(treeObjects) do
    for _, obj in pairs(laneLights) do
      setHidden(obj, true)
    end
  end
end

local function laneIdSet(laneIds)
  local set = {}
  if type(laneIds) == "table" then
    for _, laneId in ipairs(laneIds) do
      set[tonumber(laneId)] = true
    end
  end
  return set
end

local function hideTreeLane(laneLights)
  if not laneLights then
    return
  end
  for _, obj in pairs(laneLights) do
    setHidden(obj, true)
  end
end

local function setWinnerTreeFlash(laneId, enabled)
  local laneLights = treeObjects[tonumber(laneId)]
  if not laneLights then
    return
  end

  setHidden(laneLights.prestage, not enabled)
  setHidden(laneLights.stage, not enabled)
  setHidden(laneLights.red, true)
  setHidden(laneLights.amber1, not enabled)
  setHidden(laneLights.amber2, not enabled)
  setHidden(laneLights.amber3, not enabled)
  setHidden(laneLights.green, not enabled)
end

local function startWinnerTreeSweep(laneId, keepExisting)
  ensureSceneObjects()
  if not keepExisting then
    winnerTreeSweep = {}
    for otherLaneId, laneLights in pairs(treeObjects) do
      if tonumber(otherLaneId) ~= tonumber(laneId) then
        hideTreeLane(laneLights)
      end
    end
  end

  laneId = tonumber(laneId)
  if not laneId or not treeObjects[laneId] then
    return
  end

  winnerTreeSweep[laneId] = {
    laneId = laneId,
    elapsed = 0,
    enabled = true
  }
  setWinnerTreeFlash(laneId, true)
end

local function clearDigits(digits)
  for _, obj in ipairs(digits or {}) do
    setHidden(obj, true)
  end
end

local function resetBoards()
  ensureSceneObjects()
  for _, board in pairs(boardObjects) do
    clearDigits(board.time)
    clearDigits(board.speed)
    setHidden(board.timePeriod, true)
    setHidden(board.speedPeriod, true)
  end
end

local function resetWinnerLights()
  ensureSceneObjects()
  winnerSequence = {}
  winnerTreeSweep = {}
  for _, laneWinnerObjects in pairs(winnerObjects) do
    setRenderVisible(laneWinnerObjects.timeboard, false)
    setRenderVisible(laneWinnerObjects.driver, false)
    for _, entry in pairs(laneWinnerObjects.sequence or {}) do
      setWinnerEntryVisible(entry, false)
    end
  end
end

local function setWinnerSequenceStep(laneId, heads)
  local laneWinnerObjects = winnerObjects[tonumber(laneId)]
  if not laneWinnerObjects then
    return
  end

  local visible = {}
  local function addTrail(head)
    if not head then
      return
    end
    for tail = 0, WIN_LIGHT_SEQUENCE_TAIL - 1 do
      local sequenceIndex = head - tail
      if sequenceIndex >= 1 then
        local lightIndex = winLightSequence[sequenceIndex]
        if lightIndex then
          visible[lightIndex] = true
        end
      end
    end
  end

  for _, head in ipairs(heads or {}) do
    addTrail(head)
  end
  for lightIndex, entry in pairs(laneWinnerObjects.sequence or {}) do
    setWinnerEntryVisible(entry, visible[lightIndex] == true)
  end
end

local function setWinnerLights(laneId, keepExisting, useTreeSweep)
  if not keepExisting then
    resetWinnerLights()
  end
  laneId = tonumber(laneId)
  local laneWinnerObjects = winnerObjects[laneId]
  if not laneWinnerObjects then
    return
  end
  setRenderVisible(laneWinnerObjects.timeboard, false)
  setRenderVisible(laneWinnerObjects.driver, false)
  winnerSequence[laneId] = {
    laneId = laneId,
    elapsed = 0,
    heads = { 1 },
    done = false,
    loop = true
  }
  setWinnerSequenceStep(laneId, winnerSequence[laneId].heads)
  if useTreeSweep ~= false then
    startWinnerTreeSweep(laneId, keepExisting)
  end
end

local function clearTimeslip()
  triggerUi("onDragRaceTimeslipData", nil)
end

local function setDigit(obj, digit)
  if not obj then
    return
  end

  obj:preApply()
  obj:setField("shapeName", 0, "/art/shapes/quarter_mile_display/display_" .. digit .. ".dae")
  obj:setHidden(false)
  obj:postApply()
end

local function formatDigits(value, decimals, width)
  local digits = {}
  local text = string.format("%." .. tostring(decimals) .. "f", value or 0)
  for digit in string.gmatch(text, "%d") do
    table.insert(digits, digit)
  end
  while #digits < width do
    table.insert(digits, 1, "empty")
  end
  while #digits > width do
    table.remove(digits, 1)
  end
  return digits
end

local function updateBoard(laneId, finishTime, finishMph)
  ensureSceneObjects()
  local board = boardObjects[laneId]
  if not board then
    return
  end

  local timeDigits = formatDigits(finishTime, 3, 5)
  local speedDigits = formatDigits(finishMph, 2, 5)

  for i, digit in ipairs(timeDigits) do
    setDigit(board.time[i], digit)
  end
  for i, digit in ipairs(speedDigits) do
    setDigit(board.speed[i], digit)
  end

  setHidden(board.timePeriod, false)
  setHidden(board.speedPeriod, false)
end

local function updateReactionBoard(laneId, reactionTime)
  ensureSceneObjects()
  local board = boardObjects[laneId]
  if not board then
    return
  end

  local timeDigits = formatDigits(reactionTime, 3, 5)
  for i, digit in ipairs(timeDigits) do
    setDigit(board.time[i], digit)
  end

  clearDigits(board.speed)
  setHidden(board.timePeriod, false)
  setHidden(board.speedPeriod, true)
end

local function onTestLights(data)
  local payload = decode(data)
  local testLaneId = tonumber(payload.laneId or "")
  ensureSceneObjects()
  resetTree()

  if testLaneId ~= 1 and testLaneId ~= 2 then
    for _, laneLights in pairs(treeObjects) do
      for _, obj in pairs(laneLights) do
        setHidden(obj, false)
      end
    end
  end

  for _, board in pairs(boardObjects) do
    for i = 1, 5 do
      setDigit(board.time[i], 8)
      setDigit(board.speed[i], 8)
    end
    setHidden(board.timePeriod, false)
    setHidden(board.speedPeriod, false)
  end

  resetWinnerLights()
  if testLaneId == 1 or testLaneId == 2 then
    setWinnerLights(testLaneId, false, true)
  else
    setWinnerLights(1, false, false)
    setWinnerLights(2, true, false)
  end

  notice(testLaneId and ("DragMP test lights and lane " .. tostring(testLaneId) .. " winner animation enabled.") or "DragMP test lights and winner animation enabled.")
end

local function setLaneStaging(laneId, prestaged, staged)
  ensureSceneObjects()
  local laneLights = treeObjects[laneId]
  if not laneLights then
    return
  end
  setHidden(laneLights.prestage, not prestaged)
  setHidden(laneLights.stage, not staged)
end

local function sendStageTelemetry(laneId, prestaged, staged, distanceFromStart, vehicleSpeed, jumped, lateral, inLane)
  if not TriggerServerEvent then
    return
  end

  local payload = table.concat({
    tostring(laneId),
    prestaged and "1" or "0",
    staged and "1" or "0",
    string.format("%.4f", distanceFromStart or 9999),
    string.format("%.4f", vehicleSpeed or 0),
    jumped and "1" or "0",
    string.format("%.4f", lateral or 9999),
    inLane and "1" or "0"
  }, "|")

  lastStageTelemetry = payload
  TriggerServerEvent("DragMPStageTelemetry", payload)
end

local function getLaneStagePosition(lane)
  if not lane then
    return nil
  end

  local waypoint = findObject("drag_" .. tostring(lane.id) .. "_stage")
  if waypoint and waypoint.getPosition then
    return waypoint:getPosition()
  end

  if lane.stage then
    return vec3(lane.stage.x, lane.stage.y, lane.stage.z)
  end

  return nil
end

local function calculateStageMetrics(vehicle, lane)
  local triggerPos = getLaneStagePosition(lane)
  if not vehicle or not triggerPos or not vehicle.getWheelCount or not vehicle.getDirectionVector then
    return nil
  end

  local vehiclePos = vehicle:getPosition()
  local vehicleForward = vehicle:getDirectionVector():normalized()
  vehicleForward.z = 0
  if vehicleForward:len() <= 0 then
    return nil
  end
  vehicleForward = vehicleForward:normalized()

  local laneForward = vehicleForward
  if lane and lane.finish and lane.stage then
    laneForward = vec3(lane.finish.x - lane.stage.x, lane.finish.y - lane.stage.y, 0)
    if laneForward:len() > 0 then
      laneForward = laneForward:normalized()
    else
      laneForward = vehicleForward
    end
  end
  local side = vec3(-laneForward.y, laneForward.x, 0)
  local bestForward = -math.huge
  local frontPoints = {}

  for i = 0, vehicle:getWheelCount() - 1 do
    local axisNodes = vehicle:getWheelAxisNodes(i)
    if axisNodes and axisNodes[1] and vehicle.getNodePosition then
      local nodeA = vec3(vehicle:getNodePosition(axisNodes[1]))
      local nodeB = axisNodes[2] and vec3(vehicle:getNodePosition(axisNodes[2])) or nil
      if nodeA then
        local wheelPoint = nodeA
        if nodeB then
          wheelPoint = (nodeA + nodeB) * 0.5
        end
        local wheelWorld = vehiclePos + wheelPoint
        local frontness = vec3(wheelWorld - vehiclePos):dot(vehicleForward)
        if frontness > bestForward + 0.2 then
          frontPoints = { wheelWorld }
          bestForward = frontness
        elseif math.abs(frontness - bestForward) <= 0.2 then
          table.insert(frontPoints, wheelWorld)
          if frontness > bestForward then
            bestForward = frontness
          end
        end
      end
    end
  end

  if #frontPoints == 0 then
    return nil
  end

  local frontPoint = vec3(0, 0, 0)
  for _, point in ipairs(frontPoints) do
    frontPoint = frontPoint + point
  end
  frontPoint = frontPoint * (1 / #frontPoints)

  local frontToTrigger = vec3(frontPoint - triggerPos)
  frontToTrigger.z = 0

  if frontToTrigger:len() > 14 then
    return nil
  end

  local distanceFromStart = frontToTrigger:dot(laneForward)
  local lateral = math.abs(frontToTrigger:dot(side))
  return {
    distanceFromStart = distanceFromStart,
    lateral = lateral,
    inLane = lateral <= STAGE_LATERAL_TOLERANCE
  }
end

local function stockStageState(distanceFromStart, inLane)
  if not inLane or not distanceFromStart or math.abs(distanceFromStart) > STAGE_EXIT then
    return false, false
  end

  local prestaged = distanceFromStart >= PRESTAGE_THRESHOLD - STAGE_WINDOW and distanceFromStart < PRESTAGE_THRESHOLD + STAGE_WINDOW
  local staged = distanceFromStart >= STAGE_THRESHOLD - STAGE_WINDOW and distanceFromStart < STAGE_THRESHOLD + STAGE_WINDOW
  return prestaged, staged
end

local function hasLeftStageBeam(distanceFromStart)
  return not distanceFromStart or distanceFromStart < STAGE_THRESHOLD - STAGE_WINDOW or distanceFromStart > STAGE_THRESHOLD + STAGE_WINDOW
end

local function getVehicleSpeed(vehicle)
  if not vehicle or not vehicle.getVelocity then
    return 0
  end

  local velocity = vehicle:getVelocity()
  if not velocity then
    return 0
  end

  return velocity:len()
end

local function setCountdown(value, treeMode, activeLaneIds)
  ensureSceneObjects()
  local activeLanes = laneIdSet(activeLaneIds)
  local hasActiveFilter = next(activeLanes) ~= nil

  if treeMode == "pro" then
    for laneId, laneLights in pairs(treeObjects) do
      if hasActiveFilter and not activeLanes[tonumber(laneId)] then
        hideTreeLane(laneLights)
      else
      setHidden(laneLights.prestage, true)
      setHidden(laneLights.stage, true)
      setHidden(laneLights.amber1, false)
      setHidden(laneLights.amber2, false)
      setHidden(laneLights.amber3, false)
      setHidden(laneLights.green, true)
      setHidden(laneLights.red, true)
      end
    end
  elseif value == 3 then
    for laneId, laneLights in pairs(treeObjects) do
      if hasActiveFilter and not activeLanes[tonumber(laneId)] then
        hideTreeLane(laneLights)
      else
      setHidden(laneLights.prestage, true)
      setHidden(laneLights.stage, true)
      setHidden(laneLights.amber1, false)
      setHidden(laneLights.amber2, true)
      setHidden(laneLights.amber3, true)
      setHidden(laneLights.green, true)
      setHidden(laneLights.red, true)
      end
    end
  elseif value == 2 then
    for laneId, laneLights in pairs(treeObjects) do
      if hasActiveFilter and not activeLanes[tonumber(laneId)] then
        hideTreeLane(laneLights)
      else
      setHidden(laneLights.amber1, true)
      setHidden(laneLights.amber2, false)
      setHidden(laneLights.amber3, true)
      end
    end
  elseif value == 1 then
    for laneId, laneLights in pairs(treeObjects) do
      if hasActiveFilter and not activeLanes[tonumber(laneId)] then
        hideTreeLane(laneLights)
      else
      setHidden(laneLights.amber1, true)
      setHidden(laneLights.amber2, true)
      setHidden(laneLights.amber3, false)
      end
    end
  end
end

local function setGreen(jumpedLanes, activeLaneIds)
  ensureSceneObjects()
  local jumpedByLane = {}
  for _, laneId in ipairs(jumpedLanes or {}) do
    jumpedByLane[tonumber(laneId)] = true
  end
  local activeLanes = laneIdSet(activeLaneIds)
  local hasActiveFilter = next(activeLanes) ~= nil

  for laneId, laneLights in pairs(treeObjects) do
    if hasActiveFilter and not activeLanes[tonumber(laneId)] then
      hideTreeLane(laneLights)
    else
    setHidden(laneLights.prestage, true)
    setHidden(laneLights.stage, true)
    setHidden(laneLights.amber1, true)
    setHidden(laneLights.amber2, true)
    setHidden(laneLights.amber3, true)
    if jumpedByLane[laneId] then
      setHidden(laneLights.green, true)
      setHidden(laneLights.red, false)
    else
      setHidden(laneLights.red, true)
      setHidden(laneLights.green, false)
    end
    end
  end
end

local function setRed(laneId)
  ensureSceneObjects()
  local laneLights = treeObjects[laneId]
  if not laneLights then
    return
  end
  setHidden(laneLights.prestage, true)
  setHidden(laneLights.stage, true)
  setHidden(laneLights.amber1, true)
  setHidden(laneLights.amber2, true)
  setHidden(laneLights.amber3, true)
  setHidden(laneLights.green, true)
  setHidden(laneLights.red, false)
end

local function getPlayerVehicle()
  if be and be.getPlayerVehicle then
    return be:getPlayerVehicle(0)
  end
  return nil
end

local function loadBestTimes()
  if dragBestTimes then
    return dragBestTimes
  end
  dragBestTimes = {}
  if jsonReadFile then
    local ok, data = pcall(jsonReadFile, BEST_TIMES_PATH)
    if ok and type(data) == "table" then
      dragBestTimes = data
    end
  end
  return dragBestTimes
end

local function saveBestTimes()
  if jsonWriteFile and dragBestTimes then
    pcall(jsonWriteFile, BEST_TIMES_PATH, dragBestTimes, true)
  end
end

local function getCurrentVehicleConfigKey()
  local vehicle = getPlayerVehicle()
  if not vehicle then
    return "unknown"
  end

  local model = "unknown"
  if vehicle.getJBeamFilename then
    model = tostring(vehicle:getJBeamFilename() or model)
  end

  local config = vehicle.partConfig
  if config == nil and vehicle.getField then
    config = vehicle:getField("partConfig", "0")
  end
  return model .. "|" .. tostring(config or "default")
end

local function getBestTimeForCurrentConfig()
  local bests = loadBestTimes()
  local entry = bests[getCurrentVehicleConfigKey()]
  if type(entry) == "table" then
    return tonumber(entry.et)
  end
  return nil
end

local function recordBestTimeForCurrentConfig(et, summary)
  et = tonumber(et)
  if not et or et <= 0 then
    return getBestTimeForCurrentConfig()
  end
  local bests = loadBestTimes()
  local key = getCurrentVehicleConfigKey()
  local old = bests[key]
  if type(old) ~= "table" or not old.et or et < tonumber(old.et) then
    bests[key] = {
      et = et,
      mph = summary and tonumber(summary.finishMph or summary.mph) or nil,
      updatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    saveBestTimes()
  end
  return getBestTimeForCurrentConfig()
end

local function pushDragNav(force)
  if not force and dragNavPushAccumulator > 0 then
    return
  end

  local vehicle = getPlayerVehicle()
  if not vehicle or not vehicle.queueLuaCommand then
    return
  end

  dragNavState.bestTime = getBestTimeForCurrentConfig()
  local payload = encode(dragNavState)
  vehicle:queueLuaCommand(string.format(
    "local p=%q; local c=controller.getControllerSafe and controller.getControllerSafe('dragmpNavScreen'); if c and c.setDragMPJson then c.setDragMPJson(p) end",
    payload
  ))
end

local function queueVehicleController(controllerName, methodName, payload)
  local vehicle = getPlayerVehicle()
  if not vehicle or not vehicle.queueLuaCommand then
    return false
  end

  local command = string.format(
    "local c=controller.getControllerSafe and controller.getControllerSafe(%q); if c and c.%s then c.%s(%q) end",
    controllerName,
    methodName,
    methodName,
    encode(payload or {})
  )
  vehicle:queueLuaCommand(command)
  return true
end


local function setDragNavState(values, force)
  if type(values) ~= "table" then
    return
  end

  for key, value in pairs(values) do
    dragNavState[key] = value
  end
  pushDragNav(force)
end

local function clearDragNavIdleTimer()
  dragNavIdleAt = nil
end

local function scheduleDragNavIdleTimer()
  dragNavIdleAt = os.clock() + DRAG_NAV_FINISH_IDLE_SECONDS
end

local function resetDragNav()
  dragNavGreenClock = nil
  dragNavPushAccumulator = 0
  clearDragNavIdleTimer()
  dragNavState = {
    reset = true,
    status = "WAITING",
    reactionTime = nil,
    elapsedTime = nil,
    quarterTime = nil,
    quarterMph = nil,
    bestTime = getBestTimeForCurrentConfig(),
    won = false,
    racing = false
  }
  pushDragNav(true)
end

local function startDragNavRun(status)
  dragNavGreenClock = nil
  dragNavPushAccumulator = 0
  clearDragNavIdleTimer()
  dragNavState = {
    reset = true,
    status = status or "STAGE",
    reactionTime = nil,
    elapsedTime = 0,
    quarterTime = nil,
    quarterMph = nil,
    bestTime = getBestTimeForCurrentConfig(),
    won = false,
    racing = false
  }
  pushDragNav(true)
end

local function teleportToLane(lane)
  local vehicle = getPlayerVehicle()
  if not vehicle or not lane or not lane.spawn then
    return false
  end

  local pos = vec3(lane.spawn.x, lane.spawn.y, lane.spawn.z)
  local rot = quat(lane.rot.x, lane.rot.y, lane.rot.z, lane.rot.w)

  if spawn and spawn.safeTeleport then
    spawn.safeTeleport(vehicle, pos, rot)
    return true
  end

  if vehicle.setPosRot then
    vehicle:setPosRot(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
    return true
  end

  return false
end

local function onStageLane(data)
  log("I", "DragMP", "StageLane event received")
  local payload = decode(data)
  activeLane = payload.lane
  activeSessionId = tonumber(payload.sessionId) or activeSessionId
  serverRaceState = "staging"
  localStageReady = false
  localJumped = false
  lastStageTelemetry = nil
  startDragNavRun("STAGE")

  if activeLane then
    resetTree()
    resetBoards()
    notice("Assigned to " .. activeLane.name .. " lane.")
    if teleportToLane(activeLane) then
      notice("Moved to Hirochi drag staging area.")
    else
      notice("Drive to the Hirochi drag staging area, then use /drag start.")
    end
  end
end

local function onStageState(data)
  local payload = decode(data)
  if winnerTreeSweep and next(winnerTreeSweep) ~= nil then
    return
  end
  if payload.sessionId then
    activeSessionId = tonumber(payload.sessionId) or activeSessionId
  end
  serverRaceState = payload.state or serverRaceState
  if not payload.lanes then
    return
  end

  for _, lane in ipairs(payload.lanes) do
    if not winnerTreeSweep or not winnerTreeSweep[tonumber(lane.laneId)] then
      setLaneStaging(lane.laneId, lane.prestaged, lane.staged)
      if lane.jumped then
        setRed(lane.laneId)
      end
    end
    if activeLane and tonumber(activeLane.id) == tonumber(lane.laneId) and serverRaceState == "staging" then
      local status = "STAGE"
      if lane.staged then
        status = "STAGED"
      elseif lane.prestaged then
        status = "PRE-STAGE"
      end
      setDragNavState({ status = status }, true)
    end
  end
end

local function onNotice(data)
  local payload = decode(data)
  if payload.message then
    notice(payload.message)
  end
end

local function onCountdown(data)
  log("I", "DragMP", "Countdown event received")
  local payload = decode(data)
  if payload.value then
    setCountdown(payload.value, payload.treeMode, payload.laneIds)
  end
end

local function onGreen(data)
  log("I", "DragMP", "Green event received")
  local payload = decode(data)
  serverRaceState = "racing"
  if activeLane then
    clearDragNavIdleTimer()
    dragNavGreenClock = os.clock()
    dragNavState = {
      reset = true,
      status = "RUN",
      reactionTime = dragNavState.reactionTime,
      elapsedTime = 0,
      quarterTime = nil,
      quarterMph = nil,
      bestTime = getBestTimeForCurrentConfig(),
      won = false,
      racing = true
    }
    pushDragNav(true)
  end
  setGreen(payload.jumpedLanes, payload.laneIds)
end

local function onRaceReset(data)
  local payload = decode(data)
  local resetSessionId = tonumber(payload.sessionId)
  if activeLane and activeSessionId and resetSessionId and resetSessionId <= activeSessionId then
    return
  end

  activeLane = nil
  activeSessionId = resetSessionId
  serverRaceState = "idle"
  localStageReady = false
  localJumped = false
  lastStageTelemetry = nil
  resetDragNav()
  resetTree()
  resetBoards()
  resetWinnerLights()
  clearTimeslip()
  notice("Drag race reset.")
end

local function onTreeReset()
  log("I", "DragMP", "TreeReset event received")
  resetTree()
  resetBoards()
  resetWinnerLights()
end

local function onJumpStart(data)
  log("I", "DragMP", "JumpStart event received")
  local payload = decode(data)
  if payload.laneId then
    setRed(payload.laneId)
  end
  if payload.name then
    notice(payload.name .. " red lit.")
  end
end

local function onLaneResult(data)
  log("I", "DragMP", "LaneResult event received")
  local payload = decode(data)
  if payload.disqualified then
    if activeLane and tonumber(activeLane.id) == tonumber(payload.laneId) then
      setDragNavState({ status = "DQ", racing = false }, true)
      scheduleDragNavIdleTimer()
    end
    notice(string.format("%s DQ: %s", payload.name or ("Lane " .. tostring(payload.laneId)), payload.reason or "disqualified"))
    return
  end
  if payload.laneId and payload.time and payload.mph then
    updateBoard(payload.laneId, payload.time, payload.mph)
    if activeLane and tonumber(activeLane.id) == tonumber(payload.laneId) then
      local bestTime = recordBestTimeForCurrentConfig(payload.time, {finishMph = payload.mph})
      setDragNavState({
        status = "FINISH",
        elapsedTime = payload.time,
        bestTime = bestTime,
        racing = false
      }, true)
      scheduleDragNavIdleTimer()
    end
    notice(string.format("%s %.3fs %.2f MPH", payload.name or ("Lane " .. tostring(payload.laneId)), payload.time, payload.mph))
  end
end

local function onReactionTime(data)
  log("I", "DragMP", "ReactionTime event received")
  local payload = decode(data)
  if payload.laneId and payload.reactionTime then
    updateReactionBoard(payload.laneId, payload.reactionTime)
    if activeLane and tonumber(activeLane.id) == tonumber(payload.laneId) then
      setDragNavState({
        status = "RUN",
        reactionTime = payload.reactionTime,
        racing = true
      }, true)
      notice(string.format("%s R/T %.3fs", payload.name or ("Lane " .. tostring(payload.laneId)), payload.reactionTime))
    end
  end
end

local function onWinner(data)
  local payload = decode(data)
  if payload.laneId then
    serverRaceState = "finished"
    if activeLane then
      setDragNavState({
        status = tonumber(activeLane.id) == tonumber(payload.laneId) and "WIN" or "FINISH",
        won = tonumber(activeLane.id) == tonumber(payload.laneId),
        racing = false
      }, true)
      scheduleDragNavIdleTimer()
    end
    setWinnerLights(payload.laneId)
  else
    serverRaceState = "finished"
    setDragNavState({ status = "FINISH", won = false, racing = false }, true)
    scheduleDragNavIdleTimer()
    resetWinnerLights()
  end
end

local function onSplitTime(data)
  local payload = decode(data)
  if payload.label and payload.time then
    log("I", "DragMP", string.format(
      "%s %s split: ET %.3fs | ET w/o RT %s | MPH %.2f",
      payload.name or ("Lane " .. tostring(payload.laneId or "?")),
      payload.label,
      payload.time,
      payload.etWithoutRt and string.format("%.3fs", payload.etWithoutRt) or "N/A",
      payload.mph or 0
    ))
  end
end

local function formatSummaryValue(value, suffix, decimals)
  if value == nil then
    return "N/A"
  end
  return string.format("%." .. tostring(decimals or 3) .. "f%s", value, suffix or "")
end

local function formatSlipTimer(value)
  if value == nil then
    return "-"
  end
  return string.format("%.3f", value)
end

local function formatSlipVelocity(value)
  if value == nil then
    return "-"
  end
  return string.format("%.3f", value)
end

local function getSplitByKey(payload, key)
  for _, split in ipairs(payload.splits or {}) do
    if split.key == key then
      return split
    end
  end
  return nil
end

local function splitTime(payload, key)
  local split = getSplitByKey(payload, key)
  if split and split.available and split.time then
    return split.time
  end
  return nil
end

local function splitMph(payload, key)
  local split = getSplitByKey(payload, key)
  if split and split.available and split.mph then
    return split.mph
  end
  return nil
end

local function isEighthMileSummary(payload)
  local trackKey = tostring(payload.trackKey or ""):lower()
  local trackLabel = tostring(payload.trackLabel or ""):lower()
  local trackLengthMeters = tonumber(payload.trackLengthMeters)
  return trackKey == "660ft"
    or trackKey == "1/8"
    or trackLabel:find("1/8", 1, true) ~= nil
    or (trackLengthMeters ~= nil and trackLengthMeters < 250)
end

local function timeslipTimerRows(isEighthMile)
  local rows = {
    { key = "laneName", label = "Lane" },
    { key = "dial", label = "DIAL" },
    { key = "reactionTime", label = "R/T" },
    { key = "time_60", label = "60'" },
    { key = "time_330", label = "330'" },
    { key = "time_1_8", label = "1/8" },
    { key = "velAt_1_8_kmh", label = "KM/H" },
    { key = "velAt_1_8_mph", label = "MPH" }
  }

  if not isEighthMile then
    table.insert(rows, { key = "time_1000", label = "1000'" })
    table.insert(rows, { key = "time_1_4", label = "1/4" })
    table.insert(rows, { key = "velAt_1_4_kmh", label = "KM/H" })
    table.insert(rows, { key = "velAt_1_4_mph", label = "MPH" })
  end

  table.insert(rows, { key = "dialDiff", label = "DIFF" })
  return rows
end

local function buildStockRacerInfo(payload)
  local laneId = tonumber(payload.laneId) or 1
  local laneName = payload.laneName or (laneId == 1 and "Right Lane" or "Left Lane")
  local isEighthMile = isEighthMileSummary(payload)
  local eighthMph = splitMph(payload, "660ft")
  local quarterMph = isEighthMile and nil or splitMph(payload, "1320ft")

  return {
    name = payload.name or ("Lane " .. tostring(laneId)),
    stock = "Modified",
    licenseText = "DragMP",
    lane = laneName,
    laneNum = laneId,
    finalTime = (isEighthMile and splitTime(payload, "660ft") or splitTime(payload, "1320ft")) or payload.finishTime or 0,
    rewards = {},
    dialDiff = 0,
    disqualification = payload.jumped or payload.disqualified or false,
    brand = "Unknown",
    country = "Unknown",
    drivetrain = "Unknown",
    fuelType = "Unknown",
    transmission = "Unknown",
    configType = "Unknown",
    inductionType = "Unknown",
    timers = {
      reactionTime = formatSlipTimer(payload.reactionTime),
      time_60 = formatSlipTimer(splitTime(payload, "60ft")),
      time_330 = formatSlipTimer(splitTime(payload, "330ft")),
      time_1_8 = formatSlipTimer(splitTime(payload, "660ft")),
      time_1000 = isEighthMile and "-" or formatSlipTimer(splitTime(payload, "1000ft")),
      time_1_4 = isEighthMile and "-" or formatSlipTimer(splitTime(payload, "1320ft")),
      dial = "-"
    },
    velocities = {
      ["velAt_1_8_km/h"] = formatSlipVelocity(eighthMph and eighthMph * 1.609344 or nil),
      ["velAt_1_8_mph"] = formatSlipVelocity(eighthMph),
      ["velAt_1_4_km/h"] = formatSlipVelocity(quarterMph and quarterMph * 1.609344 or nil),
      ["velAt_1_4_mph"] = formatSlipVelocity(quarterMph)
    }
  }
end

local function buildStockTimeslip(payload)
  local racerInfos = {}
  local stripSummary = payload
  if payload.summaries then
    for _, summary in ipairs(payload.summaries) do
      stripSummary = stripSummary == payload and summary or stripSummary
      table.insert(racerInfos, buildStockRacerInfo(summary))
    end
  else
    table.insert(racerInfos, buildStockRacerInfo(payload))
  end

  local isEighthMile = isEighthMileSummary(stripSummary)

  return {
    stripInfo = {
      stripName = "DragMP",
      levelName = "Hirochi Raceway",
      dateTime = os.date("%a %m/%d/%Y %I:%M:%S %p"),
      tree = stripSummary.treeName or (stripSummary.treeMode == "pro" and "Pro Tree" or "Sportsman Tree")
    },
    env = {
      tempK = core_environment and core_environment.getTemperatureK and core_environment.getTemperatureK() or 293.15,
      tempC = core_environment and core_environment.getTemperatureK and (core_environment.getTemperatureK() - 273.15) or 20,
      tempF = core_environment and core_environment.getTemperatureK and ((core_environment.getTemperatureK() - 273.15) * (9 / 5) + 32) or 68,
      customGrav = false,
      gravity = "9.81 m/s^2"
    },
    dragType = "headsUpDrag",
    finishTimerKey = isEighthMile and "time_1_8" or "time_1_4",
    timerRowsInfo = timeslipTimerRows(isEighthMile),
    racerInfos = racerInfos
  }
end

local function logRunSummary(payload)
  local name = payload.name or ("Lane " .. tostring(payload.laneId or "?"))

  log("I", "DragMP", string.format(
    "%s run summary: track %s (%.1fm), R/T %s",
    name,
    payload.trackLabel or "unknown",
    payload.trackLengthMeters or 0,
    formatSummaryValue(payload.reactionTime, "s", 3)
  ))

  for _, split in ipairs(payload.splits or {}) do
    if split.available then
      log("I", "DragMP", string.format(
        "%s %s: ET %s | ET w/o RT %s | MPH %s",
        name,
        split.label or split.key or "?",
        formatSummaryValue(split.time, "s", 3),
        formatSummaryValue(split.etWithoutRt, "s", 3),
        formatSummaryValue(split.mph, "", 2)
      ))
    else
      log("I", "DragMP", string.format(
        "%s %s: ET N/A | ET w/o RT N/A | MPH N/A",
        name,
        split.label or split.key or "?"
      ))
    end
  end
end

local function onRunSummary(data)
  local payload = decode(data)
  triggerUi("onDragRaceTimeslipData", buildStockTimeslip(payload))
  if payload.summaries then
    for _, summary in ipairs(payload.summaries) do
      logRunSummary(summary)
    end
  else
    logRunSummary(payload)
  end

  local localSummary = nil
  if activeLane and payload.summaries then
    for _, summary in ipairs(payload.summaries) do
      if tonumber(summary.laneId) == tonumber(activeLane.id) then
        localSummary = summary
        break
      end
    end
  elseif activeLane and not payload.summaries and (payload.laneId == nil or tonumber(payload.laneId) == tonumber(activeLane.id)) then
    localSummary = payload
  end

  if localSummary then
    local quarter = getSplitByKey(localSummary, "1320ft")
    local bestTime = recordBestTimeForCurrentConfig(localSummary.finishTime, localSummary)
    setDragNavState({
      status = dragNavState.won and "WIN" or "FINISH",
      elapsedTime = localSummary.finishTime,
      quarterTime = quarter and quarter.available and quarter.time or nil,
      quarterMph = quarter and quarter.available and quarter.mph or nil,
      reactionTime = localSummary.reactionTime or dragNavState.reactionTime,
      bestTime = bestTime,
      racing = false
    }, true)
    scheduleDragNavIdleTimer()
  end
end

local function onRaceFinished(data)
  local payload = decode(data)
  serverRaceState = "finished"
  if payload.winner then
    notice("Winner: " .. payload.winner)
  else
    notice("Race finished.")
  end
end

local function onSelfTest()
  log("I", "DragMP", "Self-test client event received")
end

local function updateWinnerSequence(dtReal)
  if not winnerSequence then
    return
  end

  for laneId, sequence in pairs(winnerSequence) do
    if not sequence.done then
      sequence.elapsed = sequence.elapsed + (dtReal or 0)
      while sequence.elapsed >= WIN_LIGHT_SEQUENCE_STEP_SECONDS do
        sequence.elapsed = sequence.elapsed - WIN_LIGHT_SEQUENCE_STEP_SECONDS

        sequence.heads = sequence.heads or { 1 }
        for i = #sequence.heads, 1, -1 do
          sequence.heads[i] = sequence.heads[i] + 1
          if sequence.heads[i] - WIN_LIGHT_SEQUENCE_TAIL > #winLightSequence then
            table.remove(sequence.heads, i)
          end
        end

        if sequence.loop then
          local newestHead = sequence.heads[#sequence.heads]
          local newestTail = newestHead and (newestHead - WIN_LIGHT_SEQUENCE_TAIL + 1) or nil
          if not newestTail or newestTail >= WIN_LIGHT_SEQUENCE_RESTART_AFTER_TAIL then
            table.insert(sequence.heads, 1)
          end
        elseif #sequence.heads == 0 then
          sequence.done = true
          setWinnerSequenceStep(sequence.laneId or laneId, {})
          break
        end
      end

      if not sequence.done then
        setWinnerSequenceStep(sequence.laneId or laneId, sequence.heads)
      end
    end
  end
end

local function updateWinnerTreeSweep(dtReal)
  if not winnerTreeSweep then
    return
  end

  for laneId, sweep in pairs(winnerTreeSweep) do
    sweep.elapsed = sweep.elapsed + (dtReal or 0)
    while sweep.elapsed >= WINNER_TREE_FLASH_STEP_SECONDS do
      sweep.elapsed = sweep.elapsed - WINNER_TREE_FLASH_STEP_SECONDS
      sweep.enabled = not sweep.enabled
      setWinnerTreeFlash(sweep.laneId or laneId, sweep.enabled)
    end
  end
end

local function refreshWinnerTreeSweep()
  if not winnerTreeSweep then
    return
  end

  for laneId, sweep in pairs(winnerTreeSweep) do
    setWinnerTreeFlash(sweep.laneId or laneId, sweep.enabled ~= false)
  end
end

local function onUpdate(dtReal)
  updateWinnerSequence(dtReal)
  updateWinnerTreeSweep(dtReal)

  if dragNavIdleAt and os.clock() >= dragNavIdleAt then
    resetDragNav()
  end

  if dragNavState.racing and dragNavGreenClock then
    dragNavPushAccumulator = dragNavPushAccumulator + (dtReal or 0)
    if dragNavPushAccumulator >= 0.1 then
      dragNavPushAccumulator = 0
      dragNavState.elapsedTime = math.max(0, os.clock() - dragNavGreenClock)
      pushDragNav(false)
    end
  end

  lightingUpdateAccumulator = lightingUpdateAccumulator + (dtReal or 0)
  if lightingUpdateAccumulator >= 2 then
    lightingUpdateAccumulator = 0
    if not lightingPrefabLoaded or not buildingLightingPrefabLoaded or not parkingLightingPrefabLoaded then
      loadDragLightingPrefab(false)
      loadBuildingLightingPrefab(false)
      loadParkingLightingPrefab(false)
      updateDragLightingForTime(false)
    else
      updateDragLightingForTime(false)
    end
  end

  if not activeLane or (serverRaceState ~= "staging" and serverRaceState ~= "countdown" and serverRaceState ~= "racing") then
    return
  end

  stageTelemetryAccumulator = stageTelemetryAccumulator + (dtReal or 0)
  if stageTelemetryAccumulator < 0.05 then
    return
  end
  stageTelemetryAccumulator = 0

  local vehicle = getPlayerVehicle()
  local stageMetrics = calculateStageMetrics(vehicle, activeLane)

  if not stageMetrics then
    localStageReady = false
    if serverRaceState == "staging" or serverRaceState == "countdown" then
      setLaneStaging(activeLane.id, false, false)
    end
    sendStageTelemetry(activeLane.id, false, false, 9999, 0, localJumped, 9999, false)
    refreshWinnerTreeSweep()
    return
  end

  local vehicleSpeed = getVehicleSpeed(vehicle)
  local distanceFromStart = stageMetrics.distanceFromStart
  local lateral = stageMetrics.lateral
  local inLane = stageMetrics.inLane
  local prestaged, staged = stockStageState(distanceFromStart, inLane)
  local jumped = hasLeftStageBeam(distanceFromStart)
  if serverRaceState == "countdown" and jumped then
    localJumped = true
  end

  localStageReady = staged

  if serverRaceState == "staging" or serverRaceState == "countdown" then
    setLaneStaging(activeLane.id, inLane and prestaged, localStageReady)
  end
  sendStageTelemetry(activeLane.id, inLane and prestaged, localStageReady, distanceFromStart, vehicleSpeed, localJumped or jumped, lateral, inLane)
  refreshWinnerTreeSweep()
end

local function registerHandlers()
  if AddEventHandler then
    local handlers = {
      DragMPStageLane = onStageLane,
      DragMPStageState = onStageState,
      DragMPNotice = onNotice,
      DragMPCountdown = onCountdown,
      DragMPGreen = onGreen,
      DragMPRaceReset = onRaceReset,
      DragMPTreeReset = onTreeReset,
      DragMPJumpStart = onJumpStart,
      DragMPReactionTime = onReactionTime,
      DragMPSplitTime = onSplitTime,
      DragMPRunSummary = onRunSummary,
      DragMPLaneResult = onLaneResult,
      DragMPRaceFinished = onRaceFinished,
      DragMPWinner = onWinner,
      DragMPLighting = onLightingCommand,
      DragMPTestLights = onTestLights,
      DragMPSelfTest = onSelfTest,
    }

    for eventName, handler in pairs(handlers) do
      if RemoveEventHandler then
        pcall(RemoveEventHandler, eventName, HANDLER_SOURCE)
      end
      AddEventHandler(eventName, handler, HANDLER_SOURCE)
    end
  else
    log("E", "DragMP", "BeamMP AddEventHandler API is unavailable")
  end
end

local function onExtensionLoaded()
  enableFunStuffBlocker()
  loadDragLightingPrefab(false)
  loadBuildingLightingPrefab(false)
  loadParkingLightingPrefab(false)
  loadWinLightsPrefab(false)
  initTreeObjects()
  initBoardObjects()
  initWinnerObjects()
  resetTree()
  resetBoards()
  resetWinnerLights()
  registerHandlers()
  if TriggerClientEvent then
    TriggerClientEvent("DragMPSelfTest", "{}")
  end
  notice("DragMP client loaded " .. VERSION)
end

local function onClientStartMission()
  enableFunStuffBlocker()
  lightingPrefabLoaded = false
  buildingLightingPrefabLoaded = false
  parkingLightingPrefabLoaded = false
  winLightsPrefabLoaded = false
  winnerSequence = {}
  lightingEnabled = nil
  lightingUpdateAccumulator = 0
  loadDragLightingPrefab(false)
  loadBuildingLightingPrefab(false)
  loadParkingLightingPrefab(false)
  loadWinLightsPrefab(false)
  initWinnerObjects()
  resetWinnerLights()
end

M.onExtensionLoaded = onExtensionLoaded
M.onClientStartMission = onClientStartMission
M.onUpdate = onUpdate
M.getUiSettings = getUiSettings
M.setUiSettings = setUiSettings
M.applyLightingSettings = applyLightingSettings

return M


