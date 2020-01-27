local box = require "box"
local game_controller = require "controller"
local pos = require "pos"
local util = require "util"
local log = util.log
local Pathfinder = require("pathfinder").Pathfinder
local PointSet = require("pointset").PointSet
local tests = require "tests"
local tile_pathfinder = require "tile_pathfinder"
local walking = require "walking"
local WalkSimulator = walking.WalkSimulator
local DIRECTIONS = walking.DIRECTIONS

-- Ai makes the decisions what to do and controls the character through the controller object.

local Ai = {}
Ai.__index = Ai

function Ai.new(controller)
  local self = {}
  setmetatable(self, Ai)
  self.controller = controller
  self.pathfinder = Pathfinder.new(controller)
  self.walk_simulator = WalkSimulator.new(controller)
  self.previous_action = nil
  return self
end

function Ai:start()
  log("Ai:start")
  self.updates = 0
  self.tick_listener = util.bind(self, "update")
  self.controller.add_listener(self.tick_listener)
end

function Ai:stop()
  self.controller.remove_listener(self.tick_listener)
  self.walk_simulator:clear()
end

function Ai:try_to_mine()
  local player_box = box.pad(self.controller.position(), 3)
  local coal_entities = self.controller.entities_filtered{
    area = player_box,
    name = "coal"
  }
  local ore_entity = nil
  for _, e in ipairs(coal_entities) do
    if self.controller.is_minable(e) then
      ore_entity = e
      break
    end
  end

  if ore_entity ~= nil then
    self.controller.mine_entity(ore_entity)

    if self.previous_action ~= "mine" then
      log("Reached ore entity", ore_entity.name, pos.norm(ore_entity.position))
      log("L2 distance to entity:",
          pos.dist_l2(self.controller.position(), ore_entity.position))
      self.previous_action = "mine"
    end
    return true
  end

  return false
end

function Ai:update()
  if self.previous_action == "walk" then
    if not self.walk_simulator:check_prediction() then return self:stop() end
  end

  if self:try_to_mine() then return end

  if not self.pathfinder:has_goals() then
    local coal_entities = self.controller.entities_filtered{name = "coal"}
    log("Found", #coal_entities, "coal entities")
    local goals = {}
    for _, e in ipairs(coal_entities) do
      table.insert(goals, pos.pack(e.position))
    end
    self.pathfinder:set_goals(goals, 2.8)
  end

  local dir = self.pathfinder:next_step()
  log("step dir", dir)

  if dir ~= nil then
    self.controller.walk(dir)
    self.walk_simulator:register_prediction(dir)
    self.previous_action = "walk"
    return
  end

  self.previous_action = nil
end

-- Controller and Ai singletons

local active_ai = nil
local active_controller = nil

local function get_controller()
  if active_controller == nil then
    active_controller = game_controller
    active_controller.start(game.player)
    script.on_nth_tick(1, active_controller.on_tick)
  end
  return active_controller
end

local function get_ai()
  local ai_controller = get_controller()
  if active_ai == nil then active_ai = Ai.new(ai_controller) end
  return active_ai
end

-- Commands

local function start()
  game.print("--------------")
  game.print(_VERSION)

  local ai = get_ai()
  ai:start()
end

local function stop()
  get_ai():stop()
  get_controller().remove_all_listeners()
end

local function player_pos()
  local pos = get_controller().position()
  game.print("position: " .. serpent.line(pos))
  game.print("resource_reach_distance: " .. game.player.resource_reach_distance)
end

local function entities()
  local controller = get_controller()
  local entities = controller.entities(5)
  game.print("Entities in the 10x10 box:")
  for _, e in ipairs(entities) do
    log(e.name, " position: ", e.position, " bounding: ", e.bounding_box,
        " collision: ", e.prototype.collision_box, " orientation: ",
        e.orientation)
  end
end

local function all_entities()
  local count = 0
  local type_count = {}
  local p1, p2 = {x = 0, y = 0}, {x = 0, y = 0}
  for _, entity in ipairs(get_controller().entities()) do
    count = count + 1
    type_name = entity.name .. " " .. entity.type
    type_count[type_name] = (type_count[type_name] or 0) + 1

    p1.x = math.min(p1.x, entity.position.x)
    p1.y = math.min(p1.y, entity.position.y)
    p2.x = math.max(p2.x, entity.position.x)
    p2.y = math.max(p2.y, entity.position.y)
  end

  log(serpent.block(type_count))
  log("Found", count, "entities")
  log("Bounding box:", p1, p2)
end

local function recipes()
  for name, recipe in pairs(get_controller().recipes()) do
    if name == "engine-unit" or recipe.enabled and not recipe.hidden then
      log(recipe.name, recipe.category)
    end
  end
end

local function recipe(args)
  log("Args:", args)
  local name = args.parameter
  local recipe = get_controller().recipes()[name]
  log("name:", name, "enabled:", recipe.enabled, "category:", recipe.category,
      "hidden:", recipe.hidden, "energy:", recipe.energy, "order:",
      recipe.order, "group:", recipe.group.name)
  log("Ingredients:", recipe.ingredients)
  log("Products:", recipe.products)
end

local function inventory(args)
  local controller = get_controller()
  local inventory = controller.character().get_inventory(
                        defines.inventory[args.parameter])
  if inventory == nil then log("Unknown inventory") end
  log("Inventory type:", type, "slots:", #inventory)
  log("Contents:", inventory.get_contents())
  log("has_items_inside:", controller.character().has_items_inside())
end

local function mine(args) get_controller().mine() end

local function walk(args)
  dir = defines.direction[args.parameter]
  log("Walking in direction:", dir)

  local controller = get_controller()
  local simulator = WalkSimulator.new(controller)

  local function walk(controller)
    if not simulator:check_prediction() then
      controller.remove_all_listeners()
    end

    controller.walk(dir)
    simulator:register_prediction(dir)
  end

  controller.add_listener(walk)
end

local function random_walk(args)
  local controller = get_controller()
  local simulator = WalkSimulator.new(controller)

  local function walk(controller)
    if not simulator:check_prediction() then
      controller.remove_all_listeners()
    end

    local dir = DIRECTIONS[math.random(#DIRECTIONS)]
    controller.walk(dir)
    simulator:register_prediction(dir)
  end

  controller.add_listener(walk)
end

local function test() tests.run_tests() end

local function env()
  local list = {}
  for n in pairs(_G) do table.insert(list, n) end
  table.sort(list)
  log(list)
  log(_VERSION)
end

local function set_log(args)
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
end

local function pathfinder_debug()
  local coal_entities = get_controller().entities_filtered{name = "coal"}
  log("Found", #coal_entities, "coal entities")
  local goals = {}
  for _, e in ipairs(coal_entities) do
    table.insert(goals, pos.pack(e.position))
  end
  local pathfinder = Pathfinder.new(get_controller())
  pathfinder:debug(goals, 2.8)
end

local _pathfinder

local function pathfinder_step()
  if _pathfinder == nil then
    local coal_entities = get_controller().entities_filtered{name = "coal"}
    log("Found", #coal_entities, "coal entities")
    local goals = {}
    for _, e in ipairs(coal_entities) do
      table.insert(goals, pos.pack(e.position))
    end
    _pathfinder = Pathfinder.new(get_controller())
    _pathfinder:set_goals(goals, 2.8)
  end
  local dir = _pathfinder:next_step()

  log("step dir", dir)

  if dir ~= nil then get_controller().walk(dir) end
end

local function pathfinder_tiles()
  local coal_entities = get_controller().entities_filtered{name = "coal"}
  log("Found", #coal_entities, "coal entities")
  local goals = {}
  for _, e in ipairs(coal_entities) do
    table.insert(goals, pos.pack(e.position))
  end
  local goals_pset = PointSet.new(goals)
  local tp = tile_pathfinder.TilePathfinder.new(get_controller(), goals_pset,
                                                2.8)
  local center = tile_pathfinder.get_tile_center(get_controller().position())
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
end

commands.add_command("start", "Give AI control over the player", start)
commands.add_command("stop", "Stops AI and any running actions in Controller",
                     stop)
commands.add_command("pos", "Show current position", player_pos)
commands.add_command("entities", "Show entities around", entities)
commands.add_command("all_entities", "Show all known entities", all_entities)
commands.add_command("inventory",
                     "Show the character's inventory of a given type", inventory)
commands.add_command("recipe", "Show details about a recipe", recipe)
commands.add_command("recipes", "Show all known recipes", recipes)
commands.add_command("mine", "Mine the nearest minable tile", mine)
commands.add_command("walk", "Walk in the given direction (n, nw, w, ...)", walk)
commands.add_command("test", "Run unit tests", test)
commands.add_command("random-walk", "Investigate how walking works", random_walk)
commands.add_command("env", "Show all variable in global environment", env)
commands.add_command("log",
                     "Enable/disable AI logging. Args: 1/true/on to enable, 0/false/off to disable.",
                     set_log)
commands.add_command("pathfinder", "", pathfinder_debug)
commands.add_command("step", "", pathfinder_step)
commands.add_command("tiles", "", pathfinder_tiles)
