local pos = require "pos"
local tests = require "tests"
-- local log = require("util").log

local box = {}
local Box = {}
Box.__index = Box
box.Box = Box

-- Can be called as Box.new(x1, y1, x2, y2) or Box.new(p1, p2) or Box.new(b),
-- where p1 = (x1, y1) is the top-left corner, p2 = (x2, y2) is the bottom-right
-- corner, and b is a box representation as an object.
function Box.new(x1_or_p1_or_b, y1_or_p2, x2, y2)
  local self

  if y2 ~= nil then
    self = {pos.pack(x1_or_p1_or_b, y1_or_p2), pos.pack(x2, y2)}
  else
    local p1, p2
    if y1_or_p2 ~= nil then
      p1 = x1_or_p1_or_b
      p2 = y1_or_p2
    else
      p1 = box.left_top or x1_or_p1_or_b[1]
      p2 = box.right_bottom or x1_or_p1_or_b[2]
    end
    self = {pos.pack(p1), pos.pack(p2)}
  end

  setmetatable(self, Box)

  return self
end

function Box:unpack()
  local x1, y1 = pos.unpack(self[1])
  local x2, y2 = pos.unpack(self[2])
  return x1, y1, x2, y2
end

function Box:norm()
  local x1, y1 = pos.unpack(self[1])
  local x2, y2 = pos.unpack(self[2])
  return {left_top = pos.norm(x1, y1), right_bottom = pos.norm(x2, y2)}
end

-- Checks whether the point is contained in the interior or on the border
-- of the box.
function Box:contains(p)
  local x1, y1, x2, y2 = self:unpack()
  local x, y = pos.unpack(p)
  return x1 <= x and x <= x2 and y1 <= y and y <= y2
end

-- Return true if (cx, cy) and (dx, dy) are on the opposite sides of the line
-- through points (ax, ay) and (bx, by).
local function different_sides(ax, ay, bx, by, cx, cy, dx, dy)
  local s1 = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
  local s2 = (bx - ax) * (dy - ay) - (dx - ax) * (by - ay)
  return s1 * s2 <= 0
end

-- Checks whether the polygon intersects with the line segment from p1 to p2.
-- If it is, then either both points lie inside, or the segment (p1, p2)
-- has to intersect one of the polygon edges.
function Box:intersects(p1, p2)
  local x1, y1, x2, y2 = self:unpack()
  local p1x, p1y = pos.unpack(p1)
  local p2x, p2y = pos.unpack(p2)

  return (x1 <= p1x and p1x <= x2 and y1 <= p1y and p1y <= y2) or
         (x1 <= p2x and p2x <= x2 and y1 <= p2y and p2y <= y2) or
         ((p1x - x1) * (p2x - x1) <= 0 and
          different_sides(p1x, p1y, p2x, p2y, x1, y1, x1, y2)) or
         ((p1x - x2) * (p2x - x2) <= 0 and
          different_sides(p1x, p1y, p2x, p2y, x2, y1, x2, y2)) or
         ((p1y - y1) * (p2y - y1) <= 0 and
          different_sides(p1x, p1y, p2x, p2y, x1, y1, x2, y1))
  -- Not checking the 4th side because if neither end of the segment lies inside
  -- and
end

function Box:expand(b)
  local bx1, by1, bx2, by2 = box.unpack(b)
  local w = (bx2 - bx1) / 2
  local h = (by2 - by1) / 2
  local x1, y1, x2, y2 = self:unpack()

  return Box.new(x1 - w, y1 - h, x2 + w, y2 + h)
end

function box.unpack(b)
  local left_top = b.left_top or b[1]
  local right_bottom = b.right_bottom or b[2]
  local x1, y1 = pos.unpack(left_top)
  local x2, y2 = pos.unpack(right_bottom)
  return x1, y1, x2, y2
end

function box.norm(b)
  assert(b ~= nil)
  local x1, y1, x2, y2 = box.unpack(b)
  return {left_top = pos.norm(x1, y1), right_bottom = pos.norm(x2, y2)}
end

function box.new_norm(x1, y1, x2, y2)
  return {left_top = pos.norm(x1, y1), right_bottom = pos.norm(x2, y2)}
end

-- Move a box from (0, 0) to center.
function box.move(b, center)
  local x1, y1, x2, y2 = box.unpack(b)
  local x, y = pos.unpack(center)
  return {pos.pack(x + x1, y + y1), pos.pack(x + x2, y + y2)}
end

function box.contains_rotated(b, p)
  local angle = 2 * math.pi * b.orientation
  local cos = math.cos(angle)
  local sin = math.sin(angle)

  local x, y = pos.unpack(p)

  -- Before rotation
  local bx1, by1, bx2, by2 = box.unpack(b)

  -- Center of the box
  local cx, cy = (bx1 + bx2) / 2, (by1 + by2) / 2

  -- Vector from the center of the box to the point
  local vx, vy = x - cx, y - cy

  -- Rotate the point into the box coordinates
  local rx, ry = cx + cos * vx - sin * vy, cy + sin * vx + cos * vy

  return bx1 <= rx and rx <= bx2 and by1 <= ry and ry <= by2
end

-- Checks whether a point falls within bounding box
function box.contains(b, p)
  if b.orientation ~= nil and b.orientation ~= 0 then
    return box.contains_rotated(b, p)
  end
  local x1, y1, x2, y2 = box.unpack(b)
  local px, py = pos.unpack(p)

  return x1 <= px and px <= x2 and y1 <= py and py <= y2
end

function box.covers(big_box, small_box)
  local bx1, by1, bx2, by2 = box.unpack(big_box)
  local sx1, sy1, sx2, sy2 = box.unpack(small_box)

  return
      bx1 <= sx1 and sx1 <= bx2 and by1 <= sy1 and sy1 <= by2 and bx1 <= sx2 and
          sx2 <= bx2 and by1 <= sy2 and sy2 <= by2
end

-- Checks whether two boxes intersect.
function box.overlap(box1, box2)
  local ax1, ay1, ax2, ay2 = box.unpack(box1)
  local bx1, by1, bx2, by2 = box.unpack(box2)

  return ax1 <= bx2 and ax2 >= bx1 and ay1 <= by2 and ay2 >= by1
end

function box.overlap_rotated(box1, box2_rotated)
  if box2_rotated.orientation == nil or box2_rotated.orientation == 0 then
    return box.overlap(box1, box2_rotated)
  end

  local angle = 2 * math.pi * box2_rotated.orientation
  local cos = math.cos(angle)
  local sin = math.sin(angle)

  local eps = 1 / 1024

  local ax1, ay1, ax2, ay2 = box.unpack(box1)
  ax1 = ax1 - eps
  ay1 = ay1 - eps
  ax2 = ax2 + eps
  ay2 = ay2 + eps

  -- Before rotation
  local bx1, by1, bx2, by2 = box.unpack(box2_rotated)
  bx1 = bx1 - eps
  by1 = by1 - eps
  bx2 = bx2 + eps
  by2 = by2 + eps

  -- Center of box2
  local cx, cy = (bx1 + bx2) / 2, (by1 + by2) / 2

  -- Vectors from the center of box2 to vertices
  local vx1, vy1 = bx1 - cx, by1 - cy
  local vx2, vy2 = bx2 - cx, by2 - cy

  -- Rotated vertices of box2
  local rx1, ry1 = cx + cos * vx1 - sin * vy1, cy + sin * vx1 + cos * vy1
  local rx2, ry2 = cx + cos * vx2 - sin * vy1, cy + sin * vx2 + cos * vy1
  local rx3, ry3 = cx + cos * vx2 - sin * vy2, cy + sin * vx2 + cos * vy2
  local rx4, ry4 = cx + cos * vx1 - sin * vy2, cy + sin * vx1 + cos * vy2

  -- Check projection on the horizontal axis
  if rx1 >= ax2 and rx2 >= ax2 and rx3 >= ax2 and rx4 >= ax2 or rx1 <= ax1 and
      rx2 <= ax1 and rx3 <= ax1 and rx4 <= ax1 then return false end

  -- Check projection on the vertical axis
  if ry1 >= ay2 and ry2 >= ay2 and ry3 >= ay2 and ry4 >= ay2 or ry1 <= ay1 and
      ry2 <= ay1 and ry3 <= ay1 and ry4 <= ay1 then return false end

  -- Projections of box1 vertices on to (cos, sin)
  local ap1 = cos * ax1 + sin * ay1
  local ap2 = cos * ax2 + sin * ay1
  local ap3 = cos * ax2 + sin * ay2
  local ap4 = cos * ax1 + sin * ay2

  -- Projections of rotated box2 on to (cos, sin)
  local rp1 = cos * rx1 + sin * ry1
  local rp2 = cos * rx2 + sin * ry2
  local rp3 = cos * rx3 + sin * ry3
  local rp4 = cos * rx4 + sin * ry4

  -- Check that the points are separated
  if math.max(ap1, ap2, ap3, ap4) < math.min(rp1, rp2, rp3, rp4) or
      math.max(rp1, rp2, rp3, rp4) < math.min(ap1, ap2, ap3, ap4) then
    return false
  end

  -- Projections of box1 on to (-sin, cos)
  ap1 = -sin * ax1 + cos * ay1
  ap2 = -sin * ax2 + cos * ay1
  ap3 = -sin * ax2 + cos * ay2
  ap4 = -sin * ax1 + cos * ay2

  -- Projections of rotated box2 on to (-sin, cos)
  rp1 = -sin * rx1 + cos * ry1
  rp2 = -sin * rx2 + cos * ry2
  rp3 = -sin * rx3 + cos * ry3
  rp4 = -sin * rx4 + cos * ry4

  -- Check that the points are separated
  if math.max(ap1, ap2, ap3, ap4) < math.min(rp1, rp2, rp3, rp4) or
      math.max(rp1, rp2, rp3, rp4) < math.min(ap1, ap2, ap3, ap4) then
    return false
  end

  return true
end

function box.pad(center, padding)
  center = pos.norm(center)
  return {
    {center.x - padding, center.y - padding},
    {center.x + padding, center.y + padding}
  }
end

-- Find a point, that is inside box 1, but not inside box 2. Returns nil, if
-- there is no such point.
function box.selection_diff(box1, box2)
  local ax1, ay1, ax2, ay2 = box.unpack(box1)
  local bx1, by1, bx2, by2 = box.unpack(box2)

  local x = (ax2 + ax1) / 2
  if ax1 < bx1 then
    x = (ax1 + math.min(ax2, bx1)) / 2
  elseif ax2 > bx2 then
    x = (ax2 + math.max(ax1, bx2)) / 2
  end

  local y = (ay2 + ay1) / 2
  if ay1 < by1 then
    y = (ay1 + math.min(ay2, by1)) / 2
  elseif ay2 > by2 then
    y = (ay2 + math.max(ay1, by2)) / 2
  end

  local point = pos.norm(x, y)

  if box.contains(box2, point) then return nil end

  return point
end

tests.register_test("box.test_selection_diff", function()
  local box1 = {{1, 2}, {2, 3}}
  local box2 = {{0, 1}, {3, 4}}
  local p = box.selection_diff(box1, box2)
  assert(p == nil)

  box2 = {{1.5, 1}, {3, 4}}
  p = box.selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box.contains(box1, p))
  assert(not box.contains(box2, p))

  box2 = {{0, 0}, {3, 2.5}}
  p = box.selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box.contains(box1, p))
  assert(not box.contains(box2, p))

  box2 = {{1.125, 2.125}, {1.875, 2.875}}
  p = box.selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box.contains(box1, p))
  assert(not box.contains(box2, p))
end)

tests.register_test("box.test_overlap_rotated", function()
  local box1 = {{-1, -1}, {1, 1}}
  local box2 = {
    left_top = {0.9, 0.9},
    right_bottom = {3.1, 3.1},
    orientation = 0
  }
  assert(box.overlap_rotated(box1, box2))
  box2.orientation = 1 / 8
  assert(not box.overlap_rotated(box1, box2))
  box2.orientation = 1 / 4
  assert(box.overlap_rotated(box1, box2))
  box2.orientation = 3 / 8
  assert(not box.overlap_rotated(box1, box2))

  local box3 = {
    left_top = {1.1, -1.0},
    right_bottom = {3.1, 1.0},
    orientation = 0
  }
  assert(not box.overlap_rotated(box1, box3))
  box3.orientation = 1 / 8
  assert(box.overlap_rotated(box1, box3))
end)

tests.register_test("box.test_contains_rotated", function()
  local b = {left_top = {-1, -1.1}, right_bottom = {5, -0.9}}
  b.orientation = 0

  assert(box.contains(b, {4, -1}))
  assert(not box.contains(b, {3, -2}))
  assert(not box.contains(b, {2, -3}))

  b.orientation = 1 / 8
  assert(not box.contains(b, {4, -1}))
  assert(box.contains(b, {3, -2}))
  assert(not box.contains(b, {2, -3}))

  b.orientation = 1 / 4
  assert(not box.contains(b, {4, -1}))
  assert(not box.contains(b, {3, -2}))
  assert(box.contains(b, {2, -3}))
end)

tests.register_test("box.intersects", function()
  local b = Box.new(2, 3, 7, 6)

  assert(b:intersects({3, 5}, {4, 5}))
  assert(b:intersects({4, 5}, {3, 5}))
  assert(b:intersects({6, 5}, {6, 4}))
  assert(b:intersects({6, 4}, {6, 5}))
  assert(b:intersects({3, 4}, {4, 5}))

  assert(b:intersects({4, 2}, {5, 4}))
  assert(b:intersects({4, 4}, {1, 5}))

  assert(b:intersects({4, 2}, {5, 7}))
  assert(b:intersects({4, 2}, {8, 4}))
  assert(b:intersects({1, 4}, {8, 5}))

  assert(b:intersects({1, 5}, {3, 7}))
  assert(b:intersects({7, 2}, {7, 7}))
  assert(b:intersects({8, 5}, {6, 1}))

  assert(not b:intersects({3, 1}, {5, 2}))
  assert(not b:intersects({3, 1}, {5, 2}))
  assert(not b:intersects({6, 7}, {10, 4}))
end)

tests.register_test("box.expand", function()
  local b = Box.new(2, 3, 7, 6)
  local b_exp = b:expand(Box.new(0, 0, 1, 2))
  local ex1, ey1, ex2, ey2 = b_exp:unpack()
  assert(ex1 == 1.5)
  assert(ey1 == 2)
  assert(ex2 == 7.5)
  assert(ey2 == 7)
end)

return box