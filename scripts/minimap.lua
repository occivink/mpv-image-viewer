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
        top_left = { 0, 0 },
        bottom_right = { 0, 0 },
        size = { 0, 0 },
        ratios = { 0, 0 }, -- by how much the original video got scaled
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

    if not (_video_dimensions.size[1] > 0 and _video_dimensions.size[2] > 0) then return nil end
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
    mp.observe_property(p, nil, function() video_dimensions_stale = true end)
end
function draw_ass(ass)
    local ww, wh = mp.get_osd_size()
    mp.set_osd_ass(ww, wh, ass)
end

local old_timestamp = -1

function refresh_minimap()
    local dim = get_video_dimensions()
    if not dim then
        draw_ass("")
        return
    end
    if dim.timestamp == old_timestamp then return end
    old_timestamp = dim.timestamp
    local ww, wh = mp.get_osd_size()
    if not (ww > 0 and wh > 0) then return end
    if opts.hide_when_full_image_in_view then
        if dim.top_left[1] >= 0 and
           dim.top_left[2] >= 0 and
           dim.bottom_right[1] <= ww and
           dim.bottom_right[2] <= wh
        then
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
        draw((dim.top_left[1] + dim.size[1]/2 - ww/2) / opts.scale,
             (dim.top_left[2] + dim.size[2]/2 - wh/2) / opts.scale,
             dim.size[1] / opts.scale,
             dim.size[2] / opts.scale,
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
    mp.register_idle(refresh_minimap)
end

function disable_minimap()
    if not active then return end
    active = false
    ass.minimap = a.text
    draw_ass()
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
