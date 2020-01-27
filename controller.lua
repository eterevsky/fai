-- Controller contains a useful subset of Factorio API through which the AI
-- controls the game.

local box = require "box"
local log = require("util").log
local pos = require "pos"

local _listeners = {}
local _player

local function start(player) _player = player end

-- Stop any running action
local function stop() remove_all_listeners() end

-- Get current position
local function position()
  local point = _player.position
  assert(point ~= nil)
  return point
end

-- Get player character entity
local function character() return _player.character end

-- Returns all entities in the box with the side 2*radius.
local function entities(radius)
  if radius == nil then radius = 1000 end
  local bounding_box = box.pad(position(), radius)
  return _player.surface.find_entities(bounding_box)
end

-- Returns a dictionary name -> LuaRecipe of all available recipes.
local function recipes() return _player.force.recipes end

local function entities_in_box(bounding_box)
  local bounding_box = box.norm(bounding_box)
  return _player.surface.find_entities(bounding_box)
end

local function entities_filtered(filters)
  return _player.surface.find_entities_filtered(filters)
end

local function is_minable(entity)
  return entity.minable and
         _player.can_reach_entity(entity) and
         entity.name ~= "player"
end

local function mine_entity(entity)
  local selection_point = box.selection_diff(
      entity.selection_box, _player.character.selection_box)
  _player.update_selected_entity(selection_point)
  _player.mining_state = {mining = true, position = selection_point}
end

-- Mine nearby entities
-- TODO: Move to AI
local function mine()
  local reach_distance = _player.resource_reach_distance + 0.3
  local player_box = box.padding(position(), reach_distance)
  local ore_entity, ore_point

  for _, e in ipairs(_player.surface.find_entities(player_box)) do
    if is_minable(e) then ore_entity = e end
  end

  if ore_entity == nil then
    game.print("Didn't find any reachable ore entity")
    return
  end

  log("Found ore entity:", ore_entity.name, ore_entity.position)
  mine_entity(ore_entity)
end

local function get_inventory(type)
  if type == nil then
    return _player.character.get_main_inventory()
  else
    return _player.character.get_inventory(type)
  end
end

local function craft(recipe)
  _player.begin_crafting {count = 1, recipe = recipe}
end

-- TODO: Hide?
local function crafting_queue() return _player.character.crafting_queue end

-- Walk one step in given direction
local function walk(dir)
  _player.walking_state = {walking = true, direction = dir}
end

local function get_tile(point)
  return _player.surface.get_tile(pos.unpack(point))
end

local function add_listener(callback) table.insert(_listeners, callback) end

local function remove_all_listeners() _listeners = {} end

local function remove_listener(callback)
  for i, e in ipairs(_listeners) do
    if e == callback then
      table.remove(_listeners, i)
      break
    end
  end
end

local function tick() return game.tick end

local function on_tick()
  for _, listener in ipairs(_listeners) do listener() end
end

return {
  position = position,
  character = character,
  entities = entities,
  recipes = recipes,
  entities_in_box = entities_in_box,
  entities_filtered = entities_filtered,
  start = start,
  stop = stop,
  is_minable = is_minable,
  mine_entity = mine_entity,
  mine = mine,
  get_inventory = get_inventory,
  craft = craft,
  crafting_queue = crafting_queue,
  walk = walk,
  get_tile = get_tile,
  add_listener = add_listener,
  remove_all_listeners = remove_all_listeners,
  remove_listener = remove_listener,
  tick = tick,
  on_tick = on_tick,
}