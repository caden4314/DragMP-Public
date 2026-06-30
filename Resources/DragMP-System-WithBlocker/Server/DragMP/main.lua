local PLUGIN = "DragMP"
local CLIENT_EVENTS = {
  StageLane = "DragMPStageLane",
  StageState = "DragMPStageState",
  Notice = "DragMPNotice",
  Countdown = "DragMPCountdown",
  Green = "DragMPGreen",
  RaceReset = "DragMPRaceReset",
  TreeReset = "DragMPTreeReset",
  JumpStart = "DragMPJumpStart",
  ReactionTime = "DragMPReactionTime",
  SplitTime = "DragMPSplitTime",
  RunSummary = "DragMPRunSummary",
  LaneResult = "DragMPLaneResult",
  RaceFinished = "DragMPRaceFinished",
  Winner = "DragMPWinner",
  Lighting = "DragMPLighting",
  TestLights = "DragMPTestLights",
}

local STATE_IDLE = "idle"
local STATE_STAGING = "staging"
local STATE_COUNTDOWN = "countdown"
local STATE_RACING = "racing"
local STATE_FINISHED = "finished"

local SPLITS = {
  { key = "60ft", label = "60 ft", meters = 18.288 },
  { key = "330ft", label = "330 ft", meters = 100.584 },
  { key = "660ft", label = "1/8 mile", meters = 201.168 },
  { key = "1000ft", label = "1000 ft", meters = 304.8 },
  { key = "1320ft", label = "1/4 mile", meters = 402.336 }
}

local RACE_DISTANCE_MODES = {
  ["1/8"] = { key = "660ft", label = "1/8 mile", meters = 201.168 },
  ["1/4"] = { key = "1320ft", label = "1/4 mile", meters = 402.336 }
}

local track = {
  level = "/levels/hirochi_raceway/info.json",
  name = "Hirochi Main Strip",
  raceDistanceMode = "1/4",
  stageLateralTolerance = 5.5,
  clientStageLateralTolerance = 2.4,
  raceLateralTolerance = 3.6,
  clientStageMaxAgeSeconds = 0.75,
  frontAxleOffset = 0.7,
  preStageThreshold = -0.178,
  stageThreshold = 0,
  stageWindow = 0.178,
  stageExit = 0.4,
  finishRadius = 12.0,
  jumpStartSpeed = 1.5,
  countdownSeconds = 5,
  autoStartHoldSeconds = 2.0,
  raceTimeoutSeconds = 45,
  lanes = {
    {
      id = 1,
      name = "Right",
      spawn = { x = -530.2731934, y = -332.3446655, z = 52.07132339 },
      stage = { x = -514.7761841, y = -337.796051, z = 52.00240707 },
      finish = { x = -141.3102112, y = -477.2987061, z = 52.00254822 },
      rot = { x = 0, y = 0, z = 0.824031931, w = 0.5665433582 }
    },
    {
      id = 2,
      name = "Left",
      spawn = { x = -527.4268799, y = -324.9911499, z = 52.0 },
      stage = { x = -512.0938721, y = -330.6264038, z = 52.00145721 },
      finish = { x = -138.6012421, y = -470.1653442, z = 52.00250626 },
      rot = { x = 0, y = 0, z = 0.8306674358, w = 0.5567689028 }
    }
  }
}

local race = {
  state = STATE_IDLE,
  racers = {},
  countdownTimer = nil,
  raceTimer = nil,
  stagingTimer = nil,
  startedAt = nil,
  winner = nil,
  treeMode = "sportsman",
  autoStartAnnounced = false,
  sessionId = 0
}

local dragLightingMode = "auto"

local function encode(tbl)
  if Util and Util.JsonEncode then
    return Util.JsonEncode(tbl)
  end
  return "{}"
end

local function sendClient(playerId, eventName, data)
  local ok, err = MP.TriggerClientEvent(playerId, eventName, encode(data or {}))
  if ok == false then
    print("DragMP client event failed", eventName, playerId, err or "")
  end
end

local function cancelTimer(eventName)
  MP.CancelEventTimer(eventName)
end

local function chat(playerId, message)
  MP.SendChatMessage(playerId or -1, "[DragMP] " .. message)
end

local function getName(playerId)
  return MP.GetPlayerName(playerId) or ("Player " .. tostring(playerId))
end

local function distance(a, b)
  local dx = (a.x or a[1]) - (b.x or b[1])
  local dy = (a.y or a[2]) - (b.y or b[2])
  local dz = (a.z or a[3]) - (b.z or b[3])
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function speed(pos)
  if not pos or not pos.vel then
    return 0
  end
  local vx = pos.vel[1] or pos.vel.x or 0
  local vy = pos.vel[2] or pos.vel.y or 0
  local vz = pos.vel[3] or pos.vel.z or 0
  return math.sqrt(vx * vx + vy * vy + vz * vz)
end

local function mph(pos)
  return speed(pos) * 2.2369362920544
end

local function laneProgress(vehiclePos, lane)
  local dx = lane.finish.x - lane.stage.x
  local dy = lane.finish.y - lane.stage.y
  local length = math.sqrt(dx * dx + dy * dy)
  if length <= 0 then
    return 9999, 9999
  end

  local ux = dx / length
  local uy = dy / length
  local rx = vehiclePos.x - lane.stage.x
  local ry = vehiclePos.y - lane.stage.y
  local along = rx * ux + ry * uy
  local lateral = math.abs(rx * -uy + ry * ux)
  return along, lateral, ux, uy
end

local function laneLength(lane)
  local finishAlong = laneProgress(lane.finish, lane)
  return finishAlong
end

local function selectedRaceDistance()
  return RACE_DISTANCE_MODES[track.raceDistanceMode or "1/4"] or RACE_DISTANCE_MODES["1/4"]
end

local function trackType(lane)
  local selected = selectedRaceDistance()
  return selected.key, selected.label, selected.meters
end

local function stagingState(pos, lane)
  if not pos or not pos.pos then
    return false, false
  end

  local x, y, z = table.unpack(pos.pos)
  local along, lateral = laneProgress({ x = x, y = y, z = z }, lane)
  if lateral > track.stageLateralTolerance then
    return false, false
  end

  local frontAxleAlong = along + track.frontAxleOffset
  local distanceFromStart = frontAxleAlong
  if math.abs(distanceFromStart) > track.stageExit then
    return false, false
  end

  local prestaged = distanceFromStart >= track.preStageThreshold - track.stageWindow and distanceFromStart < track.preStageThreshold + track.stageWindow
  local staged = distanceFromStart >= track.stageThreshold - track.stageWindow and distanceFromStart < track.stageThreshold + track.stageWindow
  return prestaged, staged
end

local function isFreshClientStage(racer)
  return racer and racer.clientStage and racer.clientStageTimer and racer.clientStageTimer:GetCurrent() <= track.clientStageMaxAgeSeconds
end

local function stagingMetrics(pos, lane)
  if not pos or not pos.pos then
    return nil
  end

  local x, y, z = table.unpack(pos.pos)
  local along, lateral = laneProgress({ x = x, y = y, z = z }, lane)
  local prestaged, staged = stagingState(pos, lane)
  local frontAxleAlong = along + track.frontAxleOffset
  local distanceFromStart = frontAxleAlong
  return {
    along = along,
    lateral = lateral,
    frontAxleAlong = frontAxleAlong,
    distanceFromStart = distanceFromStart,
    speed = speed(pos),
    prestaged = prestaged,
    staged = staged
  }
end

local function clientStageMetrics(racer)
  if not isFreshClientStage(racer) then
    return nil
  end

  local clientStage = racer.clientStage
  if not clientStage or not clientStage.inLane then
    return nil
  end
  if not clientStage.distanceFromStart or math.abs(clientStage.distanceFromStart) > 20 then
    return nil
  end
  if not clientStage.lateral or clientStage.lateral > track.clientStageLateralTolerance then
    return nil
  end

  return {
    distanceFromStart = clientStage.distanceFromStart,
    speed = clientStage.speed,
    prestaged = clientStage.prestaged,
    staged = clientStage.staged,
    jumped = clientStage.jumped,
    lateral = clientStage.lateral,
    inLane = clientStage.inLane,
    source = "client-stock"
  }
end

local function stockStagingFromDistance(distanceFromStart, laneOk)
  if not laneOk or not distanceFromStart or math.abs(distanceFromStart) > track.stageExit then
    return false, false
  end

  local prestaged = distanceFromStart >= track.preStageThreshold - track.stageWindow and distanceFromStart < track.preStageThreshold + track.stageWindow
  local staged = distanceFromStart >= track.stageThreshold - track.stageWindow and distanceFromStart < track.stageThreshold + track.stageWindow
  return prestaged, staged
end

local function leftStageBeam(distanceFromStart)
  return not distanceFromStart or distanceFromStart < track.stageThreshold - track.stageWindow or distanceFromStart > track.stageThreshold + track.stageWindow
end

local function getVehiclePosition(playerId)
  local vehicles = MP.GetPlayerVehicles(playerId)
  if not vehicles then
    return nil, "no vehicles"
  end

  local vehicleId = nil
  for id, _ in pairs(vehicles) do
    vehicleId = tonumber(id)
    break
  end

  if vehicleId == nil then
    return nil, "no vehicle spawned"
  end

  local raw, err = MP.GetPositionRaw(playerId, vehicleId)
  if err ~= nil and err ~= "" then
    return nil, err
  end
  if not raw or not raw.pos then
    return nil, "no position packet"
  end

  return raw, nil
end

local function currentStageMetrics(playerId, racer)
  local clientMetrics = clientStageMetrics(racer)
  if clientMetrics then
    return clientMetrics
  end

  local pos, err = getVehiclePosition(playerId)
  local metrics = stagingMetrics(pos, racer.lane)
  if metrics then
    metrics.source = "server-fallback"
    return metrics
  end

  return nil, err
end

local function resetRace()
  if race.countdownTimer then
    cancelTimer("dragmpCountdownTick")
  end
  if race.raceTimer then
    cancelTimer("dragmpRaceTick")
  end
  if race.stagingTimer then
    cancelTimer("dragmpStagingTick")
  end

  race.state = STATE_IDLE
  race.racers = {}
  race.countdownTimer = nil
  race.raceTimer = nil
  race.stagingTimer = nil
  race.startedAt = nil
  race.winner = nil
  race.autoStartAnnounced = false
  race.sessionId = race.sessionId + 1

  sendClient(-1, CLIENT_EVENTS.RaceReset, { sessionId = race.sessionId })
end

local function racerCount()
  local count = 0
  for _, _ in pairs(race.racers) do
    count = count + 1
  end
  return count
end

local function activeLaneIds()
  local laneIds = {}
  for _, racer in pairs(race.racers) do
    table.insert(laneIds, racer.lane.id)
  end
  table.sort(laneIds)
  return laneIds
end

local function broadcastStatus(message)
  chat(-1, message)
  sendClient(-1, CLIENT_EVENTS.Notice, { message = message })
end

local function treeName()
  return race.treeMode == "pro" and "Pro tree" or "Sportsman tree"
end

local function assignLane(playerId)
  for _, lane in ipairs(track.lanes) do
    local used = false
    for _, racer in pairs(race.racers) do
      if racer.lane.id == lane.id then
        used = true
      end
    end
    if not used then
      return lane
    end
  end
  return nil
end

local function stagingSnapshot()
  local lanes = {}

  for playerId, racer in pairs(race.racers) do
    local metrics = currentStageMetrics(playerId, racer)
    local prestaged = metrics and metrics.prestaged or false
    local staged = metrics and metrics.staged or false

    racer.prestaged = prestaged
    racer.staged = staged
    if staged then
      if not racer.stagedSince then
        racer.stagedSince = MP.CreateTimer()
      end
    else
      racer.stagedSince = nil
      race.autoStartAnnounced = false
    end

    table.insert(lanes, {
      playerId = playerId,
      name = racer.name,
      laneId = racer.lane.id,
      prestaged = prestaged,
      staged = staged,
      stagedHold = racer.stagedSince and racer.stagedSince:GetCurrent() or 0,
      jumped = racer.jumped or false
    })
  end

  return { state = race.state, lanes = lanes }
end

local function broadcastStaging()
  local snapshot = stagingSnapshot()
  snapshot.sessionId = race.sessionId
  sendClient(-1, CLIENT_EVENTS.StageState, snapshot)
end

local function autoStartReady()
  if race.state ~= STATE_STAGING or racerCount() < 1 then
    return false
  end

  for _, racer in pairs(race.racers) do
    if not racer.staged or not racer.stagedSince then
      return false
    end
    if racer.stagedSince:GetCurrent() < track.autoStartHoldSeconds then
      return false
    end
  end

  return true
end

local function ensureStagingTimer()
  if race.stagingTimer then
    return
  end

  race.stagingTimer = true
  MP.CreateEventTimer("dragmpStagingTick", 250)
end

local beginCountdown

function dragmpStagingTick()
  if race.state ~= STATE_STAGING and race.state ~= STATE_COUNTDOWN then
    cancelTimer("dragmpStagingTick")
    race.stagingTimer = nil
    return
  end

  broadcastStaging()
  if autoStartReady() then
    beginCountdown()
  end
end

local function joinRace(playerId)
  if race.state == STATE_FINISHED then
    resetRace()
  end

  if race.state ~= STATE_IDLE and race.state ~= STATE_STAGING then
    chat(playerId, "A race is already active. Use /drag reset if it is stuck.")
    return
  end

  if race.racers[playerId] then
    chat(playerId, "You are already in lane " .. race.racers[playerId].lane.name .. ".")
    return
  end

  local lane = assignLane(playerId)
  if lane == nil then
    chat(playerId, "Both lanes are already occupied.")
    return
  end

  race.state = STATE_STAGING
  race.racers[playerId] = {
    id = playerId,
    name = getName(playerId),
    lane = lane,
    staged = false,
    prestaged = false,
    finished = false,
    jumped = false,
    launched = false,
    reactionTime = nil,
    splits = {},
    clientStage = nil,
    stagedSince = nil,
    finishTime = nil
  }

  ensureStagingTimer()
  sendClient(playerId, CLIENT_EVENTS.StageLane, { lane = lane, track = track, sessionId = race.sessionId })
  broadcastStaging()
  broadcastStatus(getName(playerId) .. " joined the " .. lane.name .. " lane.")
  if racerCount() < 2 then
    chat(-1, "Solo run ready. Stage for " .. string.format("%.1f", track.autoStartHoldSeconds) .. "s to auto-start, or wait for another racer.")
  else
    chat(-1, "Both lanes filled. Stage both lanes for " .. string.format("%.1f", track.autoStartHoldSeconds) .. "s to auto-start.")
  end
end

local function leaveRace(playerId)
  if race.racers[playerId] then
    local name = race.racers[playerId].name
    race.racers[playerId] = nil
    broadcastStatus(name .. " left the drag race.")
  end

  if racerCount() == 0 then
    resetRace()
  else
    broadcastStaging()
  end
end

local function allStaged()
  for playerId, racer in pairs(race.racers) do
    local metrics, err = currentStageMetrics(playerId, racer)
    if not metrics then
      racer.staged = false
      chat(playerId, "Cannot read staging position yet: " .. tostring(err))
      return false
    end

    racer.staged = metrics.staged
    if not racer.staged then
      chat(playerId, "Stage closer to the " .. racer.lane.name .. " lane line.")
      return false
    end
  end

  return true
end

beginCountdown = function(treeMode)
  if race.state ~= STATE_STAGING then
    return
  end

  if racerCount() < 1 then
    chat(-1, "No racers queued.")
    return
  end

  if not allStaged() then
    chat(-1, "Race start blocked until all racers are staged.")
    return
  end

  race.state = STATE_COUNTDOWN
  if treeMode == "pro" or treeMode == "sportsman" then
    race.treeMode = treeMode
  end
  race.countdownIntervalMs = race.treeMode == "pro" and 400 or 500
  race.countdownTimer = true
  broadcastStaging()
  sendClient(-1, CLIENT_EVENTS.TreeReset, {})

  if race.treeMode == "pro" then
    race.countdownValue = 0
    sendClient(-1, CLIENT_EVENTS.Countdown, { value = 0, treeMode = race.treeMode, laneIds = activeLaneIds() })
  else
    race.countdownValue = 2
    sendClient(-1, CLIENT_EVENTS.Countdown, { value = 3, treeMode = race.treeMode, laneIds = activeLaneIds() })
  end

  MP.CreateEventTimer("dragmpCountdownTick", race.countdownIntervalMs)
end

local function jumpStartRacer(racer)
  if not racer or racer.jumped then
    return
  end

  racer.jumped = true
  racer.finished = true
  racer.finishTime = 9999
  sendClient(-1, CLIENT_EVENTS.JumpStart, { laneId = racer.lane.id, name = racer.name })
  broadcastStatus(racer.name .. " jumped before green.")
  broadcastStaging()
end

local function disqualifyRacer(racer, reason)
  if not racer or racer.finished then
    return
  end

  racer.disqualified = true
  racer.disqualificationReason = reason or "DQ"
  racer.finished = true
  racer.finishTime = 9999
  racer.finishMph = 0
  sendClient(-1, CLIENT_EVENTS.LaneResult, {
    laneId = racer.lane.id,
    name = racer.name,
    time = racer.finishTime,
    mph = racer.finishMph,
    jumped = racer.jumped or false,
    disqualified = true,
    reason = racer.disqualificationReason
  })
  broadcastStatus(racer.name .. " DQ: " .. racer.disqualificationReason)
end

function dragmpCountdownTick()
  if race.state ~= STATE_COUNTDOWN then
    cancelTimer("dragmpCountdownTick")
    race.countdownTimer = nil
    return
  end

  for playerId, racer in pairs(race.racers) do
    local pos = getVehiclePosition(playerId)
    local clientMetrics = clientStageMetrics(racer)
    if (clientMetrics and clientMetrics.jumped) or speed(pos) > track.jumpStartSpeed then
      jumpStartRacer(racer)
    end
  end

  if race.countdownValue > 0 then
    sendClient(-1, CLIENT_EVENTS.Countdown, { value = race.countdownValue, treeMode = race.treeMode, laneIds = activeLaneIds() })
    race.countdownValue = race.countdownValue - 1
    return
  end

  cancelTimer("dragmpCountdownTick")
  race.countdownTimer = nil
  race.state = STATE_RACING
  race.startedAt = MP.CreateTimer()
  race.raceTimer = true
  local jumpedLanes = {}
  for _, racer in pairs(race.racers) do
    if racer.jumped then
      table.insert(jumpedLanes, racer.lane.id)
    end
  end
  sendClient(-1, CLIENT_EVENTS.Green, { jumpedLanes = jumpedLanes, laneIds = activeLaneIds() })
  MP.CreateEventTimer("dragmpRaceTick", 25)
end

local function launchRacer(racer, reactionTime)
  racer.launched = true
  racer.reactionTime = reactionTime
  sendClient(-1, CLIENT_EVENTS.ReactionTime, {
    playerId = racer.id,
    laneId = racer.lane.id,
    name = racer.name,
    reactionTime = reactionTime
  })
end

local function raceDistance(pos, lane)
  local metrics = stagingMetrics(pos, lane)
  if not metrics then
    return nil
  end
  return metrics.frontAxleAlong
end

local function recordSplit(racer, split, elapsed, splitMph)
  if racer.splits[split.key] then
    return
  end

  racer.splits[split.key] = {
    time = elapsed,
    mph = splitMph,
    etWithoutRt = racer.reactionTime and math.max(0, elapsed - racer.reactionTime) or nil
  }

  sendClient(-1, CLIENT_EVENTS.SplitTime, {
    laneId = racer.lane.id,
    name = racer.name,
    key = split.key,
    label = split.label,
    time = elapsed,
    etWithoutRt = racer.splits[split.key].etWithoutRt,
    mph = splitMph
  })
end

local function checkSplits(racer, pos, elapsed)
  local distanceTravelled = raceDistance(pos, racer.lane)
  if not distanceTravelled then
    return
  end

  local availableLength = selectedRaceDistance().meters
  for _, split in ipairs(SPLITS) do
    if split.meters <= availableLength and distanceTravelled >= split.meters then
      recordSplit(racer, split, elapsed, mph(pos))
    end
  end
end

local function buildRunSummary(racer)
  local trackKey, trackLabel, length = trackType(racer.lane)
  local summary = {}
  local availableLength = selectedRaceDistance().meters

  for _, split in ipairs(SPLITS) do
    local recorded = racer.splits[split.key]
    table.insert(summary, {
      key = split.key,
      label = split.label,
      meters = split.meters,
      available = split.meters <= availableLength,
      time = recorded and recorded.time or nil,
      etWithoutRt = recorded and recorded.etWithoutRt or nil,
      mph = recorded and recorded.mph or nil
    })
  end

  return {
    laneId = racer.lane.id,
    laneName = racer.lane.name .. " Lane",
    name = racer.name,
    trackKey = trackKey,
    trackLabel = trackLabel,
    trackLengthMeters = length,
    finishTime = racer.finishTime,
    jumped = racer.jumped or false,
    disqualified = racer.disqualified or false,
    disqualificationReason = racer.disqualificationReason,
    treeMode = race.treeMode,
    treeName = race.treeMode == "pro" and "Pro Tree" or "Sportsman Tree",
    reactionTime = racer.reactionTime,
    splits = summary
  }
end

local function raceSummaries()
  local summaries = {}
  for _, racer in pairs(race.racers) do
    table.insert(summaries, buildRunSummary(racer))
  end
  table.sort(summaries, function(a, b)
    return (a.laneId or 0) < (b.laneId or 0)
  end)
  return summaries
end

local function sendRaceFinishedToRacers()
  local payload = {
    runId = string.format("dragmp-%s-%d", os.date("!%Y%m%dT%H%M%SZ"), race.sessionId or 0),
    createdAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    sessionId = race.sessionId,
    state = race.state,
    racerCount = racerCount(),
    winner = race.winner and race.winner.name or nil,
    summaries = raceSummaries()
  }

  print(string.format("DragMP sending final timeslip to %d racer(s) with %d summaries", racerCount(), #payload.summaries))
  local finishedPayload = {
    runId = payload.runId,
    createdAt = payload.createdAt,
    sessionId = payload.sessionId,
    state = payload.state,
    racerCount = payload.racerCount,
    winner = payload.winner
  }
  for playerId, _ in pairs(race.racers) do
    sendClient(playerId, CLIENT_EVENTS.RaceFinished, finishedPayload)
    sendClient(playerId, CLIENT_EVENTS.RunSummary, payload)
  end
end

local function finishRacer(racer, elapsed, finishMph)
  racer.finished = true
  racer.finishTime = elapsed
  racer.finishMph = finishMph

  if not racer.jumped and not racer.disqualified and (not race.winner or elapsed < race.winner.finishTime) then
    race.winner = racer
  end

  local trackKey = selectedRaceDistance().key
  for _, split in ipairs(SPLITS) do
    if split.key == trackKey then
      recordSplit(racer, split, elapsed, finishMph)
      break
    end
  end

  sendClient(-1, CLIENT_EVENTS.LaneResult, {
    laneId = racer.lane.id,
    name = racer.name,
    time = elapsed,
    mph = finishMph,
    jumped = racer.jumped or false,
    disqualified = racer.disqualified or false,
    reason = racer.disqualificationReason
  })
  broadcastStatus(string.format("%s finished in %.3fs at %.2f MPH.", racer.name, elapsed, finishMph))
end

local function finishRaceIfDone()
  for _, racer in pairs(race.racers) do
    if not racer.finished then
      return false
    end
  end

  race.state = STATE_FINISHED
  cancelTimer("dragmpRaceTick")
  race.raceTimer = nil

  if race.winner and not race.winner.jumped then
    broadcastStatus("Winner: " .. race.winner.name .. " (" .. string.format("%.3fs", race.winner.finishTime) .. ", " .. string.format("%.2f MPH", race.winner.finishMph or 0) .. ")")
    sendClient(-1, CLIENT_EVENTS.Winner, { laneId = race.winner.lane.id, name = race.winner.name })
  else
    broadcastStatus("Race complete. No clean winner.")
    sendClient(-1, CLIENT_EVENTS.Winner, { laneId = nil })
  end

  sendRaceFinishedToRacers()
  return true
end

function dragmpRaceTick()
  if race.state ~= STATE_RACING then
    cancelTimer("dragmpRaceTick")
    race.raceTimer = nil
    return
  end

  local elapsed = race.startedAt:GetCurrent()
  for playerId, racer in pairs(race.racers) do
    if not racer.finished then
      local pos, err = getVehiclePosition(playerId)
      if pos then
        local x, y, z = table.unpack(pos.pos)
        local along, lateral = laneProgress({ x = x, y = y, z = z }, racer.lane)
        if along and along > 5 and lateral and lateral > track.raceLateralTolerance then
          disqualifyRacer(racer, "crossed out of lane")
        end

        if not racer.finished then
          if not racer.launched then
            local metrics = clientStageMetrics(racer) or stagingMetrics(pos, racer.lane)
            local leftStage = metrics and leftStageBeam(metrics.distanceFromStart)
            local moving = speed(pos) > track.jumpStartSpeed
            if leftStage or moving then
              launchRacer(racer, elapsed)
            end
          end

          checkSplits(racer, pos, elapsed)

          local distanceTravelled = raceDistance(pos, racer.lane)
          if distanceTravelled and distanceTravelled >= selectedRaceDistance().meters then
            if not racer.launched then
              launchRacer(racer, elapsed)
            end
            finishRacer(racer, elapsed, mph(pos))
          end
        end
      else
        print("DragMP position read failed for", playerId, err)
      end
    end
  end

  if elapsed >= track.raceTimeoutSeconds then
    for _, racer in pairs(race.racers) do
      if not racer.finished then
        racer.finished = true
        racer.finishTime = 9999
        broadcastStatus(racer.name .. " timed out.")
      end
    end
  end

  finishRaceIfDone()
end

local function status(playerId)
  local lines = {
    "Track: " .. track.name,
    "Distance: " .. selectedRaceDistance().label,
    "State: " .. race.state,
    "Tree: " .. treeName(),
    "Auto start: " .. string.format("%.1fs staged", track.autoStartHoldSeconds)
  }
  for _, racer in pairs(race.racers) do
    table.insert(lines, racer.name .. " - " .. racer.lane.name .. " lane")
  end
  chat(playerId, table.concat(lines, " | "))
end

local function setTreeMode(playerId, mode)
  if race.state == STATE_COUNTDOWN or race.state == STATE_RACING then
    chat(playerId, "Cannot change tree while a race is running.")
    return
  end

  race.treeMode = mode == "pro" and "pro" or "sportsman"
  broadcastStatus("Selected " .. treeName() .. ".")
end

local function setRaceDistance(playerId, mode)
  if race.state == STATE_COUNTDOWN or race.state == STATE_RACING then
    chat(playerId, "Cannot change race distance while a race is running.")
    return
  end

  track.raceDistanceMode = mode == "1/8" and "1/8" or "1/4"
  broadcastStatus("Selected " .. selectedRaceDistance().label .. " race distance.")
end

local function stageStatus(playerId)
  local racer = race.racers[playerId]
  if not racer then
    chat(playerId, "Use /drag join first.")
    return
  end

  local metrics, err = currentStageMetrics(playerId, racer)
  if not metrics then
    chat(playerId, "Cannot read staging position: " .. tostring(err))
    return
  end

  chat(playerId, string.format(
    "Stock stage distance %.2fm, speed %.2fm/s, pre=%s, stage=%s, source=%s. Target: pre %.3f..%.3fm, stage %.3f..%.3fm, deep %.3f..%.3fm.",
    metrics.distanceFromStart,
    metrics.speed,
    tostring(metrics.prestaged),
    tostring(metrics.staged),
    metrics.source or "unknown",
    track.preStageThreshold - track.stageWindow,
    track.preStageThreshold + track.stageWindow,
    track.stageThreshold - track.stageWindow,
    track.stageThreshold + track.stageWindow,
    track.preStageThreshold + track.stageWindow,
    track.stageThreshold + track.stageWindow
  ))
  if metrics.lateral then
    chat(playerId, string.format(
      "Client axle debug: lateral %.2fm, inLane=%s, telemetry age %s.",
      metrics.lateral,
      tostring(metrics.inLane),
      racer.clientStageTimer and string.format("%.2fs", racer.clientStageTimer:GetCurrent()) or "N/A"
    ))
  end
  if metrics.source == "server-fallback" then
    chat(playerId, string.format(
      "Fallback debug: center %.2fm, lateral %.2fm, front axle %.2fm, front axle offset %.2fm.",
      metrics.along,
      metrics.lateral,
      metrics.frontAxleAlong,
      track.frontAxleOffset
    ))
  end
end

local function help(playerId)
  MP.SendChatMessage(playerId, "[DragMP] Commands:")
  MP.SendChatMessage(playerId, "[DragMP] /drag join - join the next open lane.")
  MP.SendChatMessage(playerId, "[DragMP] /dj - quick join the next open lane.")
  MP.SendChatMessage(playerId, "[DragMP] /drag leave - leave the current race.")
  MP.SendChatMessage(playerId, "[DragMP] /drag 1/8 - run to the 1/8 mile.")
  MP.SendChatMessage(playerId, "[DragMP] /drag 1/4 - run to the 1/4 mile.")
  MP.SendChatMessage(playerId, "[DragMP] /drag pro - select pro tree auto-start.")
  MP.SendChatMessage(playerId, "[DragMP] /drag sport - select sportsman tree auto-start.")
  MP.SendChatMessage(playerId, "[DragMP] /drag start [pro|sport] - manually start the tree.")
  MP.SendChatMessage(playerId, "[DragMP] /drag status - show race state and racers.")
  MP.SendChatMessage(playerId, "[DragMP] /drag stage - show staging debug for your lane.")
  MP.SendChatMessage(playerId, "[DragMP] /drag reset - reset the race.")
  MP.SendChatMessage(playerId, "[DragMP] /drag test - turn on DragMP tree, board, and winner lights.")
  MP.SendChatMessage(playerId, "[DragMP] /drag lights auto|on|off|reload - control added drag strip lighting.")
end

function dragmpChat(playerId, playerName, message)

  message = tostring(message or ""):match("^%s*(.-)%s*$")
  if message == "/dj" then
    joinRace(playerId)
    return 1
  end

  if message == nil or message:sub(1, 5) ~= "/drag" then
    return 0
  end

  local cmd = message:match("^/drag%s+(%S+)") or "help"
  cmd = string.lower(cmd)
  local arg = message:match("^/drag%s+%S+%s+(%S+)")
  arg = arg and string.lower(arg) or nil

  if cmd == "join" then
    joinRace(playerId)
  elseif cmd == "leave" then
    leaveRace(playerId)
  elseif cmd == "1/8" or cmd == "eighth" or cmd == "8th" then
    setRaceDistance(playerId, "1/8")
  elseif cmd == "1/4" or cmd == "quarter" or cmd == "quartermile" then
    setRaceDistance(playerId, "1/4")
  elseif cmd == "pro" then
    setTreeMode(playerId, "pro")
  elseif cmd == "sport" or cmd == "sportsman" then
    setTreeMode(playerId, "sportsman")
  elseif cmd == "start" then
    if arg == "pro" or arg == "sport" or arg == "sportsman" then
      beginCountdown(arg == "pro" and "pro" or "sportsman")
    else
      beginCountdown()
    end
  elseif cmd == "reset" then
    resetRace()
    broadcastStatus("Race reset.")
  elseif cmd == "status" then
    status(playerId)
  elseif cmd == "stage" then
    stageStatus(playerId)
  elseif cmd == "test" then
    local laneId = tonumber(arg or "")
    if laneId ~= 1 and laneId ~= 2 then
      laneId = nil
    end
    sendClient(-1, CLIENT_EVENTS.TestLights, { laneId = laneId })
    chat(playerId, laneId and ("DragMP race lights test sent for lane " .. tostring(laneId) .. ".") or "DragMP race lights test sent.")
  elseif cmd == "lights" then
    local mode = (arg == "on" or arg == "off" or arg == "reload") and arg or "auto"
    local previousMode = dragLightingMode
    if mode == "on" or mode == "off" or mode == "auto" then
      dragLightingMode = mode
    end
    sendClient(-1, CLIENT_EVENTS.Lighting, { mode = mode, previousMode = previousMode, activeMode = dragLightingMode })
    chat(playerId, "Lighting mode synced: " .. dragLightingMode .. (mode == "reload" and " (reloaded)." or "."))
  else
    help(playerId)
  end

  return 1
end

function dragmpDisconnect(playerId)
  leaveRace(playerId)
end

function dragmpPlayerJoin(playerId)
  if playerId ~= nil then
    help(playerId)
    sendClient(playerId, CLIENT_EVENTS.Lighting, { mode = dragLightingMode, activeMode = dragLightingMode })
  end
end

function dragmpStageTelemetry(playerId, ...)
  local data = nil
  for _, value in ipairs({ ... }) do
    if type(value) == "string" and value:find("|", 1, true) then
      data = value
    end
  end

  local racer = race.racers[playerId]
  if not racer or type(data) ~= "string" then
    return
  end

  local parts = {}
  for part in string.gmatch(data, "([^|]+)") do
    table.insert(parts, part)
  end

  local laneId = parts[1]
  local prestaged = parts[2]
  local staged = parts[3]
  local distanceFromStart = parts[4]
  local vehicleSpeed = parts[5]
  local jumped = parts[6]
  local lateral = tonumber(parts[7] or "")
  local inLane = parts[8] == nil or parts[8] == "1"

  if not laneId or tonumber(laneId) ~= racer.lane.id then
    return
  end

  local numericDistance = tonumber(distanceFromStart) or 9999
  local numericSpeed = tonumber(vehicleSpeed) or 0
  local laneOk = inLane and lateral ~= nil and lateral <= track.clientStageLateralTolerance and math.abs(numericDistance) <= 20
  local serverPrestaged, serverStaged = stockStagingFromDistance(numericDistance, laneOk)

  racer.clientStage = {
    prestaged = prestaged == "1" and serverPrestaged,
    staged = staged == "1" and serverStaged,
    distanceFromStart = numericDistance,
    speed = numericSpeed,
    jumped = jumped == "1",
    lateral = lateral,
    inLane = laneOk
  }
  racer.clientStageTimer = MP.CreateTimer()
  racer.prestaged = racer.clientStage.prestaged
  racer.staged = racer.clientStage.staged

  if race.state == STATE_COUNTDOWN and racer.clientStage.jumped then
    jumpStartRacer(racer)
  end
end

function onInit()
  MP.RegisterEvent("onChatMessage", "dragmpChat")
  MP.RegisterEvent("onPlayerJoin", "dragmpPlayerJoin")
  MP.RegisterEvent("onPlayerDisconnect", "dragmpDisconnect")
  MP.RegisterEvent("DragMPStageTelemetry", "dragmpStageTelemetry")
  MP.RegisterEvent("dragmpStagingTick", "dragmpStagingTick")
  MP.RegisterEvent("dragmpCountdownTick", "dragmpCountdownTick")
  MP.RegisterEvent("dragmpRaceTick", "dragmpRaceTick")
  print(PLUGIN .. " loaded for " .. track.name)
end

