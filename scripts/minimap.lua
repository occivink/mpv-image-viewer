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
(require 'mp.options').read_options(opts)

function process(input)
    local ret = {}
    for str in string.gmatch(input, "([^,]+)") do
        ret[#ret + 1] = tonumber(str)
    end
    return ret
end
opts.center=process(opts.center)
opts.max_size=process(opts.max_size)

local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local video_dimensions_stale = true

function draw_ass(ass)
    local ww, wh = mp.get_osd_size()
    mp.set_osd_ass(ww, wh, ass)
end

function refresh_minimap()
    if not video_dimensions_stale then return end
    video_dimensions_stale = false

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

    local center = {
        opts.center[1] * 0.01 * ww,
        opts.center[2] * 0.01 * wh
    }
    local cutoff = {
        opts.max_size[1] * 0.01 * ww * 0.5,
        opts.max_size[2] * 0.01 * wh * 0.5
    }
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

local active = false

function enable_minimap()
    if active then return end
    active = true
    video_dimensions_stale = true
    mp.observe_property("osd-dimensions", nil, function() video_dimensions_stale = true end)
    mp.register_idle(refresh_minimap)
end

function disable_minimap()
    if not active then return end
    active = false
    draw_ass("")
    mp.unobserve_property("osd-dimensions")
    mp.unregister_idle(refresh_minimap)
end

function toggle()
    if active then
        disable_minimap()
    else
        enable_minimap()
    end
end

if opts.enabled then
    enable_minimap()
end

mp.add_key_binding(nil, "minimap-enable", enable)
mp.add_key_binding(nil, "minimap-disable", disable)
mp.add_key_binding(nil, "minimap-toggle", toggle)
