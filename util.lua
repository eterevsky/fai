local _log_enabled = true

local function enable_log() 
  _log_enabled = true
end

local function disable_log()
  _log_enabled = false
end

local function log(...)
  if not _log_enabled then
    return
  end
  
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
    enable_log = enable_log,
    disable_log = disable_log,
    log = log,
    bind = bind,
    table_size = table_size
}