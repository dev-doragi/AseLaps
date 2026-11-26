local fs = app.fs
local Widgets=dofile(fs.joinPath(fs.filePath(debug.getinfo(1,"S").source:sub(2)),"widgets.lua"))
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

function Ui:runTask(title,work,onComplete)
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
      if onComplete then
        self.task=nil
        onComplete(result,not control.cancelled and problem)
      end
    else
      if value then dlg:modify{id="progress",text=string.format("%s: %d / %d",value.phase,value.done or 0,value.total or 0)} end
      timer:start()
    end
  end}
  self.task={control=control,timer=timer}
  if onComplete then
    local ok,problem=pcall(function() dlg:show{wait=false,autoscrollbars=true} end)
    if not ok then self.task=nil; error(problem,0) end
    timer:start()
    return
  end
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
  local dlg=self.main
  if not dlg then return end
  local sprite,doc=app.sprite,self:document()
  local session=doc and doc.session
  local selected=session or (not doc and self.selected)
  local running=doc and doc.running
  local resumable=session and session.info.version>=2 and (session.faulted or session.history.status~="stopped")
  local autoResume=resumable and not session.faulted and session.history.status=="recording" and self.preferences.autoResume~=false
  local function modify(id,key,value)
    local cache=id..key
    if self.labels[cache]~=value then
      self.labels[cache]=value
      dlg:modify{id=id,[key]=value}
    end
  end
  modify("project","text",sprite and fs.fileName(sprite.filename) or "Open an artwork")
  modify("status","text",(running and "REC" or session and session.faulted and "Storage error" or autoResume and "Resumes on edit" or resumable and "Paused" or "Ready").."  |  "..duration(self.recorder.elapsed(doc)))
  modify("count","text",string.format("%d captures",session and session.history.count or 0))
  modify("record","text",running and "Pause" or resumable and "Resume" or "Record")
  local icon=running and "record" or resumable and "pause" or "stop"
  if self.recorderIcon~=icon then
    self.recorderIcon=icon
    dlg:repaint()
  end
  modify("count","visible",not self.preferences.compact)
  modify("snapshot","visible",not self.preferences.compact)
  modify("project","visible",not self.preferences.compact)
  modify("record","enabled",not not doc)
  modify("stop","enabled",not not resumable)
  modify("snapshot","enabled",not not running)
  modify("studio","enabled",not not selected)
  modify("notice","text",self.notice or (session and not sprite.hasAssociatedFile and "Save the artwork to resume this recording later." or ""))
end

function Ui:show()
  if self.main then return end
  local prefs=self.preferences
  local dlg
  dlg=Dialog{title="AseLaps",resizeable=true,onclose=function()
    if dlg then
      local ok,b=pcall(function() return dlg.bounds end)
      if ok and b then prefs.recorderBounds={x=b.x,y=b.y,w=b.width,h=b.height} end
    end
    self.main=nil
  end}
  self.main,self.labels=dlg,{}
  self.selected=nil
  dlg:label{id="project",text="Artwork"}
  dlg:newrow()
  dlg:canvas{width=10,height=10,hexpand=false,vexpand=false,onpaint=function(ev)
    Widgets.icon(ev.context,self.recorderIcon or "stop")
  end}
  dlg:label{id="status",text="Ready  |  00:00:00"}
  dlg:label{id="count",text="0 captures"}
  dlg:newrow()
  dlg:button{id="record",text="Record",onclick=function()
    self:record(function(doc)
      self.selected,self.notice=nil,nil
      if doc.running then self.recorder:status(doc,"paused")
      elseif doc.session and doc.session.info.version>=2 and (doc.session.faulted or doc.session.history.status~="stopped") then self.recorder:resume(doc)
      else self.recorder:start(doc,prefs.crop,prefs.initial) end
    end)
  end}
  dlg:button{id="stop",text="Stop",tooltip="Finish this recording. Use Pause to continue later.",onclick=function()
    self:record(function(doc) self.recorder:status(doc,"stopped") end)
  end}
  dlg:button{id="snapshot",text="Capture",tooltip="Save the current artwork immediately",onclick=function()
    self:record(function(doc) self.recorder:capture(doc,false,true) end)
  end}
  dlg:newrow()
  dlg:button{id="studio",text="Studio",tooltip="Preview, trim and export your timelapse",onclick=function()
    self:attempt(function() self:exportDialog(assert((self:document() and self:document().session) or self.selected)) end)
  end}
  dlg:button{text="Library",onclick=function() self:attempt(function() self:sessions() end) end}
  dlg:button{text="Settings",onclick=function() self:settings() end}
  dlg:button{id="compact",text=prefs.compact and "Expand" or "Compact",onclick=function()
    prefs.compact=not prefs.compact
    dlg:modify{id="compact",text=prefs.compact and "Expand" or "Compact"}
    self:refresh()
    dlg.bounds=Rectangle(dlg.bounds.x,dlg.bounds.y,dlg.sizeHint.width,dlg.sizeHint.height)
  end}
  dlg:newrow()
  dlg:label{id="notice",text=""}
  self:refresh()
  local b=prefs.recorderBounds
  local args={wait=false,autoscrollbars=true}
  if b and b.w and b.h and b.w>0 and b.h>0 then args.bounds=Rectangle(b.x,b.y,b.w,b.h) end
  dlg:show(args)
end

function Ui:settings()
  local prefs = self.preferences
  local crop = prefs.crop or {}
  local sprite = app.sprite
  local dlg = Dialog{ title="AseLaps Settings", resizeable=true }
  dlg:entry{id="recordingFolder",label="Recording folder",text=self.recorder.store:recordingFolder()}
  dlg:label{text="Choose a local folder outside OneDrive. Existing sessions stay in place."}
  dlg:check{ id="initial", label="New sessions", text="Initial snapshot", selected=prefs.initial ~= false }
  dlg:check{ id="auto", label="On reopen", text="Resume recording", selected=prefs.autoResume ~= false }
  dlg:check{id="autoRecord",label="New artwork",text="Record automatically",selected=prefs.autoRecord~=false}
  dlg:combobox{id="captureMode",label="Recording mode",options={"Balanced","Every edit","Low impact","Smart Sampling"},option=prefs.captureMode or "Balanced"}
  local intervals = {[500]="0.5 seconds", [1000]="1 second", [2000]="2 seconds"}
  dlg:combobox{ id="interval", label="Capture while drawing", options={"0.5 seconds", "1 second", "2 seconds"},
    option=intervals[prefs.intervalMs or 500] }
  dlg:file{ id="ffmpeg", label="FFmpeg", title="Select ffmpeg.exe", open=true, entry=true,
    filename=self.export.encoderPath(prefs.ffmpeg), filetypes={"exe"} }
  dlg:button{text="Check FFmpeg",onclick=function() self:attempt(function()
    self.export.checkEncoder(self.recorder.store,dlg.data.ffmpeg,true)
    app.alert("FFmpeg is ready.")
  end) end}
  dlg:label{text="Package ffmpeg.exe is used first; external path is optional."}
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
      prefs.autoRecord,prefs.captureMode=data.autoRecord,data.captureMode
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
  dlg:separator{text="Advanced tools"}
  dlg:button{text="Apply edited animation",onclick=function() self:attempt(function() self:applyEdit() end) end}
  dlg:button{text="Export edited animation",onclick=function() self:attempt(function() self:exportAnimation() end) end}
  dlg:button{text="Recording folder",onclick=function() self:attempt(function() local store=self.recorder.store; store.ensureDirectory(store:recordingFolder()); self.export.openFolder(store,store:recordingFolder()) end) end}
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
  local store=self.recorder.store
  local paths,labels,seen={}, {}, {}
  local function add(path,title)
    local key=store.pathKey(path)
    if seen[key] or not fs.isFile(path) then return end
    seen[key]=true
    labels[#labels+1]=title.." / "..fs.fileName(fs.filePath(path)).." ["..tostring(#labels+1).."]"
    paths[labels[#labels]]=path
  end
  for source,path in pairs(self.preferences.sessionsBySource or {}) do add(path,fs.fileTitle(source)) end
  local root=store:recordingFolder()
  if fs.isDirectory(root) then
    for _,entry in ipairs(fs.listFiles(root)) do
      local folder=fs.joinPath(root,fs.fileName(entry))
      if fs.isDirectory(folder) then
        for _,sub in ipairs(fs.listFiles(folder)) do
          add(fs.joinPath(folder,fs.fileName(sub),"session.json"),fs.fileName(folder):gsub("__record$",""))
        end
      end
    end
  end
  table.sort(labels,function(a,b) return a:lower()<b:lower() end)
  local dlg=Dialog{title="Recording Library",resizeable=true}
  local function loadedSession(path)
    for _,doc in pairs(self.recorder.documents) do
      if doc.session and store.pathKey(doc.session.folder)==store.pathKey(fs.filePath(path)) then return doc.session end
    end
  end
  local function open(path)
    if not path then return end
    local session=loadedSession(path) or store:open(path)
    self.selected=session
    self.preferences.lastSessionFolder=fs.filePath(path)
    dlg:close(); self:refresh(); self:exportDialog(session)
  end
  if #labels>0 then
    local thumbnail
    local function refreshThumbnail()
      thumbnail=nil
      local path=paths[dlg.data.art]
      local ok,image=pcall(function()
        local session=loadedSession(path)
        if not session then
          local info=json.decode(store.readText(path))
          if info.version~=4 then
            local first=store.snapshotPath({info=info,folder=fs.filePath(path)},1)
            if not fs.isFile(first) then return end
            return store.loadSnapshot({info=info,folder=fs.filePath(path)},1)
          end
          session=store:open(path)
        end
        local frames=store.timeline(session,"Full")
        if #frames>0 then return store.loadSnapshot(session,frames[#frames]) end
      end)
      if ok then thumbnail=image end
      dlg:modify{id="thumbnailStatus",text=thumbnail and "" or "No preview available"}
      dlg:repaint()
    end
    dlg:combobox{id="art",label="Artwork",options=labels,option=labels[1],onchange=refreshThumbnail}
    dlg:canvas{width=200,height=108,hexpand=true,vexpand=false,onpaint=function(ev)
      Widgets.thumbnail(ev.context,thumbnail)
    end}
    dlg:label{id="thumbnailStatus"}
    refreshThumbnail()
    dlg:button{text="Open Studio",onclick=function() self:attempt(function() open(paths[dlg.data.art]) end) end}
    dlg:button{text="Resume",onclick=function() self:attempt(function()
      local path=paths[dlg.data.art]
      local session=store:open(path)
      local doc=assert(self:document(),"Open the original artwork first.")
      assert(not doc.running,"Pause the current recording first.")
      assert(store.pathKey(store.source(doc.sprite))==store.pathKey(session.project.source),"Open the matching artwork first.")
      self.recorder:canResume(doc,session)
      local old,project=doc.session,doc.project
      doc.session,doc.project=session,session.project
      if not self.recorder:guard(doc,function() self.recorder:resume(doc) end) then doc.session,doc.project=old,project end
      self.selected=nil; dlg:close(); self:refresh()
    end) end}
  else dlg:label{text="No recordings yet."} end
  dlg:newrow()
  dlg:button{text="Import recording...",onclick=function() self:attempt(function()
    open(self:pickFile("Open AseLaps recording",fs.joinPath(self.preferences.lastSessionFolder or root,"session.json"),false,{"json"}))
  end) end}
  dlg:button{text="Close"}
  dlg:show{autoscrollbars=true}
end

function Ui:recordingDocument(session)
  local key=self.recorder.store.pathKey(session.folder)
  for _, doc in pairs(self.recorder.documents) do
    if doc.running and self.recorder.store.pathKey(doc.session.folder)==key then return doc end
  end
end

function Ui:assertPaused(session)
  assert(not session.exporting,"Wait for the current export to finish.")
  assert(not self:recordingDocument(session),"Pause this recording before editing or exporting.")
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
  ctx:drawImage(image, geometry.camera or image.bounds, Rectangle(x+math.floor(geometry.x*scale), y+math.floor(geometry.y*scale),
    math.max(1,math.floor(geometry.width*scale)), math.max(1,math.floor(geometry.height*scale))))
end

local function showPreview(dlg, afterShow, modeless)
  -- A canvas has no drawable surface until the modal dialog is visible.
  local firstPaint
  firstPaint = Timer{interval=0.02,ontick=function()
    firstPaint:stop()
    if afterShow then afterShow() end
    dlg:repaint()
  end}
  firstPaint:start()
  dlg:show{autoscrollbars=true,wait=not modeless}
  if not modeless then firstPaint:stop() end
  return firstPaint
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
  local recording=self:recordingDocument(session)
  if recording then session=recording.session end
  if self.studio then self.studio:close() end
  self:refresh()
  local saved=prefs.exportOptions or {}
  local timer, firstPaint, closed
  local dlg
  dlg = Dialog{title="AseLaps Studio",resizeable=true,onclose=function()
    closed=true
    if timer then timer:stop() end
    if firstPaint then firstPaint:stop() end
    if self.studio==dlg then self.studio=nil end
  end}
  if recording then self.studio=dlg end
  local sequences, missing, timelines = {}, {}, {}
  local sequence, frame, image, geometry, sourcePositions = {}, 1, nil, nil, {}
  local rangeMax=0
  local ready, changing, playing = false, false, false
  local nearby, background, valid = {}, nil, false
  local camera, cameraFrame, cameraChecked
  local previewRevision, captureCount=session.editRevision,session.history.count
  local boundaryCount=#session.boundaries
  local canAlign=not session.info.crop and boundaryCount>0
  local function stop()
    if timer then timer:stop() end
    playing = false
    dlg:modify{id="play",text="Play"}
  end
  local function seek(position)
    frame = math.max(1,math.min(position,#sequence))
    local id = sequence[frame]
    local nextCache = {}
    local radius = (playing or session.info.captureWidth*session.info.captureHeight>1024*1024) and 0 or 1
    for i=math.max(1,frame-radius), math.min(#sequence,frame+radius) do
      local neighbor = sequence[i]
      nextCache[neighbor] = nearby[neighbor] or store.loadSnapshot(session,neighbor)
    end
    nearby = nextCache
    image = nearby[id]
    changing = true
    dlg:modify{id="scrub",min=1,max=math.max(2,#sequence),value=frame,enabled=#sequence>1}
    changing = false
    local detail = id and string.format("%d / %d",frame,#sequence) or "No frames"
    dlg:modify{id="position",text=detail}
    dlg:modify{id="back",enabled=frame>1}
    dlg:modify{id="forward",enabled=frame<#sequence}
    dlg:repaint()
  end
  local function move(position)
    if closed then return false end
    if recording and (boundaryCount~=#session.boundaries or previewRevision~=session.editRevision) then
      stop()
      dlg:modify{id="recordingStatus",text="Recording changed. Refresh preview to continue."}
      return false
    end
    local ok, message = pcall(seek, position)
    if not ok then
      stop()
      app.alert{title="AseLaps",text=tostring(message)}
    end
    return ok
  end
  local function update()
    if not ready or closed then return end
    stop()
    valid = false
    if previewRevision~=session.editRevision or captureCount~=session.history.count then
      previewRevision,captureCount=session.editRevision,session.history.count
      boundaryCount=#session.boundaries
      nearby,timelines={},{}
      camera,cameraFrame,cameraChecked=nil,nil,false
    end
    local data = dlg.data
    local ok, result = pcall(function()
      local step, fps = math.tointeger(data.step), math.tointeger(data.fps)
      local hold=tonumber(data.hold)
      assert(hold and hold>=0 and hold<=60,"Final hold must be between 0 and 60 seconds.")
      assert(step and step>=1 and step<=1000,"Use every 1 to 1000 recorded frames.")
      assert(fps and fps>=1 and fps<=60,"Choose 1 to 60 FPS.")
      assert(data.format ~= "MP4" or data.background ~= "Transparent","Choose a white or black background for MP4.")
      background = data.background
      local modes = data.mode == "Both" and {"Full","Clean"} or {data.mode}
      local summaries = {}
      sequences, missing = {}, {}
      for _,mode in ipairs(modes) do
        local timeline = timelines[mode]
        if not timeline then
          local frames, absent = store.timeline(session,mode,head)
          local all = store.timeline(session,mode,head,true)
          timeline = {frames=frames,missing=absent,all=all}
          timelines[mode] = timeline
        end
        local seconds=tonumber((data.duration or ""):match("^%d+"))
        assert(not seconds or hold<seconds,"Final hold must be shorter than the video length.")
        sequences[mode]=seconds and self.export.sampleCount(timeline.frames,math.max(2,math.floor((seconds-hold)*fps+0.5))) or self.export.sample(timeline.frames,step)
        for _,id in ipairs(timeline.missing) do missing[tostring(id)]=true end
        local count = #sequences[mode]
        local outputCount=count+math.floor(hold*fps+0.5)
        summaries[#summaries+1] = string.format("%s%d frames / %.2f sec",data.mode=="Both" and mode.." " or "",outputCount,outputCount/fps)
      end
      local mode = data.mode == "Both" and data.previewMode or data.mode
      local nextSequence=sequences[mode]
      local finalFrame=nextSequence[#nextSequence]
      if data.camera and finalFrame then
        if not cameraChecked or cameraFrame~=finalFrame then
          camera=self.export.artworkBounds(store.loadSnapshot(session,finalFrame))
          cameraFrame,cameraChecked=finalFrame,true
        end
        data.cameraBounds=camera
      end
      geometry = self.export.layout(session.info,data)
      local all=timelines[mode].all
      sequence,sourcePositions = nextSequence,{}
      local output=1
      for i,id in ipairs(all) do
        if id==sequence[output] then
          sourcePositions[output]=i
          output=output+1
        end
      end
      local maximum=#all
      if maximum~=rangeMax then
        local first=math.min(data.first or 1,math.max(1,maximum))
        local last=math.max(1,maximum)
        if rangeMax>0 and data.last and data.last~=rangeMax then
          last=math.min(last,data.last)
        end
        rangeMax=maximum
        dlg:modify{id="first",min=1,max=math.max(2,maximum),value=first,enabled=maximum>1}
        dlg:modify{id="last",min=1,max=math.max(2,maximum),value=last,enabled=maximum>1}
      end
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
    dlg:modify{id="step",visible=data.duration=="Custom"}
    dlg:modify{id="scale",visible=data.preset=="Original / Custom"}
    dlg:modify{id="ratio",visible=data.preset=="Original / Custom"}

    dlg:modify{id="play",enabled=ok and #sequence>1}
    local running=self:recordingDocument(session)~=nil
    if recording then
      dlg:modify{id="pauseForEdits",enabled=running}
      dlg:modify{id="recordingStatus",text=running and "Recording continues. Refresh preview to see new captures." or "Recording is not active."}
      for _,id in ipairs({"exclude","restore","undoCut","historyTools"}) do
        dlg:modify{id=id,enabled=not running}
      end
      if canAlign then dlg:modify{id="align",enabled=not running} end
    end
    dlg:modify{id="save",enabled=ok and not session.exporting and (not running or session.info.version==4)}
    dlg:modify{id="size",text=ok and result or tostring(result):gsub("^.-:%d+: ","")}
  end
  local active = self:document()
  local scope = "Artwork"
  dlg:label{label=animation and "Source" or scope,text=animation and "Edited animation" or session.project.title}
  if active and active.session and active.session.folder ~= session.folder and not animation then
    dlg:label{label="Current artwork session",text=projectLabel(active.session)}
  end
  dlg:canvas{id="film",width=360,height=240,hexpand=true,vexpand=true,onpaint=function(ev)
    local ctx = ev.context
    local side = math.min(44, math.floor(ctx.width/5))
    drawPreview(ctx,image,geometry,background,ctx.width-2*side,ctx.height,side,0)
    if not playing then
      drawPreview(ctx,nearby[sequence[frame-1]],geometry,background,side-4,40,0,(ctx.height-40)//2)
      drawPreview(ctx,nearby[sequence[frame+1]],geometry,background,side-4,40,ctx.width-side,(ctx.height-40)//2)
    end
  end}
  dlg:slider{id="scrub",label="Output frame",min=1,max=2,value=1,onchange=function()
    if ready and not changing then stop(); move(dlg.data.scrub) end
  end}
  dlg:newrow()
  Widgets.timeline(dlg,function()
    local data=dlg.data
    local position=sourcePositions[frame] or 1
    return #sequence,position,rangeMax,data.first or 1,data.last or 1
  end,function(position)
    if not ready or #sequence==0 then return end
    local lo,hi=1,#sequence
    while lo<hi do
      local mid=(lo+hi)//2
      if sourcePositions[mid]<position then lo=mid+1 else hi=mid end
    end
    if lo>1 then
      local before=sourcePositions[lo-1]
      local after=sourcePositions[lo]
      if position-before<after-position then lo=lo-1 end
    end
    if lo~=frame then stop(); move(lo) end
  end,function(first,last)
    stop()
    dlg:modify{id="first",value=first}
    dlg:modify{id="last",value=last}
    dlg:repaint()
  end)
  dlg:label{text="Drag to seek. Shift-drag to mark a range."}
  dlg:newrow()
  dlg:canvas{width=10,height=10,hexpand=false,vexpand=false,onpaint=function(ev)
    Widgets.icon(ev.context,playing and "pause" or "play")
  end}
  dlg:button{id="back",text="Previous",onclick=function() stop(); move(frame-1) end}
  dlg:button{id="play",text="Play",onclick=function()
    if playing then stop(); move(frame); return end
    if not valid or #sequence<2 then return end
    if frame==#sequence and not move(1) then return end
    local stride=math.max(1,math.ceil(dlg.data.fps/12))
    timer=Timer{interval=stride/dlg.data.fps,ontick=function()
      if not playing then return end
      -- Loading a legacy PNG pumps Aseprite's UI events. Keep this timer
      -- stopped until the frame is ready so it cannot enter its own callback.
      timer:stop()
      if frame>=#sequence then
        stop()
        move(frame)
      elseif move(math.min(#sequence,frame+stride)) and playing then
        timer:start()
      end
    end}
    playing=true
    dlg:modify{id="play",text="Pause"}
    dlg:repaint()
    timer:start()
  end}
  dlg:button{id="forward",text="Next",onclick=function() stop(); move(frame+1) end}
  dlg:label{id="position",text="-"}
  dlg:tab{id="cutTab",text="Timing"}
  if recording then
    dlg:label{id="recordingStatus"}
    dlg:button{text="Refresh preview",onclick=update}
    dlg:button{id="pauseForEdits",text="Pause to edit",onclick=function()
      local doc=self:recordingDocument(session)
      if doc then
        local ok=self.recorder:guard(doc,function() self.recorder:status(doc,"paused") end)
        if ok then
          self:refresh()
        end
      end
      update()
    end}
  end
  dlg:combobox{id="mode",label="History",options=session.info.version>=2 and {"Full"} or {"Full","Clean","Both"},option=head and "Clean" or "Full",visible=session.info.version==1,onchange=update}
  dlg:combobox{id="previewMode",label="Preview history",options={"Full","Clean"},visible=false,onchange=update}
  dlg:number{id="fps",label="Playback FPS",text=tostring(saved.fps or 30),onchange=update}
  dlg:number{id="hold",label="Hold final frame (seconds)",text=tostring(saved.hold or 0),decimals=2,onchange=update}
  dlg:combobox{id="duration",label="Video length",options={"15 seconds","30 seconds","60 seconds","Custom"},option=animation and "Custom" or saved.duration or "30 seconds",onchange=update}
  dlg:number{id="step",label="Frame interval (custom)",text=tostring(animation and 1 or saved.step or 5),onchange=update}
  dlg:slider{id="first",label="Range start",min=1,max=2,value=1,onchange=function() dlg:repaint() end}
  dlg:slider{id="last",label="Range end",min=1,max=2,value=1,onchange=function() dlg:repaint() end}
  local function mark(field)
    stop()
    local id = sequence[frame]
    if id then
      dlg:modify{id=field,value=sourcePositions[frame]}
      dlg:repaint()
    end
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
  dlg:button{id="exclude",text="Exclude range",onclick=function() range(true) end}
  dlg:button{id="restore",text="Restore range",onclick=function() range(false) end}
  if canAlign then
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
  dlg:button{id="undoCut",text="Undo cut",onclick=function() self:attempt(function() self:assertPaused(session); store.edit(session,{kind="undo"}); update() end) end}
  dlg:button{id="historyTools",text="History tools...",onclick=function() stop(); self:attempt(function() self:history(session); timelines={}; update() end) end}
  dlg:tab{id="outputTab",text="Output"}
  dlg:combobox{id="format",label="Format",options={"MP4","GIF","PNG sequence"},option=saved.format or "MP4",onchange=update}
  dlg:combobox{id="preset",label="Canvas",options={"Original / Custom","YouTube 1080p","Vertical 1080p","Square 1080p","Portrait 1080p"},option=saved.preset or "Original / Custom",onchange=update}
  dlg:check{id="camera",text="Smart camera (frame final artwork)",selected=saved.camera==true,onclick=update}
  dlg:number{id="scale",label="Pixel scale",text=tostring(saved.scale or 4),onchange=update}
  dlg:combobox{id="background",label="Background",options={"White","Black","Transparent"},option=saved.background or "White",onchange=update}
  dlg:entry{id="ratio",label="Aspect ratio (W:H)",text=saved.ratio or "",onchange=update}

  dlg:endtabs{selected="cutTab"}
  dlg:label{id="size",label="Output",text="-"}
  dlg:button{id="save",text="Export...",onclick=function()
    stop()
    self:attempt(function()
      assert(not self.task and not session.exporting,"Wait for the current export to finish.")
      if session.info.version~=4 then self:assertPaused(session) end
      update()
      assert(valid,"Choose valid export settings.")
      local options=dlg.data
      options.sequences=sequences
      if options.camera then options.cameraBounds=camera end
      local snapshot=store.exportSnapshot(session)
      if options.format~="PNG sequence" then
        local encoder=self.export.encoderPath(prefs.ffmpeg)
        local ok,problem=pcall(self.export.checkEncoder,store,encoder)
        if not ok then
          if app.alert{title="FFmpeg required",text=tostring(problem):gsub("^.-:%d+: ",""),
            buttons={"Locate ffmpeg.exe...","Back to preview"}}~=1 then return end
          encoder=self:pickFile("Locate ffmpeg.exe",self.export.isAbsolute(encoder) and encoder or fs.joinPath(fs.filePath(fs.appPath),"ffmpeg.exe"),false,{"exe"})
          if not encoder then return end
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
      assert(not self.task and not session.exporting,"Wait for the current export to finish.")
      local live=self:recordingDocument(session)~=nil
      if live then assert(session.info.version==4,"Pause this recording before exporting.") end
      local function work(control)
        options.control=control
        return self.export.run(store,snapshot,options)
      end
      local function complete(outputs,problem)
        session.exporting=nil
        if closed then
          if problem then self:showError(problem) end
          return
        end
        self:attempt(function()
          if problem then update(); error(problem,0) end
          if not outputs then update(); return end
          prefs.lastExportFolder=fs.filePath(path)
          prefs.exportOptions={preset=options.preset,duration=options.duration,format=options.format,fps=options.fps,hold=options.hold,step=options.step,scale=options.scale,background=options.background,ratio=options.ratio,camera=options.camera}
          dlg:close()
          if app.alert{title="Export complete",text=outputs,buttons={"Done","Open folder"}}==2 then
            self.export.openFolder(store,fs.isDirectory(outputs[1]) and outputs[1] or fs.filePath(outputs[1]))
          end
        end)
      end
      session.exporting=true
      if live then
        dlg:modify{id="save",enabled=false}
        local ok,problem=pcall(self.runTask,self,"Exporting timelapse",work,complete)
        if not ok then complete(nil,problem) end
      else
        local ok,result=pcall(self.runTask,self,"Exporting timelapse",work)
        if ok then complete(result) else complete(nil,result) end
      end
    end)
  end}
  dlg:button{text="Cancel"}
  ready=true
  update()
  firstPaint=showPreview(dlg,function() move(frame) end,recording~=nil)
end

return Ui
