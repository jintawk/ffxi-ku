--[[
    Mythril - FFXI-native-look UI library for jintawk addons.

    Renders addon HUDs so they read as part of the game's own interface:
    the navy gradient window body with faint scanline stripes, the rounded
    silver-lavender frame, white outlined body text, cyan section headers,
    yellow highlight. Palette sampled from the game's real windows; frame
    textures are original, generated art (see mythril-assets/gen_assets.ps1).

    Same rendering primitives as slate (texts + images), different chrome:
    a Window is 10 image prims - gradient body (stretched), stripe overlay
    (tiled), 4 edge strips, 4 corners - plus a title drawn ON the top border
    line, the way the game titles its windows.

    Widget set:
      Window   framed native window: title, drag-anywhere, children
               (alias: Panel, slate-compatible constructor options)
      Label    outlined text
      Header   cyan section label
      Divider  embossed bevel rule (dark line over light line)
      Rect     plain tinted quad
      HitBox   invisible scroll/click/hover region
      Button   pill-gradient clickable (the game's menu-bar affordance),
               or plain outlined text when plain=true (slate.Button look)
      Toggle   two-state pill (on/off)
      Bar      recessed gauge with a state-colour fill (slate.Bar API)
      IconButton  drawn minus/plus glyph button (slate.IconButton API)

    Coordinates are DESIGN UNITS scaled by set_scale(), except Window pos
    (raw screen pixels, persists to settings). API mirrors slate where the
    widgets overlap, so a slate addon ports with mostly s/slate/mythril/.
    No dock protocol. Windows are static by default; pass minimizable=true
    (or an on_minimize callback) to make the title itself an opt-in
    collapse-to-title control - click the title to fold/unfold, and it
    highlights on hover to hint at this.

    ASSETS: this shared copy resolves its textures from
    windower.windower_path .. 'addons/libs/mythril-assets/' so any addon can
    require it without bundling art. An addon that ships its own textures can
    call mythril.set_assets_path(dir) BEFORE creating any widgets.

    Copyright (c) 2026, jintawk
    BSD 3-clause license.
]]

local texts = require('texts')
local images = require('images')

local mythril = {}
mythril.version = '0.5.0'

-- ========================================================================
-- Theme: palette sampled from the game's own windows (4K screenshots)
-- ========================================================================

-- {r, g, b, a} for quads, first three for text colors
mythril.color = {
    -- text
    title      = {240, 240, 240, 255},
    text       = {240, 240, 240, 255},
    text_dim   = {170, 175, 190, 255},
    text_faint = {120, 126, 145, 255},
    header     = {0, 212, 255, 255},      -- the game's system cyan
    accent     = {255, 220, 90, 255},     -- menu selection yellow
    ok         = {140, 255, 0, 255},      -- item/drop green from the chat log
    warn       = {255, 160, 70, 255},
    bad        = {255, 96, 96, 255},
    disabled   = {130, 136, 150, 255},
    -- row backgrounds: translucent washes for list rows
    row_hover  = {255, 220, 90, 40},      -- faint selection-yellow, on hover
    row_active = {120, 150, 255, 46},     -- faint blue lift for a live row
    -- bars / gauges
    bar_track    = {12, 10, 30, 220},     -- recessed well behind a Bar fill
    bar_text     = {12, 12, 20, 255},     -- dark text over a bright fill
    track_off_hl = {96, 102, 122, 255},   -- muted fill for a paused/disabled bar
    -- chrome
    rule_dark  = {10, 8, 30, 180},        -- divider bevel: dark then light
    rule_light = {190, 195, 230, 70},
}

mythril.font = {
    main = 'Arial',     -- what the game (and trust) effectively read as
    mono = 'Consolas',
}

-- text outline, the load-bearing part of the native text look
mythril.stroke = {width = 2, alpha = 200}

mythril.TITLE_H = 14    -- content top inset; the title overlaps the border
mythril.PAD = 10

-- body translucency, like the game's windows over scenery
local BODY_ALPHA = 235

-- frame geometry in design units. Corners are square joint tiles the same
-- thickness as the edges - the game's 2002 UI has no rounding anywhere.
local FRAME_EDGE = 3        -- edge strip / corner tile thickness
local FRAME_OUT = 1         -- how far the frame outsets past the body rect

-- shared asset directory (overridable before any widget is built)
local assets_dir = windower.windower_path .. 'addons/libs/mythril-assets/'

function mythril.set_assets_path(dir)
    assets_dir = dir
end

function mythril.assets_path()
    return assets_dir
end

-- ========================================================================
-- Scale
-- ========================================================================

local scale = 1.0
local all_widgets = {}
local all_windows = {}

function mythril.s(px)
    return math.floor(px * scale + 0.5)
end

local S = mythril.s

function mythril.scale()
    return scale
end

function mythril.set_scale(new_scale)
    scale = math.max(0.5, math.min(3, tonumber(new_scale) or 1))
    for _, w in pairs(all_widgets) do
        if w._apply_scale then
            w:_apply_scale()
        end
    end
    for _, p in pairs(all_windows) do
        p:_layout()
    end
    if mythril.on_scale_change then
        mythril.on_scale_change(scale)
    end
end

-- ========================================================================
-- Internals
-- ========================================================================

local widget_counter = 0
local function next_id(prefix)
    widget_counter = widget_counter + 1
    return prefix .. '_' .. widget_counter
end

local interactive = {}

local function register(w)
    all_widgets[w._id] = w
end

local function unregister(w)
    all_widgets[w._id] = nil
    interactive[w._id] = nil
end

-- plain tinted quad
local function new_quad(color, w, h)
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

-- textured quad: stretched by default, tiled when repeats are given
local function new_tex(file, w, h, alpha)
    return images.new({
        pos = {x = -10000, y = -10000},
        size = {width = w or 10, height = h or 10},
        color = {red = 255, green = 255, blue = 255, alpha = alpha or 255},
        visible = false,
        draggable = false,
        texture = {path = assets_dir .. file, fit = false},
        repeatable = {x = 1, y = 1},
    })
end

local function new_text(str, font, size, bold, color, italic)
    local t = texts.new(str or '', {
        pos = {x = -10000, y = -10000},
        text = {
            font = font,
            size = size,
            red = color[1], green = color[2], blue = color[3],
            alpha = color[4] or 255,
            stroke = {
                width = mythril.stroke.width,
                alpha = mythril.stroke.alpha,
                red = 0, green = 0, blue = 0,
            },
        },
        bg = {visible = false},
        flags = {draggable = false, bold = bold or false, italic = italic or false},
        padding = 0,
    })
    t:hide()
    return t
end

local function in_box(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- rough text width when texts:extents() is not yet valid (before first render)
local function estimate_width(str, size)
    return math.floor(#(str or '') * size * 0.55)
end

-- ========================================================================
-- Rect
-- ========================================================================

local Rect = {}
Rect.__index = Rect

function mythril.Rect(opts)
    local self = setmetatable({}, Rect)
    opts = opts or {}
    self._id = next_id('rect')
    self._w = opts.w or 10
    self._h = opts.h or 10
    self._color = opts.color or mythril.color.rule_dark
    self._x, self._y = -10000, -10000
    self._visible = false
    self._img = new_quad(self._color, S(self._w), S(self._h))
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
    self._img:color(c[1], c[2], c[3])
    self._img:alpha(c[4] or 255)
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
-- Divider - embossed bevel rule: 1px dark line, 1px light line under it
-- ========================================================================

local Divider = {}
Divider.__index = Divider

function mythril.Divider(opts)
    local self = setmetatable({}, Divider)
    opts = opts or {}
    self._id = next_id('div')
    self._w = opts.w or 100
    self._x, self._y = -10000, -10000
    self._visible = false
    self._dark = new_quad(mythril.color.rule_dark, S(self._w), math.max(1, S(1)))
    self._light = new_quad(mythril.color.rule_light, S(self._w), math.max(1, S(1)))
    register(self)
    return self
end

function Divider:pos(x, y)
    self._x, self._y = x, y
    self._dark:pos(x, y)
    self._light:pos(x, y + math.max(1, S(1)))
end

function Divider:show()
    self._visible = true
    self._dark:show()
    self._light:show()
end

function Divider:hide()
    self._visible = false
    self._dark:hide()
    self._light:hide()
end

function Divider:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Divider:_apply_scale()
    local t = math.max(1, S(1))
    self._dark:size(S(self._w), t)
    self._light:size(S(self._w), t)
    self:pos(self._x, self._y)
end

function Divider:destroy()
    unregister(self)
    self._dark:destroy()
    self._light:destroy()
end

-- ========================================================================
-- Label
-- ========================================================================

local Label = {}
Label.__index = Label

function mythril.Label(opts)
    local self = setmetatable({}, Label)
    opts = opts or {}
    self._id = next_id('label')
    self._base_size = opts.size or 10
    self._color = opts.color or mythril.color.text
    self._visible = false
    self._last = nil
    self._text = new_text(opts.text or '', opts.font or mythril.font.main,
        math.max(6, S(self._base_size)), opts.bold or false, self._color,
        opts.italic or false)
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

-- content-based hit test via the text plugin (valid once shown + positioned);
-- lets a plain Button size its hover region to the text, like slate.Button
function Label:hover(x, y)
    return self._visible and self._text:hover(x, y) or false
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
-- Header - cyan section label, the game's system-message color
-- ========================================================================

function mythril.Header(opts)
    opts = opts or {}
    opts.color = opts.color or mythril.color.header
    return mythril.Label(opts)
end

-- ========================================================================
-- HitBox - invisible interactive region (scroll/click/hover semantics)
-- ========================================================================

local HitBox = {}
HitBox.__index = HitBox

function mythril.HitBox(opts)
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
-- Button - two forms sharing one API:
--   default  pill-gradient clickable (the game's menu-bar affordance)
--   plain    just outlined text (opts.plain = true): no pill, hover turns the
--            text yellow, :color() sets the resting color, and the hit test is
--            content-sized. This is slate.Button's look, so a slate addon ports
--            its text buttons with s/slate/mythril/ plus plain = true.
-- Text goes yellow on hover, its normal color otherwise, dim when disabled.
-- ========================================================================

local Button = {}
Button.__index = Button

function mythril.Button(opts)
    local self = setmetatable({}, Button)
    opts = opts or {}
    self._id = next_id('btn')
    self._plain = opts.plain and true or false
    self._w = opts.w or 60
    self._h = opts.h or 16
    self._x, self._y = -10000, -10000
    self._visible = false
    self._hovered = false
    self._enabled = opts.enabled ~= false
    self._base_size = opts.size or 9
    self._label_text = opts.text or ''
    self._col_normal = opts.color or mythril.color.text
    self._col_hover = opts.hover_color or mythril.color.accent
    self._col_disabled = mythril.color.disabled
    self.on_click = opts.on_click
    if not self._plain then
        self._pill = new_tex('pill.png', S(self._w), S(self._h))
    end
    -- pill labels are always bold; plain labels follow opts.bold (bold by
    -- default, matching slate.Button) so ported text buttons look the same
    local bold = self._plain and (opts.bold ~= false) or true
    self._label = mythril.Label({
        text = self._label_text, size = self._base_size,
        bold = bold, color = self._col_normal,
    })
    register(self)
    interactive[self._id] = self
    return self
end

function Button:_recolor()
    if not self._enabled then
        self._label:color(self._col_disabled)
        if self._pill then self._pill:alpha(120) end
    elseif self._hovered then
        self._label:color(self._col_hover)
        if self._pill then self._pill:alpha(255) end
    else
        self._label:color(self._col_normal)
        if self._pill then self._pill:alpha(230) end
    end
end

-- center the label in the pill (extents fallback until first render); no-op
-- for a plain button, whose label sits at the button's own position
function Button:_center_label()
    if not self._pill then return end
    local tw = self._label:extents()
    if not tw or tw <= 0 then
        tw = estimate_width(self._label_text, S(self._base_size))
    end
    local th = S(self._base_size) + S(3)
    local lx = self._x + math.floor((S(self._w) - tw) / 2)
    local ly = self._y + math.floor((S(self._h) - th) / 2)
    self._label:pos(lx, ly)
end

function Button:pos(x, y)
    self._x, self._y = x, y
    if self._pill then
        self._pill:pos(x, y)
        self:_center_label()
    else
        self._label:pos(x, y)
    end
end

function Button:size(w, h)
    self._w, self._h = w, h
    if self._pill then
        self._pill:size(S(w), S(h))
        self:_center_label()
    end
end

function Button:text(str)
    if str ~= nil and str ~= self._label_text then
        self._label_text = str
        self._label:text(str)
        self:_center_label()
    end
    return self._label_text
end

-- set the resting color; applies at once unless we are currently showing the
-- hover color. slate.Button parity for addons that recolor text buttons each frame
function Button:color(c)
    self._col_normal = c
    if not (self._hovered and self._enabled) then
        self:_recolor()
    end
end

function Button:extents()
    return self._label:extents()
end

function Button:enable(v)
    self._enabled = v and true or false
    if not self._enabled then self._hovered = false end
    self:_recolor()
    return self._enabled
end

function Button:hover(x, y)
    if not self._visible or not self._enabled then return false end
    if self._plain then
        return self._label:hover(x, y)
    end
    return in_box(x, y, self._x, self._y, S(self._w), S(self._h))
end

function Button:set_hovered(h)
    if h ~= self._hovered then
        self._hovered = h
        self:_recolor()
    end
end

function Button:show()
    self._visible = true
    if self._pill then self._pill:show() end
    self._label:show()
    self:_recolor()
end

function Button:hide()
    self._visible = false
    self._hovered = false
    if self._pill then self._pill:hide() end
    self._label:hide()
end

function Button:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Button:_apply_scale()
    if self._pill then
        self._pill:size(S(self._w), S(self._h))
        self:_center_label()
    end
end

function Button:destroy()
    unregister(self)
    if self._pill then self._pill:destroy() end
    self._label:destroy()
end

-- ========================================================================
-- Toggle - two-state pill. Shows its label always; pill dims and text goes
-- faint when off. Fires on_change(new_state) on click.
-- ========================================================================

function mythril.Toggle(opts)
    opts = opts or {}
    local state = opts.state and true or false
    local on_change = opts.on_change
    local on_col = opts.on_color or mythril.color.ok
    local off_col = opts.off_color or mythril.color.disabled
    local btn = mythril.Button({
        text = opts.text or '', w = opts.w or 40, h = opts.h or 16,
        size = opts.size or 9,
        color = state and on_col or off_col,
        hover_color = mythril.color.accent,
    })
    btn._toggle_state = state
    btn._on_col = on_col
    btn._off_col = off_col
    btn._pill:alpha(state and 230 or 110)
    -- override recolor so the resting color tracks state, not just hover
    function btn:_recolor()
        if self._hovered and self._enabled then
            self._label:color(self._col_hover)
            self._pill:alpha(255)
        else
            self._label:color(self._toggle_state and self._on_col or self._off_col)
            self._pill:alpha(self._toggle_state and 230 or 110)
        end
    end
    function btn:get() return self._toggle_state end
    function btn:set(v)
        self._toggle_state = v and true or false
        self:_recolor()
    end
    btn.on_click = function()
        btn._toggle_state = not btn._toggle_state
        btn:_recolor()
        if on_change then on_change(btn._toggle_state) end
    end
    return btn
end

-- ========================================================================
-- Bar - a recessed gauge: a soft silver seat, a dark well, a solid
-- state-colour fill with a 1px brighter top highlight, and an optional
-- centred text overlay. Mirrors slate.Bar's API (set(frac, text, fill_color))
-- so a slate addon ports its bars with s/slate/mythril/.
-- ========================================================================

local Bar = {}
Bar.__index = Bar

local BAR_SEAT = {90, 226, 227, 242}    -- soft silver, like the window edges

local function lighten(c, amt)
    return {math.min(255, c[1] + amt), math.min(255, c[2] + amt),
        math.min(255, c[3] + amt), c[4] or 255}
end

function mythril.Bar(opts)
    local self = setmetatable({}, Bar)
    opts = opts or {}
    self._id = next_id('bar')
    self._w = opts.w or 100
    self._h = opts.h or 12
    self._frac = 0
    self._visible = false
    self._x, self._y = -10000, -10000
    self._fill_color = opts.fill_color or mythril.color.ok
    -- creation order is draw order: seat under well under fill under highlight
    self._seat = new_quad(BAR_SEAT, S(self._w) + 2, S(self._h) + 2)
    self._track = new_quad(opts.track_color or mythril.color.bar_track, S(self._w), S(self._h))
    self._fill = new_quad(self._fill_color, 0, S(self._h))
    self._hl = new_quad(lighten(self._fill_color, 45), 0, math.max(1, S(1)))
    self._label = nil
    if opts.text ~= false then
        self._label_size = opts.text_size or 8
        self._label = new_text('', opts.font or mythril.font.main,
            math.max(6, S(self._label_size)), true, opts.text_color or mythril.color.bar_text)
    end
    register(self)
    return self
end

function Bar:pos(x, y)
    self._x, self._y = x, y
    self._seat:pos(x - 1, y - 1)
    self._track:pos(x, y)
    self._fill:pos(x, y)
    self._hl:pos(x, y)
    if self._label then
        self._label:pos(x + S(4), y + math.floor((S(self._h) - S(self._label_size) - S(4)) / 2))
    end
end

function Bar:set(frac, text, fill_color)
    self._frac = math.max(0, math.min(1, frac or 0))
    if fill_color and fill_color ~= self._fill_color then
        self._fill_color = fill_color
        self._fill:color(fill_color[1], fill_color[2], fill_color[3])
        self._fill:alpha(fill_color[4] or 255)
        local hl = lighten(fill_color, 45)
        self._hl:color(hl[1], hl[2], hl[3])
        self._hl:alpha(hl[4])
    end
    local fw = math.floor(S(self._w) * self._frac)
    if self._frac > 0 then fw = math.max(1, fw) end
    self._fill:size(fw, S(self._h))
    self._hl:size(fw, math.max(1, S(1)))
    if self._label and text then
        self._label:text(text)
    end
end

function Bar:size(w, h)
    self._w, self._h = w, h or self._h
    self._seat:size(S(self._w) + 2, S(self._h) + 2)
    self._track:size(S(self._w), S(self._h))
    self:set(self._frac)
end

function Bar:show()
    self._visible = true
    self._seat:show()
    self._track:show()
    self._fill:show()
    self._hl:show()
    if self._label then self._label:show() end
end

function Bar:hide()
    self._visible = false
    self._seat:hide()
    self._track:hide()
    self._fill:hide()
    self._hl:hide()
    if self._label then self._label:hide() end
end

function Bar:visible(v)
    if v ~= nil then
        if v then self:show() else self:hide() end
    end
    return self._visible
end

function Bar:_apply_scale()
    self._seat:size(S(self._w) + 2, S(self._h) + 2)
    self._track:size(S(self._w), S(self._h))
    local fw = math.floor(S(self._w) * self._frac)
    if self._frac > 0 then fw = math.max(1, fw) end
    self._fill:size(fw, S(self._h))
    self._hl:size(fw, math.max(1, S(1)))
    if self._label then
        self._label:size(math.max(6, S(self._label_size)))
    end
end

function Bar:destroy()
    unregister(self)
    self._seat:destroy()
    self._track:destroy()
    self._fill:destroy()
    self._hl:destroy()
    if self._label then self._label:destroy() end
end

-- ========================================================================
-- IconButton - a drawn minus/plus glyph (no texture), with a faint yellow
-- row-hover wash. Mirrors slate.IconButton's API (kind, on_click); mythril
-- uses it for numeric steppers.
-- ========================================================================

local IconButton = {}
IconButton.__index = IconButton

function mythril.IconButton(opts)
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
    self._bg = new_quad(mythril.color.row_hover, S(self._w), S(self._h))
    self._bg:alpha(0)
    -- a horizontal stroke (minus) and a vertical one (adds the plus)
    self._stroke_h = new_quad(mythril.color.text, S(8), math.max(1, S(2)))
    self._stroke_v = new_quad(mythril.color.text, math.max(1, S(2)), S(8))
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
        self._bg:alpha(h and mythril.color.row_hover[4] or 0)
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
-- Window - the native-look frame
-- ========================================================================

local Window = {}
Window.__index = Window

function mythril.Window(opts)
    local self = setmetatable({}, Window)
    opts = opts or {}
    self._id = next_id('window')
    self._x = opts.x or 200
    self._y = opts.y or 200
    self._w = opts.w or 240
    self._content_h = opts.content_h or 100
    self._title_text = opts.title or (_addon and _addon.name or 'Window')
    self._shown = false
    self._children = {}                  -- {widget=, ox=, oy=}
    self.on_move = opts.on_move          -- (x, y) after drag ends
    -- () -> x, y  settings-backed position, re-applied after login (config
    -- merges the character section in after panels are built at 'load')
    self._pos_source = opts.pos_source

    -- chrome, in draw order: body gradient, stripe overlay, frame. The top
    -- border has two forms: one full strip (untitled), or a pair of strips
    -- whose inner ends fade out under a centered title, like the game's own
    -- window titles.
    self._body = new_tex('body.png', 10, 10, BODY_ALPHA)
    self._stripes = new_tex('stripes.png', 10, 10)
    self._frame = {
        top = new_tex('edge_top.png', 10, 10),
        top_l = new_tex('edge_top_l.png', 10, 10),
        top_r = new_tex('edge_top_r.png', 10, 10),
        bottom = new_tex('edge_bottom.png', 10, 10),
        left = new_tex('edge_left.png', 10, 10),
        right = new_tex('edge_right.png', 10, 10),
        tl = new_tex('corner_tl.png', 10, 10),
        tr = new_tex('corner_tr.png', 10, 10),
        bl = new_tex('corner_bl.png', 10, 10),
        br = new_tex('corner_br.png', 10, 10),
    }
    self._title = mythril.Label({
        text = self._title_text,
        size = 10,
        bold = true,
        italic = true,
        color = mythril.color.title,
    })
    -- the text plugin reports real title extents only after its first render;
    -- until then _title_width uses an estimate. _schedule_settle re-lays out
    -- once extents are live so the centered title/hitbox don't jump on first use.
    self._title_settled = false

    -- opt-in minimize: the title itself is the control. Clicking it collapses
    -- the window to its title bar (and restores); the title highlights on
    -- hover to hint at this. On when the caller asks (minimizable=true) or
    -- supplies an on_minimize callback (slate compat).
    self._minimizable = opts.minimizable or (opts.on_minimize ~= nil)
    self._minimized = self._minimizable and (opts.minimized and true or false) or false
    self.on_minimize = opts.on_minimize
    self._title_dim = false
    self._title_hovered = false
    if self._minimizable then
        self._title_hit = mythril.HitBox({
            w = 20, h = 14,
            on_click = function() self:toggle_minimize() end,
            on_hover = function(h) self._title_hovered = h; self:_recolor_title() end,
        })
        self:_size_title_hit()
    end

    all_windows[self._id] = self
    register(self)
    self:_layout()
    return self
end

-- slate-compatible alias; extra slate options (master, minimized, ...) are
-- accepted and ignored - native windows don't minimize
mythril.Panel = mythril.Window

-- width of the title text in pixels; texts:extents() with a crude estimate
-- as fallback (extents can read 0 before the text plugin first renders)
function Window:_title_width()
    if not self._title_text or self._title_text == '' then
        self._title_settled = true
        return 0
    end
    local ew = self._title:extents()
    if ew and ew > 0 then
        self._title_settled = true
        return ew
    end
    return math.floor(#self._title_text * S(10) * 0.62)
end

function Window:_layout()
    local x, y = self._x, self._y
    local w = S(self._w)
    local ch = self._minimized and 0 or self._content_h
    local h = S(mythril.TITLE_H) + S(ch)
    local o = math.max(1, S(FRAME_OUT))
    local et = math.max(2, S(FRAME_EDGE))
    local cs = et

    self._body:pos(x, y)
    self._body:size(w, h)

    self._stripes:pos(x, y)
    self._stripes:size(w, h)
    -- tile the 4px stripe texture; fractional repeats are fine
    self._stripes:repeat_xy(w / 4, h / 4)

    local f = self._frame
    f.bottom:pos(x - o + cs, y + h + o - et)
    f.bottom:size(w + 2 * o - 2 * cs, et)
    f.left:pos(x - o, y - o + cs)
    f.left:size(et, h + 2 * o - 2 * cs)
    f.right:pos(x + w + o - et, y - o + cs)
    f.right:size(et, h + 2 * o - 2 * cs)
    f.tl:pos(x - o, y - o)
    f.tl:size(cs, cs)
    f.tr:pos(x + w + o - cs, y - o)
    f.tr:size(cs, cs)
    f.bl:pos(x - o, y + h + o - cs)
    f.bl:size(cs, cs)
    f.br:pos(x + w + o - cs, y + h + o - cs)
    f.br:size(cs, cs)

    -- top border: full strip when untitled; split around a centered title
    -- with the inner ends fading out (the fade is baked into the textures)
    local tw = self:_title_width()
    local x0 = x - o + cs
    local x1 = x + w + o - cs
    self._titled = tw > 0
    if self._titled then
        local pad = S(5)
        local lx1 = math.floor(x + (w - tw) / 2) - pad
        local rx0 = math.ceil(x + (w + tw) / 2) + pad
        -- never let the segments vanish on a very long title
        lx1 = math.max(lx1, x0 + S(10))
        rx0 = math.min(rx0, x1 - S(10))
        f.top_l:pos(x0, y - o)
        f.top_l:size(lx1 - x0, et)
        f.top_r:pos(rx0, y - o)
        f.top_r:size(x1 - rx0, et)
        self._title:pos(math.floor(x + (w - tw) / 2), y - S(8))
        if self._minimizable and self._title_hit then
            self._title_hit:pos(math.floor(x + (w - tw) / 2) - S(3), y - S(9))
        end
    else
        f.top:pos(x0, y - o)
        f.top:size(x1 - x0, et)
    end
    if self._shown then
        f.top:visible(not self._titled)
        f.top_l:visible(self._titled)
        f.top_r:visible(self._titled)
    end

    for _, child in ipairs(self._children) do
        child.widget:pos(x + S(child.ox), y + S(mythril.TITLE_H) + S(child.oy))
    end
end

function Window:pos(x, y)
    self._x, self._y = x, y
    self:_layout()
end

function Window:get_pos()
    return self._x, self._y
end

function Window:width()
    return self._w
end

function Window:set_width(w)
    self._w = w
    self:_layout()
end

function Window:content_height(h)
    if h and h ~= self._content_h then
        self._content_h = h
        self:_layout()
    end
    return self._content_h
end

-- Add a child at a content-relative offset in design units. Creation order
-- is draw order for image-backed widgets: build the window first.
function Window:add(widget, ox, oy)
    self._children[#self._children + 1] = {widget = widget, ox = ox or 0, oy = oy or 0}
    widget:pos(self._x + S(ox or 0), self._y + S(mythril.TITLE_H) + S(oy or 0))
    return widget
end

function Window:place(widget, ox, oy)
    for _, child in ipairs(self._children) do
        if child.widget == widget then
            child.ox, child.oy = ox, oy
            widget:pos(self._x + S(ox), self._y + S(mythril.TITLE_H) + S(oy))
            return
        end
    end
end

function Window:title(text)
    if text then
        self._title_text = text
        self._title:text(text)
        self:_size_title_hit()
        self:_layout()
    end
    return self._title_text
end

-- opt-in minimize: collapse to the title bar. minimize(true/false) sets the
-- state, toggle_minimize() flips it. No-ops on a non-minimizable window.
function Window:minimize(min)
    if not self._minimizable then return end
    min = min and true or false
    self._minimized = min
    self:_layout()
    if self._shown then
        for _, child in ipairs(self._children) do
            if min then child.widget:hide() else child.widget:show() end
        end
    end
    if self.on_minimize then self.on_minimize(min) end
end

function Window:toggle_minimize()
    self:minimize(not self._minimized)
end

function Window:is_minimized()
    return self._minimized
end

-- dim the title (e.g. to reflect a master-off state) without touching text
function Window:title_dim(dim)
    self._title_dim = dim and true or false
    self:_recolor_title()
end

-- title color reflects, in priority: minimize-hover hint, then dim, then base
function Window:_recolor_title()
    local c
    if self._minimizable and self._title_hovered then
        c = mythril.color.accent
    elseif self._title_dim then
        c = mythril.color.text_faint
    else
        c = mythril.color.title
    end
    self._title:color(c)
end

-- size the clickable title region to roughly cover the title text (design
-- units; the hover test scales it). Re-run whenever the title text changes.
function Window:_size_title_hit()
    if not self._title_hit then return end
    local dw = math.max(12, math.floor(#(self._title_text or '') * 10 * 0.62) + 6)
    self._title_hit:size(dw, 14)
end

-- After the window is shown, re-layout a few times until the text plugin
-- reports real title extents, so the centered title settles at load instead
-- of jumping the first time something re-lays-out (e.g. a minimize click).
function Window:_schedule_settle()
    if self._title_settled then return end
    if not (coroutine and coroutine.schedule) then return end
    local win = self
    local function resettle(tries)
        if not all_windows[win._id] or not win._shown then return end
        win:_layout()
        if not win._title_settled and tries > 0 then
            coroutine.schedule(function() resettle(tries - 1) end, 0.2)
        end
    end
    coroutine.schedule(function() resettle(4) end, 0.1)
end

-- slate compatibility: the master switch lived in the title bar; native
-- windows express master state via title_dim + a row, so these stay no-ops.
function Window:set_master() end
function Window:master() return nil end

function Window:show()
    self._shown = true
    self._body:show()
    self._stripes:show()
    for _, img in pairs(self._frame) do
        img:show()
    end
    -- only one top-border form is ever visible
    self._frame.top:visible(not self._titled)
    self._frame.top_l:visible(self._titled)
    self._frame.top_r:visible(self._titled)
    self._title:show()
    if self._minimizable then
        self._title_hit:show()
        self:_recolor_title()
    end
    for _, child in ipairs(self._children) do
        if self._minimized then child.widget:hide() else child.widget:show() end
    end
    self:_schedule_settle()
end

function Window:hide()
    self._shown = false
    self._dragging = nil
    self._body:hide()
    self._stripes:hide()
    for _, img in pairs(self._frame) do
        img:hide()
    end
    self._title:hide()
    if self._minimizable then
        self._title_hit:hide()
        self._title_hovered = false
    end
    for _, child in ipairs(self._children) do
        child.widget:hide()
    end
end

function Window:visible()
    return self._shown
end

-- hover box includes the title overhang above the frame
function Window:hover(x, y)
    if not self._shown then return false end
    local ch = self._minimized and 0 or self._content_h
    local h = S(mythril.TITLE_H) + S(ch)
    return in_box(x, y, self._x - S(2), self._y - S(10), S(self._w) + S(4), h + S(12))
end

function Window:destroy()
    self._shown = false
    all_windows[self._id] = nil
    unregister(self)
    self._body:destroy()
    self._stripes:destroy()
    for _, img in pairs(self._frame) do
        img:destroy()
    end
    self._title:destroy()
    if self._minimizable then
        self._title_hit:destroy()
    end
    for _, child in ipairs(self._children) do
        if child.widget.destroy then
            child.widget:destroy()
        end
    end
    self._children = {}
end

-- ========================================================================
-- Command stub - no dock protocol; kept so ported slate addons can keep
-- routing their command event through the library
-- ========================================================================

function mythril.handle_command(cmd, ...)
    return false
end

-- slate compatibility: mythril has no dock protocol, so nothing is ever docked
function mythril.dock_available()
    return false
end

-- ========================================================================
-- Mouse dispatch - one handler per addon
-- ========================================================================

local drag_state = nil          -- {window, dx, dy}
local mouse_down_target = nil
local mouse_x, mouse_y = -10000, -10000

function mythril.mouse_pos()
    return mouse_x, mouse_y
end

local function over_any_window(x, y)
    for _, p in pairs(all_windows) do
        if p:hover(x, y) then
            return true
        end
    end
    return false
end

windower.register_event('mouse', function(m_type, x, y, delta, blocked)
    mouse_x, mouse_y = x, y
    if blocked and not drag_state and not mouse_down_target then
        return
    end

    -- move: drag or hover. Never consume plain moves - swallowing type-0
    -- events freezes FFXI's cursor tracking.
    if m_type == 0 then
        if drag_state then
            drag_state.window:pos(x - drag_state.dx, y - drag_state.dy)
            return true
        end
        for _, w in pairs(interactive) do
            if w.set_hovered then
                w:set_hovered(w:hover(x, y))
            end
        end
        return false
    end

    -- left down: arm a widget, else start a window drag from anywhere on it
    if m_type == 1 then
        for _, w in pairs(interactive) do
            if w.on_click and w:hover(x, y) then
                mouse_down_target = w
                return true
            end
        end
        for _, p in pairs(all_windows) do
            if p:hover(x, y) then
                drag_state = {window = p, dx = x - p._x, dy = y - p._y}
                return true
            end
        end
        return
    end

    -- left up: finish drag, or fire the armed widget
    if m_type == 2 then
        if drag_state then
            local p = drag_state.window
            drag_state = nil
            if p.on_move then
                p.on_move(p._x, p._y)
            end
            return true
        end
        if mouse_down_target then
            local w = mouse_down_target
            mouse_down_target = nil
            if w.on_click and w:hover(x, y) then
                w.on_click()
                return true
            end
        end
        if over_any_window(x, y) then
            return true
        end
        return
    end

    -- other buttons: dispatch right-click release, block the rest over windows
    if m_type == 3 or m_type == 4 or m_type == 5 then
        if m_type == 4 then
            for _, w in pairs(interactive) do
                if w.on_rclick and w:hover(x, y) then
                    w.on_rclick()
                    return true
                end
            end
        end
        if over_any_window(x, y) then
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
        if over_any_window(x, y) then
            return true
        end
    end
end)

-- ========================================================================
-- Login re-position (see slate: config merges char settings after 'load')
-- ========================================================================

windower.register_event('login', function()
    coroutine.schedule(function()
        for _, p in pairs(all_windows) do
            if p._pos_source then
                local x, y = p._pos_source()
                if x and y then
                    p:pos(x, y)
                end
            end
        end
    end, 0)
end)

-- ========================================================================
-- Cleanup
-- ========================================================================

function mythril.cleanup()
    local windows = {}
    for _, p in pairs(all_windows) do
        windows[#windows + 1] = p
    end
    for _, p in ipairs(windows) do
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

return mythril
