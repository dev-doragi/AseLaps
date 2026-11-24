local fs=app.fs
local root,work=assert(app.params.root),assert(app.params.work)
local function module(name) return dofile(fs.joinPath(root,"extension",name..".lua")) end
local H,S,R,E=module("history"),module("store"),module("recorder"),module("export")
local U=module("ui")
assert(U.version=="2.2.0-rc.1" or U.version=="@ASELAPS_VERSION@")
assert(not E.isAbsolute('C:\\recordings\\C:\\art\\session.json'))
local ending={}
for i=1,19556 do ending[i]=i end
local sampled=E.sample(ending,15)
assert(sampled[#sampled]==19556 and sampled[#sampled-1]==19546)
S.recordingRoot=function() return fs.joinPath(work,"recordings") end
local store=S.new(fs.joinPath(work,"legacy"),H)
local preferences={}
local recorder=R.new(store,H,preferences,function(message) error(message) end)
local function artwork(folder)
  S.ensureDirectory(fs.joinPath(work,folder))
  local sprite=Sprite(12,12)
  sprite:saveAs(fs.joinPath(work,folder,"same.aseprite"))
  return sprite
end
local first=artwork("one")
local doc=recorder:document(first)
recorder:start(doc)
local session=doc.session
local second=artwork("two")
local other=recorder:document(second)
assert(not other.session,"A same-name artwork must not attach to another source.")
other.session=session
assert(not pcall(recorder.resume,recorder,other),"Duplicate writers must be refused.")
other.session=nil
app.sprite=first
recorder:status(doc,"paused")

-- Fixed crop remains in canvas coordinates after expansion and contraction.
recorder:start(doc,{x=2,y=3,w=5,h=4})
session=doc.session
first.cels[1].image:drawPixel(3,4,app.pixelColor.rgba(255,77,33,255))
recorder:sample(doc,true)
first:crop(Rectangle(-2,-1,16,15))
recorder:sample(doc,true)
assert(session.info.captureWidth==5 and session.info.captureHeight==4)
local cropped=S.loadSnapshot(session,session.lastCapture)
assert(cropped.width==5 and cropped.height==4)
assert(cropped:getPixel(3,2)~=0)
first:crop(Rectangle(0,0,3,3))
recorder:sample(doc,true)
cropped=S.loadSnapshot(session,session.lastCapture)
assert(cropped:getPixel(4,3)==0)
recorder:status(doc,"paused")

-- Interrupted final edit is backed up and repaired; middle corruption is rejected.
S.edit(session,{kind="exclude",ids={1},value=true})
local editPath=fs.joinPath(session.folder,"edits.jsonl")
local file=assert(io.open(editPath,"ab")); file:write('{"kind":'); file:close()
session=store:open(fs.joinPath(session.folder,"session.json"))
assert(session.recovered and session.editTail)
S.edit(session,{kind="undo"})
assert(not session.editTail and #session.editOps==0)
local backup=false
for _,entry in ipairs(fs.listFiles(session.folder)) do
  if fs.fileName(entry):match("^edit%-recovery_") then backup=true end
end
assert(backup)

-- Edited frames must be transformed when converting after a resize.
first=artwork("resize")
doc=recorder:document(first)
recorder:start(doc)
session=doc.session
S.ensureDirectory(fs.joinPath(session.folder,"edits"))
local image=Image(12,12,ColorMode.RGB)
image:drawPixel(1,1,app.pixelColor.rgba(70,150,230,255))
S.writeImage(image,fs.joinPath(session.folder,"edits","test.png"))
S.edit(session,{kind="replace",first=1,last=1,frames={"edits/test.png"}})
first:crop(Rectangle(-2,-3,14,15))
recorder:sample(doc,true)
S.setAlignment(session,session.lastCapture,2,3)
recorder:status(doc,"paused")
local converted=store:convert(session,fs.joinPath(work,"converted"))
local before,after=S.timeline(session),S.timeline(converted)
assert(#before==#after)
for i,id in ipairs(before) do assert(S.loadSnapshot(session,id):isEqual(S.loadSnapshot(converted,after[i]))) end

-- Normal close flushes a change before the sampling timer fires.
recorder:watch()
recorder:resume(doc)
app.useTool{tool="pencil",color=Color{r=23,g=155,b=99},points={Point(5,5)}}
local previous=session.history.count
first:saveAs(first.filename)
app.command.CloseFile()
assert(session.history.count>previous,"CloseFile must flush the last drawing change.")
recorder:shutdown()

-- Coroutine export preserves an old destination when cancelled.
local function options(format)
  return {mode="Full",format=format,background="White",ratio="",scale=1,fps=30,hold=0,step=1,folder=work,ffmpeg=app.params.ffmpeg}
end
local input=options("PNG sequence")
input.sequenceFolder=fs.joinPath(work,"cancelled-png")
input.control={}
local task=coroutine.create(function() return E.run(store,converted,input) end)
assert(coroutine.resume(task))
input.control.cancelled=true
local ok=coroutine.resume(task)
assert(not ok and not fs.isDirectory(input.sequenceFolder))
input=options("PNG sequence")
input.sequenceFolder=fs.joinPath(work,"complete-png")
input.control={}
task=coroutine.create(function() return E.run(store,converted,input) end)
repeat assert(coroutine.resume(task)) until coroutine.status(task)=="dead"
assert(fs.isFile(fs.joinPath(input.sequenceFolder,"frame_000001.png")))
if app.params.ffmpeg then
  for _,format in ipairs({"MP4","GIF"}) do
    input=options(format)
    input.output=fs.joinPath(work,"async."..format:lower())
    input.control={}
    task=coroutine.create(function() return E.run(store,converted,input) end)
    local started=os.time()
    repeat
      local success,result=coroutine.resume(task)
      assert(success,result)
      assert(os.time()-started<60,"Async encoder timed out")
    until coroutine.status(task)=="dead"
    assert(fs.fileSize(input.output)>0)
  end
  input=options("MP4")
  input.output=fs.joinPath(work,"keep.mp4")
  S.writeText(input.output,"original video")
  input.overwrite=true
  input.control={}
  task=coroutine.create(function() return E.run(store,converted,input) end)
  assert(coroutine.resume(task))
  input.control.cancelled=true
  assert(not coroutine.resume(task))
  assert(S.readText(input.output)=="original video")
end
file=assert(io.open(editPath,"ab")); file:write("broken\n"); file:close()
assert(not pcall(store.open,store,fs.joinPath(fs.filePath(editPath),"session.json")))
print("ASELAPS_RELEASE_OK")
