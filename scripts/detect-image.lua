local opts = {
    command_on_first_image_loaded="",
    command_on_image_loaded="",
    command_on_non_image_loaded="",
}
(require 'mp.options').read_options(opts)

if opts.command_on_first_image_loaded == ""
    and opts.command_on_image_loaded == ""
    and opts.command_on_non_image_loaded == ""
then
    return
end

local msg = require 'mp.msg'

local was_image = false
local frame_count = nil
local audio_tracks = nil
local out_params_ready = nil
local path = nil

function run_maybe(str)
    if str ~= "" then
        mp.command(str)
    end
end

function set_image(is_image)
    if is_image and not was_image then
        msg.verbose("First image detected")
        run_maybe(opts.command_on_first_image_loaded)
    end
    if is_image then
        msg.verbose("Image detected")
        run_maybe(opts.command_on_image_loaded)
    end
    if not is_image and was_image then
        msg.verbose("Non-image detected")
        run_maybe(opts.command_on_non_image_loaded)
    end
    was_image = is_image
end

function state_changed()
    -- only do things when state is consistent
    if path ~= nil and audio_tracks ~= nil then
        if frame_count == nil and audio_tracks > 0 then
            set_image(false)
        elseif out_params_ready and frame_count ~= nil then
            -- png have 0 frames, jpg 1 ¯\_(ツ)_/¯
            set_image((frame_count == 0 or frame_count == 1) and audio_tracks == 0)
        end
    end
end

mp.observe_property("dwidth", "number", function(_, val)
    out_params_ready = (val ~= nil and val > 0)
    state_changed()
end)

mp.observe_property("estimated-frame-count", "number", function(_, val)
    frame_count = val
    state_changed()
end)

mp.observe_property("path", "string", function(_, val)
    if not val or val == "" then
        path = nil
    else
        path = val
    end
    state_changed()
end)

mp.register_event("tracks-changed", function()
    audio_tracks = 0
    local tracks = 0
    for _, track in ipairs(mp.get_property_native("track-list")) do
        tracks = tracks + 1
         if track.type == "audio" then
             audio_tracks = audio_tracks + 1
         end
    end
    if tracks == 0 then
        audio_tracks = nil
    end
    state_changed()
end)
