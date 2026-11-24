local fs = app.fs
local Ui = {}
Ui.__index = Ui
-- build.ps1 replaces this token using package.json; source runs remain labelled development.
Ui.version="@ASELAPS_VERSION@"

function Ui.new(recorder, export, preferences)
  return setmetatable({ recorder=recorder, export=export, preferences=preferences }, Ui)
end

local function duration(seconds)
  return string.format("%02d:%02d:%02d", seconds//3600, seconds//60%60, seconds%60)
end

local function projectLabel(session)
  return session.project.title .. " / " .. session.name
end

function Ui:attempt(action)
  local ok, result = pcall(action)
  if not ok then self:showError(result) end
  return ok, result
end

function Ui:showError(message)
  local detail=tostring(message)
  local brief=detail:gsub("^.-:%d+: ","")
  if app.alert{title="AseLaps",text=brief,buttons={"OK","Details"}}==2 then
    app.alert{title="AseLaps error details",text=detail}
  end
end

function Ui:runTask(title,work)
  assert(not self.task,"Wait for the current task to finish.")
  local control={cancelled=false}
  local finished,result,problem=false,nil,nil
  local dlg=Dialog{title=title,onclose=function() if not finished then control.cancelled=true end end}
  dlg:label{id="progress",text="Starting..."}
  dlg:button{id="cancel",text="Cancel",onclick=function()
    control.cancelled=true
    dlg:modify{id="cancel",enabled=false}
    dlg:modify{id="progress",text="Cancelling safely..."}
  end}
  local task=coroutine.create(function() return work(control) end)
  local timer
  timer=Timer{interval=0.02,ontick=function()
    timer:stop()
    local ok,value
    local started=os.clock()
    for _=1,16 do
      ok,value=coroutine.resume(task)
      if not ok or coroutine.status(task)=="dead" or os.clock()-started>=0.008
        or (value and (value.phase=="Encoding" or value.phase=="Cancelling encoder")) then break end
    end
    if not ok or coroutine.status(task)=="dead" then
      finished=true
      if ok then result=value else problem=value end
      dlg:close()
    else
      if value then dlg:modify{id="progress",text=string.format("%s: %d / %d",value.phase,value.done or 0,value.total or 0)} end
      timer:start()
    end
  end}
  self.task={control=control,timer=timer}
  timer:start()
  repeat dlg:show{autoscrollbars=true} until finished
  timer:stop()
  self.task=nil
  if problem and not control.cancelled then error(problem,0) end
  return result
end

function Ui:document()
  local sprite = app.sprite
  return sprite and self.recorder.documents[sprite.id]
end

function Ui:session()
  local doc = self:document()
  if self.selected then
    for _, item in pairs(self.recorder.documents) do
      if item.session and item.session.folder == self.selected.folder then return item.session end
    end
    return self.selected
  end
  return doc and doc.session
end

function Ui:record(action)
  self.recorder:tick(0)
  local doc = self:document()
  if not doc then return end
  self.recorder:guard(doc, function() action(doc) end)
  self:refresh()
end

function Ui:refresh()
  local dlg = self.main
  if not dlg then return end
  local sprite = app.sprite
  local doc = self:document()
  local session = doc and doc.session
  local selected = self:session()
  local status = "Ready"
  if session then
    if doc.running then
      status = "Recording"
    elseif session.faulted then
      status = "Storage error - check free space, then Resume"
    elseif session.history.status == "stopped" then
      status = "Stopped"
    else
      status = "Paused"
    end
  end
  local function label(id, value)
    if self.labels[id] ~= value then
      self.labels[id] = value
      dlg:modify{ id=id, text=value }
    end
  end
  label("project", sprite and fs.fileName(sprite.filename) or "No document")
  label("canvas", sprite and string.format("%d x %d px", sprite.width, sprite.height) or "-")
  label("session", session and session.name or "-")
  label("status", status)
  label("time", duration(self.recorder.elapsed(doc)))
  local last = "No captures yet"
  if session and session.history.count > 0 then
    if self.lastSession ~= session or self.lastCount ~= session.history.count then
      self.lastSession, self.lastCount = session, session.history.count
      local events = session.history.events
      for i = #events, 1, -1 do
        local event = events[i]
        if event.snapshot or event.png then
          self.lastSaved = string.format("#%s at %s", event.snapshot or event.png, duration(event.elapsed or 0))
          break
        end
      end
    end
    last = self.lastSaved or "-"
  end
  label("count", last)
  label("selected", selected and projectLabel(selected) or "-")
  local hint=""
  if not sprite then hint="Open artwork, save it, then choose New Recording."
  elseif not sprite.hasAssociatedFile then hint="Save this artwork before starting a recording." end
  label("notice", self.notice or (selected and selected.recovered and "Recovered to the last valid record. Original data is preserved.") or hint)
  local function enable(id, value)
    value = not not value
    if self.enabled[id] ~= value then
      self.enabled[id] = value
      dlg:modify{ id=id, enabled=value }
    end
  end
  local resumable = session and session.info.version >= 2 and (session.faulted or session.history.status ~= "stopped")
  enable("start", doc and sprite.hasAssociatedFile and not doc.running and not resumable)
  enable("pause", doc and doc.running)
  enable("resume", resumable and not doc.running)
  enable("stop", resumable)
  enable("snapshot", doc and doc.running)
  enable("history", selected)
  enable("export", selected)
  enable("current", self.selected)
end

function Ui:show()
  if self.main then self.main:close() end
  local version=Ui.version
  if version:sub(1,1)=="@" then version="development" end
  local dlg = Dialog{ title="AseLaps "..version, resizeable=false, onclose=function() self.main = nil end }
  self.main, self.labels, self.enabled = dlg, {}, {}
  dlg:label{ id="project", label="Document", text="-" }
  dlg:label{ id="canvas", label="Canvas", text="-" }
  dlg:label{ id="session", label="Recording session", text="-" }
  dlg:label{ id="status", label="Status", text="-" }
  dlg:label{ id="time", label="Elapsed", text="00:00:00" }
  dlg:label{ id="count", label="Last saved capture", text="-" }
  dlg:button{ id="start", text="New Recording...", onclick=function()
    self:record(function(doc)
      self.selected, self.notice = nil, nil
      assert(doc.sprite.hasAssociatedFile, "Save the artwork before recording.")
      local root = fs.joinPath(self.recorder.store:recordingFolder(), fs.fileTitle(doc.sprite.filename) .. "__record")
      local selected = self:pickFile("New recording: choose session location", fs.joinPath(root, os.date("%Y%m%d_%H%M%S") .. ".json"), true, {"json"})
      if not selected then return end
      local folder = fs.joinPath(fs.filePath(selected), fs.fileTitle(selected))
      self.recorder:start(doc, self.preferences.crop, self.preferences.initial, folder)
      self.preferences.lastRecordingFolder = fs.filePath(selected)
    end)
  end }
  dlg:button{ id="pause", text="Pause", onclick=function()
    self:record(function(doc) self.recorder:status(doc, "paused") end)
  end }
  dlg:button{ id="resume", text="Resume", onclick=function()
    self:record(function(doc)
      self.notice = nil
      self.recorder:resume(doc)
    end)
  end }
  dlg:newrow()
  dlg:button{ id="stop", text="Stop", onclick=function()
    self:record(function(doc) self.recorder:status(doc, "stopped") end)
  end }
  dlg:button{ id="snapshot", text="Snapshot", onclick=function()
    self:record(function(doc) self.recorder:capture(doc, false, true) end)
  end }
  dlg:button{ text="Hide", onclick=function() dlg:close() end }
  dlg:label{ text="Pause: resume later. Stop: finish this session. Hide: keep recording." }
  dlg:separator{ text="Review and export" }
  dlg:label{ id="selected", label="Selected session", text="-" }
  dlg:button{ text="Open Session...", onclick=function() self:attempt(function() self:sessions() end) end }
  dlg:button{text="Resume Selected",onclick=function()
    self:attempt(function()
      local session=assert(self:session(),"Open a session first.")
      local doc=assert(self:document(),"Open the artwork to resume recording.")
      assert(not doc.running,"Pause the current recording first.")
      self.recorder:canResume(doc,session)
      if session.info.version < 4 then
        assert(doc.sprite.width==session.info.width and doc.sprite.height==session.info.height,"Canvas size differs from this session.")
      end
      if self.recorder.store.source(doc.sprite)~=session.project.source then
        assert(app.alert{title="Link artwork",text="Resume this session with the current artwork?",buttons={"Resume","Cancel"}}==1,"Resume cancelled.")
      end
      local previousSession,previousProject=doc.session,doc.project
      doc.session,doc.project=session,session.project
      local ok=self.recorder:guard(doc,function() self.recorder:resume(doc) end)
      if not ok then doc.session,doc.project=previousSession,previousProject end
      self.selected=nil; self:refresh()
    end)
  end}
  dlg:button{ id="current", text="Use Current", onclick=function()
    self.selected = nil
    self:refresh()
  end }
  dlg:newrow()
  dlg:button{ id="history", text="Frame History...", onclick=function()
    self:attempt(function() self:history(assert(self:session())) end)
  end }
  dlg:button{ id="export", text="Preview and Export...", onclick=function()
    self:attempt(function() self:exportDialog(assert(self:session())) end)
  end }
  dlg:newrow()
  dlg:separator{text="Advanced"}
  dlg:check{id="advanced",text="Show editing and legacy tools",selected=false,onclick=function()
    for _,id in ipairs({"applyEdit","exportAnimation","legacy"}) do dlg:modify{id=id,visible=dlg.data.advanced} end
  end}
  dlg:newrow()
  dlg:button{id="applyEdit",visible=false,text="Apply Edit to Session",onclick=function() self:attempt(function() self:applyEdit() end) end}
  dlg:button{id="exportAnimation",visible=false,text="Export Edited Animation",onclick=function() self:attempt(function() self:exportAnimation() end) end}
  dlg:newrow()
  dlg:separator{text="Files and settings"}
  dlg:button{id="legacy",visible=false,text="Open Legacy Folder",onclick=function() self:attempt(function() self.export.openFolder(self.recorder.store,self.recorder.store.root) end) end}
  dlg:button{ text="Settings", onclick=function() self:settings() end }
  dlg:button{ text="Open Folder", onclick=function()
    self:attempt(function()
      local session = self:session()
      local store = self.recorder.store
      store.ensureDirectory(store.root)
      self.export.openFolder(store, session and session.folder or store.root)
    end)
  end }
  dlg:label{ id="notice", text="" }
  self:refresh()
  dlg:show{ wait=false, autoscrollbars=true }
end

function Ui:settings()
  local prefs = self.preferences
  local crop = prefs.crop or {}
  local sprite = app.sprite
  local dlg = Dialog{ title="AseLaps Settings" }
  dlg:entry{id="recordingFolder",label="Recording folder",text=self.recorder.store:recordingFolder()}
  dlg:label{text="Choose a local folder outside OneDrive. Existing sessions stay in place."}
  dlg:check{ id="initial", label="New sessions", text="Initial snapshot", selected=prefs.initial ~= false }
  dlg:check{ id="auto", label="On reopen", text="Auto-resume recording", selected=prefs.autoResume ~= false }
  local intervals = {[500]="0.5 seconds", [1000]="1 second", [2000]="2 seconds"}
  dlg:combobox{ id="interval", label="Capture while drawing", options={"0.5 seconds", "1 second", "2 seconds"},
    option=intervals[prefs.intervalMs or 500] }
  dlg:file{ id="ffmpeg", label="FFmpeg", title="Select ffmpeg.exe", open=true, entry=true,
    filename=self.export.encoderPath(prefs.ffmpeg), filetypes={"exe"} }
  dlg:button{text="Check FFmpeg",onclick=function() self:attempt(function()
    self.export.checkEncoder(self.recorder.store,dlg.data.ffmpeg)
    app.alert("FFmpeg is ready.")
  end) end}
  dlg:label{text="MP4/GIF: get a Windows build from ffmpeg.org/download.html."}
  dlg:newrow()
  dlg:label{text="Extract it, then select bin/ffmpeg.exe. PNG export needs no FFmpeg."}
  dlg:separator{ text="Capture area for new sessions" }
  dlg:combobox{ id="area", label="Area", options={"Full canvas", "Fixed crop"},
    option=prefs.crop and "Fixed crop" or "Full canvas" }
  dlg:number{ id="x", label="Left / top", text=tostring(crop.x or 0) }
  dlg:number{ id="y", text=tostring(crop.y or 0) }
  dlg:number{ id="w", label="Width / height", text=tostring(crop.w or (sprite and sprite.width) or 1) }
  dlg:number{ id="h", text=tostring(crop.h or (sprite and sprite.height) or 1) }
  dlg:label{ label="Layers", text="Visible artwork (reference layers excluded)" }
  dlg:button{ text="Save", onclick=function()
    self:attempt(function()
      local data = dlg.data
      assert(self.export.isAbsolute(data.recordingFolder),"Choose an absolute recording folder.")
      self.recorder.store.assertLocalPath(data.recordingFolder)
      local area
      if data.area == "Fixed crop" then
        area = {
          x=math.tointeger(data.x), y=math.tointeger(data.y),
          w=math.tointeger(data.w), h=math.tointeger(data.h)
        }
        assert(area.x and area.y and area.w and area.h and area.x >= 0 and area.y >= 0
          and area.w > 0 and area.h > 0, "Enter a positive crop size and nonnegative coordinates.")
      end
      local intervals = {["0.5 seconds"]=500, ["1 second"]=1000, ["2 seconds"]=2000}
      prefs.intervalMs = intervals[data.interval]
      local encoder = data.ffmpeg
      if encoder and encoder ~= "" then
        assert(self.export.isAbsolute(encoder), "Choose an absolute FFmpeg path.")
        encoder = fs.normalizePath(encoder)
      end
      prefs.initial, prefs.autoResume, prefs.ffmpeg, prefs.crop = data.initial, data.auto, encoder, area
      prefs.recordingFolder=fs.normalizePath(data.recordingFolder)
      dlg:close()
    end)
  end }
  dlg:button{ text="Cancel" }
  dlg:show{autoscrollbars=true}
end

function Ui:pickFile(title, filename, save, types)
  if not pcall(self.recorder.store.assertLocalPath,filename) then
    filename=fs.joinPath(self.recorder.store.recordingRoot(),fs.fileName(filename))
  end
  local picker = Dialog{title=title}
  picker:file{id="path", label="File", filename=filename, open=not save, save=save, entry=true, filetypes=types}
  picker:button{id="ok", text="OK"}
  picker:button{text="Cancel"}
  picker:show()
  if picker.data.ok and picker.data.path ~= "" then
    assert(self.export.isAbsolute(picker.data.path), "Choose an absolute file path.")
    local path = fs.normalizePath(picker.data.path)
    if save then self.recorder.store.assertLocalPath(path) end
    return path
  end
end

function Ui:sessions()
  local initial = self.preferences.lastSessionFolder or self.recorder.store.root
  local path = self:pickFile("Open AseLaps session", fs.joinPath(initial,"session.json"),false,{"json"})
  if not path then return end
  local session = self.recorder.store:open(path)
  for _, doc in pairs(self.recorder.documents) do
    if doc.session and doc.session.folder == session.folder then session = doc.session end
  end
  self.selected = session
  self.preferences.lastSessionFolder = fs.filePath(path)
  self:refresh()
end

function Ui:assertPaused(session)
  assert(not session.exporting,"Wait for the current export to finish.")
  for _, doc in pairs(self.recorder.documents) do
    assert(not (doc.running and doc.session.folder == session.folder), "Pause this recording before editing.")
  end
end

function Ui:editRange(session)
  self:assertPaused(session)
  local store = self.recorder.store
  local frames = store.timeline(session,"Full")
  assert(#frames > 0, "No frames to edit.")
  local dlg = Dialog{title="Edit range (review order)"}
  local update
  dlg:number{id="first",label="First position",text="1",onchange=function() if update then update() end end}
  dlg:number{id="last",label="Last position",text=tostring(math.min(#frames,100)),onchange=function() if update then update() end end}
  dlg:label{id="memory",text=""}
  update=function()
    local count = math.max(0,math.floor(dlg.data.last)-math.floor(dlg.data.first)+1)
    dlg:modify{id="memory",text=string.format("%d frames / %.1f MiB raw image data",count,count*session.info.captureWidth*session.info.captureHeight*4/1048576)}
  end
  dlg:button{id="ok",text="Open in Aseprite"}
  dlg:button{text="Cancel"}
  update(); dlg:show()
  if not dlg.data.ok then return end
  local first,last = math.tointeger(dlg.data.first), math.tointeger(dlg.data.last)
  assert(first and last and first>=1 and last<=#frames and first<=last,"Invalid range.")
  local sprite = Sprite(session.info.captureWidth,session.info.captureHeight,ColorMode.RGB)
  sprite.properties["aselapsEdit"] = json.encode({session=fs.joinPath(session.folder,"session.json"), first=frames[first],last=frames[last],revision=session.editRevision})
  app.transaction("Open timelapse range",function()
    for i=first,last do
      local frame = sprite.frames[1]
      if i>first then frame = sprite:newEmptyFrame() end
      sprite:newCel(sprite.layers[1],frame,store.loadSnapshot(session,frames[i]))
      frame.duration = 1/24
    end
  end)
  self.selected = session
end

function Ui:applyEdit()
  local sprite = assert(app.sprite,"Open the edited animation first.")
  local data = sprite.properties["aselapsEdit"]
  assert(data,"This is not an AseLaps edit document.")
  local metadata = json.decode(data)
  local store = self.recorder.store
  local session = store:open(metadata.session)
  self:assertPaused(session)
  assert(session.editRevision == metadata.revision,"The session changed. Reopen the range before applying edits.")
  assert(sprite.width==session.info.captureWidth and sprite.height==session.info.captureHeight,"Keep the original canvas size.")
  local folder = store.numberedDirectory(fs.joinPath(session.folder,"edits"),"range")
  local paths = {}
  for i,frame in ipairs(sprite.frames) do
    local relative = "edits/" .. fs.fileName(folder) .. "/" .. string.format("%06d.png",i)
    store.writeImage(self.recorder.render(sprite,frame.frameNumber,{}),fs.joinPath(session.folder,relative))
    paths[#paths+1] = relative
  end
  store.edit(session,{kind="replace",first=metadata.first,last=metadata.last,frames=paths})
  metadata.revision = session.editRevision
  metadata.first,metadata.last = paths[1],paths[#paths]
  sprite.properties["aselapsEdit"] = json.encode(metadata)
  for _, doc in pairs(self.recorder.documents) do
    if doc.session and doc.session.folder==session.folder then doc.session=store:load(session) end
  end
  self.selected = session
  self:refresh()
end

function Ui:history(session)
  local store = self.recorder.store
  local history = session.history
  local rows = {}
  local bySnapshot={}
  for _,event in ipairs(history.events) do
    local id=event.snapshot or event.png
    if id then bySnapshot[tostring(id)]=event end
  end
  local frames=store.timeline(session,"Full",nil,true,true)
  for _,id in ipairs(frames) do rows[#rows+1]=bySnapshot[tostring(id)] or {snapshot=id,label="Edited frame"} end
  for _,id in ipairs(session.orphans) do rows[#rows+1]={png=id,label="Recovered snapshot"} end

  assert(#rows > 0, "This session has no history to show.")

  local index, preview = #rows, nil
  local excluded = {}
  for _, op in ipairs(session.editOps) do
    if op.kind == "exclude" then for _, id in ipairs(op.ids) do excluded[tostring(id)] = op.value end end
  end
  local dlg = Dialog{ title="AseLaps History" }
  local function update(nextIndex)
    index = math.max(1, math.min(nextIndex, #rows))
    local item = rows[index]
    local node = history.nodes[item.id]
    local detail = item.label
    local snapshotId = item.snapshot or item.png
    if type(snapshotId)=="number" then detail = detail .. string.format(" / Original %06d.png",snapshotId)
    else detail=detail .. " / " .. tostring(snapshotId) end
    if excluded[tostring(snapshotId)] then detail = detail .. " / EXCLUDED" end
    if item.id then detail = string.format("#%d  %s", item.id, detail) end
    if item.frame then detail = detail .. "  /  Frame " .. item.frame end
    if node and session.info.version == 1 then
      if node.uncertain then
        detail = detail .. "  /  Unresolved parent"
      else
        detail = detail .. "  /  Parent #" .. node.parent
      end
      if history.head == node.id then detail = detail .. "  /  Current head" end
    elseif item.head then
      detail = detail .. "  /  State #" .. item.head
    end
    preview = nil
    local snapshot = item.snapshot or item.png
    if snapshot then
      local ok, image = pcall(store.loadSnapshot, session, snapshot)
      if ok then
        preview = image
      else
        detail = detail .. "  /  Cannot load snapshot #" .. snapshot
      end
    end
    dlg:modify{ id="counter", text=string.format("%d / %d", index, #rows) }
    dlg:modify{ id="detail", text=detail }
    dlg:modify{ id="prev", enabled=index > 1 }
    dlg:modify{ id="next", enabled=index < #rows }
    dlg:modify{ id="open", enabled=preview ~= nil }
    dlg:modify{ id="extract", enabled=preview ~= nil }
    if session.info.version == 1 then
    dlg:modify{ id="resolve", enabled=node and node.uncertain or false }
    dlg:modify{ id="branch", enabled=node ~= nil or item.head ~= nil }
    end
    dlg:repaint()
  end

  dlg:label{ label="Session", text=projectLabel(session) }
  dlg:label{ id="counter", label="Entry", text="" }
  dlg:label{ id="detail", text="" }
  dlg:canvas{ id="preview", width=252, height=160, onpaint=function(ev)
    if not preview then return end
    local scale = math.min(240/preview.width, 150/preview.height)
    if scale >= 1 then scale = math.floor(scale) end
    local w, h = math.max(1, math.floor(preview.width*scale)), math.max(1, math.floor(preview.height*scale))
    ev.context:drawImage(preview, preview.bounds, Rectangle((252-w)//2, (160-h)//2, w, h))
  end }
  dlg:button{ id="prev", text="Previous", onclick=function() update(index-1) end }
  dlg:button{ id="next", text="Next", onclick=function() update(index+1) end }
  dlg:newrow()
  dlg:number{ id="entry", label="Go to entry", text=tostring(index) }
  dlg:button{ text="Go", onclick=function() update(math.floor(dlg.data.entry or 1)) end }
  dlg:newrow()
  dlg:button{ id="open", text="Open Snapshot", onclick=function()
    self:attempt(function()
      local image = assert(preview)
      local sprite = Sprite(image.width, image.height, ColorMode.RGB)
      sprite:newCel(sprite.layers[1], 1, image)
    end)
  end }
  dlg:button{ id="extract", text="Export PNG", onclick=function()
    local id = rows[index].snapshot or rows[index].png
    local picker = Dialog{ title="Extract AseLaps Snapshot" }
    picker:file{ id="file", label="Save as", save=true, open=false, entry=true,
      filename="AseLaps_" .. tostring(id):gsub("[/%.]","_") .. ".png", filetypes={"png"} }
    picker:button{ text="Save", onclick=function()
      self:attempt(function()
        local path = picker.data.file
        assert(fs.fileExtension(path):lower() == "png", "Choose a .png filename.")
        assert(not fs.isFile(path), "Choose an unused filename.")
        store.writeImage(store.loadSnapshot(session, id), path)
        picker:close()
      end)
    end }
    picker:button{ text="Cancel" }
    picker:show()
  end }
  dlg:newrow()
  if session.info.version == 1 then
  dlg:button{ id="resolve", text="Set Parent", onclick=function()
    local node = rows[index]
    local picker = Dialog{ title="Resolve AseLaps Branch" }
    picker:label{ text="Enter an earlier state ID shown in History. Use 0 to start a new branch." }
    picker:number{ id="parent", label="Parent state ID", text="0" }
    picker:button{ text="Apply", onclick=function()
      self:attempt(function()
        local parent = math.tointeger(picker.data.parent)
        assert(parent and (parent == 0 or history.nodes[parent] and parent < node.id),
          "Choose an earlier state ID or 0.")
        store.append(session, { kind="link", node=node.id, parent=parent })
        picker:close()
        update(index)
      end)
    end }
    picker:button{ text="Cancel" }
    picker:show()
  end }
  dlg:button{ id="branch", text="Export This Branch", onclick=function()
    local item = rows[index]
    self:exportDialog(session, item.head or item.id)
  end }
  end
  dlg:entry{id="ids",label="Original IDs / ranges",text="",tooltip="Example: 257, 300-350"}
  local function exclude(value)
    self:attempt(function()
      self:assertPaused(session)
      local ids = {}
      local text = dlg.data.ids
      if text:match("^%s*$") then text=tostring(rows[index].snapshot or rows[index].png) end
      if type(rows[index].snapshot)=="string" and text==tostring(rows[index].snapshot) then
        ids[1]=rows[index].snapshot
      else
      for token in text:gmatch("[^,]+") do
        local first,last = token:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
        if not first then first=token:match("^%s*(%d+)%s*$"); last=first end
        first,last=tonumber(first),tonumber(last)
        assert(first and last and first<=last and last-first<1000000,"Use IDs such as 257, 300-350.")
        for id=first,last do assert(history.snapshots[id],"Unknown original ID: "..id); ids[#ids+1]=id end
      end
      end
      assert(#ids>0,"Enter a frame ID.")
      store.edit(session,{kind="exclude",ids=ids,value=value})
      for _,id in ipairs(ids) do excluded[tostring(id)]=value end
      update(index)
    end)
  end
  dlg:button{text="Exclude",onclick=function() exclude(true) end}
  dlg:button{text="Restore",onclick=function() exclude(false) end}
  dlg:button{text="Undo Last Edit",onclick=function()
    self:attempt(function()
      self:assertPaused(session)
      assert(#session.editOps>0,"No edit to undo.")
      store.edit(session,{kind="undo"})
      dlg:close(); self:history(session)
    end)
  end}
  dlg:newrow()
  dlg:button{text="Edit Range...",onclick=function() self:attempt(function() self:editRange(session) end) end}
  dlg:button{text="Convert to PNG Copy...",onclick=function()
    self:attempt(function()
      self:assertPaused(session)
      local path=self:pickFile("PNG copy location",fs.joinPath(self.preferences.lastRecordingFolder or session.project.folder,"PNG_copy.json"),true,{"json"})
      if not path then return end
      self.selected=store:convert(session,fs.filePath(path)); self:refresh()
    end)
  end}
  dlg:button{ text="Close" }
  update(index)
  dlg:show{ autoscrollbars=true }
end

function Ui:exportAnimation()
  local sprite = assert(app.sprite,"Open an animation first.")
  assert(sprite.properties["aselapsEdit"],"Open an AseLaps edit document first.")
  local store = self.recorder.store
  local root = store.numberedDirectory(fs.tempPath,"AseLaps-animation")
  local project = {folder=root,title="Edited animation",standalone=true}
  local session = store:create(project,{version=3,captureMode="sampled",intervalMs=500,width=sprite.width,height=sprite.height,captureWidth=sprite.width,captureHeight=sprite.height,rowStride=sprite.width*4})
  for _,frame in ipairs(sprite.frames) do
    local id=store.saveSnapshot(session,self.recorder.render(sprite,frame.frameNumber,{}))
    store.append(session,{kind="state",parent=session.history.head,snapshot=id,emit=true,label="Edited animation"})
  end
  self:exportDialog(session,nil,true)
end

local function drawPreview(ctx, image, geometry, background, width, height, left, top)
  if not image or not geometry then return end
  local scale = math.min(width / geometry.outWidth, height / geometry.outHeight)
  local w = math.max(1, math.floor(geometry.outWidth * scale))
  local h = math.max(1, math.floor(geometry.outHeight * scale))
  local x, y = (left or 0)+(width-w)//2, (top or 0)+(height-h)//2
  ctx.color = background == "Black" and Color{r=0,g=0,b=0} or Color{r=255,g=255,b=255}
  ctx:fillRect(Rectangle(x,y,w,h))
  if background == "Transparent" then
    ctx.color = Color{r=200,g=200,b=200}
    for row=0,h-1,8 do
      for col=(row//8%2)*8,w-1,16 do
        ctx:fillRect(Rectangle(x+col,y+row,math.min(8,w-col),math.min(8,h-row)))
      end
    end
  end
  ctx:drawImage(image, image.bounds, Rectangle(x+math.floor(geometry.x*scale), y+math.floor(geometry.y*scale),
    math.max(1,math.floor(geometry.width*scale)), math.max(1,math.floor(geometry.height*scale))))
end

local function showPreview(dlg, afterShow)
  -- A canvas has no drawable surface until the modal dialog is visible.
  local firstPaint
  firstPaint = Timer{interval=0.02,ontick=function()
    firstPaint:stop()
    if afterShow then afterShow() end
    dlg:repaint()
  end}
  firstPaint:start()
  dlg:show{autoscrollbars=true}
  firstPaint:stop()
end

function Ui:alignResize(session)
  self:assertPaused(session)
  local store = self.recorder.store
  local names, options, first = {}, {}, nil
  for _, boundary in ipairs(session.boundaries) do
    local name = string.format("#%d   %dx%d to %dx%d%s", boundary.id, boundary.oldWidth, boundary.oldHeight,
      boundary.width, boundary.height, boundary.uncertain and "   (review)" or "")
    names[name] = boundary
    options[#options+1] = name
    if boundary.uncertain and not first then first = name end
  end
  local dlg = Dialog{title="Align a canvas resize"}
  local boundary, before, after, comparison, geometry
  local function redraw()
    if not before then return end
    local data = dlg.data
    local x, y = math.tointeger(data.dx), math.tointeger(data.dy)
    if not x or not y then return end
    comparison = Image(after.width,after.height,ColorMode.RGB)
    if data.view ~= "After" then comparison:drawImage(before, Point(x,y)) end
    if data.view ~= "Before" then
      comparison:drawImage(after,Point(0,0),data.view == "Overlay" and 128 or 255)
    end
    dlg:repaint()
  end
  local function selectBoundary()
    boundary = names[dlg.data.boundary]
    if boundary.id>1 then
      before = store.loadNative(session,boundary.id-1)
    else
      before = Image(boundary.oldWidth,boundary.oldHeight,ColorMode.RGB)
    end
    after = store.loadNative(session,boundary.id)
    geometry = {width=after.width,height=after.height,outWidth=after.width,outHeight=after.height,x=0,y=0}
    dlg:modify{id="dx",text=tostring(boundary.dx)}
    dlg:modify{id="dy",text=tostring(boundary.dy)}
    dlg:modify{id="firstBoundary",visible=boundary.id==1}
    redraw()
  end
  dlg:combobox{id="boundary",label="Resize at capture",options=options,option=first or options[1],onchange=selectBoundary}
  dlg:combobox{id="view",label="Compare",options={"Overlay","Before","After"},onchange=redraw}
  dlg:label{id="firstBoundary",text="No capture was saved before this resize.",visible=false}
  dlg:canvas{width=280,height=142,onpaint=function(ev)
    drawPreview(ev.context,comparison,geometry,"Transparent",280,142)
  end}
  dlg:number{id="dx",label="Move earlier artwork right / down (px)",text="0",onchange=redraw}
  dlg:number{id="dy",text="0",onchange=redraw}
  dlg:button{text="Apply alignment",onclick=function()
    self:attempt(function()
      local x,y = math.tointeger(dlg.data.dx),math.tointeger(dlg.data.dy)
      assert(x and y,"Enter whole-pixel offsets.")
      store.setAlignment(session,boundary.id,x,y)
      dlg:close()
    end)
  end}
  dlg:button{text="Cancel"}
  selectBoundary()
  showPreview(dlg)
end

function Ui:exportDialog(session, head, animation)
  local store,prefs=self.recorder.store,self.preferences
  for _,doc in pairs(self.recorder.documents) do
    if doc.running and store.pathKey(doc.session.folder)==store.pathKey(session.folder) then
      self.recorder:status(doc,"paused")
      session=doc.session
      self.notice="Recording paused for preview and export. Use Resume to continue."
    end
  end
  self:refresh()
  local saved=prefs.exportOptions or {}
  local timer, closed
  local dlg = Dialog{title="Preview and Export",onclose=function()
    closed=true
    if timer then timer:stop() end
  end}
  local sequences, missing, timelines = {}, {}, {}
  local sequence, frame, image, geometry, sourcePositions = {}, 1, nil, nil, {}
  local ready, changing, playing = false, false, false
  local nearby, background, valid = {}, nil, false
  local playbackFrames, preparing
  local previewRevision=session.editRevision
  local function stop()
    if timer then timer:stop() end
    playing = false
    dlg:modify{id="play",text="Play"}
  end
  local function seek(position)
    frame = math.max(1,math.min(position,#sequence))
    local id = sequence[frame]
    local nextCache = {}
    local radius = playing and 0 or 1
    for i=math.max(1,frame-radius), math.min(#sequence,frame+radius) do
      local neighbor = sequence[i]
      nextCache[neighbor] = playbackFrames and playbackFrames[neighbor]
        or nearby[neighbor] or store.loadSnapshot(session,neighbor)
    end
    nearby = nextCache
    image = nearby[id]
    changing = true
    dlg:modify{id="scrub",min=1,max=math.max(2,#sequence),value=frame,enabled=#sequence>1}
    changing = false
    local detail = id and string.format("Output %d of %d   /   Recorded position %d",frame,#sequence,sourcePositions[tostring(id)] or frame) or "No frames"
    dlg:modify{id="position",text=detail}
    dlg:modify{id="back",enabled=frame>1}
    dlg:modify{id="forward",enabled=frame<#sequence}
    dlg:repaint()
  end
  local function move(position)
    if preparing or closed then return false end
    local ok, message = pcall(seek, position)
    if not ok then
      stop()
      app.alert{title="AseLaps",text=tostring(message)}
    end
    return ok
  end
  local function update()
    if not ready or preparing then return end
    stop()
    valid = false
    if previewRevision~=session.editRevision then
      previewRevision=session.editRevision
      playbackFrames,nearby,timelines=nil,{},{}
    end
    local data = dlg.data
    local ok, result = pcall(function()
      local step, fps = math.tointeger(data.step), math.tointeger(data.fps)
      local hold=tonumber(data.hold)
      assert(hold and hold>=0 and hold<=60,"Final hold must be between 0 and 60 seconds.")
      assert(step and step>=1 and step<=1000,"Use every 1 to 1000 recorded frames.")
      assert(fps and fps>=1 and fps<=60,"Choose 1 to 60 FPS.")
      assert(data.format ~= "MP4" or data.background ~= "Transparent","Choose a white or black background for MP4.")
      geometry = self.export.layout(session.info,data)
      background = data.background
      local modes = data.mode == "Both" and {"Full","Clean"} or {data.mode}
      local summaries = {}
      sequences, missing = {}, {}
      for _,mode in ipairs(modes) do
        local timeline = timelines[mode]
        if not timeline then
          local frames, absent = store.timeline(session,mode,head)
          local all = store.timeline(session,mode,head,true)
          local positions = {}
          for i,id in ipairs(all) do positions[tostring(id)]=i end
          timeline = {frames=frames,missing=absent,all=all,positions=positions}
          timelines[mode] = timeline
        end
        sequences[mode] = self.export.sample(timeline.frames,step)
        for _,id in ipairs(timeline.missing) do missing[tostring(id)]=true end
        local count = #sequences[mode]
        local outputCount=count+math.floor(hold*fps+0.5)
        summaries[#summaries+1] = string.format("%s%d frames / %.2f sec",data.mode=="Both" and mode.." " or "",outputCount,outputCount/fps)
      end
      local mode = data.mode == "Both" and data.previewMode or data.mode
      local nextSequence=sequences[mode]
      if #nextSequence~=#sequence then playbackFrames=nil
      elseif playbackFrames then
        for i,id in ipairs(nextSequence) do
          if id~=sequence[i] then playbackFrames=nil; break end
        end
      end
      sequence,sourcePositions = nextSequence,timelines[mode].positions
      seek(frame)
      for _,modeName in ipairs(modes) do
        assert(#sequences[modeName]>0,"No frames included. Restore a recorded range.")
      end
      return string.format("%dx%d px   |   ",geometry.outWidth,geometry.outHeight)..table.concat(summaries,"   |   ")
    end)
    valid = ok
    if not ok then
      sequence, image, nearby = {}, nil, {}
      seek(1)
    end
    dlg:modify{id="previewMode",visible=data.mode=="Both"}
    dlg:modify{id="encoder",visible=data.format~="PNG sequence"}
    dlg:modify{id="play",enabled=ok and #sequence>1}
    dlg:modify{id="save",enabled=ok}
    dlg:modify{id="size",text=ok and result or tostring(result):gsub("^.-:%d+: ","")}
  end
  local active = self:document()
  local scope = active and active.session and active.session.folder == session.folder and "Current recording" or "Selected session"
  dlg:label{label=animation and "Source" or scope,text=animation and "Edited animation" or projectLabel(session)}
  if active and active.session and active.session.folder ~= session.folder and not animation then
    dlg:label{label="Current artwork session",text=projectLabel(active.session)}
  end
  dlg:canvas{id="film",width=280,height=116,onpaint=function(ev)
    local ctx = ev.context
    local side = 44
    drawPreview(ctx,image,geometry,background,ctx.width-2*side,ctx.height,side,0)
    if not playing then
      drawPreview(ctx,nearby[sequence[frame-1]],geometry,background,side-4,40,0,(ctx.height-40)//2)
      drawPreview(ctx,nearby[sequence[frame+1]],geometry,background,side-4,40,ctx.width-side,(ctx.height-40)//2)
    end
  end}
  dlg:slider{id="scrub",label="Output frame",min=1,max=2,value=1,onchange=function()
    if ready and not changing then stop(); move(dlg.data.scrub) end
  end}
  dlg:button{id="back",text="Previous",onclick=function() stop(); move(frame-1) end}
  dlg:button{id="play",text="Play",onclick=function()
    if preparing then return end
    if playing then stop(); move(frame); return end
    if not valid or #sequence<2 then return end
    if not playbackFrames then
      preparing=true
      dlg:modify{id="play",text="Preparing preview...",enabled=false}
      local ok, frames=pcall(function() return self:runTask("Preparing preview",function(control)
        local cache={}
        local w,h=session.info.captureWidth,session.info.captureHeight
        local scale=math.min(1,192/math.max(w,h),math.sqrt(48*1024*1024/(4*w*h*#sequence)))
        local size=Size(math.max(1,math.floor(w*scale)),math.max(1,math.floor(h*scale)))
        for i,id in ipairs(sequence) do
          coroutine.yield({phase="Preparing preview",done=i-1,total=#sequence})
          if closed or control.cancelled then return end
          if not cache[id] then
            local thumbnail=store.loadSnapshot(session,id)
            if thumbnail.width~=size.width or thumbnail.height~=size.height then
              thumbnail:resize(size.width,size.height)
            end
            cache[id]=thumbnail
          end
        end
        return cache
      end) end)
      preparing=false
      if closed then return end
      dlg:modify{id="play",text="Play",enabled=true}
      if not ok then app.alert{title="AseLaps",text=tostring(frames)}; return end
      if not frames then return end
      playbackFrames=frames
    end
    if frame==#sequence and not move(1) then return end
    timer=Timer{interval=1/dlg.data.fps,ontick=function()
      if not playing then return end
      -- Loading a legacy PNG pumps Aseprite's UI events. Keep this timer
      -- stopped until the frame is ready so it cannot enter its own callback.
      timer:stop()
      if frame>=#sequence then
        stop()
        move(frame)
      elseif move(frame+1) and playing then
        timer:start()
      end
    end}
    playing=true
    dlg:modify{id="play",text="Pause"}
    timer:start()
  end}
  dlg:button{id="forward",text="Next",onclick=function() stop(); move(frame+1) end}
  dlg:label{id="position",text="-"}
  dlg:tab{id="cutTab",text="Timing and cuts"}
  for _,doc in pairs(self.recorder.documents) do
    if doc.running and doc.session.folder == session.folder then
      dlg:button{id="pauseForEdits",text="Pause recording to edit this session",onclick=function()
        local ok=self.recorder:guard(doc,function() self.recorder:status(doc,"paused") end)
        if ok then
          timelines,nearby={},{}
          dlg:modify{id="pauseForEdits",visible=false}
          self:refresh()
          update()
        end
      end}
      break
    end
  end
  dlg:combobox{id="mode",label="History",options=session.info.version>=2 and {"Full"} or {"Full","Clean","Both"},option=head and "Clean" or "Full",visible=session.info.version==1,onchange=update}
  dlg:combobox{id="previewMode",label="Preview history",options={"Full","Clean"},visible=false,onchange=update}
  dlg:number{id="fps",label="Playback FPS",text=tostring(saved.fps or 30),onchange=update}
  dlg:number{id="hold",label="Hold final frame (seconds)",text=tostring(saved.hold or 0),decimals=2,onchange=update}
  dlg:number{id="step",label="Use every Nth recorded frame",text=tostring(animation and 1 or saved.step or 5),onchange=update}
  dlg:number{id="first",label="Recorded range from / to",text="1"}
  dlg:number{id="last",text="1"}
  local function mark(field)
    stop()
    local id = sequence[frame]
    if id then dlg:modify{id=field,text=tostring(sourcePositions[tostring(id)])} end
  end
  dlg:button{text="Mark start",onclick=function() mark("first") end}
  dlg:button{text="Mark end",onclick=function() mark("last") end}
  local function range(value)
    stop()
    self:attempt(function()
      self:assertPaused(session)
      local data = dlg.data
      local mode = data.mode=="Both" and data.previewMode or data.mode
      local all = assert(timelines[mode],"Choose a valid history.").all
      local first, last = math.tointeger(data.first),math.tointeger(data.last)
      assert(first and last and first>=1 and first<=last and last<=#all,
        "Enter recorded positions between 1 and "..#all..".")
      local ids = {}
      for i=first,last do ids[#ids+1]=all[i] end
      store.edit(session,{kind="exclude",ids=ids,value=value})
      timelines={}
      update()
    end)
  end
  dlg:button{text="Exclude range",onclick=function() range(true) end}
  dlg:button{text="Restore range",onclick=function() range(false) end}
  if not session.info.crop and session.boundaries and #session.boundaries>0 then
    local function resizeLabel()
      local count = 0
      for _,b in ipairs(session.boundaries) do if b.uncertain then count=count+1 end end
      return count>0 and string.format("Review %d uncertain resize(s)...",count) or "Adjust resize alignment..."
    end
    dlg:newrow()
    dlg:button{id="align",text=resizeLabel(),onclick=function()
      stop()
      self:attempt(function() self:alignResize(session) end)
      nearby={}
      dlg:modify{id="align",text=resizeLabel()}
      update()
    end}
  end
  dlg:tab{id="outputTab",text="Output settings"}
  dlg:combobox{id="format",label="Format",options={"MP4","GIF","PNG sequence"},option=saved.format or "MP4",onchange=update}
  dlg:number{id="scale",label="Pixel scale",text=tostring(saved.scale or 4),onchange=update}
  dlg:combobox{id="background",label="Background",options={"White","Black","Transparent"},option=saved.background or "White",onchange=update}
  dlg:entry{id="ratio",label="Aspect ratio (W:H)",text=saved.ratio or "",onchange=update}
  dlg:file{id="encoder",label="FFmpeg executable",title="Locate ffmpeg.exe",open=true,entry=true,
    filename=self.export.encoderPath(prefs.ffmpeg),filetypes={"exe"}}
  dlg:endtabs{selected="cutTab"}
  dlg:label{id="size",label="Output",text="-"}
  dlg:button{id="save",text="Export as...",onclick=function()
    stop()
    self:attempt(function()
      local options=dlg.data
      options.sequences=sequences
      if options.format~="PNG sequence" then
        local encoder=options.encoder
        local ok,problem=pcall(self.export.checkEncoder,store,encoder)
        if not ok then
          if app.alert{title="FFmpeg required",text=tostring(problem):gsub("^.-:%d+: ",""),
            buttons={"Locate ffmpeg.exe...","Back to preview"}}~=1 then return end
          encoder=self:pickFile("Locate ffmpeg.exe",self.export.isAbsolute(encoder) and encoder or fs.joinPath(fs.filePath(fs.appPath),"ffmpeg.exe"),false,{"exe"})
          if not encoder then return end
          dlg:modify{id="encoder",filename=encoder}
          self.export.checkEncoder(store,encoder)
        end
        options.ffmpeg=fs.normalizePath(encoder)
        prefs.ffmpeg=options.ffmpeg
      end
      local extension=options.format=="PNG sequence" and "png" or options.format:lower()
      local initial=prefs.lastExportFolder or session.project.folder
      local path=self:pickFile("Save timelapse",fs.joinPath(initial,"timelapse."..extension),true,{extension})
      if not path then return end
      assert(fs.fileExtension(path):lower()==extension,"Choose a ."..extension.." filename.")
      local missingCount=0
      for _ in pairs(missing) do missingCount=missingCount+1 end
      if missingCount>0 then
        local answer=app.alert{title="Missing frames",text=tostring(missingCount).." captures are missing or damaged. Skip them?",buttons={"Skip","Cancel"}}
        if answer~=1 then return end
        options.skipMissing=true
      end
      if fs.isFile(path) then
        if app.alert{title="Replace file?",text=path,buttons={"Replace","Cancel"}}~=1 then return end
        options.overwrite=true
      end
      options.head=head
      options.output=path
      options.folder=fs.filePath(path)
      if options.format=="PNG sequence" then
        local folder=fs.joinPath(fs.filePath(path),fs.fileTitle(path))
        assert(not fs.isDirectory(folder),"PNG sequence folder already exists. Choose another name.")
        options.folder=folder
        options.sequenceFolder=folder
        options.sequencePrefix=fs.fileTitle(path)
        options.output=nil
      end
      session.exporting=true
      local ok,outputs=pcall(function()
        return self:runTask("Exporting timelapse",function(control)
          options.control=control
          return self.export.run(store,session,options)
        end)
      end)
      session.exporting=nil
      if not ok then error(outputs,0) end
      if not outputs then return end
      prefs.lastExportFolder=fs.filePath(path)
      prefs.exportOptions={format=options.format,fps=options.fps,hold=options.hold,step=options.step,scale=options.scale,background=options.background,ratio=options.ratio}
      dlg:close()
      if app.alert{title="Export complete",text=outputs,buttons={"Done","Open folder"}}==2 then
        self.export.openFolder(store,fs.isDirectory(outputs[1]) and outputs[1] or fs.filePath(outputs[1]))
      end
    end)
  end}
  dlg:button{text="Cancel"}
  ready=true
  update()
  showPreview(dlg,function() seek(frame) end)
end

return Ui
