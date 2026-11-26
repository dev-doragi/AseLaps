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
function Recorder:remember(doc)
  local key = self.store.pathKey(doc.project.source)
  if not key then return end
  self.preferences.sessionsBySource = self.preferences.sessionsBySource or {}
  self.preferences.sessionsBySource[key] = app.fs.joinPath(doc.session.folder,"session.json")
end
function Recorder:start(doc, crop, initial, folder)
  assert(not doc.running, "Stop the current session first.")
  local sprite = doc.sprite
  if crop then
    assert(crop.x >= 0 and crop.y >= 0 and crop.w > 0 and crop.h > 0
      and crop.x+crop.w <= sprite.width and crop.y+crop.h <= sprite.height,
      "The capture area must fit inside the canvas.")
  end
  local mode=self.preferences.captureMode or "Balanced"
  local interval = mode=="Low impact" and 2000 or self.preferences.intervalMs or 500
  assert(interval == 500 or interval == 1000 or interval == 2000, "Invalid capture interval.")
  doc.project = self.store:project(sprite, true)
  doc.session = self.store:create(doc.project, {
    version=4, folder=folder, captureMode="sampled", capturePolicy=mode, intervalMs=interval, width=sprite.width, height=sprite.height,
    captureWidth=crop and crop.w or sprite.width, captureHeight=crop and crop.h or sprite.height,
    rowStride=(crop and crop.w or sprite.width)*4, crop=crop, initial=initial ~= false})
  doc.project = doc.session.project
  self:remember(doc)
  doc.elapsedBase, doc.started, doc.running = 0, os.time(), true
  doc.view,doc.dirty=nil,false
  doc.lastSample,doc.pendingChanges=self.clock,0
  doc.nextCapture=self.clock+(mode=="Smart Sampling" and 2000 or interval)
  self:append(doc, {kind="status", status="recording", source=self.store.source(doc.sprite)})
  if initial ~= false then self:sample(doc, true) end
end
function Recorder:resume(doc)
  assert(doc.session and not doc.running, "Select a paused session first.")
  self:canResume(doc,doc.session)
  if doc.session.info.version < 2 then
    local crop = doc.session.info.crop
    if crop and (crop.x+crop.w > doc.sprite.width or crop.y+crop.h > doc.sprite.height) then crop = nil end
    return self:start(doc, crop, true)
  end
  if doc.session.faulted then doc.session = self.store:load(doc.session) end
  assert(doc.session.history.status ~= "stopped", "Start a new session after stopping.")
  doc.elapsedBase, doc.started, doc.running = doc.session.history.elapsed, os.time(), true
  doc.view,doc.dirty=nil,true
  doc.lastSample,doc.pendingChanges=self.clock,0
  local info=doc.session.info
  doc.nextCapture=self.clock+(info.capturePolicy=="Smart Sampling" and 2000 or info.intervalMs)
  self:append(doc, {kind="status", status="recording", source=self.store.source(doc.sprite)})
  doc.project.source=self.store.source(doc.sprite)
  self:remember(doc)
end
function Recorder:canResume(doc,session)
  assert(doc.sprite.hasAssociatedFile or not session.project.source,"Open the original artwork before resuming.")
  assert(not session.exporting,"Wait for the current export to finish.")
  assert(session.history.status~="stopped","Start a new session after stopping.")
  for _,other in pairs(self.documents) do
    assert(not (other~=doc and other.running and other.session and
      self.store.pathKey(other.session.folder)==self.store.pathKey(session.folder)),
      "This session is already recording in another document.")
  end
end
function Recorder:sample(doc, manual)
  if not doc.running or not doc.sprite.isValid then return end
  local info = doc.session.info
  if info.version~=4 and (doc.sprite.width ~= info.width or doc.sprite.height ~= info.height) then
    local crop = info.crop
    if crop and (crop.x+crop.w > doc.sprite.width or crop.y+crop.h > doc.sprite.height) then crop = nil end
    self:append(doc, {kind="status", status="stopped"})
    doc.running = false
    return self:start(doc, crop, info.initial)
  end
  local frame = doc.frame or 1
  if (manual or not doc.dirty) and app.sprite==doc.sprite and app.frame then frame=app.frame.frameNumber end
  frame=math.min(frame,#doc.sprite.frames)
  local image = render(doc.sprite, frame, info.version==4 and {} or info)
  local previous = doc.view
  if not previous and info.version==4 and doc.session.lastCapture then
    local last=doc.session.records[doc.session.lastCapture]
    local events=doc.session.history.events
    local lastFrame=frame
    for i=#events,1,-1 do if events[i].snapshot then lastFrame=events[i].frame or frame; break end end
    if last and last.w==image.width and last.h==image.height then previous={frame=lastFrame,image=self.store.loadNative(doc.session,doc.session.lastCapture)} end
  end
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
  doc.lastSample,doc.pendingChanges=self.clock,0
  doc.nextCapture = self.clock+(info.capturePolicy=="Smart Sampling" and 2000 or info.intervalMs)
end
function Recorder:capture(doc, fromUndo, manual)
  if not doc.running then return end
  if manual then return self:sample(doc, true) end
  doc.dirty = true
  if app.sprite==doc.sprite and app.frame then doc.frame=app.frame.frameNumber end
  local session=doc.session
  if session.info.capturePolicy=="Smart Sampling" then
    doc.pendingChanges=(doc.pendingChanges or 0)+1
    local interval=doc.pendingChanges>=6 and 500 or doc.pendingChanges>=3 and 1000 or 2000
    doc.nextCapture=math.min(doc.nextCapture,(doc.lastSample or self.clock)+interval)
  end
  if session.info.capturePolicy=="Every edit" and app.sprite==doc.sprite then
    self:guard(doc,function() self:sample(doc,false) end)
    return
  end
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
  local source = self.store.source(doc.sprite)
  if source and self.store.pathKey(source) ~= self.store.pathKey(doc.project and doc.project.source) then
    if doc.session and not doc.project.source then
      self.store:bind(doc.session, source)
      doc.project = doc.session.project
      self:remember(doc)
    else
      local running, info = doc.running, doc.session and doc.session.info
      if running then self:status(doc, "stopped") end
      self:findSession(doc, source)
      doc.autoAttempted = nil
      if running and not doc.session then self:start(doc, info.crop, info.initial) end
    end
  end
  doc.filename = doc.sprite.filename
end
function Recorder:findSession(doc, source)
  local key = self.store.pathKey(source)
  local remembered=key and self.preferences.sessionsBySource and self.preferences.sessionsBySource[key]
  if remembered and app.fs.isFile(remembered) then
    local candidate=self.store:open(remembered)
    if self.store.pathKey(candidate.project.source)==key then
      doc.session,doc.project=candidate,candidate.project
      return
    end
  end
  doc.session,doc.project=nil,self.store:project(doc.sprite, false)
  if not key then return end
  local unsaved = {folder=app.fs.joinPath(self.store:recordingFolder(), "_Unsaved"), title="Untitled", standalone=true}
  local latest
  for _, project in ipairs({unsaved, doc.project}) do
    for _, candidate in ipairs(self.store:sessions(project)) do
      local knownSource=candidate.info.source or (not project.standalone and project.source)
      if self.store.pathKey(knownSource or nil)==key and (not latest or candidate.name>latest.name) then
        latest=candidate
      end
    end
  end
  if latest then
    local loaded=self.store:load(latest)
    if self.store.pathKey(loaded.project.source)==key then doc.session,doc.project=loaded,loaded.project end
  end
end
function Recorder:changed(doc)
  if self.busy then return end
  local ok, sampled = self:guard(doc, function()
    if doc.filename ~= doc.sprite.filename or (doc.session and not doc.project.source and doc.sprite.hasAssociatedFile) then
      self:renamed(doc)
    end
    if doc.running or doc.autoAttempted then return end
    if app.sprite==doc.sprite and app.frame then doc.frame=app.frame.frameNumber end
    if doc.session then
      if self.preferences.autoResume ~= false and doc.session.history.status == "recording" and not doc.session.exporting then
        doc.autoAttempted=true
        self:resume(doc)
        self:sample(doc, false)
        return true
      end
    elseif self.preferences.autoRecord ~= false then
      doc.autoAttempted=true
      local crop=self.preferences.crop
      if crop and (crop.x+crop.w>doc.sprite.width or crop.y+crop.h>doc.sprite.height) then crop=nil end
      self:start(doc,crop,self.preferences.initial)
      if self.preferences.initial == false then self:sample(doc, false) end
      return true
    end
  end)
  if ok and not sampled then self:capture(doc) end
end
function Recorder:document(sprite)
  if self.documents[sprite.id] then return self.documents[sprite.id] end
  if sprite.properties["aselapsEdit"] then return nil end
  local doc = {sprite=sprite, filename=sprite.filename, events=sprite.events, listeners={}}
  self.documents[sprite.id] = doc
  for _, name in ipairs({"change", "layervisibility", "layeropacity", "layerblendmode"}) do
    doc.listeners[#doc.listeners+1] = sprite.events:on(name, function() self:changed(doc) end)
  end
  if not self:guard(doc, function() self:findSession(doc,self.store.source(sprite)) end) then
    doc.autoAttempted=true
  end
  return doc
end
function Recorder:site()
  if self.busy then return end
  for _,doc in pairs(self.documents) do
    if doc.running and doc.dirty and doc.sprite.isValid then
      self:guard(doc,function() self:flush(doc) end)
    end
  end
  if app.sprite then self:document(app.sprite) end
end
function Recorder:tick(milliseconds)
  if self.busy then return end
  self.clock = self.clock+(milliseconds or 250)
  for id, doc in pairs(self.documents) do
    if not doc.sprite.isValid then
      self:guard(doc, function()
        if doc.running then self:append(doc, {kind="status", status="recording"}) end
      end)
      self.documents[id] = nil
    end
  end
  if app.sprite then self:document(app.sprite) end
  for _,doc in pairs(self.documents) do
    self:guard(doc, function()
      if doc.filename ~= doc.sprite.filename or (doc.session and not doc.project.source and doc.sprite.hasAssociatedFile) then
        self:renamed(doc)
      end
      if doc.running and doc.dirty and self.clock >= doc.nextCapture then self:sample(doc, false) end
    end)
  end
end
function Recorder:watch()
  self.listeners[#self.listeners+1]=app.events:on("sitechange",function() self:site() end)
  self.listeners[#self.listeners+1]=app.events:on("beforecommand",function(ev)
    if ev.name=="CloseFile" or ev.name=="CloseAllFiles" or ev.name=="Exit" then self:tick(0); self:site() end
  end)
  self.listeners[#self.listeners+1]=app.events:on("aftercommand",function(ev)
    if ev.name=="SaveFile" or ev.name=="SaveFileAs" then self:tick(0) end
  end)
  self:tick(0)
end
function Recorder:shutdown()
  for _,id in ipairs(self.listeners) do app.events:off(id) end
  self.listeners={}
  for _, doc in pairs(self.documents) do
    self:guard(doc, function()
      if doc.sprite.isValid and not self.store.pathKey(doc.project and doc.project.source)
        and doc.session and doc.sprite.hasAssociatedFile then self:renamed(doc) end
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
