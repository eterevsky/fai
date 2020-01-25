local util = require "util"
local log = util.log
local pos = require "pos"
local pqueue = require "pqueue"
local PriorityQueue = pqueue.PriorityQueue
local PointSet = require("pointset").PointSet
local walking = require "walking"

local DIAG_SPEED = walking.DIAG_SPEED
local DIRECTIONS = walking.DIRECTIONS
local SPEED = walking.SPEED
local WalkSimulator = walking.WalkSimulator
local _enable_pointset = false

local function enable_pointset(value)
  _enable_pointset = value
end

local PathNode = {}
PathNode.__index = PathNode

-- steps is the number of steps already taken
-- cost is the sum of `steps` plus the low estimate for the remaining part
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

-- local CoarsePathfinder = {}
-- CoarsePathfinder.__index = CoarsePathfinder

-- function CoarsePathfinder.new(controller)
--   local self = {}
--   setmetatable(self, CoarsePathfinder)
--   self.controller = controller
--   self.goals = {}
--   self.distance = 1.0
--   self.steps_cache = {}
-- end

-- Pathfinder implements walking to reach certain goals.
local Pathfinder = {}
Pathfinder.__index = Pathfinder

function Pathfinder.new(controller)
  local self = {}
  setmetatable(self, Pathfinder)
  self.controller = controller
  -- self.coarse = CoarsePathfinder.new(controller)
  self.goals = {}
  self.goals_pset = nil
  self.distance = 1.0

  -- Every next step should lead to the closest node that is no further from the goals than on the
  -- previous step
  self.closest_node_distance = nil

  -- Encoded position -> distance to goals
  self.steps_cache = {}
  self.cache_hits = 0
  self.cache_misses = 0

  -- A reversed list of several next moves.
  self.reversed_path = {}

  self.simulator = WalkSimulator.new(controller)
  return self
end

-- function Pathfinder:_find_coarse_path(start, finish)
--   local visited = {}
--   local queue = PriorityQueue.new()
--   local start = pos.pack(start)
--   start_node = PathNode.new(start, nil, nil, 0, self:_estimate_steps(start))
--   queue:push(start_node)

--   while not queue:empty() do
--   end
-- end

-- function Pathfinder:_estimate_from_coarse_path(start)
-- end

-- Low estimate for the number of ticks to reach a point within the given distance from any of the
-- goals.
function Pathfinder:_estimate_steps(from)
  local from = pos.pack(from)
  local cached_steps = self.steps_cache[from]
  if cached_steps ~= nil then
    self.cache_hits = self.cache_hits + 1
    return cached_steps
  else
    self.cache_misses = self.cache_misses + 1
  end

  local fromx, fromy = pos.unpack(from)
  local min_steps = math.huge

  if _enable_pointset then
    local dist = self.goals_pset:min_l2_dist(from)
    min_steps = math.ceil((dist - self.goal_radius) / SPEED)
  else
    for _, goal in ipairs(self.goals) do
      local goalx, goaly = pos.unpack(goal)
      local dx = math.abs(goalx - fromx)
      local dy = math.abs(goaly - fromy)
      if dx < dy then
        dx, dy = dy, dx
      end

      local steps = dy / DIAG_SPEED + (dx - dy) / SPEED - self.goal_radius_steps
      steps = math.ceil(steps)
      if steps <= 0 then
        local dist = pos.dist_l2(from, goal)
        if dist <= self.goal_radius_steps then
          steps = 0
        else 
          steps = math.ceil((dist - self.distance) / SPEED)
        end
      end
      if steps < min_steps then min_steps = steps end
    end
  end

  self.cache_misses = self.cache_misses + 1
  self.steps_cache[from] = min_steps

  return min_steps
end

function Pathfinder:set_goals(goals, goal_radius)
  self.goals = goals
  self.goals_pset = PointSet.new(goals)
  self.goal_radius = goal_radius
  self.goal_radius_steps = math.floor(goal_radius / SPEED)
  
  self.steps_cache = {}
  self.cache_hits = 0
  self.cache_misses = 0
end

function Pathfinder:clear_goals()
  self.goals = {}
  self.goals_pset = nil
  self.steps_cache = {}
  self.cache_hits = 0
  self.cache_missed = 0
end

function Pathfinder:has_goals()
  return #self.goals > 0
end

-- Initialize the queue and visited table, or use them from the previous iteration. If the char
-- has moved, the queue is invalidated.
function Pathfinder:_init_queue(start_pos)
  if self.visited ~= nil and self.queue ~= nil then
    local start_node = self.visited[start_pos]
    if start_node ~= nil and start_node.steps == 0 then
      log("Inherited the queue with", self.queue:size(),
          "elements and", util.table_size(self.visited), "visited nodes")
      return
    end
  end

  self.queue = PriorityQueue.new()
  start_node = PathNode.new(start_pos, nil, nil, 0, start_cost)
  self.queue:push(start_node)
  -- visited position -> PathNode
  self.visited = {}
  -- log("Creating new queue with", self.queue:size(),
  -- "elements and", util.table_size(self.visited), "visited nodes")

  self.simulator:reset()
end

function Pathfinder:_build_path(to_node)
  local node = to_node
  self.reversed_path = {}
  while node ~= nil and node.dir ~= nil do
    table.insert(self.reversed_path, node.dir)
    node = self.visited[node.prev_enc]
  end
end

-- A* search that finds the fastest path to any position from goals, ending within the goal_radius
-- of it.
function Pathfinder:next_step()
  self.cache_hits = 0
  self.cache_misses = 0

  local start_pos = pos.pack(self.controller:position())
  local min_rem_steps = self:_estimate_steps(start_pos)
  self:_init_queue(start_pos)
  local queue, visited = self.queue, self.visited
  local counter = 0
  local closest_node

  while not queue:empty() and counter < 512 and min_rem_steps > 0 do
    local node = queue:pop()
    assert(node ~= nil)
    if visited[node.pos] == nil then
      visited[node.pos] = node
      counter = counter + 1

      for _, dir in ipairs(DIRECTIONS) do
        local new_pos = self.simulator:walk(node.pos, dir)
        if new_pos ~= node.pos then
          local new_rem_steps = self:_estimate_steps(new_pos)
          local new_node = PathNode.new(new_pos, node.pos, dir, node.steps + 1,
                                        new_rem_steps + node.steps + 1)
          if new_rem_steps < min_rem_steps then
            closest_node = new_node
            min_rem_steps = new_rem_steps
          end
          if new_rem_steps == 0 then break end

          queue:push(new_node)
        end
      end
    end
  end

  if closest_node == nil then
    log("Not found. #queue = ", #queue, ", min_rem_steps = ", min_rem_steps,
        "(cache: ", self.cache_hits, "/", self.cache_misses, ")")
    return nil
  end

  if self.closest_node_distance ~= nil and
     closest_node:remaining_steps() > self.closest_node_distance then
    -- log("Closest node too far:", closest_node,
    --     "(cache: ", self.cache_hits, "/", self.cache_misses, ")")
    if #self.reversed_path > 0 then
      return table.remove(self.reversed_path)
    end
    self.old_visited = visited
    self.old_queue = queue
    return nil
  end

  self.closest_node_distance = closest_node:remaining_steps()
  self:_build_path(closest_node)


  log(#self.reversed_path, " + ", min_rem_steps, " steps",
      " (cache: ", self.cache_hits, "/", self.cache_misses, ")")

  return table.remove(self.reversed_path)
end

return {
  Pathfinder = Pathfinder,
  enable_pointset = enable_pointset,
}