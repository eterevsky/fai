local box = require "box"
local pos = require "pos"
local pqueue = require "pqueue"
local PriorityQueue = pqueue.PriorityQueue
local util = require "util"
local log = util.log
local walking = require "walking"
local WalkSimulator = walking.WalkSimulator
local DIRECTIONS = walking.DIRECTIONS

local function sign(x)
  if x > 0 then
    return 1
  elseif x < 0 then
    return -1
  else
    return 0
  end
end

-- Controller creates a useful subset of Factorio API through which the AI controls the game.

local Controller = {}
Controller.__index = Controller

function Controller.new(player)
  local controller = {}
  setmetatable(controller, Controller)
  controller.player = player
  controller.surface = player.surface
  controller.action_state = {type = nil}
  controller.old_action_state = nil
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

-- Return all entities in the box with the side 2*radius.
function Controller:entities(radius)
  if radius == nil then radius = 1000 end
  local bounding_box = box.pad(self:position(), radius)
  return self.surface.find_entities(bounding_box)
end

function Controller:entities_in_box(bounding_box)
  local bounding_box = box.norm(bounding_box)
  return self.surface.find_entities(bounding_box)
end

function Controller:entities_filtered(filters)
  return self.surface.find_entities_filtered(filters)
end

function Controller:stop_actions()
  self.action_state = {action = nil}
end

-- Stop any running action
function Controller:stop()
  self:stop_actions()
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
  self.action_state = {action = "mining", position = selection_point, entity = entity}
end

-- Walk one step in given direction
function Controller:walk(dir)
  self.action_state = {action = "walking", direction = dir}
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

function Controller:on_tick()
  for _, listener in ipairs(self.listeners) do
    listener(self)
  end
  self:update()
end

function Controller:current_action()
  return self.action_state.action
end

-- Keep doing whatever we are doing (i.e. walking, mining)
function Controller:update()
  if self.old_action_state ~= self.action_state then
    -- game.print("New action_state: " .. serpent.line(self.action_state))
    self.old_action_state = self.action_state
  end
  if self.action_state.action == "walking" then
    self.player.walking_state = {walking = true, direction = self.action_state.direction}
  elseif self.action_state.action == "mining" then
    self.player.update_selected_entity(self.action_state.position)
    self.player.mining_state = {mining = true, position = self.action_state.position}
  end
end

local PathNode = {}
PathNode.__index = PathNode

-- steps is the number of steps already taken
-- cost is the sum of `steps` and the low estimate for the remaining part
function PathNode.new(position, prev_enc, dir, steps, cost)
  local self = {
    pos = position,
    prev_enc = prev_enc,
    dir = dir,
    steps = steps,
    cost = cost,
  }
  setmetatable(self, PathNode)
  return self
end

-- Returns the estimated distance from the node position to the goals.
function PathNode:remaining_steps()
  return self.cost - self.steps
end

PathNode.__eq = function(a, b)
  return a.cost == b.cost
end

PathNode.__lt = function(a, b)
  return a.cost < b.cost
end

PathNode.__le = function(a, b)
  return a.cost <= b.cost
end

-- Pathfinder implements walking to reach certain goals.
local Pathfinder = {}
Pathfinder.__index = Pathfinder

function Pathfinder.new(controller)
  local self = {}
  setmetatable(self, Pathfinder)
  self.controller = controller
  self.goals = {}
  self.distance = 1.0
  -- Every next step should lead to the closest node that is no further from the goals than on the
  -- previous step
  self.closest_node_distance = nil
  -- Encoded position -> distance to goals
  self.steps_cache = {}
  self.simulator = WalkSimulator.new(controller)
  return self
end

-- Low estimate for the number of ticks to reach a point within the given distance from any of the
-- goals.
function Pathfinder:_estimate_steps(from)
  local from = pos.pack(from)
  local cached_steps = self.steps_cache[from]
  if cached_steps ~= nil then
    self.cache_hits = self.cache_hits + 1
    return cached_steps
  end

  local speed = 38 / 256
  local diag_speed = 27 / 256
  local min_steps = 1E9
  local sqrt2 = math.sqrt(2)

  for _, goal in ipairs(self.goals) do
    local dist = pos.dist_l2(from, goal)
    if dist < self.distance then return 0 end

    local steps = math.ceil((dist - self.distance) / speed)
    assert(steps > 0)
    if steps < min_steps then min_steps = steps end
  end

  self.cache_misses = self.cache_misses + 1
  self.steps_cache[from] = min_steps

  return min_steps
end

function Pathfinder:set_goals(goals, distance)
  self.goals = goals
  self.distance = distance
  self.steps_cache = {}
end

-- A* search that finds the fastest path to any position from goals, ending within the distance of
-- it.
function Pathfinder:next_step()
  self.cache_hits = 0
  self.cache_misses = 0
  local start_pos = self.controller:position()
  local start_pos = pos.pack(start_pos)
  local start_cost = self:_estimate_steps(start_pos)

  local queue, visited
  if self.old_queue ~= nil then
    queue = self.old_queue
    self.old_queue = nil
    visited = self.old_visited
    self.old_visited = nil
    -- log("Inherited the queue with", queue:size(), "elements and", util.table_size(visited),
    --     "visited nodes")
  else
    self.simulator:reset()
    queue = PriorityQueue.new()
    start_node = PathNode.new(start_pos, nil, nil, 0, start_cost)
    queue:push(start_node)
    -- visited position -> PathNode
    visited = {}
  end

  local counter = 0

  local closest_node = nil
  local min_cost = start_cost
  local last_node

  while not queue:empty() and counter < 256 and min_cost > 0 do
    local node = queue:pop()
    last_node = node
    assert(node ~= nil)
    if visited[node.pos] ~= nil then goto continue end
    visited[node.pos] = node
    counter = counter + 1

    for _, dir in ipairs(DIRECTIONS) do
      local new_pos = self.simulator:walk(node.pos, dir)
      if new_pos ~= node.pos then
        local new_cost = self:_estimate_steps(new_pos)
        local new_node = PathNode.new(new_pos, node.pos, dir, node.steps + 1,
                                      new_cost + node.steps + 1)
        if new_cost < min_cost then
          closest_node = new_node
          min_cost = new_cost
        end
        if new_cost == 0 then break end

        queue:push(new_node)
      end
    end

    ::continue::
  end

  if closest_node == nil then
    -- log("Not found. min_cost =", min_cost, "(", self.cache_hits, "/", self.cache_misses, ")")
    -- self.simulator:log()
    self.old_visited = visited
    self.old_queue = queue
    return nil
  end

  if self.closest_node_distance ~= nil and
     closest_node:remaining_steps() > self.closest_node_distance then
    -- log("Closest node too far:", closest_node, "(", self.cache_hits, "/", self.cache_misses, ")")
    self.old_visited = visited
    self.old_queue = queue
    return nil
  end

  local node = closest_node
  self.closest_node_distance = closest_node:remaining_steps()
  local steps = 0
  local next_dir = nil
  local next_pos = nil
  while node ~= nil and node.dir ~= nil do
    next_pos = node.pos
    next_dir = node.dir
    node = visited[node.prev_enc]
    steps = steps + 1
  end

  log(steps, "+", min_cost, "steps (", self.cache_hits, "/", self.cache_misses, ")")
  -- log(steps, " steps + estimation ", min_cost, " = initial estimation + ",
  --     min_cost + steps - start_cost, "(", self.cache_hits, "/", self.cache_misses, ")")
  -- self.simulator:log()

  return {
    current_pos = start_pos,
    expected_pos = next_pos,
    step = next_dir
  }
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
  return self
end

function Ai:start()
  -- self.start_clock = os.clock()
  self.updates = 0
  self.controller:add_listener(util.bind(self, 'update'))

  local coal_entities = self.controller:entities_filtered{name = "coal"}
  log("Found", #coal_entities, "coal entities")
  local goals = {}
  for _, e in ipairs(coal_entities) do
    table.insert(goals, pos.pack(e.position))
  end
  self.pathfinder:set_goals(goals, 2.8)
end

function Ai:stop()
  self.controller:stop()
end

function Ai:update()
  self.walk_simulator:check_prediction()
  -- self.updates = self.updates + 1
  -- if self.controller:current_action() == "mining" then return end

  if self.prediction ~= nil then
    if pos.dist_linf(self.prediction.expected_pos, self.controller:position()) > 0 then
      log("Expected position:", pos.norm(self.prediction.expected_pos))
      log("Actual position:", self.controller:position())
      log("Expected delta:", pos.delta(self.prediction.expected_pos, self.prediction.current_pos))
      log("Actual delta:", pos.delta(self.controller:position(), self.prediction.current_pos))
      self.prediction = nil
      self:stop()
      return
    end
    self.prediction = nil
  end

  local player_box = box.pad(self.controller:position(), 3)
  local coal_entities = self.controller:entities_filtered{area=player_box, name = "coal"}
  local ore_entity = nil
  for _, e in ipairs(coal_entities) do
    -- log("L2 distance to entity:",
    --     pos.dist_l2(self.controller:position(), e.position),
    --     "Linf distance to entity:", pos.dist_linf(self.controller:position(), e.position))
    if self.controller:is_minable(e) then
      ore_entity = e
      break
    end
  end

  if ore_entity ~= nil then
    -- local mine_clock = os.clock()
    -- log(mine_clock - self.start_clock, "seconds per", self.updates, "updates =",
    --     (mine_clock - self.start_clock) / self.updates, "s per update")
    log("Reached ore entity", ore_entity.name, ore_entity.position)
    log("L2 distance to entity:", pos.dist_l2(self.controller:position(), ore_entity.position))
    log("Linf distance to entity:", pos.dist_linf(self.controller:position(), ore_entity.position))
    self.controller:mine_entity(ore_entity)
    return
  end

  self.prediction = self.pathfinder:next_step()

  -- Path works as a stack, with the first direction on top.
  if self.prediction == nil then
    -- log("Finished walk, but haven't found any ore")
    -- self:stop()
    self.controller:stop_actions()
    return
  end

  self.controller:walk(self.prediction.step)
  self.walk_simulator:register_prediction(self.prediction.step)
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
  local entities = controller:entities(10)
  game.print("Entities in the 20x20 box:")
  for _, e in ipairs(entities) do
    log(e.name, e.position)
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

  game.print(serpent.block(type_count))
  game.print("Found " .. count .. " entities")
  game.print("Bounding box: " .. serpent.line(p1) .. " " .. serpent.line(p2))
end

local function recipes()
  local force = game.player.force
  for name, recipe in pairs(force.recipes) do
    if name == "engine-unit" or recipe.enabled and not recipe.hidden then
      game.print(recipe.name .. " "  ..
                 recipe.category .. " ")
    end
  end
end

local function mine(args)
  get_controller():mine()
end

local function walk(args)
  game.print("Args: [" .. serpent.line(args) .. "]")
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
commands.add_command("recipes", "Show all known recipes", recipes)
commands.add_command("mine", "Mine the nearest minable tile", mine)
commands.add_command("walk", "Walk in the direction given by two relative coordinates", walk)
commands.add_command("test", "Run unit tests", test)
commands.add_command("test-walk", "Investigate how walking works", test_walk)
commands.add_command("env", "Show all variable in global environment", env)