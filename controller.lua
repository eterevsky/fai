-- Controller contains a useful subset of Factorio API through which the AI
-- controls the game.
local box = require "box"
local log = require("util").log
local pos = require "pos"
local walking = require "walking"

local _listeners = {}
local _player
local _listening = false
local _walk_simulator

local controller = {}

controller.directions_by_name = defines.direction
controller.directions = {}

for _, dir in pairs(defines.direction) do
  table.insert(controller.directions, dir)
end

function controller.activate()
  if game.player == nil then
    game.print(
        "controller.activate() should only be called from a command handler")
    return
  end
  log("Activating controller for player", game.player.name)
  _player = game.player
  if not _listening then
    log("Controller now listens on every tick")
    script.on_nth_tick(1, controller.on_tick)
    _listening = true
  end
  if _walk_simulator == nil then
    _walk_simulator = walking.WalkSimulator.new(controller)
  end
end

-- Stop any running action
function controller.stop()
  controller.remove_all_listeners()
  -- log('Controller stops listening')
  -- script.on_nth_tick(1, nil)
  -- _listening = false
end

-- Get current position
function controller.position()
  local point = _player.position
  assert(point ~= nil)
  return point
end

-- Get player character entity
function controller.character() return _player.character end

-- Returns all entities in the box with the side 2*radius.
function controller.entities(radius)
  if radius == nil then radius = 1000 end
  local bounding_box = box.pad(controller.position(), radius)
  log("bounding box:", box.norm(bounding_box))
  return _player.surface.find_entities(bounding_box)
end

-- Returns a dictionary name -> LuaRecipe of all available recipes.
function controller.recipes() return _player.force.recipes end

function controller.entities_in_box(bounding_box)
  local norm_box = box.norm(bounding_box)
  return _player.surface.find_entities(norm_box)
end

function controller.entities_filtered(filters)
  return _player.surface.find_entities_filtered(filters)
end

function controller.is_minable(entity)
  return entity.minable and _player.can_reach_entity(entity) and entity.name ~=
             "player"
end

function controller.mine_entity(entity)
  local selection_point = box.selection_diff(entity.selection_box,
                                             _player.character.selection_box)
  _player.update_selected_entity(selection_point)
  _player.mining_state = {mining = true, position = selection_point}
end

function controller.get_inventory(type)
  if type == nil then
    return _player.character.get_main_inventory()
  else
    return _player.character.get_inventory(type)
  end
end

function controller.craft(recipe)
  _player.begin_crafting {count = 1, recipe = recipe}
end

-- Walk one step in given direction
function controller.walk(dir)
  _player.walking_state = {walking = true, direction = dir}
  _walk_simulator:register_prediction(dir)
end

function controller.get_tile(point)
  return _player.surface.get_tile(pos.unpack(point))
end

function controller.add_listener(callback)
  table.insert(_listeners, callback)
end

function controller.remove_all_listeners() _listeners = {} end

function controller.remove_listener(callback)
  for i, e in ipairs(_listeners) do
    if e == callback then
      table.remove(_listeners, i)
      break
    end
  end
end

function controller.tick() return game.tick end

function controller.on_tick()
  if not _walk_simulator:check_prediction() then
    return controller.stop()
  end
  for _, listener in ipairs(_listeners) do listener() end
end

return controller
