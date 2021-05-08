local opts = {
    enabled = true,
    size = 36,
    margin = 10,
    text_top_left = "",
    text_top_right = "",
    text_bottom_left = "${filename} [${playlist-pos-1}/${playlist-count}]",
    text_bottom_right = "[${dwidth:X}x${dheight:X}]",
}
(require 'mp.options').read_options(opts)

local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local stale = true

function draw_ass(ass)
    local ww, wh = mp.get_osd_size()
    mp.set_osd_ass(ww, wh, ass)
end

function refresh()
    if not stale then return end
    stale = false
    local a = assdraw:ass_new()
    local draw_text = function(text, an, x, y)
        if text == "" then return end
        local expanded = mp.command_native({ "expand-text", text})
        if not expanded then
            msg.error("Error expanding status-line")
            return
        end
        msg.verbose("Status-line changed to: " .. expanded)
        a:new_event()
        a:an(an)
        a:pos(x,y)
        a:append("{\\fs".. opts.size.. "}{\\bord1.0}")
        a:append(expanded)
    end
    local w,h = mp.get_osd_size()
    local m = opts.margin
    draw_text(opts.text_top_left, 7, m, m)
    draw_text(opts.text_top_right, 9, w-m, m)
    draw_text(opts.text_bottom_left, 1, m, h-m)
    draw_text(opts.text_bottom_right, 3, w-m, h-m)
    draw_ass(a.text)
end

function mark_stale()
    stale = true
end

local active = false

function enable()
    if active then return end
    active = true
    for _, str in ipairs({
        opts.text_top_left,
        opts.text_top_right,
        opts.text_bottom_left,
        opts.text_bottom_right,
    }) do
        local start = 0
        while true do
            local s, e, cap = string.find(str, "%${[?!]?([%l%d-/]*)", start)
            if not s then break end
            msg.verbose("Observing property " .. cap)
            mp.observe_property(cap, nil, mark_stale)
            start = e
        end
    end
    mp.observe_property("osd-width", nil, mark_stale)
    mp.observe_property("osd-height", nil, mark_stale)
    mp.register_idle(refresh)
    mark_stale()
end


function disable()
    if not active then return end
    active = false
    mp.unobserve_property(mark_stale)
    mp.unregister_idle(refresh)
    ass.status_line = ""
    draw_ass()
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

mp.add_key_binding(nil, "enable-status-line", enable)
mp.add_key_binding(nil, "disable-status-line", disable)
mp.add_key_binding(nil, "toggle-status-line", toggle)
