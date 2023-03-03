local opts = {
    enabled = true,
    center = "92,92",
    scale = .1,
    max_size = "16,16",
    image_opacity = "88",
    image_color = "BBBBBB",
    view_opacity = "BB",
    view_color = "222222",
    view_above_image = true,
    hide_when_full_image_in_view = true,
    image_fixed_view_moves = true,
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
    local max_size = split_comma(opts.max_size)
    max_size[1] = max_size[1] * 0.01 * ww
    max_size[2] = max_size[2] * 0.01 * wh

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
        local x0,y0,x1,y1 = x-w, y-h, x+w, y+h
        local cutoff = {max_size[1] * .5, max_size[2] * .5}
        x0 = math.max(x0, -cutoff[1])
        y0 = math.max(y0, -cutoff[2])
        x1 = math.min(x1, cutoff[1])
        y1 = math.min(y1, cutoff[2])
        if x0 > cutoff[1] or x1 < -cutoff[1] or y0 > cutoff[2] or y1 < -cutoff[2] then return end
        w = x1 - x0
        h = y1 - y0

        a:move_to(x0,y0)
        a:line_to(x1, y0)
        a:line_to(x1, y1)
        a:line_to(x0, y1)
        a:line_to(x0, y0)
        a:draw_stop()

        a:new_event()
        a:pos(center[1], center[2])
        a:append("{\\bord0}")
        a:append("{\\shad0}")
        a:append("{\\c&" .. "ffffff" .. "&}")
        a:append("{\\2a&HFF}")
        a:append("{\\3a&HFF}")
        a:append("{\\4a&HFF}")
        a:append("{\\1a&H" .. "22" .. "}")
        a:draw_start()
        local draw_line = function(x, y, horiz)
            bord = 1 * .5
            if horiz then
                a:move_to(x - bord    , y + bord)
                a:line_to(x + w + bord, y + bord)
                a:line_to(x + w + bord, y - bord)
                a:line_to(x - bord    , y - bord)
                a:line_to(x - bord    , y + bord)
            else
                a:move_to(x - bord, y - bord)
                a:line_to(x - bord, y + h + bord)
                a:line_to(x + bord, y + h + bord)
                a:line_to(x + bord, y - bord)
                a:line_to(x - bord, y - bord)
            end
        end
        if x0 > -cutoff[1] and x0 < cutoff[1] then draw_line(x0, y0, false) end
        if y0 > -cutoff[2] and y0 < cutoff[2] then draw_line(x0, y0, true) end
        if x1 > -cutoff[1] and x1 < cutoff[1] then draw_line(x1, y0, false) end
        if y1 > -cutoff[2] and y1 < cutoff[2] then draw_line(x0, y1, true) end
        a:draw_stop()
    end
    local image, view
    local image_width = (ww - dim.ml - dim.mr)
    local image_height = (wh - dim.mt - dim.mb)
    if opts.image_fixed_view_moves then
        local scale = math.min((1 - opts.scale) * max_size[1] / image_width, 
                               (1 - opts.scale) * max_size[2] / image_height)
        image = function()
            draw(0,
                 0,
                 image_width * scale,
                 image_height * scale,
                 opts.image_opacity,
                 opts.image_color)
        end
        view = function()
            draw(-(dim.ml/2 - dim.mr/2) * scale,
                 -(dim.mt/2 - dim.mb/2) * scale,
                 ww * scale,
                 wh * scale,
                 opts.view_opacity,
                 opts.view_color)
        end
    else
        image = function()
            draw(image_width / opts.scale,
                 image_height / opts.scale,
                 (ww - dim.ml - dim.mr) / opts.scale,
                 (wh - dim.mt - dim.mb) / opts.scale,
                 opts.image_opacity,
                 opts.image_color)
        end
        view = function()
            draw(0,
                 0,
                 ww / opts.scale,
                 wh / opts.scale,
                 opts.view_opacity,
                 opts.view_color)
        end
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
