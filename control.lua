-- This is the top-level script defining commands, available from Factorio
-- console. It initializes controller and ai modules.

local ai = require "ai"
local controller = require "controller"
local pos = require "pos"
local util = require "util"
local log = util.log
local Pathfinder = require("pathfinder").Pathfinder
local PointSet = require("pointset").PointSet
require "polygon"
local tests = require "tests"
local tile_pathfinder = require "tile_pathfinder"

-- Commands

commands.add_command("start", "Give AI control over the player",
function()
  log(_VERSION)

  controller.activate()
  ai.start(controller)
end)

commands.add_command("stop", "Stops AI and Controller",
function()
  ai.stop()
  controller.stop()
end)

commands.add_command("pos", "Show current player position",
function()
  controller.activate()
  local point = controller.position()
  log("position:", pos.norm(point))
  log("resource_reach_distance:", game.player.resource_reach_distance)
end)

commands.add_command("entities", "Show entities around",
function()
  controller.activate()
  local entities = controller.entities(5)
  log("Entities in the 10x10 box:")
  for _, e in ipairs(entities) do
    log(e.name, " position: ", e.position, " bounding: ", e.bounding_box,
        " collision: ", e.prototype.collision_box, " orientation: ",
        e.orientation)
  end
end)

commands.add_command("all_entities", "Show statistics over all known entities",
function()
  controller.activate()
  local count = 0
  local type_count = {}
  local p1, p2 = {x = 0, y = 0}, {x = 0, y = 0}
  for _, entity in ipairs(controller.entities()) do
    count = count + 1
    local type_name = entity.name .. " " .. entity.type
    type_count[type_name] = (type_count[type_name] or 0) + 1

    p1.x = math.min(p1.x, entity.position.x)
    p1.y = math.min(p1.y, entity.position.y)
    p2.x = math.max(p2.x, entity.position.x)
    p2.y = math.max(p2.y, entity.position.y)
  end

  log(serpent.block(type_count))
  log("Found", count, "entities")
  log("Bounding box:", p1, p2)
end)

commands.add_command("recipes", "Show all enabled recipes",
function()
  controller.activate()
  for name, recipe in pairs(controller.recipes()) do
    if recipe.enabled and not recipe.hidden then
      log(recipe.name, recipe.category)
    end
  end
end)

commands.add_command("recipe", "Show details about a recipe",
function(args)
  controller.activate()
  local name = args.parameter
  local recipe = controller.recipes()[name]
  log("name:", name, "enabled:", recipe.enabled, "category:", recipe.category,
      "hidden:", recipe.hidden, "energy:", recipe.energy, "order:",
      recipe.order, "group:", recipe.group.name)
  log("Ingredients:", recipe.ingredients)
  log("Products:", recipe.products)
end)

commands.add_command("inventory", "Show the character's inventory",
function()
  controller.activate()
  local inventory = controller.character().get_inventory(
                        defines.inventory.character_main)
  if inventory == nil then log("Unknown inventory") end
  log("Inventory type:", type, "slots:", #inventory)
  log("Contents:", inventory.get_contents())
  log("has_items_inside:", controller.character().has_items_inside())
end)

commands.add_command("walk", "Walk in the given direction (north, northwest, ...)",
function(args)
  controller.activate()
  local dir = controller.directions_by_name[args.parameter]
  log("Walking in direction:", dir)

  local function walk()
    controller.walk(dir)
  end

  controller.add_listener(walk)
end)

commands.add_command("random-walk", "Walk in a random direction on each tick",
function(args)
  controller.activate()
 
  local function walk()
    local dir = controller.directions[math.random(#controller.directions)]
    controller.walk(dir)
  end

  controller.add_listener(walk)
end)

commands.add_command("test", "Run unit tests", function() tests.run_tests() end)

commands.add_command("env", "Show all variable in global environment",
function()
  local list = {}
  for n in pairs(_G) do table.insert(list, n) end
  table.sort(list)
  log(_VERSION)
  log(list)
end)

commands.add_command(
    "log", "Enable/disable logging. `/log on` to enable, `/log off` to disable.",
function(args)
  local enabled = true
  if args.parameter ~= nil then
    local param = string.lower(args.parameter)
    if param == "1" or param == "on" or param == "true" then
      enabled = true
    elseif param == "0" or param == "off" or param == "false" then
      enabled = false
    else
      game.print("Usage: /log [on|off]\n")
      return
    end
  end
  util.set_log(true)
  if enabled then
    game.print("Logging enabled")
  else
    game.print("Logging disabled")
  end
end)

commands.add_command("pathfinder", "Pathfinder debug",
function()
  controller.activate()
  local coal_entities = controller.entities_filtered{name = "coal"}
  log("Found", #coal_entities, "coal entities")
  local goals = {}
  for _, e in ipairs(coal_entities) do
    table.insert(goals, pos.pack(e.position))
  end
  local pathfinder = Pathfinder.new(controller, goals, 2.8)
  pathfinder:debug()
end)

local _pathfinder

commands.add_command("step", "Make one pathfinder step (debug)",
function()
  controller.activate()
  if _pathfinder == nil then
    local coal_entities = controller.entities_filtered{name = "coal"}
    log("Found", #coal_entities, "coal entities")
    local goals = {}
    for _, e in ipairs(coal_entities) do
      table.insert(goals, pos.pack(e.position))
    end
    _pathfinder = Pathfinder.new(controller, goals, 2.8)
  end
  local dir = _pathfinder:next_step()

  log("step dir", dir)

  if dir ~= nil then controller.walk(dir) end
end)

commands.add_command("tiles", "Show TilePathfinder distances",
function()
  controller.activate()
  local coal_entities = controller.entities_filtered{name = "coal"}
  log("Found", #coal_entities, "coal entities")
  local goals = {}
  for _, e in ipairs(coal_entities) do
    table.insert(goals, pos.pack(e.position))
  end
  local goals_pset = PointSet.new(goals)
  local tp = tile_pathfinder.TilePathfinder.new(controller, goals_pset,
                                                2.8)
  local center = tile_pathfinder.get_tile_center(controller.position())
  local cx, cy = pos.unpack(center)
  log("center", pos.norm(center))
  for dy = -5, 5, 1 do
    local row = {}
    for dx = -5, 5, 1 do
      local dist = tp:min_distance({cx + dx, cy + dy})
      if dist == nil then
        table.insert(row, "*")
      else
        table.insert(row, string.format("%0.2f", dist))
      end
    end
    log(dy, row)
  end
end)
