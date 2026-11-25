-- Pure Lua 5.4: no Aseprite dependency. lua tests/codec_pure.lua
local here=debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])") or ""
local root=here.."../extension/"
local C=dofile(root.."codec.lua")
local writer,records,rows={}, {},nil
local w,h=257,17
local bytes=string.rep("\0",w*h*4)
local file=assert(io.tmpfile())
math.randomseed(1729)
local function pixel(r,g,b,a) return string.char(r,g,b,a) end
for i=1,300 do
  if i==151 then w,h=129,23; bytes=string.rep("\0",w*h*4) end
  for j=1, i%11+1 do
    local pos=math.random(w*h)*4-3
    bytes=bytes:sub(1,pos-1)..pixel(math.random(255),math.random(255),math.random(255),math.random(255))..bytes:sub(pos+4)
  end
  if i%29==0 then bytes=string.rep(pixel(12,23,34,255),w*h) end
  local packed,ref=C.encode(writer,{width=w,height=h,bytes=bytes},i%120==1)
  local offset=assert(file:seek("end"));assert(file:write(packed));assert(file:flush())
  local record={offset=offset,length=#packed,w=w,h=h,ref=ref}
  rows=C.decode(file,record,rows)
  assert(table.concat(rows)==bytes,"Lossless round trip failed at "..i)
  records[i]={record=record,expected=bytes}
end
for _,id in ipairs({1,120,121,150,151,250,300,7}) do
  local base=id
  while not records[base].record.ref do base=base-1 end
  local decoded
  for n=base,id do decoded=C.decode(file,records[n].record,decoded) end
  assert(table.concat(decoded)==records[id].expected,"Random seek mismatch")
end
file:close()
-- A detailed row with two far-apart changes: the unchanged middle should not be copied.
local row={};for i=1,512 do row[i]=pixel(i%251,i//251,i%101,255) end
local base=table.concat(row);writer={}
C.encode(writer,{width=512,height=1,bytes=base},true)
row[2],row[511]=pixel(9,8,7,255),pixel(6,5,4,255)
local delta,ref=C.encode(writer,{width=512,height=1,bytes=table.concat(row)},false)
assert(not ref and #delta<64,"Sparse row was not split: "..#delta)
print("SPARSE_DELTA_BYTES",#delta)
app={fs={joinPath=function(...) return table.concat({...},"/") end,filePath=function(path) return path:match("^(.*)/[^/]+$") end}}
local E=dofile(root.."export.lua")
local frames={};for i=1,13777 do frames[i]=i end
for _,n in ipairs({2,450,900,1800}) do
  local sampled=E.sampleCount(frames,n)
  assert(#sampled==n and sampled[1]==1 and sampled[n]==#frames)
  for i=2,#sampled do assert(sampled[i]>sampled[i-1]) end
end
local g=E.layout({captureWidth=128,captureHeight=128},{scale=4,preset="Vertical 1080p",ratio="",format="MP4"})
assert(g.outWidth==1080 and g.outHeight==1920 and g.width==1024 and g.x==28 and g.y==448)
local S=dofile(root.."store.lua")
local session={info={},editRevision=0,boundaries={{id=5,dx=2,dy=-3},{id=8,dx=-1,dy=5}}}
local function offset(id,x,y) local a,b=S.offset(session,id);assert(a==x and b==y) end
offset(1,1,2);offset(5,-1,5);offset(8,0,0)
session.boundaries[2].dy=7;session.editRevision=1;offset(1,1,4)
print("ASELAPS_CODEC_PURE_OK")
