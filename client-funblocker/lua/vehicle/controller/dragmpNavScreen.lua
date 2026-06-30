local M = {}
M.type = "auxiliary"

local htmlTexture = require("htmlTexture")

local screenMaterialName = "@dragmp_nav_screen"
local htmlFilePath = "local://local/vehicles/common/dragmp_nav/dragmp_nav_screen.html"
local textureWidth = 512
local textureHeight = 256
local textureFPS = 20
local lastData = {
  status = "WAITING",
  reactionTime = nil,
  elapsedTime = nil,
  quarterTime = nil,
  quarterMph = nil,
  won = false,
  racing = false
}

local function pushData()
  htmlTexture.call(screenMaterialName, "updateDragMP", lastData)
end

local function setDragMPData(data)
  if type(data) ~= "table" then
    return
  end

  if data.reset == true then
    lastData = {
      status = data.status or "WAITING",
      reactionTime = data.reactionTime,
      elapsedTime = data.elapsedTime,
      quarterTime = data.quarterTime,
      quarterMph = data.quarterMph,
      won = data.won == true,
      racing = data.racing == true
    }
    pushData()
    return
  end

  for key, value in pairs(data) do
    lastData[key] = value
  end
  pushData()
end

local function setDragMPJson(data)
  if type(data) ~= "string" then
    return
  end

  local ok, decoded = pcall(jsonDecode, data)
  if ok and type(decoded) == "table" then
    setDragMPData(decoded)
  end
end

local function init(jbeamData)
  screenMaterialName = jbeamData.screenMaterialName or screenMaterialName
  htmlFilePath = jbeamData.htmlFilePath or htmlFilePath
  textureWidth = jbeamData.textureWidth or textureWidth
  textureHeight = jbeamData.textureHeight or textureHeight
  textureFPS = jbeamData.textureFPS or textureFPS

  htmlTexture.create(screenMaterialName, htmlFilePath, textureWidth, textureHeight, textureFPS, "automatic")
  pushData()
end

M.init = init
M.reset = nop
M.setDragMPData = setDragMPData
M.setDragMPJson = setDragMPJson

return M
