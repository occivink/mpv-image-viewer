-- Adds a status line that can show different properties in the corner of the window. By default it shows `filename [positon/total]` in the bottom left
-- Can be activated with the commands `status-line-enable`, `status-line-disable`, `status-line-toggle` and configured through mvi_3_status_line.conf

local std  = require "lib/std".std

local script_dir      	= mp.get_script_directory()          	-- ~/.config/mpv/scripts/mvi
local script_dir_base 	= std.basename(script_dir)           	--                       mvi
local script_path     	= std.getScriptFullPath()            	-- ~/.config/mpv/scripts/mvi/<script_name>.lua
local script_file_name	= std.filename(script_path)          	-- <script_name>.lua
local script_stem     	= std.delua(script_file_name)        	-- <script_name>
local opt_path_rel    	= script_dir_base ..'/'.. script_stem	-- mvi/<script_name>

local opts = {
  enabled          	= true,
  size             	= 36,
  margin           	= 10,
  text_top_left    	= "",
  text_top_right   	= "",
  text_bottom_left 	= "${filename} [${playlist-pos-1}/${playlist-count}]",
  text_bottom_right	= "[${dwidth:X}x${dheight:X}]",
}

local msg    	= require 'mp.msg'
local assdraw	= require 'mp.assdraw'
local options	= require 'mp.options'

options.read_options(opts, opt_path_rel, function(c)
  if c["enabled"] then
    if opts.enabled then  enable()
    else                 disable() end
  end
  if c["size"] or c["margin"] then
    mark_stale()
  end
  if c["text_top_left"    ] or
     c["text_top_right"   ] or
     c["text_bottom_left" ] or
     c["text_bottom_right"]
  then
    observe_properties()
    mark_stale()
  end
end)
-- msg.info("text_bottom_left	= " .. tostring(opts.text_bottom_left))

local stale 	= true
local active	= false

function draw_ass(ass)
  local ww, wh = mp.get_osd_size()
  mp.set_osd_ass(ww, wh, ass)
end

function refresh()
  if not stale then return end
  stale = false
  local a = assdraw:ass_new()
  local draw_text = function(text, an, x, y)
    if text == "" then return end
    local expanded = mp.command_native({ "expand-text", text})
    if not expanded then
      msg.error("Error expanding status-line")
      return
    end
    msg.verbose("Status-line changed to: " .. expanded)
    a:new_event()
    a:an(an)
    a:pos(x,y)
    a:append("{\\fs".. opts.size.. "}{\\bord1.0}")
    a:append(expanded)
  end
  local w,h = mp.get_osd_size()
  local m = opts.margin
  draw_text(opts.text_top_left    	, 7,   m,   m)
  draw_text(opts.text_top_right   	, 9, w-m,   m)
  draw_text(opts.text_bottom_left 	, 1,   m, h-m)
  draw_text(opts.text_bottom_right	, 3, w-m, h-m)
  draw_ass(a.text)
end

function mark_stale()
  stale = true
end

function observe_properties()
  mp.unobserve_property(mark_stale)
  if not active then return end
  for _, str in ipairs({
    opts.text_top_left,
    opts.text_top_right,
    opts.text_bottom_left,
    opts.text_bottom_right,
  }) do
    local start = 0
    while true do
      local s, e, cap = string.find(str, "%${[?!]?([%l%d-/]*)", start)
      if not s then break end
      msg.verbose("Observing property " .. cap)
      mp.observe_property(cap, nil, mark_stale)
      start = e
    end
  end
  mp.observe_property("osd-width" , nil, mark_stale)
  mp.observe_property("osd-height", nil, mark_stale)
end

function enable()
  if active then return end
  active = true
  observe_properties()
  mp.register_idle(refresh)
  mark_stale()
end


function disable()
  if not active then return end
  active = false
  observe_properties()
  mp.unregister_idle(refresh)
  draw_ass("")
end

function toggle()
  if active then
    disable()
  else
    enable()
  end
end

if opts.enabled then
  enable()
end

mp.add_key_binding(nil, "status-line-enable" 	, enable)
mp.add_key_binding(nil, "status-line-disable"	, disable)
mp.add_key_binding(nil, "status-line-toggle" 	, toggle)
