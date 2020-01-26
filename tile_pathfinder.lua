local box = require "box"
local log = require("util").log
local pos = require "pos"
local pqueue = require "pqueue"
local PriorityQueue = pqueue.PriorityQueue

local DIRECTIONS = {}
DIRECTIONS[defines.direction.north] = pos.pack_delta(0, -1);
DIRECTIONS[defines.direction.northeast] = pos.pack_delta(1, -1);
DIRECTIONS[defines.direction.east] = pos.pack_delta(1, 0);
DIRECTIONS[defines.direction.southeast] = pos.pack_delta(1, 1);
DIRECTIONS[defines.direction.south] = pos.pack_delta(0, 1);
DIRECTIONS[defines.direction.southwest] = pos.pack_delta(-1, 1);
DIRECTIONS[defines.direction.west] = pos.pack_delta(-1, 0);
DIRECTIONS[defines.direction.northwest] = pos.pack_delta(-1, -1);


local TileNode = {}
TileNode.__index = TileNode

function TileNode.new(position, distance_from_start, distance_to_goal,
                       previous_node)
    local self = {
        pos = position,
        distance_from_start = distance_from_start,
        -- This the best low estimate for the distance. It can only grow.
        distance_to_goal = distance_to_goal,
        -- This is the low estimate for the distance that was used when this
        -- node was added to the priority queue. When the node is taken out of
        -- the priortity queue, if this value is the same as distance, then the
        -- distance is guaranteed to be minimal in the queue. Otherwise,
        -- the distance was updated after adding to the queue, and it has to be
        -- re-pushed.
        queue_distance = distance_from_start + distance_to_goal,
        -- Previous node in the optimial path from start to this node.
        previous_node = previous_node,
        final = false
    }
    setmetatable(self, TileNode)
    return self
end

TileNode.__eq = function(a, b) return a.queue_distance == b.queue_distance end

TileNode.__lt = function(a, b) return a.queue_distance < b.queue_distance end

TileNode.__le = function(a, b) return a.queue_distance <= b.queue_distance end

function TileNode:update_distance()
    self.queue_distance = self.distance_from_start + self.distance_to_goal
end

local function get_tile_center(point)
    local x, y = pos.unpack(point)
    x = math.floor(x) + 0.5
    y = math.floor(y) + 0.5
    return pos.pack(x, y)
end

local TilePathfinder = {}
TilePathfinder.__index = TilePathfinder

function TilePathfinder.new(controller, goals_pset, goal_radius)
    assert(controller ~= nil)
    assert(goals_pset ~= nil)
    assert(type(goal_radius) == "number")
    local self = {}
    setmetatable(self, TilePathfinder)
    self.controller = controller
    self.goals_pset = goals_pset
    self.goal_radius = goal_radius
    -- Position -> QueueNode
    self.distances = {}
    return self
end

function TilePathfinder:_estimate(from)
    local from = pos.pack(from)
    local dist = self.goals_pset:min_l2_dist(from)
    return math.max(0, dist - self.goal_radius)
end

function TilePathfinder:_reconstruct_path(to)
    local node = to
    local dist = self.distances[node.pos]
    while node.previous_node ~= nil do
        local delta = node.previous_node.pos - node.pos
        node = node.previous_node

        dist = dist + pos.delta_len(delta)
        self.distances[node.pos] = dist
    end
end

function TilePathfinder:_tile_passable(point)
    local tile = self.controller:get_tile(point)
    if tile.collides_with("player-layer") then return false end
    local x, y = pos.unpack(point)
    local entities = self.controller:entities_filtered{area={{x-0.1, y-0.1}, {x+0.1, y+0.1}},
       collision_mask="player-layer"}
    for _, entity in ipairs(entities) do
        if entity.name ~= "character" and box.contains(entity.bounding_box, point) then
            return false
        end
    end

    return true
end

-- Calculate distance to the closest tile center within the goal_radius from
-- one of the goals. The distance is calculated as travelled along 8 directions.
function TilePathfinder:min_distance(from)
    assert(from ~= nil)
    local from = get_tile_center(from)
    if not self:_tile_passable(from) then return nil end
    local cached_distance = self.distances[from]
    if cached_distance ~= nil then return cached_distance end

    local start_node = TileNode.new(from, 0, self:_estimate(from), nil)
    local visited = {}
    local queue = PriorityQueue.new()
    queue:push(start_node)
    local last_node = nil

    while not queue:empty() do
        local node = queue:pop()
        if from == pos.pack(106.5, -15.5) then
            log("pos", pos.norm(node.pos), "distance_from_start", node.distance_from_start,
            "disatnce_to_goal", node.distance_to_goal, "visited", visited[node.pos] ~= nil,
            "known", self.distances[node.pos])
        end
        if visited[node.pos] ~= nil then goto continue end
        visited[node.pos] = true

        local cached_distance = nil
        if node.distance_to_goal == 0 then
            self.distances[node.pos] = 0
            cached_distance = 0
        else
            cached_distance = self.distances[node.pos]
        end

        if cached_distance ~= nil then
            self:_reconstruct_path(node)
            break
        end

        for dir, delta in pairs(DIRECTIONS) do
            local new_pos = node.pos + delta
            assert(new_pos == get_tile_center(new_pos))
            if self:_tile_passable(new_pos) then
                local cached = self.distances[new_pos]
                local estimate = (cached == nil) and self:_estimate(new_pos) or cached;
                local new_node = TileNode.new(
                    new_pos, node.distance_from_start + pos.delta_len(delta),
                                            estimate, node)
                queue:push(new_node)
            end
        end

        ::continue::
    end

    return self.distances[from]
end

return {
    DIRECTIONS = DIRECTIONS,
    TilePathfinder = TilePathfinder,
    get_tile_center = get_tile_center,
}