-- Polygon is represented by a list of (usually packed) positions representing
-- vertices in counter-clockwise direction.

local box = require "box"
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

function Polygon.from_box(b)
  local angle = 2 * math.pi * b.orientation
  local cos = math.cos(angle)
  local sin = math.sin(angle)

  -- Before rotation
  local bx1, by1, bx2, by2 = box.unpack(b)

  -- Center of the box
  local cx, cy = (bx1 + bx2) / 2, (by1 + by2) / 2

  local rotate = function(x, y)
    -- Vector from the center of the box to the point
    local vx, vy = x - cx, y - cy

    -- Rotate the point into the box coordinates
    local rx, ry = cos * vx - sin * vy, sin * vx + cos * vy
    if rx > 0 then
      rx = math.ceil(256 * rx) / 256
    else
      rx = math.floor(256 * rx) / 256
    end

    if ry > 0 then
      ry = math.ceil(256 * ry) / 256
    else
      ry = math.floor(256 * ry) / 256
    end

    return pos.pack(cx + rx, cy + ry)
  end

  local box_poly = Polygon.new()

  box_poly:add_vertice(rotate(bx1, by1))
  box_poly:add_vertice(rotate(bx2, by1))
  box_poly:add_vertice(rotate(bx2, by2))
  box_poly:add_vertice(rotate(bx1, by2))

  assert(box_poly:is_convex())
  return box_poly
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

-- Expand the polygon to contain the set of points such that a rectangle with
-- dimensions b (box) centered in those points will intersect with the original
-- polygon. In other words it is such that polygon `poly` intersects with
-- rectangle `b` iff `poly:expand(b)` contains the central point of `b`.
--
-- Note: if there are horizontal or vertical edges, it will generate some extra
-- vertices lying on the edges.
function Polygon:expand(b)
  local bx1, by1, bx2, by2 = box.unpack(b)
  local w = (bx2 - bx1) / 2
  local h = (by2 - by1) / 2

  local exp_poly = Polygon.new()
  local prevx, prevy = pos.unpack(self[#self])

  for _, v in ipairs(self) do
    local x, y = pos.unpack(v)

    local dx, dy
    if y >= prevy then dx = w else dx = -w end
    if x >= prevx then dy = -h else dy = h end

    local p1 = pos.pack(prevx + dx, prevy + dy)

    if #exp_poly == 0 or exp_poly[#exp_poly] ~= p1 then
      exp_poly:add_vertice(p1)
    end

    local p2 = pos.pack(x + dx, y + dy)
    exp_poly:add_vertice(p2)

    prevx, prevy = x, y
  end

  return exp_poly
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

tests.register_test("polygon.from_box", function()
  local b = {{1, 1}, {4, 3}}
  b.orientation = 0

  local rotated0 = Polygon.from_box(b)
  assert(rotated0[1] == pos.pack(1, 1))
  assert(rotated0[2] == pos.pack(4, 1))
  assert(rotated0[3] == pos.pack(4, 3))
  assert(rotated0[4] == pos.pack(1, 3))

  b.orientation = 0.25
  local rotated1 = Polygon.from_box(b)
  assert(rotated1[1] == pos.pack(3.5, 0.5))
  assert(rotated1[2] == pos.pack(3.5, 3.5))
  assert(rotated1[3] == pos.pack(1.5, 3.5))
  assert(rotated1[4] == pos.pack(1.5, 0.5))
end)

tests.register_test("polygon.expand", function()
  local poly = Polygon.new{{2, 1}, {6, 3}, {5, 5}, {1, 3}}
  local exp = poly:expand({{0, 0}, {2, 4}})

  assert(#exp == 8)
  assert(exp[3] == pos.pack(3, -1))
  assert(exp[4] == pos.pack(7, 1))
  assert(exp[5] == pos.pack(7, 5))
  assert(exp[6] == pos.pack(6, 7))
  assert(exp[7] == pos.pack(4, 7))
  assert(exp[8] == pos.pack(0, 5))
  assert(exp[1] == pos.pack(0, 1))
  assert(exp[2] == pos.pack(1, -1))
end)

return polygon