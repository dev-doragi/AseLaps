local fs = app.fs
local work = assert(app.params.work)
local path = fs.joinPath(work, "한글 test")
assert(fs.isDirectory(path) or fs.makeAllDirectories(path))
local first = fs.joinPath(path, "write.tmp")
local second = fs.joinPath(path, "write.txt")
local file = assert(io.open(first, "wb"))
assert(file:write("test"))
assert(file:close())
if fs.isFile(second) then assert(os.remove(second)) end
assert(os.rename(first, second))
assert(fs.isFile(second))

local sprite = Sprite(8, 8)
local layer = sprite.layers[1]
local red = app.pixelColor.rgba(255, 0, 0, 255)
local blue = app.pixelColor.rgba(0, 0, 255, 255)
local function render(frame)
  local image = Image(8, 8, ColorMode.RGB)
  image:drawSprite(sprite, frame)
  return image
end
local function observe(event)
  local steps = sprite.undoHistory
  print(string.format("change undo=%s steps=%d/%d frame=%d pixel=%x",
    tostring(event.fromUndo), steps.undoSteps, steps.redoSteps,
    app.frame.frameNumber, render(app.frame.frameNumber):getPixel(1, 1)))
end
sprite.events:on("change", observe)
for _, event in ipairs({ "layervisibility", "layeropacity", "layerblendmode" }) do
  local label = event
  sprite.events:on(label, function() print(label) end)
end
app.events:on("sitechange", function()
  print("site " .. tostring(app.frame and app.frame.frameNumber))
end)
app.useTool{ tool="pencil", color=Color{ r=255, a=255 }, points={Point(1, 1)}, layer=layer }
assert(render(1):getPixel(1, 1) == red)
app.undo()
assert(render(1):getPixel(1, 1) == 0)
app.redo()
assert(render(1):getPixel(1, 1) == red)
layer.isVisible = false
assert(render(1):getPixel(1, 1) == 0)
layer.isVisible = true
app.command.NewLayer{ reference=true, name="Reference", ui=false }
local reference = app.layer
assert(reference.isReference)
local referenceImage = Image(8, 8)
referenceImage:clear(blue)
sprite:newCel(reference, 1, referenceImage)
assert(render(1):getPixel(1, 1) == red and render(1):getPixel(0, 0) == 0)

local indexed = Sprite(4, 4, ColorMode.INDEXED)
local palette = Palette(3)
palette:setColor(1, Color{ r=0, g=255, b=0 })
indexed:setPalette(palette)
local indices = Image(4, 4, ColorMode.INDEXED)
indices:drawPixel(0, 0, 1)
indexed:newCel(indexed.layers[1], 1, indices)
local rgba = Image(4, 4, ColorMode.RGB)
rgba:drawSprite(indexed, 1)
assert(rgba:getPixel(0, 0) == app.pixelColor.rgba(0, 255, 0, 255))
assert(rgba:getPixel(1, 1) == 0)
local png = fs.joinPath(path, "indexed.png")
assert(rgba:saveAs(png))
local loaded = assert(Image{ fromFile=png })
assert(loaded:isEqual(rgba))

local grouped = Sprite(8, 8)
local floor = grouped.layers[1]
local group = grouped:newGroup()
floor.parent = group
local overlay = grouped:newLayer()
overlay.parent = group
overlay.blendMode = BlendMode.MULTIPLY
local baseImage = Image(8, 8)
baseImage:clear(red)
grouped:newCel(floor, 1, baseImage)
local overlayImage = Image(8, 8)
overlayImage:clear(blue)
grouped:newCel(overlay, 1, overlayImage)
local blended = Image(8, 8)
blended:drawSprite(grouped, 1)
assert(blended:getPixel(0, 0) == app.pixelColor.rgba(0, 0, 0, 255))
group.isVisible = false
blended:clear()
blended:drawSprite(grouped, 1)
assert(blended:getPixel(0, 0) == 0)
print("PASS group hierarchy and layer blend mode")

app.command.NewLayer{ tilemap=true, gridBounds=Rectangle(0, 0, 4, 4), ui=false }
local tilemap = app.layer
assert(tilemap.isTilemap)
tilemap.parent = grouped
local tile = grouped:newTile(tilemap.tileset)
tile.image:clear(blue)
local tileImage = Image(1, 1, ColorMode.TILEMAP)
tileImage:drawPixel(0, 0, app.pixelColor.tile(tile.index, 0))
grouped:newCel(tilemap, 1, tileImage)
blended:clear()
blended:drawSprite(grouped, 1)
assert(blended:getPixel(0, 0) == blue and blended:getPixel(4, 0) == 0)
print("PASS tilemap composition")
print("ASELAPS_PROBE_OK")
