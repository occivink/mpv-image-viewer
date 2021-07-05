local opts = {
    bars = 'brightness,contrast,gamma,saturation,hue',
    draw_icons = true,
}

local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'
local options = require 'mp.options'
local utils = require 'mp.utils'

options.read_options(opts, nil, function(c)
end)

local enabled = false
local active_bars = {}
local bar_being_dragged = nil
local stale = false

function split_comma(input)
    local ret = {}
    for str in string.gmatch(input, "([^,]+)") do
        ret[#ret + 1] = str
    end
    return ret
end

function get_position_normalized(x, y, bar)
    return (x - bar.x) / bar.w, (y - bar.y) / bar.h
end

function handle_mouse_move()
    if not bar_being_dragged then return end
    local bar = bar_being_dragged
    local mx, my = mp.get_mouse_pos()
    local nx, _ = get_position_normalized(mx, my, bar)
    nx = math.max(0, math.min(nx, 1))
    local val = math.floor(nx * (bar.max_value - bar.min_value) + bar.min_value + 0.5)
    mp.set_property_number(bar.property, val)
    -- the observe_property call will take care of setting the value
end

function handle_mouse_left(table)
    if table["event"] == "down" then
        local mx, my = mp.get_mouse_pos()
        for _, bar in ipairs(active_bars) do
            local nx, ny = get_position_normalized(mx, my, bar)
            if nx >= 0 and ny >= 0 and nx <= 1 and ny <= 1 then
                bar_being_dragged = bar
                local val = math.floor(nx * (bar.max_value - bar.min_value) + bar.min_value + 0.5)
                mp.set_property_number(bar.property, val)
                mp.add_forced_key_binding("mouse_move", "mouse_move", handle_mouse_move)
                break
            end
        end
    elseif table["event"] == "up" then
        mp.remove_key_binding("mouse_move")
        bar_being_dragged = nil
    end
end

function property_changed(prop, val)
    for _, bar in ipairs(active_bars) do
        if bar.property == prop then
            bar.value = val
            stale = true
            break
        end
    end
end

function idle_handler()
    if not stale then return end
    stale = false
    local a = assdraw.ass_new()
    a:new_event()
    a:append(string.format('{\\an0\\bord2\\shad0\\1a&00&\\1c&%s&}', '888888'))
    a:pos(0, 0)
    a:draw_start()
    for _, bar in ipairs(active_bars) do
        a:rect_cw(bar.x, bar.y, bar.x + bar.w, bar.y + bar.h)
    end
    a:new_event()
    a:append(string.format('{\\an0\\bord2\\shad0\\1a&00&\\1c&%s&}', 'dddddd'))
    a:pos(0, 0)
    a:draw_start()
    for _, bar in ipairs(active_bars) do
        if bar.value > bar.min_value then
            local val_norm = (bar.value - bar.min_value) / (bar.max_value - bar.min_value)
            a:rect_cw(bar.x, bar.y, bar.x + val_norm * bar.w, bar.y + bar.h)
        end
    end
    for _, bar in ipairs(active_bars) do
        a:new_event()
        a:append("{\\an6\\fs40\\bord2}")
        a:pos(bar.x - 8, bar.y + bar.h/2 - 2)
        a:append(bar.property:sub(1,1):upper() .. bar.property:sub(2,-1))
    end
    local ww, wh = mp.get_osd_size()
    mp.set_osd_ass(ww, wh, a.text)
end

function fix_position()
    local ww, wh = mp.get_osd_size()
    for i, bar in ipairs(active_bars) do
        bar.x = ww / 5
        bar.y = wh / 2 + i * 50
        bar.w = ww - 2 * (ww / 5)
        bar.h = 30
    end
end

function dimensions_changed()
    stale = true
    fix_position()
end

function enable()
    if enabled then return end
    enabled = true
    mp.add_forced_key_binding("MBTN_LEFT", "mouse_left", handle_mouse_left, {complex=true})
    for i, prop in ipairs(split_comma(opts.bars)) do
        local prop_info = mp.get_property_native("option-info/" .. prop)
        if not prop_info then
            msg.warn("Property \'" .. prop .. "\' does not exist")
        elseif not prop_info.type == 'Integer' then
            msg.warn("Property \'" .. prop .. "\' is not an integer")
        else
            mp.observe_property(prop, 'native', property_changed)
            active_bars[#active_bars + 1] = {
                property = prop,
                value = mp.get_property_number(prop),
                min_value = prop_info.min,
                max_value = prop_info.max,
            }
        end
    end
    stale = true
    fix_position()
    mp.observe_property("osd-dimensions", "native", dimensions_changed)
    mp.register_idle(idle_handler)
end

function disable()
    if not enabled then return end
    enabled = false
    active_bars = {}
    bar_being_dragged = nil
    mp.remove_key_binding("mouse_left")
    mp.remove_key_binding("mouse_move")
    mp.unobserve_property(property_changed)
    mp.unobserve_property(dimensions_changed)
    mp.unregister_idle(idle_handler)
    mp.set_osd_ass(1280, 720, "")
end

function toggle()
    if enabled then
        disable()
    else
        enable()
    end
end

function reset()
    for _, prop in ipairs(split_comma(opts.bars)) do
        local prop_info = mp.get_property_native("option-info/" .. prop)
        if prop_info and prop_info["default-value"] then
            mp.set_property(prop_info["name"], prop_info["default-value"])
        end
    end
end

mp.add_key_binding(nil, "equalizer-enable", enable)
mp.add_key_binding(nil, "equalizer-disable", disable)
mp.add_key_binding(nil, "equalizer-toggle", toggle)
mp.add_key_binding(nil, "equalizer-reset", reset)
