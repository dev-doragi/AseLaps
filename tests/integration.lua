local fs = app.fs
local join = fs.joinPath
local root = assert(app.params.root)
local work = assert(app.params.work)
local function module(name) return dofile(join(root, "extension", name .. ".lua")) end
local History, Store, Recorder, Export = module("history"), module("store"), module("recorder"), module("export")
assert(loadfile(join(root, "extension", "ui.lua")))
assert(loadfile(join(root, "extension", "init.lua")))
local store = Store.new(join(work, "recordings 한글 O'Brien & percent%"), History)
local warnings = {}
local function warn(message) warnings[#warnings + 1] = message end
local prefs = {}
local recorder = Recorder.new(store, History, prefs, warn)
local red = Color{r=255, g=0, b=0, a=255}
local green = Color{r=0, g=255, b=0, a=255}
local blue = Color{r=0, g=0, b=255, a=255}
local function paint(sprite, x, y, color)
  app.useTool{ tool="pencil", color=color, points={Point(x, y)}, layer=app.layer,
    frame=app.frame, sprite=sprite }
end
local function check(condition, label)
  assert(condition, label)
  print("PASS " .. label)
end
local function eq(sequence, expected)
  assert(sequence, "timeline missing")
  assert(table.concat(sequence, ",") == table.concat(expected, ","),
    table.concat(sequence, ",") .. " != " .. table.concat(expected, ","))
end
local function append(session, bytes)
  local file = assert(io.open(session.journal, "ab"))
  assert(file:write(bytes))
  assert(file:close())
end

Store.ensureDirectory(work)
local sprite = Sprite(208, 304)
local spritePath = join(work, "drawing.aseprite")
sprite:saveAs(spritePath)
local doc = recorder:document(sprite)
recorder:start(doc)
local session = doc.session
local history = session.history
paint(sprite, 1, 1, red)
paint(sprite, 2, 1, green)
local branch = history.head
app.undo()
app.redo()
app.undo()
paint(sprite, 2, 1, blue)
eq(history:timeline("Full"), {1, 2, 3, 2, 3, 2, 4})
eq(history:timeline("Clean"), {1, 2, 4})
eq(history:timeline("Clean", branch), {1, 2, 3})
check(history.count == 4,
  "real pencil edits, Undo/Redo, snapshot reuse, Full/Clean and abandoned branch")
local lastPng = assert(Image{ fromFile=Store.png(session, 4) })
local steps = sprite.undoHistory
check(lastPng:isEqual(Recorder.render(sprite, 1, session.info)) and sprite.isModified
  and sprite.filename == spritePath and sprite.undoHistory.undoSteps == steps.undoSteps
  and sprite.undoHistory.redoSteps == steps.redoSteps, "detached PNG matches edited document")

local before = history.count
sprite:newLayer()
check(history.count == before, "empty layer does not create a snapshot")
local artwork = sprite.layers[1]
artwork.isVisible = false
recorder:tick()
check(history.count == before + 1 and (Image{ fromFile=Store.png(session, before+1) }):isEmpty(),
  "non-transactional visibility change is captured")
artwork.isVisible = true
recorder:tick()
recorder:status(doc, "paused")
local pausedCount = history.count
app.layer = artwork
paint(sprite, 3, 1, red)
assert(history.count == pausedCount)
recorder:resume(doc)
check(history.count == pausedCount + 1 and history.nodes[history.head].label == "Resume gap",
  "pause omits edits and resume records changed baseline")
app.undo()
local unresolved = history.head
assert(history.nodes[unresolved].uncertain and not history:timeline("Clean"))
assert(#history:timeline("Full") > 0)
Store.append(session, {kind="link", node=unresolved, parent=0})
check(history:timeline("Clean") ~= nil, "unknown native state and persistent manual resolution")

recorder:status(doc, "stopped")
local fullFixture = session
local orphan = Store.savePng(session, lastPng)
append(session, '{"id":')
local recovered = store:load(session)
check(recovered.recovered and recovered.history.head == unresolved and recovered.orphans[1] == orphan,
  "torn journal preserves valid prefix and orphan PNG")
local nextId = Store.savePng(recovered, lastPng)
assert(nextId > orphan)
Store.append(recovered, {kind="state", parent=unresolved, png=nextId, frame=1, label="Edit", emit=true})
local replay = store:load(session)
check(replay.history.count == recovered.history.count and replay.history.head == recovered.history.head,
  "new journal generation replays after damaged original")

local lazy = store:create(doc.project, {
  width=208, height=304, captureWidth=208, captureHeight=304
})
Store.append(lazy, {kind="status", status="recording"})
local first = Store.savePng(lazy, lastPng)
Store.append(lazy, {kind="state", parent=0, png=first, frame=1, label="Initial", emit=true})
local last = Store.savePng(lazy, lastPng)
Store.append(lazy, {kind="state", parent=2, png=last, frame=1, label="Edit", emit=true})
Store.append(lazy, {kind="status", status="stopped"})
Store.writeImage(Image(1, 1), Store.png(lazy, first))
local loaded = store:load(lazy)
check(loaded.history.count == 2 and not loaded.recovered and
  not pcall(Store.loadSnapshot, loaded, first) and Store.loadSnapshot(loaded, last):isEqual(lastPng),
  "session opens without decoding older PNGs and validates them on access")

Store.writeImage(lastPng, Store.png(lazy, first))
Store.append(lazy, {kind="status", status="recording"})
local damagedPath = Store.png(lazy, last)
local pngFile = assert(io.open(damagedPath, "rb"))
local pngHeader = assert(pngFile:read(24))
assert(pngFile:close())
Store.writeText(damagedPath, pngHeader)
local truncated = store:load(lazy)
check(truncated.recovered and truncated.history.head == 2 and truncated.history.count == 1
  and truncated.nextPng > last, "interrupted tail without IEND restores the previous snapshot")
assert(Store.remove(damagedPath))
local missing = store:load(lazy)
check(missing.recovered and missing.history.count == 1 and missing.nextPng > last,
  "missing PNG stops journal replay and its ID remains reserved")

local video = {
  folder=join(work, "한글 O'Brien & percent%"), fps=10, scale=4, hold=0.2, step=1,
  ratio="", format="PNG sequence", background="Transparent", mode="Both",
  ffmpeg=app.params.ffmpeg, head=branch
}
local seq = Export.run(store, fullFixture, video)
local cleanFrame = Image{ fromFile=join(seq[2], "frame_000003.png") }
check(cleanFrame.width == 832 and cleanFrame.height == 1216 and
  cleanFrame:getPixel(4, 4) == app.pixelColor.rgba(255, 0, 0, 255) and
  cleanFrame:getPixel(3, 4) == 0 and
  fs.isFile(join(seq[2], "frame_000005.png")) and not fs.isFile(join(seq[2], "frame_000006.png")),
  "PNG Full/Clean, nearest scale and exact hold on special-character path")
local again = Export.run(store, fullFixture, video)
check(seq[2] ~= again[2], "exports reserve new names")
video.mode, video.step, video.hold = "Full", nil, 0
local selected = Export.run(store, fullFixture, video)[1]
local function frame(n)
  return Store.loadImage(join(selected, string.format("frame_%06d.png", n)))
end
local function fullFrame(n)
  return Store.loadImage(join(seq[1], string.format("frame_%06d.png", n)))
end
check(frame(1):isEqual(fullFrame(1)) and frame(2):isEqual(fullFrame(9))
  and frame(3):isEqual(fullFrame(11)) and not fs.isFile(join(selected, "frame_000004.png")),
  "default interval selects first, every eighth offset and final frame")
video.mode, video.step, video.hold = "Both", 1, 0.2
video.format, video.ffmpeg = "MP4", join(work, "missing", "ffmpeg.exe")
assert(not pcall(Export.run, store, fullFixture, video))
check(true, "missing FFmpeg is rejected")
if app.params.ffmpeg then
  local file = assert(io.open(join(work, "media-results.txt"), "wb"))
  for _, format in ipairs({"MP4", "GIF"}) do
    video.format, video.ffmpeg = format, app.params.ffmpeg
    video.background = format == "GIF" and "Transparent" or "White"
    local outputs = Export.run(store, fullFixture, video)
    for _, output in ipairs(outputs) do
      local folder = fs.filePath(output)
      assert(not fs.isDirectory(join(folder, "input")) and not fs.isFile(join(folder, "frames.ffconcat")))
      assert(file:write(output .. "\n"))
    end
    check(#outputs == 2 and fs.isFile(outputs[1]) and fs.isFile(outputs[2]), format .. " Full/Clean encoded")
  end
  assert(file:close())
  local ffprobe = join(fs.filePath(app.params.ffmpeg), "ffprobe.exe")
  if fs.isFile(ffprobe) then
    local invalid = join(work, "failed encoder")
    Store.ensureDirectory(invalid)
    video.format, video.mode = "MP4", "Full"
    video.background = "White"
    video.ffmpeg = join(invalid, "ffmpeg.exe")
    Store.copy(ffprobe, video.ffmpeg)
    local ok, message = pcall(Export.run, store, fullFixture, video)
    local log = tostring(message):match("Log: (.+)")
    check(not ok and log and fs.isFile(log), "nonzero FFmpeg exit reports a retained log")
  end
end

local multiframe = Sprite(19, 17)
multiframe:newEmptyFrame()
app.frame = 1
local multi = recorder:document(multiframe)
recorder:start(multi, {x=1, y=1, w=15, h=15})
paint(multiframe, 1, 1, red)
app.frame = 2
recorder:site()
check(multi.session.history.count == 2, "frame navigation does not capture")
paint(multiframe, 1, 1, green)
assert(multi.session.history.count == 3)
local frameTwo = assert(Image{ fromFile=Store.png(multi.session, 3) })
check(frameTwo.width == 15 and frameTwo.height == 15 and
  frameTwo:getPixel(0, 0) == app.pixelColor.rgba(0, 255, 0, 255),
  "active animation frame and fixed crop")
local layout = Export.layout(multi.session.info, {scale=1, ratio="16:9", format="PNG sequence"})
check(layout.outWidth == 32 and layout.outHeight == 18, "exact aspect ratio is padded without cropping")
if app.params.ffmpeg then
  local odd = Export.run(store, multi.session, {
    folder=join(work, "odd"), fps=10, scale=1, hold=0, ratio="", format="MP4",
    background="White", mode="Clean", step=1, ffmpeg=app.params.ffmpeg
  })
  local file = assert(io.open(join(work, "odd-media.txt"), "wb"))
  assert(file:write(odd[1] .. "\n"))
  assert(file:close())
end
app.undo()
check(not multi.session.history.nodes[multi.session.history.head].uncertain,
  "Undo on an animation frame matches its observed baseline")
local multiFolder = multi.session.folder
multiframe:resize(18, 18)
check(multi.session.folder ~= multiFolder and multi.session.info.width == 18
  and multi.session.info.captureWidth == 15, "canvas resize splits the recording")
assert(#warnings == 1, table.concat(warnings, "\n"))

local stress = Sprite(208, 304)
local stressDoc = recorder:document(stress)
recorder:start(stressDoc)
local started = os.clock()
for i = 1, 1000 do paint(stress, i % 200, i // 200, red) end
for i = 1, 100 do app.undo() end
paint(stress, 207, 303, blue)
local stressSession = stressDoc.session
local stressHistory = stressSession.history
check(stressHistory.count == 1002 and #stressHistory:timeline("Clean") == 902
  and #stressHistory:timeline("Full") == 1102, "1000 captures, Undo 100 times and a new branch")
print(string.format("1000 edits + Undo 100 + branch elapsed %.3fs", os.clock()-started))
check(multi.session.history.count == 1 and history.head == unresolved,
  "open sprites keep independent sessions")

local failure = Sprite(8, 8)
local failureDoc = recorder:document(failure)
recorder:start(failureDoc)
local snapshots = join(failureDoc.session.folder, "snapshots")
local blocked = join(failureDoc.session.folder, "snapshots-blocked")
assert(os.rename(snapshots, blocked))
paint(failure, 1, 1, red)
check(not failureDoc.running and failureDoc.session.faulted and failureDoc.session.history.count == 1,
  "failed PNG write pauses without committing a record")
assert(os.rename(blocked, snapshots))
recorder:resume(failureDoc)
check(failureDoc.running and failureDoc.session.history.count == 2, "retry reloads and records the recovered baseline")
assert(#warnings == 2, table.concat(warnings, "\n"))

local duplicate = Sprite(7, 9)
local duplicateDoc = recorder:document(duplicate)
recorder:start(duplicateDoc)
paint(duplicate, 1, 1, red)
app.useTool{ tool="eraser", brush=Brush(1), points={Point(1, 1)} }
local laterBlank = duplicateDoc.session.history.head
paint(duplicate, 1, 1, blue)
app.undo()
check(duplicateDoc.session.history.head == laterBlank,
  "identical pixels at different native steps resolve to the observed step")
recorder:status(duplicateDoc, "stopped")

local rename = Sprite(7, 9)
rename:saveAs(join(work, "before-rename.aseprite"))
local renameDoc = recorder:document(rename)
recorder:start(renameDoc)
local beforeRename = renameDoc.session
rename:saveAs(join(work, "after-rename.aseprite"))
recorder:tick()
check(renameDoc.running and renameDoc.project.source == Store.source(rename)
  and renameDoc.session.folder ~= beforeRename.folder and beforeRename.history.status == "stopped",
  "Save As preserves the old session and records under the new document")

local resumeSprite = Sprite(7, 9)
local resumePath = join(work, "resume.aseprite")
local resumeDoc = recorder:document(resumeSprite)
recorder:start(resumeDoc)
assert(not resumeDoc.project.source)
paint(resumeSprite, 0, 0, blue)
resumeSprite:saveAs(resumePath)
recorder:tick()
check(resumeDoc.project.source == Store.source(resumeSprite), "first save binds the existing unsaved session")
local resumeFolder = resumeDoc.session.folder
recorder:shutdown()
resumeSprite:close()
local reopen = assert(app.open(resumePath))
recorder:site()
local reopened = recorder.documents[reopen.id]
check(reopened.running and reopened.session.folder == resumeFolder and reopened.session.history.count == 2,
  "reopened saved sprite resumes the same recording without a duplicate PNG")
recorder:shutdown()
print("ASELAPS_INTEGRATION_OK")
