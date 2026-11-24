local fs=app.fs
local root,work=app.params.root,app.params.work
local function module(n) return dofile(fs.joinPath(root,"extension",n..".lua")) end
local H,S,R,E=module("history"),module("store"),module("recorder"),module("export")
S.ensureDirectory(work)
S.recordingRoot=function() return work end
local store=S.new(work,H)
local sprite=Sprite(208,304)
sprite:saveAs(fs.joinPath(work,"test.aseprite"))
app.useTool{tool="pencil",color=Color{r=111,g=22,b=55,a=255},points={Point(10,15)}}
local recorder=R.new(store,H,{},function(msg) error(msg) end)
local doc=recorder:document(sprite)
recorder:start(doc)
local session=doc.session
local first=S.loadNative(session,1)
local key=first:getPixel(10,15)
assert(key~=0)
sprite.events:on("change",function(ev)
 local keys={}
 for k in pairs(ev) do keys[#keys+1]=k end
 print("RESIZE EVENT",table.concat(keys,","))
end)
sprite:crop(Rectangle(-6,0,214,304))
recorder:sample(doc,false)
sprite:crop(Rectangle(0,-1,214,305))
recorder:sample(doc,false)
assert(session==doc.session and #session.boundaries==2)
local function offset(id,x,y)
 local a,b=S.offset(session,id);assert(a==x and b==y,("%s %s vs %s %s"):format(a,b,x,y))
end
offset(1,6,1);offset(2,0,1)
assert(S.loadSnapshot(session,1):getPixel(16,16)==key)
sprite:crop(Rectangle(30,0,100,200));recorder:sample(doc,false)
assert(S.loadNative(session,1).bytes==first.bytes)
assert(session.boundaries[3].uncertain)
S.setAlignment(session,4,-30,0)
assert(not session.boundaries[3].uncertain)
app.undo();recorder:sample(doc,false)
recorder:status(doc,"paused");recorder:resume(doc);recorder:sample(doc,true)
recorder:status(doc,"paused")
local count=session.history.count
local path=fs.joinPath(session.folder,"session.json")
local file=assert(io.open(session.pack,"ab"));assert(file:write("partial capture"));assert(file:close())
file=assert(io.open(session.journal,"ab"));assert(file:write('{"id":'));assert(file:close())
session=store:open(path)
assert(session.recovered and session.history.count==count)
local image=Image(214,305,ColorMode.RGB)
image.bytes=string.char(33,11,77,0)..image.bytes:sub(5)
local id=S.saveSnapshot(session,image)
S.append(session,{kind="state",snapshot=id,parent=session.history.head,emit=true})
assert(S.loadNative(store:open(path),id).bytes==image.bytes)
S.edit(session,{kind="exclude",ids={2,3},value=true})
local eligible=S.timeline(session,"Full")
assert(#eligible==count-1)
S.edit(session,{kind="undo"});assert(#S.timeline(session,"Full")==count+1)
local many={}
for i=1,13777 do many[i]=i end
assert(#E.sample(many,5)==2756)
if app.params.ffmpeg then
 local opts={mode="Full",format="MP4",background="White",ratio="",scale=1,fps=30,hold=0,step=2,folder=work,ffmpeg=app.params.ffmpeg}
 assert(not pcall(E.checkEncoder,store,"missing.exe"))
 assert(E.checkEncoder(store,opts.ffmpeg))
 -- Include saturated color blocks so frame order is visible after chroma subsampling.
 for _,color in ipairs({Color{r=200,g=20,b=40},Color{r=10,g=180,b=80},Color{r=20,g=60,b=200}}) do
   local block=Image(214,305,ColorMode.RGB)
   block:clear(color)
   local nextId=S.saveSnapshot(session,block)
   S.append(session,{kind="state",snapshot=nextId,parent=session.history.head,emit=true})
 end
 local selection=E.sample(S.timeline(session,"Full"),2)
 opts.sequences={Full=selection}
 local result=E.run(store,session,opts)
 local expected=assert(io.open(fs.joinPath(work,"expected.rgb"),"wb"))
 for _,selected in ipairs(selection) do
   local canvas=Image(214,306,ColorMode.RGB)
   canvas:clear(Color{r=255,g=255,b=255})
   canvas:drawImage(S.loadSnapshot(session,selected),Point(0,0))
   assert(expected:write((canvas.bytes:gsub("(...).","%1"))))
 end
 assert(expected:close())
 print("VIDEO",result[1],#selection)

end
print("ASELAPS_V4_OK")
