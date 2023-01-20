local std	= require "lib/std".std

local script_directory = mp.get_script_directory() -- ~/.config/mpv/scripts/mpvi
function load(relative_path)
  if relative_path:endswith('.lua') then relative_path = relative_path
  else                                   relative_path = relative_path .. ".lua" end
  dofile(script_directory ..'/'.. relative_path)
end

-- configs are @ script-opts/mpvi/<script_name>.conf
load('2_image_positioning'	) -- add several high-level commands to zoom and pan
load('3_status_line'      	) -- add a status line that can show different properties in the window corner
load('4_minimap'          	) -- add a minimap that displays the position of the image relative to the view
load('5_ruler'            	) -- add a `ruler` command that lets you measure positions, distances and angles in the image
load('6_freeze_window'    	) -- disabled window auto resizing on file changes to fit its size
load('9_detect_image'     	) -- detect when 🖼 are loaded, allows running commands from .conf
