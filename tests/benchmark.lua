local fs=app.fs
local root=app.params.root
local work=fs.joinPath(root,".test-work","v4")
local base=app.params.mode=="old"
local ext=base and fs.joinPath(work,"baseline") or fs.joinPath(root,"extension")
local function load(n) return dofile(fs.joinPath(ext,n..".lua")) end
local S,E=load("store"),load("export")
local store=S.new(work,load("history"))
local src=fs.joinPath(work,"Ranger")
local n=13777
local large=app.params.large=="1"
if large then n=100;src=fs.joinPath(work,"Samurai") end
local project={folder=work,title="Benchmark",standalone=true}
local first=S.loadImage(fs.joinPath(src,"snapshots","000001.png"))
local w,h=first.width,first.height
local sess=store:create(project,{folder=fs.joinPath(work,app.params.name),version=base and 3 or 4,width=w,height=h,captureWidth=w,captureHeight=h,rowStride=w*4,captureMode="sampled",intervalMs=500})
local times={}
local function stats(a)
 table.sort(a);return string.format("p50=%.3f p95=%.3f max=%.3f ms",a[(#a+1)//2],a[math.ceil(#a*.95)],a[#a])
end
local function input(i)
 return S.loadImage(fs.joinPath(src,"snapshots",string.format("%06d.png",i)))
end
for i=1,n do
 local image=input(i)
 local start=os.clock()
 local id=S.saveSnapshot(sess,image)
 S.append(sess,{kind="state",snapshot=id,parent=sess.history.head,emit=true,label="Sample",frame=1})
 times[i]=(os.clock()-start)*1000
 if i%1000==0 then print("capture",i) end
end
print("CAPTURE",stats(times))
sess=store:open(fs.joinPath(sess.folder,"session.json"))
for i=1,n do assert(S.loadSnapshot(sess,i).bytes==input(i).bytes,tostring(i)) end
times={}
for i=1,100 do
 local id=(i*7919)%n+1
 local start=os.clock()
 S.loadSnapshot(sess,id)
 times[i]=(os.clock()-start)*1000
end
print("SEEK",stats(times))
local step=large and 1 or 5
-- Old sampler appends the last frame. Give both implementations the same selection.
local frames={}
for i=1,n,step do frames[#frames+1]=i end
store.timeline=function() return frames,{} end
local start=os.clock()
local out=E.run(store,sess,{mode="Full",format="MP4",background="White",ratio="",scale=1,fps=30,hold=0,step=1,folder=work,ffmpeg=app.params.ffmpeg})
print("EXPORT",os.clock()-start,out[1])
print("BENCH_OK")
