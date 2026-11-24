local fs=app.fs
local root,work=assert(app.params.root),assert(app.params.work)
local function module(name) return dofile(fs.joinPath(root,"extension",name..".lua")) end
local H,S,E=module("history"),module("store"),module("export")
local store=S.new(work,H)
local destination=fs.joinPath(work,"한글 O'Brien & percent%")
S.ensureDirectory(destination)
local session=store:create({folder=destination,title="Long session",standalone=true},
  {version=4,captureMode="sampled",intervalMs=500,width=64,height=64,captureWidth=64,captureHeight=64})
local image=Image(64,64,ColorMode.RGB)
local started=os.clock()
for i=1,10001 do
  image:clear(app.pixelColor.rgba(i%256,(i//256)%256,99,255))
  local id=S.saveSnapshot(session,image)
  S.append(session,{kind="state",parent=session.history.head,snapshot=id,emit=true})
end
local recorded=os.clock()-started
session=store:open(fs.joinPath(session.folder,"session.json"))
assert(session.history.count==10001)
for _,id in ipairs({1,120,121,5000,10001,5001,2}) do
  assert(S.loadNative(session,id):getPixel(0,0)==app.pixelColor.rgba(id%256,(id//256)%256,99,255))
end
local big=store:create({folder=destination,title="Large canvas",standalone=true},
  {version=4,captureMode="sampled",intervalMs=500,width=2048,height=2048,captureWidth=2048,captureHeight=2048})
local large=Image(2048,2048,ColorMode.RGB)
for i=1,3 do
  large:drawPixel(i*100,i*100,app.pixelColor.rgba(220,20,i*50,255))
  local id=S.saveSnapshot(big,large)
  S.append(big,{kind="state",parent=big.history.head,snapshot=id,emit=true})
end
assert(S.loadNative(store:open(fs.joinPath(big.folder,"session.json")),3):isEqual(large))
if app.params.ffmpeg then
  local options={mode="Full",format="MP4",background="White",ratio="",scale=1,fps=30,hold=0,step=10,
    ffmpeg=app.params.ffmpeg,folder=destination,output=fs.joinPath(destination,"long.mp4"),control={}}
  local task=coroutine.create(function() return E.run(store,session,options) end)
  local yields=0
  started=os.time()
  repeat
    local ok,value=coroutine.resume(task)
    assert(ok,value)
    yields=yields+1
    assert(os.time()-started<90,"Long export timed out")
  until coroutine.status(task)=="dead"
  assert(yields>1000 and fs.fileSize(options.output)>0)
  print("STRESS_VIDEO",options.output,1001,64,64,30)
  -- Cancellation after the worker has started must preserve the old output.
  options.overwrite=true
  local original=S.readText(options.output)
  options.control={}
  task=coroutine.create(function() return E.run(store,session,options) end)
  local reachedEncoder=false
  started=os.time()
  local result
  repeat
    local ok,value=coroutine.resume(task)
    if not ok then result=value; break end
    if value and value.phase=="Encoding" then options.control.cancelled=true; reachedEncoder=true end
    assert(os.time()-started<90,"Encoder cancellation timed out")
  until coroutine.status(task)=="dead"
  assert(reachedEncoder and result and S.readText(options.output)==original)
end
print(string.format("STRESS_RECORDING_SECONDS %.3f",recorded))
print("ASELAPS_STRESS_OK")
