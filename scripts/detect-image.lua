local opts = {
    command_on_first_image_loaded="",
    command_on_image_loaded="",
    command_on_non_image_loaded="",
}
local options = require 'mp.options'
local msg = require 'mp.msg'

options.read_options(opts, nil, function() end)

function run_maybe(str)
    if str ~= "" then
        mp.command(str)
    end
end

local was_image = false

function set_image(is_image)
    if is_image and not was_image then
        msg.info("First image detected")
        run_maybe(opts.command_on_first_image_loaded)
    end
    if is_image then
        msg.info("Image detected")
        run_maybe(opts.command_on_image_loaded)
    end
    if not is_image and was_image then
        msg.info("Non-image detected")
        run_maybe(opts.command_on_non_image_loaded)
    end
    was_image = is_image
end

local properties = {}

function properties_changed()
    local dwidth = properties["dwidth"]
    local tracks = properties["track-list"]
    local path = properties["path"]
    local framecount = properties["estimated-frame-count"]

    if not path or path == "" then return end
    if not tracks or #tracks == 0 then return end
    local audio_tracks = 0
    for _, track in ipairs(tracks) do
        if track.type == "audio" then
            audio_tracks = audio_tracks + 1
        end
    end

    -- only do things when state is consistent
    if not framecount and audio_tracks > 0 then
        set_image(false)
    elseif framecount and dwidth and dwidth > 0 then
        -- png have 0 frames, jpg 1 ¯\_(ツ)_/¯
        set_image((framecount == 0 or framecount == 1) and audio_tracks == 0)
    end
end

function observe(propname)
    mp.observe_property(propname, "native", function(_, val)
        if val ~= properties[propname] then
            properties[propname] = val
            msg.verbose("Property " .. propname .. " changed")
            properties_changed()
        end
    end)
end
observe("estimated-frame-count")
observe("track-list")
observe("dwidth")
observe("path")
