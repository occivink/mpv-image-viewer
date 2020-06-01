local opts = {
    pan_follows_cursor_margin = 50,
    pan_follows_cursor_move_if_full_view = false,

    drag_to_pan_margin = 50,
    drag_to_pan_move_if_full_view = false,
}
(require 'mp.options').read_options(opts)

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

function get_video_dimensions()
    -- this function is very much ripped from video/out/aspect.c in mpv's source
    local video_params = mp.get_property_native("video-out-params")
    if not video_params then
        _video_dimensions = nil
        return nil
    end
    _video_dimensions = {
        top_left = { 0,  0 },
        bottom_right = { 0,  0 },
        size = { 0,  0 },
        ratios = { 0,  0 }, -- by how much the original video got scaled
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
        _video_dimensions.top_left[1], _video_dimensions.bottom_right[1] = split_scaling(window_w, scaled_width, zoom, align_x, pan_x)

        local align_y = mp.get_property_number("video-align-y")
        local pan_y = mp.get_property_number("video-pan-y")
        _video_dimensions.top_left[2], _video_dimensions.bottom_right[2] = split_scaling(window_h,  scaled_height, zoom, align_y, pan_y)
    else
        _video_dimensions.top_left[1] = 0
        _video_dimensions.bottom_right[1] = window_w
        _video_dimensions.top_left[2] = 0
        _video_dimensions.bottom_right[2] = window_h
    end
    _video_dimensions.size[1] = _video_dimensions.bottom_right[1] - _video_dimensions.top_left[1]
    _video_dimensions.size[2] = _video_dimensions.bottom_right[2] - _video_dimensions.top_left[2]
    _video_dimensions.ratios[1] = _video_dimensions.size[1] / w
    _video_dimensions.ratios[2] = _video_dimensions.size[2] / h
    return _video_dimensions
end

local cleanup = nil -- function set up by drag-to-pan/pan-follows cursor and must be called to clean lingering state

function drag_to_pan_handler(table)
    if cleanup then
        cleanup()
        cleanup = nil
    end
    if table["event"] == "down" then
        local video_dimensions = get_video_dimensions()
        if not video_dimensions then return end
        local window_w, window_h = mp.get_osd_size()
        local mouse_pos_origin, video_pan_origin = {}, {}
        local moved = false
        mouse_pos_origin[1], mouse_pos_origin[2] = mp.get_mouse_pos()
        video_pan_origin[1] = mp.get_property_number("video-pan-x")
        video_pan_origin[2] = mp.get_property_number("video-pan-y")
        local margin = opts.drag_to_pan_margin
        local move_up = true
        local move_lateral = true
        if not opts.drag_to_pan_move_if_full_view then
            if video_dimensions.size[1] <= window_w then
                move_lateral = false
            end
            if video_dimensions.size[2] <= window_h then
                move_up = false
            end
        end
        if not move_up and not move_lateral then return end
        local idle = function()
            if moved then
                local mX, mY = mp.get_mouse_pos()
                local pX = video_pan_origin[1]
                local pY = video_pan_origin[2]
                if move_lateral then
                    pX = video_pan_origin[1] + (mX - mouse_pos_origin[1]) / video_dimensions.size[1]
                    if video_dimensions.size[1] + 2 * margin > window_w then
                        pX = clamp(pX,
                            (-margin + window_w / 2) / video_dimensions.size[1] - 0.5,
                            (margin - window_w / 2) / video_dimensions.size[1] + 0.5)
                    else
                        pX = clamp(pX,
                            (margin - window_w / 2) / video_dimensions.size[1] + 0.5,
                            (-margin + window_w / 2) / video_dimensions.size[1] - 0.5)
                    end
                end
                if move_up then
                    pY = video_pan_origin[2] + (mY - mouse_pos_origin[2]) / video_dimensions.size[2]
                    if video_dimensions.size[2] + 2 * margin > window_h then
                        pY = clamp(pY,
                            (-margin + window_h / 2) / video_dimensions.size[2] - 0.5,
                            (margin - window_h / 2) / video_dimensions.size[2] + 0.5)
                    else
                        pY = clamp(pY,
                            (margin - window_h / 2) / video_dimensions.size[2] + 0.5,
                            (-margin + window_h / 2) / video_dimensions.size[2] - 0.5)
                    end
                end
                mp.command("no-osd set video-pan-x " .. clamp(pX, -3, 3) .. "; no-osd set video-pan-y " .. clamp(pY, -3, 3))
                moved = false
            end
        end
        mp.register_idle(idle)
        mp.add_forced_key_binding("mouse_move", "image-viewer-mouse-move", function() moved = true end)
        cleanup = function()
            mp.remove_key_binding("image-viewer-mouse-move")
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
                if (not move_full and window_w < video_dimensions.size[1]) then
                    command = command .. "no-osd set video-pan-x " .. clamp(x * (video_dimensions.size[1] - window_w + 2 * margin) / (2 * video_dimensions.size[1]), -3, 3) .. ";"
                elseif mp.get_property_number("video-pan-x") ~= 0 then
                    command = command .. "no-osd set video-pan-x " .. "0;"
                end
                if (not move_full and window_h < video_dimensions.size[2]) then
                    command = command .. "no-osd set video-pan-y " .. clamp(y * (video_dimensions.size[2] - window_h + 2 * margin) / (2 * video_dimensions.size[2]), -3, 3) .. ";"
                elseif mp.get_property_number("video-pan-y") ~= 0 then
                    command = command .. "no-osd set video-pan-y " .. "0;"
                end
                if command ~= "" then
                    mp.command(command)
                end
                moved = false
            end
        end
        mp.register_idle(idle)
        mp.add_forced_key_binding("mouse_move", "image-viewer-mouse-move", function() moved = true end)
        cleanup = function()
            mp.remove_key_binding("image-viewer-mouse-move")
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
    mouse_pos_origin[1], mouse_pos_origin[2] = mp.get_mouse_pos()
    video_pan_origin[1] = mp.get_property("video-pan-x")
    video_pan_origin[2] = mp.get_property("video-pan-y")
    local zoom_origin = mp.get_property("video-zoom")
    -- how far the cursor is form the middle of the video (in percentage)
    local rx = (video_dimensions.top_left[1] + video_dimensions.size[1] / 2 - mouse_pos_origin[1]) / (video_dimensions.size[1] / 2)
    local ry = (video_dimensions.top_left[2] + video_dimensions.size[2] / 2 - mouse_pos_origin[2]) / (video_dimensions.size[2] / 2)

    -- the size in pixels of the (in|de)crement
    local diffHeight = (2 ^ zoom_inc - 1) * video_dimensions.size[2]
    local diffWidth  = (2 ^ zoom_inc - 1) * video_dimensions.size[1]
    local newPanX = (video_pan_origin[1] * video_dimensions.size[1] + rx * diffWidth / 2) / (video_dimensions.size[1] + diffWidth)
    local newPanY = (video_pan_origin[2] * video_dimensions.size[2] + ry * diffHeight / 2) / (video_dimensions.size[2] + diffHeight)
    mp.command("no-osd set video-zoom " .. zoom_origin + zoom_inc .. "; no-osd set video-pan-x " .. clamp(newPanX, -3, 3) .. "; no-osd set video-pan-y " .. clamp(newPanY, -3, 3))
end

function align_border(x, y)
    local video_dimensions = get_video_dimensions()
    if not video_dimensions then return end
    local window_w, window_h = mp.get_osd_size()
    local x, y = tonumber(x), tonumber(y)
    local command = ""
    if x then
        command = command .. "no-osd set video-pan-x " .. clamp(x * (video_dimensions.size[1] - window_w) / (2 * video_dimensions.size[1]), -3, 3) .. ";"
    end
    if y then
        command = command .. "no-osd set video-pan-y " .. clamp(y * (video_dimensions.size[2] - window_h) / (2 * video_dimensions.size[2]), -3, 3) .. ";"
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
    axis = (axis == "x") and 1 or 2
    if image_constrained == "yes" then
        local video_dimensions = get_video_dimensions()
        if not video_dimensions then return end
        local window = {}
        window[1], window[2] = mp.get_osd_size()
        local pixels_moved = amount * video_dimensions.size[axis]
        -- should somehow refactor this
        if pixels_moved > 0 then
            if window[axis] > video_dimensions.size[axis] then
                if video_dimensions.bottom_right[axis] >= window[axis] then return end
                if video_dimensions.bottom_right[axis] + pixels_moved > window[axis] then
                    amount = (window[axis] - video_dimensions.bottom_right[axis]) / video_dimensions.size[axis]
                end
            else
                if video_dimensions.top_left[axis] >= 0 then return end
                if video_dimensions.top_left[axis] + pixels_moved > 0 then
                    amount = (0 - video_dimensions.top_left[axis]) / video_dimensions.size[axis]
                end
            end
        else
            if window[axis] > video_dimensions.size[axis] then
                if video_dimensions.top_left[axis] <= 0 then return end
                if video_dimensions.top_left[axis] + pixels_moved < 0 then
                    amount = (0 - video_dimensions.top_left[axis]) / video_dimensions.size[axis]
                end
            else
                if video_dimensions.bottom_right[axis] <= window[axis] then return end
                if video_dimensions.bottom_right[axis] + pixels_moved < window[axis] then
                    amount = (window[axis] - video_dimensions.bottom_right[axis]) / video_dimensions.size[axis]
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
    local video_dimensions = get_video_dimensions()
    if not video_dimensions then return end
    local window_w, window_h = mp.get_osd_size()
    local command = ""
    if (window_w >= video_dimensions.size[1]) then
        command = command .. "no-osd set video-pan-x 0" .. ";"
    end
    if (window_h >= video_dimensions.size[2]) then
        command = command .. "no-osd set video-pan-y 0" .. ";"
    end
    if command ~= "" then
        mp.command(command)
    end
end

mp.add_key_binding(nil, "drag-to-pan", drag_to_pan_handler, {complex = true})
mp.add_key_binding(nil, "pan-follows-cursor", pan_follows_cursor_handler, {complex = true})
mp.add_key_binding(nil, "cursor-centric-zoom", cursor_centric_zoom_handler)
mp.add_key_binding(nil, "align-border", align_border)
mp.add_key_binding(nil, "pan-image", pan_image)
mp.add_key_binding(nil, "rotate-video", rotate_video)
mp.add_key_binding(nil, "reset-pan-if-visible", reset_pan_if_visible)
mp.add_key_binding(nil, "force-print-filename", force_print_filename)
