local box = require "box"
local log = require("util").log
local pos = require("pos")

-- Simulate walking and collisions
local DIR_TO_VELOCITY = {}
DIR_TO_VELOCITY[defines.direction.north] = pos.pack_delta(0, -38 / 256)
DIR_TO_VELOCITY[defines.direction.northeast]	= pos.pack_delta(27 / 256, -27 / 256)
DIR_TO_VELOCITY[defines.direction.east] = pos.pack_delta(38 / 256, 0)
DIR_TO_VELOCITY[defines.direction.southeast]	= pos.pack_delta(27 / 256, 27 / 256)
DIR_TO_VELOCITY[defines.direction.south]	= pos.pack_delta(0, 38 / 256)
DIR_TO_VELOCITY[defines.direction.southwest]	= pos.pack_delta(-27 / 256, 27 / 256)
DIR_TO_VELOCITY[defines.direction.west] = pos.pack_delta(-38 / 256, 0)
DIR_TO_VELOCITY[defines.direction.northwest] = pos.pack_delta(-27 / 256, -27 / 256)

local DIRECTIONS = {}
for dir, _ in pairs(DIR_TO_VELOCITY) do
  table.insert(DIRECTIONS, dir)
end

local WalkSimulator = {}
WalkSimulator.__index = WalkSimulator

function WalkSimulator.new(controller)
  assert(controller ~= nil)
  local self = {}
  setmetatable(self, WalkSimulator)
  self.controller = controller
  self.char_collision_box = self.controller:character().prototype.collision_box
  self.entity_cache = {}
  self.cache_box = nil
  self.walk_calls = 0
  self.cache_updates = 0
  return self
end

-- Expects packed position. Returns new position after moving in the direction `dir`, without any
-- collisions.
function WalkSimulator:walk_no_collisions(player_pos, dir)
  if dir == nil then return player_pos end
  assert(type(player_pos) == "number")
  return player_pos + DIR_TO_VELOCITY[dir]
end

function WalkSimulator:reset()
  self.cache_box = nil
  self.walk_calls = 0
  self.cache_updates = 0
end

function WalkSimulator:log()
  log("entities =", #self.entity_cache, "cache_box =", self.cache_box,
      "walk_calls =", self.walk_calls, "cache_updates =", self.cache_updates)
end

function WalkSimulator:_update_cache(player_box)
  if self.cache_box ~= nil and box.covers(self.cache_box, player_box) then return end

  self.cache_updates = self.cache_updates + 1
  local px1, py1, px2, py2 = box.unpack(player_box)
  local nx1, ny1, nx2, ny2
  if self.cache_box == nil then
    nx1, ny1, nx2, ny2 = px1, py1, px2, py2
  else
    local cx1, cy1, cx2, cy2 = box.unpack(self.cache_box)
    nx1 = math.min(cx1, px1 - 0.5)
    ny1 = math.min(cy1, py1 - 0.5)
    nx2 = math.max(cx2, px2 + 0.5)
    ny2 = math.max(cy2, py2 + 0.5)
  end

  local new_box = box.new_norm(nx1, ny1, nx2, ny2)
  self.cache_box = new_box
  self.entity_cache = {}

  for _, entity in ipairs(self.controller:entities_in_box(new_box)) do
    -- local entity_box = box.move(entity.prototype.collision_box, entity.position)
    local entity_box = entity.bounding_box
    if entity.name ~= "player" and
       entity.prototype.collision_mask["player-layer"] then
      table.insert(self.entity_cache, entity_box)
    end
  end
end

-- Assuming that the character is in the position `from`, simulate walking for one tick in the
-- direction (dx, dy). Instead of simulating the game behavior regarding collisions, in case we
-- collide with anything, we return the starting position.
-- Returns the new position.
function WalkSimulator:walk(from, dir)
  self.walk_calls = self.walk_calls + 1
  local new_pos = self:walk_no_collisions(from, dir)
  local new_tile = self.controller:get_tile(new_pos)
  if new_tile.collides_with("player-layer") then
    return from
  end
  local player_box = box.move(self.char_collision_box, new_pos)
  self:_update_cache(player_box)
  for _, entity_box in ipairs(self.entity_cache) do
    if box.overlap_rotated(player_box, entity_box) then return from end
  end
  return new_pos
end

function WalkSimulator:register_prediction(dir)
  local player_pos = pos.pack(self.controller:position())
  self.old_pos = player_pos
  self.prediction_dir = dir
  self.predicted_pos = self:walk(player_pos, dir)
  self.predicted_no_collision = self:walk_no_collisions(player_pos, dir)
end

function WalkSimulator:check_prediction()
  self:reset()  
  if self.predicted_pos == nil then return end
  local player_pos = pos.pack(self.controller:position())
  if player_pos ~= self.predicted_pos then
    if self.old_pos ~= self.predicted_pos or player_pos == self.predicted_no_collision then
      log("Previous position:", pos.norm(self.old_pos))
      log("Expected position:", pos.norm(self.predicted_pos))
      log("Actual position:", pos.norm(player_pos))
      log("Expected delta:", pos.delta(self.old_pos, self.predicted_pos))
      log("Actual delta:", pos.delta(self.old_pos, player_pos))
      local player_box = box.pad(player_pos, 1.0)
      for _, entity in ipairs(self.controller:entities_in_box(player_box)) do
        -- local entity_box = box.move(entity.prototype.collision_box, entity.position)
        local entity_box = entity.bounding_box
        log(entity.name, box.norm(entity_box))
        if entity.name == "cliff" then
          log("cliff orientation: ", entity.cliff_orientation)
          log("orientation: ", entity.orientation)
          log("direction: ", entity.orientation)
        end
      end
    end
    assert(self.old_pos == self.predicted_pos)
    assert(player_pos ~= self.predicted_no_collision)

    local old_x, old_y = pos.unpack(self.old_pos)
    local new_x, new_y = pos.unpack(player_pos)
    local predicted_x, predicted_y = pos.unpack(self.predicted_no_collision)
    local dx = new_x - old_x
    local dy = new_y - old_y
    local pdx = predicted_x - old_x
    local pdy = predicted_y - old_y
    
    assert(dx == 0 or dx == pdx)
    assert(dy == 0 or dy == pdy)

  end
  self.predicted_pos = nil
end

return {
  DIRECTIONS = DIRECTIONS,
  WalkSimulator = WalkSimulator,
  test = test,
}