local log = require("util").log
local tests = require "tests"

-- Binary heap-based priority queue. Returns elements lower-first.
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
  local self = {}
  setmetatable(self, PriorityQueue)
  self.heap = {}
  return self
end

-- Adds an entry to the priority queue.
function PriorityQueue:push(entry)
  table.insert(self.heap, entry)
  self:_sift_down(#self.heap)
end

function PriorityQueue:empty()
  return next(self.heap) == nil
end

function PriorityQueue:pop()
  local last = table.remove(self.heap)
  if not self:empty() then
    local ret = self.heap[1]
    self.heap[1] = last
    self:_sift_up(1)
    return ret
  else
    return last
  end
end

function PriorityQueue:size()
  return #self.heap
end

function PriorityQueue:_sift_down(idx)
  while idx > 1 do
    local parent_idx = math.floor(idx / 2)

    if self.heap[parent_idx] < self.heap[idx] then return end

    local temp = self.heap[idx]
    self.heap[idx] = self.heap[parent_idx]
    self.heap[parent_idx] = temp

    idx = parent_idx    
  end
end

function PriorityQueue:_sift_up(idx)
  while idx < #self.heap do
    local left = 2 * idx
    local right = left + 1
    if (left > #self.heap or self.heap[idx] < self.heap[left]) and
       (right > #self.heap or self.heap[idx] < self.heap[right]) then
      return
    end
    if right <= #self.heap and self.heap[right] < self.heap[left] then
      local temp = self.heap[right]
      self.heap[right] = self.heap[idx]
      self.heap[idx] = temp
      idx = right
    else
      local temp = self.heap[left]
      self.heap[left] = self.heap[idx]
      self.heap[idx] = temp
      idx = left
    end
  end
end

tests.register_test("pqueue.small", function()
  local queue = PriorityQueue.new()
  queue:push(2)
  queue:push(1)
  assert(queue:pop() == 1)
  queue:push(3)
  queue:push(4)
  assert(queue:pop() == 2)
  queue:push(-1)
  assert(queue:pop() == -1)
  assert(queue:pop() == 3)
  assert(queue:size() == 1)
end)

tests.register_test("pqueue.test", function()
  local elements = {}
  local pq = PriorityQueue.new()
  assert(pq:empty())

  for _i = 1, 100 do
    local x = math.random()
    table.insert(elements, x)
    pq:push(x)

    assert(not pq:empty())
    assert(pq:size() == #elements)

    if math.random() < 0.5 then
      local lo = pq:pop()

      local lo_i = 1
      local lo_x = elements[1]
      for i, x in ipairs(elements) do
        if x < lo_x then
          lo_i = i
          lo_x = x
        end
      end

      assert(lo == lo_x)
      table.remove(elements, lo_i)
    end
  end

  while #elements > 0 do
    assert(not pq:empty())
    assert(pq:size() == #elements)
    local lo = pq:pop()

    local lo_i = 1
    local lo_x = elements[1]
    for i, x in ipairs(elements) do
      if x < lo_x then
        lo_i = i
        lo_x = x
      end
    end

    assert(lo == lo_x)
    table.remove(elements, lo_i)
  end

  assert(pq:empty())

  log("pqueue.test ok")
end)

return {
  PriorityQueue = PriorityQueue,
}