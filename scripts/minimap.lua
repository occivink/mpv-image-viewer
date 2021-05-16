local opts = {
    enabled = true,
    center = "92,92",
    scale = 12,
    max_size = "16,16",
    image_opacity = "88",
    image_color = "BBBBBB",
    view_opacity = "BB",
    view_color = "222222",
    view_above_image = true,
    hide_when_full_image_in_view = true,
}

local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'
local options = require 'mp.options'

options.read_options(opts, nil, function(c)
    if c["enabled"] then
        if opts.enabled then
            enable()
        else
            disable()
        end
    end
    mark_stale()
end)

function split_comma(input)
    local ret = {}
    for str in string.gmatch(input, "([^,]+)") do
        ret[#ret + 1] = tonumber(str)
    end
    return ret
end

local active = false
local refresh = true

function draw_ass(ass)
    local ww, wh = mp.get_osd_size()
    mp.set_osd_ass(ww, wh, ass)
end

function mark_stale()
    refresh = true
end

function refresh_minimap()
    if not refresh then return end
    refresh = false

    local dim = mp.get_property_native("osd-dimensions")
    if not dim then
        draw_ass("")
        return
    end
    local ww, wh = dim.w, dim.h

    if not (ww > 0 and wh > 0) then return end
    if opts.hide_when_full_image_in_view then
        if dim.mt >= 0 and dim.mb >= 0 and dim.ml >= 0 and dim.mr >= 0 then
            draw_ass("")
            return
        end
    end

    local center = split_comma(opts.center)
    center[1] = center[1] * 0.01 * ww
    center[2] = center[2] * 0.01 * wh
    local cutoff = split_comma(opts.max_size)
    cutoff[1] = cutoff[1] * 0.01 * ww * 0.5
    cutoff[2] = cutoff[2] * 0.01 * wh * 0.5

    local a = assdraw.ass_new()
    local draw = function(x, y, w, h, opacity, color)
        a:new_event()
        a:pos(center[1], center[2])
        a:append("{\\bord0}")
        a:append("{\\shad0}")
        a:append("{\\c&" .. color .. "&}")
        a:append("{\\2a&HFF}")
        a:append("{\\3a&HFF}")
        a:append("{\\4a&HFF}")
        a:append("{\\1a&H" .. opacity .. "}")
        w = w * 0.5
        h = h * 0.5
        a:draw_start()
        local rounded = {true,true,true,true} -- tl, tr, br, bl
        local x0,y0,x1,y1 = x-w, y-h, x+w, y+h
        if x0 < -cutoff[1] then
            x0 = -cutoff[1]
            rounded[4] = false
            rounded[1] = false
        end
        if y0 < -cutoff[2] then
            y0 = -cutoff[2]
            rounded[1] = false
            rounded[2] = false
        end
        if x1 > cutoff[1] then
            x1 = cutoff[1]
            rounded[2] = false
            rounded[3] = false
        end
        if y1 > cutoff[2] then
            y1 = cutoff[2]
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
        draw((dim.ml/2 - dim.mr/2) / opts.scale,
             (dim.mt/2 - dim.mb/2) / opts.scale,
             (ww - dim.ml - dim.mr) / opts.scale,
             (wh - dim.mt - dim.mb) / opts.scale,
             opts.image_opacity,
             opts.image_color)
    end
    local view = function()
        draw(0,
             0,
             ww / opts.scale,
             wh / opts.scale,
             opts.view_opacity,
             opts.view_color)
    end
    if opts.view_above_image then
        image()
        view()
    else
        view()
        image()
    end
    draw_ass(a.text)
end

function enable()
    if active then return end
    active = true
    mp.observe_property("osd-dimensions", nil, mark_stale)
    mp.register_idle(refresh_minimap)
    mark_stale()
end

function disable()
    if not active then return end
    active = false
    mp.unobserve_property(mark_stale)
    mp.unregister_idle(refresh_minimap)
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

mp.add_key_binding(nil, "minimap-enable", enable)
mp.add_key_binding(nil, "minimap-disable", disable)
mp.add_key_binding(nil, "minimap-toggle", toggle)
