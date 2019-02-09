local function log(...)
  local s = ""
  local first = true
  for _, arg in ipairs{...} do
    if first then
      first = false
    else
      s = s .. " "
    end

    if type(arg) == "string" or type(arg) == "number" then
      s = s .. arg
    else
      s = s .. serpent.line(arg)
    end
  end
  game.print(s)
end

local function bind(t, k)
  return function(...) return t[k](t, ...) end
end

local function table_size(t)
  local count = 0
  for _, _ in pairs(t) do
    count = count + 1
  end
  return count
end

return {
    log = log,
    bind = bind,
    table_size = table_size
}