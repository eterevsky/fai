-- AI makes the decisions what to do and controls the character through
-- the controller object.

local box = require "box"
local log = require("util").log
local Pathfinder = require("pathfinder").Pathfinder
local pos = require "pos"
local walking = require "walking"

local _controller, _pathfinder, _walk_simulator
local _previous_action

local ai = {}

function ai.start(controller)
  log("Starting AI")
  _controller = controller
  _pathfinder = Pathfinder.new(controller)
  _walk_simulator = walking.WalkSimulator.new(controller)
  _controller.add_listener(ai.update)
end

function ai.stop()
  _controller.remove_listener(ai.update)
  _walk_simulator:clear()
end

local function _try_to_mine()
  local player_box = box.pad(_controller.position(), 3)
  local coal_entities = _controller.entities_filtered{
    area = player_box,
    name = "coal"
  }
  local ore_entity = nil
  for _, e in ipairs(coal_entities) do
    if _controller.is_minable(e) then
      ore_entity = e
      break
    end
  end

  if ore_entity ~= nil then
    _controller.mine_entity(ore_entity)

    if _previous_action ~= "mine" then
      log("Reached ore entity", ore_entity.name, pos.norm(ore_entity.position))
      log("L2 distance to entity:",
          pos.dist_l2(_controller.position(), ore_entity.position))
      _previous_action = "mine"
    end
    return true
  end

  return false
end

function ai.update()
  if _previous_action == "walk" then
    if not _walk_simulator:check_prediction() then return ai.stop() end
  end

  if _try_to_mine() then return end

  if not _pathfinder:has_goals() then
    local coal_entities = _controller.entities_filtered{name = "coal"}
    log("Found", #coal_entities, "coal entities")
    local goals = {}
    for _, e in ipairs(coal_entities) do
      table.insert(goals, pos.pack(e.position))
    end
    _pathfinder:set_goals(goals, 2.8)
  end

  local dir = _pathfinder:next_step()
  log("step dir", dir)

  if dir ~= nil then
    _controller.walk(dir)
    _walk_simulator:register_prediction(dir)
    _previous_action = "walk"
    return
  end

  _previous_action = nil
end

return ai