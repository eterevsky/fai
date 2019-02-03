local function log(...)
  local s = ""
  local first = true
  for _, arg in ipairs{...} do
    if first then
      first = false
    else
      s = s .. " "
    end

    if type(arg) == "string" or type(arg) == "number" then
      s = s .. arg
    else
      s = s .. serpent.line(arg)
    end
  end
  game.print(s)
end

local function bind(t, k)
  return function(...) return t[k](t, ...) end
end

local function table_size(t)
  local count = 0
  for _, _ in pairs(t) do
    count = count + 1
  end
  return count
end

local function sign(x)
  if x > 0 then
    return 1
  elseif x < 0 then
    return -1
  else
    return 0
  end
end

local function pos_unpack(pos)
  if type(pos) == "number" then
    log(debug.traceback())
  end
  local x = pos.x or pos[1]
  local y = pos.y or pos[2]
  return x, y
end

local function pos_norm(pos)
  if pos.x ~= nil then
    return pos
  end
  return {x = pos[1], y = pos[2]}
end

local function pos_delta(p1, p2) 
  local x1, y1 = pos_unpack(p1)
  local x2, y2 = pos_unpack(p2)
  return {x2 - x1, y2 - y1}
end

local RADIX = 2 ^ 20

local function pos_enc(pos)
  local x, y = pos_unpack(pos)
  local x_scaled = math.floor(x * 256)
  local y_scaled = math.floor(y * 256)

  assert(x_scaled < RADIX and y_scaled < RADIX)

  return x_scaled + RADIX * y_scaled
end

local function l2_distance(p1, p2)
  local x1, y1 = pos_unpack(p1)
  local x2, y2 = pos_unpack(p2)
  local dx = x2 - x1
  local dy = y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function linf_distance(p1, p2)
  local x1, y1 = pos_unpack(p1)
  local x2, y2 = pos_unpack(p2)
  local dx = x2 - x1
  local dy = y2 - y1
  return math.max(math.abs(dx), math.abs(dy))
end

local function box_norm(box)
  if box.left_top ~= nil then
    return box
  end
  local left_top = box.left_top or box[1]
  local right_bottom = box.right_bottom or box[2]
  return {left_top = pos_norm(left_top), right_bottom = pos_norm(right_bottom)}
end

-- Move a box from (0, 0) to center.
local function box_move(box, center)
  local box = box_norm(box)
  local x, y = pos_unpack(center)
  return box_norm{
    {box.left_top.x + x, box.left_top.y + y},
    {box.right_bottom.x + x, box.right_bottom.y + y}
  }
end

-- Checks whether a point falls within bounding box
local function box_contains(box, pos)
  local box = box_norm(box)
  local pos = pos_norm(pos)

  return box.left_top.x <= pos.x and box.left_top.y <= pos.y and
         box.right_bottom.x >= pos.x and box.right_bottom.y >= pos.y
end

-- Checks whether two boxes intersect.
local function boxes_overlap(box1, box2)
  local box1 = box_norm(box1)
  local box2 = box_norm(box2)

  return box1.left_top.x < box2.right_bottom.x and
         box1.right_bottom.x > box2.left_top.x and
         box1.left_top.y < box2.right_bottom.y and
         box1.right_bottom.y > box2.left_top.y
end

local function box_padding(center, padding)
  center = pos_norm(center)
  return {{center.x - padding, center.y - padding}, {center.x + padding, center.y + padding}}
end

-- Find a point, that is inside bounding box 1, but not inside bounding box 2.
local function selection_diff(box1, box2)
  local box1 = box_norm(box1)
  local box2 = box_norm(box2)

  local x = (box1.right_bottom.x + box1.left_top.x) / 2
  if box1.left_top.x < box2.left_top.x then
    x = (box1.left_top.x + math.min(box1.right_bottom.x, box2.left_top.x)) / 2
  elseif box1.right_bottom.x > box2.right_bottom.x then
    x = (box1.right_bottom.x + math.max(box1.left_top.x, box2.right_bottom.x)) / 2
  end

  local y = (box1.right_bottom.y + box1.left_top.y) / 2
  if box1.left_top.y < box2.left_top.y then
    y = (box1.left_top.y + math.min(box1.right_bottom.y, box2.left_top.y)) / 2
  elseif box1.right_bottom.y > box2.right_bottom.y then
    y = (box1.right_bottom.y + math.max(box1.left_top.y, box2.right_bottom.y)) / 2
  end

  if box_contains(box2, {x, y}) then
    return nil
  end
  
  return {x = x, y = y}
end

local function test_selection_diff()
  local box1 = {{1, 2}, {2, 3}}
  local box2 = {{0, 1}, {3, 4}}
  local p = selection_diff(box1, box2)
  assert(p == nil)

  box2 = {{1.5, 1}, {3, 4}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box_contains(box1, p))
  assert(not box_contains(box2, p))

  box2 = {{0, 0}, {3, 2.5}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box_contains(box1, p))
  assert(not box_contains(box2, p))

  box2 = {{1.1, 2.1}, {1.9, 2.9}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box_contains(box1, p))
  assert(not box_contains(box2, p))

  log("test_selection_diff ok")
end

local DIR_TO_DELTA = {}
DIR_TO_DELTA[defines.direction.north]	= {0, -1}
DIR_TO_DELTA[defines.direction.northeast]	= {1, -1}
DIR_TO_DELTA[defines.direction.east] = {1, 0}
DIR_TO_DELTA[defines.direction.southeast]	= {1, 1}
DIR_TO_DELTA[defines.direction.south]	= {0, 1}
DIR_TO_DELTA[defines.direction.southwest]	= {-1, 1}
DIR_TO_DELTA[defines.direction.west] = {-1, 0}
DIR_TO_DELTA[defines.direction.northwest] = {-1, -1}

local DIRECTIONS = {}
for dir, _ in pairs(DIR_TO_DELTA) do
  table.insert(DIRECTIONS, dir)
end

local function encode_delta(dx, dy)
  local x = sign(dx) + 1
  local y = sign(dy) + 1
  return x * 3 + y
end

local DELTA_TO_DIR = {}
for dir, delta in pairs(DIR_TO_DELTA) do
  DELTA_TO_DIR[encode_delta(delta[1], delta[2])] = dir
end

local function delta_to_dir(dx, dy)
  return DELTA_TO_DIR[encode_delta(dx, dy)]
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
  local x, y = pos_unpack(self:position())
  if radius == nil then radius = 1000 end
  local box = {{x - radius, y - radius}, {x + radius, y + radius}}
  return self.surface.find_entities(box)
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
  local player = self.player
  local pos = self.player.position
  local reach_distance = self.player.resource_reach_distance + 0.3
  local box = box_padding(pos, reach_distance)
  local ore_entity, ore_point

  for _, e in ipairs(self.surface.find_entities(box)) do
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
  local selection_point = selection_diff(entity.selection_box, self.player.character.selection_box)
  self.action_state = {action = "mining", position = selection_point, entity = entity}
end

-- Walk one step in given direction
function Controller:walk(dx_or_dir, dy)
  local dir = dx_or_dir
  if dy ~= nil then
    dir = delta_to_dir(dx_or_dir, dy)
  end
  self.action_state = {action = "walking", direction = dir}
end

function Controller:simulate_walk_no_collisions(pos, dir)
  local posx, posy = pos_unpack(pos)
  local dx, dy = table.unpack(DIR_TO_DELTA[dir])
  -- Default speed. TODO: Take into account the type of surface and speed bonuses.
  local speed = 38 / 256
  local diag_speed = 27 / 256
  if dx == 0 or dy == 0 then
    return {posx + dx * speed, posy + dy * speed}
  else
    return {posx + dx * diag_speed, posy + dy * diag_speed}
  end
end

-- Assuming that the character is in the position pos, simulate walking for one tick in the
-- direction (dx, dy). Instead of simulating the game behavior regarding collisions, in case we
-- collide with anything, we return the starting position.
-- Returns the new position.
function Controller:simulate_walk(pos, dir)
  local new_pos = self:simulate_walk_no_collisions(pos, dir)
  local new_tile = self.surface.get_tile(table.unpack(new_pos))
  if new_tile.collides_with("player-layer") then
    return pos
  end
  local player_box = box_move(self:character().prototype.collision_box, new_pos)
  for _, entity in ipairs(self.surface.find_entities(box_padding(new_pos, 3))) do
    local entity_box = box_move(entity.prototype.collision_box, entity.position)
    if entity.name ~= "player" and
       entity.prototype.collision_mask["player-layer"] and
       boxes_overlap(player_box, entity_box) then
      log("collision with", entity.name)
      return pos
    end
  end
  return new_pos
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

-- Binary heap-based priority queue.

local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
  local self = {}
  setmetatable(self, PriorityQueue)
  self.heap = {}
  return self
end

-- Adds an entry to the priority queue.
function PriorityQueue:push(entry)
  table.insert(self.heap, entry)
  self:_sift_down(#self.heap)
end

function PriorityQueue:empty()
  return next(self.heap) == nil
end

function PriorityQueue:pop()
  local last = table.remove(self.heap)
  if not self:empty() then
    local ret = self.heap[1]
    self.heap[1] = last
    self:_sift_up(1)
    return ret
  else
    return last
  end
end

function PriorityQueue:size()
  return #self.heap
end

function PriorityQueue:_sift_down(idx)
  while idx > 1 do
    local parent_idx = math.floor(idx / 2)

    if self.heap[parent_idx] < self.heap[idx] then return end

    local temp = self.heap[idx]
    self.heap[idx] = self.heap[parent_idx]
    self.heap[parent_idx] = temp

    idx = parent_idx    
  end
end

function PriorityQueue:_sift_up(idx)
  while idx < #self.heap do
    local left, right = 2 * idx, 2 * idx + 1
    if (left > #self.heap or self.heap[idx] < self.heap[left]) and
       (right > #self.heap or self.heap[idx] < self.heap[right]) then
      return
    end
    if right <= #self.heap and self.heap[right] < self.heap[left] then
      local temp = self.heap[right]
      self.heap[right] = self.heap[idx]
      self.heap[idx] = temp
      idx = right
    else
      local temp = self.heap[left]
      self.heap[left] = self.heap[idx]
      self.heap[idx] = temp
      idx = left
    end
  end
end

local function test_priority_queue()
  local queue = PriorityQueue.new()
  queue:push(2)
  queue:push(1)
  assert(queue:pop() == 1)
  queue:push(3)
  queue:push(4)
  assert(queue:pop() == 2)
  queue:push(-1)
  assert(queue:pop() == -1)
  assert(queue:pop() == 3)
  assert(queue:size() == 1)

  log("test_priority_queue ok")
end

local PathNode = {}
PathNode.__index = PathNode

-- steps is the number of steps already taken
-- cost is the sum of `steps` and the low estimate for the remaining part
function PathNode.new(pos, prev_enc, dir, steps, cost)
  local self = {
    pos = pos,
    prev_enc = prev_enc,
    dir = dir,
    steps = steps,
    cost = cost,
  }
  setmetatable(self, PathNode)
  return self
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

-- Ai makes the decisions what to do and controls the character through the controller object.

local Ai = {}
Ai.__index = Ai

function Ai.new(controller)
  local self = {}
  setmetatable(self, Ai)
  self.controller = controller
  return self
end

function Ai:start()
  self.path = {}
  
  local coal_entities = self.controller:entities_filtered{name = "coal"}
  log("Found", #coal_entities, "coal entities")
  local goals = {}
  for _, e in ipairs(coal_entities) do
    table.insert(goals, e.position)
  end
  self.path = self:find_path(goals, 2.8)

  self.controller:add_listener(bind(self, 'update'))
end

function Ai:stop()
  self.controller:stop()
end

-- Low estimate for the number of ticks to reach a point within the given distance from any of the
-- goals.
function Ai:_estimate_steps(pos, goals, distance)
  local pos = pos_norm(pos)
  local speed = 38 / 256
  local diag_speed = 27 / 256
  local min_steps = 1E9
  local sqrt2 = math.sqrt(2)

  for _, goal in ipairs(goals) do
    local goal = pos_norm(goal)
    local dist = l2_distance(pos, goal)
    if dist < distance then return 0 end

    local steps = math.ceil((dist - distance) / speed)
    assert(steps > 0)
    if steps < min_steps then min_steps = steps end
  end

  return min_steps
end

-- A* search that finds the fastest path to any position from goals, ending within the distance of
-- it.
function Ai:find_path(goals, distance)
  local queue = PriorityQueue.new()
  local start_pos = self.controller:position()
  local start_cost = self:_estimate_steps(start_pos, goals, distance)
  log("Initial cost estimation:", start_cost)

  local start_node = PathNode.new(start_pos, nil, nil, 0, start_cost)
  queue:push(start_node)

  -- visited position -> PathNode
  local visited = {}
  local last_node = nil
  local counter = 0

  while not queue:empty() and counter < 10000 do
    local node = queue:pop()
    -- log("Expanding", node)
    assert(node ~= nil)
    local enc = pos_enc(node.pos)
    if visited[enc] ~= nil then goto continue end
    visited[enc] = node
    counter = counter + 1

    local current_pos = node.pos
    local current_steps = node.steps

    for _, dir in ipairs(DIRECTIONS) do
      local new_pos = self.controller:simulate_walk(current_pos, dir)
      if new_pos ~= current_pos then
        local new_cost = self:_estimate_steps(new_pos, goals, distance)
        local new_node = PathNode.new(new_pos, enc, dir, current_steps + 1,
                                      new_cost + current_steps + 1)
        if new_cost == 0 then
          last_node = new_node
          goto found
        end

        queue:push(new_node)
      end
    end

    ::continue::
  end

  ::found::
  log("Have", table_size(visited), "visited nodes and", queue:size(), "nodes in queue")
  if last_node == nil then
    log("Path not found")
    local lo_cost = 100000
    local closest_node = nil
    for _, node in pairs(visited) do
      if node.cost - node.steps < lo_cost then
        lo_cost = node.cost - node.steps
        closest_node = node
      end
    end
    log("Closest node:", closest_node)
    return {}
  end
  
  local path = {}
  local node = last_node

  while node ~= nil and node.dir ~= nil do
    table.insert(path, node.dir)
    node = visited[node.prev_enc]
  end

  log("Found path:", path)
  log("Steps:", #path)
  log("Steps in last node:", last_node.steps)

  return path
end

function Ai:update()
  if self.controller:current_action() == "mining" then return end

  if self.prediction ~= nil then
    if linf_distance(self.prediction.expected_pos, self.controller:position()) > 0 then
      log(self.prediction)
      log("Actual position:", self.controller:position())
      log("Expected delta:", pos_delta(self.prediction.expected_pos, self.prediction.current_pos))
      log("Actual delta:", pos_delta(self.controller:position(), self.prediction.current_pos))
      self.prediction = nil
      self:stop()
      return
    end
    self.prediction = nil
  end

  local box = box_padding(self.controller:position(), 3)
  local coal_entities = self.controller:entities_filtered{area=box, name = "coal"}
  local ore_entity = nil
  for _, e in ipairs(coal_entities) do
    log("L2 distance to entity:",
        l2_distance(self.controller:position(), e.position),
        "Linf distance to entity:", linf_distance(self.controller:position(), e.position))
    if self.controller:is_minable(e) then
      ore_entity = e
      break
    end
  end

  if ore_entity ~= nil then
    log("Reached ore entity", ore_entity.name, ore_entity.position)
    log("Remaining steps:", self.path)
    log("L2 distance to entity:", l2_distance(self.controller:position(), ore_entity.position))
    log("Linf distance to entity:", linf_distance(self.controller:position(), ore_entity.position))
    self.path = {}
    self.controller:mine_entity(ore_entity)
    return
  end

  -- Path works as a stack, with the first direction on top.
  if #self.path == 0 then
    -- self.controller:mine()
    -- self.controller:stop_actions()
    log("Finished walk, but haven't found any ore")
    self:stop()
    return
  end

  local step = table.remove(self.path)
  local current_pos = self.controller:position()
  local expected_pos = self.controller:simulate_walk(current_pos, step)

  self.prediction = {
    step = step,
    current_pos = current_pos,
    expected_pos = expected_pos
  }

  self.controller:walk(step)
end

-- Controller and Ai singletons

local active_controller = nil;
local active_ai = nil;

local function get_controller()
  if active_controller == nil then
    active_controller = Controller.new(game.player)
    script.on_nth_tick(1, bind(active_controller, 'on_tick'))
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

local function pos()
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
  game.print("Args: " .. serpent.line(args))
  local x, y = string.match(args.parameter, "(-?%d+)%s+(-?%d+)")
  x, y = tonumber(x), tonumber(y)
  get_controller():walk(x, y)
end

local function test_walk(args)
  local controller = get_controller()
  local pos = controller:position()
  local expected_pos = controller:position()

  local function continue(controller)
    local new_pos = controller:position()
    
    if l2_distance(new_pos, expected_pos) > 0.001 then
      log(pos, "->", new_pos)
      log("expected:", expected_pos)
    end
    pos = new_pos

    -- local dir = DIRECTIONS[math.random(#DIRECTIONS)]
    local dir = defines.direction.east
    controller:walk(dir)
    expected_pos = controller:simulate_walk(pos, dir)
    unexpected_pos = controller:simulate_walk_no_collisions(pos, dir)
  end

  controller:add_listener(continue)
end

local function test()
  test_selection_diff()
  test_priority_queue()
end

commands.add_command("start", "Give AI control over the player", start)
commands.add_command("stop", "Stops AI and any running actions in Controller", stop)
commands.add_command("pos", "Show current position", pos)
commands.add_command("entities", "Show entities around", entities)
commands.add_command("all_entities", "Show all known entities", all_entities)
commands.add_command("recipes", "Show all known recipes", recipes)
commands.add_command("mine", "Mine the nearest minable tile", mine)
commands.add_command("walk", "Walk in the direction given by two relative coordinates", walk)
commands.add_command("test", "Run unit tests", test)
commands.add_command("test-walk", "Investigate how walking works", test_walk)