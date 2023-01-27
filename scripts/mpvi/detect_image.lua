-- Detects when 🖼 are loaded and allows you to run commands from config
-- Configure via script-opts/mpvi/detect_image.yaml

local std       	= require "lib/std".std
local parse_yaml	= require "lib/tinyyaml".parse

local script_dir      	= mp.get_script_directory()          	-- ~/.config/mpv/scripts/mpvi
local script_dir_base 	= std.basename(script_dir)           	--                       mpvi
local script_path     	= std.getScriptFullPath()            	-- ~/.config/mpv/scripts/mpvi/<script_name>.lua
local script_file_name	= std.filename(script_path)          	-- <script_name>.lua
local script_stem     	= std.delua(script_file_name)        	-- <script_name>
local opt_path_rel    	= script_dir_base ..'/'.. script_stem	-- mpvi/<script_name>

local opts = {
  on_load_image_first	= {""},
  on_load_image      	= {""},
  on_unload_image    	= {""},
}
local options	= require 'mp.options'
local msg    	= require 'mp.msg'

std.read_options_yaml(opts, opt_path_rel, function() end)

local function run_maybe(str_or_strdict)
  local  arg_type = type(str_or_strdict)
  if     arg_type == 'string' then
    if str_or_strdict ~= "" then mp.command(str_or_strdict) end
  elseif arg_type == 'table' then
    for k, v in pairs(str_or_strdict) do run_maybe(v) end   end
end

local wasImg = false
local function set_image(isImg)
  if     isImg and not wasImg then msg.info("🖼 Load#1"); run_maybe(opts.on_load_image_first) end
  if     isImg                then msg.info("🖼 Load"  ); run_maybe(opts.on_load_image      ) end
  if not isImg and     wasImg then msg.info("🖼 Unload"); run_maybe(opts.on_unload_image    ) end
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
