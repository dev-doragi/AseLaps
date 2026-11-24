local fs = app.fs
local join = fs.joinPath
local Export = { defaultStep=10 }
local launcher = join(fs.filePath(debug.getinfo(1, "S").source:sub(2)), "AseLaps.cmd")

function Export.encoderPath(remembered)
  local default = join(assert(os.getenv("USERPROFILE")), "Projects", "AseLaps", "tools", "ffmpeg", "ffmpeg.exe")
  if remembered and fs.isFile(remembered) then return remembered end
  if fs.isFile(default) then return default end
  return remembered or ""
end

local function integer(value, minimum, maximum, label)
  local number = math.tointeger(tonumber(value))
  assert(number and number >= minimum and number <= maximum,
    string.format("%s must be an integer between %d and %d.", label, minimum, maximum))
  return number
end

function Export.layout(info, options)
  local scale = integer(options.scale, 1, 16, "Pixel scale")
  local width, height = info.captureWidth * scale, info.captureHeight * scale
  local outWidth, outHeight = width, height
  local ratio = options.ratio:match("^%s*(.-)%s*$")
  if ratio ~= "" then
    local horizontal, vertical = ratio:match("^(%d+):(%d+)$")
    horizontal = integer(horizontal, 1, 8192, "Aspect ratio width")
    vertical = integer(vertical, 1, 8192, "Aspect ratio height")
    local a, b = horizontal, vertical
    while b ~= 0 do a, b = b, a % b end
    horizontal, vertical = horizontal // a, vertical // a
    local units = math.max(math.ceil(width / horizontal), math.ceil(height / vertical))
    if options.format == "MP4" then units = units + units % 2 end
    outWidth, outHeight = units * horizontal, units * vertical
  elseif options.format == "MP4" then
    outWidth = outWidth + outWidth % 2
    outHeight = outHeight + outHeight % 2
  end
  assert(outWidth <= 8192 and outHeight <= 8192, "Output exceeds 8192 pixels on one side.")
  return {
    width=width, height=height, outWidth=outWidth, outHeight=outHeight,
    x=(outWidth-width)//2, y=(outHeight-height)//2
  }
end

function Export.isAbsolute(path)
  return type(path) == "string" and (path:match("^%a:[/\\]") or path:sub(1, 2) == "\\\\")
end

local function launcherCommand()
  local suffix = "extensions\\AseLaps\\AseLaps.cmd"
  local config = fs.normalizePath(fs.userConfigPath):gsub("[/\\]+$", "")
  local normalized = fs.normalizePath(launcher):lower()
  if normalized == fs.normalizePath(join(config, suffix)):lower() then
    local profile = os.getenv("ASEPRITE_USER_FOLDER")
    if profile and profile ~= "" then return "%ASEPRITE_USER_FOLDER%\\" .. suffix end
    if fs.fileName(config):lower() == "aseprite" and
      config:lower() ~= fs.normalizePath(fs.filePath(fs.appPath)):lower() and os.getenv("APPDATA") then
      return "%APPDATA%\\Aseprite\\" .. suffix
    end
  end
  return launcher
end

local function runHelper(store, action, data, produce)
  assert(fs.isFile(launcher), "AseLaps Windows helper is missing. Reinstall the extension.")
  local folder = store.numberedDirectory(fs.tempPath, "AseLaps-" .. os.time())
  local request = join(folder, "request.json")
  local selection = join(folder, "selection.txt")
  local command = '""' .. launcherCommand() .. '" ' .. action .. " " .. fs.fileName(folder) .. '"'
  local called, ok, code, result = pcall(function()
    store.writeText(request, json.encode(data))
    local success, exitCode
    if produce then
      local pipe=assert(io.popen(command,"wb"))
      local wrote,message=pcall(produce,pipe)
      local reason
      success,reason,exitCode=pipe:close()
      if not wrote then error(message,0) end
    else
      local reason
      success,reason,exitCode=os.execute(command)
    end
    local selected
    if success and action == "browse" and fs.isFile(selection) then
      selected = store.readText(selection)
    end
    return success, exitCode, selected
  end)
  local cleaned, removed = pcall(function()
    return store.remove(selection) and store.remove(request) and fs.removeDirectory(folder)
  end)
  if not cleaned or not removed then print("AseLaps: temporary request remains at " .. folder) end
  if not called then error(ok, 0) end
  return ok, code, result
end

function Export.checkEncoder(store,path)
  assert(Export.isAbsolute(path) and fs.fileName(path):lower()=="ffmpeg.exe" and fs.isFile(path),
    "Locate ffmpeg.exe to export a video.")
  assert(runHelper(store,"check",{executable=path}), "FFmpeg could not start. Locate a working ffmpeg.exe.")
  return true
end

function Export.chooseFolder(store, initial, fallback)
  local ok, _, folder = runHelper(store, "browse", {initial=initial, fallback=fallback})
  assert(ok, "Could not open the Windows folder picker.")
  return folder
end

function Export.openFolder(store, path)
  assert(fs.isDirectory(path), "Folder does not exist: " .. path)
  assert(runHelper(store, "open", {path=path}), "Could not open folder.")
end

local function fill(color)
  if color == "Black" then return app.pixelColor.rgba(0, 0, 0, 255) end
  if color == "White" then return app.pixelColor.rgba(255, 255, 255, 255) end
  return 0
end

local function pngSequence(store, session, frames, folder, geometry, options)
  local color = fill(options.background)
  local last
  for i, id in ipairs(frames) do
    local source = store.snapshotPath(session, id)
    local path = join(folder, string.format("%s_%06d.png", options.sequencePrefix or "frame", i))
    local image = store.loadSnapshot(session, id)
    if geometry.outWidth == session.info.captureWidth
      and geometry.outHeight == session.info.captureHeight and color == 0 then
      if session.info.version >= 4 or session.info.version == 2 then store.writeImage(image, path)
      else store.copy(source, path) end
    else
      if image.width ~= geometry.width or image.height ~= geometry.height then
        image:resize(geometry.width, geometry.height)
      end
      local canvas = Image(geometry.outWidth, geometry.outHeight, ColorMode.RGB)
      canvas:clear(color)
      canvas:drawImage(image, Point(geometry.x, geometry.y))
      store.writeImage(canvas, path)
    end
    last = path
  end
  for i = 1, options.holdFrames do
    store.copy(last, join(folder, string.format("%s_%06d.png", options.sequencePrefix or "frame", #frames + i)))
  end
  return folder
end

local function encode(store, session, frames, folder, geometry, options)
  local transparent = options.background == "Transparent"
  local ext = options.format:lower()
  local pending = join(folder, "timelapse.pending." .. ext)
  local output = join(folder, "timelapse." .. ext)
  local log = join(folder, "ffmpeg.log")
  local ok, err = pcall(function()
    local args = {"-hide_banner", "-nostdin", "-n", "-loglevel", "warning", "-xerror"}
    local function add(...)
      for _, value in ipairs({...}) do args[#args + 1] = value end
    end
    add("-f", "rawvideo", "-pixel_format", "rgba", "-video_size",
      string.format("%dx%d", session.info.captureWidth, session.info.captureHeight),
      "-framerate", tostring(options.fps), "-i", "pipe:0")

    -- Use one timestamp per selected frame, including repeated Undo/Redo images.
    local filters = string.format(
      "[0:v]settb=1/%d,setpts=N,format=rgba,scale=%d:%d:flags=neighbor",
      options.fps, geometry.width, geometry.height)
    if transparent then
      filters = filters .. string.format(",pad=%d:%d:%d:%d:color=black@0",
        geometry.outWidth, geometry.outHeight, geometry.x, geometry.y)
    else
      local color = options.background == "Black" and "black" or "white"
      filters = filters .. string.format(
        "[art];color=c=%s:s=%dx%d:r=%d,format=rgba[bg];[bg][art]overlay=x=%d:y=%d:format=rgb:shortest=1",
        color, geometry.outWidth, geometry.outHeight, options.fps, geometry.x, geometry.y)
    end
    if options.holdFrames > 0 then
      filters = filters .. string.format(",tpad=stop_mode=clone:stop=%d", options.holdFrames)
    end
    if ext == "gif" then
      filters = filters .. ",split[a][b];[a]palettegen=reserve_transparent=" ..
        (transparent and "1" or "0") .. "[p];[b][p]paletteuse=dither=none"
    end
    add("-filter_complex_threads", "1", "-filter_complex", filters .. "[out]", "-map", "[out]")
    if ext == "mp4" then
      add("-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart")
    else
      add("-loop", "0")
      -- Full frames keep isolated opaque pixels after an entirely transparent frame.
      if transparent then add("-gifflags", "-offsetting-transdiff") end
    end
    add(pending)
    local success, code = runHelper(store, "export", {
      executable=options.ffmpeg, arguments=args, log=log, stream=true
    },function(pipe)
      for _,id in ipairs(frames) do
        local image=store.loadSnapshot(session,id)
        assert(image.width==session.info.captureWidth and image.height==session.info.captureHeight,
          "Edited frame dimensions differ from the output canvas.")
        assert(pipe:write(image.bytes))
      end
    end)
    assert(success, string.format("FFmpeg failed (%s). Log: %s", tostring(code), log))
    assert(fs.isFile(pending) and fs.fileSize(pending) > 0, "No video produced. Log: " .. log)
    store.move(pending, output)
  end)
  local function remove(path)
    local succeeded, removed = pcall(store.remove, path)
    if not succeeded or not removed then
      print("AseLaps: temporary export data could not be removed: " .. path)
    end
  end
  if not ok then
    remove(pending)
    error(err, 0)
  end
  return output
end

local function sample(frames, step)
  if step == 1 then return frames end
  local result = {}
  for i = 1, #frames, step do result[#result + 1] = frames[i] end
  return result
end

function Export.run(store, session, input)
  assert(session.info.version == 1 or input.mode == "Full", "Sampled sessions support Full history only.")
  local options = {
    format=input.format, background=input.background, ratio=input.ratio, sequencePrefix=input.sequencePrefix,
    scale=input.scale, ffmpeg=input.ffmpeg, fps=integer(input.fps, 1, 60, "FPS")
  }
  local step = integer(input.step or Export.defaultStep, 1, 1000, "Frame interval")
  assert(options.format == "MP4" or options.format == "GIF" or options.format == "PNG sequence",
    "Select an output format.")
  local hold = tonumber(input.hold)
  assert(hold and hold >= 0 and hold <= 60, "Final hold must be between 0 and 60 seconds.")
  options.holdFrames = math.floor(hold * options.fps + 0.5)
  if options.format ~= "PNG sequence" then
    assert(Export.isAbsolute(options.ffmpeg) and fs.fileName(options.ffmpeg):lower() == "ffmpeg.exe"
      and fs.isFile(options.ffmpeg), "Select an installed ffmpeg.exe in Settings.")
  end
  assert(options.format ~= "MP4" or options.background ~= "Transparent",
    "Choose an opaque background for MP4.")
  local geometry = Export.layout(session.info, options)
  local modes = input.mode == "Both" and {"Full", "Clean"} or {input.mode}
  local sequences = {}
  for _, mode in ipairs(modes) do
    assert(mode == "Full" or mode == "Clean", "Select a history mode.")
    if input.sequences and input.sequences[mode] then
      sequences[mode]=input.sequences[mode]
    else
      local frames,missing=store.timeline(session,mode,input.head)
      assert(#missing==0 or input.skipMissing,"Missing frames found. Review and confirm skipping them.")
      sequences[mode]=sample(frames,step)
    end
    assert(#sequences[mode]>0,"There are no output frames in "..mode.." History.")
  end
  local destination = input.folder or (input.output and fs.filePath(input.output))
  if destination == "" then destination = join(session.project.folder, "exports") end
  assert(Export.isAbsolute(destination), "Enter an absolute Windows output folder.")
  local outputs = {}
  for _, mode in ipairs(modes) do
    local folder
    if input.sequenceFolder then
      folder=input.sequenceFolder
      if #modes>1 then folder=folder .. "_" .. mode end
      assert(not fs.isDirectory(folder),"PNG sequence folder already exists.")
      store.ensureDirectory(folder)
    else folder = store.numberedDirectory(destination, "AseLaps_" .. mode .. "_" .. session.name) end
    if options.format == "PNG sequence" then
      outputs[#outputs + 1] = pngSequence(store, session, sequences[mode], folder, geometry, options)
    else
      local encoded = encode(store, session, sequences[mode], folder, geometry, options)
      if input.output then
        local target = input.output
        if #modes > 1 then target = target:gsub("(%.[^.]+)$", "_" .. mode .. "%1") end
        if fs.isFile(target) then
          assert(input.overwrite, "Output already exists.")
          -- Keep the previous video until encoding has completed successfully.
          local backup = target .. ".backup-" .. os.time()
          assert(not fs.isFile(backup), "Output backup already exists.")
          store.move(target, backup)
          local moved, message = pcall(store.move, encoded, target)
          if not moved then store.move(backup, target); error(message) end
          assert(store.remove(backup))
        else store.move(encoded,target) end
        outputs[#outputs+1] = target
      else outputs[#outputs+1] = encoded end
    end
  end
  return outputs
end

Export.sample = sample
return Export
