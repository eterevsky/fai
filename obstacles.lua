-- Keeps track of the obstacles and can answer a question of whether character's
-- path will intersec any.

local box = require "box"
local log = require("util").log
local polygon = require "polygon"
local pos = require "pos"

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
-- p is *already aligned* by 4x4 grid.
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
    local cx, cy = math.floor(px / 4) * 4 + 2, math.floor(py / 4) * 4 + 2

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

return obstacles