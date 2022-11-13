-- Keeps track of the obstacles and can answer a question of whether character's
-- path will intersec any.

local box = require "box"
local log = require("util").log
local polygon = require "polygon"
local pos = require "pos"
local tests = require "tests"

local obstacles = {}
local _controller
local _char_collision_box

-- {padx, pady}, that is used to pad the block when requesting entities from
-- the controller
local _pad

-- A box that is used to expand the entity collision box to check whether it
-- can collide with the character when he's center is in the block. After
-- padding the collision box it's enough to check whether the center of
-- the block lies inside
local _block_pad

-- Packed position -> { updated: ... obstacles: ... }
-- Obstacles field contains a list of expanded collision boxes, represented as
-- either Box or Polygon objects, that intersect even by a single point with
-- the square from (pos.x, pos.y) to (pos.x + 4, pos.y + 4)
local _blocks = {}

function obstacles.init(controller)
  _controller = controller
  _char_collision_box = controller.character().prototype.collision_box
  local cx1, cy1, cx2, cy2 = box.unpack(_char_collision_box)
  _pad = {cx2 - cx1 + 2, cy2 - cy1 + 2}
  _block_pad = {{0, 0}, {4 + cx2 - cx1, 4 + cy2 - cy1}}
end

-- If necessary updates and gets the block at position p. It is assumed that
-- p is *already aligned* by 4x4 grid and packed
function obstacles.get_block(p)
  local block = _blocks[p]

  if block == nil or block.updates < _controller.tick() - 600 then
    block = {
      updated = _controller.tick(),
      obstacles = {}
    }
    _blocks[p] = block

    local px, py = pos.unpack(p)
    -- Center of the block.
    local cx, cy = px + 2, py + 2
    -- local cx, cy = math.floor(px / 4) * 4 + 2, math.floor(py / 4) * 4 + 2

    local b = {left_top = {px - _pad[1], py - _pad[2]},
               right_bottom = {px + 4 + _pad[1], py + 4 + _pad[2]}}
    log("Requesting entities in box:", b)
    local entities = _controller.entities_filtered{
      area = b, collision_mask = "player-layer"
    }

    for _, entity in ipairs(entities) do
      if entity.name == "character" then goto continue end

      local collision_box
      if entity.bounding_box.orientation ~= nil then
        collision_box = polygon.from_box(entity.bounding_box)
      else
        collision_box = box.Box.new(entity.bounding_box)
      end

      -- Collision box, expanded by character size + block size. If it covers
      -- the center of the block, it can collide with a character in the box.
      local wide_exp_collision_box = collision_box:expand(_block_pad)

      -- log("collision_box:", box.norm(collision_box))
      -- log("wide_exp:", box.norm(wide_exp_collision_box))
      -- log("expanded:", box.norm(collision_box:expand(_char_collision_box)))

      if wide_exp_collision_box:contains({cx, cy}) then
        -- Collision box padded by the collision box of the character. The check
        -- of whether the character will collide with the initial collision box is
        -- equivalent to checking whether the center of the character is in this
        -- expanded collision box.
        table.insert(block.obstacles, collision_box:expand(_char_collision_box))
      end

      ::continue::
    end

    _blocks[p] = block
  end

  return block
end

-- Returns the list of block, that covers the segment from p1 to p2.
local function intersecting_blocks(p1, p2)
  local x1, y1 = pos.unpack(p1)
  local x2, y2 = pos.unpack(p2)
  local dx, dy = x2 - x1, y2 - y1
  local blocks = {}

  -- Final block
  local bx2, by2 = math.floor(x2 / 4) * 4, math.floor(y2 / 4) * 4

  while true do
    local bx1, by1 = math.floor(x1 / 4) * 4, math.floor(y1 / 4) * 4
    table.insert(blocks, pos.pack(bx1, by1))

    if bx1 == bx2 and by1 == by2 then break end

    -- Next vertical and horizontal grid lines to be intersected. Can be nil,
    -- if (dx, dy) is horizontal/vertical.
    local next_bx, next_by

    if dx > 0 then
      next_bx = bx1 + 1
    elseif dx < 0 then
      next_bx = bx1 - 1
    end

    if dy > 0 then
      next_by = by1 + 1
    elseif dy < 0 then
      next_by = by1 - 1
    end


  end
end

-- Checks whether a segment from p1 to p2 intersects with any of the obstacles.
function obstacles.intersects(p1, p2)
end

-- function obstacles.draw(p)
--   local block = obstacles.get_block(p)

--   for _, obstacle in ipairs(block.obstacles) do
--     local poly = obstacle:norm_vertices()
--     local vertices = {}
--     for _, v in ipairs(poly) do
--       table.insert(vertices, {target = v})
--     end
--     table.insert(vertices, {target = pos.norm(pos.pack(poly[1]))})
--     rendering.draw_polygon{
--       vertices = vertices,
--       color = {g = 0.5, b = 0.5},
--       surface = game.player.surface}
--   end
-- end

-- tests.register_test("obstacles.intersecting_blocks", function()
--   local blocks = intersecting_blocks({1.125, 2.0}, {3.5, 0.123})
--   assert(#blocks == 1)
--   assert(blocks[1] == pos.pack(0, 0))

--   blocks = intersecting_blocks({3, 2}, {5, -3})
--   assert(#blocks == 3)
--   assert(blocks[1] == pos.pack(0, 0))
--   assert(blocks[2] == pos.pack(0, -4))
--   assert(blocks[3] == pos.pack(4, -4))
-- end)


return obstacles