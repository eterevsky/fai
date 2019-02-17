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
  if box.left_top ~= nil then
    return box
  end
  local x1, y1, x2, y2 = unpack(box)
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

-- Checks whether two boxes intersect.
local function overlap(box1, box2)
  local box1 = norm(box1)
  local box2 = norm(box2)

  return box1.left_top.x < box2.right_bottom.x and
         box1.right_bottom.x > box2.left_top.x and
         box1.left_top.y < box2.right_bottom.y and
         box1.right_bottom.y > box2.left_top.y
end

local function padding(center, padding)
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


return {
  norm = norm,
  move = move,
  contains = contains,
  selection_diff = selection_diff,
  test_selection_diff = test_selection_diff,
}
