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
  return self
end

-- Expects packed position. Returns new position after moving in the direction `dir`, without any
-- collisions.
function WalkSimulator:walk_no_collisions(player_pos, dir)
  if dir == nil then return player_pos end
  assert(type(player_pos) == "number")
  return player_pos + DIR_TO_VELOCITY[dir]
end

-- Assuming that the character is in the position `from`, simulate walking for one tick in the
-- direction (dx, dy). Instead of simulating the game behavior regarding collisions, in case we
-- collide with anything, we return the starting position.
-- Returns the new position.
function WalkSimulator:walk(from, dir)
  local new_pos = self:walk_no_collisions(from, dir)
  local new_tile = self.controller:get_tile(new_pos)
  if new_tile.collides_with("player-layer") then
    return from
  end
  local player_box = box.move(self.char_collision_box, new_pos)
  for _, entity in ipairs(self.controller:entities_in_box(player_box)) do
    local entity_box = box.move(entity.prototype.collision_box, entity.position)
    if entity.name ~= "player" and
       entity.prototype.collision_mask["player-layer"] and
       box.overlap(player_box, entity_box) then
      return from
    end
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
  if self.predicted_pos == nil then return end
  local player_pos = pos.pack(self.controller:position())
  if player_pos ~= self.predicted_pos then
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
end

return {
  DIRECTIONS = DIRECTIONS,
  WalkSimulator = WalkSimulator,
  test = test,
}