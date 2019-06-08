local log = require("util").log
local pos = require("pos")

local function unpack(box)
  local left_top = box.left_top or box[1]
  local right_bottom = box.right_bottom or box[2]
  local x1, y1 = pos.unpack(left_top)
  local x2, y2 = pos.unpack(right_bottom)
  return x1, y1, x2, y2
end

local function norm(box)
  assert(box ~= nil)
  local x1, y1, x2, y2 = unpack(box)
  return {
    left_top = pos.norm(x1, y1),
    right_bottom = pos.norm(x2, y2)
  }
end

local function new_norm(x1, y1, x2, y2)
  return {
    left_top = pos.norm(x1, y1),
    right_bottom = pos.norm(x2, y2)
  }
end

-- Move a box from (0, 0) to center.
local function move(box, center)
  local x1, y1, x2, y2 = unpack(box)
  local x, y = pos.unpack(center)
  return {pos.pack(x + x1, y + y1), pos.pack(x + x2, y + y2)}
end

-- Checks whether a point falls within bounding box
local function contains(box, p)
  local x1, y1, x2, y2 = unpack(box)
  local px, py = pos.unpack(p)

  return x1 <= px and px <= x2 and y1 <= py and py <= y2
end

local function covers(big_box, small_box)
  local bx1, by1, bx2, by2 = unpack(big_box)
  local sx1, sy1, sx2, sy2 = unpack(small_box)

  return bx1 <= sx1 and sx1 <= bx2 and by1 <= sy1 and sy1 <= by2 and
         bx1 <= sx2 and sx2 <= bx2 and by1 <= sy2 and sy2 <= by2
end 

-- Checks whether two boxes intersect.
local function overlap(box1, box2)
  local box1 = norm(box1)
  local box2 = norm(box2)

  return box1.left_top.x < box2.right_bottom.x and
         box1.right_bottom.x > box2.left_top.x and
         box1.left_top.y < box2.right_bottom.y and
         box1.right_bottom.y > box2.left_top.y
end

local function overlap_rotated(box1, box2_rotated)
  if box2_rotated.orientation == nil or box2_rotated.orientation == 0 then
    return overlap(box1, box2_rotated)
  end

  local angle = 2 * math.pi * box2_rotated.orientation
  local cos = math.cos(angle)
  local sin = math.sin(angle)
  
  local ax1, ay1, ax2, ay2 = unpack(box1)

  -- Before rotation
  local bx1, by1, bx2, by2 = unpack(box2_rotated)

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
  if rx1 >= ax2 and rx2 >= ax2 and rx3 >= ax2 and rx4 >= ax2 or
     rx1 <= ax1 and rx2 <= ax1 and rx3 <= ax1 and rx4 <= ax1 then return false end

  -- Check projection on the vertical axis
  if ry1 >= ay2 and ry2 >= ay2 and ry3 >= ay2 and ry4 >= ay2 or
     ry1 <= ay1 and ry2 <= ay1 and ry3 <= ay1 and ry4 <= ay1 then return false end

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
  if math.max(ap1, ap2, ap3, ap4) <= math.min(rp1, rp2, rp3, rp4) or
     math.max(rp1, rp2, rp3, rp4) <= math.min(ap1, ap2, ap3, ap4) then return false end

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
  if math.max(ap1, ap2, ap3, ap4) <= math.min(rp1, rp2, rp3, rp4) or
     math.max(rp1, rp2, rp3, rp4) <= math.min(ap1, ap2, ap3, ap4) then return false end

  return true
end

local function pad(center, padding)
  center = pos.norm(center)
  return {{center.x - padding, center.y - padding}, {center.x + padding, center.y + padding}}
end

-- Find a point, that is inside bounding box 1, but not inside bounding box 2.
local function selection_diff(box1, box2)
  local box1 = norm(box1)
  local box2 = norm(box2)

  local x = (box1.right_bottom.x + box1.left_top.x) / 2
  if box1.left_top.x < box2.left_top.x then
    x = (box1.left_top.x + math.min(box1.right_bottom.x, box2.left_top.x)) / 2
  elseif box1.right_bottom.x > box2.right_bottom.x then
    x = (box1.right_bottom.x + math.max(box1.left_top.x, box2.right_bottom.x)) / 2
  end

  local y = (box1.right_bottom.y + box1.left_top.y) / 2
  if box1.left_top.y < box2.left_top.y then
    y = (box1.left_top.y + math.min(box1.right_bottom.y, box2.left_top.y)) / 2
  elseif box1.right_bottom.y > box2.right_bottom.y then
    y = (box1.right_bottom.y + math.max(box1.left_top.y, box2.right_bottom.y)) / 2
  end

  if contains(box2, {x, y}) then
    return nil
  end
  
  return {x = x, y = y}
end

local function test_selection_diff()
  local box1 = {{1, 2}, {2, 3}}
  local box2 = {{0, 1}, {3, 4}}
  local p = selection_diff(box1, box2)
  assert(p == nil)

  box2 = {{1.5, 1}, {3, 4}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(contains(box1, p))
  assert(not contains(box2, p))

  box2 = {{0, 0}, {3, 2.5}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(contains(box1, p))
  assert(not contains(box2, p))

  box2 = {{1.125, 2.125}, {1.875, 2.875}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(contains(box1, p))
  assert(not contains(box2, p))

  log("box.test_selection_diff ok")
end

local function test_overlap_rotated()
  local box1 = {{-1, -1}, {1, 1}}
  local box2 = {left_top = {0.9, 0.9}, right_bottom = {3.1, 3.1}, orientation = 0}
  assert(overlap_rotated(box1, box2))
  box2.orientation = 1/8
  assert(not overlap_rotated(box1, box2))
  box2.orientation = 1/4
  assert(overlap_rotated(box1, box2))
  box2.orientation = 3/8
  assert(not overlap_rotated(box1, box2))
  
  local box3 = {left_top = {1.1, -1.0}, right_bottom = {3.1, 1.0}, orientation = 0}
  assert(not overlap_rotated(box1, box3))
  box3.orientation = 1/8
  assert(overlap_rotated(box1, box3))

  log("box.test_overlap_rotated ok")
end

return {
  norm = norm,
  new_norm = new_norm,
  move = move,
  contains = contains,
  covers = covers,
  overlap = overlap,
  overlap_rotated = overlap_rotated,
  pad = pad,
  unpack = unpack,
  selection_diff = selection_diff, 
  test_overlap_rotated = test_overlap_rotated,
  test_selection_diff = test_selection_diff,
}
