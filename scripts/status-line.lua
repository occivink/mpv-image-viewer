local opts = {
    enabled = true,
    position = "bottom-left",
    size = 36,
    text = "${filename} [${playlist-pos-1}/${playlist-count}]",
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
    local expanded = mp.command_native({ "expand-text", opts.text})
    if not expanded then
        msg.error("Error expanding status-line")
        draw_ass("")
        return
    end
    msg.verbose("Status-line changed to: " .. expanded)
    local w,h = mp.get_osd_size()
    local an, x, y
    local margin = 10
    if opts.position == "top-left" then
        x = margin
        y = margin
        an = 7
    elseif opts.position == "top-right" then
        x = w-margin
        y = margin
        an = 9
    elseif opts.position == "bottom-right" then
        x = w-margin
        y = h-margin
        an = 3
    elseif opts.position == "bottom-left" then
        x = margin
        y = h-margin
        an = 1
    else
        msg.error("Invalid position: " .. opts.position)
        return
    end
    local a = assdraw:ass_new()
    a:new_event()
    a:an(an)
    a:pos(x,y)
    a:append("{\\fs".. opts.size.. "}{\\bord1.0}")
    a:append(expanded)
    draw_ass(a.text)
end

function mark_stale()
    stale = true
end

local active = false

function enable()
    if active then return end
    active = true
    local start = 0
    while true do
        local s, e, cap = string.find(opts.text, "%${[?!]?([%l%d-/]*)", start)
        if not s then break end
        msg.verbose("Observing property " .. cap)
        mp.observe_property(cap, nil, mark_stale)
        start = e
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
