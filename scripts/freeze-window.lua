-- credit to TheAMM

local size_changed = false

mp.register_idle(function()
    if not size_changed then return end
    local ww, wh = mp.get_osd_size()
    if not ww or ww <= 0 or not wh or wh <= 0 then return end
    mp.set_property("geometry", string.format("%dx%d", ww, wh))
    size_changed = false
end)

mp.observe_property("osd-width", "native", function() size_changed = true end)
mp.observe_property("osd-height", "native", function() size_changed = true end)
