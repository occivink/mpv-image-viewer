local needs_adjusting = false
local current_idle = nil
local zoom_increment = 0

local opts = {
    pan_follows_cursor_margin = 50,
    pan_follows_cursor_move_if_full_view = true,
    status_line_enabled = true,
    status_line_position = "bottom_left",
    status_line_size = 36,
    status_line = "${filename} [${playlist-pos-1}/${playlist-count}]",
    command_on_first_image_loaded="",
    command_on_image_loaded="",
    command_on_non_image_loaded="",
}
(require 'mp.options').read_options(opts)
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

function register_idle(func)
    current_idle = func
    mp.register_idle(current_idle)
end

function cleanup()
    mp.remove_key_binding("image-viewer-impl")
    if current_idle then mp.unregister_idle(current_idle) end
    needs_adjusting = false
    zoom_increment = 0
end

function compute_video_dimensions()
    -- this function is very much ripped from video/out/aspect.c in mpv's source
    local video_params = mp.get_property_native("video-out-params")
    if not video_params then return nil end
    local video_dimensions = {
        top_left = {x = 0, y = 0},
        bottom_right = {x = 0, y = 0},
        size = {h = 0, w = 0},
    }
    local keep_aspect = mp.get_property_bool("keepaspect")
    local w = video_params["w"]
    local h = video_params["h"]
    local dw = video_params["dw"]
    local dh = video_params["dh"]
    if mp.get_property_number("video-rotate") % 180 == 90 then
        w, h = h,w
        dw, dh = dh, dw
    end
    local window_w, window_h = mp.get_osd_size()

    if keep_aspect then
        local unscaled = mp.get_property_native("video-unscaled")
        local panscan = mp.get_property_number("panscan")

        local fwidth = window_w
        local fheight = math.floor(window_w / dw * dh)
        if fheight > window_h or fheight < h then
            local tmpw = math.floor(window_h / dh * dw)
            if tmpw <= window_w then
                fheight = window_h
                fwidth = tmpw
            end
        end
        local vo_panscan_area = window_h - fheight
        local f_w = fwidth / fheight
        local f_h = 1
        if vo_panscan_area == 0 then
            vo_panscan_area = window_h - fwidth
            f_w = 1
            f_h = fheight / fwidth
        end
        if unscaled or unscaled == "downscale-big" then
            vo_panscan_area = 0
            if unscaled or (dw <= window_w and dh <= window_h) then
                fwidth = dw
                fheight = dh
            end
        end

        local scaled_width = fwidth + math.floor(vo_panscan_area * panscan * f_w)
        local scaled_height = fheight + math.floor(vo_panscan_area * panscan * f_h)

        local split_scaling = function (dst_size, scaled_src_size, zoom, align, pan)
            scaled_src_size = math.floor(scaled_src_size * 2 ^ zoom)
            align = (align + 1) / 2
            local dst_start = math.floor((dst_size - scaled_src_size) * align + pan * scaled_src_size)
            if dst_start < 0 then
                --account for C int cast truncating as opposed to flooring
                dst_start = dst_start + 1
            end
            local dst_end = dst_start + scaled_src_size;
            if dst_start >= dst_end then
                dst_start = 0
                dst_end = 1
            end
            return dst_start, dst_end
        end
        local zoom = mp.get_property_number("video-zoom")

        local align_x = mp.get_property_number("video-align-x")
        local pan_x = mp.get_property_number("video-pan-x")
        video_dimensions.top_left.x, video_dimensions.bottom_right.x = split_scaling(window_w, scaled_width, zoom, align_x, pan_x)

        local align_y = mp.get_property_number("video-align-y")
        local pan_y = mp.get_property_number("video-pan-y")
        video_dimensions.top_left.y, video_dimensions.bottom_right.y = split_scaling(window_h,  scaled_height, zoom, align_y, pan_y)
    else
        video_dimensions.top_left.x = 0
        video_dimensions.bottom_right.x = window_w
        video_dimensions.top_left.y = 0
        video_dimensions.bottom_right.y = window_h
    end
    video_dimensions.size.w = video_dimensions.bottom_right.x - video_dimensions.top_left.x
    video_dimensions.size.h = video_dimensions.bottom_right.y - video_dimensions.top_left.y
    return video_dimensions
end

function drag_to_pan_handler(table)
    cleanup()
    if table["event"] == "down" then
        local video_dimensions = compute_video_dimensions()
        if not video_dimensions then return end
        local mouse_pos_origin, video_pan_origin = {}, {}
        mouse_pos_origin.x, mouse_pos_origin.y = mp.get_mouse_pos()
        video_pan_origin.x = mp.get_property("video-pan-x")
        video_pan_origin.y = mp.get_property("video-pan-y")
        register_idle(function()
            if needs_adjusting then
                local mX, mY = mp.get_mouse_pos()
                local pX = video_pan_origin.x + (mX - mouse_pos_origin.x) / video_dimensions.size.w
                local pY = video_pan_origin.y + (mY - mouse_pos_origin.y) / video_dimensions.size.h
                mp.command("no-osd set video-pan-x " .. pX .. "; no-osd set video-pan-y " .. pY)
                needs_adjusting = false
            end
        end)
        mp.add_forced_key_binding("mouse_move", "image-viewer-impl",
            function() needs_adjusting = true end
        )
    end
end

function pan_follows_cursor_handler(table)
    cleanup()
    if table["event"] == "down" then
        local video_dimensions = compute_video_dimensions()
        if not video_dimensions then return end
        local window_w, window_h = mp.get_osd_size()
        register_idle(function()
            if needs_adjusting then
                local mX, mY = mp.get_mouse_pos()
                local x = math.min(1, math.max(- 2 * mX / window_w + 1, -1))
                local y = math.min(1, math.max(- 2 * mY / window_h + 1, -1))
                local command = ""
                local margin, move_full = opts.pan_follows_cursor_margin, opts.pan_follows_cursor_move_if_full_view
                if (not move_full and window_w < video_dimensions.size.w) then
                    command = command .. "no-osd set video-pan-x " .. x * (video_dimensions.size.w - window_w + 2 * margin) / (2 * video_dimensions.size.w) .. ";"
                elseif mp.get_property_number("video-pan-x") ~= 0 then
                    command = command .. "no-osd set video-pan-x " .. "0;"
                end
                if (not move_full and window_h < video_dimensions.size.h) then
                    command = command .. "no-osd set video-pan-y " .. y * (video_dimensions.size.h - window_h + 2 * margin) / (2 * video_dimensions.size.h) .. ";"
                elseif mp.get_property_number("video-pan-y") ~= 0 then
                    command = command .. "no-osd set video-pan-y " .. "0;"
                end
                if command ~= "" then
                    mp.command(command)
                end
                needs_adjusting = false
            end
        end)
        needs_adjusting = true
        mp.add_forced_key_binding("mouse_move", "image-viewer-impl", function()
            needs_adjusting = true
        end)
    end
end

function cursor_centric_zoom_handler(amt)
    local arg_num = tonumber(amt)
    if not arg_num or arg_num == 0 then return end
    if zoom_increment == 0 then
        cleanup()
        local video_dimensions = compute_video_dimensions()
        if not video_dimensions then return end
        local mouse_pos_origin, video_pan_origin = {}, {}
        mouse_pos_origin.x, mouse_pos_origin.y = mp.get_mouse_pos()
        video_pan_origin.x = mp.get_property("video-pan-x")
        video_pan_origin.y = mp.get_property("video-pan-y")
        local zoom_origin = mp.get_property("video-zoom")
        -- how far the cursor is form the middle of the video (in percentage)
        local rx = (video_dimensions.top_left.x + video_dimensions.size.w / 2 - mouse_pos_origin.x) / (video_dimensions.size.w / 2)
        local ry = (video_dimensions.top_left.y + video_dimensions.size.h / 2 - mouse_pos_origin.y) / (video_dimensions.size.h / 2)
        register_idle(function()
            if needs_adjusting then
                -- the size in pixels of the (in|de)crement
                local diffHeight = (2 ^ zoom_increment - 1) * video_dimensions.size.h
                local diffWidth  = (2 ^ zoom_increment - 1) * video_dimensions.size.w
                local newPanX = (video_pan_origin.x * video_dimensions.size.w + rx * diffWidth / 2) / (video_dimensions.size.w + diffWidth)
                local newPanY = (video_pan_origin.y * video_dimensions.size.h + ry * diffHeight / 2) / (video_dimensions.size.h + diffHeight)
                mp.command("no-osd set video-zoom " .. zoom_origin + zoom_increment .. "; no-osd set video-pan-x " .. newPanX .. "; no-osd set video-pan-y " .. newPanY)
                needs_adjusting = false
            end
        end)
        mp.add_forced_key_binding("mouse_move", "image-viewer-impl", cleanup)
    end
    zoom_increment = zoom_increment + arg_num
    needs_adjusting = true
end

function align_border(x, y)
    local video_dimensions = compute_video_dimensions()
    if not video_dimensions then return end
    local window_w, window_h = mp.get_osd_size()
    local x, y = tonumber(x), tonumber(y)
    local command = ""
    if x then
        command = command .. "no-osd set video-pan-x " .. x * (video_dimensions.size.w - window_w) / (2 * video_dimensions.size.w) .. ";"
    end
    if y then
        command = command .. "no-osd set video-pan-y " .. y * (video_dimensions.size.h - window_h) / (2 * video_dimensions.size.h) .. ";"
    end
    if command ~= "" then
        mp.command(command)
    end
end

function pan_image(axis, amount, zoom_invariant, image_constrained)
    amount = tonumber(amount)
    if not amount or amount == 0 or axis ~= "x" and axis ~= "y" then return end
    if zoom_invariant == "yes" then
        amount = amount / 2 ^ mp.get_property_number("video-zoom")
    end
    local prop = "video-pan-" .. axis
    local old_pan = mp.get_property_number(prop)
    if image_constrained == "yes" then
        local video_dimensions = compute_video_dimensions()
        if not video_dimensions then return end
        local measure = axis == "x" and "w" or "h"
        local window = {}
        window.w, window.h = mp.get_osd_size()
        local pixels_moved = amount * video_dimensions.size[measure]
        -- should somehow refactor this
        if pixels_moved > 0 then
            if window[measure] > video_dimensions.size[measure] then
                if video_dimensions.bottom_right[axis] >= window[measure] then return end
                if video_dimensions.bottom_right[axis] + pixels_moved > window[measure] then
                    amount = (window[measure] - video_dimensions.bottom_right[axis]) / video_dimensions.size[measure]
                end
            else
                if video_dimensions.top_left[axis] >= 0 then return end
                if video_dimensions.top_left[axis] + pixels_moved > 0 then
                    amount = (0 - video_dimensions.top_left[axis]) / video_dimensions.size[measure]
                end
            end
        else
            if window[measure] > video_dimensions.size[measure] then
                if video_dimensions.top_left[axis] <= 0 then return end
                if video_dimensions.top_left[axis] + pixels_moved < 0 then
                    amount = (0 - video_dimensions.top_left[axis]) / video_dimensions.size[measure]
                end
            else
                if video_dimensions.bottom_right[axis] <= window[measure] then return end
                if video_dimensions.bottom_right[axis] + pixels_moved < window[measure] then
                    amount = (window[measure] - video_dimensions.bottom_right[axis]) / video_dimensions.size[measure]
                end
            end
        end
    end
    mp.set_property_number(prop, old_pan + amount)
end

function rotate_video(amt)
    local rot = mp.get_property_number("video-rotate")
    rot = (rot + amt) % 360
    mp.set_property_number("video-rotate", rot)
end

function reset_pan_if_visible()
    local video_dimensions = compute_video_dimensions()
    if not video_dimensions then return end
    local window_w, window_h = mp.get_osd_size()
    local command = ""
    if (window_w >= video_dimensions.size.w) then
        command = command .. "no-osd set video-pan-x 0" .. ";"
    end
    if (window_h >= video_dimensions.size.h) then
        command = command .. "no-osd set video-pan-y 0" .. ";"
    end
    if command ~= "" then
        mp.command(command)
    end
end

function force_print_filename()
    mp.set_property("msg-level", "cplayer=info")
    mp.commandv("print-text", mp.get_property("path"))
    mp.set_property("msg-level", "all=no")
end

local status_line_enabled = false;

function refresh_status_line()
    local path = mp.get_property("path")
    if path == nil or path == "" then
        mp.set_osd_ass(0, 0, "")
        return
    end
    local expanded = mp.command_native({ "expand-text", opts.status_line })
    if not expanded then
        msg.warn("Error expanding status line")
        mp.set_osd_ass(0, 0, "")
        return
    end
    local w,h = mp.get_osd_size()
    local an, x, y
    local margin = 10
    if opts.status_line_position == "top_left" then
        x = margin
        y = margin
        an = 7
    elseif opts.status_line_position == "top_right" then
        x = w-margin
        y = margin
        an = 9
    elseif opts.status_line_position == "bottom_right" then
        x = w-margin
        y = h-margin
        an = 3
    else
        x = margin
        y = h-margin
        an = 1
    end
    local ass = assdraw:ass_new()
    ass:new_event()
    ass:an(an)
    ass:pos(x,y)
    ass:append("{\\fs".. opts.status_line_size.. "}{\\bord1.0}")
    ass:append(expanded)
    mp.set_osd_ass(w, h, ass.text)
end

function enable_status_line()
    if status_line_enabled then return end
    status_line_enabled = true
    local start = 0
    while true do
        local s, e, cap = string.find(opts.status_line, "%${[?!]?([%l%d-/]*)", start)
        if not s then break end
        mp.observe_property(cap, nil, refresh_status_line)
        start = e
    end
    mp.observe_property("path", nil, refresh_status_line)
    mp.observe_property("osd-width", nil, refresh_status_line)
    mp.observe_property("osd-height", nil, refresh_status_line)
    refresh_status_line()
end

function disable_status_line()
    if not status_line_enabled then return end
    status_line_enabled = false
    mp.unobserve_property(refresh_status_line)
    mp.set_osd_ass(0, 0, "")
end

if opts.status_line_enabled then
    enable_status_line()
end

if opts.command_on_image_loaded ~= "" or opts.command_on_non_image_loaded ~= "" then
    local was_image = false
    local frame_count = nil
    local audio_tracks = nil
    local out_params_ready = nil
    local path = nil

    function state_changed()
        function set_image(is_image)
            if is_image and not was_image and opts.command_on_first_image_loaded ~= "" then
                mp.command(opts.command_on_first_image_loaded)
            end
            if is_image and opts.command_on_image_loaded ~= "" then
                mp.command(opts.command_on_image_loaded)
            end
            if not is_image and was_image and opts.command_on_non_image_loaded ~= "" then
                mp.command(opts.command_on_non_image_loaded)
            end
            was_image = is_image
        end
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

    mp.observe_property("video-out-params/par", "number", function(_, val)
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
end

mp.add_key_binding(nil, "drag-to-pan", drag_to_pan_handler, {complex = true})
mp.add_key_binding(nil, "pan-follows-cursor", pan_follows_cursor_handler, {complex = true})
mp.add_key_binding(nil, "cursor-centric-zoom", cursor_centric_zoom_handler)
mp.add_key_binding(nil, "align-border", align_border)
mp.add_key_binding(nil, "pan-image", pan_image)
mp.add_key_binding(nil, "rotate-video", rotate_video)
mp.add_key_binding(nil, "reset-pan-if-visible", reset_pan_if_visible)
mp.add_key_binding(nil, "force-print-filename", force_print_filename)

mp.add_key_binding(nil, "enable-status-line", enable_status_line)
mp.add_key_binding(nil, "disable-status-line", disable_status_line)
mp.add_key_binding(nil, "toggle-status-line", function() if status_line_enabled then disable_status_line() else enable_status_line() end end)
