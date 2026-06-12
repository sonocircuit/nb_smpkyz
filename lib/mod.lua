-- smpKey v1.0 - nb player 4 sample instruments - @sonoCircuit

local fs = require 'fileselect'
local tx = require 'textentry'
local mu = require 'musicutil'
local md = require 'core/mods'
local vx = require 'voice'

local preset_path = "/home/we/dust/data/nb_smpkey/smpkey_presets"
local audio_path = "/home/we/dust/audio/"
local current_preset = ""
local is_active = false

local MAX_LENGTH = math.pow(2, 24) -- approx 5.8min @48k (sc phasor resolution)
local MAX_SAMPLES = 36
local MAX_POLY = 6
local NOTE_MIN = 12
local NOTE_MAX = 104

local paramslist = {
  "sample_path", "amp", "pan", "spread", "drive", "noise", "send_a", "send_b",
  "pitchbend", "transpose", "tune", "start", "loop_start", "loop_length", "loop_fade",
  "a_attack", "a_decay", "a_sustain", "a_release", "f_attack", "f_decay", "f_sustain", "f_release",
  "lpf_hz", "lpf_env", "lpf_rz", "hpf_hz", "hpf_env", "hpf_rz",
  "drive_mod", "lpf_hz_mod", "hpf_hz_mod", "send_a_mod", "send_b_mod"
}

local skey = {}
for i = NOTE_MIN, NOTE_MAX do
  skey[i] = {id = 0, rp = 0}
end

local function clear_sample_map()
  for i = NOTE_MIN, NOTE_MAX do
    skey[i].id = 0
    skey[i].rp = 0
  end
end


--------------------------- osc msgs ---------------------------

local function init_smpkey()
  osc.send({ "localhost", 57120 }, "/nb_smpkey/init")
end

local function reset_queue()
  osc.send({ "localhost", 57120 }, "/nb_smpkey/reset_loadqueue")
end

local function load_buffer(i, path)
  osc.send({ "localhost", 57120 }, "/nb_smpkey/load_sample", {i - 1, path})
end

local function clear_buffer()
  osc.send({ "localhost", 57120 }, "/nb_smpkey/clear_buffer")
  clear_sample_map()
end

local function play_voice(vox, note, vel)
  if skey[note].id > 0 then
    local buf = skey[note].id - 1
    local pitch = skey[note].rp
    osc.send({ "localhost", 57120 }, "/nb_smpkey/play", {vox, buf, pitch, vel})
  end
end

local function stop_voice(vox)
  osc.send({ "localhost", 57120 }, "/nb_smpkey/stop", {vox})
end

local function dont_panic()
  osc.send({ "localhost", 57120 }, "/nb_smpkey/panic")
end

local function set_param(key, val)
  osc.send({ "localhost", 57120 }, "/nb_smpkey/set_param", {key, val})
end


--------------------------- utils ---------------------------

local function round_form(param, quant, form)
  return(util.round(param, quant)..form)
end

local function pan_display(param)
  if param < -0.01 then
    return ("L < "..math.abs(util.round(param * 100, 1)))
  elseif param > 0.01 then
    return (math.abs(util.round(param * 100, 1)).." > R")
  else
    return "> <"
  end
end

local function format_freq(freq)
  if freq < 0.1 then
    freq = round_form(freq, 0.001, "Hz")
  elseif freq < 100 then
    freq = round_form(freq, 0.01, "Hz")
  elseif util.round(freq, 1) < 1000 then
    freq = round_form(freq, 1, "Hz")
  else
    freq = round_form(freq / 1000, 0.01, "kHz")
  end
  return freq
end

local function set_loop(key)
  local s = params:get("nb_smpkey_loop_start")
  local l = params:get("nb_smpkey_loop_length")
  if s + l > 1 then
    if key == "start" then
      params:set("nb_smpkey_loop_length", 1 - s)
    elseif key == "length" then
      params:set("nb_smpkey_loop_start", 1 - l)
    end
  end
end

local function bang_params()
  for _, prm in ipairs(paramslist) do
    local p = params:lookup_param("nb_smpkey_"..prm)
    p:bang()
  end
end


--------------------------- file management ---------------------------

local function getfiles(directory)
  local fp = util.scandir(directory)
  local tp = {table.unpack(fp)}
  for i, f in ipairs(tp) do
    if f:match("[/]$") then
      table.remove(fp, tab.key(fp, f))
    end
  end
  return fp, #fp
end

local function build_sample_map(fmap)
  clear_sample_map()
  for note = NOTE_MIN, NOTE_MAX do
    if fmap[note] then
      skey[note].id = fmap[note]
      skey[note].rp = 0
    else
      for note_next = note, NOTE_MAX do
        if fmap[note_next] then
          skey[note].id = fmap[note_next]
          skey[note].rp = note - note_next
          break
        end
      end
    end
    if skey[note].id == 0 then
      for note_prev = NOTE_MAX, NOTE_MIN, -1 do
        if fmap[note_prev] then
          skey[note].id = fmap[note_prev]
          skey[note].rp = note - note_prev
          break
        end
      end
    end
  end
end

local function load_collection(path)
  if is_active and (path ~= "cancel" and path ~= "" and path ~= _path.audio) then
    local directory = path:match("(.*[/])")
    local flist, fnum = getfiles(directory)
    local fmap = {}
    if fnum <= MAX_SAMPLES then
      for buf_id, fname in ipairs(flist) do
        local fpath = directory..fname
        local midi = tonumber(string.match(fname, "^(%d+)"))
        local ch, samples = audio.file_info(fpath)
        if midi >= NOTE_MIN and midi <= NOTE_MAX then
          if ch > 0 and ch < 3 and samples > 1 then
            if samples < MAX_LENGTH then
              if fmap[midi] == nil then
                fmap[midi] = buf_id
                load_buffer(buf_id, fpath)
              end
            else
              print("max length exceeded: "..fpath)
            end
          else
            print("file not supported: "..fpath)
          end
        else
          print("midi note out of bounds", fname)
        end
      end
      build_sample_map(fmap)
      params:set("nb_smpkey_sample_path", path)
    else
      print("!! max 36 samples allowed !!")
    end
  end
end

local function alloc_buffers()
  reset_queue()
  load_collection(params:get("nb_smpkey_sample_path"))
end


--------------------------- save and load ---------------------------

local function save_preset(txt)
  if txt then
    local preset = {}
    for _, v in pairs(paramslist) do
      preset[v] = params:get("nb_smpkey_"..v)
    end
    clock.run(function()
      clock.sleep(0.2)
      tab.save(preset, preset_path.."/"..txt..".smk")
      current_preset = txt
      print("saved smpKey: "..txt)
    end)
  end
end

local function load_preset(path)
  if path ~= "cancel" and path ~= "" and path ~= preset_path then
    dont_panic()
    if path:match("^.+(%..+)$") == ".smk" then
      local preset = tab.load(path)
      if preset ~= nil then
        for _, v in pairs(paramslist) do
          params:set("nb_smpkey_"..v, preset[v])
        end
        alloc_buffers()
        current_preset = path:match("[^/]*$"):gsub(".smk", "")
        print("loaded smpKey: "..current_preset)
      else
        print("error: smpKey file not found", path)
      end
    else
      print("error: not a smpKey file")
    end
  end
end


--------------------------- params ---------------------------

local function add_smpkey_params()
  params:add_group("nb_smpkey_group", "smpkey", 49)
  params:hide("nb_smpkey_group")

  params:add_separator("nb_smpkey_presets", "presets")

  params:add_trigger("nb_smpkey_load", ">> load")
  params:set_action("nb_smpkey_load", function() fs.enter(preset_path, load_preset) end)

  params:add_trigger("nb_smpkey_save", "<< save")
  params:set_action("nb_smpkey_save", function() tx.enter(save_preset, current_preset) end)

  params:add_separator("nb_smpkey_samples", "samples")

  params:add_trigger("nb_smpkey_load_samples", "load samples")
  params:set_action("nb_smpkey_load_samples", function() fs.enter(audio_path, load_collection) end)

  params:add_text("nb_smpkey_sample_path", "path", audio_path)
  params:hide("nb_smpkey_sample_path")

  params:add_trigger("nb_smpkey_clear_samples", "clear samples")
  params:set_action("nb_smpkey_clear_samples", function() clear_buffer() end)

  params:add_separator("nb_smpkey_voice", "smpKey voice")

  params:add_control("nb_smpkey_amp", "level", controlspec.new(0, 2, "lin", 0, 1), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_amp", function(val) set_param('amp', val) end)

  params:add_control("nb_smpkey_pan", "pan", controlspec.new(-1, 1, "lin", 0, 0), function(param) return pan_display(param:get()) end)
  params:set_action("nb_smpkey_pan", function(val) set_param('pan', val) end)

  params:add_control("nb_smpkey_spread", "spread", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_spread", function(val) set_param('spread', val) end)

  params:add_control("nb_smpkey_drive", "drive", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_drive", function(val) set_param('drive', val) end)

  params:add_control("nb_smpkey_noise", "noise", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_noise", function(val) set_param('noiseAmp', val) end)

  params:add_control("nb_smpkey_send_a", "send a", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_send_a", function(val) set_param('sendA', val) end)
  
  params:add_control("nb_smpkey_send_b", "send b", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_send_b", function(val) set_param('sendB', val) end)

  params:add_separator("nb_smpkey_playback", "playback")

  params:add_number("nb_smpkey_start", "sample start", 0, 1000, 0, function(param) return param:get().."ms" end)
  params:set_action("nb_smpkey_start", function(val) set_param('startPos', val / 1000) end)

  params:add_control("nb_smpkey_loop_start", "loop start", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 0.1, "%") end)
  params:set_action("nb_smpkey_loop_start", function(val) set_param('loopIn', val) set_loop('start') end)

  params:add_control("nb_smpkey_loop_length", "loop length", controlspec.new(0, 1, "lin", 0, 1), function(param) return round_form(param:get() * 100, 0.1, "%") end)
  params:set_action("nb_smpkey_loop_length", function(val) set_param('loopLen', val) set_loop('length') end)

  params:add_control("nb_smpkey_loop_fade", "loop fade", controlspec.new(0.01, 1, "lin", 0, 0.2), function(param) return round_form(param:get() * 100, 0.1, "%") end)
  params:set_action("nb_smpkey_loop_fade", function(val) set_param('fadeRel', val) end)

  params:add_separator("nb_smpkey_envelope", "amp envelope")

  params:add_control("nb_smpkey_a_attack", "attack", controlspec.new(0.001, 10, "exp", 0, 0.001), function(param) return (round_form(param:get(),0.01," s")) end)
  params:set_action("nb_smpkey_a_attack", function(val) set_param('atkA', val) end)

  params:add_control("nb_smpkey_a_decay", "decay", controlspec.new(0.01, 10, "exp", 0, 2.2), function(param) return (round_form(param:get(),0.01," s")) end)
  params:set_action("nb_smpkey_a_decay", function(val) set_param('decA', val) end)

  params:add_control("nb_smpkey_a_sustain", "sustain", controlspec.new(0, 1, "lin", 0, 0.5), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_a_sustain", function(val) set_param('susA', val) end)

  params:add_control("nb_smpkey_a_release", "release", controlspec.new(0.01, 10, "exp", 0, 2.2), function(param) return (round_form(param:get(), 0.01, " s")) end)
  params:set_action("nb_smpkey_a_release", function(val) set_param('relA', val) end)

  params:add_separator("nb_smpkey_envelope", "filter envelope")

  params:add_control("nb_smpkey_f_attack", "attack", controlspec.new(0.001, 10, "exp", 0, 0.001), function(param) return (round_form(param:get(),0.01," s")) end)
  params:set_action("nb_smpkey_f_attack", function(val) set_param('atkF', val) end)

  params:add_control("nb_smpkey_f_decay", "decay", controlspec.new(0.01, 10, "exp", 0, 2.2), function(param) return (round_form(param:get(),0.01," s")) end)
  params:set_action("nb_smpkey_f_decay", function(val) set_param('decF', val) end)

  params:add_control("nb_smpkey_f_sustain", "sustain", controlspec.new(0, 1, "lin", 0, 0.5), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_f_sustain", function(val) set_param('susF', val) end)

  params:add_control("nb_smpkey_f_release", "release", controlspec.new(0.01, 10, "exp", 0, 2.2), function(param) return (round_form(param:get(), 0.01, " s")) end)
  params:set_action("nb_smpkey_f_release", function(val) set_param('relF', val) end)

  params:add_separator("nb_smpkey_filters", "filters")

  params:add_control("nb_smpkey_lpf_hz", "lpf cutoff", controlspec.new(60, 20000, "exp", 0, 20000), function(param) return format_freq(param:get()) end)
  params:set_action("nb_smpkey_lpf_hz", function(val) set_param('lpfHz', val) end)

  params:add_control("nb_smpkey_lpf_rz", "lpf resonance", controlspec.new(0, 1, "lin", 0, 0.2), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_lpf_rz", function(val) set_param('lpfRz', val) end)

  params:add_control("nb_smpkey_lpf_env", "lpf env", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_lpf_env", function(val) set_param('lpfEnv', val) end)

  params:add_control("nb_smpkey_hpf_hz", "hpf cutoff", controlspec.new(20, 8000, "exp", 0, 20), function(param) return format_freq(param:get()) end)
  params:set_action("nb_smpkey_hpf_hz", function(val) set_param('hpfHz', val) end)

  params:add_control("nb_smpkey_hpf_rz", "hpf resonance", controlspec.new(0, 1, "lin", 0, 0.2), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_hpf_rz", function(val) set_param('hpfRz', val) end)

  params:add_control("nb_smpkey_hpf_env", "hpf env", controlspec.new(-1, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_hpf_env", function(val) set_param('hpfEnv', val) end)

  params:add_separator("nb_smpkey_pitch", "pitch")

  params:add_number("nb_smpkey_tune", "tune", -100, 100, 0, function(param) return param:get().."ct" end)
  params:set_action("nb_smpkey_tune", function(val) set_param('tune', val / 100) end)

  params:add_number("nb_smpkey_transpose", "transpose", -24, 24, 0, function(param) return param:get().."st" end)
  params:set_action("nb_smpkey_transpose", function(val) set_param('pitch', val) end)

  params:add_number("nb_smpkey_pitchbend", "pitchbend", 1, 24, 1, function(param) return param:get().."st" end)
  params:set_action("nb_smpkey_pitchbend", function(val) set_param('bndAmt', val) end)

  params:add_separator("nb_smpkey_modmods", "modulation")

  params:add_control("nb_smpkey_mod_amt", "mod amt [map me]", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_mod_amt", function(val) set_param('modDepth', val) end)
  params:set_save("nb_smpkey_mod_amt", false)

  params:add_control("nb_smpkey_drive_mod", "drive", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_drive_mod", function(val) set_param('driveMod', val) end)

  params:add_control("nb_smpkey_noise_mod", "noise", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_noise_mod", function(val) set_param('noiseMod', val) end)

  params:add_control("nb_smpkey_lpf_hz_mod", "lpf cutoff", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_lpf_hz_mod", function(val) set_param('lpfMod', val) end)
  
  params:add_control("nb_smpkey_hpf_hz_mod", "hpf cutoff", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_hpf_hz_mod", function(val) set_param('hpfMod', val) end)

  params:add_control("nb_smpkey_send_a_mod", "send a", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_send_a_mod", function(val) set_param('sendAMod', val) end)
  
  params:add_control("nb_smpkey_send_b_mod", "send b", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_smpkey_send_b_mod", function(val) set_param('sendBMod', val) end)

  bang_params()

end


--------------------------- nb player ---------------------------

function add_smpkey_player()
  local player = {
    alloc = vx.new(MAX_POLY, 2),
    slot = {},
    clk = nil
  }

  function player:describe()
    return {
      name = "smpKey",
      supports_bend = false,
      supports_slew = false
    }
  end

  function player:active()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if not is_active then
          is_active = true
          alloc_buffers()
          params:show("nb_smpkey_group")
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:inactive()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if is_active then
          is_active = false
          dont_panic()
          clear_buffer()
          params:hide("nb_smpkey_group")
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:stop_all()
    dont_panic()
  end

  function player:set_slew(s)
  end

  function player:pitch_bend(note, val)
    set_param('bndDepth', val)
  end

  function player:modulate_note(note, key, value)
  end

  function player:modulate(val)
    params:set("nb_smpkey_mod_amt", val)
  end

  function player:note_on(note, vel)
    local slot = self.slot[note]
    if slot == nil then
      slot = self.alloc:get()
      slot.count = 1
    end
    local vox = slot.id - 1 -- sc is zero indexed!
    slot.on_release = function()
      stop_voice(vox)
    end
    self.slot[note] = slot
    play_voice(vox, note, vel)
  end

  function player:note_off(note)
    local slot = self.slot[note]
    if slot ~= nil then
      self.alloc:release(slot)
    end
    self.slot[note] = nil
  end

  function player:add_params()
    add_smpkey_params()
  end

  if note_players == nil then
    note_players = {}
  end
  note_players["smpKey"] = player

end


--------------------------- mod zone ---------------------------

local function post_system()
  if util.file_exists(preset_path) == false then
    util.make_dir(preset_path)
  end
end

local function pre_init()
  init_smpkey()
  add_smpkey_player()
end

local function post_cleanup()
  clear_buffer()
end

md.hook.register("system_post_startup", "nb smpKey post startup", post_system)
md.hook.register("script_pre_init", "nb smpKey pre init", pre_init)
md.hook.register("script_post_cleanup", "nb smpKey cleanup", post_cleanup)
