local fs = app.fs
local join = fs.joinPath
local function module(name) return dofile(join(app.params.root, "extension", name .. ".lua")) end
local History, Store, Recorder = module("history"), module("store"), module("recorder")
local work = assert(app.params.work)
local store = Store.new(join(work, "recordings"), History)
local recorder = Recorder.new(store, History, {}, function(message) error(message) end)
local filename = join(work, "crash.aseprite")
local color = Color{ r=255, g=0, b=0 }
if app.params.phase == "write" then
  Store.ensureDirectory(work)
  local sprite = Sprite(9, 9)
  sprite:saveAs(filename)
  local doc = recorder:document(sprite)
  recorder:start(doc)
  app.useTool{ tool="pencil", color=color, points={Point(1, 1)} }
  sprite:saveAs(filename)
  local orphan = Store.savePng(doc.session, Recorder.render(sprite, 1, doc.session.info))
  assert(orphan == 3)
  local journal = assert(io.open(doc.session.journal, "ab"))
  assert(journal:write('{"id":'))
  assert(journal:close())
  local signal = assert(io.open(join(work, "ready"), "wb"))
  assert(signal:close())
  local expires = os.clock() + 30
  repeat until os.clock() > expires
  error("The crash test process was not terminated.")
else
  local sprite = assert(app.open(filename))
  recorder:site()
  local doc = assert(recorder.documents[sprite.id])
  assert(doc.running and doc.session.recovered and doc.session.history.count == 2)
  assert(doc.session.orphans[1] == 3)
  app.useTool{ tool="pencil", color=color, points={Point(2, 2)} }
  assert(doc.session.history.count == 3 and fs.isFile(Store.png(doc.session, 4)))
  recorder:shutdown()
  print("ASELAPS_CRASH_RECOVERY_OK")
end
