-- Each record replaces spans of RGBA pixels. Reference records start from zero.
-- A negative run length repeats a pixel, a positive length copies literal pixels.
local Codec = {}
local function encodeSpan(row, first, last)
  local chunks, literal = {}, first
  local p = first
  while p <= last do
    local pixel = row:sub(p,p+3)
    local stop = p+4
    while stop <= last and row:sub(stop,stop+3)==pixel and stop-p<32767*4 do stop=stop+4 end
    if stop-p>=12 then
      if literal<p then chunks[#chunks+1]=string.pack("<i2",(p-literal)//4)..row:sub(literal,p-1) end
      chunks[#chunks+1]=string.pack("<i2",-(stop-p)//4)..pixel
      literal=stop
    end
    p=stop
    if p-literal>=32000*4 then
      chunks[#chunks+1]=string.pack("<i2",(p-literal)//4)..row:sub(literal,p-1)
      literal=p
    end
  end
  if literal<=last then chunks[#chunks+1]=string.pack("<i2",(last-literal+1)//4)..row:sub(literal,last) end
  return table.concat(chunks)
end
local function span(row, before, y, width)
  if row==before then return "" end
  local a,b=1,#row
  while row:sub(a,a+3)==before:sub(a,a+3) do a=a+4 end
  while row:sub(b-3,b)==before:sub(b-3,b) do b=b-4 end
  local encoded=encodeSpan(row,a,b)
  return string.pack("<I4I4",y*width+(a-1)//4,#encoded)..encoded
end
function Codec.encode(session,image,force)
  local w,h=image.width,image.height
  local bytes=image.bytes
  local old=session.writer
  if not old or w~=old.w or h~=old.h then force=true; old=nil end
  local blank=string.rep("\0",w*4)
  local full,delta={},{}
  local size=0
  for y=0,h-1 do
    local row=bytes:sub(y*w*4+1,(y+1)*w*4)
    local prev=old and old.bytes:sub(y*w*4+1,(y+1)*w*4)
    if row==prev then full[y+1]=old.full[y+1]
    else
      full[y+1]=span(row,blank,y,w)
      if not force then delta[#delta+1]=span(row,prev,y,w) end
    end
    size=size+#full[y+1]
  end
  local patch=table.concat(delta)
  local ref=force or size<=#patch
  session.writer={w=w,h=h,bytes=bytes,full=full}
  return ref and table.concat(full) or patch, ref
end
function Codec.decode(file, record, rows)
  assert(file:seek("set",record.offset))
  local data=record.length==0 and "" or assert(file:read(record.length))
  assert(#data==record.length,"Incomplete frame record.")
  local w,h=record.w,record.h
  if record.ref then
    rows={}
    local blank=string.rep("\0",w*4)
    for y=1,h do rows[y]=blank end
  end
  local p=1
  while p<=#data do
    local pos,length
    pos,length,p=string.unpack("<I4I4",data,p)
    local stop=p+length
    local parts={}
    while p<stop do
      local n
      n,p=string.unpack("<i2",data,p)
      if n<0 then parts[#parts+1]=data:sub(p,p+3):rep(-n); p=p+4
      else parts[#parts+1]=data:sub(p,p+n*4-1); p=p+n*4 end
    end
    assert(p==stop)
    local y,x=pos//w+1,(pos%w)*4
    local row=assert(rows[y])
    local changed=table.concat(parts)
    assert(x+#changed<=#row)
    rows[y]=row:sub(1,x)..changed..row:sub(x+#changed+1)
  end
  return rows
end
-- Compare overlapping rows for ordinary resizes. Larger searches are left for review.
function Codec.align(old,new)
  local dw,dh=new.width-old.width,new.height-old.height
  if (math.abs(dw)+1)*(math.abs(dh)+1)*math.min(old.height,new.height)>200000 then return 0,0,true end
  local a,b=old.bytes,new.bytes
  local w,h=math.min(old.width,new.width),math.min(old.height,new.height)
  local best,dx,dy,tie=-1,0,0,false
  for y=math.min(0,dh),math.max(0,dh) do
    for x=math.min(0,dw),math.max(0,dw) do
      local score=0
      for r=0,h-1 do
        local i=((r+math.max(0,-y))*old.width+math.max(0,-x))*4
        local j=((r+math.max(0,y))*new.width+math.max(0,x))*4
        if a:sub(i+1,i+w*4)==b:sub(j+1,j+w*4) then score=score+1 end
      end
      if score>best then best,dx,dy,tie=score,x,y,false
      elseif score==best then tie=true end
    end
  end
  return dx,dy,tie or best<h
end
return Codec
