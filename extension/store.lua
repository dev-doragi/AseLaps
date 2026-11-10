local fs = app.fs
local join = fs.joinPath
local Store = {}
Store.__index = Store

local function write(path, bytes, mode)
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

function Store.new(root, history)
  return setmetatable({ root=root, history=history }, Store)
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
  if source then
    for _, project in ipairs(self:projects()) do
      if project.source == source then return project end
    end
  end
  if not create then return nil end
  local title = fs.fileTitle(sprite.filename)
  if title == "" then title = "Untitled" end
  local prefix = os.date("%Y%m%d_%H%M%S")
  local folder = numberedDirectory(self.root, prefix)
  local info = { version=1, title=title, source=source }
  writeNewJson(join(folder, "project.json"), info)
  info.folder = folder
  return info
end

function Store:bind(project, source)
  assert(not project.source and source, "Project already has a source document.")
  writeNewJson(join(project.folder, "source.json"), { source=source })
  project.source = source
end

function Store:sessions(project)
  local result = {}
  for _, name in ipairs(entries(join(project.folder, "sessions"))) do
    local path = join(project.folder, "sessions", name, "session.json")
    if fs.isFile(path) then
      result[#result + 1] = {
        folder=fs.filePath(path), project=project, name=name, info=readJson(path)
      }
    end
  end
  return result
end

function Store:create(project, info)
  local folder = numberedDirectory(join(project.folder, "sessions"), os.date("%Y%m%d_%H%M%S"))
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

function Store.loadSnapshot(session, id)
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
  assert(image:saveAs(path) and fs.isFile(path), "Cannot write PNG: " .. path)
end

function Store.copy(source, destination)
  write(destination, read(source), "wb")
end

function Store.writeText(path, text)
  write(path, text, "wb")
end

function Store.move(source, destination)
  assert(os.rename(source, destination))
end

function Store.remove(path)
  if fs.isFile(path) then return os.remove(path) end
  return true
end

function Store.snapshotPath(session, id)
  if session.info.version == 1 then return Store.png(session, id) end
  return join(session.folder, "snapshots", string.format("%06d.rgba", id))
end

function Store.saveSnapshot(session, image)
  assert(session.info.version == 2, "New recordings require a sampled session.")
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
  local session = {
    folder=descriptor.folder, project=descriptor.project, name=descriptor.name,
    info=descriptor.info, nextPng=1, recovered=false
  }
  assert(session.info.version == 1 or session.info.version == 2, "Unsupported AseLaps session format.")
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
    if id then snapshots[id] = session.info.version == 1 or completePng(session, id) end
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
  local function replay()
    session.history = self.history.new()
    local damaged, lastPng = false, 0
    for _, journal in ipairs(journals) do
      damaged = false
      local file = assert(io.open(join(session.folder, journal.name), "rb"))
      for line in file:lines("L") do
        local decoded, event = pcall(decode, line)
        local png = decoded and math.tointeger(event.snapshot or event.png)
        if png then session.nextPng = math.max(session.nextPng, png + 1) end
        if not damaged then
          if line:sub(-1) ~= "\n" or not decoded or not session.history:accepts(event)
            or (png and not snapshots[png]) then
            damaged = true
            session.recovered = true
          else
            session.history:apply(event)
            if png then lastPng = math.max(lastPng, png) end
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

  session.orphans = {}
  for id, valid in pairs(snapshots) do
    if valid and not session.history.snapshots[id] then
      session.orphans[#session.orphans + 1] = id
    end
  end
  table.sort(session.orphans)
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
  event.time = os.time()
  assert(session.history:accepts(event), "Invalid AseLaps history event.")
  write(session.journal, json.encode(event) .. "\n", "ab")
  session.history:apply(event)
end

Store.ensureDirectory = ensureDirectory
Store.numberedDirectory = numberedDirectory
Store.readText = read
return Store
