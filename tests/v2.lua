local fs=app.fs
local root,work=assert(app.params.root),assert(app.params.work)
local function module(name) return dofile(fs.joinPath(root,"extension",name..".lua")) end
local H,S,R,E,U=module("history"),module("store"),module("recorder"),module("export"),module("ui")
S.ensureDirectory(work)
local store=S.new(fs.joinPath(work,"legacy"),H)
local sprite=Sprite(8,8)
sprite:saveAs(fs.joinPath(work,"art.aseprite"))
local prefs={}
S.recordingRoot=function() return fs.joinPath(work,"local-recordings") end
assert(not pcall(S.assertLocalPath,fs.joinPath(os.getenv("USERPROFILE"),"OneDrive","blocked.png")))
assert(pcall(S.assertLocalPath,fs.joinPath(work,"allowed.png")))
local recorder=R.new(store,H,prefs,function(message) error(message) end)
local doc=recorder:document(sprite)
-- Exercise compatibility with a recording made by the v3 PNG writer.
function store:create(project,info)
  if info.version==4 then info.version=3 end
  return S.create(self,project,info)
end
recorder:start(doc)
for i=1,5 do
  sprite.cels[1].image:drawPixel(i,1,app.pixelColor.rgba(i*30,100,10,255))
  recorder:sample(doc,true)
end
recorder:status(doc,"paused")
local session=doc.session
assert(session.info.version==3 and session.history.count==6)
assert(fs.filePath(session.folder):match("art__record$"))
assert(fs.isFile(S.snapshotPath(session,1)) and not fs.isFile(fs.joinPath(session.folder,"snapshots","000001.rgba")))
S.edit(session,{kind="exclude",ids={2,3},value=true})
local loaded=store:open(fs.joinPath(session.folder,"session.json"))
assert(#S.timeline(loaded)==4)
S.edit(loaded,{kind="undo"})
assert(#S.timeline(loaded)==6)
local edited=Sprite(8,8)
edited.properties["aselapsEdit"]=json.encode({session=fs.joinPath(session.folder,"session.json"),first=2,last=4,revision=loaded.editRevision})
edited.cels[1].image:drawPixel(0,0,app.pixelColor.rgba(255,0,0,255))
edited:newEmptyFrame()
edited:newCel(edited.layers[1],2,edited.cels[1].image)
local ui=U.new(recorder,E,prefs)
ui:applyEdit()
loaded=store:open(fs.joinPath(session.folder,"session.json"))
local frames=S.timeline(loaded)
assert(#frames==5 and type(frames[2])=="string" and type(frames[3])=="string")
assert(S.loadSnapshot(loaded,frames[2]):isEqual(edited.cels[1].image))
assert(not recorder:document(edited))
-- Edit metadata survives saving and reopening the document.
edited:saveAs(fs.joinPath(work,"edit.aseprite"))
local reopened=app.open(fs.joinPath(work,"edit.aseprite"))
assert(reopened.properties["aselapsEdit"])
-- A stale edit cannot overwrite a subsequent exclusion.
S.edit(loaded,{kind="exclude",ids={6},value=true})
assert(not pcall(function() ui:applyEdit() end))
S.edit(loaded,{kind="undo"})
S.edit(loaded,{kind="undo"})
assert(#S.timeline(loaded)==6)
-- Missing middle files preserve every later journal entry.
assert(os.remove(S.snapshotPath(loaded,3)))
loaded=store:open(fs.joinPath(session.folder,"session.json"))
assert(loaded.history.count==6 and loaded.missing[3])
assert(#S.timeline(loaded)==5)
-- Standalone session can move with no project metadata.
local moved=fs.joinPath(work,"moved")
assert(os.rename(session.folder,moved))
loaded=store:open(fs.joinPath(moved,"session.json"))
assert(#S.timeline(loaded)==5)
-- Legacy raw data converts losslessly to a new PNG copy.
local raw=store:create({folder=work,title="Raw",standalone=true},{version=2,captureMode="sampled",intervalMs=500,width=8,height=8,captureWidth=8,captureHeight=8,rowStride=32})
local image=Image(8,8,ColorMode.RGB)
image:drawPixel(2,2,app.pixelColor.rgba(99,88,77,123))
local id=S.saveSnapshot(raw,image)
S.append(raw,{kind="state",parent=0,snapshot=id,emit=true,label="Raw"})
local converted=store:convert(raw,fs.joinPath(work,"converted"))
assert(converted.info.version==3 and S.loadSnapshot(converted,1):isEqual(image))
assert(fs.isFile(S.snapshotPath(raw,1)))
if app.params.ffmpeg then
  local options={mode="Full",format="MP4",background="White",ratio="",scale=4,fps=24,hold=2,step=10,ffmpeg=app.params.ffmpeg,folder=work,output=fs.joinPath(work,"custom.mp4")}
  local output=E.run(store,converted,options)
  assert(output[1]==options.output and fs.fileSize(output[1])>0)
  assert(not pcall(function() E.run(store,loaded,options) end))
end
print("ASELAPS_V2_OK")

