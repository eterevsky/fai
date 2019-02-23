local log = require("util").log
local pos = require "pos"
local pqueue = require "pqueue"
local PriorityQueue = pqueue.PriorityQueue
local walking = require "walking"
local WalkSimulator = walking.WalkSimulator
local DIRECTIONS = walking.DIRECTIONS

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
    if visited[node.pos] == nil then
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
    end
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

return {
  Pathfinder = Pathfinder   
}