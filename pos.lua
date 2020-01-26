local log = require("util").log
local tests = require "tests"

local RADIX = 2^20
local HALF_RADIX = 2^19

local function unpack(pos)
  if type(pos) == "number" then
    local x_scaled = pos % RADIX
    local y_scaled = math.floor(pos / RADIX)
    return (x_scaled - HALF_RADIX) / 256, (y_scaled - HALF_RADIX) / 256
  else 
    local x = pos.x or pos[1]
    local y = pos.y or pos[2]
    return x, y
  end
end

local function pack(pos_or_x, y)
  local x
  if y == nil then
    if type(pos_or_x) == "number" then return pos_or_x end
    x = pos_or_x.x or pos_or_x[1]
    y = pos_or_x.y or pos_or_x[2]
  else 
    x = pos_or_x
  end

  local x_scaled = math.floor(x * 256 + 0.5) + HALF_RADIX
  local y_scaled = math.floor(y * 256 + 0.5) + HALF_RADIX

  assert(x_scaled > 0 and x_scaled < RADIX and
         y_scaled > 0 and y_scaled < RADIX)

  return x_scaled + RADIX * y_scaled
end

local function norm(pos_or_x, y)
  if y ~= nil then
    return {x = pos_or_x, y = y}
  end
  if type(pos_or_x) == "table" and pos_or_x.x ~= nil then
    return pos_or_x
  end 
  local x, y = unpack(pos_or_x)
  return {x = x, y = y}
end

local function delta(p1, p2) 
  local x1, y1 = unpack(p1)
  local x2, y2 = unpack(p2)
  return {x2 - x1, y2 - y1}
end

local function dist_l2(p1, p2)
  assert(p1 ~= nil)
  assert(p2 ~= nil)
  local x1, y1 = unpack(p1)
  local x2, y2 = unpack(p2)
  local dx = x2 - x1
  local dy = y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function dist_linf(p1, p2)
  local x1, y1 = unpack(p1)
  local x2, y2 = unpack(p2)
  local dx = x2 - x1
  local dy = y2 - y1
  return math.max(math.abs(dx), math.abs(dy))
end

-- Returns a single value that can be added to a packed position so that (x, y) is transformed to
-- (x + dx, y + dy)
local function pack_delta(dx, dy)
  local p = pack(dx, dy)
  local p0 = pack(0, 0)
  return p - p0
end

local function delta_len(delta)
  local x, y = unpack(delta + pack(0, 0))
  return math.sqrt(x * x + y * y)
end

local function test()
  for x = -10, 10, 239/256 do
    for y = -10, 10, 239/256 do
      local pos = pack(x, y)
      local ux, uy = unpack(pos)
      assert(x == ux)
      assert(y == uy)

      local upos = pack(pos)
      assert(upos == pos)

      local upos = pack({x, y})
      assert(upos == pos)
    end
  end

  local ux, uy = unpack(pack(0, 0))
  assert(ux == 0)
  assert(uy == 0)

  local ux, uy = unpack({12, 34})
  assert(ux == 12)
  assert(uy == 34)

  local pos = norm({12, 34})
  assert(pos.x == 12)
  assert(pos.y == 34)
end

tests.register_test("pos.test", test)

local function test_pack_delta()
  for _i = 1, 10 do
  local dx = math.random(-10000, 10000) / 256
  local dy = math.random(-10000, 10000) / 256
  local x = math.random(-10000, 10000) / 256
  local y = math.random(-10000, 10000) / 256

  local p = pack(x, y)
  local d = pack_delta(dx, dy)
  local xn, yn = unpack(p + d)
  assert(xn == x + dx)
  assert(yn == y + dy)
  end
end

tests.register_test("pos.test_pack_delta", test_pack_delta)

return {
  pack = pack,
  unpack = unpack,
  norm = norm,
  delta = delta,
  dist_l2 = dist_l2,
  dist_linf = dist_linf,
  pack_delta = pack_delta,
  delta_len = delta_len,
}