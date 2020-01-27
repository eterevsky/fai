local box = require "box"
local log = require("util").log
local pos = require "pos"
local tests = require "tests"

-- A set of 2D points, allowing fast search operations.
local PointSet = {}
PointSet.__index = PointSet

function PointSet.new(points)
  local self = {}
  setmetatable(self, PointSet)

  assert(#points > 0)

  local minx = 1000000
  local miny = 1000000
  local maxx = -1000000
  local maxy = -1000000

  for _, point in ipairs(points) do
    local x, y = pos.unpack(point)
    if x < minx then minx = x end
    if y < miny then miny = y end
    if x > maxx then maxx = x end
    if y > maxy then maxy = y end
  end

  self.box = box.new_pack(minx, miny, maxx, maxy)

  if #points <= 4 or (minx == maxx and miny == maxy) then
    self.points = points
    self.part1 = nil
    self.part2 = nil
  else
    self.points = nil
    local part1_points = {}
    local part2_points = {}
    local midx = nil
    local midy = nil
    if maxx - minx >= maxy - miny then
      midx = (minx + maxx) / 2
    else
      midy = (miny + maxy) / 2
    end

    for _, point in ipairs(points) do
      local x, y = pos.unpack(point)
      if (midy == nil and x < midx) or (midx == nil and y < midy) then
        table.insert(part1_points, point)
      else
        table.insert(part2_points, point)
      end
    end

    self.part1 = PointSet.new(part1_points)
    self.part2 = PointSet.new(part2_points)
  end

  return self
end

-- Returns low estimate for the L2 distance from a given point to the set, based
-- on the set's bounding box.
function PointSet:l2_dist_est(from)
  assert(from ~= nil)
  local x, y = pos.unpack(from)
  local x1, y1, x2, y2 = box.unpack(self.box)

  if x1 <= x and x <= x2 then
    if y1 <= y and y <= y2 then return 0 end
    return math.min(math.abs(y1 - y), math.abs(y2 - y))
  end

  if y1 <= y and y <= y2 then
    return math.min(math.abs(x1 - x), math.abs(x2 - x))
  end

  local dx1 = x - x1
  local dx2 = x - x2
  local dy1 = y - y1
  local dy2 = y - y2

  local dx = math.min(dx1 * dx1, dx2 * dx2)
  local dy = math.min(dy1 * dy1, dy2 * dy2)

  return math.sqrt(dx + dy)
end

function PointSet:min_l2_dist(from)
  assert(from ~= nil)
  if self.points ~= nil then
    local min_dist = 1000000
    for _, point in ipairs(self.points) do
      local dist = pos.dist_l2(from, point)
      if dist < min_dist then min_dist = dist end
    end
    return min_dist
  end

  local dist1 = self.part1:l2_dist_est(from)
  local dist2 = self.part2:l2_dist_est(from)

  if dist1 <= dist2 then
    dist1 = self.part1:min_l2_dist(from)
    if dist2 < dist1 then dist2 = self.part2:min_l2_dist(from) end
  else
    dist2 = self.part2:min_l2_dist(from)
    if dist1 < dist2 then dist1 = self.part1:min_l2_dist(from) end
  end

  return math.min(dist1, dist2)
end

tests.register_test("pointset.test", function()
  local points = {}
  for _i = 1, 100 do
    local point = pos.pack(math.random(), math.random())
    table.insert(points, point)
  end

  local pointset = PointSet.new(points)

  for _i = 1, 100 do
    local from = pos.pack(math.random(), math.random())
    local pointset_dist = pointset:min_l2_dist(from)
    assert(pointset_dist ~= nil)
    local min_dist = 1000000
    for _, point in ipairs(points) do
      local dist = pos.dist_l2(from, point)
      if dist < min_dist then min_dist = dist end
    end

    if min_dist ~= pointset_dist then
      log("min_dist =", min_dist, "pointset_dist =", pointset_dist)
    end

    assert(min_dist == pointset_dist)
  end
end)

return {PointSet = PointSet}

