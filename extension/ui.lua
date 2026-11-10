local fs = app.fs
local Ui = {}
Ui.__index = Ui

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
  if not ok then app.alert{ title="AseLaps", text=tostring(result) } end
  return ok, result
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
      status = "Paused (storage error)"
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
  label("count", session and tostring(session.history.count) or "0")
  label("selected", selected and projectLabel(selected) or "-")
  label("notice", self.notice or (selected and selected.recovered and "Recovered to the last valid record.") or "")
  local function enable(id, value)
    value = not not value
    if self.enabled[id] ~= value then
      self.enabled[id] = value
      dlg:modify{ id=id, enabled=value }
    end
  end
  local resumable = session and session.info.version == 2 and (session.faulted or session.history.status ~= "stopped")
  enable("start", doc and not doc.running and not resumable)
  enable("pause", doc and doc.running)
  enable("resume", resumable and not doc.running)
  enable("stop", resumable)
  enable("snapshot", doc and doc.running)
  enable("history", selected)
  enable("export", selected)
  enable("current", self.selected)
end

function Ui:show()
  if self.main then return end
  local dlg = Dialog{ title="AseLaps 1.2.0", resizeable=false, onclose=function() self.main = nil end }
  self.main, self.labels, self.enabled = dlg, {}, {}
  dlg:label{ id="project", label="Document", text="-" }
  dlg:label{ id="canvas", label="Canvas", text="-" }
  dlg:label{ id="session", label="Recording session", text="-" }
  dlg:label{ id="status", label="Status", text="-" }
  dlg:label{ id="time", label="Elapsed", text="00:00:00" }
  dlg:label{ id="count", label="Captures", text="0" }
  dlg:button{ id="start", text="Start", onclick=function()
    self:record(function(doc)
      self.selected, self.notice = nil, nil
      self.recorder:start(doc, self.preferences.crop, self.preferences.initial)
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
  dlg:button{ id="stop", text="Stop", onclick=function()
    self:record(function(doc) self.recorder:status(doc, "stopped") end)
  end }
  dlg:button{ id="snapshot", text="Snapshot", onclick=function()
    self:record(function(doc) self.recorder:capture(doc, false, true) end)
  end }
  dlg:button{ text="Hide", onclick=function() dlg:close() end }
  dlg:label{ text="Recording continues when this panel is closed." }
  dlg:separator{ text="Review and export" }
  dlg:label{ id="selected", label="Selected session", text="-" }
  dlg:button{ text="Browse Sessions", onclick=function() self:attempt(function() self:sessions() end) end }
  dlg:button{ id="current", text="Use Current", onclick=function()
    self.selected = nil
    self:refresh()
  end }
  dlg:newrow()
  dlg:button{ id="history", text="History", onclick=function()
    self:attempt(function() self:history(assert(self:session())) end)
  end }
  dlg:button{ id="export", text="Export", onclick=function() self:exportDialog(assert(self:session())) end }
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
  dlg:check{ id="initial", label="New sessions", text="Initial snapshot", selected=prefs.initial ~= false }
  dlg:check{ id="auto", label="On reopen", text="Auto-resume recording", selected=prefs.autoResume ~= false }
  local intervals = {[500]="0.5 seconds", [1000]="1 second", [2000]="2 seconds"}
  dlg:combobox{ id="interval", label="New session interval", options={"0.5 seconds", "1 second", "2 seconds"},
    option=intervals[prefs.intervalMs or 500] }
  dlg:file{ id="ffmpeg", label="FFmpeg", title="Select ffmpeg.exe", open=true, entry=true,
    filename=prefs.ffmpeg or "", filetypes={"exe"} }
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
      prefs.initial, prefs.autoResume, prefs.ffmpeg, prefs.crop = data.initial, data.auto, data.ffmpeg, area
      dlg:close()
    end)
  end }
  dlg:button{ text="Cancel" }
  dlg:show()
end

function Ui:sessions()
  local store = self.recorder.store
  local names, descriptors = {}, {}
  for _, project in ipairs(store:projects()) do
    for _, session in ipairs(store:sessions(project)) do
      local label = projectLabel(session) .. " [" .. fs.fileName(project.folder) .. "]"
      table.insert(names, 1, label)
      descriptors[label] = session
    end
  end
  assert(#names > 0, "No AseLaps sessions have been recorded.")
  local dlg = Dialog{ title="AseLaps Sessions" }
  dlg:combobox{ id="session", label="Session", options=names }
  dlg:button{ text="Select", onclick=function()
    self:attempt(function()
      local descriptor = assert(descriptors[dlg.data.session], "Select a session.")
      for _, doc in pairs(self.recorder.documents) do
        if doc.session and doc.session.folder == descriptor.folder then
          self.selected = doc.session
          dlg:close()
          self:refresh()
          return
        end
      end
      self.selected = store:load(descriptor)
      dlg:close()
      self:refresh()
    end)
  end }
  dlg:button{ text="Cancel" }
  dlg:show()
end

function Ui:history(session)
  local store = self.recorder.store
  local history = session.history
  local rows = {}
  for _, event in ipairs(history.events) do
    if event.kind == "state" or event.kind == "visit" then rows[#rows + 1] = event end
  end
  for _, id in ipairs(session.orphans) do
    rows[#rows + 1] = {png=id, label="Recovered snapshot"}
  end

  assert(#rows > 0, "This session has no history to show.")

  local index, preview = #rows, nil
  local dlg = Dialog{ title="AseLaps History" }
  local function update(nextIndex)
    index = math.max(1, math.min(nextIndex, #rows))
    local item = rows[index]
    local node = history.nodes[item.id]
    local detail = item.label
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
      filename=string.format("AseLaps_%06d.png", id), filetypes={"png"} }
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
  dlg:button{ text="Close" }
  update(index)
  dlg:show{ autoscrollbars=true }
end

function Ui:exportDialog(session, head)
  local dlg = Dialog{ title="AseLaps Export" }
  local function update()
    local ok, result = pcall(self.export.layout, session.info, dlg.data)
    local label = ok and string.format("%d x %d px", result.outWidth, result.outHeight) or "-"
    dlg:modify{ id="size", text=label }
  end
  dlg:label{ label="Session", text=projectLabel(session) }
  if head then dlg:label{ label="Clean head", text="#" .. head } end
  dlg:combobox{ id="mode", label="History", options=session.info.version == 2 and {"Full"} or {"Full", "Clean", "Both"}, option=head and "Clean" or "Full" }
  dlg:combobox{ id="format", label="Format", options={"MP4", "GIF", "PNG sequence"}, onchange=update }
  dlg:number{ id="fps", label="FPS", text="24" }
  dlg:number{ id="step", label="Frame interval", text=tostring(session.info.version == 2 and 1 or self.export.defaultStep) }
  dlg:label{ text="1 keeps every frame. First and last are always included." }
  dlg:number{ id="scale", label="Pixel scale", text="4", onchange=update }
  dlg:number{ id="hold", label="Final hold (sec)", text="2", decimals=2 }
  dlg:combobox{ id="background", label="Background", options={"White", "Black", "Transparent"} }
  dlg:entry{ id="ratio", label="Aspect ratio (W:H)", text="", onchange=update }
  dlg:label{ id="size", label="Output size", text="" }
  dlg:entry{ id="folder", label="Output folder", text=fs.joinPath(session.project.folder, "exports") }
  dlg:button{ text="Browse...", onclick=function()
    self:attempt(function()
      local folder = self.export.chooseFolder(self.recorder.store, dlg.data.folder, session.project.folder)
      if folder then dlg:modify{ id="folder", text=folder } end
    end)
  end }
  dlg:newrow()
  dlg:button{ text="Export", onclick=function()
    self:attempt(function()
      local options = dlg.data
      options.ffmpeg, options.head = self.preferences.ffmpeg, head
      local outputs = self.export.run(self.recorder.store, session, options)
      dlg:close()
      app.alert{ title="AseLaps Export", text=outputs }
    end)
  end }
  dlg:button{ text="Cancel" }
  update()
  dlg:show{ autoscrollbars=true }
end

return Ui
