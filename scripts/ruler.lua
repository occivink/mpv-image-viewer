local opts = {
    show_distance=true,
    show_coordinates=true,
    coordinates_space="image",
    show_angles="degrees",
    line_width=2,
    dots_radius=3,
    font_size=36,
    line_color="33",
    confirm_bindings="MBTN_LEFT,ENTER",
    exit_bindings="ESC",
    set_first_point_on_begin=false,
    clear_on_second_point_set=false,
}
(require 'mp.options').read_options(opts)

function split(input)
    local ret = {}
    for str in string.gmatch(input, "([^,]+)") do
        ret[#ret + 1] = str
    end
    return ret
end
opts.confirm_bindings=split(opts.confirm_bindings)
opts.exit_bindings=split(opts.exit_bindings)

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

local state = 0 -- {0,1,2,3} = {inactive,setting first point,setting second point,done}
local first_point = nil -- in video space coordinates
local second_point = nil -- in video space coordinates

function draw_ass(ass)
    local ww, wh = mp.get_osd_size()
    mp.set_osd_ass(ww, wh, ass)
end

function cursor_video_space()
    local dim = get_video_dimensions()
    if not dim then return nil end
    local mx, my = mp.get_mouse_pos()
    local ret = {}
    ret[1] = (mx - dim.top_left[1]) / dim.ratios[1]
    ret[2] = (my - dim.top_left[2]) / dim.ratios[2]
    return ret
end

function video_space_to_screen(point)
    local dim = get_video_dimensions()
    if not dim then return nil end
    local ret = {}
    ret[1] = point[1] * dim.ratios[1] + dim.top_left[1]
    ret[2] = point[2] * dim.ratios[2] + dim.top_left[2]
    return ret
end

function refresh()
    local dim = get_video_dimensions()
    if not dim then
        draw_ass("")
        return
    end

    local line_start = {}
    local line_end = {}
    if second_point then
        line_start.image = first_point
        line_start.screen = video_space_to_screen(first_point)
        line_end.image = second_point
        line_end.screen = video_space_to_screen(second_point)
    elseif first_point then
        line_start.image = first_point
        line_start.screen = video_space_to_screen(first_point)
        line_end.image = cursor_video_space()
        line_end.screen = {}
        line_end.screen[1], line_end.screen[2] = mp.get_mouse_pos()
    else
        local mx, my = mp.get_mouse_pos()
        line_start.image = cursor_video_space()
        line_start.screen = {}
        line_start.screen[1], line_start.screen[2] = mp.get_mouse_pos()
        line_end = line_start
    end
    local distinct = (math.abs(line_start.screen[1] - line_end.screen[1]) >= 1
                   or math.abs(line_start.screen[2] - line_end.screen[2]) >= 1)

    local a = assdraw:ass_new()
    local draw_setup = function(bord)
        a:new_event()
        a:pos(0,0)
        a:append("{\\bord" .. bord .. "}")
        a:append("{\\shad0}")
        local r = opts.line_color
        a:append("{\\3c&H".. r .. r .. r .. "&}")
        a:append("{\\1a&HFF}")
        a:append("{\\2a&HFF}")
        a:append("{\\3a&H00}")
        a:append("{\\4a&HFF}")
        a:draw_start()
    end
    local dot = function(pos, size)
        draw_setup(size)
        a:move_to(pos[1], pos[2]-0.5)
        a:line_to(pos[1], pos[2]+0.5)
    end
    local line = function(from, to, size)
        draw_setup(size)
        a:move_to(from[1], from[2])
        a:line_to(to[1], to[2])
    end
    if distinct then
        dot(line_start.screen, opts.dots_radius)
        line(line_start.screen, line_end.screen, opts.line_width)
        dot(line_end.screen, opts.dots_radius)
    else
        dot(line_start.screen, opts.dots_radius)
    end

    local line_info = function()
        if not opts.show_distance then return end
        a:new_event()
        a:append("{\\fs36}{\\bord1}")
        a:pos((line_start.screen[1] + line_end.screen[1]) / 2, (line_start.screen[2] + line_end.screen[2]) / 2)
        local an = 1
        if line_start.image[1] < line_end.image[1] then an = an + 2 end
        if line_start.image[2] < line_end.image[2] then an = an + 6 end
        a:an(an)
        local image = math.sqrt(math.pow(line_start.image[1] - line_end.image[1], 2) + math.pow(line_start.image[2] - line_end.image[2], 2))
        local screen = math.sqrt(math.pow(line_start.screen[1] - line_end.screen[1], 2) + math.pow(line_start.screen[2] - line_end.screen[2], 2))
        if opts.coordinates_space == "both" then
            a:append(string.format("image: %.1f\\Nscreen: %.1f", image, screen))
        elseif opts.coordinates_space == "image" then
            a:append(string.format("%.1f", image))
        elseif opts.coordinates_space == "window" then
            a:append(string.format("%.1f", screen))
        end
    end
    local dot_info = function(pos, opposite)
        if not opts.show_coordinates then return end
        a:new_event()
        a:append("{\\fs" .. opts.font_size .."}{\\bord1}")
        a:pos(pos.screen[1], pos.screen[2])
        local an
        if distinct then
            an = 1
            if line_start.image[1] > line_end.image[1] then an = an + 2 end
            if line_start.image[2] < line_end.image[2] then an = an + 6 end
        else
            an = 7
        end
        if opposite then
            an = 9 + 1 - an
        end
        a:an(an)
        if opts.coordinates_space == "both" then
            a:append(string.format("image: %.1f, %.1f\\Nscreen: %i, %i",
                pos.image[1], pos.image[2], pos.screen[1], pos.screen[2]))
        elseif opts.coordinates_space == "image" then
            a:append(string.format("%.1f, %.1f", pos.image[1], pos.image[2]))
        elseif opts.coordinates_space == "window" then
            a:append(string.format("%i, %i", pos.screen[1], pos.screen[2]))
        end
    end
    dot_info(line_start, true)
    if distinct then
        line_info()
        dot_info(line_end, false)
    end
    if distinct and opts.show_angles ~= "no" then
        local dist = 50
        local pos_from_angle = function(mult, angle)
            return {
                line_start.screen[1] + mult * dist * math.cos(angle),
                line_start.screen[2] + mult * dist * math.sin(angle),
            }
        end
        local extended = { line_start.screen[1], line_start.screen[2] }
        if line_end.screen[1] > line_start.screen[1] then
            extended[1] = extended[1] + dist
        else
            extended[1] = extended[1] - dist
        end
        line(line_start.screen, extended, math.max(0, opts.line_width-0.5))
        local angle = math.atan(math.abs(line_start.image[2] - line_end.image[2]) / math.abs(line_start.image[1] - line_end.image[1]))
        local fix_angle
        local an
        if line_end.image[2] < line_start.image[2] and line_end.image[1] > line_start.image[1] then
            -- upper-right
            an = 4
            fix_angle = function(angle) return - angle end
        elseif line_end.image[2] < line_start.image[2] then
            -- upper-left
            an = 6
            fix_angle = function(angle) return math.pi + angle end
        elseif line_end.image[1] < line_start.image[1] then
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
        a:bezier_curve(cp1[1], cp1[2], cp2[1], cp2[2], p2[1], p2[2])

        a:new_event()
        a:append("{\\fs" .. opts.font_size .."}{\\bord1}")
        local text_pos = pos_from_angle(1.1, fix_angle(angle*2/3)) -- you'd think /2 would make more sense, but *2/3  looks better
        a:pos(text_pos[1], text_pos[2])
        a:an(an)
        if opts.show_angles == "both" then
            a:append(string.format("%.2f\\N%.1f°", angle, angle / math.pi * 180))
        elseif opts.show_angles == "degrees" then
            a:append(string.format("%.1f°", angle / math.pi * 180))
        elseif opts.show_angles == "radians" then
            a:append(string.format("%.2f", angle))
        end
    end

    draw_ass(a.text)
end

function next()
    if state == 0 then
        mp.register_idle(refresh)
        mp.add_forced_key_binding("mouse_move", "ruler-mouse-move", function() end) -- only used to get an idle event on mouse move
        for _,key in ipairs(opts.confirm_bindings) do
            mp.add_forced_key_binding(key, "ruler-next-" .. key, next)
        end
        for _,key in ipairs(opts.exit_bindings) do
            mp.add_forced_key_binding(key, "ruler-stop-" .. key, stop)
        end
        state = 1
        if opts.set_first_point_on_begin then
            next()
        end
    elseif state == 1 then
        first_point = cursor_video_space()
        state = 2
    elseif state == 2 then
        state = 3
        second_point = cursor_video_space()
        if opts.clear_on_second_point_set then
            next()
        end
    else
        stop()
    end
end

function stop()
    if state == 0 then return end
    mp.unregister_idle(refresh)
    for _,key in ipairs(opts.confirm_bindings) do
        mp.remove_key_binding("ruler-next-" .. key)
    end
    for _,key in ipairs(opts.exit_bindings) do
        mp.remove_key_binding("ruler-stop-" .. key)
    end
    mp.remove_key_binding("ruler-mouse-move")
    state = 0
    first_point = nil
    second_point = nil
    draw_ass("")
end

mp.add_key_binding(nil, "ruler", next)
