local fs = app.fs
local join = fs.joinPath
local Codec = dofile(join(fs.filePath(debug.getinfo(1,"S").source:sub(2)), "codec.lua"))
local Store = {}
Store.__index = Store

local function write(path, bytes, mode)
  Store.assertLocalPath(path)
  local file = assert(io.open(path, mode))
  local written, writeError = file:write(bytes)
  local closed, closeError = file:close()
  assert(written, writeError)
  assert(closed, closeError)
end

local function plainObject(object)
  local result = {}
  for key, value in pairs(object) do
    if type(value) == "userdata" then value = plainObject(value) end
    if type(value) == "number" then value = math.tointeger(value) or value end
    result[key] = value
  end
  for index, value in ipairs(object) do
    if type(value) == "userdata" or type(value) == "table" then value = plainObject(value) end
    if type(value) == "number" then value = math.tointeger(value) or value end
    result[index] = value
  end
  return result
end

local function decode(bytes)
  return plainObject(json.decode(bytes))
end

local function read(path)
  local file = assert(io.open(path, "rb"))
  local bytes, readError = file:read("a")
  assert(file:close())
  return assert(bytes, readError)
end

local function readJson(path)
  return decode(read(path))
end

local function writeNewJson(path, data)
  local pending = path .. ".tmp"
  assert(not fs.isFile(path), "AseLaps metadata already exists: " .. path)
  write(pending, json.encode(data), "wb")
  assert(os.rename(pending, path))
end

local function ensureDirectory(path)
  Store.assertLocalPath(path)
  assert(fs.isDirectory(path) or fs.makeAllDirectories(path), "Cannot create folder: " .. path)
end

local function entries(path)
  local names = {}
  if fs.isDirectory(path) then
    for _, entry in ipairs(fs.listFiles(path)) do names[#names + 1] = fs.fileName(entry) end
  end
  table.sort(names)
  return names
end

local function numberedDirectory(root, prefix)
  ensureDirectory(root)
  local suffix = 0
  while true do
    local path = join(root, string.format("%s_%03d", prefix, suffix))
    if not fs.isDirectory(path) and not fs.isFile(path) then
      assert(fs.makeDirectory(path), "Cannot create folder: " .. path)
      return path
    end
    suffix = suffix + 1
  end
end

function Store.recordingRoot()
  return join(assert(os.getenv("USERPROFILE")), "Downloads", "AseLaps")
end

function Store.pathKey(path)
  return path and fs.normalizePath(path):gsub("\\", "/"):lower():gsub("/+$", "")
end

function Store.assertLocalPath(path)
  local normalized = fs.normalizePath(path):gsub("\\", "/"):lower():gsub("/+$", "")
  local roots = {join(assert(os.getenv("USERPROFILE")), "OneDrive")}
  for _, name in ipairs({"OneDrive", "OneDriveConsumer", "OneDriveCommercial"}) do
    local value = os.getenv(name)
    if value and value ~= "" then roots[#roots+1] = value end
  end
  for _, root in ipairs(roots) do
    root = fs.normalizePath(root):gsub("\\", "/"):lower():gsub("/+$", "")
    assert(normalized ~= root and normalized:sub(1,#root+1) ~= root .. "/",
      "OneDrive storage is disabled. Choose a folder outside OneDrive.")
  end
end

function Store.new(root, history, preferences)
  return setmetatable({ root=root, history=history, preferences=preferences or {} }, Store)
end

function Store:recordingFolder()
  return self.preferences.recordingFolder or Store.recordingRoot()
end

function Store.source(sprite)
  if sprite.hasAssociatedFile then return fs.normalizePath(sprite.filename):lower() end
end

function Store:projects()
  local result = {}
  for _, name in ipairs(entries(self.root)) do
    local folder = join(self.root, name)
    local path = join(folder, "project.json")
    if fs.isFile(path) then
      local info = readJson(path)
      local binding = join(folder, "source.json")
      if fs.isFile(binding) then info.source = readJson(binding).source end
      info.folder = folder
      result[#result + 1] = info
    end
  end
  return result
end

function Store:project(sprite, create)
  local source = Store.source(sprite)
  local title = source and fs.fileTitle(sprite.filename) or "Untitled"
  local folder = join(self:recordingFolder(), source and (title .. "__record") or "_Unsaved")
  local project = {folder=folder, title=title, source=source, standalone=true}
  if not source then return create and project or nil end
  if fs.isDirectory(folder) or create then return project end
  for _, legacy in ipairs(self:projects()) do
    if legacy.source == source then return legacy end
  end
end

function Store:bind(session, source)
  assert(not session.project.source and source, "Session already has a source document.")
  writeNewJson(join(session.folder, "source.json"), { source=source })
  session.info.source, session.project.source = source, source
end

function Store:sessions(project)
  local result = {}
  for _, name in ipairs(entries(project.standalone and project.folder or join(project.folder, "sessions"))) do
    local path = join(project.standalone and project.folder or join(project.folder, "sessions"), name, "session.json")
    if fs.isFile(path) then
      local info = readJson(path)
      local binding = join(fs.filePath(path), "source.json")
      if fs.isFile(binding) then info.source = readJson(binding).source end
      result[#result + 1] = {
        folder=fs.filePath(path), project=project, name=name, info=info
      }
    end
  end
  return result
end

function Store:create(project, info)
  local folder = info.folder
  if folder then
    assert(not fs.isDirectory(folder) and not fs.isFile(folder), "Choose a new session name.")
    ensureDirectory(folder)
  else
    folder = numberedDirectory(project.standalone and project.folder or join(project.folder, "sessions"), os.date("%Y%m%d_%H%M%S"))
  end
  info.folder = nil
  info.title, info.source = project.title, project.source
  ensureDirectory(join(folder, "snapshots"))
  info.version = info.version or 1
  writeNewJson(join(folder, "session.json"), info)
  return self:load{ folder=folder, project=project, name=fs.fileName(folder), info=info }
end

function Store.png(session, id)
  return join(session.folder, "snapshots", string.format("%06d.png", id))
end

function Store.loadImage(path)
  return assert(Image{ fromFile=path }, "Cannot load PNG: " .. path)
end

local function packPath(session, generation)
  if not generation or generation==0 then return join(session.folder,"frames.pack") end
  return join(session.folder,string.format("frames.%06d.pack",generation))
end

function Store.loadNative(session,id)
  if session.info.version~=4 or type(id)=="string" then return Store.loadSnapshot(session,id) end
  local target=assert(session.records[id],"Missing frame.")
  local cache=session.reader
  local start=target.base
  local rows
  if cache and cache.id>=start and cache.id<=id then start,rows=cache.id+1,cache.rows end
  if start<=id then
    local file <close> = assert(io.open(packPath(session,target.generation),"rb"))
    for n=start,id do rows=Codec.decode(file,assert(session.records[n]),rows) end
  end
  session.reader={id=id,rows=rows}
  local image=Image(target.w,target.h,ColorMode.RGB)
  image.bytes=table.concat(rows)
  return image
end

function Store.offset(session,id)
  local crop=session.info.crop
  if crop then return -crop.x,-crop.y end
  local boundaries=session.boundaries
  local cache=session.offsetCache
  if not cache or cache.count~=#boundaries or cache.revision~=session.editRevision then
    cache={count=#boundaries,revision=session.editRevision,x={},y={}}
    local x,y=0,0
    for i=#boundaries,1,-1 do
      x,y=x+boundaries[i].dx,y+boundaries[i].dy
      cache.x[i],cache.y[i]=x,y
    end
    session.offsetCache=cache
  end
  local lo,hi=1,#boundaries+1
  while lo<hi do
    local mid=(lo+hi)//2
    if boundaries[mid].id<=id then lo=mid+1 else hi=mid end
  end
  return cache.x[lo] or 0,cache.y[lo] or 0
end

function Store.exportSnapshot(session)
  local snapshot= {
    folder=session.folder, name=session.name, project=session.project, pack=session.pack,
    records=session.records, editAnchors=session.editAnchors,
    editRevision=session.editRevision, info={}, boundaries={}
  }
  -- Existing records and pack bytes are immutable. Resize geometry can change as captures arrive.
  for key,value in pairs(session.info) do snapshot.info[key]=value end
  for i,boundary in ipairs(session.boundaries) do
    snapshot.boundaries[i]={id=boundary.id,dx=boundary.dx,dy=boundary.dy}
  end
  return snapshot
end

local function indexRecord(session,event)
  local r=event.record
  local id=event.snapshot
  session.records[id]=r
  session.lastCapture=id
  if event.boundary then
    local b=event.boundary
    b.id=id
    session.boundaries[#session.boundaries+1]=b
    if not session.info.crop then session.info.captureWidth,session.info.captureHeight=r.w,r.h end
  end
end

function Store.setAlignment(session,id,dx,dy)
  assert(math.tointeger(dx) and math.tointeger(dy),"Use whole pixel offsets.")
  for _,b in ipairs(session.boundaries) do
    if b.id==id then
      Store.edit(session,{kind="alignment",id=id,dx=dx,dy=dy})
      return
    end
  end
  error("Unknown resize boundary.")
end

function Store.loadSnapshot(session, id)
  if type(id)=="string" then
    local edited=Store.loadImage(Store.snapshotPath(session,id))
    local anchor=session.editAnchors and session.editAnchors[id]
    if not anchor or session.info.crop then return edited end
    local x,y=0,0
    for _,b in ipairs(session.boundaries) do
      if b.id>anchor.id then x,y=x+b.dx,y+b.dy end
    end
    if anchor.crop and #session.boundaries>0 then x,y=x+anchor.crop.x,y+anchor.crop.y end
    if x==0 and y==0 and edited.width==session.info.captureWidth and edited.height==session.info.captureHeight then return edited end
    return Image(edited,Rectangle(-x,-y,session.info.captureWidth,session.info.captureHeight))
  end
  if session.info.version==4 then
    local image=Store.loadNative(session,id)
    local x,y=Store.offset(session,id)
    local w,h=session.info.captureWidth,session.info.captureHeight
    if x==0 and y==0 and image.width==w and image.height==h then return image end
    return Image(image,Rectangle(-x,-y,w,h))
  end
  if session.info.version == 2 then
    local image = Image(session.info.captureWidth, session.info.captureHeight, ColorMode.RGB)
    local bytes = read(Store.snapshotPath(session, id))
    assert(#bytes == image.rowStride * image.height, "Incomplete RGBA snapshot.")
    image.bytes = bytes
    return image
  end
  local path = Store.png(session, id)
  local image = Store.loadImage(path)
  assert(image.width == session.info.captureWidth and image.height == session.info.captureHeight,
    "Unexpected snapshot size: " .. path)
  return image
end

function Store.writeImage(image, path)
  Store.assertLocalPath(path)
  assert(image:saveAs(path) and fs.isFile(path), "Cannot write PNG: " .. path)
end

function Store.copy(source, destination)
  write(destination, read(source), "wb")
end

function Store.writeText(path, text)
  write(path, text, "wb")
end

function Store.move(source, destination)
  Store.assertLocalPath(destination)
  assert(os.rename(source, destination))
end

function Store.remove(path)
  if fs.isFile(path) then return os.remove(path) end
  return true
end

function Store.snapshotPath(session, id)
  if type(id) == "string" then
    assert(id:match("^edits/[%w_/-]+%.png$") and not id:find("..", 1, true), "Invalid edit path.")
    return join(session.folder, id)
  end
  if session.info.version ~= 2 then return Store.png(session, id) end
  return join(session.folder, "snapshots", string.format("%06d.rgba", id))
end

function Store.saveSnapshot(session, image)
  if session.info.version==4 then
    local id=session.nextPng
    local last=session.records[session.lastCapture]
    local force=not last or id-last.base>=120
    local data,ref=Codec.encode(session,image,force)
    Store.assertLocalPath(session.pack)
    local file = assert(io.open(session.pack,"ab"))
    local offset=assert(file:seek("end"))
    local written,writeError=file:write(data)
    local closed,closeError=file:close()
    assert(written,writeError)
    assert(closed,closeError)
    session.pending={generation=session.generation>0 and session.generation or nil,offset=offset,length=#data,w=image.width,h=image.height,ref=ref,base=ref and id or last.base}
    session.nextPng=id+1
    return id
  end
  if session.info.version == 3 then return Store.savePng(session, image) end
  assert(session.info.version == 2, "Unsupported recording format.")
  assert(image.rowStride == session.info.rowStride, "Unexpected RGBA row stride.")
  local id = session.nextPng
  session.nextPng = id + 1
  local path = Store.snapshotPath(session, id)
  local pending = path .. ".pending"
  assert(not fs.isFile(path) and not fs.isFile(pending), "Snapshot number already exists.")
  write(pending, image.bytes, "wb")
  Store.move(pending, path)
  return id
end

local function completePng(session, id)
  if session.info.version == 2 then
    return fs.fileSize(Store.snapshotPath(session, id)) == session.info.rowStride * session.info.captureHeight
  end
  if not fs.isFile(Store.png(session, id)) then return false end
  local file = assert(io.open(Store.png(session, id), "rb"))
  local header = file:read(24)
  local ending = file:seek("end", -12) and file:read(12)
  assert(file:close())
  if not header or #header ~= 24 or header:sub(1, 16) ~= "\137PNG\r\n\26\n\0\0\0\13IHDR"
    or ending ~= "\0\0\0\0IEND\174\66\96\130" then return false end
  local width, height = string.unpack(">I4I4", header, 17)
  return width == session.info.captureWidth and height == session.info.captureHeight
end

function Store:load(descriptor)
  local project={}
  for key,value in pairs(descriptor.project) do project[key]=value end
  local session = {
    folder=descriptor.folder, project=project, name=descriptor.name,
    info=readJson(join(descriptor.folder,"session.json")), records={}, boundaries={}, pack=join(descriptor.folder,"frames.pack"), nextPng=1, recovered=false, missing={}, editOps={}, editRevision=0
  }
  local binding = join(session.folder,"source.json")
  if fs.isFile(binding) then session.info.source=readJson(binding).source end
  if session.info.source then project.source=session.info.source end
  assert(session.info.version == 1 or session.info.version == 2 or session.info.version == 3 or session.info.version == 4, "Unsupported AseLaps session format.")
  if session.info.version == 2 then
    assert(session.info.captureMode == "sampled" and session.info.rowStride == session.info.captureWidth*4
      and (session.info.intervalMs == 500 or session.info.intervalMs == 1000 or session.info.intervalMs == 2000),
      "Invalid sampled session metadata.")
  end
  local snapshots = {}
  local hasPending = false
  for _, name in ipairs(entries(join(session.folder, "snapshots"))) do
    local id = tonumber(name:match(session.info.version == 2 and "^(%d+)%.rgba$" or "^(%d+)%.png$"))
    local pending = tonumber(name:match(session.info.version == 2 and "^(%d+)%.rgba%.pending$" or "^(%d+)%.pending%.png$"))
    if id or pending then session.nextPng = math.max(session.nextPng, (id or pending) + 1) end
    if id then snapshots[id] = completePng(session, id) end
    if pending then hasPending = true end
  end

  local files = entries(session.folder)
  local journals = {}
  local generation = 0
  for _, name in ipairs(files) do
    if name == "events.jsonl" then
      journals[#journals + 1] = { name=name, number=0 }
    else
      local number = tonumber(name:match("^events%.(%d+)%.jsonl$"))
      if number and number > 0 then
        journals[#journals + 1] = { name=name, number=number }
        generation = math.max(generation, number)
      end
    end
  end
  table.sort(journals, function(a, b) return a.number < b.number end)
  local packSizes={}
  local function completeRecord(record)
    if not record then return false end
    local generation=record.generation or 0
    local size=packSizes[generation]
    if size==nil then
      local path=packPath(session,generation)
      size=fs.isFile(path) and fs.fileSize(path) or -1
      packSizes[generation]=size
    end
    return record.offset>=0 and record.length>=0 and record.offset+record.length<=size
  end
  local function replay()
    session.history = self.history.new()
    local damaged, lastPng = false, 0
    for _, journal in ipairs(journals) do
      damaged = false
      local file = assert(io.open(join(session.folder, journal.name), "rb"))
      for line in file:lines("L") do
        local decoded, event = pcall(decode, line)
        local png = decoded and math.tointeger(event.snapshot or event.png)
        if png and session.info.version~=4 then session.nextPng = math.max(session.nextPng, png + 1) end
        if not damaged then
          if line:sub(-1) ~= "\n" or not decoded or not session.history:accepts(event)
            or (png and session.info.version==4 and not completeRecord(event.record))
            then
            damaged = true
            session.recovered = true
          else
            session.history:apply(event)
            if event.source then session.project.source=event.source end
            if png and session.info.version==4 then
              indexRecord(session,event)
              session.nextPng=png+1
            elseif png and not snapshots[png] then session.missing[png] = true end
            if png and snapshots[png] then lastPng = math.max(lastPng, png) end
          end
        end
      end
      assert(file:close())
    end
    return damaged, lastPng
  end

  local damaged, lastPng = replay()
  -- Committed snapshots are renamed before journaling. Check the end of an
  -- interrupted recording for truncation without opening images in Aseprite.
  if session.recovered or hasPending or session.history.status == "recording" then
    while lastPng > 0 and not completePng(session, lastPng) do
      snapshots[lastPng] = nil
      damaged, lastPng = replay()
    end
  end
  if damaged then generation = generation + 1 end
  local name = generation == 0 and "events.jsonl" or string.format("events.%06d.jsonl", generation)
  session.journal = join(session.folder, name)
  session.generation=generation
  session.pack=packPath(session,generation)

  session.orphans = {}
  for id, valid in pairs(snapshots) do
    if valid and not session.history.snapshots[id] then
      session.orphans[#session.orphans + 1] = id
    end
  end
  table.sort(session.orphans)
  Store.loadEdits(session)
  return session
end

function Store.savePng(session, image)
  local id = session.nextPng
  session.nextPng = id + 1
  local path = Store.png(session, id)
  local pending = join(session.folder, "snapshots", string.format("%06d.pending.png", id))
  assert(fs.isDirectory(fs.filePath(path)), "Snapshot folder is unavailable: " .. fs.filePath(path))
  assert(not fs.isFile(path) and not fs.isFile(pending), "Snapshot number already exists.")
  Store.writeImage(image, pending)
  Store.move(pending, path)
  return id
end

function Store.append(session, event)
  assert(not session.faulted, "Reopen the session after the storage error before writing.")
  event.id = #session.history.events + 1
  event.time = event.time or os.time()
  assert(session.history:accepts(event), "Invalid AseLaps history event.")
  if session.info.version==4 and event.snapshot then
    event.record=assert(session.pending,"Missing frame data.")
  end
  write(session.journal, json.encode(event) .. "\n", "ab")
  session.history:apply(event)
  if session.info.version==4 and event.record then indexRecord(session,event); session.pending=nil end
end

function Store:open(path)
  assert(fs.fileName(path):lower() == "session.json", "Select session.json.")
  local folder = fs.filePath(path)
  local info = readJson(path)
  local project = {title=info.title or fs.fileName(folder), source=info.source, folder=fs.filePath(folder), standalone=true}
  if not info.title then
    local legacy = join(fs.filePath(fs.filePath(folder)), "project.json")
    if fs.isFile(legacy) then
      project = readJson(legacy)
      project.folder = fs.filePath(fs.filePath(folder))
    end
  end
  return self:load{folder=folder, project=project, info=info, name=fs.fileName(folder)}
end

local applyAlignments
function Store.loadEdits(session)
  session.offsetCache=nil
  local path = join(session.folder, "edits.jsonl")
  session.editOps, session.editRevision = {}, 0
  for _,b in ipairs(session.boundaries or {}) do
    if not b.original then b.original={b.dx,b.dy,b.uncertain} end
    b.dx,b.dy,b.uncertain=table.unpack(b.original)
  end
  if not fs.isFile(path) then return end
  local bytes=read(path)
  session.editTail=nil
  if bytes~="" and bytes:sub(-1)~="\n" then
    local ending=bytes:match(".*()\n") or 0
    session.editTail=bytes:sub(ending+1)
    bytes=bytes:sub(1,ending)
    session.recovered=true
  end
  for line in bytes:gmatch("[^\n]+\n") do
    local ok, event = pcall(decode, line)
    if not ok then error("Damaged edit history: " .. path) end
    assert(type(event)=="table" and (event.kind=="undo" or event.kind=="exclude" or event.kind=="replace" or event.kind=="alignment"),"Invalid edit history: "..path)
    session.editRevision = session.editRevision + 1
    if event.kind == "undo" then table.remove(session.editOps)
    else session.editOps[#session.editOps+1] = event end
  end
  applyAlignments(session)
end

applyAlignments=function(session)
  session.editAnchors={}
  for _,op in ipairs(session.editOps) do
    if op.kind=="replace" and op.anchor then
      for _,id in ipairs(op.frames) do session.editAnchors[id]=op.anchor end
    elseif op.kind=="alignment" then
      for _,b in ipairs(session.boundaries) do
        if b.id==op.id then b.dx,b.dy,b.uncertain=op.dx,op.dy,false end
      end
    end
  end
end

function Store.edit(session, operation)
  assert(not session.exporting,"Wait for the current export to finish.")
  if session.info.version==4 and operation.kind=="replace" then
    operation.anchor={id=session.lastCapture,crop=#session.boundaries==0 and session.info.crop or nil}
  end
  local path = join(session.folder, "edits.jsonl")
  if fs.isFile(path) then
    local bytes = read(path)
    if bytes~="" and bytes:sub(-1)~="\n" then
      -- Preserve the interrupted journal before restoring its committed prefix.
      local ending=bytes:match(".*()\n") or 0
      local backup=numberedDirectory(session.folder,"edit-recovery")
      Store.copy(path,join(backup,"edits.jsonl"))
      local pending=path..".recovered"
      write(pending,bytes:sub(1,ending),"wb")
      local original=join(backup,"original.jsonl")
      Store.move(path,original)
      local ok,message=pcall(Store.move,pending,path)
      if not ok then Store.move(original,path); error(message,0) end
    end
  end
  write(path, json.encode(operation) .. "\n", "ab")
  Store.loadEdits(session)
end

function Store.timeline(session, mode, head, includeExcluded, includeMissing)
  local base, reason = session.history:timeline(mode or "Full", head)
  assert(base, reason)
  local frames = {}
  for _, id in ipairs(base) do frames[#frames+1] = id end
  local excluded = {}
  for _, operation in ipairs(session.editOps or {}) do
    if operation.kind == "exclude" then
      for _, id in ipairs(operation.ids) do excluded[tostring(id)] = operation.value end
    elseif operation.kind == "replace" then
      local first, last
      for i, id in ipairs(frames) do
        if tostring(id) == tostring(operation.first) then first = i end
        if tostring(id) == tostring(operation.last) then last = i end
      end
      if first and last and first <= last then
        local result = {}
        for i=1,first-1 do result[#result+1] = frames[i] end
        for _, id in ipairs(operation.frames) do result[#result+1] = id end
        for i=last+1,#frames do result[#result+1] = frames[i] end
        frames = result
      end
    end
  end
  local result, missing = {}, {}
  for _, id in ipairs(frames) do
    if includeExcluded or not excluded[tostring(id)] then
      if session.missing[id] or (type(id)=="number" and session.info.version==4 and not session.records[id]) or (type(id)=="string" and not fs.isFile(Store.snapshotPath(session,id))) then
        missing[#missing+1] = id
        if includeMissing then result[#result+1] = id end
      else result[#result+1] = id end
    end
  end
  return result, missing
end

function Store:convert(session, parent)
  local info = {}
  for key,value in pairs(session.info) do info[key] = value end
  info.version, info.captureMode, info.intervalMs = 3, "sampled", info.intervalMs or 500
  info.folder = numberedDirectory(parent, "PNG_copy_" .. session.name)
  -- create() owns creation of the session directory.
  assert(fs.removeDirectory(info.folder))
  local converted = self:create(session.project, info)
  for _, event in ipairs(session.history.events) do
    local copy = {}
    for key,value in pairs(event) do copy[key] = value end
    local id = event.snapshot or event.png
    if id and not session.missing[id] and not fs.isFile(Store.png(converted,id)) then
      Store.writeImage(Store.loadSnapshot(session,id), Store.png(converted,id))
      assert(Store.loadSnapshot(converted,id):isEqual(Store.loadSnapshot(session,id)), "PNG verification failed.")
    end
    copy.record,copy.boundary=nil,nil
    Store.append(converted,copy)
  end
  for _, operation in ipairs(session.editOps) do
    if operation.kind == "replace" then
      for _, id in ipairs(operation.frames) do
        local target = Store.snapshotPath(converted,id)
        ensureDirectory(fs.filePath(target))
        Store.writeImage(Store.loadSnapshot(session,id),target)
        assert(Store.loadImage(target):isEqual(Store.loadSnapshot(session,id)),"Edited PNG verification failed.")
      end
    end
    if operation.kind~="alignment" then
      local copy={}
      for key,value in pairs(operation) do copy[key]=value end
      copy.anchor=nil
      Store.edit(converted,copy)
    end
  end
  return self:load(converted)
end

Store.align = Codec.align
Store.ensureDirectory = ensureDirectory
Store.numberedDirectory = numberedDirectory
Store.readText = read
return Store
