local opts = {
    drag_to_pan_margin = 50,
    drag_to_pan_move_if_full_view=false,

    pan_follows_cursor_margin = 50,

    cursor_centric_zoom_margin = 50,
    cursor_centric_zoom_auto_center = true,
    cursor_centric_zoom_dezoom_if_full_view = false,
}
local options = require 'mp.options'
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

options.read_options(opts, nil, function() end)

function clamp(value, low, high)
    if value <= low then
        return low
    elseif value >= high then
        return high
    else
        return value
    end
end


local cleanup = nil -- function set up by drag-to-pan/pan-follows cursor and must be called to clean lingering state

function drag_to_pan_handler(table)
    if cleanup then
        cleanup()
        cleanup = nil
    end
    if table["event"] == "down" then
        local dim = mp.get_property_native("osd-dimensions")
        if not dim then return end
        local mouse_pos_origin, video_pan_origin = {}, {}
        local moved = false
        mouse_pos_origin[1], mouse_pos_origin[2] = mp.get_mouse_pos()
        video_pan_origin[1] = mp.get_property_number("video-pan-x")
        video_pan_origin[2] = mp.get_property_number("video-pan-y")
        local video_size = { dim.w - dim.ml - dim.mr, dim.h - dim.mt - dim.mb }
        local margin = opts.drag_to_pan_margin
        local move_up = true
        local move_lateral = true
        if not opts.drag_to_pan_move_if_full_view then
            if dim.ml >= 0 and dim.mr >= 0 then
                move_lateral = false
            end
            if dim.mt >= 0 and dim.mb >= 0 then
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
                    pX = video_pan_origin[1] + (mX - mouse_pos_origin[1]) / video_size[1]
                    if 2 * margin > dim.ml + dim.mr then
                        pX = clamp(pX,
                            (-margin + dim.w / 2) / video_size[1] - 0.5,
                            (margin - dim.w / 2) / video_size[1] + 0.5)
                    else
                        pX = clamp(pX,
                            (margin - dim.w / 2) / video_size[1] + 0.5,
                            (-margin + dim.w / 2) / video_size[1] - 0.5)
                    end
                end
                if move_up then
                    pY = video_pan_origin[2] + (mY - mouse_pos_origin[2]) / video_size[2]
                    if 2 * margin > dim.mt + dim.mb then
                        pY = clamp(pY,
                            (-margin + dim.h / 2) / video_size[2] - 0.5,
                            (margin - dim.h / 2) / video_size[2] + 0.5)
                    else
                        pY = clamp(pY,
                            (margin - dim.h / 2) / video_size[2] + 0.5,
                            (-margin + dim.h / 2) / video_size[2] - 0.5)
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
        local dim = mp.get_property_native("osd-dimensions")
        if not dim then return end
        local video_size = { dim.w - dim.ml - dim.mr, dim.h - dim.mt - dim.mb }
        local moved = true
        local idle = function()
            if moved then
                local mX, mY = mp.get_mouse_pos()
                local x = math.min(1, math.max(- 2 * mX / dim.w + 1, -1))
                local y = math.min(1, math.max(- 2 * mY / dim.h + 1, -1))
                local command = ""
                local margin = opts.pan_follows_cursor_margin
                if dim.ml + dim.mr < 0 then
                    command = command .. "no-osd set video-pan-x " .. clamp(x * (2 * margin - dim.ml - dim.mr) / (2 * video_size[1]), -3, 3) .. ";"
                elseif mp.get_property_number("video-pan-x") ~= 0 then
                    command = command .. "no-osd set video-pan-x " .. "0;"
                end
                if dim.mt + dim.mb < 0 then
                    command = command .. "no-osd set video-pan-y " .. clamp(y * (2 * margin - dim.mt - dim.mb) / (2 * video_size[2]), -3, 3) .. ";"
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
    local dim = mp.get_property_native("osd-dimensions")
    if not dim then return end

    local margin = opts.cursor_centric_zoom_margin

    local video_size = { dim.w - dim.ml - dim.mr, dim.h - dim.mt - dim.mb }

    -- the size in pixels of the (in|de)crement
    local diff_width  = (2 ^ zoom_inc - 1) * video_size[1]
    local diff_height = (2 ^ zoom_inc - 1) * video_size[2]
    if not opts.cursor_centric_zoom_dezoom_if_full_view and
        zoom_inc < 0 and
        video_size[1] + diff_width + 2 * margin <= dim.w and
        video_size[2] + diff_height + 2 * margin <= dim.h
    then
        -- the zoom decrement is too much, reduce it such that the full image is visible, no more, no less
        -- in addition, this should take care of trying too zoom out while everything is already visible
        local new_zoom_inc_x = math.log((dim.w - 2 * margin) / video_size[1]) / math.log(2)
        local new_zoom_inc_y = math.log((dim.h - 2 * margin) / video_size[2]) / math.log(2)
        local new_zoom_inc = math.min(0, math.min(new_zoom_inc_x, new_zoom_inc_y))
        zoom_inc = new_zoom_inc
        diff_width  = (2 ^ zoom_inc - 1) * video_size[1]
        diff_height = (2 ^ zoom_inc - 1) * video_size[2]
    end
    local new_width = video_size[1] + diff_width
    local new_height = video_size[2] + diff_height

    local mouse_pos_origin = {}
    mouse_pos_origin[1], mouse_pos_origin[2] = mp.get_mouse_pos()
    local new_pan_x, new_pan_y

    -- some additional constraints:
    -- if image can be fully visible (in either direction), set pan to 0
    -- if border would show on either side, then prefer adjusting the pan even if not cursor-centric
    local auto_c = opts.cursor_centric_zoom_auto_center
    if auto_c and new_width <= dim.w then
        new_pan_x = 0
    else
        local pan_x = mp.get_property("video-pan-x")
        local rx = (dim.ml + video_size[1] / 2 - mouse_pos_origin[1]) / (video_size[1] / 2)
        new_pan_x = (pan_x * video_size[1] + rx * diff_width / 2) / new_width
        if auto_c then
            new_pan_x = clamp(new_pan_x, (dim.w - 2 * margin) / (2 * new_width) - 0.5, - (dim.w - 2 * margin) / (2 * new_width) + 0.5)
        end
    end

    if auto_c and new_height <= dim.h then
        new_pan_y = 0
    else
        local pan_y = mp.get_property("video-pan-y")
        local ry = (dim.mt + video_size[2] / 2 - mouse_pos_origin[2]) / (video_size[2] / 2)
        new_pan_y = (pan_y * video_size[2] + ry * diff_height / 2) / new_height
        if auto_c then
            new_pan_y = clamp(new_pan_y, (dim.h - 2 * margin) / (2 * new_height) - 0.5, - (dim.h - 2 * margin) / (2 * new_height) + 0.5)
        end
    end

    local zoom_origin = mp.get_property("video-zoom")
    mp.command("no-osd set video-zoom " .. zoom_origin + zoom_inc .. "; no-osd set video-pan-x " .. clamp(new_pan_x, -3, 3) .. "; no-osd set video-pan-y " .. clamp(new_pan_y, -3, 3))
end

function align_border(x, y)
    local dim = mp.get_property_native("osd-dimensions")
    if not dim then return end
    local video_size = { dim.w - dim.ml - dim.mr, dim.h - dim.mt - dim.mb }
    local x, y = tonumber(x), tonumber(y)
    local command = ""
    if x then
        command = command .. "no-osd set video-pan-x " .. clamp(- x * (dim.ml + dim.mr) / (2 * video_size[1]), -3, 3) .. ";"
    end
    if y then
        command = command .. "no-osd set video-pan-y " .. clamp(- y * (dim.mt + dim.mb) / (2 * video_size[2]), -3, 3) .. ";"
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
        local dim = mp.get_property_native("osd-dimensions")
        if not dim then return end
        local margin =
            (axis == "x" and amount > 0) and dim.ml
            or (axis == "x" and amount < 0) and dim.mr
            or (amount > 0) and dim.mt
            or (amount < 0) and dim.mb
        local vid_size = (axis == "x") and (dim.w - dim.ml - dim.mr) or (dim.h - dim.mt - dim.mb)
        local pixels_moved = math.abs(amount) * vid_size
        -- the margin is already visible, no point going further
        if margin >= 0 then
            return
        elseif margin + pixels_moved > 0 then
            amount = -(math.abs(amount) / amount) * margin / vid_size
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
    local dim = mp.get_property_native("osd-dimensions")
    if not dim then return end
    local command = ""
    if (dim.ml + dim.mr >= 0) then
        command = command .. "no-osd set video-pan-x 0" .. ";"
    end
    if (dim.mt + dim.mb >= 0) then
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
