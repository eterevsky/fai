-- Polygon is represented by a list of (usually packed) positions representing
-- vertices in counter-clockwise direction.

local pos = require "pos"
local tests = require "tests"
local log = require("util").log

local polygon = {}
local Polygon = {}
Polygon.__index = Polygon
polygon.Polygon = Polygon

function Polygon.new(vertices)
  local self = {}
  setmetatable(self, Polygon)

  if vertices ~= nil then
    for _, v in ipairs(vertices) do
      self:add_vertice(v)
    end
  end

  return self
end

function Polygon:add_vertice(v)
  table.insert(self, pos.pack(v))
end

-- Checks that the polygon is convex, not self-intersecting, doesn't have 3
-- vertices lying on the same straight line, and that the vertices are
-- enumerated in clockwise order (if the y axis looks down).
function Polygon:is_convex()
  assert(#self >= 3)
  for i, v1 in ipairs(self) do
    assert(v1 ~= nil)
    local v2 = self[i+1] or self[1]

    local x1, y1 = pos.unpack(v1)
    local x2, y2 = pos.unpack(v2)
    local edge_x, edge_y = x2 - x1, y2 - y1

    for j, v in ipairs(self) do
      if j ~= i and j ~= i+1 and (i ~= #self or j ~= 1) then
        local x, y = pos.unpack(v)
        local vertice_x, vertice_y = x - x1, y - y1

        if edge_x * vertice_y - edge_y * vertice_x <= 0 then return false end
      end
    end
  end

  return true
end

-- Checks whether the point is contained in the interior or on the border 
-- of the polygon.
function Polygon:contains(p)
  local px, py = pos.unpack(p)
  local prevx, prevy = pos.unpack(self[#self])
  for _, v in ipairs(self) do
    local x, y = pos.unpack(v)
    if (x - prevx) * (py - prevy) - (y - prevy) * (px - prevx) < 0 then
      return false
    end
    prevx, prevy = x, y
  end
  return true
end

tests.register_test("polygon.is_convex", function()
  assert(Polygon.new({{0, 0}, {1, 2}, {-5, -1}}):is_convex())
  assert(not Polygon.new({{0, 0}, {-5, -1}, {1, 2}}):is_convex())

  assert(Polygon.new({{0, 0}, {1, 2}, {-2, 3}, {-5, -1}}):is_convex())
  assert(not Polygon.new({{0, 0}, {1, 2}, {-1, 0}, {-5, -1}}):is_convex())
  assert(not Polygon.new({{0, 0}, {1, 2}, {-1, 1}, {-5, -1}}):is_convex())
  assert(not Polygon.new({{0, 0}, {1, 2}, {-5, -2}, {-5, -1}}):is_convex())
end)

tests.register_test("polygon.contains", function()
  local poly = Polygon.new({{1, 0}, {3, 2}, {4, 4}, {3, 4}, {0, 2}})

  -- -- Check vertices
  -- for _, v in ipairs(poly) do
  --   assert(poly:contains(v))
  -- end

  -- Points on sides
  assert(poly:contains({2, 1}))
  assert(poly:contains({3.5, 3}))
  assert(poly:contains({0.5, 1}))

  -- Interior
  assert(poly:contains({1, 1}))
  assert(poly:contains({3.5, 3.5}))

  assert(not poly:contains({0, 0}))
  assert(not poly:contains({0, 1}))
  assert(not poly:contains({2.5, 1}))
  assert(not poly:contains({4, 3}))
  assert(not poly:contains({1.5, 3.5}))
  assert(not poly:contains({-1, 1}))
  assert(not poly:contains({-1000, -1000}))
  assert(not poly:contains({-1000, 1000}))
  assert(not poly:contains({1000, -1000}))
  assert(not poly:contains({1000, 1000}))
end)

return polygon