local opts = {
    show_distance = true,
    show_coordinates = true,
    coordinates_space = "image",
    show_angles = "degrees",
    line_width = 2,
    dots_radius = 3,
    font_size = 36,
    line_color = "33",
    confirm_bindings = "MBTN_LEFT,ENTER",
    exit_bindings = "ESC",
    set_first_point_on_begin = false,
    clear_on_second_point_set = false,
}

local options = require 'mp.options'
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local state = 0 -- {0,1,2,3} = {inactive,setting first point,setting second point,done}
local first_point = nil -- in normalized video space coordinates
local second_point = nil -- in normalized video space coordinates
local video_dimensions_stale = false

function split(input)
    local ret = {}
    for str in string.gmatch(input, "([^,]+)") do
        ret[#ret + 1] = str
    end
    return ret
end

local confirm_bindings = split(opts.confirm_bindings)
local exit_bindings = split(opts.exit_bindings)

options.read_options(opts, nil, function()
    if state ~= 0 then
        remove_bindings()
    end
    confirm_bindings = split(opts.confirm_bindings)
    exit_bindings = split(opts.exit_bindings)
    if state ~= 0 then
        add_bindings()
        mark_stale()
    end
end)

function draw_ass(ass)
    local ww, wh = mp.get_osd_size()
    mp.set_osd_ass(ww, wh, ass)
end


function cursor_video_space_normalized(dim)
    local mx, my = mp.get_mouse_pos()
    local ret = {}
    ret[1] = (mx - dim.ml) / (dim.w - dim.ml - dim.mr)
    ret[2] = (my - dim.mt) / (dim.h - dim.mt - dim.mb)
    return ret
end

function refresh()
    if not video_dimensions_stale then return end
    video_dimensions_stale = false

    local dim = mp.get_property_native("osd-dimensions")
    local out_params = mp.get_property_native("video-out-params")
    if not dim or not out_params then
        draw_ass("")
        return
    end
    local vid_width = out_params.dw
    local vid_height = out_params.dh

    function video_space_normalized_to_video(point)
        local ret = {}
        ret[1] = point[1] * vid_width
        ret[2] = point[2] * vid_height
        return ret
    end
    function video_space_normalized_to_screen(point)
        local ret = {}
        ret[1] = point[1] * (dim.w - dim.ml - dim.mr) + dim.ml
        ret[2] = point[2] * (dim.h - dim.mt - dim.mb) + dim.mt
        return ret
    end

    local line_start = {}
    local line_end = {}
    if second_point then
        line_start.image = video_space_normalized_to_video(first_point)
        line_start.screen = video_space_normalized_to_screen(first_point)
        line_end.image = video_space_normalized_to_video(second_point)
        line_end.screen = video_space_normalized_to_screen(second_point)
    elseif first_point then
        line_start.image = video_space_normalized_to_video(first_point)
        line_start.screen = video_space_normalized_to_screen(first_point)
        line_end.image = video_space_normalized_to_video(cursor_video_space_normalized(dim))
        line_end.screen = {}
        line_end.screen[1], line_end.screen[2] = mp.get_mouse_pos()
    else
        local mx, my = mp.get_mouse_pos()
        line_start.image = video_space_normalized_to_video(cursor_video_space_normalized(dim))
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

function mark_stale()
    video_dimensions_stale = true
end

function add_bindings()
    mp.add_forced_key_binding("mouse_move", "ruler-mouse-move", mark_stale)
    for _, key in ipairs(confirm_bindings) do
        mp.add_forced_key_binding(key, "ruler-next-" .. key, next_step)
    end
    for _, key in ipairs(exit_bindings) do
        mp.add_forced_key_binding(key, "ruler-stop-" .. key, stop)
    end
end

function remove_bindings()
    for _, key in ipairs(confirm_bindings) do
        mp.remove_key_binding("ruler-next-" .. key)
    end
    for _, key in ipairs(exit_bindings) do
        mp.remove_key_binding("ruler-stop-" .. key)
    end
    mp.remove_key_binding("ruler-mouse-move")
end

function next_step()
    if state == 0 then
        state = 1
        mp.register_idle(refresh)
        mp.observe_property("osd-dimensions", nil, mark_stale)
        mark_stale()
        add_bindings()
        if opts.set_first_point_on_begin then
            next_step()
        end
    elseif state == 1 then
        local dim = mp.get_property_native("osd-dimensions")
        if not dim then return end
        state = 2
        first_point = cursor_video_space_normalized(dim)
    elseif state == 2 then
        local dim = mp.get_property_native("osd-dimensions")
        if not dim then return end
        state = 3
        second_point = cursor_video_space_normalized(dim)
        if opts.clear_on_second_point_set then
            next_step()
        end
    else
        stop()
    end
end

function stop()
    if state == 0 then return end
    mp.unregister_idle(refresh)
    mp.unobserve_property(mark_stale)
    remove_bindings()
    state = 0
    first_point = nil
    second_point = nil
    draw_ass("")
end

mp.add_key_binding(nil, "ruler", next_step)
