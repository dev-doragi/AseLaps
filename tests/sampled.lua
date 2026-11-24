local root, work = assert(app.params.root), assert(app.params.work)
local function module(name) return dofile(app.fs.joinPath(root, "extension", name..".lua")) end
local H,S,R,E = module("history"),module("store"),module("recorder"),module("export")
assert(loadfile(app.fs.joinPath(root,"extension","ui.lua")))
assert(loadfile(app.fs.joinPath(root,"extension","init.lua")))
S.recordingRoot=function() return app.fs.joinPath(work,"local-recordings") end
local store = S.new(work,H)
local warnings={}
local r=R.new(store,H,{},function(s) warnings[#warnings+1]=s end)
local sprite=Sprite(16,16)
sprite:saveAs(app.fs.joinPath(work,"art.aseprite"))
local doc=r:document(sprite)
r:start(doc)
local session=doc.session
assert(session.info.version==4 and session.history.count==1)
local function paint(x)
  app.useTool{tool="pencil",color=Color{r=255,g=17,b=31,a=128},points={Point(x,1)}}
end
local original=S.loadSnapshot(session,1)
assert(original:isEqual(R.render(sprite,1,session.info)))
paint(1); paint(2)
assert(session.history.count==1 and doc.dirty)
r:tick(250); assert(session.history.count==1)
r:tick(250); assert(session.history.count==2)
assert(S.loadSnapshot(session,2):isEqual(R.render(sprite,1,session.info)))
local saves=S.saveSnapshot
S.saveSnapshot=function() error("Navigation must not save") end
for i=1,100 do r:site() end
r:tick(1000)
S.saveSnapshot=saves
assert(session.history.count==2)
paint(3); r:status(doc,"paused"); assert(session.history.count==3)
r:resume(doc); r:tick(500)
paint(4); r:tick(5000); assert(session.history.count==5)
local loaded=store:load(session)
assert(loaded.history.count==5)
local options={mode="Full",format="PNG sequence",background="Transparent",ratio="",scale=1,fps=10,hold=0,folder=app.fs.joinPath(work,"export")}
E.run(store,session,options)
local legacy=store:create(doc.project,{width=16,height=16,captureWidth=16,captureHeight=16})
local id=S.savePng(legacy,original)
S.append(legacy,{kind="state",parent=0,png=id,emit=true,label="Legacy"})
assert(store:load(legacy).history:timeline("Clean")[1]==id)
assert(S.loadSnapshot(legacy,id):isEqual(original))
if app.params.ffmpeg then
  options.ffmpeg=app.params.ffmpeg
  for _, format in ipairs({"MP4","GIF"}) do
    options.format=format
    options.background="White"
    local loadSnapshot,writeImage=S.loadSnapshot,S.writeImage
    S.writeImage=function() error("Video export must not create intermediate PNGs") end
    local outputs=E.run(store,session,options)
    S.loadSnapshot,S.writeImage=loadSnapshot,writeImage
    assert(app.fs.fileSize(outputs[1])>0)
    for _,path in ipairs(app.fs.listFiles(app.fs.filePath(outputs[1]))) do
      assert(not path:match("%.png$") and not path:match("%.ffconcat$"),path)
    end
    E.run(store,legacy,options)
  end
end
local f=assert(io.open(session.journal,"ab")); f:write("partial"); f:close()
local recovered=store:load(session)
assert(recovered.recovered and #S.timeline(recovered,"Full")==5)
assert(#warnings==0,table.concat(warnings,"\n"))
r:shutdown()
print("ASELAPS_SAMPLED_OK")
print("CONFIG="..app.fs.userConfigPath)
