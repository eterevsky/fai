-- Polygon is represented by a list of (usually packed) positions representing
-- vertices in counter-clockwise direction.

local pos = require "pos"
local tests = require "tests"

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

-- Checks whether the polygon intersects with the line segment from p1 to p2.
-- If it is, then either both points lie inside, or the segment (p1, p2)
-- has to intersect one of the polygon edges.
function Polygon:intersects(p1, p2)
  local x1, y1 = pos.unpack(p1)
  local x2, y2 = pos.unpack(p2)

  local prevx, prevy = pos.unpack(self[#self])
  local contains1 = true

  for _, v in ipairs(self) do
    local x, y = pos.unpack(v)
    if contains1 and (x - prevx) * (y1 - prevy) -
                     (y - prevy) * (x1 - prevx) < 0 then
      contains1 = false
    end

    if ((x2 - x1) * (y - y1) - (x - x1) * (y2 - y1)) *
       ((x2 - x1) * (prevy - y1) - (prevx - x1) * (y2 - y1)) <= 0 and
       ((x - prevx) * (y1 - prevy) - (x1 - prevx) * (y - prevy)) *
       ((x - prevx) * (y2 - prevy) - (x2 - prevx) * (y - prevy)) <= 0 then
      -- Segment from p1 to p2 intersects the edge from (xprev yprev) to (x, y)
      return true
    end

    prevx, prevy = x, y
  end

  return contains1
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

  -- Check vertices
  for _, v in ipairs(poly) do
    assert(poly:contains(v))
  end

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

tests.register_test("polygon.intersects", function()
  local poly = Polygon.new({{1, 0}, {3, 2}, {4, 4}, {3, 4}, {0, 2}})

  local deltas = {
    pos.pack_delta(1, 0),
    pos.pack_delta(0, 1),
    pos.pack_delta(-1, 0),
    pos.pack_delta(0, -1)}

  -- Segments from vertices
  for _, v in ipairs(poly) do
    for _, d in ipairs(deltas) do
      assert(poly:intersects(v, v + d))
      assert(poly:intersects(v + d, v))
    end
  end

  -- Segments with one side on the edge
  assert(poly:intersects({2, 1}, {3, 0}))
  assert(poly:intersects({3, 0}, {2, 1}))
  assert(poly:intersects({3.5, 3}, {4, 2}))
  assert(poly:intersects({4, 2}, {3.5, 3}))
  assert(poly:intersects({0.5, 1}, {0, 0}))
  assert(poly:intersects({0, 0}, {0.5, 1}))
  assert(poly:intersects({0.5, 1}, {0, 0}))

  -- Interior
  assert(poly:intersects({1, 1}, {3, 2}))
  assert(poly:intersects({1, 2}, {2, 2}))

  -- One in, one out
  assert(poly:intersects({1, 1}, {3, 1}))
  assert(poly:intersects({3, 1}, {1, 1}))
  assert(poly:intersects({0.5, 1}, {-2, -2}))
  assert(poly:intersects({-2, -2}, {0.5, 1}))

  -- Both out
  assert(poly:intersects({-2, 3}, {5, 3}))
  assert(poly:intersects({5, 3}, {-2, 3}))
  assert(poly:intersects({0, 5}, {4, -1}))
  assert(poly:intersects({4, -1}, {0, 5}))

  assert(not poly:intersects({0, 5}, {5, 5}))
  assert(not poly:intersects({5, 5}, {0, 5}))
  assert(not poly:intersects({5, 4}, {5, 0}))
  assert(not poly:intersects({5, 0}, {5, 4}))
  assert(not poly:intersects({-1, 1}, {1, -1}))
  assert(not poly:intersects({1, -1}, {-1, 1}))
end)

return polygon