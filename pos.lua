local tests = require "tests"

-- Packed positions represent any coordinates between (-2048, -2048) and
-- (2048, 2048) with a step of 1/256.
local RADIX = 2 ^ 20
local HALF_RADIX = RADIX / 2

local pos = {}

function pos.unpack(p)
  if type(p) == "number" then
    local x_scaled = p % RADIX
    local y_scaled = math.floor(p / RADIX)
    return (x_scaled - HALF_RADIX) / 256, (y_scaled - HALF_RADIX) / 256
  else
    local x = p.x or pos[1]
    local y = p.y or pos[2]
    return x, y
  end
end

function pos.pack(pos_or_x, y)
  local x
  if y == nil then
    if type(pos_or_x) == "number" then return pos_or_x end
    x = pos_or_x.x or pos_or_x[1]
    y = pos_or_x.y or pos_or_x[2]
  else
    x = pos_or_x
  end

  assert(-2048 < x and x < 2048)
  assert(-2048 < y and y < 2048)

  local x_scaled = math.floor(x * 256 + 0.5) + HALF_RADIX
  local y_scaled = math.floor(y * 256 + 0.5) + HALF_RADIX

  assert(x_scaled > 0 and x_scaled < RADIX and y_scaled > 0 and y_scaled < RADIX)

  return x_scaled + RADIX * y_scaled
end

function pos.norm(pos_or_x, y)
  if y ~= nil then return {x = pos_or_x, y = y} end
  if type(pos_or_x) == "table" and pos_or_x.x ~= nil then return pos_or_x end
  local ux, uy = pos.unpack(pos_or_x)
  return {x = ux, y = uy}
end

function pos.dist_l2(p1, p2)
  assert(p1 ~= nil)
  assert(p2 ~= nil)
  local x1, y1 = pos.unpack(p1)
  local x2, y2 = pos.unpack(p2)
  local dx = x2 - x1
  local dy = y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

-- Returns a single value that can be added to a packed position so that (x, y)
-- is transformed to (x + dx, y + dy)
function pos.pack_delta(dx, dy)
  local p = pos.pack(dx, dy)
  local p0 = pos.pack(0, 0)
  return p - p0
end

-- Length of packed delta.
function pos.delta_len(d)
  local x, y = pos.unpack(d + pos.pack(0, 0))
  return math.sqrt(x * x + y * y)
end

tests.register_test("pos.test", function()
  for x = -10, 10, 239 / 256 do
    for y = -10, 10, 239 / 256 do
      local p = pos.pack(x, y)
      local ux, uy = pos.unpack(p)
      assert(x == ux)
      assert(y == uy)

      local upos = pos.pack(p)
      assert(upos == p)

      upos = pos.pack({x, y})
      assert(upos == p)
    end
  end

  local ux, uy = pos.unpack(pos.pack(0, 0))
  assert(ux == 0)
  assert(uy == 0)

  ux, uy = pos.unpack({12, 34})
  assert(ux == 12)
  assert(uy == 34)

  local p = pos.norm({12, 34})
  assert(p.x == 12)
  assert(p.y == 34)
end)

tests.register_test("pos.test_pack_delta", function()
  for _ = 1, 10 do
    local dx = math.random(-10000, 10000) / 256
    local dy = math.random(-10000, 10000) / 256
    local x = math.random(-10000, 10000) / 256
    local y = math.random(-10000, 10000) / 256

    local p = pos.pack(x, y)
    local d = pos.pack_delta(dx, dy)
    local xn, yn = pos.unpack(p + d)
    assert(xn == x + dx)
    assert(yn == y + dy)
  end
end)

return pos