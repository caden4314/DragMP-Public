-- Scenic Route DragMP stock drag-strip discovery.
-- Reads BeamNG's own *.strip.json descriptors, including files mounted from level ZIPs.
local M = {}

local SOURCE = "DragMP.TrackResolver"
local lastSignature = nil

local function position(transform)
  local p = transform and transform.position
  if not p then return nil end
  return { x = tonumber(p.x), y = tonumber(p.y), z = tonumber(p.z) }
end

local function rotation(transform)
  local q = transform and transform.rotation
  if not q then return nil end
  return { x = tonumber(q.x) or 0, y = tonumber(q.y) or 0, z = tonumber(q.z) or 0, w = tonumber(q.w) or 1 }
end

local function waypoint(lane, wanted)
  for _, point in ipairs(lane.waypoints or {}) do
    if point.type == wanted then return point end
  end
  return nil
end

local function levelKey()
  local key = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or nil
  if key and key ~= "" then return tostring(key):gsub("^/levels/", ""):gsub("/.*$", "") end
  local mission = getMissionFilename and getMissionFilename() or ""
  return tostring(mission):match("/levels/([^/]+)/")
end

local function descriptor(path, level)
  local data = jsonReadFile and jsonReadFile(path) or nil
  if type(data) ~= "table" or type(data.lanes) ~= "table" or #data.lanes < 2 then return nil end
  local lanes = {}
  for _, sourceLane in ipairs(data.lanes) do
    local spawn = waypoint(sourceLane, "spawn")
    local stage = waypoint(sourceLane, "stage")
    local finish = waypoint(sourceLane, "endLine")
    if spawn and stage and finish then
      lanes[#lanes + 1] = {
        id = tonumber(sourceLane.laneOrder) or #lanes + 1,
        name = tostring(sourceLane.shortName or sourceLane.name or ("Lane " .. (#lanes + 1))),
        spawn = position(spawn.transform),
        stage = position(stage.transform),
        finish = position(finish.transform),
        rot = rotation(spawn.transform),
        width = tonumber(sourceLane.boundary and sourceLane.boundary.transform and sourceLane.boundary.transform.scale and sourceLane.boundary.transform.scale.x)
      }
    end
  end
  if #lanes ~= 2 then return nil end
  table.sort(lanes, function(a, b) return a.id < b.id end)
  return {
    protocol = 1,
    levelKey = level,
    name = tostring(data.description or data.id or "Discovered Drag Strip"),
    stripId = tostring(data.id or path),
    sourcePath = path,
    lanes = lanes
  }
end

local function discover()
  local level = levelKey()
  if not level or not FS or not FS.findFiles then return end
  local files = FS:findFiles("/levels/" .. level .. "/dragstrips/", "*.strip.json", -1, true, false) or {}
  table.sort(files)
  for _, path in ipairs(files) do
    local candidate = descriptor(path, level)
    if candidate and jsonEncode and TriggerServerEvent then
      local payload = jsonEncode(candidate)
      local signature = candidate.levelKey .. ":" .. candidate.stripId .. ":" .. tostring(#payload)
      if signature ~= lastSignature then
        lastSignature = signature
        TriggerServerEvent("DragMPTrackCandidate", payload)
        log("I", SOURCE, "Submitted stock strip " .. candidate.stripId .. " for " .. level)
      end
      return
    end
  end
  log("W", SOURCE, "No stock *.strip.json descriptor found for " .. tostring(level))
end

local function delayedDiscover()
  if core_jobsystem and core_jobsystem.create then
    core_jobsystem.create(function(job)
      job.sleep(1.5)
      discover()
    end, 1)
  else
    discover()
  end
end

M.onExtensionLoaded = delayedDiscover
M.onClientStartMission = delayedDiscover
M.discover = discover
return M
