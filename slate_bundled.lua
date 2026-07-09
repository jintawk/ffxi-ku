--[[
    Slate - shared UI library for jintawk addons.

    One visual identity for every addon HUD: dark slate panels, amber accent,
    green toggle switches, Segoe UI. Derived from Medic's UI, generalised.

    Widgets:
      Panel      window with title bar (title, optional master toggle,
                 minimize button), drag, children, dock integration
      Label      text
      Rect       plain rectangle (building block, exposed for custom layouts)
      Toggle     on/off switch (the Medic switch)
      Button     clickable text with hover feedback
      IconButton drawn glyph button (minus / plus / x), no image assets
      Bar        progress bar with optional text overlay
      HitBox     invisible click/hover region (row semantics)
      Divider    1px hairline rule

    Coordinates: everything you pass to Slate is in DESIGN UNITS. The library
    multiplies by the ui scale internally. Panel screen position (pos) is the
    only exception - it is raw screen pixels, since it persists to settings.

    Dock protocol (slatedock addon). The dock is a taskbar: every live
    Slate addon has an entry; minimized entries just look different.
      panel addon -> dock:  lua c slatedock hello <name> <TITLE> <on|off|none> <min|max>
                            lua c slatedock present <name> <TITLE> <on|off|none> <min|max>
                            lua c slatedock dock <name> <TITLE> <on|off|none>
                            lua c slatedock undock <name>
                            lua c slatedock state <name> <on|off|none>
                            lua c slatedock bye <name>
      dock -> panel addon:  lua c <name> slate dockready
                            lua c <name> slate dockgone
                            lua c <name> slate restore
                            lua c <name> slate minimize
                            lua c <name> slate toggle
    hello announces a new panel (dock answers dockready); present answers
    a dockready broadcast (no reply, so the handshake terminates); bye
    removes the entry on unload.
    Route your 'addon command' event through slate.handle_command first; it
    returns true when the command was Slate's.

    Copyright (c) 2026, jintawk
    BSD 3-clause license.
]]

local texts = require('texts')
local images = require('images')

local slate = {}
slate.version = '1.2.0'

-- ========================================================================
-- Theme
-- ========================================================================

-- {r, g, b, a} for rects, first three for text colors
slate.color = {
    panel        = {17, 19, 24, 240},
    header       = {27, 31, 38, 255},
    well         = {10, 12, 16, 255},
    row_hover    = {255, 255, 255, 26},
    row_active   = {255, 200, 60, 30},
    accent       = {255, 200, 60, 255},
    green        = {64, 168, 96, 255},
    green_hl     = {84, 196, 118, 255},
    track_off    = {64, 70, 80, 255},
    track_off_hl = {88, 96, 108, 255},
    knob         = {235, 238, 242, 255},
    title        = {235, 240, 245, 255},
    text         = {225, 228, 233, 255},
    text_dim     = {150, 157, 166, 255},
    text_faint   = {105, 110, 118, 255},
    disabled     = {125, 131, 140, 255},
    ok           = {150, 210, 160, 255},
    warn         = {255, 180, 90, 255},
    bad          = {255, 110, 110, 255},
    divider      = {255, 255, 255, 18},
    bar_track    = {64, 70, 80, 255},
    bar_text     = {11, 13, 17, 255},
}

slate.font = {
    main = 'Segoe UI',
    mono = 'Consolas',
}

slate.TITLE_H = 30      -- title bar height, design units
slate.PAD = 10          -- default horizontal padding inside panels

-- ========================================================================
-- Scale
-- ========================================================================

local scale = 1.0
local all_widgets = {}      -- every widget, for scale reapplication
local all_panels = {}       -- panels, for relayout and dock protocol

function slate.s(px)
    return math.floor(px * scale + 0.5)
end

local S = slate.s

function slate.scale()
    return scale
end

function slate.set_scale(new_scale)
    scale = math.max(0.5, math.min(3, tonumber(new_scale) or 1))
    for _, w in pairs(all_widgets) do
        if w._apply_scale then
            w:_apply_scale()
        end
    end
    for _, p in pairs(all_panels) do
        p:_layout()
    end
    if slate.on_scale_change then
        slate.on_scale_change(scale)
    end
end

-- ========================================================================
-- Internals: registries, primitive helpers
-- ========================================================================

local widget_counter = 0
local function next_id(prefix)
    widget_counter = widget_counter + 1
    return prefix .. '_' .. widget_counter
end

local interactive = {}      -- id -> widget with hover/on_click/on_scroll

local function register(w)
    all_widgets[w._id] = w
end

local function unregister(w)
    all_widgets[w._id] = nil
    interactive[w._id] = nil
end

local function new_image(color, w, h)
    return images.new({
        pos = {x = -10000, y = -10000},
        size = {width = w or 10, height = h or 10},
        color = {red = color[1], green = color[2], blue = color[3], alpha = color[4] or 255},
        visible = false,
        draggable = false,
        texture = {path = '', fit = true},
        repeatable = {x = 1, y = 1},
    })
end

local function new_text(str, font, size, bold, color)
    local t = texts.new(str or '', {
        pos = {x = -10000, y = -10000},
        text = {
            font = font,
            size = size,
            red = color[1], green = color[2], blue = color[3],
            alpha = color[4] or 255,
            stroke = {width = 0, alpha = 0, red = 0, green = 0, blue = 0},
        },
        bg = {visible = false},
        flags = {draggable = false, bold = bold or false},
        padding = 0,
    })
    t:hide()
    return t
end

local function img_color(img, c)
    img:color(c[1], c[2], c[3])
    img:alpha(c[4] or 255)
end

local function in_box(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- ========================================================================
-- Rect
-- ========================================================================

local Rect = {}
Rect.__index = Rect

function slate.Rect(opts)
    local self = setmetatable({}, Rect)
    opts = opts or {}
    self._id = next_id('rect')
    self._w = opts.w or 10
    self._h = opts.h or 10
    self._color = opts.color or slate.color.header
    self._x, self._y = -10000, -10000
    self._visible = false
    self._img = new_image(self._color, S(self._w), S(self._h))
    register(self)
    return self
end

function Rect:pos(x, y)
    self._x, self._y = x, y
    self._img:pos(x, y)
end

function Rect:size(w, h)
    self._w, self._h = w, h
    self._img:size(S(w), S(h))
end

function Rect:color(c)
    self._color = c
    img_color(self._img, c)
end

function Rect:show()
    self._visible = true
    self._img:show()
end

function Rect:hide()
    self._visible = false
    self._img:hide()
end

function Rect:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Rect:_apply_scale()
    self._img:size(S(self._w), S(self._h))
end

function Rect:destroy()
    unregister(self)
    self._img:destroy()
end

-- ========================================================================
-- Divider - 1px hairline
-- ========================================================================

function slate.Divider(opts)
    opts = opts or {}
    return slate.Rect({
        w = opts.w or 100,
        h = opts.h or 1,
        color = opts.color or slate.color.divider,
    })
end

-- ========================================================================
-- Label
-- ========================================================================

local Label = {}
Label.__index = Label

function slate.Label(opts)
    local self = setmetatable({}, Label)
    opts = opts or {}
    self._id = next_id('label')
    self._base_size = opts.size or 10
    self._color = opts.color or slate.color.text
    self._visible = false
    self._last = nil
    self._text = new_text(opts.text or '', opts.font or slate.font.main,
        math.max(6, S(self._base_size)), opts.bold or false, self._color)
    if opts.text then self._last = opts.text end
    register(self)
    return self
end

function Label:text(str)
    if str ~= nil and str ~= self._last then
        self._last = str
        self._text:text(str)
    end
    return self._last
end

function Label:pos(x, y)
    self._text:pos(x, y)
end

function Label:color(c)
    if c ~= self._color then
        self._color = c
        self._text:color(c[1], c[2], c[3])
        self._text:alpha(c[4] or 255)
    end
end

function Label:extents()
    return self._text:extents()
end

function Label:show()
    self._visible = true
    self._text:show()
end

function Label:hide()
    self._visible = false
    self._text:hide()
end

function Label:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Label:_apply_scale()
    self._text:size(math.max(6, S(self._base_size)))
end

function Label:destroy()
    unregister(self)
    self._text:destroy()
end

-- ========================================================================
-- Toggle - the Medic switch. Display-only state; flip it from on_click.
-- ========================================================================

local Toggle = {}
Toggle.__index = Toggle

function slate.Toggle(opts)
    local self = setmetatable({}, Toggle)
    opts = opts or {}
    self._id = next_id('toggle')
    self._w = opts.w or 26
    self._h = opts.h or 14
    self._on = opts.on or false
    self._hovered = false
    self._visible = false
    self._x, self._y = -10000, -10000
    self.on_click = opts.on_click
    self._track = new_image(slate.color.track_off, S(self._w), S(self._h))
    self._knob = new_image(slate.color.knob, S(self._h - 4), S(self._h - 4))
    register(self)
    if self.on_click then
        interactive[self._id] = self
    end
    self:_paint()
    return self
end

function Toggle:_paint()
    local c
    if self._on then
        c = self._hovered and slate.color.green_hl or slate.color.green
    else
        c = self._hovered and slate.color.track_off_hl or slate.color.track_off
    end
    img_color(self._track, c)
end

function Toggle:_place_knob()
    local kw = S(self._h - 4)
    local kx = self._on and (self._x + S(self._w) - kw - S(2)) or (self._x + S(2))
    self._knob:pos(kx, self._y + S(2))
end

function Toggle:pos(x, y)
    self._x, self._y = x, y
    self._track:pos(x, y)
    self:_place_knob()
end

function Toggle:set(on)
    on = on and true or false
    if on ~= self._on then
        self._on = on
        self:_paint()
        self:_place_knob()
    end
end

function Toggle:get()
    return self._on
end

function Toggle:hover(x, y)
    if not self._visible then return false end
    -- generous hit box: 4 design units of padding on every side
    local p = S(4)
    return in_box(x, y, self._x - p, self._y - p, S(self._w) + p * 2, S(self._h) + p * 2)
end

function Toggle:set_hovered(h)
    if h ~= self._hovered then
        self._hovered = h
        self:_paint()
    end
end

function Toggle:show()
    self._visible = true
    self._track:show()
    self._knob:show()
end

function Toggle:hide()
    self._visible = false
    self._hovered = false
    self._track:hide()
    self._knob:hide()
end

function Toggle:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Toggle:_apply_scale()
    self._track:size(S(self._w), S(self._h))
    self._knob:size(S(self._h - 4), S(self._h - 4))
    self:_place_knob()
end

function Toggle:destroy()
    unregister(self)
    self._track:destroy()
    self._knob:destroy()
end

-- ========================================================================
-- Button - clickable text with hover color/background
-- ========================================================================

local Button = {}
Button.__index = Button

function slate.Button(opts)
    local self = setmetatable({}, Button)
    opts = opts or {}
    self._id = next_id('btn')
    self._base_size = opts.size or 10
    self._color = opts.color or slate.color.text
    self._hover_color = opts.hover_color or slate.color.title
    self._hovered = false
    self._visible = false
    self._last = nil
    self.on_click = opts.on_click
    self._text = new_text(opts.text or '', opts.font or slate.font.main,
        math.max(6, S(self._base_size)), opts.bold ~= false, self._color)
    if opts.text then self._last = opts.text end
    register(self)
    interactive[self._id] = self
    return self
end

function Button:text(str)
    if str ~= nil and str ~= self._last then
        self._last = str
        self._text:text(str)
    end
    return self._last
end

function Button:pos(x, y)
    self._text:pos(x, y)
end

function Button:color(c)
    self._color = c
    if not self._hovered then
        self._text:color(c[1], c[2], c[3])
        self._text:alpha(c[4] or 255)
    end
end

function Button:extents()
    return self._text:extents()
end

function Button:hover(x, y)
    return self._visible and self._text:hover(x, y)
end

function Button:set_hovered(h)
    if h ~= self._hovered then
        self._hovered = h
        local c = h and self._hover_color or self._color
        self._text:color(c[1], c[2], c[3])
        self._text:alpha(c[4] or 255)
    end
end

function Button:show()
    self._visible = true
    self._text:show()
end

function Button:hide()
    self._visible = false
    self._hovered = false
    self._text:hide()
end

function Button:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Button:_apply_scale()
    self._text:size(math.max(6, S(self._base_size)))
end

function Button:destroy()
    unregister(self)
    self._text:destroy()
end

-- ========================================================================
-- IconButton - drawn glyphs (no image assets): 'minus', 'plus', 'x'
-- ========================================================================

local IconButton = {}
IconButton.__index = IconButton

function slate.IconButton(opts)
    local self = setmetatable({}, IconButton)
    opts = opts or {}
    self._id = next_id('icon')
    self._w = opts.w or 18
    self._h = opts.h or 16
    self._kind = opts.kind or 'minus'
    self._hovered = false
    self._visible = false
    self._x, self._y = -10000, -10000
    self.on_click = opts.on_click
    self._bg = new_image(slate.color.row_hover, S(self._w), S(self._h))
    self._bg:alpha(0)
    -- two strokes cover minus (h only), plus and x (both)
    self._stroke_h = new_image(slate.color.knob, S(8), math.max(1, S(2)))
    self._stroke_v = new_image(slate.color.knob, math.max(1, S(2)), S(8))
    register(self)
    interactive[self._id] = self
    return self
end

function IconButton:kind(k)
    if k and k ~= self._kind then
        self._kind = k
        self:pos(self._x, self._y)
        if self._visible then
            self:show()
        end
    end
    return self._kind
end

function IconButton:pos(x, y)
    self._x, self._y = x, y
    self._bg:pos(x, y)
    local cx = x + math.floor((S(self._w) - S(8)) / 2)
    local cy = y + math.floor((S(self._h) - math.max(1, S(2))) / 2)
    self._stroke_h:pos(cx, cy)
    local vx = x + math.floor((S(self._w) - math.max(1, S(2))) / 2)
    local vy = y + math.floor((S(self._h) - S(8)) / 2)
    self._stroke_v:pos(vx, vy)
end

function IconButton:hover(x, y)
    if not self._visible then return false end
    local p = S(3)
    return in_box(x, y, self._x - p, self._y - p, S(self._w) + p * 2, S(self._h) + p * 2)
end

function IconButton:set_hovered(h)
    if h ~= self._hovered then
        self._hovered = h
        self._bg:alpha(h and slate.color.row_hover[4] or 0)
    end
end

function IconButton:show()
    self._visible = true
    self._bg:show()
    self._stroke_h:show()
    self._stroke_v:visible(self._kind ~= 'minus')
end

function IconButton:hide()
    self._visible = false
    self._hovered = false
    self._bg:hide()
    self._stroke_h:hide()
    self._stroke_v:hide()
end

function IconButton:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function IconButton:_apply_scale()
    self._bg:size(S(self._w), S(self._h))
    self._stroke_h:size(S(8), math.max(1, S(2)))
    self._stroke_v:size(math.max(1, S(2)), S(8))
    self:pos(self._x, self._y)
end

function IconButton:destroy()
    unregister(self)
    self._bg:destroy()
    self._stroke_h:destroy()
    self._stroke_v:destroy()
end

-- ========================================================================
-- Bar - progress bar, optional text overlay
-- ========================================================================

local Bar = {}
Bar.__index = Bar

function slate.Bar(opts)
    local self = setmetatable({}, Bar)
    opts = opts or {}
    self._id = next_id('bar')
    self._w = opts.w or 100
    self._h = opts.h or 12
    self._frac = 0
    self._visible = false
    self._x, self._y = -10000, -10000
    self._fill_color = opts.fill_color or slate.color.green
    self._track = new_image(opts.track_color or slate.color.bar_track, S(self._w), S(self._h))
    self._fill = new_image(self._fill_color, 0, S(self._h))
    self._label = nil
    if opts.text ~= false then
        self._label_size = opts.text_size or 8
        self._label = new_text('', opts.font or slate.font.main,
            math.max(6, S(self._label_size)), true, opts.text_color or slate.color.bar_text)
    end
    register(self)
    return self
end

function Bar:pos(x, y)
    self._x, self._y = x, y
    self._track:pos(x, y)
    self._fill:pos(x, y)
    if self._label then
        self._label:pos(x + S(4), y + math.floor((S(self._h) - S(self._label_size) - S(4)) / 2))
    end
end

function Bar:set(frac, text, fill_color)
    self._frac = math.max(0, math.min(1, frac or 0))
    if fill_color and fill_color ~= self._fill_color then
        self._fill_color = fill_color
        img_color(self._fill, fill_color)
    end
    local fw = math.floor(S(self._w) * self._frac)
    if self._frac > 0 then fw = math.max(1, fw) end
    self._fill:size(fw, S(self._h))
    if self._label and text then
        self._label:text(text)
    end
end

function Bar:size(w, h)
    self._w, self._h = w, h or self._h
    self._track:size(S(self._w), S(self._h))
    self:set(self._frac)
end

function Bar:show()
    self._visible = true
    self._track:show()
    self._fill:show()
    if self._label then self._label:show() end
end

function Bar:hide()
    self._visible = false
    self._track:hide()
    self._fill:hide()
    if self._label then self._label:hide() end
end

function Bar:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Bar:_apply_scale()
    self._track:size(S(self._w), S(self._h))
    local fw = math.floor(S(self._w) * self._frac)
    if self._frac > 0 then fw = math.max(1, fw) end
    self._fill:size(fw, S(self._h))
    if self._label then
        self._label:size(math.max(6, S(self._label_size)))
    end
end

function Bar:destroy()
    unregister(self)
    self._track:destroy()
    self._fill:destroy()
    if self._label then self._label:destroy() end
end

-- ========================================================================
-- HitBox - invisible interactive region (row hover/click semantics)
-- ========================================================================

local HitBox = {}
HitBox.__index = HitBox

function slate.HitBox(opts)
    local self = setmetatable({}, HitBox)
    opts = opts or {}
    self._id = next_id('hit')
    self._w = opts.w or 10
    self._h = opts.h or 10
    self._visible = false
    self._hovered = false
    self._x, self._y = -10000, -10000
    self.on_click = opts.on_click
    self.on_hover = opts.on_hover
    self.on_scroll = opts.on_scroll
    self.on_rclick = opts.on_rclick
    -- optional press-drag: on_drag(dx, dy) receives the offset from the
    -- press point; a press that moves beyond the threshold never clicks
    self.on_drag = opts.on_drag
    self.on_drag_end = opts.on_drag_end
    register(self)
    interactive[self._id] = self
    return self
end

function HitBox:pos(x, y)
    self._x, self._y = x, y
end

function HitBox:size(w, h)
    self._w, self._h = w, h
end

function HitBox:hover(x, y)
    if not self._visible then return false end
    return in_box(x, y, self._x, self._y, S(self._w), S(self._h))
end

function HitBox:set_hovered(h)
    if h ~= self._hovered then
        self._hovered = h
        if self.on_hover then
            self.on_hover(h)
        end
    end
end

function HitBox:show()
    self._visible = true
end

function HitBox:hide()
    self._visible = false
    self._hovered = false
end

function HitBox:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function HitBox:destroy()
    unregister(self)
end

-- ========================================================================
-- Panel
-- ========================================================================

local Panel = {}
Panel.__index = Panel

local dock = {
    available = false,
    addon = (_addon and _addon.name or 'addon'):lower(),
}

local function dock_send(msg)
    windower.send_command('lua c slatedock ' .. msg)
end

function slate.Panel(opts)
    local self = setmetatable({}, Panel)
    opts = opts or {}
    self._id = next_id('panel')
    self._x = opts.x or 200
    self._y = opts.y or 200
    self._w = opts.w or 240
    self._content_h = opts.content_h or 100
    self._title_text = opts.title or dock.addon:upper()
    self._shown = false                  -- addon-level visibility
    self._minimized = opts.minimized or false
    self._docked = false                 -- hidden into slatedock
    self._children = {}                  -- {widget=, ox=, oy=}
    self._dragging = nil

    self.on_move = opts.on_move          -- (x, y) after drag ends
    self.on_minimize = opts.on_minimize  -- (minimized)
    self.on_master = opts.on_master      -- () master toggle clicked

    -- chrome: content bg first, then title bar, so children stack above bg
    self._content_bg = new_image(slate.color.panel, S(self._w), S(self._content_h))
    self._title_bg = new_image(slate.color.header, S(self._w), S(slate.TITLE_H))
    self._title = slate.Label({
        text = self._title_text,
        size = 11,
        bold = true,
        color = slate.color.title,
    })

    if opts.master then
        self._toggle = slate.Toggle({
            w = 30, h = 16,
            on = opts.master_on or false,
            on_click = function()
                if self.on_master then self.on_master() end
            end,
        })
    end

    self._min_btn = slate.IconButton({
        kind = self._minimized and 'plus' or 'minus',
        on_click = function()
            self:minimize(not self._minimized)
        end,
    })

    all_panels[self._id] = self
    register(self)

    -- announce ourselves to the dock, if it is loaded
    self:_announce('hello')

    self:_layout()
    return self
end

-- Full presence line: <verb> <name> <TITLE> <on|off|none> <min|max>
function Panel:_announce(verb)
    dock_send(verb .. ' ' .. dock.addon .. ' ' .. self._title_text:gsub('%s+', '') ..
        ' ' .. self:_master_word() .. ' ' .. (self._minimized and 'min' or 'max'))
end

function Panel:_layout()
    local x, y = self._x, self._y
    local w = S(self._w)
    local th = S(slate.TITLE_H)

    self._title_bg:pos(x, y)
    self._title_bg:size(w, th)
    self._title:pos(x + S(12), y + math.floor((th - S(17)) / 2))

    local mw, mh = S(18), S(16)
    local mx = x + w - S(10) - mw
    local my = y + math.floor((th - mh) / 2)
    self._min_btn:pos(mx, my)

    if self._toggle then
        local tw, tth = S(30), S(16)
        self._toggle:pos(mx - S(10) - tw, y + math.floor((th - tth) / 2))
    end

    self._content_bg:pos(x, y + th)
    self._content_bg:size(w, S(self._content_h))

    for _, child in ipairs(self._children) do
        child.widget:pos(x + S(child.ox), y + th + S(child.oy))
    end
end

function Panel:pos(x, y)
    self._x, self._y = x, y
    self:_layout()
end

function Panel:get_pos()
    return self._x, self._y
end

function Panel:width()
    return self._w
end

function Panel:set_width(w)
    self._w = w
    self:_layout()
end

function Panel:content_height(h)
    if h and h ~= self._content_h then
        self._content_h = h
        self._content_bg:size(S(self._w), S(h))
    end
    return self._content_h
end

-- Add a child at a content-relative offset in design units. Order of
-- creation is draw order: create the panel first, then children.
function Panel:add(widget, ox, oy)
    self._children[#self._children + 1] = {widget = widget, ox = ox or 0, oy = oy or 0}
    widget:pos(self._x + S(ox or 0), self._y + S(slate.TITLE_H) + S(oy or 0))
    return widget
end

-- Move an existing child to a new content-relative offset.
function Panel:place(widget, ox, oy)
    for _, child in ipairs(self._children) do
        if child.widget == widget then
            child.ox, child.oy = ox, oy
            widget:pos(self._x + S(ox), self._y + S(slate.TITLE_H) + S(oy))
            return
        end
    end
end

function Panel:title(text)
    if text then
        self._title_text = text
        self._title:text(text)
    end
    return self._title_text
end

function Panel:set_master(on)
    on = on and true or false
    if not self._toggle or on == self._toggle:get() then
        return
    end
    self._toggle:set(on)
    if dock.available then
        dock_send('state ' .. dock.addon .. ' ' .. (on and 'on' or 'off'))
    end
end

function Panel:master()
    return self._toggle and self._toggle:get() or nil
end

function Panel:_master_word()
    if not self._toggle then return 'none' end
    return self._toggle:get() and 'on' or 'off'
end

-- Presentation refresh honouring shown/minimized/docked state.
function Panel:_present()
    if not self._shown or self._docked then
        self._title_bg:hide()
        self._title:hide()
        self._min_btn:hide()
        if self._toggle then self._toggle:hide() end
        self._content_bg:hide()
        for _, child in ipairs(self._children) do
            child.widget:hide()
        end
        return
    end
    self._title_bg:show()
    self._title:show()
    self._min_btn:kind(self._minimized and 'plus' or 'minus')
    self._min_btn:show()
    if self._toggle then self._toggle:show() end
    if self._minimized then
        self._content_bg:hide()
        for _, child in ipairs(self._children) do
            child.widget:hide()
        end
    else
        self._content_bg:show()
        for _, child in ipairs(self._children) do
            child.widget:show()
        end
    end
end

function Panel:minimize(min)
    min = min and true or false
    if min == self._minimized then return end
    self._minimized = min
    if min and dock.available then
        self._docked = true
        dock_send('dock ' .. dock.addon .. ' ' .. self._title_text:gsub('%s+', '') ..
            ' ' .. self:_master_word())
    elseif not min and self._docked then
        self._docked = false
        dock_send('undock ' .. dock.addon)
    end
    self:_present()
    if self.on_minimize then
        self.on_minimize(min)
    end
end

function Panel:is_minimized()
    return self._minimized
end

function Panel:show()
    self._shown = true
    -- a panel that loads minimized while the dock is up goes straight there
    if self._minimized and dock.available and not self._docked then
        self._docked = true
        dock_send('dock ' .. dock.addon .. ' ' .. self._title_text:gsub('%s+', '') ..
            ' ' .. self:_master_word())
    end
    self:_present()
end

function Panel:hide()
    self._shown = false
    self._dragging = nil
    self:_present()
end

function Panel:visible()
    return self._shown
end

function Panel:hover(x, y)
    if not self._shown or self._docked then return false end
    local h = S(slate.TITLE_H)
    if not self._minimized then
        h = h + S(self._content_h)
    end
    return in_box(x, y, self._x, self._y, S(self._w), h)
end

function Panel:hover_title(x, y)
    if not self._shown or self._docked then return false end
    return in_box(x, y, self._x, self._y, S(self._w), S(slate.TITLE_H))
end

function Panel:destroy()
    self._shown = false
    self._dragging = nil
    all_panels[self._id] = nil
    unregister(self)
    dock_send('bye ' .. dock.addon)
    self._content_bg:destroy()
    self._title_bg:destroy()
    self._title:destroy()
    self._min_btn:destroy()
    if self._toggle then self._toggle:destroy() end
    for _, child in ipairs(self._children) do
        if child.widget.destroy then
            child.widget:destroy()
        end
    end
    self._children = {}
end

-- ========================================================================
-- Dock protocol client
-- ========================================================================

local function first_panel()
    for _, p in pairs(all_panels) do
        return p
    end
    return nil
end

-- Route your addon command event through this first:
--   if slate.handle_command(cmd, ...) then return end
function slate.handle_command(cmd, sub, ...)
    if not cmd or cmd:lower() ~= 'slate' then
        return false
    end
    sub = (sub or ''):lower()
    local panel = first_panel()

    if sub == 'dockready' then
        dock.available = true
        if panel then
            -- a panel already minimized in place moves into the dock
            if panel._minimized and not panel._docked then
                panel._docked = true
                panel:_present()
            end
            -- answer with presence so a late-loading dock lists us
            panel:_announce('present')
        end
    elseif sub == 'dockgone' then
        dock.available = false
        if panel and panel._docked then
            panel._docked = false
            panel:_present()
        end
    elseif sub == 'restore' then
        if panel then
            panel._docked = false
            panel:minimize(false)
            panel:_present()
        end
    elseif sub == 'minimize' then
        if panel then
            panel:minimize(true)
        end
    elseif sub == 'toggle' then
        if panel and panel.on_master then
            panel.on_master()
        end
    else
        return false
    end
    return true
end

function slate.dock_available()
    return dock.available
end

-- ========================================================================
-- Mouse dispatch - one handler per addon
-- ========================================================================

local drag_state = nil          -- {panel, dx, dy}
local mouse_down_target = nil
local mouse_down_pos = nil
local widget_dragging = false

local function over_any_panel(x, y)
    for _, p in pairs(all_panels) do
        if p:hover(x, y) then
            return true
        end
    end
    return false
end

windower.register_event('mouse', function(m_type, x, y, delta, blocked)
    if blocked and not drag_state and not mouse_down_target then
        return
    end

    -- move: drag or hover. Never consume plain moves - swallowing type-0
    -- events freezes FFXI's cursor tracking.
    if m_type == 0 then
        if drag_state then
            drag_state.panel:pos(x - drag_state.dx, y - drag_state.dy)
            return true
        end
        if mouse_down_target and mouse_down_target.on_drag and mouse_down_pos then
            local dx, dy = x - mouse_down_pos.x, y - mouse_down_pos.y
            if not widget_dragging and (math.abs(dx) > 3 or math.abs(dy) > 3) then
                widget_dragging = true
            end
            if widget_dragging then
                mouse_down_target.on_drag(dx, dy)
                return true
            end
        end
        for _, w in pairs(interactive) do
            if w.set_hovered then
                w:set_hovered(w:hover(x, y))
            end
        end
        return false
    end

    -- left down: arm a widget, or start a title drag. Overlapping widgets:
    -- the smallest hit area wins (a switch on a clickable bar beats the bar;
    -- text buttons have no _w/_h and always win over boxes).
    if m_type == 1 then
        local best, best_area
        for _, w in pairs(interactive) do
            if (w.on_click or w.on_drag) and w:hover(x, y) then
                local area = (w._w and w._h) and (w._w * w._h) or 0
                if not best or area < best_area then
                    best, best_area = w, area
                end
            end
        end
        if best then
            mouse_down_target = best
            mouse_down_pos = {x = x, y = y}
            widget_dragging = false
            return true
        end
        for _, p in pairs(all_panels) do
            if p:hover_title(x, y) then
                drag_state = {panel = p, dx = x - p._x, dy = y - p._y}
                return true
            end
        end
        if over_any_panel(x, y) then
            return true
        end
        return
    end

    -- left up: finish drag, or fire the armed widget
    if m_type == 2 then
        if drag_state then
            local p = drag_state.panel
            drag_state = nil
            if p.on_move then
                p.on_move(p._x, p._y)
            end
            return true
        end
        if mouse_down_target then
            local w = mouse_down_target
            mouse_down_target = nil
            mouse_down_pos = nil
            if widget_dragging then
                widget_dragging = false
                if w.on_drag_end then
                    w.on_drag_end()
                end
                return true
            end
            if w.on_click and w:hover(x, y) then
                w.on_click()
                return true
            end
            if over_any_panel(x, y) then
                return true
            end
            return
        end
        if over_any_panel(x, y) then
            return true
        end
        return
    end

    -- other buttons: dispatch right-click release, block the rest over panels
    if m_type == 3 or m_type == 4 or m_type == 5 then
        if m_type == 4 then
            for _, w in pairs(interactive) do
                if w.on_rclick and w:hover(x, y) then
                    w.on_rclick()
                    return true
                end
            end
        end
        if over_any_panel(x, y) then
            return true
        end
        return
    end

    -- scroll wheel
    if m_type == 10 then
        for _, w in pairs(interactive) do
            if w.on_scroll and w:hover(x, y) then
                w.on_scroll(delta)
                return true
            end
        end
        if over_any_panel(x, y) then
            return true
        end
    end
end)

-- ========================================================================
-- Cleanup
-- ========================================================================

windower.register_event('unload', function()
    -- drop our taskbar entry; harmless no-op when the dock is not loaded
    dock_send('bye ' .. dock.addon)
end)

function slate.cleanup()
    local panels = {}
    for _, p in pairs(all_panels) do
        panels[#panels + 1] = p
    end
    for _, p in ipairs(panels) do
        p:destroy()
    end
    local rest = {}
    for _, w in pairs(all_widgets) do
        rest[#rest + 1] = w
    end
    for _, w in ipairs(rest) do
        if w.destroy then
            w:destroy()
        end
    end
end

return slate
