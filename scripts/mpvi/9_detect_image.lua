-- Detects when 🖼 are loaded and allows you to run commands configured in 1_detect_image.conf

local std  = require "lib/std".std

local script_dir      	= mp.get_script_directory()          	-- ~/.config/mpv/scripts/mpvi
local script_dir_base 	= std.basename(script_dir)           	--                       mpvi
local script_path     	= std.getScriptFullPath()            	-- ~/.config/mpv/scripts/mpvi/<script_name>.lua
local script_file_name	= std.filename(script_path)          	-- <script_name>.lua
local script_stem     	= std.delua(script_file_name)        	-- <script_name>
local opt_path_rel    	= script_dir_base ..'/'.. script_stem	-- mpvi/<script_name>

local opts = {
  on_load_image_first	= "",
  on_load_image      	= "",
  on_load_non_image  	= "",
}
local options	= require 'mp.options'
local msg    	= require 'mp.msg'

options.read_options(opts, opt_path_rel, function() end)
-- msg.info("on_load_image_first	= " .. tostring(opts.on_load_image_first))
-- msg.info("on_load_image      	= " .. tostring(opts.on_load_image))
-- msg.info("on_load_non_image  	= " .. tostring(opts.on_load_non_image))

local function run_maybe(str)
  if str ~= "" then mp.command(str) end
end

local wasImg = false
local function set_image(isImg)
  if     isImg and not wasImg then msg.info("Detected 🖼 #1"); run_maybe(opts.on_load_image_first) end
  if     isImg                then msg.info("Detected 🖼"   ); run_maybe(opts.on_load_image      ) end
  if not isImg and     wasImg then msg.info("Detected Non🖼"); run_maybe(opts.on_load_non_image  ) end
  wasImg = isImg
end

local properties = {}
local function properties_changed()
  local framecount	= properties["estimated-frame-count"]
  local dwidth    	= properties["dwidth"               ]
  local tracks    	= properties["track-list"           ]
  local path      	= properties["path"                 ]

  if not path   or path    == "" then return end
  if not tracks or #tracks ==  0 then return end
  local audio_tracks = 0
  for _, track in ipairs(tracks) do
    if track.type == "audio" then
      audio_tracks = audio_tracks + 1
    end
  end
  -- only do things when state is consistent
  if     not framecount and audio_tracks      > 0 then set_image(false)
  elseif     framecount and dwidth and dwidth > 0 then set_image(
    (framecount == 0 or framecount == 1) -- png have 0 frames, jpg 1 ¯\_(ツ)_/¯
    and audio_tracks == 0)
  end
end

local function observe(propname)
  mp.observe_property(propname, "native", function(_, val)
    if val ~= properties[propname] then
      properties[propname] = val
      msg.verbose("Property " .. propname .. " changed")
      properties_changed()
    end
  end)
end

observe("estimated-frame-count")
observe("track-list"           )
observe("dwidth"               )
observe("path"                 )
