-- Offline smoke test for ku's mythril port (gui.lua): drives update_gui across
-- states and clicks the footer (the mythril replacement for slate's title-bar
-- master switch) through the real mythril mouse handler to confirm pause
-- toggles and the title dims. Stubs windower/texts/images/config + List/const.
-- Run with local Lua 5.1.

_addon = {name = 'ku'}
coroutine.schedule = function() end

local events = {}
windower = {
    windower_path = 'C:/Program Files (x86)/Windower/',
    addon_path = 'C:/nonexistent-ku-harness/',
    register_event = function(name, fn) events[name] = fn end,
    add_to_chat = function() end,
}
package.preload['List'] = function() return {} end
package.preload['const'] = function() return {} end
package.preload['config'] = function()
    return {load = function(d) return d end, save = function() end, register = function() end}
end
package.preload['texts'] = function()
    return {new = function(str)
        local t = {_str = str, _visible = false}
        function t:hide() self._visible = false end
        function t:show() self._visible = true end
        function t:visible(v) if v ~= nil then self._visible = v end return self._visible end
        function t:text(s) self._str = s end
        function t:pos() end function t:color() end function t:alpha() end function t:size() end
        function t:extents() return 40, 12 end
        function t:hover() return false end
        function t:destroy() end
        return t
    end}
end
package.preload['images'] = function()
    return {new = function(s)
        local t = {_visible = false, _alpha = s.color and s.color.alpha}
        function t:show() self._visible = true end
        function t:hide() self._visible = false end
        function t:visible(v) if v ~= nil then self._visible = v end return self._visible end
        function t:pos() end function t:size() end function t:color() end
        function t:alpha(a) self._alpha = a end
        function t:repeat_xy() end function t:destroy() end
        return t
    end}
end

package.path = 'C:/Program Files (x86)/Windower/addons/libs/?.lua;'
    .. 'C:/Program Files (x86)/Windower/addons/ku/?.lua;' .. package.path

-- globals gui.lua's footer-click closure re-renders with
pause = false
log = function() end
zone_restriction_name = 'Test Zone'
local function make_list(n)
    local items = {}
    for i = 1, n do items[i] = {name = 'Ability ' .. i, type = 'selfja', when = 'idle'} end
    return {count = n, first = 1, items = items}
end
ability_list = make_list(2)

dofile('C:/Program Files (x86)/Windower/addons/ku/gui.lua')

local function check(cond, msg)
    if not cond then print('FAIL: ' .. msg) os.exit(1) end
end
check(type(update_gui) == 'function', 'update_gui defined')

-- render with two abilities, running
update_gui(ability_list, zone_restriction_name, pause)
check(events['mouse'] ~= nil, 'mythril mouse handler registered')

-- footer HitBox is placed full-width at content y = 4 + rows_h + 4 (rows_h =
-- 2*18). Panel origin is settings.pos (300,475), title inset 14. Click there.
local fx, fy = 300 + 20, 475 + 14 + (4 + 2 * 18 + 4) + 4
check(events['mouse'](1, fx, fy, 0, false) == true, 'footer click armed over the master hit')
events['mouse'](2, fx, fy, 0, false)
check(pause == true, 'clicking the footer toggled pause on')

-- click again to resume
events['mouse'](1, fx, fy, 0, false)
events['mouse'](2, fx, fy, 0, false)
check(pause == false, 'clicking the footer again resumed')

-- empty list still renders (hint line where rows would be)
update_gui(make_list(0), nil, pause)

-- paused state renders (title dims via title_dim, footer turns warn)
pause = true
update_gui(ability_list, zone_restriction_name, pause)

print('ALL OK')
