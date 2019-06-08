local box = require "box"
local pos = require "pos"
local pqueue = require "pqueue"
local util = require "util"
local log = util.log
local Pathfinder = require("pathfinder").Pathfinder
local walking = require "walking"
local WalkSimulator = walking.WalkSimulator
local DIRECTIONS = walking.DIRECTIONS

-- Controller creates a useful subset of Factorio API through which the AI controls the game.

local Controller = {}
Controller.__index = Controller

function Controller.new(player)
  local controller = {}
  setmetatable(controller, Controller)
  controller.player = player
  controller.surface = player.surface
  controller.listeners = {}
  return controller
end

-- Get current position
function Controller:position()
  return self.player.position
end

-- Get player character entity
function Controller:character()
  return self.player.character
end

-- Returns all entities in the box with the side 2*radius.
function Controller:entities(radius)
  if radius == nil then radius = 1000 end
  local bounding_box = box.pad(self:position(), radius)
  return self.surface.find_entities(bounding_box)
end

-- Returns a dictionary name -> LuaRecipe of all available recipes.
function Controller:recipes()
  return self.player.force.recipes
end

function Controller:entities_in_box(bounding_box)
  local bounding_box = box.norm(bounding_box)
  return self.surface.find_entities(bounding_box)
end

function Controller:entities_filtered(filters)
  return self.surface.find_entities_filtered(filters)
end

-- Stop any running action
function Controller:stop()
  self:remove_all_listeners()
end

-- Mine position
function Controller:mine()
  local reach_distance = self.player.resource_reach_distance + 0.3
  local player_box = box.padding(self:position(), reach_distance)
  local ore_entity, ore_point

  for _, e in ipairs(self.surface.find_entities(player_box)) do
    if self:is_minable(e) then
      ore_entity = e
    end
  end

  if ore_entity == nil then
    game.print("Didn't find any reachable ore entity")
    return
  end

  log("Found ore entity:", ore_entity.name, ore_entity.position)
  self:mine_entity(ore_entity)
end

function Controller:is_minable(entity)
  return entity.minable and self.player.can_reach_entity(entity) and entity.name ~= "player"
end

function Controller:mine_entity(entity)
  local selection_point = box.selection_diff(entity.selection_box, self.player.character.selection_box)
  self.player.update_selected_entity(selection_point)
  self.player.mining_state = {mining = true, position = selection_point}
end

function Controller:get_inventory(type)
  if type == nil then
    return self.player.character.get_main_inventory()
  else
    return self.player.character.get_inventory(type)
  end
end

function Controller:craft(recipe)
  self.player.begin_crafting{count=1, recipe=recipe}
end

function Controller:crafting_queue()
  return self.player.character.crafting_queue
end

-- Walk one step in given direction
function Controller:walk(dir)
  self.player.walking_state = {walking = true, direction = dir}
end

function Controller:get_tile(position)
  return self.surface.get_tile(pos.unpack(position))
end

function Controller:add_listener(callback)
  table.insert(self.listeners, callback)
end

function Controller:remove_all_listeners()
  self.listeners = {}
end

function Controller:remove_listener(callback)
  for i, e in ipairs(self.listeners) do
    if e == callback then
      table.remove(self.listeners, i)
      break
    end
  end
end

function Controller:tick()
  return game.tick
end

function Controller:on_tick()
  for _, listener in ipairs(self.listeners) do
    listener(self)
  end
end

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
  log('Ai:start')
  self.updates = 0
  self.controller:add_listener(util.bind(self, 'update'))
end

function Ai:stop()
  self.controller:stop()
end

function Ai:try_to_mine()
  local player_box = box.pad(self.controller:position(), 3)
  local coal_entities = self.controller:entities_filtered{area=player_box, name = "coal"}
  local ore_entity = nil
  for _, e in ipairs(coal_entities) do
    if self.controller:is_minable(e) then
      ore_entity = e
      break
    end
  end

  if ore_entity ~= nil then
    self.controller:mine_entity(ore_entity)

    if self.previous_action ~= "mine" then
      log("Reached ore entity", ore_entity.name, pos.norm(ore_entity.position))
      log("L2 distance to entity:", pos.dist_l2(self.controller:position(), ore_entity.position))
      self.previous_action = "mine"
    end
    return true
  end

  return false
end

function Ai:check_tool()
  local tools = self.controller:get_inventory(defines.inventory.player_tools)
  if not tools.is_empty() then return end
  local crafting_queue = self.controller:crafting_queue()
  if crafting_queue ~= nil then
    for _, crafting_item in ipairs(crafting_queue) do
      if crafting_item.recipe == "iron-axe" then return end
    end
  end
  self.controller:craft("iron-axe")
end

function Ai:update()
  if self.previous_action == "walk" then
    self.walk_simulator:check_prediction()
  end

  if self:try_to_mine() then return end

  if not self.pathfinder:has_goals() then
    local coal_entities = self.controller:entities_filtered{name = "coal"}
    log("Found", #coal_entities, "coal entities")
    local goals = {}
    for _, e in ipairs(coal_entities) do
      table.insert(goals, pos.pack(e.position))
    end
    self.pathfinder:set_goals(goals, 2.8)
  end

  local dir = self.pathfinder:next_step()

  if dir ~= nil then
    self.controller:walk(dir)
    self.walk_simulator:register_prediction(dir)
    self.previous_action = "walk"
    return
  end

  self.previous_action = nil
end

-- Controller and Ai singletons

local active_controller = nil;
local active_ai = nil;

local function get_controller()
  if active_controller == nil then
    active_controller = Controller.new(game.player)
    script.on_nth_tick(1, util.bind(active_controller, 'on_tick'))
  end
  return active_controller
end

local function get_ai()
  local controller = get_controller()
  if active_ai == nil then
    active_ai = Ai.new(controller)
  end
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
  get_controller():remove_all_listeners()
end

local function player_pos()
  local pos = get_controller():position()
  game.print("position: " .. serpent.line(pos))
  game.print("resource_reach_distance: " .. game.player.resource_reach_distance)
end

local function entities()
  local controller = get_controller()
  local entities = controller:entities(5)
  game.print("Entities in the 10x10 box:")
  for _, e in ipairs(entities) do
    log(e.name, " position: ", e.position, " bounding: ", e.bounding_box,
        " collision: ", e.prototype.collision_box, " orientation: ", e.orientation)
  end
end

local function all_entities()
  local count = 0
  local type_count = {}
  local p1, p2 = {x = 0, y = 0}, {x = 0, y = 0}
  for _, entity in ipairs(get_controller():entities()) do
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
  for name, recipe in pairs(get_controller():recipes()) do
    if name == "engine-unit" or recipe.enabled and not recipe.hidden then
      log(recipe.name, recipe.category)
    end
  end
end

local function recipe(args)
  log("Args:", args)
  local name = args.parameter
  local recipe = get_controller():recipes()[name]
  log("name:", name, "enabled:", recipe.enabled, "category:", recipe.category,
      "hidden:", recipe.hidden, "energy:", recipe.energy, "order:", recipe.order,
      "group:", recipe.group.name)
  log("Ingredients:", recipe.ingredients)
  log("Products:", recipe.products)
end

local function inventory(args)
  local controller = get_controller()
  local inventory = controller:character().get_inventory(defines.inventory[args.parameter])
  if inventory == nil then
    log("Unknown inventory")
  end
  log("Inventory type:", type, "slots:", #inventory)
  log("Contents:", inventory.get_contents())
  log("has_items_inside:", controller:character().has_items_inside())
end

local function mine(args)
  get_controller():mine()
end

local function walk(args)
  log("Args:", args)
  dir = defines.direction[args.parameter]
  get_controller():walk(dir)
end

local function test_walk(args)
  local controller = get_controller()
  local simulator = WalkSimulator.new(get_controller())
  simulator:register_prediction()

  log(DIRECTIONS)

  local function continue(controller)
    simulator:check_prediction()

    local dir = DIRECTIONS[math.random(#DIRECTIONS)]
    controller:walk(dir)
    simulator:register_prediction(dir)
  end

  controller:add_listener(continue)
end

local function test()
  box.test_selection_diff()
  box.test_overlap_rotated()
  pos.test()
  pos.test_pack_delta()
  pqueue.small_test()
  pqueue.test()
end

local function env()
  local list = {}
  for n in pairs(_G) do
    table.insert(list, n)
  end
  table.sort(list)
  log(list)
  log(_VERSION)
end

commands.add_command("start", "Give AI control over the player", start)
commands.add_command("stop", "Stops AI and any running actions in Controller", stop)
commands.add_command("pos", "Show current position", player_pos)
commands.add_command("entities", "Show entities around", entities)
commands.add_command("all_entities", "Show all known entities", all_entities)
commands.add_command("inventory", "Show the character's inventory of a given type", inventory)
commands.add_command("recipe", "Show details about a recipe", recipe)
commands.add_command("recipes", "Show all known recipes", recipes)
commands.add_command("mine", "Mine the nearest minable tile", mine)
commands.add_command("walk", "Walk in the direction given by two relative coordinates", walk)
commands.add_command("test", "Run unit tests", test)
commands.add_command("test-walk", "Investigate how walking works", test_walk)
commands.add_command("env", "Show all variable in global environment", env)