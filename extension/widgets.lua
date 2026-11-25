local Widgets={}

local icons={
  record={"01110","11111","11111","11111","01110"},
  pause={"11011","11011","11011","11011","11011"},
  play={"10000","11100","11111","11100","10000"},
  stop={"11111","11111","11111","11111","11111"}
}

function Widgets.icon(ctx,name)
  ctx.color=name=="record" and Color{r=240,g=83,b=91} or Color{r=140,g=158,b=173}
  for y,row in ipairs(icons[name]) do
    for x=1,#row do
      if row:sub(x,x)=="1" then ctx:fillRect(Rectangle((x-1)*2,(y-1)*2,2,2)) end
    end
  end
end

function Widgets.thumbnail(ctx,image)
  if not image then return end
  local scale=math.min(ctx.width/image.width,ctx.height/image.height)
  local w,h=math.max(1,math.floor(image.width*scale)),math.max(1,math.floor(image.height*scale))
  ctx:drawImage(image,image.bounds,Rectangle((ctx.width-w)//2,(ctx.height-h)//2,w,h))
end

function Widgets.timeline(dlg,state,onScrub,onRange)
  local width=1
  local dragging,anchor,last
  local function pixel(position,count)
    return math.floor((position-1)*math.max(0,width-1)/math.max(1,count-1)+0.5)
  end
  local function position(x,count)
    return 1+math.floor(math.max(0,math.min(1,x/math.max(1,width-1)))*(count-1)+0.5)
  end
  local function drag(ev)
    if not dragging then return end
    local _,_,rangeCount=state()
    if rangeCount<1 then return end
    local current=position(ev.x,rangeCount)
    if current==last then return end
    last=current
    if anchor then onRange(math.min(anchor,current),math.max(anchor,current))
    else onScrub(current) end
  end
  dlg:canvas{id="timeline",width=360,height=18,hexpand=true,vexpand=false,
    onpaint=function(ev)
      local ctx=ev.context
      width=ctx.width
      local count,frame,rangeCount,first,final=state()
      ctx.color=Color{r=55,g=61,b=73}
      ctx:fillRect(Rectangle(0,4,width,10))
      if rangeCount>0 then
        local left,right=pixel(first,rangeCount),pixel(final,rangeCount)
        ctx.color=Color{r=74,g=117,b=149}
        ctx:fillRect(Rectangle(left,5,math.max(1,right-left+1),8))
      end
      if count>0 then
        ctx.color=Color{r=246,g=213,b=132}
        ctx:fillRect(Rectangle(pixel(frame,rangeCount),1,2,16))
      end
    end,
    onmousedown=function(ev)
      if ev.button~=MouseButton.LEFT then return end
      local count,_,rangeCount=state()
      if (ev.shiftKey and rangeCount<1) or (not ev.shiftKey and count<1) then return end
      dragging,last=true,nil
      anchor=ev.shiftKey and position(ev.x,rangeCount) or nil
      drag(ev)
    end,
    onmousemove=drag,
    onmouseup=function(ev)
      if ev.button~=MouseButton.LEFT then return end
      drag(ev)
      dragging,anchor,last=false,nil,nil
    end}
end

return Widgets
