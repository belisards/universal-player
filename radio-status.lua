local mp = require("mp")
local utils = require("mp.utils")

local status_path = os.getenv("RADIO_ATLAS_STATUS_FILE")
local queue_path = os.getenv("RADIO_ATLAS_QUEUE_FILE")
local queue = nil
local update_timer = nil
local last_volume = 70
local last_output = ""
local station_loaded = false
local station_position = -1
local failure = nil
local max_queue_bytes = 4194304

local function clean_text(value, limit)
  if type(value) ~= "string" then return "" end
  value = value:gsub("[%c]", " "):gsub("  +", " ")
  if #value <= limit then return value end
  local last = limit
  while last > 0 do
    local next_byte = value:byte(last + 1)
    if not next_byte or next_byte < 128 or next_byte > 191 then break end
    last = last - 1
  end
  return value:sub(1, last)
end

local function clean_output(value)
  if type(value) ~= "string" then return "" end
  if value == "auto" then return "" end
  value = value:gsub("^pipewire/", "")
  return value:sub(1, 160)
end

local function empty_station()
  return { uuid = "", name = "", kind = "", provider = "", source = "",
    title = "", artist = "", album = "", albumKey = "", year = "",
    favicon = "", country = "", countryCode = "" }
end

local function status_station(station)
  if type(station) ~= "table" then return empty_station() end
  local latitude = type(station.latitude) == "number" and station.latitude or nil
  local longitude = type(station.longitude) == "number" and station.longitude or nil
  return {
    uuid = clean_text(station.uuid, 64),
    name = clean_text(station.name, 160),
    kind = clean_text(station.kind, 24),
    provider = clean_text(station.provider, 40),
    source = clean_text(station.source, 40),
    title = clean_text(station.title, 160),
    artist = clean_text(station.artist, 160),
    album = clean_text(station.album, 160),
    albumKey = clean_text(station.albumKey, 64),
    year = clean_text(station.year, 16),
    favicon = clean_text(station.favicon, 2048),
    country = clean_text(station.country, 100),
    countryCode = clean_text(station.countryCode, 2),
    latitude = latitude,
    longitude = longitude
  }
end

local function read_queue()
  if queue then return queue end
  queue = {}
  if not queue_path then return queue end

  local file = io.open(queue_path, "r")
  if not file then return queue end
  local size = file:seek("end")
  if not size or size > max_queue_bytes then
    file:close()
    return queue
  end
  file:seek("set", 0)
  local parsed = utils.parse_json(file:read("*a"))
  file:close()
  if type(parsed) == "table" and #parsed <= 500 then queue = parsed end
  return queue
end

local function write_status(state)
  if not status_path then return end
  local temporary = status_path .. "." .. tostring(mp.get_property_number("pid", 0)) .. ".tmp"
  local file = io.open(temporary, "w")
  if not file then return end
  file:write(utils.format_json(state), "\n")
  file:close()
  os.rename(temporary, status_path)
end

local function current_status()
  local position = failure and failure.position or mp.get_property_number("playlist-pos", -1)
  local volume = mp.get_property_number("volume", last_volume)
  last_volume = math.floor(volume + 0.5)
  last_output = clean_output(mp.get_property("audio-device", ""))
  return {
    running = true,
    paused = failure ~= nil or mp.get_property_bool("pause", false),
    muted = mp.get_property_bool("mute", false),
    title = clean_text(mp.get_property("media-title", ""), 512),
    playlistPosition = position,
    playlistCount = mp.get_property_number("playlist-count", 0),
    volume = last_volume,
    output = last_output,
    loaded = station_loaded,
    error = failure and failure.message or "",
    errorDetail = failure and failure.detail or "",
    station = status_station(read_queue()[position + 1])
  }
end

local function emit_status()
  update_timer = nil
  write_status(current_status())
end

local function schedule_update()
  if update_timer then update_timer:kill() end
  update_timer = mp.add_timeout(0.04, emit_status)
end

for _, property in ipairs({
  "pause", "mute", "media-title", "playlist-pos", "playlist-count", "volume", "audio-device"
}) do
  mp.observe_property(property, "native", schedule_update)
end

mp.register_event("start-file", function()
  station_loaded = false
  station_position = mp.get_property_number("playlist-pos", -1)
  failure = nil
  mp.set_property_native("user-data/radio-atlas-failure", nil)
  schedule_update()
end)
-- TV channels need video and their own request headers; radio stays audio-only.
mp.add_hook("on_load", 50, function()
  local position = mp.get_property_number("playlist-pos", -1) + 1
  local path = mp.get_property("path")
  local entry = read_queue()[position]
  if type(entry) ~= "table" or entry.url ~= path then
    -- A replaced playlist can load before its reload message arrives.
    queue = nil
    entry = read_queue()[position]
  end
  if type(entry) ~= "table" or entry.kind ~= "tv" or entry.url ~= path then return end
  mp.set_property("file-local-options/vid", "auto")
  mp.set_property("file-local-options/sid", "no")
  mp.set_property("file-local-options/demuxer-max-bytes", "64MiB")
  local user_agent = clean_text(entry.userAgent, 512)
  if user_agent ~= "" then mp.set_property("file-local-options/user-agent", user_agent) end
  local referrer = clean_text(entry.referrer, 2048)
  if referrer ~= "" then mp.set_property("file-local-options/referrer", referrer) end
end)
mp.register_event("file-loaded", function()
  station_loaded = true
  schedule_update()
end)
mp.register_event("end-file", function(event)
  local entry = read_queue()[station_position + 1]
  local finished_track = event.reason == "eof" and station_loaded
    and type(entry) == "table" and entry.kind == "track"
  if not finished_track and (event.reason == "eof" or event.reason == "error") then
    failure = {
      position = station_position,
      message = station_loaded and "Stream disconnected" or "Station could not be played",
      detail = clean_text(event.error, 200)
    }
    mp.set_property_native("user-data/radio-atlas-failure", failure)
  end
  station_loaded = false
  schedule_update()
end)
-- A hook blocks mpv from opening the next queued station before we stop it.
mp.add_hook("on_after_end_file", 50, function()
  if failure then mp.commandv("stop", "keep-playlist") end
end)
mp.register_event("idle", function()
  station_loaded = false
  -- Retain native Next/Previous navigation without reopening the failed stream.
  if failure then mp.set_property_number("playlist-current-pos", failure.position) end
  schedule_update()
end)
mp.register_script_message("radio-atlas-reload", function()
  queue = nil
  schedule_update()
end)
mp.register_script_message("radio-atlas-toggle", function()
  if failure then
    if failure.position < 0 then return end
    mp.commandv("playlist-play-index", failure.position)
    mp.set_property_bool("pause", false)
    return
  end
  mp.commandv("cycle", "pause")
end)
mp.register_event("shutdown", function()
  if update_timer then update_timer:kill() end
  write_status({
    running = false,
    paused = false,
    muted = false,
    title = "",
    playlistPosition = -1,
    playlistCount = 0,
    volume = last_volume,
    output = last_output,
    loaded = false,
    station = empty_station()
  })
end)

schedule_update()
