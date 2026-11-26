local fs = app.fs
local root, work = assert(app.params.root), assert(app.params.work)
local function module(name) return dofile(fs.joinPath(root,"extension",name..".lua")) end
assert(loadfile(fs.joinPath(root,"extension","ui.lua")))
assert(loadfile(fs.joinPath(root,"extension","init.lua")))
local History, Store, Recorder = module("history"), module("store"), module("recorder")
local prefs = {recordingFolder=fs.joinPath(work,"recordings"), initial=false}
local store = Store.new(fs.joinPath(work,"legacy"), History, prefs)
local function newRecorder()
  return Recorder.new(store, History, prefs, function(message) error(message) end)
end
local function paint(x)
  app.useTool{tool="pencil",color=Color{r=255,a=255},points={Point(x,1)}}
end

local recorder = newRecorder()
recorder:watch()
local sprite = Sprite(8,8)
local doc = assert(recorder.documents[sprite.id], "Site change must attach before the first edit.")
assert(not doc.session)
paint(1)
assert(doc.running and doc.session.history.count==1)
local folder = doc.session.folder
local path = fs.joinPath(work,"art.aseprite")
sprite:saveAs(path)
paint(2)
app.command.CloseFile{ui=false}
recorder:shutdown()
local saved = store:open(fs.joinPath(folder,"session.json"))
assert(saved.history.count==2 and Store.pathKey(saved.project.source)==Store.pathKey(path))

-- Recover the link from disk without the preferences index.
prefs.sessionsBySource = nil
recorder = newRecorder()
recorder:watch()
sprite = app.open(path)
doc = assert(recorder.documents[sprite.id])
assert(doc.session.folder==folder and not doc.running)
paint(3)
assert(doc.running and doc.session.history.count==3 and doc.elapsedBase==saved.history.elapsed)
recorder:status(doc,"paused")
paint(4)
assert(not doc.running and doc.session.history.count==3)
recorder:shutdown()
app.command.CloseFile{ui=false}

recorder = newRecorder()
recorder:watch()
sprite = app.open(path)
doc = assert(recorder.documents[sprite.id])
paint(4)
assert(not doc.running and doc.session.history.count==3)
recorder:status(doc,"stopped")
paint(5)
assert(not doc.running and doc.session.history.count==3)
prefs.autoRecord = false
sprite = Sprite(8,8)
paint(6)
assert(not recorder.documents[sprite.id].session)
recorder:shutdown()
print("ASELAPS_AUTORECORD_OK")
