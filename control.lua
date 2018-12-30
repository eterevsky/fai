local function pos_tostring(pos) 
  return string.format("(%.2f, %.2f)", pos.x or pos[1], pos.y or pos[2])
end

local function bind(t, k)
  return function(...) return t[k](t, ...) end
end

local function pos_coords(pos)
  x = pos.x or pos[1]
  y = pos.y or pos[2]
  return x, y
end

local function norm_pos(pos)
  if pos.x ~= nil then
    return pos
  end
  return {x = pos[1], y = pos[2]}
end

local function delta(p1, p2) 
  x1, y1 = pos_coords(p1)
  x2, y2 = pos_coords(p2)
  return {x2 - x1, y2 - y1}
end

local function distance(p1, p2)
  x1, y1 = pos_coords(p1)
  x2, y2 = pos_coords(p2)
  dx = x2 - x1
  dy = y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function norm_box(box)
  if box.left_top ~= nil then
    return box
  end
  left_top = box.left_top or box[1]
  right_bottom = box.right_bottom or box[2]
  return {left_top = norm_pos(left_top), right_bottom = norm_pos(right_bottom)}
end

-- Checks whether a point falls within bounding box
local function box_contains(box, pos)
  local box = norm_box(box)
  local pos = norm_pos(pos)

  return box.left_top.x <= pos.x and box.left_top.y <= pos.y and
         box.right_bottom.x >= pos.x and box.right_bottom.y >= pos.y
end

-- Find a point, that is inside bounding box 1, but not inside bounding box 2.
local function selection_diff(box1, box2)
  local box1 = norm_box(box1)
  local box2 = norm_box(box2)

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

  if box_contains(box2, {x, y}) then
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
  assert(box_contains(box1, p))
  assert(not box_contains(box2, p))

  box2 = {{0, 0}, {3, 2.5}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box_contains(box1, p))
  assert(not box_contains(box2, p))

  box2 = {{1.1, 2.1}, {1.9, 2.9}}
  p = selection_diff(box1, box2)
  assert(p ~= nil)
  assert(box_contains(box1, p))
  assert(not box_contains(box2, p))

  game.print("test_selection_diff ok")
end

local function padding_box(center, padding)
  center = norm_pos(center)
  return {{center.x - padding, center.y - padding}, {center.x + padding, center.y + padding}}
end

-- Controller creates a useful subset of Factorio API through which the AI controls the game.

local Controller = {}
Controller.__index = Controller

function Controller.new(player)
  local controller = {}
  setmetatable(controller, Controller)
  controller.player = player
  controller.surface = player.surface
  controller.action_state = {type = nil}
  controller.old_action_state = nil
  return controller
end

-- Get current position
function Controller:position()
  return game.player.position
end

-- Stop any running action
function Controller:stop()
  self.action_state = {action = nil}
end

-- Mine position
function Controller:mine()
  local player = self.player
  local pos = self.player.position
  local reach_distance = self.player.resource_reach_distance + 0.3
  local box = padding_box(pos, reach_distance)
  local ore_entity, ore_point

  for i, e in ipairs(self.surface.find_entities(box)) do
    if e.minable and player.can_reach_entity(e) and e.name ~= "player" then
      selection_point = selection_diff(e.selection_box, player.character.selection_box)
      if selection_point then
        game.print(e.name .. " " .. serpent.line(e.position))
        ore_entity = e
        ore_point = selection_point
        break
      end
    end
  end

  if ore_entity == nil then
    game.print("Didn't find any reachable ore entity")
    return
  end

  game.print("Found ore entity: " .. ore_entity.name .. " " .. serpent.line(ore_entity.position))
  -- game.print("distance: " .. distance(game.player.position, ore_entity.position))
  -- game.print("selection_box: " .. serpent.line(ore_entity.selection_box))
  -- game.print("player selection_box: " .. serpent.line(game.player.character.selection_box))
                      
  self.action_state = {action = "mining", position = selection_point, entity = ore_entity}
end

-- Walk one step in given direction
function Controller:walk(dx, dy)
  game.print("walk " .. serpent.line({dx, dy}))
  local dir = nil
  if dy > 0 then
    if dx > 0 then
      dir = defines.direction.southeast
    elseif dx < 0 then
      dir = defines.direction.southwest
    else
      dir = defines.direction.south
    end
  elseif dy < 0 then
    if dx > 0 then
      dir = defines.direction.northeast
    elseif dx < 0 then
      dir = defines.direction.northwest
    else
      dir = defines.direction.north
    end
  else
    if dx > 0 then
      dir = defines.direction.east
    elseif dx < 0 then
      dir = defines.direction.west
    else
      dir = nil
    end
  end
  if dir ~= nil then
    self.action_state = {action = "walking", direction = dir}
  else
    game.print("Couldn't interpret walking direction: " .. serpent.line({dx = dx, dy = dy}))
  end
end

function Controller:on_tick()
  self:update()
end

-- Keep doing whatever we are doing (i.e. walking, mining)
function Controller:update()
  if self.old_action_state ~= self.action_state then
    game.print("New action_state: " .. serpent.line(self.action_state))
    self.old_action_state = self.action_state
  end
  if self.action_state.action == "walking" then
    self.player.walking_state = {walking = true, direction = self.action_state.direction}
  elseif self.action_state.action == "mining" then
    self.player.update_selected_entity(self.action_state.position)
    self.player.mining_state = {mining = true, position = self.action_state.position}
  end
end

-- Ai makes the decisions what to do and controls the character through the controller object.

local Ai = {}
Ai.__index = Ai

function Ai.new(controller)
  local ai = {}
  setmetatable(ai, Ai)
  ai.controller = controller
  return ai
end

function Ai:stop()
  self.controller:stop()
end

-- Controller and Ai singletons

local active_controller = nil;
local active_ai = nil;

local function get_controller()
  if active_controller == nil then
    active_controller = Controller.new(game.player)
    script.on_nth_tick(1, bind(active_controller, 'on_tick'))
  end
  return active_controller
end

local function get_ai()
  local controller = get_controller()
  if active_ai == nil then
    active_ai = Ai.new(controller)
  end
  return active_ai
end

-- Commands

local function start()
  game.print("--------------")
  game.print(_VERSION)

  local ai = get_ai()
  ai:start()
end

local function stop()
  get_ai():stop()
end

local function pos()
  local pos = get_controller():position()
  game.print("position: " .. serpent.line(pos))
  game.print("resource_reach_distance: " .. game.player.resource_reach_distance)
end

local function entities()
  local controller = get_controller()
  local pos = controller:position()
  local box = {{x = pos.x - 10, y = pos.y - 10}, {x = pos.x + 10, y = pos.y + 10}}
  game.print("Entities in the bounding box " .. serpent.line(box))
  for i, e in ipairs(game.player.surface.find_entities(box)) do
    game.print(i .. " " .. e.name .. " " .. serpent.line(e.position))
  end
end

local function all_entities()
  local count = 0
  local type_count = {}
  local p1, p2 = {x = 0, y = 0}, {x = 0, y = 0}
  for _, entity in ipairs(game.player.surface.find_entities()) do
    count = count + 1
    type_count[entity.name] = (type_count[entity.name] or 0) + 1

    p1.x = math.min(p1.x, entity.position.x)
    p1.y = math.min(p1.y, entity.position.y)
    p2.x = math.max(p2.x, entity.position.x)
    p2.y = math.max(p2.y, entity.position.y)
  end

  game.print(serpent.block(type_count))
  game.print("Found " .. count .. " entities")
  game.print("Bounding box: " .. serpent.line(p1) .. " " .. serpent.line(p2))
end

local function recipes()
  local force = game.player.force
  for name, recipe in pairs(force.recipes) do
    if name == "engine-unit" or recipe.enabled and not recipe.hidden then
      game.print(recipe.name .. " "  ..
                 recipe.category .. " ")
    end
  end
end

local function mine(args)
  get_controller():mine()
end

local function walk(args)
  game.print("Args: " .. serpent.line(args))
  local x, y = string.match(args.parameter, "(-?%d+)%s+(-?%d+)")
  x, y = tonumber(x), tonumber(y)
  get_controller():walk(x, y)
end

local function test()
  test_selection_diff()
end

commands.add_command("start", "Give AI control over the player", start)
commands.add_command("stop", "Stops AI", stop)
commands.add_command("pos", "Show current position", pos)
commands.add_command("entities", "Show entities around", entities)
commands.add_command("all_entities", "Show all known entities", all_entities)
commands.add_command("recipes", "Show all known recipes", recipes)
commands.add_command("mine", "Mine the nearest minable tile", mine)
commands.add_command("walk", "Walk in the direction given by two relative coordinates", walk)
commands.add_command("test", "Run unit tests", test)