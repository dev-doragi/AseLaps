local Recorder = {}
Recorder.__index = Recorder
local function render(sprite, frame, info)
  local image = Image(sprite.width, sprite.height, ColorMode.RGB)
  image:drawSprite(sprite, frame)
  if info.crop then
    local c = info.crop
    image = Image(image, Rectangle(c.x, c.y, c.w, c.h))
  end
  return image
end
function Recorder.new(store, history, preferences, warning)
  return setmetatable({store=store, history=history, preferences=preferences,
    warning=warning, documents={}, listeners={}, clock=0}, Recorder)
end
function Recorder.elapsed(doc)
  if not doc or not doc.session then return 0 end
  if doc.running then return doc.elapsedBase + math.max(0, os.time()-doc.started) end
  return doc.session.history.elapsed
end
function Recorder:append(doc, event)
  event.elapsed = Recorder.elapsed(doc)
  self.store.append(doc.session, event)
end
function Recorder:guard(doc, action)
  if self.busy then return false end
  self.busy = true
  local ok, result = pcall(action)
  self.busy = false
  if not ok then
    if doc and doc.session then doc.running = false; doc.session.faulted = true end
    self.warning(tostring(result) .. (doc and doc.session and ("\nSaved captures: "..doc.session.history.count..". Use Resume to continue.") or ""))
  end
  return ok, result
end
function Recorder:start(doc, crop, initial, folder)
  assert(not doc.running, "Stop the current session first.")
  local sprite = doc.sprite
  if crop then
    assert(crop.x >= 0 and crop.y >= 0 and crop.w > 0 and crop.h > 0
      and crop.x+crop.w <= sprite.width and crop.y+crop.h <= sprite.height,
      "The capture area must fit inside the canvas.")
  end
  local interval = self.preferences.intervalMs or 500
  assert(interval == 500 or interval == 1000 or interval == 2000, "Invalid capture interval.")
  assert(sprite.hasAssociatedFile, "Save the artwork as .aseprite before recording.")
  doc.project = self.store:project(sprite, true)
  doc.session = self.store:create(doc.project, {
    version=4, folder=folder, captureMode="sampled", intervalMs=interval, width=sprite.width, height=sprite.height,
    captureWidth=crop and crop.w or sprite.width, captureHeight=crop and crop.h or sprite.height,
    rowStride=(crop and crop.w or sprite.width)*4, crop=crop, initial=initial ~= false})
  self.preferences.sessionsBySource = self.preferences.sessionsBySource or {}
  self.preferences.sessionsBySource[self.store.source(sprite):gsub("\\","/")] = app.fs.normalizePath(app.fs.joinPath(doc.session.folder,"session.json"))
  doc.elapsedBase, doc.started, doc.running = 0, os.time(), true
  doc.view, doc.dirty, doc.nextCapture = nil, false, self.clock+interval
  self:append(doc, {kind="status", status="recording"})
  if initial ~= false then self:sample(doc, true) end
end
function Recorder:resume(doc)
  assert(doc.session and not doc.running, "Select a paused session first.")
  if doc.session.info.version < 3 then
    local crop = doc.session.info.crop
    if crop and (crop.x+crop.w > doc.sprite.width or crop.y+crop.h > doc.sprite.height) then crop = nil end
    return self:start(doc, crop, true)
  end
  if doc.session.faulted then doc.session = self.store:load(doc.session) end
  assert(doc.session.history.status ~= "stopped", "Start a new session after stopping.")
  doc.elapsedBase, doc.started, doc.running = doc.session.history.elapsed, os.time(), true
  doc.view, doc.dirty, doc.nextCapture = nil, true, self.clock+doc.session.info.intervalMs
  self:append(doc, {kind="status", status="recording"})
end
function Recorder:sample(doc, manual)
  if not doc.running or not doc.sprite.isValid or app.sprite ~= doc.sprite then return end
  local info = doc.session.info
  if info.version~=4 and (doc.sprite.width ~= info.width or doc.sprite.height ~= info.height) then
    local crop = info.crop
    if crop and (crop.x+crop.w > doc.sprite.width or crop.y+crop.h > doc.sprite.height) then crop = nil end
    self:append(doc, {kind="status", status="stopped"})
    doc.running = false
    return self:start(doc, crop, info.initial)
  end
  local frame = app.frame and app.frame.frameNumber or 1
  local image = render(doc.sprite, frame, info.version==4 and {} or info)
  local previous = doc.view
  if not previous or previous.frame ~= frame or not previous.image:isEqual(image) then
    local boundary
    if info.version==4 then
      local last=doc.session.records[doc.session.lastCapture]
      local w,h=info.width,info.height
      if last then w,h=last.w,last.h end
      if image.width~=w or image.height~=h then
        local x,y,review=0,0,true
        if last then
          local old=previous and previous.image or self.store.loadNative(doc.session,doc.session.lastCapture)
          x,y,review=self.store.align(old,image)
        end
        boundary={oldWidth=w,oldHeight=h,width=image.width,height=image.height,dx=x,dy=y,uncertain=review}
      end
    end
    local id = self.store.saveSnapshot(doc.session, image)
    self:append(doc, {kind="state", parent=doc.session.history.head,
      boundary=boundary,label=manual and "Snapshot" or "Sample", snapshot=id, frame=frame, emit=true})
  end
  doc.view, doc.dirty = {frame=frame, image=image}, false
  doc.nextCapture = self.clock+info.intervalMs
end
function Recorder:capture(doc, fromUndo, manual)
  if not doc.running then return end
  if manual then return self:sample(doc, true) end
  doc.dirty = true
  local session=doc.session
  if session.info.version==4 and app.sprite==doc.sprite then
    local last=session.records[session.lastCapture]
    if doc.sprite.width~=(last and last.w or session.info.width)
      or doc.sprite.height~=(last and last.h or session.info.height) then
      self:guard(doc,function() self:sample(doc,false) end)
    end
  end
end
function Recorder:flush(doc)
  if doc.dirty then self:sample(doc, false) end
end
function Recorder:status(doc, status)
  assert(doc.session, "Select a session first.")
  if doc.session.faulted then doc.session = self.store:load(doc.session) end
  if doc.running then self:flush(doc) end
  self:append(doc, {kind="status", status=status})
  doc.running, doc.dirty, doc.view = false, false, nil
end
function Recorder:renamed(doc)
  if not doc.project then return end
  local source = self.store.source(doc.sprite)
  if not source then return end
  if source ~= doc.project.source then
    local target = self.store:project(doc.sprite, false)
    if not doc.project.source and not target then self.store:bind(doc.project, source)
    else
      local running, info = doc.running, doc.session and doc.session.info
      if running then self:status(doc, "stopped") end
      doc.project, doc.session = target, nil
      if running then self:start(doc, info.crop, info.initial) end
    end
  end
  doc.filename = doc.sprite.filename
end
function Recorder:document(sprite)
  if self.documents[sprite.id] then return self.documents[sprite.id] end
  if sprite.properties["aselapsEdit"] then return nil end
  local doc = {sprite=sprite, filename=sprite.filename, events=sprite.events, listeners={}}
  self.documents[sprite.id] = doc
  for _, name in ipairs({"change", "layervisibility", "layeropacity", "layerblendmode"}) do
    doc.listeners[#doc.listeners+1] = sprite.events:on(name, function() self:capture(doc) end)
  end
  local source=self.store.source(sprite)
  local remembered=source and self.preferences.sessionsBySource and (self.preferences.sessionsBySource[source:gsub("\\","/")] or self.preferences.sessionsBySource[source])
  if remembered and app.fs.isFile(remembered) then
    doc.session=self.store:open(remembered)
    doc.project=doc.session.project
    doc.project.source=source
  end
  doc.project = doc.project or self.store:project(sprite, false)
  if doc.project and not doc.session then
    local sessions = self.store:sessions(doc.project)
    if #sessions > 0 then doc.session = self.store:load(sessions[#sessions]) end
  end
  return doc
end
function Recorder:site()
  -- Frame navigation deliberately performs no rendering or storage work.
end
function Recorder:tick(milliseconds)
  self.clock = self.clock+(milliseconds or 250)
  for id, doc in pairs(self.documents) do
    if not doc.sprite.isValid then
      self:guard(doc, function()
        if doc.running then self:append(doc, {kind="status", status="recording"}) end
      end)
      self.documents[id] = nil
    end
  end
  local sprite = app.sprite
  if not sprite then return end
  local doc = self.documents[sprite.id]
  if not doc then
    local ok
    ok, doc = self:guard(nil, function() return self:document(sprite) end)
    if not ok or not doc then return end
    if doc.session and doc.session.history.status == "recording" and self.preferences.autoResume ~= false then
      self:guard(doc, function() self:resume(doc) end)
    end
  end
  self:guard(doc, function()
    if doc.filename ~= sprite.filename then self:renamed(doc) end
    if doc.running and doc.dirty and self.clock >= doc.nextCapture then self:sample(doc, false) end
  end)
end
function Recorder:watch()
  self:tick(0)
end
function Recorder:shutdown()
  for _, doc in pairs(self.documents) do
    self:guard(doc, function()
      if doc.running then self:status(doc, "recording") end
      if doc.sprite.isValid then
        for _, id in ipairs(doc.listeners) do doc.events:off(id) end
      end
    end)
  end
  self.documents = {}
end
Recorder.render = render
return Recorder
