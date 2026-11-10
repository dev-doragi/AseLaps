local History = {}
History.__index = History

function History.new()
  return setmetatable({
    events={}, nodes={}, snapshots={}, count=0, head=0,
    status="stopped", elapsed=0
  }, History)
end

function History:accepts(event)
  if type(event) ~= "table" or event.id ~= #self.events + 1 then return false end
  local kind = event.kind
  if kind == "status" then
    return event.status == "recording" or event.status == "paused"
      or event.status == "stopped"
  end
  if kind == "link" then
    local node = self.nodes[event.node]
    return node and node.uncertain and type(event.parent) == "number"
      and (event.parent == 0 or
        (self.nodes[event.parent] and event.parent < event.node))
  end
  if kind ~= "state" and kind ~= "visit" then return false end
  local snapshot = event.snapshot or event.png
  if snapshot ~= nil and (not math.tointeger(snapshot) or snapshot < 1) then return false end
  if event.emit and not snapshot then return false end
  if kind == "state" then
    return event.parent == 0 or self.nodes[event.parent] ~= nil
  end
  return event.head == 0 or self.nodes[event.head] ~= nil
end

function History:apply(event)
  self.events[event.id] = event
  self.elapsed = event.elapsed or self.elapsed
  local snapshot = event.snapshot or event.png
  if snapshot and not self.snapshots[snapshot] then
    self.snapshots[snapshot] = true
    self.count = self.count + 1
  end
  if event.kind == "status" then
    self.status = event.status
  elseif event.kind == "state" then
    self.nodes[event.id] = event
    self.head = event.id
  elseif event.kind == "visit" then
    self.head = event.head
  elseif event.kind == "link" then
    local node = self.nodes[event.node]
    node.parent = event.parent
    node.uncertain = nil
  end
end

function History:timeline(mode, head)
  local frames = {}
  if mode == "Full" then
    for _, event in ipairs(self.events) do
      if event.emit then frames[#frames + 1] = event.snapshot or event.png end
    end
    return frames
  end

  local reverse = {}
  local id = head or self.head
  while id ~= 0 do
    local node = assert(self.nodes[id], "Unknown history state.")
    if node.uncertain then
      return nil, string.format("Resolve state #%d in History before Clean export.", id)
    end
    if node.png then reverse[#reverse + 1] = node.png end
    id = node.parent
  end
  for i = #reverse, 1, -1 do
    frames[#frames + 1] = reverse[i]
  end
  return frames
end

function History.direction(previous, current)
  if not previous or not current or
    previous.undoSteps + previous.redoSteps ~= current.undoSteps + current.redoSteps then
    return nil
  end
  if current.undoSteps < previous.undoSteps then return "Undo" end
  if current.undoSteps > previous.undoSteps then return "Redo" end
  return nil
end

return History
