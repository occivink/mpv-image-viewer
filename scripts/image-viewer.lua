local opts = {
    pan_follows_cursor_margin = 50,
    pan_follows_cursor_move_if_full_view = false,

    status_line_enabled = false,
    status_line_position = "bottom_left",
    status_line_size = 36,
    status_line = "${filename} [${playlist-pos-1}/${playlist-count}]",

    minimap_enabled = true,
    minimap_center = "92,92",
    minimap_scale = 12,
    minimap_max_size = "16,16",
    minimap_image_opacity = "88",
    minimap_image_color = "BBBBBB",
    minimap_view_opacity = "BB",
    minimap_view_color = "222222",
    minimap_view_above_image = true,
    minimap_hide_when_full_image_in_view = true,

    ruler_show_distance=true,
    ruler_show_coordinates=true,
    ruler_coordinates_space="both",
    ruler_show_angles="degrees",
    ruler_line_width=2,
    ruler_dots_radius=3,
    ruler_font_size=36,
    ruler_line_color="33",
    ruler_confirm_bindings="MBTN_LEFT,ENTER",
    ruler_exit_bindings="ESC",
    ruler_set_first_point_on_begin=false,
    ruler_clear_on_second_point_set=false,

    command_on_first_image_loaded="",
    command_on_image_loaded="",
    command_on_non_image_loaded="",
}
(require 'mp.options').read_options(opts)
function split(input)
    local ret = {}
    for str in string.gmatch(input, "([^,]+)") do
        ret[#ret + 1] = str
    end
    return ret
end
function str_to_num(array)
    local ret = {}
    for _, v in ipairs(array) do
        ret[#ret + 1] = tonumber(v)
    end
    return ret
end
opts.minimap_center=str_to_num(split(opts.minimap_center))
opts.minimap_max_size=str_to_num(split(opts.minimap_max_size))
opts.ruler_confirm_bindings=split(opts.ruler_confirm_bindings)
opts.ruler_exit_bindings=split(opts.ruler_exit_bindings)

function clamp(value, low, high)
    if value <= low then
        return low
    elseif value >= high then
        return high
    else
        return value
    end
end

local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local ass = { -- shared ass state
    status_line = "",
    minimap = "",
    ruler = "",
}

local cleanup = nil -- function set up by drag-to-pan/pan-follows cursor and must be called to clean lingering state
local mouse_move_callbacks = {} -- functions that are called when mouse_move is triggered
function add_mouse_move_callback(key, func)
    if #mouse_move_callbacks == 0 then
        mp.add_forced_key_binding("mouse_move", "image-viewer-internal", function()
            for _, func in pairs(mouse_move_callbacks) do
                func()
            end
        end)
    end
    mouse_move_callbacks[key] = func
end
function remove_mouse_move_callback(key)
    mouse_move_callbacks[key] = nil
    for _,_ in pairs(mouse_move_callbacks) do
        return
    end
    mp.remove_key_binding("image-viewer-internal")
end

video_dimensions_stale = true
function get_video_dimensions()
    -- this function is very much ripped from video/out/aspect.c in mpv's source
    if not video_dimensions_stale then return _video_dimensions end
    local video_params = mp.get_property_native("video-out-params")
    if not video_params then
        _video_dimensions = nil
        return nil
    end
    if not _timestamp then _timestamp = 0 end
    _timestamp = _timestamp + 1
    _video_dimensions = {
        timestamp = _timestamp,
        top_left = {x = 0, y = 0},
        bottom_right = {x = 0, y = 0},
        size = {w = 0, h = 0},
        ratios = {w = 0, h = 0}, -- by how much the original video got scaled
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
        _video_dimensions.top_left.x, _video_dimensions.bottom_right.x = split_scaling(window_w, scaled_width, zoom, align_x, pan_x)

        local align_y = mp.get_property_number("video-align-y")
        local pan_y = mp.get_property_number("video-pan-y")
        _video_dimensions.top_left.y, _video_dimensions.bottom_right.y = split_scaling(window_h,  scaled_height, zoom, align_y, pan_y)
    else
        _video_dimensions.top_left.x = 0
        _video_dimensions.bottom_right.x = window_w
        _video_dimensions.top_left.y = 0
        _video_dimensions.bottom_right.y = window_h
    end
    _video_dimensions.size.w = _video_dimensions.bottom_right.x - _video_dimensions.top_left.x
    _video_dimensions.size.h = _video_dimensions.bottom_right.y - _video_dimensions.top_left.y
    _video_dimensions.ratios.w = _video_dimensions.size.w / w
    _video_dimensions.ratios.h = _video_dimensions.size.h / h
    video_dimensions_stale = false
    return _video_dimensions
end

for _, p in ipairs({
    "keepaspect",
    "video-out-params",
    "video-unscaled",
    "panscan",
    "video-zoom",
    "video-align-x",
    "video-pan-x",
    "video-align-y",
    "video-pan-y",
    "osd-width",
    "osd-height",
}) do
    mp.observe_property(p, "native", function() video_dimensions_stale = true end)
end

function drag_to_pan_handler(table)
    if cleanup then
        cleanup()
        cleanup = nil
    end
    if table["event"] == "down" then
        local video_dimensions = get_video_dimensions()
        if not video_dimensions then return end
        local mouse_pos_origin, video_pan_origin = {}, {}
        local moved = false
        mouse_pos_origin.x, mouse_pos_origin.y = mp.get_mouse_pos()
        video_pan_origin.x = mp.get_property("video-pan-x")
        video_pan_origin.y = mp.get_property("video-pan-y")
        local idle = function()
            if moved then
                local mX, mY = mp.get_mouse_pos()
                local pX = video_pan_origin.x + (mX - mouse_pos_origin.x) / video_dimensions.size.w
                local pY = video_pan_origin.y + (mY - mouse_pos_origin.y) / video_dimensions.size.h
                mp.command("no-osd set video-pan-x " .. clamp(pX, -3, 3) .. "; no-osd set video-pan-y " .. clamp(pY, -3, 3))
                video_dimensions_stale = true
                moved = false
            end
        end
        mp.register_idle(idle)
        add_mouse_move_callback("drag-to-pan", function() moved = true end)
        cleanup = function()
            remove_mouse_move_callback("drag-to-pan")
            mp.unregister_idle(idle)
        end
    end
end

function pan_follows_cursor_handler(table)
    if cleanup then
        cleanup()
        cleanup = nil
    end
    if table["event"] == "down" then
        local video_dimensions = get_video_dimensions()
        if not video_dimensions then return end
        local window_w, window_h = mp.get_osd_size()
        local moved = true
        local idle = function()
            if moved then
                local mX, mY = mp.get_mouse_pos()
                local x = math.min(1, math.max(- 2 * mX / window_w + 1, -1))
                local y = math.min(1, math.max(- 2 * mY / window_h + 1, -1))
                local command = ""
                local margin, move_full = opts.pan_follows_cursor_margin, opts.pan_follows_cursor_move_if_full_view
                if (not move_full and window_w < video_dimensions.size.w) then
                    command = command .. "no-osd set video-pan-x " .. clamp(x * (video_dimensions.size.w - window_w + 2 * margin) / (2 * video_dimensions.size.w), -3, 3) .. ";"
                elseif mp.get_property_number("video-pan-x") ~= 0 then
                    command = command .. "no-osd set video-pan-x " .. "0;"
                end
                if (not move_full and window_h < video_dimensions.size.h) then
                    command = command .. "no-osd set video-pan-y " .. clamp(y * (video_dimensions.size.h - window_h + 2 * margin) / (2 * video_dimensions.size.h), -3, 3) .. ";"
                elseif mp.get_property_number("video-pan-y") ~= 0 then
                    command = command .. "no-osd set video-pan-y " .. "0;"
                end
                if command ~= "" then
                    mp.command(command)
                    video_dimensions_stale = true
                end
                moved = false
            end
        end
        mp.register_idle(idle)
        add_mouse_move_callback("pan-follows-cursor", function() moved = true end)
        cleanup = function()
            remove_mouse_move_callback("pan-follows-cursor")
            mp.unregister_idle(idle)
        end
    end
end

function cursor_centric_zoom_handler(amt)
    local zoom_inc = tonumber(amt)
    if not zoom_inc or zoom_inc == 0 then return end
    local video_dimensions = get_video_dimensions()
    if not video_dimensions then return end
    local mouse_pos_origin, video_pan_origin = {}, {}
    mouse_pos_origin.x, mouse_pos_origin.y = mp.get_mouse_pos()
    video_pan_origin.x = mp.get_property("video-pan-x")
    video_pan_origin.y = mp.get_property("video-pan-y")
    local zoom_origin = mp.get_property("video-zoom")
    -- how far the cursor is form the middle of the video (in percentage)
    local rx = (video_dimensions.top_left.x + video_dimensions.size.w / 2 - mouse_pos_origin.x) / (video_dimensions.size.w / 2)
    local ry = (video_dimensions.top_left.y + video_dimensions.size.h / 2 - mouse_pos_origin.y) / (video_dimensions.size.h / 2)

    -- the size in pixels of the (in|de)crement
    local diffHeight = (2 ^ zoom_inc - 1) * video_dimensions.size.h
    local diffWidth  = (2 ^ zoom_inc - 1) * video_dimensions.size.w
    local newPanX = (video_pan_origin.x * video_dimensions.size.w + rx * diffWidth / 2) / (video_dimensions.size.w + diffWidth)
    local newPanY = (video_pan_origin.y * video_dimensions.size.h + ry * diffHeight / 2) / (video_dimensions.size.h + diffHeight)
    mp.command("no-osd set video-zoom " .. zoom_origin + zoom_inc .. "; no-osd set video-pan-x " .. clamp(newPanX, -3, 3) .. "; no-osd set video-pan-y " .. clamp(newPanY, -3, 3))
    video_dimensions_stale = true
end

function align_border(x, y)
    local video_dimensions = get_video_dimensions()
    if not video_dimensions then return end
    local window_w, window_h = mp.get_osd_size()
    local x, y = tonumber(x), tonumber(y)
    local command = ""
    if x then
        command = command .. "no-osd set video-pan-x " .. clamp(x * (video_dimensions.size.w - window_w) / (2 * video_dimensions.size.w), -3, 3) .. ";"
    end
    if y then
        command = command .. "no-osd set video-pan-y " .. clamp(y * (video_dimensions.size.h - window_h) / (2 * video_dimensions.size.h), -3, 3) .. ";"
    end
    if command ~= "" then
        mp.command(command)
        video_dimensions_stale = true
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
        local video_dimensions = get_video_dimensions()
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
    video_dimensions_stale = true
end

function rotate_video(amt)
    local rot = mp.get_property_number("video-rotate")
    rot = (rot + amt) % 360
    mp.set_property_number("video-rotate", rot)
end

function reset_pan_if_visible()
    local video_dimensions = get_video_dimensions()
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

function draw_ass()
    local ww, wh = mp.get_osd_size()
    local merge = function(a, b)
        return b ~= "" and (a .. "\n" .. b) or a
    end
    mp.set_osd_ass(ww, wh, merge(merge(ass.status_line, ass.minimap), ass.ruler))
end

local status_line_enabled = false
local status_line_stale = true

function mark_status_line_stale()
    status_line_stale = true
end

function refresh_status_line()
    if not status_line_stale then return end
    status_line_stale = false
    local path = mp.get_property("path")
    if path == nil or path == "" then
        ass.status_line = ""
        draw_ass()
        return
    end
    local expanded = mp.command_native({ "expand-text", opts.status_line })
    if not expanded then
        msg.warn("Error expanding status line")
        ass.status_line = ""
        draw_ass()
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
    local a = assdraw:ass_new()
    a:new_event()
    a:an(an)
    a:pos(x,y)
    a:append("{\\fs".. opts.status_line_size.. "}{\\bord1.0}")
    a:append(expanded)
    ass.status_line = a.text
    draw_ass()
end

function enable_status_line()
    if status_line_enabled then return end
    status_line_enabled = true
    local start = 0
    while true do
        local s, e, cap = string.find(opts.status_line, "%${[?!]?([%l%d-/]*)", start)
        if not s then break end
        mp.observe_property(cap, nil, mark_status_line_stale)
        start = e
    end
    mp.observe_property("path", nil, mark_status_line_stale)
    mp.observe_property("osd-width", nil, mark_status_line_stale)
    mp.observe_property("osd-height", nil, mark_status_line_stale)
    mp.register_idle(refresh_status_line)
    mark_status_line_stale()
end

function disable_status_line()
    if not status_line_enabled then return end
    status_line_enabled = false
    mp.unobserve_property(mark_status_line_stale)
    mp.unregister_idle(refresh_status_line)
    ass.status_line = ""
    draw_ass()
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

function refresh_minimap()
    local dim = get_video_dimensions()
    if not dim then
        ass.minimap = ""
        draw_ass()
        return
    end
    if _minimap_old_timestamp and dim.timestamp == _minimap_old_timestamp then return end
    _minimap_old_timestamp = dim.timestamp
    local ww, wh = mp.get_osd_size()
    if opts.minimap_hide_when_full_image_in_view then
        if dim.top_left.x >= 0 and
           dim.top_left.y >= 0 and
           dim.bottom_right.x <= ww and
           dim.bottom_right.y <= wh
        then
            ass.minimap = ""
            draw_ass()
            return
        end
    end
    local center = {
        x=opts.minimap_center[1]/100*ww,
        y=opts.minimap_center[2]/100*wh
    }
    local cutoff = {
        x=opts.minimap_max_size[1]/100*ww/2,
        y=opts.minimap_max_size[2]/100*wh/2
    }
    local a = assdraw.ass_new()
    local draw = function(x, y, w, h, opacity, color)
        a:new_event()
        a:pos(center.x, center.y)
        a:append("{\\bord0}")
        a:append("{\\shad0}")
        a:append("{\\c&" .. color .. "&}")
        a:append("{\\2a&HFF}")
        a:append("{\\3a&HFF}")
        a:append("{\\4a&HFF}")
        a:append("{\\1a&H" .. opacity .. "}")
        w=w/2
        h=h/2
        a:draw_start()
        local rounded = {true,true,true,true} -- tl, tr, br, bl
        local x0,y0,x1,y1 = x-w, y-h, x+w, y+h
        if x0 < -cutoff.x then
            x0 = -cutoff.x
            rounded[4] = false
            rounded[1] = false
        end
        if y0 < -cutoff.y then
            y0 = -cutoff.y
            rounded[1] = false
            rounded[2] = false
        end
        if x1 > cutoff.x then
            x1 = cutoff.x
            rounded[2] = false
            rounded[3] = false
        end
        if y1 > cutoff.y then
            y1 = cutoff.y
            rounded[3] = false
            rounded[4] = false
        end

        local r = 3
        local c = 0.551915024494 * r
        if rounded[0] then
            a:move_to(x0 + r, y0)
        else
            a:move_to(x0,y0)
        end
        if rounded[1] then
            a:line_to(x1 - r, y0)
            a:bezier_curve(x1 - r + c, y0, x1, y0 + r - c, x1, y0 + r)
        else
            a:line_to(x1, y0)
        end
        if rounded[2] then
            a:line_to(x1, y1 - r)
            a:bezier_curve(x1, y1 - r + c, x1 - r + c, y1, x1 - r, y1)
        else
            a:line_to(x1, y1)
        end
        if rounded[3] then
            a:line_to(x0 + r, y1)
            a:bezier_curve(x0 + r - c, y1, x0, y1 - r + c, x0, y1 - r)
        else
            a:line_to(x0, y1)
        end
        if rounded[4] then
            a:line_to(x0, y0 + r)
            a:bezier_curve(x0, y0 + r - c, x0 + r - c, y0, x0 + r, y0)
        else
            a:line_to(x0, y0)
        end
        a:draw_stop()
    end
    local image = function()
        draw((dim.top_left.x + dim.size.w/2 - ww/2) / opts.minimap_scale,
             (dim.top_left.y + dim.size.h/2 - wh/2) / opts.minimap_scale,
             dim.size.w / opts.minimap_scale,
             dim.size.h / opts.minimap_scale,
             opts.minimap_image_opacity,
             opts.minimap_image_color)
    end
    local view = function()
        draw(0,
             0,
             ww / opts.minimap_scale,
             wh / opts.minimap_scale,
             opts.minimap_view_opacity,
             opts.minimap_view_color)
    end
    if opts.minimap_view_above_image then
        image()
        view()
    else
        view()
        image()
    end
    ass.minimap = a.text
    draw_ass()
end

local minimap_enabled = false

function enable_minimap()
    if minimap_enabled then return end
    minimap_enabled = true
    mp.register_idle(refresh_minimap)
end

function disable_minimap()
    if not minimap_enabled then return end
    minimap_enabled = false
    ass.minimap = a.text
    draw_ass()
    mp.unregister_idle(refresh_minimap)
end

if opts.minimap_enabled then
    enable_minimap()
end

local ruler_state = 0 -- {0,1,2,3} = {inactive,setting first point,setting second point,done}
local ruler_first_point = nil -- in video space coordinates
local ruler_second_point = nil -- in video space coordinates

function cursor_video_space()
    local dim = get_video_dimensions()
    if not dim then return nil end
    local mx, my = mp.get_mouse_pos()
    local ret = {}
    ret.x = (mx - dim.top_left.x) / dim.ratios.w
    ret.y = (my - dim.top_left.y) / dim.ratios.h
    return ret
end
function video_space_to_screen(point)
    local dim = get_video_dimensions()
    if not dim then return nil end
    local ret = {}
    ret.x = point.x * dim.ratios.w + dim.top_left.x
    ret.y = point.y * dim.ratios.h + dim.top_left.y
    return ret
end

function refresh_ruler()
    local dim = get_video_dimensions()
    if not dim then
        ass.ruler = ""
        draw_ass()
        return
    end

    local line_start = {}
    local line_end = {}
    if ruler_second_point then
        line_start.image = ruler_first_point
        line_start.screen = video_space_to_screen(ruler_first_point)
        line_end.image = ruler_second_point
        line_end.screen = video_space_to_screen(ruler_second_point)
    elseif ruler_first_point then
        line_start.image = ruler_first_point
        line_start.screen = video_space_to_screen(ruler_first_point)
        line_end.image = cursor_video_space()
        line_end.screen = {}
        line_end.screen.x, line_end.screen.y = mp.get_mouse_pos()
    else
        local mx, my = mp.get_mouse_pos()
        line_start.image = cursor_video_space()
        line_start.screen = {}
        line_start.screen.x, line_start.screen.y = mp.get_mouse_pos()
        line_end = line_start
    end
    local distinct = (math.abs(line_start.screen.x - line_end.screen.x) >= 1
                   or math.abs(line_start.screen.y - line_end.screen.y) >= 1)

    local a = assdraw:ass_new()
    local draw_setup = function(bord)
        a:new_event()
        a:pos(0,0)
        a:append("{\\bord" .. bord .. "}")
        a:append("{\\shad0}")
        local r = opts.ruler_line_color
        a:append("{\\3c&H".. r .. r .. r .. "&}")
        a:append("{\\1a&HFF}")
        a:append("{\\2a&HFF}")
        a:append("{\\3a&H00}")
        a:append("{\\4a&HFF}")
        a:draw_start()
    end
    local dot = function(pos, size)
        draw_setup(size)
        a:move_to(pos.x, pos.y-0.5)
        a:line_to(pos.x, pos.y+0.5)
    end
    local line = function(from, to, size)
        draw_setup(size)
        a:move_to(from.x, from.y)
        a:line_to(to.x, to.y)
    end
    if distinct then
        dot(line_start.screen, opts.ruler_dots_radius)
        line(line_start.screen, line_end.screen, opts.ruler_line_width)
        dot(line_end.screen, opts.ruler_dots_radius)
    else
        dot(line_start.screen, opts.ruler_dots_radius)
    end

    local line_info = function()
        if not opts.ruler_show_distance then return end
        a:new_event()
        a:append("{\\fs36}{\\bord1}")
        a:pos((line_start.screen.x + line_end.screen.x) / 2, (line_start.screen.y + line_end.screen.y) / 2)
        local an = 1
        if line_start.image.x < line_end.image.x then an = an + 2 end
        if line_start.image.y < line_end.image.y then an = an + 6 end
        a:an(an)
        local image = math.sqrt(math.pow(line_start.image.x - line_end.image.x, 2) + math.pow(line_start.image.y - line_end.image.y, 2))
        local screen = math.sqrt(math.pow(line_start.screen.x - line_end.screen.x, 2) + math.pow(line_start.screen.y - line_end.screen.y, 2))
        if opts.ruler_coordinates_space == "both" then
            a:append(string.format("image: %.1f\\Nscreen: %.1f", image, screen))
        elseif opts.ruler_coordinates_space == "image" then
            a:append(string.format("%.1f", image))
        elseif opts.ruler_coordinates_space == "window" then
            a:append(string.format("%.1f", screen))
        end
    end
    local dot_info = function(pos, opposite)
        if not opts.ruler_show_coordinates then return end
        a:new_event()
        a:append("{\\fs" .. opts.ruler_font_size .."}{\\bord1}")
        a:pos(pos.screen.x, pos.screen.y)
        local an
        if distinct then
            an = 1
            if line_start.image.x > line_end.image.x then an = an + 2 end
            if line_start.image.y < line_end.image.y then an = an + 6 end
        else
            an = 7
        end
        if opposite then
            an = 9 + 1 - an
        end
        a:an(an)
        if opts.ruler_coordinates_space == "both" then
            a:append(string.format("image: %.1f, %.1f\\Nscreen: %i, %i",
                pos.image.x, pos.image.y, pos.screen.x, pos.screen.y))
        elseif opts.ruler_coordinates_space == "image" then
            a:append(string.format("%.1f, %.1f", pos.image.x, pos.image.y))
        elseif opts.ruler_coordinates_space == "window" then
            a:append(string.format("%i, %i", pos.screen.x, pos.screen.y))
        end
    end
    dot_info(line_start, true)
    if distinct then
        line_info()
        dot_info(line_end, false)
    end
    if distinct and opts.ruler_show_angles ~= "no" then
        local dist = 50
        local pos_from_angle = function(mult, angle)
            return {
                x = line_start.screen.x + mult * dist * math.cos(angle),
                y = line_start.screen.y + mult * dist * math.sin(angle)
            }
        end
        local extended = {x=line_start.screen.x, y=line_start.screen.y}
        if line_end.screen.x > line_start.screen.x then
            extended.x = extended.x + dist
        else
            extended.x = extended.x - dist
        end
        line(line_start.screen, extended, math.max(0, opts.ruler_line_width-0.5))
        local angle = math.atan(math.abs(line_start.image.y - line_end.image.y) / math.abs(line_start.image.x - line_end.image.x))
        local fix_angle
        local an
        if line_end.image.y < line_start.image.y and line_end.image.x > line_start.image.x then
            -- upper-right
            an = 4
            fix_angle = function(angle) return - angle end
        elseif line_end.image.y < line_start.image.y then
            -- upper-left
            an = 6
            fix_angle = function(angle) return math.pi + angle end
        elseif line_end.image.x < line_start.image.x then
            -- bottom-left
            an = 6
            fix_angle = function(angle) return math.pi - angle end
        else
            -- bottom-right
            an = 4
            fix_angle = function(angle) return angle end
        end
        -- should implement this https://math.stackexchange.com/questions/873224/calculate-control-points-of-cubic-bezier-curve-approximating-a-part-of-a-circle
        local cp1 = pos_from_angle(1, fix_angle(angle*1/4))
        local cp2 = pos_from_angle(1, fix_angle(angle*3/4))
        local p2 = pos_from_angle(1, fix_angle(angle))
        a:bezier_curve(cp1.x, cp1.y, cp2.x, cp2.y, p2.x, p2.y)

        a:new_event()
        a:append("{\\fs" .. opts.ruler_font_size .."}{\\bord1}")
        local text_pos = pos_from_angle(1.1, fix_angle(angle*2/3)) -- you'd think /2 would make more sense, but *2/3  looks better
        a:pos(text_pos.x, text_pos.y)
        a:an(an)
        if opts.ruler_show_angles == "both" then
            a:append(string.format("%.2f\\N%.1f°", angle, angle / math.pi * 180))
        elseif opts.ruler_show_angles == "degrees" then
            a:append(string.format("%.1f°", angle / math.pi * 180))
        elseif opts.ruler_show_angles == "radians" then
            a:append(string.format("%.2f", angle))
        end
    end

    ass.ruler = a.text
    draw_ass()
end

function ruler_next()
    if ruler_state == 0 then
        mp.register_idle(refresh_ruler)
        add_mouse_move_callback("ruler", function() end) -- only used to get an idle event on mouse move
        for _,key in ipairs(opts.ruler_confirm_bindings) do
            mp.add_forced_key_binding(key, "ruler-next-" .. key, ruler_next)
        end
        for _,key in ipairs(opts.ruler_exit_bindings) do
            mp.add_forced_key_binding(key, "ruler-stop-" .. key, ruler_stop)
        end
        ruler_state = 1
        if opts.ruler_set_first_point_on_begin then
            ruler_next()
        end
    elseif ruler_state == 1 then
        ruler_first_point = cursor_video_space()
        ruler_state = 2
    elseif ruler_state == 2 then
        ruler_state = 3
        ruler_second_point = cursor_video_space()
        if opts.ruler_clear_on_second_point_set then
            ruler_next()
        end
    else
        ruler_stop()
    end
end

function ruler_stop()
    if ruler_state == 0 then return end
    mp.unregister_idle(refresh_ruler)
    for _,key in ipairs(opts.ruler_confirm_bindings) do
        mp.remove_key_binding("ruler-next-" .. key)
    end
    for _,key in ipairs(opts.ruler_exit_bindings) do
        mp.remove_key_binding("ruler-stop-" .. key)
    end
    remove_mouse_move_callback("ruler")
    ruler_state = 0
    ruler_first_point = nil
    ruler_second_point = nil
    ass.ruler = ""
    draw_ass()
end

mp.add_key_binding(nil, "drag-to-pan", drag_to_pan_handler, {complex = true})
mp.add_key_binding(nil, "pan-follows-cursor", pan_follows_cursor_handler, {complex = true})
mp.add_key_binding(nil, "cursor-centric-zoom", cursor_centric_zoom_handler)
mp.add_key_binding(nil, "align-border", align_border)
mp.add_key_binding(nil, "pan-image", pan_image)
mp.add_key_binding(nil, "rotate-video", rotate_video)
mp.add_key_binding(nil, "reset-pan-if-visible", reset_pan_if_visible)
mp.add_key_binding(nil, "force-print-filename", force_print_filename)

mp.add_key_binding(nil, "ruler", ruler_next)

mp.add_key_binding(nil, "enable-status-line", enable_status_line)
mp.add_key_binding(nil, "disable-status-line", disable_status_line)
mp.add_key_binding(nil, "toggle-status-line", function() if status_line_enabled then disable_status_line() else enable_status_line() end end)

mp.add_key_binding(nil, "enable-minimap", enable_minimap)
mp.add_key_binding(nil, "disable-minimap", disable_minimap)
mp.add_key_binding(nil, "toggle-minimap", function() if minimap_enabled then disable_minimap() else enable_minimap() end end)
