require "List"
require "const"
config = require('config')
-- shared mythril UI lib when present; the bundled copy makes a standalone clone work
local mythril_ok
mythril_ok, mythril = pcall(require, 'mythril')
if not mythril_ok then
	mythril = require('mythril_bundled')
end
mythril.set_assets_path(windower.addon_path .. 'assets/')

defaults = {
	pos = {
		x = 300,
		y = 475,
	},
	ui = {
		scale = 1,
		minimized = false,
	},
}

settings = config.load(defaults)

local UI_W     = 250
local ROW_H    = 18
local FOOTER_H = 16

-- master "Keeping up" switch sits at the top, mirroring Medic's Auto-Cure and
-- fisher's Auto-Fish rows: a bold label with an On/Off value, a divider under
-- it, then the ability list. The active zone restriction (if any) shows in the
-- footer.
local MASTER_Y  = 4
local MASTER_H  = 20
local DIV_Y     = MASTER_Y + MASTER_H
local ROWS_TOP  = DIV_Y + 6
local COL_LABEL = 10
local COL_VALUE = 205

local ui = {
	built = false,
	panel = nil,
	rows = {},        -- pooled: {idx, name, tag} labels per display slot
	master = nil,     -- {bg, label, value, hit} "Keeping up" row
	master_hover = false,
	divider = nil,
	footer = nil,
	hint = nil,
}

local function toggle_pause()
	pause = not pause
	log(pause and 'Paused' or 'Resuming')
	update_gui(ability_list, zone_restriction_name, pause)
end

local function build_ui()
	if ui.built then
		return
	end
	ui.built = true
	mythril.set_scale(tonumber(settings.ui.scale) or 1)

	ui.panel = mythril.Panel({
		x = settings.pos.x,
		y = settings.pos.y,
		pos_source = function() return settings.pos.x, settings.pos.y end,
		w = UI_W,
		content_h = 60,
		title = 'Keeper Upper',
		minimized = settings.ui.minimized,
		on_move = function(x, y)
			settings.pos.x = x
			settings.pos.y = y
			config.save(settings)
		end,
		on_minimize = function(min)
			settings.ui.minimized = min
			config.save(settings)
			update_gui(ability_list, zone_restriction_name, pause)
		end,
	})

	-- master switch: clicking the row pauses/resumes the whole addon. The bg is
	-- a hover wash (shown only while the cursor is over the row).
	ui.master = {
		bg    = mythril.Rect({w = UI_W - 4, h = MASTER_H - 2, color = mythril.color.row_hover}),
		label = mythril.Label({size = 10, bold = true, color = mythril.color.text}),
		value = mythril.Label({size = 10, color = mythril.color.header}),
		hit   = mythril.HitBox({
			w = UI_W, h = MASTER_H,
			on_click = toggle_pause,
			on_hover = function(h) ui.master_hover = h; ui.master.bg:visible(h) end,
		}),
	}
	ui.master.label:text('Keeping up')
	ui.panel:add(ui.master.bg, 2, MASTER_Y)
	ui.panel:add(ui.master.label, COL_LABEL, MASTER_Y + 3)
	ui.panel:add(ui.master.value, COL_VALUE, MASTER_Y + 3)
	ui.panel:add(ui.master.hit, 0, MASTER_Y)

	ui.divider = mythril.Divider({w = UI_W - 20})
	ui.panel:add(ui.divider, 10, DIV_Y)

	ui.footer = mythril.Label({size = 9, font = mythril.font.mono, color = mythril.color.text_dim})
	ui.panel:add(ui.footer, COL_LABEL, 0)

	ui.hint = mythril.Label({size = 10, color = mythril.color.text_faint, text = 'no actions - //ku help'})
	ui.panel:add(ui.hint, COL_LABEL, ROWS_TOP)
end

local function ensure_rows(n)
	for i = #ui.rows + 1, n do
		local row = {
			idx  = mythril.Label({size = 9, font = mythril.font.mono, color = mythril.color.text_faint}),
			name = mythril.Label({size = 10, color = mythril.color.text}),
			tag  = mythril.Label({size = 9, font = mythril.font.mono, color = mythril.color.text_faint}),
		}
		local ry = ROWS_TOP + (i - 1) * ROW_H
		ui.panel:add(row.idx, 10, ry + 1)
		ui.panel:add(row.name, 28, ry)
		ui.panel:add(row.tag, 150, ry + 1)
		ui.rows[i] = row
	end
end

function update_gui(list, zone, pause)
	build_ui()

	local n = list.count
	ensure_rows(n)
	-- empty list still shows the panel, with a hint line where rows would be
	local rows_h = (n > 0 and n or 1) * ROW_H
	local footer_h = zone and FOOTER_H or 0
	ui.panel:content_height(ROWS_TOP + rows_h + 6 + footer_h)

	local slot = 0
	if n > 0 then
		local first = list.first
		local last = list.first + list.count - 1
		for i = first, last do
			local item = list.items[i]
			if item ~= nil then
				slot = slot + 1
				local row = ui.rows[slot]
				local ry = ROWS_TOP + (slot - 1) * ROW_H
				ui.panel:place(row.idx, 10, ry + 1)
				ui.panel:place(row.name, 28, ry)
				ui.panel:place(row.tag, 150, ry + 1)
				row.idx:text(tostring(i))
				row.name:text(item.name)
				row.name:color(pause and mythril.color.disabled or mythril.color.text)
				row.tag:text('(' .. item.type .. '-' .. (item.when or '') .. ')')
			end
		end
	end

	-- master row: On when keeping up, Off when paused (Medic's affordance)
	if pause then
		ui.master.value:text('Off')
		ui.master.value:color(mythril.color.disabled)
	else
		ui.master.value:text('On')
		ui.master.value:color(mythril.color.header)
	end
	ui.panel:place(ui.master.bg, 2, MASTER_Y)
	ui.panel:place(ui.master.label, COL_LABEL, MASTER_Y + 3)
	ui.panel:place(ui.master.value, COL_VALUE, MASTER_Y + 3)
	ui.panel:place(ui.master.hit, 0, MASTER_Y)
	ui.panel:place(ui.divider, 10, DIV_Y)

	-- footer: the active zone restriction, if one is set
	if zone ~= nil then
		ui.footer:text('zone: ' .. zone)
		ui.panel:place(ui.footer, COL_LABEL, ROWS_TOP + rows_h + 4)
	end

	ui.panel:title_dim(pause)
	if not ui.panel:visible() then
		ui.panel:show()
	end

	-- hide pooled rows beyond the current count and re-assert the conditional
	-- children (panel:show() reveals every child, so the hover bg and the
	-- zoneless footer must be hidden back here); leave everything alone while
	-- minimized (the panel manages its own children)
	if not ui.panel:is_minimized() then
		ui.master.bg:visible(ui.master_hover)
		ui.master.label:visible(true)
		ui.master.value:visible(true)
		ui.master.hit:visible(true)
		ui.divider:visible(true)
		ui.footer:visible(zone ~= nil)
		ui.hint:visible(n == 0)
		for i = 1, #ui.rows do
			local v = i <= slot
			ui.rows[i].idx:visible(v)
			ui.rows[i].name:visible(v)
			ui.rows[i].tag:visible(v)
		end
	end
end
