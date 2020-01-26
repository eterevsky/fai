local util = require "util"
local log = util.log
local pos = require "pos"
local pqueue = require "pqueue"
local PriorityQueue = pqueue.PriorityQueue
local PointSet = require("pointset").PointSet
local tile_pathfinder = require "tile_pathfinder"
local walking = require "walking"

local DIAG_SPEED = walking.DIAG_SPEED
local DIRECTIONS = walking.DIRECTIONS
local SPEED = walking.SPEED
local WalkSimulator = walking.WalkSimulator

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
        cost = cost
    }
    setmetatable(self, PathNode)
    return self
end

-- Returns the estimated distance from the node position to the goals.
function PathNode:remaining_steps() return self.cost - self.steps end

PathNode.__eq = function(a, b) return a.cost == b.cost end

PathNode.__lt = function(a, b) return a.cost < b.cost end

PathNode.__le = function(a, b) return a.cost <= b.cost end

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

function Pathfinder:_estimate_by_tiles(from)
    local min_distance = math.huge
    local center = tile_pathfinder.get_tile_center(from)
    local cx, cy = pos.unpack(center)
    local best_dir = nil
    local best_local_steps = nil
    for dir, delta in pairs(tile_pathfinder.DIRECTIONS) do
        local neighbor_center = center + delta
        local nx, ny = pos.unpack(neighbor_center)

        local x, y = pos.unpack(from)
        local local_distance
        if cx ~= nx and cy ~= ny then
            local_distance = pos.dist_l2(from, neighbor_center)
        else
            local_distance = math.max(math.abs(x - nx), math.abs(y - ny))
        end

        local tile_distance = self.tile_pathfinder:min_distance({nx, ny})
        if tile_distance == nil then goto continue end
        local distance = tile_distance + local_distance

        -- if dir == 1 or dir == 2 or dir == 6 then
        --     log("  dir", dir, "neighbor", pos.norm(neighbor_center), "tile_distance", tile_distance, "local_distance", local_distance, "distance", distance)
        -- end

        if distance < min_distance then
            min_distance = distance
            best_dir = dir
            best_local_distance = local_distance
        end
        ::continue::
    end

    local min_steps = math.ceil(min_distance / SPEED)
    local neighbor_center = center + tile_pathfinder.DIRECTIONS[best_dir]
-- log("from", pos.norm(from), "neighbor_center", pos.norm(neighbor_center), "min_distance", min_distance, "best_dir",
--         best_dir, "min_steps", math.ceil(min_steps), "best_local_distance", best_local_distance)

    return min_steps
end

-- Low estimate for the number of ticks to reach a point within the given
-- distance from any of the goals.
function Pathfinder:_estimate_steps(from)
    local from = pos.pack(from)
    local cached_steps = self.steps_cache[from]
    if cached_steps ~= nil then
        self.cache_hits = self.cache_hits + 1
        return cached_steps
    else
        self.cache_misses = self.cache_misses + 1
    end

    local dist = self.goals_pset:min_l2_dist(from)
    local min_steps = math.ceil((dist - self.goal_radius) / SPEED)

    if min_steps > 0 then
        local tile_estimation = self:_estimate_by_tiles(from)
        min_steps = math.max(min_steps, tile_estimation)
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
    self.tile_pathfinder = tile_pathfinder.TilePathfinder.new(self.controller,
                                                              self.goals_pset,
                                                              self.goal_radius)
end

function Pathfinder:clear_goals()
    self.goals = {}
    self.goals_pset = nil
    self.steps_cache = {}
    self.cache_hits = 0
    self.cache_missed = 0
    self.tile_pathfinder = nil
end

function Pathfinder:has_goals() return #self.goals > 0 end

-- Initialize the queue and visited table, or use them from the previous iteration. If the char
-- has moved, the queue is invalidated.
function Pathfinder:_init_queue(start_pos)
    if self.visited ~= nil and self.queue ~= nil then
        local start_node = self.visited[start_pos]
        if start_node ~= nil and start_node.steps == 0 then
            log("Inherited the queue with", self.queue:size(), "elements and",
                util.table_size(self.visited), "visited nodes")
            return
        end
    end

    self.queue = PriorityQueue.new()
    local start_cost = self:_estimate_steps(start_pos)
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
    -- log("Distance from the current tile:",
    --     self.tile_pathfinder:min_distance(start_pos))
    -- log("Direct distance:",
    --     self.goals_pset:min_l2_dist(start_pos) - self.goal_radius)
    -- log("Estimated steps:", min_rem_steps)
    local queue, visited = self.queue, self.visited
    local counter = 0
    local closest_node

    while not queue:empty() and counter < 128 and min_rem_steps > 0 do
        local node = queue:pop()
        assert(node ~= nil)
        if visited[node.pos] == nil then
            visited[node.pos] = node
            counter = counter + 1

            for idir, dir in ipairs(DIRECTIONS) do
                local new_pos = self.simulator:walk(node.pos, dir)
                if new_pos ~= node.pos then
                    local new_rem_steps = self:_estimate_steps(new_pos)
                    local new_node = PathNode.new(new_pos, node.pos, dir,
                                                  node.steps + 1,
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

    if self.closest_node_distance ~= nil and closest_node:remaining_steps() >
        self.closest_node_distance then
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

    log(#self.reversed_path, " + ", min_rem_steps, " steps", " (cache: ",
        self.cache_hits, "/", self.cache_misses, ")")

    return table.remove(self.reversed_path)
end

function Pathfinder:debug(goals, goal_radius)
    self:set_goals(goals, goal_radius)
    local start = pos.pack(self.controller:position())
    log("Current pos:", pos.norm(start))
    log("Distance from the current tile:",
        self.tile_pathfinder:min_distance(start))
    log("Direct distance:",
        self.goals_pset:min_l2_dist(start) - self.goal_radius)
    log("Estimated steps:", self:_estimate_steps(start))

    for _, dir in ipairs(DIRECTIONS) do
        local new_pos = self.simulator:walk(start, dir)
        if new_pos == start then
            log("Direction", dir, "blocked")
        else
            log("Direction", dir)
            local new_rem_steps = self:_estimate_steps(new_pos)
        end
    end
end

return {Pathfinder = Pathfinder}
