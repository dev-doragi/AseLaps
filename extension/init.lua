local recorder, timer, ui

function init(plugin)
  plugin:newCommand{
    id="AseLapsOpen", title="AseLaps", group="file_scripts",
    onclick=function()
      if ui then
        ui:show()
      else
        app.alert("AseLaps requires Windows and Aseprite 1.3.18.6 or later.")
      end
    end
  }
  if not app.isUIAvailable or not app.os.windows or (app.apiVersion or 0) < 39 or app.version<Version("1.3.18.6") then return end

  local fs = app.fs
  local function load(name) return dofile(fs.joinPath(plugin.path, name .. ".lua")) end
  local History = load("history")
  local Store = load("store")
  local Recorder = load("recorder")
  local Export = load("export")
  local Ui = load("ui")
  local prefs=plugin.preferences
  if not prefs.recordingFolder and (prefs.sessionsBySource or prefs.lastRecordingFolder) then
    prefs.recordingFolder=prefs.lastRecordingFolder or fs.joinPath(os.getenv("USERPROFILE"),"Downloads","IncreParty_Illust")
  end
  local store = Store.new(fs.joinPath(fs.userConfigPath, "AseLaps"), History,prefs)
  local warning
  recorder = Recorder.new(store, History, plugin.preferences, function(message)
    warning = message
    print("AseLaps: " .. message)
  end)
  ui = Ui.new(recorder, Export, plugin.preferences)
  recorder:watch()
  timer = Timer{ interval=0.25, ontick=function()
    recorder:tick()
    if warning then
      ui.notice, warning = warning, nil
      app.alert{ title="AseLaps", text=ui.notice }
    end
    ui:refresh()
  end }
  timer:start()
end

function exit()
  if timer then timer:stop() end
  if ui and ui.main then ui.main:close() end
  if recorder then recorder:shutdown() end
  recorder, timer, ui = nil, nil, nil
end
