local log = require("util").log

local RADIX = 2^20
local HALF_RADIX = 2^19

local function pack(x, y)
  local x_scaled = math.floor(x * 256 + 0.5) + HALF_RADIX
  local y_scaled = math.floor(y * 256 + 0.5) + HALF_RADIX

  assert(x_scaled > 0 and x_scaled < RADIX and
         y_scaled > 0 and y_scaled < RADIX)

  return x_scaled + RADIX * y_scaled
end

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

local function enc(pos)
  if type(pos) == "number" then return pos end
  local x, y = unpack(pos)
  return pack(x, y)
end

local function norm(pos)
  if type(pos) == "number" then
    local x, y = unpack(pos)
    return {x = x, y = y}
  else
    if pos.x ~= nil then return pos end
    return {x = pos[1], y = pos[2]}
  end
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

local function test()
  for x = -10, 10, 239/256 do
    for y = -10, 10, 239/256 do
      local pos = pack(x, y)
      local ux, uy = unpack(pos)
      assert(x == ux)
      assert(y == uy)

      local upos = enc(pos)
      assert(upos == pos)

      local upos = enc({x, y})
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

  log("pos.test ok")
end

return {
  pack = pack,
  unpack = unpack,
  enc = enc,
  norm = norm,
  delta = delta,
  dist_l2 = dist_l2,
  dist_linf = dist_linf,
  test = test,
}